import Foundation

public enum XGatewayResponseProjector {
    public static func account(_ payload: Any) -> [String: Any] {
        let data = dataObject(payload)
        return [
            "id": stringValue(data["id"]),
            "username": stringValue(data["username"]),
            "name": stringValue(data["name"])
        ]
    }

    public static func apiUsage(_ payload: Any) -> [String: Any] {
        let data = dataObject(payload)
        let dailyProjectUsage: [String: Any] = [
            "projectId": stringValue((data["daily_project_usage"] as? [String: Any])?["project_id"]),
            "usage": usageDays((data["daily_project_usage"] as? [String: Any])?["usage"])
        ]
        return [
            "capResetDay": intValue(data["cap_reset_day"]),
            "dailyClientAppUsage": ((data["daily_client_app_usage"] as? [[String: Any]]) ?? []).map { app in
                [
                    "clientAppId": stringValue(app["client_app_id"]),
                    "usageResultCount": intValue(app["usage_result_count"]),
                    "usage": usageDays(app["usage"])
                ] as [String: Any]
            },
            "dailyProjectUsage": dailyProjectUsage,
            "projectCap": intValue(data["project_cap"]),
            "projectId": stringValue(data["project_id"]),
            "projectUsage": intValue(data["project_usage"])
        ]
    }

    public static func post(_ payload: Any, options: XGatewayPostReadOptions = XGatewayPostReadOptions()) throws -> [String: Any] {
        let root = object(payload)
        let context = ProjectionContext(root: root)
        guard let post = try postObject(dataObject(payload), context: context, maxReferenceDepth: 2, options: options) else {
            throw XGatewayErrorPayload(
                code: .permissionDenied,
                summary: "Promoted post filtered from the stable read surface",
                details: "The requested post was identified as promoted in the upstream payload and x-gateway excluded it because includePromoted was not enabled.",
                likelyCauses: [
                    "The post is currently promoted for the authenticated author context",
                    "The request relied on the default includePromoted: false behavior"
                ],
                remediations: [
                    "Retry with includePromoted: true if you want promoted posts returned."
                ],
                classification: "permission",
                retryable: false,
                traceId: nil
            )
        }
        return post
    }

    public static func post(_ payload: Any, includePromoted: Bool) throws -> [String: Any] {
        return try post(payload, options: XGatewayPostReadOptions(includePromoted: includePromoted))
    }

    public static func postPage(_ payload: Any, options: XGatewayPostReadOptions = XGatewayPostReadOptions()) throws -> [String: Any] {
        let root = object(payload)
        let context = ProjectionContext(root: root)
        let tweets = (root["data"] as? [[String: Any]]) ?? []
        var posts: [[String: Any]] = []
        for tweet in tweets {
            if let post = try postObject(tweet, context: context, maxReferenceDepth: 2, options: options) {
                posts.append(post)
            }
        }
        let meta = (root["meta"] as? [String: Any]) ?? [:]
        var pageInfo: [String: Any] = [
            "resultCount": intValue(meta["result_count"], fallback: posts.count)
        ]
        copyString(meta, from: "next_token", to: "nextToken", into: &pageInfo)
        copyString(meta, from: "previous_token", to: "previousToken", into: &pageInfo)
        if let newestId = posts.first?["id"] as? String {
            pageInfo["newestId"] = newestId
        } else {
            copyString(meta, from: "newest_id", to: "newestId", into: &pageInfo)
        }
        if let oldestId = posts.last?["id"] as? String {
            pageInfo["oldestId"] = oldestId
        } else {
            copyString(meta, from: "oldest_id", to: "oldestId", into: &pageInfo)
        }
        return [
            "posts": posts,
            "pageInfo": pageInfo
        ]
    }

    public static func postPage(_ payload: Any, includePromoted: Bool) throws -> [String: Any] {
        return try postPage(payload, options: XGatewayPostReadOptions(includePromoted: includePromoted))
    }

    public static func createdPost(_ payload: Any) -> [String: Any] {
        let data = dataObject(payload)
        return [
            "id": stringValue(data["id"]),
            "text": stringValue(data["text"])
        ]
    }

    public static func deletedPost(postId: String, _ payload: Any) -> [String: Any] {
        let data = dataObject(payload)
        return [
            "id": stringValue(data["id"], fallback: postId),
            "deleted": boolValue(data["deleted"], fallback: true)
        ]
    }

    public static func repost(postId: String, _ payload: Any, defaultReposted: Bool) -> [String: Any] {
        let data = dataObject(payload)
        return [
            "id": stringValue(data["id"], fallback: stringValue(data["tweet_id"], fallback: postId)),
            "reposted": boolValue(data["retweeted"], fallback: boolValue(data["reposted"], fallback: defaultReposted))
        ]
    }
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
    if let value = value {
        return String(describing: value)
    }
    return fallback
}

private func intValue(_ value: Any?, fallback: Int = 0) -> Int {
    if let value = value as? Int {
        return value
    }
    if let value = value as? Double {
        return Int(value)
    }
    if let value = value as? String, let parsed = Int(value) {
        return parsed
    }
    return fallback
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

private func usageDays(_ value: Any?) -> [[String: Any]] {
    return ((value as? [[String: Any]]) ?? []).map { day in
        [
            "date": stringValue(day["date"]),
            "usage": intValue(day["usage"])
        ]
    }
}

private struct ProjectionContext {
    let usersById: [String: [String: Any]]
    let mediaByKey: [String: [String: Any]]
    let tweetsById: [String: [String: Any]]

    init(root: [String: Any]) {
        let includes = root["includes"] as? [String: Any]
        var users: [String: [String: Any]] = [:]
        for user in (includes?["users"] as? [[String: Any]]) ?? [] {
            if let id = user["id"] as? String {
                users[id] = user
            }
        }
        var media: [String: [String: Any]] = [:]
        for item in (includes?["media"] as? [[String: Any]]) ?? [] {
            if let mediaKey = item["media_key"] as? String {
                media[mediaKey] = item
            }
        }
        var tweets: [String: [String: Any]] = [:]
        if let data = root["data"] as? [String: Any],
           let id = data["id"] as? String {
            tweets[id] = data
        }
        for tweet in (root["data"] as? [[String: Any]]) ?? [] {
            if let id = tweet["id"] as? String {
                tweets[id] = tweet
            }
        }
        for tweet in (includes?["tweets"] as? [[String: Any]]) ?? [] {
            if let id = tweet["id"] as? String {
                tweets[id] = tweet
            }
        }
        usersById = users
        mediaByKey = media
        tweetsById = tweets
    }
}

private func postObject(
    _ tweet: [String: Any],
    context: ProjectionContext,
    maxReferenceDepth: Int,
    options: XGatewayPostReadOptions,
    relation: String? = nil
) throws -> [String: Any]? {
    guard !stringValue(tweet["id"]).isEmpty else {
        return nil
    }
    let promotionStatus = detectPromotionStatus(tweet)
    if !options.includePromoted,
       promotionStatus == "PROMOTED" {
        return nil
    }
    var post: [String: Any] = [
        "id": stringValue(tweet["id"]),
        "text": stringValue(tweet["text"]),
        "promotionStatus": promotionStatus,
        "metrics": metricsObject(tweet)
    ]
    copyString(tweet, from: "created_at", to: "createdAt", into: &post)
    copyString(tweet, from: "conversation_id", to: "conversationId", into: &post)
    copyString(tweet, from: "in_reply_to_user_id", to: "replyToUserId", into: &post)
    if let authorId = tweet["author_id"] as? String,
       let user = context.usersById[authorId] {
        post["author"] = [
            "id": stringValue(user["id"]),
            "username": stringValue(user["username"]),
            "name": stringValue(user["name"])
        ]
    }
    if let relation {
        post["relation"] = relation
    }
    let media = try mediaAssets(for: tweet, context: context, options: options)
    if !media.isEmpty {
        post["media"] = media
    }
    if maxReferenceDepth > 0 {
        let referencedPosts = try referencedPostObjects(
            tweet,
            context: context,
            maxReferenceDepth: maxReferenceDepth,
            options: options
        )
        if !referencedPosts.isEmpty {
            post["referencedPosts"] = referencedPosts
        }
        if let replyTo = referencedPosts.first(where: { ($0["relation"] as? String) == "replied_to" }) {
            post["replyTo"] = replyTo
        }
        if let quote = referencedPosts.first(where: { ($0["relation"] as? String) == "quoted" }) {
            post["quote"] = quote
        }
        if let repost = referencedPosts.first(where: { ($0["relation"] as? String) == "retweeted" }) {
            post["repost"] = repost
        }
    }
    return post
}

private func referencedPostObjects(
    _ tweet: [String: Any],
    context: ProjectionContext,
    maxReferenceDepth: Int,
    options: XGatewayPostReadOptions
) throws -> [[String: Any]] {
    let references = (tweet["referenced_tweets"] as? [[String: Any]]) ?? []
    var posts: [[String: Any]] = []
    for reference in references {
        guard let relation = reference["type"] as? String,
              ["replied_to", "quoted", "retweeted"].contains(relation),
              let id = reference["id"] as? String,
              let referencedTweet = context.tweetsById[id] else {
            continue
        }
        if let post = try postObject(
            referencedTweet,
            context: context,
            maxReferenceDepth: maxReferenceDepth - 1,
            options: options,
            relation: relation
        ) {
            posts.append(post)
        }
    }
    return posts
}

private func mediaAssets(
    for tweet: [String: Any],
    context: ProjectionContext,
    options: XGatewayPostReadOptions
) throws -> [[String: Any]] {
    let mediaKeys = ((tweet["attachments"] as? [String: Any])?["media_keys"] as? [String]) ?? []
    var assets: [[String: Any]] = []
    for mediaKey in mediaKeys {
        guard let media = context.mediaByKey[mediaKey],
              let source = mediaSource(media) else {
            continue
        }
        var asset: [String: Any] = [
            "kind": mediaKind(media["type"]),
            "contentType": source.contentType,
            "sourceUrl": source.sourceUrl
        ]
        copyString(media, from: "preview_image_url", to: "previewImageUrl", into: &asset)
        assets.append(try materializeMediaAsset(
            asset,
            mediaKey: mediaKey,
            postId: stringValue(tweet["id"], fallback: "post"),
            options: options
        ))
    }
    return assets
}

private func mediaKind(_ value: Any?) -> String {
    let type = stringValue(value, fallback: "photo")
    if ["photo", "video", "animated_gif"].contains(type) {
        return type
    }
    return "photo"
}

private func mediaSource(_ media: [String: Any]) -> (contentType: String, sourceUrl: String)? {
    let type = stringValue(media["type"])
    if type == "photo",
       let url = media["url"] as? String,
       !url.isEmpty {
        let extensionValue = URL(string: url)?.pathExtension.lowercased()
        return (extensionValue == "png" ? "image/png" : "image/jpeg", url)
    }
    let variants = ((media["variants"] as? [[String: Any]]) ?? [])
        .filter { ($0["content_type"] as? String) == "video/mp4" && ($0["url"] as? String)?.isEmpty == false }
        .sorted { intValue($0["bit_rate"]) > intValue($1["bit_rate"]) }
    if let variant = variants.first,
       let url = variant["url"] as? String {
        return ("video/mp4", url)
    }
    return nil
}

private func materializeMediaAsset(
    _ asset: [String: Any],
    mediaKey: String,
    postId: String,
    options: XGatewayPostReadOptions
) throws -> [String: Any] {
    guard options.downloadMedia,
          let mediaRootDir = nonBlank(options.mediaRootDir),
          let sourceUrlValue = asset["sourceUrl"] as? String else {
        return asset
    }
    guard let sourceUrl = URL(string: sourceUrlValue),
          let scheme = sourceUrl.scheme?.lowercased(),
          ["http", "https"].contains(scheme) else {
        throw XGatewayErrorPayload(
            code: .upstreamFailure,
            summary: "Media source URL is not downloadable",
            details: "The upstream media asset did not include a supported http or https source URL.",
            likelyCauses: [
                "The X API response included an unexpected media URL shape",
                "The media asset is missing a direct downloadable URL"
            ],
            remediations: [
                "Retry with downloadMedia: false to return source URLs only.",
                "Capture the upstream payload and verify the media URL field."
            ],
            classification: "upstream",
            retryable: false,
            traceId: nil
        )
    }

    let rootUrl = URL(fileURLWithPath: mediaRootDir, isDirectory: true)
    let postDirectory = rootUrl.appendingPathComponent(sanitizePathComponent(postId, fallback: "post"), isDirectory: true)
    let localUrl = postDirectory.appendingPathComponent(
        mediaFileName(mediaKey: mediaKey, sourceUrl: sourceUrl, contentType: stringValue(asset["contentType"])),
        isDirectory: false
    )
    var materialized = asset
    if FileManager.default.fileExists(atPath: localUrl.path),
       !options.forceDownload {
        materialized["localFilePath"] = localUrl.path
        return materialized
    }

    do {
        try FileManager.default.createDirectory(at: postDirectory, withIntermediateDirectories: true)
        let data = try Data(contentsOf: sourceUrl)
        try data.write(to: localUrl, options: .atomic)
        materialized["localFilePath"] = localUrl.path
        return materialized
    } catch {
        throw XGatewayErrorPayload(
            code: .networkFailure,
            summary: "Media download failed",
            details: "x-gateway could not download \(sourceUrlValue) to \(localUrl.path): \(error.localizedDescription)",
            likelyCauses: [
                "The media URL expired or was unreachable",
                "The local mediaRootDir is not writable",
                "Network connectivity failed while downloading media"
            ],
            remediations: [
                "Retry the read operation.",
                "Retry with forceDownload: false if the file already exists locally.",
                "Retry with downloadMedia: false to return source URLs without local materialization.",
                "Verify that mediaRootDir exists or can be created by this process."
            ],
            classification: "network",
            retryable: true,
            traceId: nil
        )
    }
}

private func mediaFileName(mediaKey: String, sourceUrl: URL, contentType: String) -> String {
    let lastPathComponent = sourceUrl.lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
    let base = lastPathComponent.isEmpty ? mediaKey : lastPathComponent
    let sanitizedBase = sanitizePathComponent(base, fallback: "media")
    if !sourceUrl.pathExtension.isEmpty {
        return sanitizedBase
    }
    return sanitizedBase + mediaExtension(contentType: contentType)
}

private func mediaExtension(contentType: String) -> String {
    switch contentType.lowercased() {
    case "image/jpeg":
        return ".jpg"
    case "image/png":
        return ".png"
    case "image/gif":
        return ".gif"
    case "video/mp4":
        return ".mp4"
    case "application/vnd.apple.mpegurl":
        return ".m3u8"
    default:
        return ""
    }
}

private func sanitizePathComponent(_ value: String, fallback: String) -> String {
    let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._-")
    let sanitized = String(value.unicodeScalars.map { scalar in
        allowed.contains(scalar) ? Character(scalar) : "_"
    })
    let trimmed = sanitized.trimmingCharacters(in: CharacterSet(charactersIn: "._-"))
    return trimmed.isEmpty ? fallback : sanitized
}

private func metricsObject(_ tweet: [String: Any]?) -> [String: Any] {
    let publicMetrics = tweet?["public_metrics"] as? [String: Any]
    let organicMetrics = tweet?["organic_metrics"] as? [String: Any]
    let promotedMetrics = tweet?["promoted_metrics"] as? [String: Any]
    return [
        "likeCount": nullableInt(publicMetrics?["like_count"]),
        "replyCount": nullableInt(publicMetrics?["reply_count"]),
        "repostCount": nullableInt(publicMetrics?["retweet_count"]),
        "quoteCount": nullableInt(publicMetrics?["quote_count"]),
        "bookmarkCount": nullableInt(publicMetrics?["bookmark_count"]),
        "impressionCount": firstNullableInt([
            publicMetrics?["impression_count"],
            organicMetrics?["impression_count"],
            promotedMetrics?["impression_count"]
        ])
    ]
}

private func detectPromotionStatus(_ tweet: [String: Any]) -> String {
    if hasFiniteMetricValue(tweet["promoted_metrics"] as? [String: Any]) {
        return "PROMOTED"
    }
    if hasFiniteMetricValue(tweet["organic_metrics"] as? [String: Any]) {
        return "NOT_PROMOTED"
    }
    return "UNKNOWN"
}

private func hasFiniteMetricValue(_ metrics: [String: Any]?) -> Bool {
    guard let metrics else {
        return false
    }
    return metrics.values.contains { value in
        if let value = value as? Int {
            return value >= 0
        }
        if let value = value as? Double {
            return value.isFinite
        }
        return false
    }
}

private func firstNullableInt(_ values: [Any?]) -> Any {
    for value in values {
        if value != nil,
           !(value is NSNull) {
            return nullableInt(value)
        }
    }
    return NSNull()
}

private func nullableInt(_ value: Any?) -> Any {
    guard let value else {
        return NSNull()
    }
    if value is NSNull {
        return NSNull()
    }
    return intValue(value)
}

private func copyString(_ source: [String: Any], from sourceKey: String, to targetKey: String, into target: inout [String: Any]) {
    guard let value = source[sourceKey] as? String,
          !value.isEmpty else {
        return
    }
    target[targetKey] = value
}
