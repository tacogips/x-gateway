import Foundation

extension XGatewayResponseProjector {
    public static func space(_ payload: Any) -> [String: Any] {
        return openAPISpace(openAPIDataObject(payload))
    }

    public static func spacePage(_ payload: Any) -> [String: Any] {
        let root = openAPIObject(payload)
        let spaces = ((root["data"] as? [[String: Any]]) ?? []).map(openAPISpace)
        return [
            "spaces": spaces,
            "pageInfo": openAPIPageInfo(root: root, resultCount: spaces.count)
        ]
    }

    public static func streamRulePage(_ payload: Any) -> [String: Any] {
        let root = openAPIObject(payload)
        var projected: [String: Any] = [
            "rules": openAPIStreamRules(root),
            "pageInfo": openAPIPageInfo(root: root, resultCount: openAPIStreamRules(root).count)
        ]
        openAPICopyStreamMeta(root, into: &projected)
        return projected
    }

    public static func streamRuleUpdateResult(_ payload: Any) -> [String: Any] {
        let root = openAPIObject(payload)
        var projected = streamRulePage(payload)
        let errors = ((root["errors"] as? [[String: Any]]) ?? []).map(openAPIStreamRuleError)
        if !errors.isEmpty {
            projected["errors"] = errors
        }
        return projected
    }
}

private func openAPISpace(_ space: [String: Any]) -> [String: Any] {
    var projected: [String: Any] = [
        "id": openAPIStringValue(space["id"])
    ]
    openAPICopyString(space, from: "state", to: "state", into: &projected)
    openAPICopyString(space, from: "title", to: "title", into: &projected)
    openAPICopyString(space, from: "creator_id", to: "creatorId", into: &projected)
    openAPICopyString(space, from: "created_at", to: "createdAt", into: &projected)
    openAPICopyString(space, from: "started_at", to: "startedAt", into: &projected)
    openAPICopyString(space, from: "ended_at", to: "endedAt", into: &projected)
    openAPICopyString(space, from: "scheduled_start", to: "scheduledStart", into: &projected)
    openAPICopyString(space, from: "updated_at", to: "updatedAt", into: &projected)
    openAPICopyString(space, from: "lang", to: "lang", into: &projected)
    openAPICopyStringArray(space, from: "host_ids", to: "hostIds", into: &projected)
    openAPICopyStringArray(space, from: "speaker_ids", to: "speakerIds", into: &projected)
    openAPICopyStringArray(space, from: "invited_user_ids", to: "invitedUserIds", into: &projected)
    openAPICopyStringArray(space, from: "topic_ids", to: "topicIds", into: &projected)
    openAPICopyInt(space, from: "participant_count", to: "participantCount", into: &projected)
    openAPICopyInt(space, from: "subscriber_count", to: "subscriberCount", into: &projected)
    openAPICopyBool(space, from: "is_ticketed", to: "isTicketed", into: &projected)
    return projected
}

private func openAPIObject(_ payload: Any) -> [String: Any] {
    return (payload as? [String: Any]) ?? [:]
}

private func openAPIDataObject(_ payload: Any) -> [String: Any] {
    return openAPIObject(payload)["data"] as? [String: Any] ?? [:]
}

private func openAPIStringValue(_ value: Any?, fallback: String = "") -> String {
    if let value = value as? String {
        return value
    }
    if let value {
        return String(describing: value)
    }
    return fallback
}

private func openAPIIntValue(_ value: Any?, fallback: Int = 0) -> Int {
    if let value = value as? Int {
        return value
    }
    if let value = value as? Double {
        return Int(value)
    }
    if let value = value as? String,
       let parsed = Int(value) {
        return parsed
    }
    return fallback
}

private func openAPIBoolValue(_ value: Any?) -> Bool? {
    if let value = value as? Bool {
        return value
    }
    if let value = value as? String {
        return value == "true" || value == "1" || value == "yes"
    }
    return nil
}

private func openAPIStringArrayValue(_ value: Any?) -> [String] {
    return (value as? [Any] ?? []).map { openAPIStringValue($0) }.filter { !$0.isEmpty }
}

private func openAPIPageInfo(root: [String: Any], resultCount: Int) -> [String: Any] {
    let meta = (root["meta"] as? [String: Any]) ?? [:]
    var pageInfo: [String: Any] = [
        "resultCount": openAPIIntValue(meta["result_count"], fallback: resultCount)
    ]
    openAPICopyString(meta, from: "next_token", to: "nextToken", into: &pageInfo)
    openAPICopyString(meta, from: "previous_token", to: "previousToken", into: &pageInfo)
    openAPICopyString(meta, from: "newest_id", to: "newestId", into: &pageInfo)
    openAPICopyString(meta, from: "oldest_id", to: "oldestId", into: &pageInfo)
    return pageInfo
}

private func openAPIStreamRules(_ root: [String: Any]) -> [[String: Any]] {
    return ((root["data"] as? [[String: Any]]) ?? []).map { rule in
        var projected: [String: Any] = [
            "id": openAPIStringValue(rule["id"]),
            "value": openAPIStringValue(rule["value"])
        ]
        openAPICopyString(rule, from: "tag", to: "tag", into: &projected)
        return projected
    }
}

private func openAPICopyStreamMeta(_ root: [String: Any], into target: inout [String: Any]) {
    let meta = (root["meta"] as? [String: Any]) ?? [:]
    openAPICopyString(meta, from: "sent", to: "sent", into: &target)
    guard let summary = meta["summary"] as? [String: Any] else {
        return
    }
    var projectedSummary: [String: Any] = [:]
    openAPICopyInt(summary, from: "created", to: "created", into: &projectedSummary)
    openAPICopyInt(summary, from: "deleted", to: "deleted", into: &projectedSummary)
    openAPICopyInt(summary, from: "invalid", to: "invalid", into: &projectedSummary)
    openAPICopyInt(summary, from: "not_created", to: "notCreated", into: &projectedSummary)
    openAPICopyInt(summary, from: "not_deleted", to: "notDeleted", into: &projectedSummary)
    openAPICopyInt(summary, from: "valid", to: "valid", into: &projectedSummary)
    if !projectedSummary.isEmpty {
        target["summary"] = projectedSummary
    }
}

private func openAPIStreamRuleError(_ error: [String: Any]) -> [String: Any] {
    var projected: [String: Any] = [:]
    openAPICopyString(error, from: "title", to: "title", into: &projected)
    openAPICopyString(error, from: "type", to: "type", into: &projected)
    openAPICopyString(error, from: "detail", to: "detail", into: &projected)
    openAPICopyInt(error, from: "status", to: "status", into: &projected)
    return projected
}

private func openAPICopyString(_ source: [String: Any], from sourceKey: String, to targetKey: String, into target: inout [String: Any]) {
    guard let value = source[sourceKey] as? String,
          !value.isEmpty else {
        return
    }
    target[targetKey] = value
}

private func openAPICopyStringArray(_ source: [String: Any], from sourceKey: String, to targetKey: String, into target: inout [String: Any]) {
    let values = openAPIStringArrayValue(source[sourceKey])
    guard !values.isEmpty else {
        return
    }
    target[targetKey] = values
}

private func openAPICopyInt(_ source: [String: Any], from sourceKey: String, to targetKey: String, into target: inout [String: Any]) {
    guard let value = source[sourceKey] else {
        return
    }
    target[targetKey] = openAPIIntValue(value)
}

private func openAPICopyBool(_ source: [String: Any], from sourceKey: String, to targetKey: String, into target: inout [String: Any]) {
    guard let value = openAPIBoolValue(source[sourceKey]) else {
        return
    }
    target[targetKey] = value
}
