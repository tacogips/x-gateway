import Foundation

enum XGatewayExtendedProjector {
    static func list(_ payload: Any) -> [String: Any] {
        return listObject(dataObject(payload))
    }

    static func listPage(_ payload: Any) -> [String: Any] {
        let root = object(payload)
        let lists = ((root["data"] as? [[String: Any]]) ?? []).map(listObject)
        return [
            "lists": lists,
            "pageInfo": pageInfo(root: root, resultCount: lists.count)
        ]
    }

    static func dmEvent(_ payload: Any) -> [String: Any] {
        return dmEventObject(dataObject(payload))
    }

    static func dmEventPage(_ payload: Any) -> [String: Any] {
        let root = object(payload)
        let events = ((root["data"] as? [[String: Any]]) ?? []).map(dmEventObject)
        return [
            "events": events,
            "pageInfo": pageInfo(root: root, resultCount: events.count)
        ]
    }

    static func booleanResult(
        id: String,
        key: String,
        _ payload: Any,
        upstreamKey: String? = nil,
        defaultValue: Bool
    ) -> [String: Any] {
        let data = dataObject(payload)
        let sourceKey = upstreamKey ?? key
        return [
            "id": stringValue(data["id"], fallback: id),
            key: boolValue(data[sourceKey], fallback: defaultValue)
        ]
    }
}

private func listObject(_ list: [String: Any]) -> [String: Any] {
    var projected: [String: Any] = [
        "id": stringValue(list["id"]),
        "name": stringValue(list["name"])
    ]
    copyString(list, from: "description", to: "description", into: &projected)
    copyString(list, from: "created_at", to: "createdAt", into: &projected)
    copyString(list, from: "owner_id", to: "ownerId", into: &projected)
    copyInt(list, from: "follower_count", to: "followerCount", into: &projected)
    copyInt(list, from: "member_count", to: "memberCount", into: &projected)
    if let isPrivate = list["private"] as? Bool {
        projected["private"] = isPrivate
    }
    return projected
}

private func dmEventObject(_ event: [String: Any]) -> [String: Any] {
    let eventId = stringValue(event["id"], fallback: stringValue(event["dm_event_id"]))
    var projected: [String: Any] = [
        "id": eventId,
        "eventType": stringValue(event["event_type"], fallback: eventId.isEmpty ? "" : "MessageCreate")
    ]
    copyString(event, from: "created_at", to: "createdAt", into: &projected)
    copyString(event, from: "dm_conversation_id", to: "conversationId", into: &projected)
    copyString(event, from: "sender_id", to: "senderId", into: &projected)
    copyString(event, from: "text", to: "text", into: &projected)
    let participants = stringArrayValue(event["participant_ids"])
    if !participants.isEmpty {
        projected["participantIds"] = participants
    }
    let referencedPostIds = ((event["referenced_tweets"] as? [[String: Any]]) ?? []).compactMap { item -> String? in
        let id = stringValue(item["id"])
        return id.isEmpty ? nil : id
    }
    if !referencedPostIds.isEmpty {
        projected["referencedPostIds"] = referencedPostIds
    }
    if let attachments = event["attachments"] as? [String: Any] {
        projected["attachmentMediaKeys"] = stringArrayValue(attachments["media_keys"])
        projected["attachmentCardIds"] = stringArrayValue(attachments["card_ids"])
    }
    return projected
}

private func object(_ payload: Any) -> [String: Any] {
    return (payload as? [String: Any]) ?? [:]
}

private func dataObject(_ payload: Any) -> [String: Any] {
    return object(payload)["data"] as? [String: Any] ?? [:]
}

private func stringValue(_ value: Any?, fallback: String = "") -> String {
    if let value = value as? String {
        return value
    }
    if let value {
        return String(describing: value)
    }
    return fallback
}

private func intValue(_ value: Any?) -> Int? {
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
    return nil
}

private func boolValue(_ value: Any?, fallback: Bool) -> Bool {
    if let value = value as? Bool {
        return value
    }
    if let value = value as? String {
        return value == "true" || value == "1" || value == "yes"
    }
    return fallback
}

private func pageInfo(root: [String: Any], resultCount: Int) -> [String: Any] {
    let meta = (root["meta"] as? [String: Any]) ?? [:]
    var page: [String: Any] = [
        "resultCount": intValue(meta["result_count"]) ?? resultCount
    ]
    copyString(meta, from: "next_token", to: "nextToken", into: &page)
    copyString(meta, from: "previous_token", to: "previousToken", into: &page)
    copyString(meta, from: "newest_id", to: "newestId", into: &page)
    copyString(meta, from: "oldest_id", to: "oldestId", into: &page)
    return page
}

private func stringArrayValue(_ value: Any?) -> [String] {
    return (value as? [Any] ?? []).map { stringValue($0) }.filter { !$0.isEmpty }
}

private func copyString(_ source: [String: Any], from sourceKey: String, to targetKey: String, into target: inout [String: Any]) {
    guard let value = source[sourceKey] as? String,
          !value.isEmpty else {
        return
    }
    target[targetKey] = value
}

private func copyInt(_ source: [String: Any], from sourceKey: String, to targetKey: String, into target: inout [String: Any]) {
    if let value = intValue(source[sourceKey]) {
        target[targetKey] = value
    }
}
