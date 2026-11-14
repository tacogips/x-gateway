import Foundation

extension XGatewayResponseProjector {
    public static func user(_ payload: Any) -> [String: Any] {
        return account(payload)
    }

    public static func userPage(_ payload: Any) -> [String: Any] {
        let root = mcpObject(payload)
        let users = ((root["data"] as? [[String: Any]]) ?? []).map { user in
            [
                "id": mcpStringValue(user["id"]),
                "username": mcpStringValue(user["username"]),
                "name": mcpStringValue(user["name"])
            ]
        }
        return [
            "users": users,
            "pageInfo": mcpPageInfo(root: root, resultCount: users.count)
        ]
    }

    public static func postCounts(_ payload: Any) -> [String: Any] {
        let root = mcpObject(payload)
        let buckets = ((root["data"] as? [[String: Any]]) ?? []).map { bucket in
            [
                "start": mcpStringValue(bucket["start"]),
                "end": mcpStringValue(bucket["end"]),
                "postCount": mcpIntValue(bucket["tweet_count"])
            ]
        }
        let meta = (root["meta"] as? [String: Any]) ?? [:]
        return [
            "counts": buckets,
            "pageInfo": mcpPageInfo(root: root, resultCount: buckets.count),
            "totalPostCount": mcpIntValue(meta["total_tweet_count"])
        ]
    }

    public static func bookmark(postId: String, _ payload: Any, defaultBookmarked: Bool) -> [String: Any] {
        let data = mcpDataObject(payload)
        return [
            "id": mcpStringValue(data["id"], fallback: mcpStringValue(data["tweet_id"], fallback: postId)),
            "bookmarked": mcpBoolValue(data["bookmarked"], fallback: defaultBookmarked)
        ]
    }

    public static func bookmarkFolderPage(_ payload: Any) -> [String: Any] {
        let root = mcpObject(payload)
        let folders = ((root["data"] as? [[String: Any]]) ?? []).map { folder in
            [
                "id": mcpStringValue(folder["id"]),
                "name": mcpStringValue(folder["name"])
            ]
        }
        return [
            "folders": folders,
            "pageInfo": mcpPageInfo(root: root, resultCount: folders.count)
        ]
    }

    public static func newsPage(_ payload: Any) -> [String: Any] {
        let root = mcpObject(payload)
        let stories = ((root["data"] as? [[String: Any]]) ?? []).map(newsStory)
        return [
            "stories": stories,
            "pageInfo": mcpPageInfo(root: root, resultCount: stories.count)
        ]
    }

    public static func news(_ payload: Any) -> [String: Any] {
        return newsStory(mcpDataObject(payload))
    }

    public static func trendPage(_ payload: Any) -> [String: Any] {
        let root = mcpObject(payload)
        let trends = ((root["data"] as? [[String: Any]]) ?? []).map { trend in
            [
                "name": mcpStringValue(trend["trend_name"]),
                "postCount": mcpNullableIntJSONValue(trend["tweet_count"])
            ]
        }
        return [
            "trends": trends,
            "pageInfo": mcpPageInfo(root: root, resultCount: trends.count)
        ]
    }

    public static func articleDraft(_ payload: Any) -> [String: Any] {
        let data = mcpDataObject(payload)
        return [
            "id": mcpStringValue(data["id"]),
            "title": mcpStringValue(data["title"])
        ]
    }

    public static func articlePublish(_ payload: Any) -> [String: Any] {
        let data = mcpDataObject(payload)
        return [
            "postId": mcpStringValue(data["post_id"])
        ]
    }
}

private func newsStory(_ story: [String: Any]) -> [String: Any] {
    var projected: [String: Any] = [
        "id": mcpStringValue(story["id"]),
        "name": mcpStringValue(story["name"]),
        "keywords": mcpStringArrayValue(story["keywords"]),
        "postIds": mcpNewsPostIds(story["cluster_posts_results"])
    ]
    mcpCopyString(story, from: "summary", to: "summary", into: &projected)
    mcpCopyString(story, from: "category", to: "category", into: &projected)
    mcpCopyString(story, from: "hook", to: "hook", into: &projected)
    mcpCopyString(story, from: "updated_at", to: "lastUpdatedAt", into: &projected)
    return projected
}

private func mcpObject(_ payload: Any) -> [String: Any] {
    return (payload as? [String: Any]) ?? [:]
}

private func mcpDataObject(_ payload: Any) -> [String: Any] {
    return mcpObject(payload)["data"] as? [String: Any] ?? [:]
}

private func mcpStringValue(_ value: Any?, fallback: String = "") -> String {
    if let value = value as? String {
        return value
    }
    if let value {
        return String(describing: value)
    }
    return fallback
}

private func mcpIntValue(_ value: Any?, fallback: Int = 0) -> Int {
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

private func mcpNullableIntValue(_ value: Any?) -> Int? {
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

private func mcpNullableIntJSONValue(_ value: Any?) -> Any {
    return mcpNullableIntValue(value) ?? NSNull()
}

private func mcpBoolValue(_ value: Any?, fallback: Bool) -> Bool {
    if let value = value as? Bool {
        return value
    }
    if let value = value as? String {
        return value == "true" || value == "1" || value == "yes"
    }
    return fallback
}

private func mcpPageInfo(root: [String: Any], resultCount: Int) -> [String: Any] {
    let meta = (root["meta"] as? [String: Any]) ?? [:]
    var pageInfo: [String: Any] = [
        "resultCount": mcpIntValue(meta["result_count"], fallback: resultCount)
    ]
    mcpCopyString(meta, from: "next_token", to: "nextToken", into: &pageInfo)
    mcpCopyString(meta, from: "previous_token", to: "previousToken", into: &pageInfo)
    mcpCopyString(meta, from: "newest_id", to: "newestId", into: &pageInfo)
    mcpCopyString(meta, from: "oldest_id", to: "oldestId", into: &pageInfo)
    return pageInfo
}

private func mcpStringArrayValue(_ value: Any?) -> [String] {
    return (value as? [Any] ?? []).map { mcpStringValue($0) }.filter { !$0.isEmpty }
}

private func mcpNewsPostIds(_ value: Any?) -> [String] {
    return ((value as? [[String: Any]]) ?? []).compactMap { item in
        let postId = mcpStringValue(item["post_id"])
        return postId.isEmpty ? nil : postId
    }
}

private func mcpCopyString(_ source: [String: Any], from sourceKey: String, to targetKey: String, into target: inout [String: Any]) {
    guard let value = source[sourceKey] as? String,
          !value.isEmpty else {
        return
    }
    target[targetKey] = value
}
