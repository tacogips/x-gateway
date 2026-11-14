import Foundation

public enum XGatewayPostCoverageStatus: String, Codable, Sendable {
    case available, unknown
}

public enum XGatewayPostCoverageReason: String, Codable, Sendable {
    case returned, missing, unsupported, filtered
    case depthLimit = "depth-limit"
}

/// Availability of provider-declared media metadata, not downloaded or inspected bytes.
public struct XGatewayPostMediaAvailability: Codable, Equatable, Sendable {
    public let mediaKey: String
    public let status: XGatewayPostCoverageStatus
    public let reason: XGatewayPostCoverageReason

    var projected: [String: Any] { ["mediaKey": mediaKey, "status": status.rawValue, "reason": reason.rawValue] }
}

/// Availability within this response's bounded projection, never proof of deletion.
public struct XGatewayPostReferenceAvailability: Codable, Equatable, Sendable {
    public let postId: String
    public let relation: String
    public let status: XGatewayPostCoverageStatus
    public let reason: XGatewayPostCoverageReason

    var projected: [String: Any] {
        ["postId": postId, "relation": relation, "status": status.rawValue, "reason": reason.rawValue]
    }
}

func postCoverage(_ tweet: [String: Any], returnedMediaKeys: Set<String>, includedMediaKeys: Set<String>,
                  projectedReferences: [[String: Any]], includedReferenceIDs: Set<String>, depth: Int) -> [String: Any] {
    let attachments = tweet["attachments"] as? [String: Any]
    let rawMedia = attachments?["media_keys"] as? [Any]
    var mediaComplete = (tweet["attachments"] == nil || attachments != nil)
        && (attachments?["media_keys"] == nil || rawMedia != nil) && (rawMedia?.count ?? 0) <= 100
    var media: [[String: Any]] = []
    var seenMedia = Set<String>()
    for item in (rawMedia ?? []).prefix(100) {
        guard let key = item as? String, key.range(of: "^[A-Za-z0-9_-]{1,128}$", options: .regularExpression) != nil else {
            mediaComplete = false; continue
        }
        guard seenMedia.insert(key).inserted else { continue }
        let available = returnedMediaKeys.contains(key)
        if !available { mediaComplete = false }
        media.append(XGatewayPostMediaAvailability(mediaKey: key, status: available ? .available : .unknown,
            reason: available ? .returned : includedMediaKeys.contains(key) ? .unsupported : .missing).projected)
    }
    let rawReferences = tweet["referenced_tweets"] as? [Any]
    var referenceComplete = (tweet["referenced_tweets"] == nil || rawReferences != nil) && (rawReferences?.count ?? 0) <= 100
    var references: [[String: Any]] = []
    var seenReferences = Set<String>()
    for item in (rawReferences ?? []).prefix(100) {
        guard let row = item as? [String: Any], let identity = row["id"] as? String,
              identity.range(of: "^[0-9]{1,32}$", options: .regularExpression) != nil,
              let relation = row["type"] as? String, ["quoted", "retweeted", "replied_to"].contains(relation) else {
            referenceComplete = false; continue
        }
        guard seenReferences.insert(identity + ":" + relation).inserted else { continue }
        let available = projectedReferences.contains { ($0["id"] as? String) == identity && ($0["relation"] as? String) == relation }
        let reason: XGatewayPostCoverageReason = available ? .returned : depth == 0 ? .depthLimit
            : includedReferenceIDs.contains(identity) ? .filtered : .missing
        if !available { referenceComplete = false }
        references.append(XGatewayPostReferenceAvailability(postId: identity, relation: relation,
            status: available ? .available : .unknown, reason: reason).projected)
    }
    return ["mediaAvailability": media, "mediaCoverageComplete": mediaComplete,
            "referenceAvailability": references, "referenceCoverageComplete": referenceComplete]
}
