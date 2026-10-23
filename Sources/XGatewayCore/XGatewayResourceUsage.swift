import Foundation
import Crypto

public enum XGatewayResourceKind: String, Sendable {
    case post, user, media, other
}

public struct XGatewayObservedResource: Sendable {
    public let kind: XGatewayResourceKind
    public let idHash: String
    public let utcDay: String

    func jsonObject() -> [String: Any] {
        ["kind": kind.rawValue, "idHash": idHash, "utcDay": utcDay]
    }
}

/// Observations, not an invoice. X owns billing deduplication and discounts.
public struct XGatewayResourceUsageSnapshot: Sendable {
    public let httpResponses: Int
    public let successfulResponses: Int
    public let unclassifiedResources: Int
    public let resources: [XGatewayObservedResource]

    func jsonObject() -> [String: Any] {
        ["version": 1, "basis": "upstream-response", "billingStatus": "not-reported",
         "httpResponses": httpResponses, "successfulResponses": successfulResponses,
         "unclassifiedResources": unclassifiedResources,
         "resources": resources.map { $0.jsonObject() }]
    }
}

/// Records HTTP responses before projection or user-cache enrichment.
final class XGatewayResourceUsage {
    private var httpResponses = 0
    private var successfulResponses = 0
    private var unclassifiedResources = 0
    private var resources: [XGatewayObservedResource] = []
    func markUnknownRequest() { unclassifiedResources += 1 }

    func record(method: String, url: URL, status: Int, payload: Any, at: Date = Date()) {
        httpResponses += 1
        guard (200...299).contains(status) else {
            if payload is NSNull { unclassifiedResources += 1 }
            return
        }
        successfulResponses += 1
        guard method == "GET" else { return }
        guard let object = payload as? [String: Any] else { unclassifiedResources += 1; return }
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        let day = String(formatter.string(from: at).prefix(10))
        let path = url.path
        if path.hasPrefix("/2/usage/") { return }
        let kind: XGatewayResourceKind
        if path == "/2/tweets" || path.hasPrefix("/2/tweets/search/")
            || path.range(of: #"^/2/tweets/[0-9]+$"#, options: .regularExpression) != nil
            || path.hasSuffix("/tweets") || path.hasSuffix("/liked_tweets") || path.hasSuffix("/mentions")
            || path.hasSuffix("/bookmarks") || path.hasSuffix("/timelines/reverse_chronological") {
            kind = .post
        } else if path == "/2/users" || path == "/2/users/me"
            || path.range(of: #"^/2/users/[0-9]+$"#, options: .regularExpression) != nil
            || path.hasPrefix("/2/users/by") || path.hasSuffix("/retweeted_by") || path.hasSuffix("/liking_users")
            || path.hasSuffix("/following") || path.hasSuffix("/followers") {
            kind = .user
        } else {
            kind = .other
        }
        append(object["data"], kind: kind, day: day)
        let includes = object["includes"] as? [String: Any] ?? [:]
        append(includes["tweets"], kind: .post, day: day)
        append(includes["users"], kind: .user, day: day)
        append(includes["media"], kind: .media, day: day)
    }

    private func append(_ value: Any?, kind: XGatewayResourceKind, day: String) {
        let rows = value as? [[String: Any]] ?? (value as? [String: Any]).map { [$0] } ?? []
        for row in rows {
            guard let id = row[kind == .media ? "media_key" : "id"] as? String,
                  !id.isEmpty, id.utf8.count <= 256, resources.count < 100_000 else {
                unclassifiedResources += 1
                continue
            }
            if kind == .other { unclassifiedResources += 1 }
            let hash = SHA256.hash(data: Data((kind.rawValue + ":" + id).utf8)).map { String(format: "%02x", $0) }.joined()
            resources.append(XGatewayObservedResource(kind: kind, idHash: hash, utcDay: day))
        }
    }

    var snapshot: XGatewayResourceUsageSnapshot {
        XGatewayResourceUsageSnapshot(httpResponses: httpResponses, successfulResponses: successfulResponses,
            unclassifiedResources: unclassifiedResources, resources: resources)
    }
}
