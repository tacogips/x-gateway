import Foundation

private enum XGatewayRequestAuthorization {
    case bearer(String)
    case oauth1(XGatewayOAuth1SigningCredentials)
}

enum MultipartPart {
    case field(name: String, value: String)
    case file(name: String, filename: String, mimeType: String, data: Data)
}

private final class ReplyExpansionState {
    var count = 0
}

private let maxReplyExpansions = 25

struct XGatewayLiveExecutor {
    let token: String?
    let oauth1Credentials: XGatewayOAuth1SigningCredentials?
    let mediaRootDir: String?
    let traceId: String?
    let transport: TransportSettings
}

extension XGatewayLiveExecutor {
    func executeGraphQL(document: String, operationType: XGatewayGraphQLOperationType) throws -> [String: Any] {
        let operation = try parseSupportedOperation(document: document, operationType: operationType)
        let authorization = try requireAuthorization(operation: operation)
        let response = try execute(operation: operation, authorization: authorization)
        return ["data": response]
    }

    private func requireAuthorization(operation: SupportedGraphQLOperation) throws -> XGatewayRequestAuthorization {
        if operation.requiresOAuth1 {
            guard let oauth1Credentials else {
                throw XGatewayErrorPayload(
                    code: .authMissing,
                    summary: "OAuth1 authentication configuration missing",
                    details: "\(operation.fieldName).attachments requires complete OAuth1 credentials because Swift media upload uses the X media upload API.",
                    likelyCauses: [
                        "Attachment-backed posting was requested",
                        "OAuth1 credentials were not fully configured"
                    ],
                    remediations: [
                        "Set X_GW_CONSUMER_KEY, X_GW_CONSUMER_SECRET, X_GW_ACCESS_TOKEN, and X_GW_ACCESS_TOKEN_SECRET.",
                        "Retry without attachments if text-only bearer-token posting is sufficient."
                    ],
                    classification: "auth",
                    retryable: false,
                    traceId: traceId
                )
            }
            return .oauth1(oauth1Credentials)
        }
        if !operation.supportsOAuth1 {
            return try requireBearerAuthorization(operation: operation, oauth1Supported: false)
        }
        if let oauth1Credentials {
            return .oauth1(oauth1Credentials)
        }
        return try requireBearerAuthorization(operation: operation, oauth1Supported: true)
    }

    private func requireBearerAuthorization(
        operation: SupportedGraphQLOperation,
        oauth1Supported: Bool
    ) throws -> XGatewayRequestAuthorization {
        guard let token,
              !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            let oauth1Cause = oauth1Supported
                ? "OAuth1 credentials were not fully configured"
                : "OAuth1 credentials are not supported by this Swift usage endpoint"
            let oauth1Remediation = oauth1Supported
                ? "Set X_GW_CONSUMER_KEY, X_GW_CONSUMER_SECRET, X_GW_ACCESS_TOKEN, and X_GW_ACCESS_TOKEN_SECRET for OAuth1 usage."
                : "Set X_GW_TOKEN for bearer-token usage."
            let credentialDetails = oauth1Supported
                ? "\(operation.fieldName) requires X_GW_TOKEN or complete OAuth1 credentials for the current Swift transport slice."
                : "\(operation.fieldName) requires X_GW_TOKEN or --token for the current Swift transport slice."
            throw XGatewayErrorPayload(
                code: .authMissing,
                summary: "Authentication configuration missing",
                details: credentialDetails,
                likelyCauses: [
                    "No bearer token was configured",
                    oauth1Cause
                ],
                remediations: [
                    "Set X_GW_TOKEN to a user-context bearer token with the required X API scope.",
                    oauth1Remediation
                ],
                classification: "auth",
                retryable: false,
                traceId: traceId
            )
        }
        return .bearer(token.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func execute(operation: SupportedGraphQLOperation, authorization: XGatewayRequestAuthorization) throws -> [String: Any] {
        switch operation {
        case .accountMe:
            let payload = try performJSONRequest(
                method: "GET",
                url: try xAPIURL(path: "/2/users/me", query: queryItems(["user.fields": "id,name,username"])),
                authorization: authorization,
                body: nil
            )
            return [operation.fieldName: XGatewayResponseProjector.account(payload)]
        case .apiUsage(let days):
            let payload = try performJSONRequest(
                method: "GET",
                url: try xUsageAPIURL(path: "/2/usage/tweets", query: queryItems(["days": String(days)])),
                authorization: authorization,
                body: nil
            )
            return [operation.fieldName: XGatewayResponseProjector.apiUsage(payload)]
        case .post(let postId, let readOptions, let replyExpansion):
            let options = readOptions.withDefaultMediaRootDir(mediaRootDir)
            let payload = try performJSONRequest(
                method: "GET",
                url: try xAPIURL(path: "/2/tweets/\(urlPathEscape(postId))", query: tweetLookupQuery),
                authorization: authorization,
                body: nil
            )
            let post = try XGatewayResponseProjector.post(payload, options: options)
            return [operation.fieldName: try hydrateReplies(in: post, expansion: replyExpansion, authorization: authorization)]
        case .searchPosts(let query, let maxResults, let readOptions, let replyExpansion):
            let options = readOptions.withDefaultMediaRootDir(mediaRootDir)
            let payload = try performJSONRequest(
                method: "GET",
                url: try xAPIURL(
                    path: "/2/tweets/search/recent",
                    query: timelineQueryItems(["query": query, "max_results": String(maxResults)])
                ),
                authorization: authorization,
                body: nil
            )
            let page = try XGatewayResponseProjector.postPage(payload, options: options)
            return [operation.fieldName: try hydrateReplies(inPage: page, expansion: replyExpansion, authorization: authorization)]
        case .homeTimeline(let maxResults, let readOptions, let replyExpansion):
            let options = readOptions.withDefaultMediaRootDir(mediaRootDir)
            let userId = try authenticatedUserId(authorization: authorization)
            let payload = try performJSONRequest(
                method: "GET",
                url: try xAPIURL(
                    path: "/2/users/\(urlPathEscape(userId))/timelines/reverse_chronological",
                    query: timelineQueryItems(["max_results": String(maxResults)])
                ),
                authorization: authorization,
                body: nil
            )
            let page = try XGatewayResponseProjector.postPage(payload, options: options)
            return [operation.fieldName: try hydrateReplies(inPage: page, expansion: replyExpansion, authorization: authorization)]
        case .followingTimeline(let maxResults, let maxUsers, let maxResultsPerUser, let readOptions, let replyExpansion):
            let options = readOptions.withDefaultMediaRootDir(mediaRootDir)
            let payload = try followingTimeline(
                authorization: authorization,
                maxResults: maxResults,
                maxUsers: maxUsers,
                maxResultsPerUser: maxResultsPerUser
            )
            let page = try XGatewayResponseProjector.postPage(payload, options: options)
            return [operation.fieldName: try hydrateReplies(inPage: page, expansion: replyExpansion, authorization: authorization)]
        case .userTimeline(let userId, let maxResults, let readOptions, let replyExpansion):
            let options = readOptions.withDefaultMediaRootDir(mediaRootDir)
            let payload = try performJSONRequest(
                method: "GET",
                url: try xAPIURL(
                    path: "/2/users/\(urlPathEscape(userId))/tweets",
                    query: timelineQueryItems(["max_results": String(maxResults)])
                ),
                authorization: authorization,
                body: nil
            )
            let page = try XGatewayResponseProjector.postPage(payload, options: options)
            return [operation.fieldName: try hydrateReplies(inPage: page, expansion: replyExpansion, authorization: authorization)]
        case .mentionsTimeline(let userId, let maxResults, let readOptions, let replyExpansion):
            let options = readOptions.withDefaultMediaRootDir(mediaRootDir)
            let payload = try performJSONRequest(
                method: "GET",
                url: try xAPIURL(
                    path: "/2/users/\(urlPathEscape(userId))/mentions",
                    query: timelineQueryItems(["max_results": String(maxResults)])
                ),
                authorization: authorization,
                body: nil
            )
            let page = try XGatewayResponseProjector.postPage(payload, options: options)
            return [operation.fieldName: try hydrateReplies(inPage: page, expansion: replyExpansion, authorization: authorization)]
        case .createPost(let text, let attachments):
            var body: [String: Any] = ["text": text]
            if let media = try buildTweetMediaPayload(attachments: attachments, authorization: authorization) {
                body["media"] = media
            }
            let payload = try performJSONRequest(
                method: "POST",
                url: try xAPIURL(path: "/2/tweets"),
                authorization: authorization,
                body: body
            )
            return [operation.fieldName: XGatewayResponseProjector.createdPost(payload)]
        case .deletePost(let postId):
            let payload = try performJSONRequest(
                method: "DELETE",
                url: try xAPIURL(path: "/2/tweets/\(urlPathEscape(postId))"),
                authorization: authorization,
                body: nil
            )
            return [operation.fieldName: XGatewayResponseProjector.deletedPost(postId: postId, payload)]
        case .replyToPost(let text, let replyToPostId, let attachments):
            var body: [String: Any] = [
                "text": text,
                "reply": ["in_reply_to_tweet_id": replyToPostId]
            ]
            if let media = try buildTweetMediaPayload(attachments: attachments, authorization: authorization) {
                body["media"] = media
            }
            let payload = try performJSONRequest(
                method: "POST",
                url: try xAPIURL(path: "/2/tweets"),
                authorization: authorization,
                body: body
            )
            return [operation.fieldName: XGatewayResponseProjector.createdPost(payload)]
        case .quotePost(let text, let quotedPostId, let attachments):
            var body: [String: Any] = [
                "text": text,
                "quote_tweet_id": quotedPostId
            ]
            if let media = try buildTweetMediaPayload(attachments: attachments, authorization: authorization) {
                body["media"] = media
            }
            let payload = try performJSONRequest(
                method: "POST",
                url: try xAPIURL(path: "/2/tweets"),
                authorization: authorization,
                body: body
            )
            return [operation.fieldName: XGatewayResponseProjector.createdPost(payload)]
        case .repostPost(let postId):
            let userId = try authenticatedUserId(authorization: authorization)
            let payload = try performJSONRequest(
                method: "POST",
                url: try xAPIURL(path: "/2/users/\(urlPathEscape(userId))/retweets"),
                authorization: authorization,
                body: ["tweet_id": postId]
            )
            return [operation.fieldName: XGatewayResponseProjector.repost(postId: postId, payload, defaultReposted: true)]
        case .unrepostPost(let postId):
            let userId = try authenticatedUserId(authorization: authorization)
            let payload = try performJSONRequest(
                method: "DELETE",
                url: try xAPIURL(path: "/2/users/\(urlPathEscape(userId))/retweets/\(urlPathEscape(postId))"),
                authorization: authorization,
                body: nil
            )
            return [operation.fieldName: XGatewayResponseProjector.repost(postId: postId, payload, defaultReposted: false)]
        }
    }

    private func hydrateReplies(
        in post: [String: Any],
        expansion: ReplyExpansionRequest?,
        authorization: XGatewayRequestAuthorization
    ) throws -> [String: Any] {
        return try hydrateReplies(in: post, expansion: expansion, authorization: authorization, state: ReplyExpansionState())
    }

    private func hydrateReplies(
        inPage page: [String: Any],
        expansion: ReplyExpansionRequest?,
        authorization: XGatewayRequestAuthorization
    ) throws -> [String: Any] {
        return try hydrateReplies(inPage: page, expansion: expansion, authorization: authorization, state: ReplyExpansionState())
    }

    private func hydrateReplies(
        inPage page: [String: Any],
        expansion: ReplyExpansionRequest?,
        authorization: XGatewayRequestAuthorization,
        state: ReplyExpansionState
    ) throws -> [String: Any] {
        guard let expansion else {
            return page
        }
        var hydrated = page
        var posts: [[String: Any]] = []
        for post in (page["posts"] as? [[String: Any]]) ?? [] {
            posts.append(try hydrateReplies(in: post, expansion: expansion, authorization: authorization, state: state))
        }
        hydrated["posts"] = posts
        return hydrated
    }

    private func hydrateReplies(
        in post: [String: Any],
        expansion: ReplyExpansionRequest?,
        authorization: XGatewayRequestAuthorization,
        state: ReplyExpansionState
    ) throws -> [String: Any] {
        guard let expansion else {
            return post
        }
        guard let postId = post["id"] as? String,
              !postId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw XGatewayErrorPayload(
                code: .internalError,
                summary: "Projected post is missing an id for reply lookup",
                details: "Nested Post.replies requires the parent post projection to include a stable string id.",
                likelyCauses: ["The upstream post payload did not project into the stable Post shape"],
                remediations: ["Retry without selecting Post.replies and inspect the parent post payload."],
                classification: "internal",
                retryable: false,
                traceId: traceId
            )
        }
        let safePostId = try validateReplyLookupPostId(postId)
        state.count += 1
        if state.count > maxReplyExpansions {
            throw validation("Public GraphQL selection 'Post.replies' exceeded the nested reply expansion limit of \(maxReplyExpansions) reply lookups in a single request. Reduce replies maxResults or nesting depth.")
        }

        var query: [String: String] = [
            "query": "in_reply_to_tweet_id:\(safePostId)",
            "max_results": String(expansion.maxResults)
        ]
        if let paginationToken = expansion.paginationToken {
            query["next_token"] = paginationToken
        }
        let payload = try performJSONRequest(
            method: "GET",
            url: try xAPIURL(path: "/2/tweets/search/recent", query: timelineQueryItems(query)),
            authorization: authorization,
            body: nil
        )
        let options = expansion.readOptions.withDefaultMediaRootDir(mediaRootDir)
        let repliesPage = try XGatewayResponseProjector.postPage(payload, options: options)
        var hydrated = post
        hydrated["replies"] = try hydrateReplies(
            inPage: repliesPage,
            expansion: expansion.child,
            authorization: authorization,
            state: state
        )
        return hydrated
    }

    private func followingTimeline(
        authorization: XGatewayRequestAuthorization,
        maxResults: Int,
        maxUsers: Int,
        maxResultsPerUser: Int
    ) throws -> [String: Any] {
        let userId = try authenticatedUserId(authorization: authorization)
        let followingPayload = try performJSONRequest(
            method: "GET",
            url: try xAPIURL(
                path: "/2/users/\(urlPathEscape(userId))/following",
                query: timelineQueryItems(["max_results": String(maxUsers)], includeTweetFields: false)
            ),
            authorization: authorization,
            body: nil
        )
        let followedUserIds = extractUserIds(followingPayload).prefix(maxUsers)
        var posts: [[String: Any]] = []
        var includes: [[String: Any]] = []

        for followedUserId in followedUserIds {
            let page = try performJSONRequest(
                method: "GET",
                url: try xAPIURL(
                    path: "/2/users/\(urlPathEscape(followedUserId))/tweets",
                    query: timelineQueryItems(["max_results": String(maxResultsPerUser)], includeOwnerMetrics: false)
                ),
                authorization: authorization,
                body: nil
            )
            if let root = page as? [String: Any] {
                posts.append(contentsOf: (root["data"] as? [[String: Any]]) ?? [])
                if let pageIncludes = root["includes"] as? [String: Any] {
                    includes.append(pageIncludes)
                }
            }
        }

        posts.sort { left, right in
            let leftCreatedAt = (left["created_at"] as? String) ?? ""
            let rightCreatedAt = (right["created_at"] as? String) ?? ""
            return leftCreatedAt > rightCreatedAt
        }

        var result: [String: Any] = [
            "data": Array(posts.prefix(maxResults)),
            "meta": [
                "result_count": min(posts.count, maxResults)
            ]
        ]
        if !includes.isEmpty {
            result["includes"] = mergeIncludes(includes)
        }
        return result
    }

    private func authenticatedUserId(authorization: XGatewayRequestAuthorization) throws -> String {
        let payload = try performJSONRequest(
            method: "GET",
            url: try xAPIURL(path: "/2/users/me", query: queryItems(["user.fields": "id"])),
            authorization: authorization,
            body: nil
        )
        guard let root = payload as? [String: Any],
              let data = root["data"] as? [String: Any],
              let id = data["id"] as? String,
              !id.isEmpty else {
            throw XGatewayErrorPayload(
                code: .upstreamFailure,
                summary: "Authenticated user id was missing",
                details: "The Swift repost adapter could not read data.id from GET /2/users/me.",
                likelyCauses: ["Unexpected X API response shape", "Bearer token is not user-context capable"],
                remediations: ["Verify X_GW_TOKEN user context and retry.", "Inspect the upstream user lookup response."],
                classification: "upstream",
                retryable: false,
                traceId: traceId
            )
        }
        return id
    }

    private func buildTweetMediaPayload(
        attachments: [PostAttachmentInput]?,
        authorization: XGatewayRequestAuthorization
    ) throws -> [String: Any]? {
        guard let attachments,
              !attachments.isEmpty else {
            return nil
        }
        guard case .oauth1 = authorization else {
            throw XGatewayErrorPayload(
                code: .authMissing,
                summary: "OAuth1 authentication configuration missing",
                details: "Attachment-backed Swift posting requires OAuth1 because media upload is not available through the bearer-token baseline.",
                likelyCauses: ["Attachment-backed posting was requested without complete OAuth1 credentials"],
                remediations: [
                    "Set X_GW_CONSUMER_KEY, X_GW_CONSUMER_SECRET, X_GW_ACCESS_TOKEN, and X_GW_ACCESS_TOKEN_SECRET.",
                    "Retry without attachments if text-only bearer-token posting is sufficient."
                ],
                classification: "auth",
                retryable: false,
                traceId: traceId
            )
        }

        var mediaIds: [String] = []
        mediaIds.reserveCapacity(attachments.count)
        for attachment in attachments {
            let mediaId = try uploadImageAttachment(attachment, authorization: authorization)
            if let altText = attachment.altText {
                try createMediaMetadata(mediaId: mediaId, altText: altText, authorization: authorization)
            }
            mediaIds.append(mediaId)
        }
        return ["media_ids": mediaIds]
    }

    private func uploadImageAttachment(
        _ attachment: PostAttachmentInput,
        authorization: XGatewayRequestAuthorization
    ) throws -> String {
        let media = try readAttachmentData(attachment)
        let mediaType = mimeType(for: attachment.filePath)
        let mediaCategory = mediaCategory(for: mediaType)
        let uploadURL = try xUploadURL()
        let initPayload = try performFormRequest(
            method: "POST",
            url: uploadURL,
            authorization: authorization,
            parameters: [
                ("command", "INIT"),
                ("total_bytes", String(media.count)),
                ("media_type", mediaType),
                ("media_category", mediaCategory)
            ]
        )
        let mediaId = try extractMediaId(from: initPayload)
        let chunkSize = 1_024 * 1_024
        var offset = 0
        var segmentIndex = 0
        while offset < media.count {
            let end = min(offset + chunkSize, media.count)
            let chunk = media.subdata(in: offset..<end)
            _ = try performMultipartRequest(
                method: "POST",
                url: uploadURL,
                authorization: authorization,
                parts: [
                    .field(name: "command", value: "APPEND"),
                    .field(name: "media_id", value: mediaId),
                    .field(name: "segment_index", value: String(segmentIndex)),
                    .file(name: "media", filename: URL(fileURLWithPath: attachment.filePath).lastPathComponent, mimeType: mediaType, data: chunk)
                ]
            )
            offset = end
            segmentIndex += 1
        }

        let finalizePayload = try performFormRequest(
            method: "POST",
            url: uploadURL,
            authorization: authorization,
            parameters: [
                ("command", "FINALIZE"),
                ("media_id", mediaId)
            ]
        )
        try ensureMediaProcessingComplete(mediaId: mediaId, payload: finalizePayload, authorization: authorization)
        return mediaId
    }

    private func createMediaMetadata(
        mediaId: String,
        altText: String,
        authorization: XGatewayRequestAuthorization
    ) throws {
        _ = try performJSONRequest(
            method: "POST",
            url: try xUploadURL(path: "/1.1/media/metadata/create.json"),
            authorization: authorization,
            body: [
                "media_id": mediaId,
                "alt_text": ["text": altText]
            ]
        )
    }

    private func readAttachmentData(_ attachment: PostAttachmentInput) throws -> Data {
        let expandedPath = NSString(string: attachment.filePath).expandingTildeInPath
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: expandedPath, isDirectory: &isDirectory),
              !isDirectory.boolValue else {
            throw validation("attachments.filePath must point to a readable image file.")
        }
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: expandedPath), options: [.mappedIfSafe])
            guard !data.isEmpty else {
                throw validation("attachments.filePath must point to a non-empty image file.")
            }
            return data
        } catch let error as XGatewayErrorPayload {
            throw error
        } catch {
            throw validation("attachments.filePath could not be read: \(error.localizedDescription)")
        }
    }

    private func mimeType(for filePath: String) -> String {
        switch URL(fileURLWithPath: filePath).pathExtension.lowercased() {
        case "png":
            return "image/png"
        case "webp":
            return "image/webp"
        case "gif":
            return "image/gif"
        default:
            return "image/jpeg"
        }
    }

    private func mediaCategory(for mediaType: String) -> String {
        if mediaType == "image/gif" {
            return "TweetGif"
        }
        return "TweetImage"
    }

    private func extractMediaId(from payload: Any) throws -> String {
        guard let root = payload as? [String: Any] else {
            throw XGatewayErrorPayload(
                code: .upstreamFailure,
                summary: "Media upload response was invalid",
                details: "The Swift media upload adapter expected an object response.",
                likelyCauses: ["Unexpected X media upload response shape"],
                remediations: ["Retry and inspect upstream media upload diagnostics if the issue persists."],
                classification: "upstream",
                retryable: false,
                traceId: traceId
            )
        }
        if let mediaId = root["media_id_string"] as? String,
           !mediaId.isEmpty {
            return mediaId
        }
        if let mediaId = root["media_id"] {
            return String(describing: mediaId)
        }
        throw XGatewayErrorPayload(
            code: .upstreamFailure,
            summary: "Media id was missing",
            details: "The Swift media upload adapter could not read media_id_string from the upload response.",
            likelyCauses: ["Unexpected X media upload response shape"],
            remediations: ["Retry and inspect upstream media upload diagnostics if the issue persists."],
            classification: "upstream",
            retryable: false,
            traceId: traceId
        )
    }

    private func ensureMediaProcessingComplete(
        mediaId: String,
        payload: Any,
        authorization: XGatewayRequestAuthorization
    ) throws {
        var currentPayload = payload
        for _ in 0..<10 {
            guard let processingInfo = processingInfo(from: currentPayload),
                  let state = processingInfo["state"] as? String else {
                return
            }
            if state == "succeeded" {
                return
            }
            if state == "failed" {
                throw XGatewayErrorPayload(
                    code: .upstreamFailure,
                    summary: "Media processing failed",
                    details: jsonString(processingInfo, pretty: false),
                    likelyCauses: ["X media processing rejected the uploaded file"],
                    remediations: ["Verify the image file format and retry with a supported file."],
                    classification: "upstream",
                    retryable: false,
                    traceId: traceId
                )
            }
            let waitSeconds = max(1, min(mediaProcessingIntValue(processingInfo["check_after_secs"]), 5))
            Thread.sleep(forTimeInterval: TimeInterval(waitSeconds))
            currentPayload = try performJSONRequest(
                method: "GET",
                url: try xUploadURL(query: queryItems(["command": "STATUS", "media_id": mediaId])),
                authorization: authorization,
                body: nil
            )
        }
        throw XGatewayErrorPayload(
            code: .upstreamFailure,
            summary: "Media processing did not finish",
            details: "The Swift media upload adapter timed out while waiting for media id \(mediaId).",
            likelyCauses: ["X media processing is still pending"],
            remediations: ["Retry the request later.", "Use a smaller supported image file if processing repeatedly times out."],
            classification: "upstream",
            retryable: true,
            traceId: traceId
        )
    }

    private func processingInfo(from payload: Any) -> [String: Any]? {
        guard let root = payload as? [String: Any] else {
            return nil
        }
        return root["processing_info"] as? [String: Any]
    }

    private func performJSONRequest(
        method: String,
        url: URL,
        authorization: XGatewayRequestAuthorization,
        body: [String: Any]?
    ) throws -> Any {
        return try performRequestWithRetry {
            try performSingleJSONRequest(method: method, url: url, authorization: authorization, body: body)
        }
    }

    private func performFormRequest(
        method: String,
        url: URL,
        authorization: XGatewayRequestAuthorization,
        parameters: [(String, String)]
    ) throws -> Any {
        return try performRequestWithRetry {
            let body = formURLEncodedData(parameters)
            return try performSingleRequest(
                method: method,
                url: url,
                authorization: authorization,
                contentType: "application/x-www-form-urlencoded",
                body: body,
                signatureParameters: parameters
            )
        }
    }

    private func performMultipartRequest(
        method: String,
        url: URL,
        authorization: XGatewayRequestAuthorization,
        parts: [MultipartPart]
    ) throws -> Any {
        return try performRequestWithRetry {
            let boundary = "x-gateway-\(UUID().uuidString)"
            let body = multipartData(parts: parts, boundary: boundary)
            return try performSingleRequest(
                method: method,
                url: url,
                authorization: authorization,
                contentType: "multipart/form-data; boundary=\(boundary)",
                body: body,
                signatureParameters: []
            )
        }
    }

    private func performRequestWithRetry(_ perform: () throws -> Any) throws -> Any {
        var attempt = 0
        while true {
            do {
                return try perform()
            } catch let error as XGatewayErrorPayload {
                guard error.retryable,
                      attempt < transport.retryCount else {
                    throw error
                }
                sleepBeforeRetry(attempt: attempt)
                attempt += 1
            }
        }
    }

    private func performSingleJSONRequest(
        method: String,
        url: URL,
        authorization: XGatewayRequestAuthorization,
        body: [String: Any]?
    ) throws -> Any {
        let bodyData: Data?
        if let body {
            bodyData = try JSONSerialization.data(withJSONObject: body, options: [])
        } else {
            bodyData = nil
        }
        return try performSingleRequest(
            method: method,
            url: url,
            authorization: authorization,
            contentType: body == nil ? nil : "application/json",
            body: bodyData,
            signatureParameters: []
        )
    }

    private func performSingleRequest(
        method: String,
        url: URL,
        authorization: XGatewayRequestAuthorization,
        contentType: String?,
        body: Data?,
        signatureParameters: [(String, String)]
    ) throws -> Any {
        var request = URLRequest(url: url)
        request.httpMethod = method
        applyAuthorizationHeader(
            to: &request,
            method: method,
            url: url,
            authorization: authorization,
            signatureParameters: signatureParameters
        )
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let contentType {
            request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        }
        request.httpBody = body

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = transport.timeoutSeconds
        configuration.timeoutIntervalForResource = transport.timeoutSeconds
        let session = URLSession(configuration: configuration)
        let semaphore = DispatchSemaphore(value: 0)
        var result: Result<(Data, URLResponse), Error>?
        let task = session.dataTask(with: request) { data, response, error in
            if let error {
                result = .failure(error)
            } else {
                result = .success((data ?? Data(), response ?? URLResponse()))
            }
            semaphore.signal()
        }
        task.resume()
        let waitResult = semaphore.wait(timeout: .now() + .milliseconds(max(1, transport.timeoutMs) + 1_000))
        if waitResult == .timedOut {
            task.cancel()
            session.invalidateAndCancel()
            throw XGatewayErrorPayload(
                code: .networkFailure,
                summary: "Network request timed out",
                details: "No response was received within \(transport.timeoutMs)ms.",
                likelyCauses: ["Temporary connectivity loss", "X API did not respond before the configured timeout"],
                remediations: ["Retry with a larger --timeout-ms value", "Check network connectivity and DNS"],
                classification: "network",
                retryable: true,
                traceId: traceId
            )
        }
        session.finishTasksAndInvalidate()

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try result?.get() ?? (Data(), URLResponse())
        } catch {
            throw XGatewayErrorPayload(
                code: .networkFailure,
                summary: "Network request failed",
                details: error.localizedDescription,
                likelyCauses: ["DNS or connection issue", "Temporary connectivity loss", "Timeout while calling X API"],
                remediations: ["Retry with backoff", "Check network connectivity and DNS"],
                classification: "network",
                retryable: true,
                traceId: traceId
            )
        }

        guard let http = response as? HTTPURLResponse else {
            throw XGatewayErrorPayload(
                code: .upstreamFailure,
                summary: "X API returned an invalid response",
                details: "The Swift transport did not receive an HTTP response.",
                likelyCauses: ["Unexpected URLSession response type"],
                remediations: ["Retry and inspect transport diagnostics if the issue persists."],
                classification: "upstream",
                retryable: true,
                traceId: traceId
            )
        }

        let parsed = try parseJSON(data: data)
        if (200...299).contains(http.statusCode) {
            return parsed
        }
        throw mapHTTPError(statusCode: http.statusCode, payload: parsed)
    }

    private func applyAuthorizationHeader(
        to request: inout URLRequest,
        method: String,
        url: URL,
        authorization: XGatewayRequestAuthorization,
        signatureParameters: [(String, String)]
    ) {
        switch authorization {
        case .bearer(let token):
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        case .oauth1(let credentials):
            request.setValue(
                XGatewayOAuth1Signer.authorizationHeader(
                    method: method,
                    url: url,
                    credentials: credentials,
                    queryParameters: signatureParameters
                ),
                forHTTPHeaderField: "Authorization"
            )
        }
    }

    private func sleepBeforeRetry(attempt: Int) {
        let delayMs: Int
        switch transport.retryBackoff {
        case "none":
            delayMs = 0
        case "fixed":
            delayMs = transport.retryBaseMs
        default:
            let exponent = min(attempt, 10)
            let uncapped = transport.retryBaseMs * (1 << exponent)
            let capped = min(uncapped, transport.retryMaxMs)
            delayMs = capped == 0 ? 0 : Int(Double(capped) * Double.random(in: 0.5...1.0))
        }
        if delayMs > 0 {
            Thread.sleep(forTimeInterval: TimeInterval(delayMs) / 1_000)
        }
    }

    private func parseJSON(data: Data) throws -> Any {
        if data.isEmpty {
            return [:] as [String: Any]
        }
        do {
            return try JSONSerialization.jsonObject(with: data, options: [])
        } catch {
            throw XGatewayErrorPayload(
                code: .upstreamFailure,
                summary: "X API returned malformed JSON",
                details: error.localizedDescription,
                likelyCauses: ["Unexpected upstream response body", "Proxy or network middleware returned non-JSON content"],
                remediations: ["Inspect the upstream response and retry after confirming the endpoint."],
                classification: "upstream",
                retryable: false,
                traceId: traceId
            )
        }
    }

    private func mapHTTPError(statusCode: Int, payload: Any) -> XGatewayErrorPayload {
        let detail = jsonString(payload, pretty: false)
        if statusCode == 401 {
            return XGatewayErrorPayload(
                code: .authInvalid,
                summary: "Authentication failed",
                details: detail,
                likelyCauses: ["Bearer token is invalid, expired, revoked, or not user-context capable"],
                remediations: ["Re-issue X_GW_TOKEN and retry", "Confirm token/app pairing and auth mode"],
                classification: "auth",
                retryable: false,
                traceId: traceId
            )
        }
        if statusCode == 403 {
            return XGatewayErrorPayload(
                code: .permissionDenied,
                summary: "Authorization failed",
                details: detail,
                likelyCauses: ["Token lacks required scope", "X API plan or app settings do not permit this operation"],
                remediations: ["Grant required read/write scope", "Use credentials for an app with the required access"],
                classification: "permission",
                retryable: false,
                traceId: traceId
            )
        }
        if statusCode == 404 {
            return XGatewayErrorPayload(
                code: .resourceNotFound,
                summary: "Requested resource was not found",
                details: detail,
                likelyCauses: ["Resource id is invalid", "Resource is deleted or inaccessible"],
                remediations: ["Verify the resource identifier", "Check resource visibility"],
                classification: "upstream",
                retryable: false,
                traceId: traceId
            )
        }
        if statusCode == 429 {
            return XGatewayErrorPayload(
                code: .rateLimited,
                summary: "Rate limit exceeded",
                details: detail,
                likelyCauses: ["Too many requests in current window", "Quota exhausted"],
                remediations: ["Retry after the rate-limit window", "Lower request frequency"],
                classification: "rate_limit",
                retryable: true,
                traceId: traceId
            )
        }
        return XGatewayErrorPayload(
            code: .upstreamFailure,
            summary: "X API returned an error",
            details: detail,
            likelyCauses: ["API credentials are missing required access", "Requested operation is blocked by account/app settings"],
            remediations: ["Verify credential scopes and X app permissions", "Review X developer portal app/token status"],
            classification: "upstream",
            retryable: statusCode >= 500,
            traceId: traceId
        )
    }
}
