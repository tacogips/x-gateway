import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

enum XGatewayStreamEndpoint: String {
    case sample
    case filtered

    var path: String {
        switch self {
        case .sample:
            return "/2/tweets/sample/stream"
        case .filtered:
            return "/2/tweets/search/stream"
        }
    }
}

struct XGatewayStreamOptions {
    let endpoint: XGatewayStreamEndpoint
    let maxEvents: Int
    let durationSeconds: Int
    let reconnect: Bool
}

extension XGatewayLiveExecutor {
    func executeStream(
        options: XGatewayStreamOptions,
        authorization: XGatewayRequestAuthorization,
        eventSink: XGatewayStreamEventSink? = nil
    ) throws -> [String: Any] {
        let startedAt = Date()
        let deadline = startedAt.addingTimeInterval(TimeInterval(options.durationSeconds))
        var events: [Any] = []
        var attempts = 0
        var reconnects = 0
        var lastStatusCode: Int?

        repeat {
            let remaining = deadline.timeIntervalSinceNow
            if remaining <= 0 || events.count >= options.maxEvents {
                break
            }
            let remainingEvents = options.maxEvents - events.count
            let result = try streamAttempt(
                endpoint: options.endpoint,
                authorization: authorization,
                maxEvents: remainingEvents,
                durationSeconds: remaining,
                eventSink: eventSink
            )
            events.append(contentsOf: result.events)
            lastStatusCode = result.statusCode
            if events.count >= options.maxEvents || !options.reconnect {
                break
            }
            attempts += 1
            guard attempts <= transport.retryCount else {
                break
            }
            reconnects += 1
            Thread.sleep(forTimeInterval: reconnectDelay(attempt: attempts))
        } while true

        var payload: [String: Any] = [
            "endpoint": options.endpoint.rawValue,
            "startedAt": ISO8601DateFormatter().string(from: startedAt),
            "endedAt": ISO8601DateFormatter().string(from: Date()),
            "maxEvents": options.maxEvents,
            "durationSeconds": options.durationSeconds,
            "reconnect": options.reconnect,
            "reconnects": reconnects,
            "eventCount": events.count,
            "events": events
        ]
        if let lastStatusCode {
            payload["lastStatusCode"] = lastStatusCode
        }
        return payload
    }

    private func streamAttempt(
        endpoint: XGatewayStreamEndpoint,
        authorization: XGatewayRequestAuthorization,
        maxEvents: Int,
        durationSeconds: TimeInterval,
        eventSink: XGatewayStreamEventSink?
    ) throws -> (events: [Any], statusCode: Int?) {
        let url = try xAPIURL(path: endpoint.path, query: timelineQueryItems([:], includeOwnerMetrics: false))
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        applyAuthorizationHeader(to: &request, method: "GET", url: url, authorization: authorization, signatureParameters: [])

        let delegate = XGatewayStreamCollector(maxEvents: maxEvents, eventSink: eventSink)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = max(1, durationSeconds)
        configuration.timeoutIntervalForResource = max(1, durationSeconds)
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        let task = session.dataTask(with: request)
        delegate.task = task
        task.resume()

        let timeout = DispatchTime.now() + .milliseconds(Int(max(1, durationSeconds) * 1_000) + 1_000)
        if delegate.wait(timeout: timeout) == .timedOut {
            task.cancel()
        }
        session.finishTasksAndInvalidate()

        if let statusCode = delegate.statusCode,
           !(200...299).contains(statusCode) {
            let payload = (try? JSONSerialization.jsonObject(with: Data(delegate.rawBody.utf8), options: []))
                ?? ["rawBody": delegate.rawBody]
            throw mapHTTPError(statusCode: statusCode, payload: payload)
        }
        return (delegate.events, delegate.statusCode)
    }

    private func reconnectDelay(attempt: Int) -> TimeInterval {
        if transport.retryBackoff == "none" {
            return 0
        }
        if transport.retryBackoff == "fixed" {
            return TimeInterval(transport.retryBaseMs) / 1_000
        }
        let exponent = min(attempt, 10)
        let uncapped = transport.retryBaseMs * (1 << exponent)
        let capped = min(uncapped, transport.retryMaxMs)
        return capped == 0 ? 0 : TimeInterval(capped) / 1_000
    }
}

private final class XGatewayStreamCollector: NSObject, URLSessionDataDelegate, URLSessionTaskDelegate {
    private let lock = NSLock()
    private let semaphore = DispatchSemaphore(value: 0)
    private let maxEvents: Int
    private let eventSink: XGatewayStreamEventSink?
    private var buffer = ""
    private var signaled = false

    weak var task: URLSessionDataTask?
    private(set) var events: [Any] = []
    private(set) var statusCode: Int?
    private(set) var rawBody = ""

    init(maxEvents: Int, eventSink: XGatewayStreamEventSink?) {
        self.maxEvents = maxEvents
        self.eventSink = eventSink
    }

    func wait(timeout: DispatchTime) -> DispatchTimeoutResult {
        semaphore.wait(timeout: timeout)
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        if let http = response as? HTTPURLResponse {
            lock.lock()
            statusCode = http.statusCode
            lock.unlock()
        }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard let text = String(data: data, encoding: .utf8) else {
            return
        }
        lock.lock()
        rawBody += text
        buffer += text
        parseCompleteLines()
        let shouldStop = events.count >= maxEvents
        lock.unlock()
        if shouldStop {
            dataTask.cancel()
            signalOnce()
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock()
        if !buffer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parseLine(buffer)
            buffer = ""
        }
        lock.unlock()
        signalOnce()
    }

    private func parseCompleteLines() {
        while let newline = buffer.firstIndex(of: "\n") {
            let line = String(buffer[..<newline])
            buffer = String(buffer[buffer.index(after: newline)...])
            parseLine(line)
            if events.count >= maxEvents {
                return
            }
        }
    }

    private func parseLine(_ line: String) {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let data = trimmed.data(using: .utf8),
              let parsed = try? JSONSerialization.jsonObject(with: data, options: []) else {
            return
        }
        events.append(parsed)
        eventSink?(jsonString(parsed, pretty: false))
    }

    private func signalOnce() {
        lock.lock()
        let shouldSignal = !signaled
        signaled = true
        lock.unlock()
        if shouldSignal {
            semaphore.signal()
        }
    }
}
