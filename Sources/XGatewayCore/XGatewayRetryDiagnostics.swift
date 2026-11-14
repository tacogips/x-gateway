import Foundation

/// Bounded transport evidence for the failed HTTP request, never provider text.
public struct XGatewayRetryDiagnostics: Sendable {
    public enum StopReason: String, Sendable {
        case notStarted = "not-started"
        case nonRetryable = "non-retryable"
        case disabled = "retry-disabled"
        case exhausted = "retry-exhausted"
        case methodNotRetryable = "method-not-retryable"
    }
    public let requestAttempts: Int
    public let retryAttempts: Int
    public let backoffMs: Int
    public let stopReason: StopReason

    static let notStarted = Self(requestAttempts: 0, retryAttempts: 0, backoffMs: 0, stopReason: .notStarted)
}

extension XGatewayRetryPolicy {
    static func perform<T>(
        method: String, transport: TransportSettings,
        sleep: (Int) -> Void = { Thread.sleep(forTimeInterval: Double($0) / 1_000) },
        jitter: () -> Double = { Double.random(in: 0.5...1.0) },
        perform: () throws -> T
    ) throws -> T {
        let limit = automaticRetryCount(forHTTPMethod: method, configuredRetryCount: transport.retryCount)
        var retries = 0
        var backoffMs = 0
        while true {
            do {
                return try perform()
            } catch var error as XGatewayErrorPayload {
                guard error.retryable, retries < limit else {
                    let reason: XGatewayRetryDiagnostics.StopReason
                    if !error.retryable {
                        reason = .nonRetryable
                    } else if method.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() != "GET" {
                        reason = .methodNotRetryable
                    } else if limit == 0 {
                        reason = .disabled
                    } else {
                        reason = .exhausted
                    }
                    error.retryDiagnostics = XGatewayRetryDiagnostics(
                        requestAttempts: retries + 1, retryAttempts: retries, backoffMs: backoffMs, stopReason: reason)
                    throw error
                }
                let delay: Int
                switch transport.retryBackoff {
                case "none": delay = 0
                case "fixed": delay = transport.retryBaseMs
                default:
                    let capped = min(transport.retryBaseMs * (1 << min(retries, 10)), transport.retryMaxMs)
                    delay = Int(Double(capped) * jitter())
                }
                if delay > 0 { sleep(delay) }
                backoffMs += delay
                retries += 1
            }
        }
    }
}
