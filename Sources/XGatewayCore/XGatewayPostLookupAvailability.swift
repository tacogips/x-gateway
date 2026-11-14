import Foundation

public enum XGatewayPostLookupStatus: String, Codable, Sendable {
    case available, unavailable, unknown
}

public enum XGatewayPostLookupReason: String, Codable, Sendable {
    case returned, filtered, missing, unknown
    case notFound = "not-found"
    case forbidden
}

/// Availability in this response, never proof of permanent deletion or future access.
public struct XGatewayPostLookupAvailability: Codable, Equatable, Sendable {
    public let postId: String
    public let status: XGatewayPostLookupStatus
    public let reason: XGatewayPostLookupReason

    var projected: [String: Any] { ["postId": postId, "status": status.rawValue, "reason": reason.rawValue] }
}

extension XGatewayResponseProjector {
    static func lookupAvailability(root: [String: Any], posts: [[String: Any]], requestedIDs: [String]) -> [[String: Any]] {
        let returned = Set(posts.compactMap { $0["id"] as? String })
        let providerReturned = Set(((root["data"] as? [[String: Any]]) ?? []).compactMap { $0["id"] as? String })
        let rawErrors = (root["errors"] as? [[String: Any]]) ?? []
        let errorsComplete = rawErrors.count <= 1_000
        let errors = Array(rawErrors.prefix(1_000))
        var seen = Set<String>()
        return requestedIDs.filter { seen.insert($0).inserted }.map { identity in
            let status: XGatewayPostLookupStatus
            let reason: XGatewayPostLookupReason
            if returned.contains(identity) {
                status = .available; reason = .returned
            } else if providerReturned.contains(identity) {
                // The provider returned it, but the gateway's projection omitted it.
                status = .unknown; reason = .filtered
            } else if !errorsComplete {
                status = .unknown; reason = .unknown
            } else {
                let bound = errors.filter { error in
                    guard error["resource_type"] as? String == "tweet" else { return false }
                    if let resourceID = error["resource_id"] as? String { return resourceID == identity }
                    return error["parameter"] as? String == "ids" && error["value"] as? String == identity
                }
                let reasons = bound.map { error -> XGatewayPostLookupReason in
                    guard let type = error["type"] as? String else { return .unknown }
                    if ["https://api.x.com/2/problems/resource-not-found", "https://api.twitter.com/2/problems/resource-not-found"].contains(type) { return .notFound }
                    if ["https://api.x.com/2/problems/not-authorized-for-resource", "https://api.twitter.com/2/problems/not-authorized-for-resource"].contains(type) { return .forbidden }
                    return .unknown
                }
                if let first = reasons.first, first != .unknown, reasons.allSatisfy({ $0 == first }) {
                    status = .unavailable; reason = first
                } else {
                    status = .unknown; reason = bound.isEmpty ? .missing : .unknown
                }
            }
            return XGatewayPostLookupAvailability(postId: identity, status: status, reason: reason).projected
        }
    }
}
