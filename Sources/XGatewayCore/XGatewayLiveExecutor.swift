import Foundation

enum XGatewayRequestAuthorization {
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
    let appToken: String?
    let oauth1Credentials: XGatewayOAuth1SigningCredentials?
    let mediaRootDir: String?
    let traceId: String?
    let transport: TransportSettings
}

enum XGatewayRetryPolicy {
    static func automaticRetryCount(forHTTPMethod method: String, configuredRetryCount: Int) -> Int {
        let normalizedMethod = method.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard normalizedMethod == "GET" else {
            return 0
        }
        return max(0, configuredRetryCount)
    }
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
        if operation.prefersBearerAuthorization,
           let token,
           !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .bearer(token)
        }
        if operation.prefersAppOnlyAuthorization {
            return try requireAppBearerAuthorization(operation: operation)
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

    private func requireAppBearerAuthorization(operation: SupportedGraphQLOperation) throws -> XGatewayRequestAuthorization {
        if let appToken,
           !appToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .bearer(appToken.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        if let token,
           !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .bearer(token.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        throw XGatewayErrorPayload(
            code: .authMissing,
            summary: "Authentication configuration missing",
            details: "\(operation.fieldName) requires X_GW_APP_TOKEN, X_GW_TOKEN, or --token for the current Swift transport slice.",
            likelyCauses: [
                "No app-only bearer token was configured",
                "No fallback bearer token was configured"
            ],
            remediations: [
                "Set X_GW_APP_TOKEN to an app-only bearer token for public app-context X endpoints.",
                "Use --token for one-off app-only endpoint verification."
            ],
            classification: "auth",
            retryable: false,
            traceId: traceId
        )
    }

    private func execute(operation: SupportedGraphQLOperation, authorization: XGatewayRequestAuthorization) throws -> [String: Any] {
        if let response = try executeOpenAPIParityOperation(operation: operation, authorization: authorization) {
            return response
        }
        if let response = try executeMCPParityOperation(operation: operation, authorization: authorization) {
            return response
        }
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
        default:
            throw XGatewayErrorPayload(
                code: .internalError,
                summary: "Swift GraphQL operation dispatch failed",
                details: "Operation \(operation.fieldName) passed validation but did not match a reviewed executor branch.",
                likelyCauses: ["The operation parser and executor dispatch table are out of sync"],
                remediations: ["Add the missing Swift executor branch for \(operation.fieldName)."],
                classification: "internal",
                retryable: false,
                traceId: traceId
            )
        }
    }

    func hydrateReplies(
        in post: [String: Any],
        expansion: ReplyExpansionRequest?,
        authorization: XGatewayRequestAuthorization
    ) throws -> [String: Any] {
        return try hydrateReplies(in: post, expansion: expansion, authorization: authorization, state: ReplyExpansionState())
    }

    func hydrateReplies(
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

    private func buildTweetMediaPayload(
        attachments: [PostAttachmentInput]?,
        authorization: XGatewayRequestAuthorization
    ) throws -> [String: Any]? {
        try tweetMediaPayload(attachments: attachments, authorization: authorization)
    }

    func performJSONRequest(
        method: String,
        url: URL,
        authorization: XGatewayRequestAuthorization,
        body: [String: Any]?
    ) throws -> Any {
        return try performRequestWithRetry(method: method) {
            try performSingleJSONRequest(method: method, url: url, authorization: authorization, body: body)
        }
    }

    func performFormRequest(
        method: String,
        url: URL,
        authorization: XGatewayRequestAuthorization,
        parameters: [(String, String)]
    ) throws -> Any {
        return try performRequestWithRetry(method: method) {
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

    func performMultipartRequest(
        method: String,
        url: URL,
        authorization: XGatewayRequestAuthorization,
        parts: [MultipartPart]
    ) throws -> Any {
        return try performRequestWithRetry(method: method) {
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

    func performBinaryDownloadRequest(
        method: String,
        url: URL,
        authorization: XGatewayRequestAuthorization
    ) throws -> (data: Data, contentType: String?) {
        return try performRequestWithRetry(method: method) {
            try performSingleBinaryDownloadRequest(method: method, url: url, authorization: authorization)
        }
    }

    private func performRequestWithRetry<T>(method: String, _ perform: () throws -> T) throws -> T {
        let retryCount = XGatewayRetryPolicy.automaticRetryCount(
            forHTTPMethod: method,
            configuredRetryCount: transport.retryCount
        )
        var attempt = 0
        while true {
            do {
                return try perform()
            } catch let error as XGatewayErrorPayload {
                guard error.retryable,
                      attempt < retryCount else {
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

    private func performSingleBinaryDownloadRequest(
        method: String,
        url: URL,
        authorization: XGatewayRequestAuthorization
    ) throws -> (Data, String?) {
        var request = URLRequest(url: url)
        request.httpMethod = method
        applyAuthorizationHeader(to: &request, method: method, url: url, authorization: authorization, signatureParameters: [])
        request.setValue("application/octet-stream", forHTTPHeaderField: "Accept")

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
        if (200...299).contains(http.statusCode) {
            return (data, http.value(forHTTPHeaderField: "Content-Type"))
        }
        let parsed = (try? parseJSON(data: data)) ?? ["rawBodyByteCount": data.count]
        throw mapHTTPError(statusCode: http.statusCode, payload: parsed)
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

    func applyAuthorizationHeader(
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

    func mapHTTPError(statusCode: Int, payload: Any) -> XGatewayErrorPayload {
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
