import Foundation

func urlPathEscape(_ value: String) -> String {
    var allowed = CharacterSet.urlPathAllowed
    allowed.remove(charactersIn: "/?#[]@!$&'()*+,;=:")
    return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
}

let tweetLookupQuery = timelineQueryItems([:])
let userLookupQuery = queryItems(["user.fields": "id,name,username"])

func userPageQueryItems(_ additionalItems: [String: String]) -> String {
    var items = additionalItems
    items["user.fields"] = "id,name,username"
    return queryItems(items)
}

func xAPIURL(path: String, query: String? = nil) throws -> URL {
    return try httpsURL(host: "api.twitter.com", path: path, query: query)
}

func xUsageAPIURL(path: String, query: String? = nil) throws -> URL {
    return try httpsURL(host: "api.x.com", path: path, query: query)
}

func xArticleAPIURL(path: String, query: String? = nil) throws -> URL {
    return try httpsURL(host: XGatewayArticleRequestBuilder.apiHost, path: path, query: query)
}

func xUploadURL(path: String = "/1.1/media/upload.json", query: String? = nil) throws -> URL {
    return try httpsURL(host: "upload.twitter.com", path: path, query: query)
}

private func httpsURL(host: String, path: String, query: String?) throws -> URL {
    var components = URLComponents()
    components.scheme = "https"
    components.host = host
    components.percentEncodedPath = path
    if let query,
       !query.isEmpty {
        components.percentEncodedQuery = query
    }
    guard let url = components.url else {
        throw XGatewayErrorPayload(
            code: .internalError,
            summary: "X API URL construction failed",
            details: "Could not construct HTTPS URL for host \(host) and path \(path).",
            likelyCauses: ["The Swift endpoint adapter used an invalid path or query string"],
            remediations: ["Inspect the Swift endpoint adapter for malformed URL components."],
            classification: "internal",
            retryable: false,
            traceId: nil
        )
    }
    return url
}

func queryItems(_ items: [String: String]) -> String {
    return items
        .sorted { $0.key < $1.key }
        .map { key, value in
            "\(urlQueryEscape(key))=\(urlQueryEscape(value))"
        }
        .joined(separator: "&")
}

func timelineQueryItems(
    _ additionalItems: [String: String],
    includeTweetFields: Bool = true,
    includeOwnerMetrics: Bool = true
) -> String {
    var items = additionalItems
    if includeTweetFields {
        var tweetFields = "attachments,author_id,conversation_id,created_at,in_reply_to_user_id,public_metrics,referenced_tweets"
        if includeOwnerMetrics {
            tweetFields += ",organic_metrics,promoted_metrics"
        }
        items["tweet.fields"] = tweetFields
        items["expansions"] = "author_id,attachments.media_keys,referenced_tweets.id"
        items["media.fields"] = "alt_text,duration_ms,height,media_key,preview_image_url,type,url,width"
    }
    items["user.fields"] = "id,name,username"
    return queryItems(items)
}

func urlQueryEscape(_ value: String) -> String {
    var allowed = CharacterSet.urlQueryAllowed
    allowed.remove(charactersIn: ":#[]@!$&'()*+,;=")
    return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
}

func formURLEncodedData(_ items: [(String, String)]) -> Data {
    let encoded = items
        .map { key, value in
            "\(urlQueryEscape(key))=\(urlQueryEscape(value))"
        }
        .joined(separator: "&")
    return Data(encoded.utf8)
}

func multipartData(parts: [MultipartPart], boundary: String) -> Data {
    var data = Data()
    for part in parts {
        appendUTF8("--\(boundary)\r\n", to: &data)
        switch part {
        case .field(let name, let value):
            appendUTF8("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n", to: &data)
            appendUTF8("\(value)\r\n", to: &data)
        case .file(let name, let filename, let mimeType, let body):
            appendUTF8("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n", to: &data)
            appendUTF8("Content-Type: \(mimeType)\r\n\r\n", to: &data)
            data.append(body)
            appendUTF8("\r\n", to: &data)
        }
    }
    appendUTF8("--\(boundary)--\r\n", to: &data)
    return data
}

private func appendUTF8(_ string: String, to data: inout Data) {
    data.append(Data(string.utf8))
}

func mediaProcessingIntValue(_ value: Any?) -> Int {
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
    return 0
}

func extractUserIds(_ payload: Any) -> [String] {
    guard let root = payload as? [String: Any],
          let data = root["data"] as? [[String: Any]] else {
        return []
    }
    return data.compactMap { $0["id"] as? String }
}

func mergeIncludes(_ includes: [[String: Any]]) -> [String: Any] {
    var usersById: [String: [String: Any]] = [:]
    var mediaByKey: [String: [String: Any]] = [:]
    var tweetsById: [String: [String: Any]] = [:]

    for include in includes {
        for user in (include["users"] as? [[String: Any]]) ?? [] {
            if let id = user["id"] as? String {
                usersById[id] = user
            }
        }
        for media in (include["media"] as? [[String: Any]]) ?? [] {
            if let key = media["media_key"] as? String {
                mediaByKey[key] = media
            }
        }
        for tweet in (include["tweets"] as? [[String: Any]]) ?? [] {
            if let id = tweet["id"] as? String {
                tweetsById[id] = tweet
            }
        }
    }

    var merged: [String: Any] = [:]
    if !usersById.isEmpty {
        merged["users"] = Array(usersById.values)
    }
    if !mediaByKey.isEmpty {
        merged["media"] = Array(mediaByKey.values)
    }
    if !tweetsById.isEmpty {
        merged["tweets"] = Array(tweetsById.values)
    }
    return merged
}
