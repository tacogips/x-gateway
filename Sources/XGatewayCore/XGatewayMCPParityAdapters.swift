import Foundation

extension XGatewayLiveExecutor {
    func executeMCPParityOperation(
        operation: SupportedGraphQLOperation,
        authorization: XGatewayRequestAuthorization
    ) throws -> [String: Any]? {
        switch operation {
        case .user(let userId):
            return [operation.fieldName: try user(userId: userId, authorization: authorization)]
        case .userByUsername(let username):
            return [operation.fieldName: try userByUsername(username: username, authorization: authorization)]
        case .followers(let userId, let maxResults, let paginationToken):
            return [operation.fieldName: try followers(userId: userId, maxResults: maxResults, paginationToken: paginationToken, authorization: authorization)]
        case .following(let userId, let maxResults, let paginationToken):
            return [operation.fieldName: try following(userId: userId, maxResults: maxResults, paginationToken: paginationToken, authorization: authorization)]
        case .postLikingUsers(let postId, let maxResults, let paginationToken):
            return [operation.fieldName: try postLikingUsers(postId: postId, maxResults: maxResults, paginationToken: paginationToken, authorization: authorization)]
        case .postRepostingUsers(let postId, let maxResults, let paginationToken):
            return [operation.fieldName: try postRepostingUsers(postId: postId, maxResults: maxResults, paginationToken: paginationToken, authorization: authorization)]
        case .postQuotes(let postId, let maxResults, let paginationToken, let readOptions, let replyExpansion):
            let page = try postQuotes(
                postId: postId,
                maxResults: maxResults,
                paginationToken: paginationToken,
                readOptions: readOptions.withDefaultMediaRootDir(mediaRootDir),
                authorization: authorization
            )
            return [operation.fieldName: try hydrateReplies(inPage: page, expansion: replyExpansion, authorization: authorization)]
        case .recentPostCounts(let query, let options):
            return [operation.fieldName: try recentPostCounts(query: query, options: options, authorization: authorization)]
        case .searchAllPosts(let query, let options, let readOptions, let replyExpansion):
            let page = try searchAllPosts(
                query: query,
                options: options,
                readOptions: readOptions.withDefaultMediaRootDir(mediaRootDir),
                authorization: authorization
            )
            return [operation.fieldName: try hydrateReplies(inPage: page, expansion: replyExpansion, authorization: authorization)]
        case .searchUsers(let query, let maxResults, let nextToken):
            return [operation.fieldName: try searchUsers(query: query, maxResults: maxResults, nextToken: nextToken, authorization: authorization)]
        case .searchNews(let query, let maxResults, let maxAgeHours):
            return [operation.fieldName: try searchNews(query: query, maxResults: maxResults, maxAgeHours: maxAgeHours, authorization: authorization)]
        case .news(let id):
            return [operation.fieldName: try news(id: id, authorization: authorization)]
        case .trendsByWoeid(let woeid, let maxTrends):
            return [operation.fieldName: try trendsByWoeid(woeid: woeid, maxTrends: maxTrends, authorization: authorization)]
        case .bookmarks(let maxResults, let paginationToken, let readOptions, let replyExpansion):
            let page = try bookmarks(
                maxResults: maxResults,
                paginationToken: paginationToken,
                readOptions: readOptions.withDefaultMediaRootDir(mediaRootDir),
                authorization: authorization
            )
            return [operation.fieldName: try hydrateReplies(inPage: page, expansion: replyExpansion, authorization: authorization)]
        case .bookmarkFolders(let maxResults, let paginationToken):
            return [operation.fieldName: try bookmarkFolders(maxResults: maxResults, paginationToken: paginationToken, authorization: authorization)]
        case .bookmarksByFolder(let folderId, let readOptions, let replyExpansion):
            let page = try bookmarksByFolder(
                folderId: folderId,
                readOptions: readOptions.withDefaultMediaRootDir(mediaRootDir),
                authorization: authorization
            )
            return [operation.fieldName: try hydrateReplies(inPage: page, expansion: replyExpansion, authorization: authorization)]
        case .bookmarkPost(let postId):
            return [operation.fieldName: try bookmarkPost(postId: postId, authorization: authorization)]
        case .removeBookmark(let postId):
            return [operation.fieldName: try removeBookmark(postId: postId, authorization: authorization)]
        case .createArticleDraft(let title, let text):
            return [operation.fieldName: try createArticleDraft(title: title, text: text, authorization: authorization)]
        case .publishArticle(let articleId):
            return [operation.fieldName: try publishArticle(articleId: articleId, authorization: authorization)]
        default:
            return try executeExtendedParityOperation(operation: operation, authorization: authorization)
        }
    }

    func user(userId: String, authorization: XGatewayRequestAuthorization) throws -> [String: Any] {
        let payload = try performJSONRequest(
            method: "GET",
            url: try xAPIURL(path: "/2/users/\(urlPathEscape(userId))", query: userLookupQuery),
            authorization: authorization,
            body: nil
        )
        return XGatewayResponseProjector.user(payload)
    }

    func userByUsername(username: String, authorization: XGatewayRequestAuthorization) throws -> [String: Any] {
        let payload = try performJSONRequest(
            method: "GET",
            url: try xAPIURL(path: "/2/users/by/username/\(urlPathEscape(username))", query: userLookupQuery),
            authorization: authorization,
            body: nil
        )
        return XGatewayResponseProjector.user(payload)
    }

    func followers(
        userId: String,
        maxResults: Int,
        paginationToken: String?,
        authorization: XGatewayRequestAuthorization
    ) throws -> [String: Any] {
        let payload = try performJSONRequest(
            method: "GET",
            url: try xAPIURL(
                path: "/2/users/\(urlPathEscape(userId))/followers",
                query: userPageQuery(maxResults: maxResults, paginationToken: paginationToken)
            ),
            authorization: authorization,
            body: nil
        )
        return XGatewayResponseProjector.userPage(payload)
    }

    func following(
        userId: String,
        maxResults: Int,
        paginationToken: String?,
        authorization: XGatewayRequestAuthorization
    ) throws -> [String: Any] {
        let payload = try performJSONRequest(
            method: "GET",
            url: try xAPIURL(
                path: "/2/users/\(urlPathEscape(userId))/following",
                query: userPageQuery(maxResults: maxResults, paginationToken: paginationToken)
            ),
            authorization: authorization,
            body: nil
        )
        return XGatewayResponseProjector.userPage(payload)
    }

    func postLikingUsers(
        postId: String,
        maxResults: Int,
        paginationToken: String?,
        authorization: XGatewayRequestAuthorization
    ) throws -> [String: Any] {
        let payload = try performJSONRequest(
            method: "GET",
            url: try xAPIURL(
                path: "/2/tweets/\(urlPathEscape(postId))/liking_users",
                query: userPageQuery(maxResults: maxResults, paginationToken: paginationToken)
            ),
            authorization: authorization,
            body: nil
        )
        return XGatewayResponseProjector.userPage(payload)
    }

    func postRepostingUsers(
        postId: String,
        maxResults: Int,
        paginationToken: String?,
        authorization: XGatewayRequestAuthorization
    ) throws -> [String: Any] {
        let payload = try performJSONRequest(
            method: "GET",
            url: try xAPIURL(
                path: "/2/tweets/\(urlPathEscape(postId))/retweeted_by",
                query: userPageQuery(maxResults: maxResults, paginationToken: paginationToken)
            ),
            authorization: authorization,
            body: nil
        )
        return XGatewayResponseProjector.userPage(payload)
    }

    func postQuotes(
        postId: String,
        maxResults: Int,
        paginationToken: String?,
        readOptions: XGatewayPostReadOptions,
        authorization: XGatewayRequestAuthorization
    ) throws -> [String: Any] {
        let payload = try performJSONRequest(
            method: "GET",
            url: try xAPIURL(
                path: "/2/tweets/\(urlPathEscape(postId))/quote_tweets",
                query: postPageQuery(maxResults: maxResults, paginationToken: paginationToken)
            ),
            authorization: authorization,
            body: nil
        )
        return try XGatewayResponseProjector.postPage(payload, options: readOptions)
    }

    func recentPostCounts(
        query: String,
        options: PostCountsRequestOptions,
        authorization: XGatewayRequestAuthorization
    ) throws -> [String: Any] {
        var parameters: [String: String] = [
            "query": query,
            "granularity": options.granularity
        ]
        copyIfPresent(options.startTime, to: "start_time", into: &parameters)
        copyIfPresent(options.endTime, to: "end_time", into: &parameters)
        copyIfPresent(options.sinceId, to: "since_id", into: &parameters)
        copyIfPresent(options.untilId, to: "until_id", into: &parameters)
        copyIfPresent(options.nextToken, to: "next_token", into: &parameters)
        copyIfPresent(options.paginationToken, to: "pagination_token", into: &parameters)
        let payload = try performJSONRequest(
            method: "GET",
            url: try xAPIURL(path: "/2/tweets/counts/recent", query: queryItems(parameters)),
            authorization: authorization,
            body: nil
        )
        return XGatewayResponseProjector.postCounts(payload)
    }

    func searchAllPosts(
        query: String,
        options: SearchAllPostsRequestOptions,
        readOptions: XGatewayPostReadOptions,
        authorization: XGatewayRequestAuthorization
    ) throws -> [String: Any] {
        var parameters: [String: String] = [
            "query": query,
            "max_results": String(options.maxResults)
        ]
        copyIfPresent(options.startTime, to: "start_time", into: &parameters)
        copyIfPresent(options.endTime, to: "end_time", into: &parameters)
        copyIfPresent(options.sinceId, to: "since_id", into: &parameters)
        copyIfPresent(options.untilId, to: "until_id", into: &parameters)
        copyIfPresent(options.nextToken, to: "next_token", into: &parameters)
        copyIfPresent(options.paginationToken, to: "pagination_token", into: &parameters)
        copyIfPresent(options.sortOrder, to: "sort_order", into: &parameters)
        let payload = try performJSONRequest(
            method: "GET",
            url: try xAPIURL(path: "/2/tweets/search/all", query: timelineQueryItems(parameters)),
            authorization: authorization,
            body: nil
        )
        return try XGatewayResponseProjector.postPage(payload, options: readOptions)
    }

    func searchUsers(
        query: String,
        maxResults: Int,
        nextToken: String?,
        authorization: XGatewayRequestAuthorization
    ) throws -> [String: Any] {
        var parameters: [String: String] = [
            "query": query,
            "max_results": String(maxResults)
        ]
        copyIfPresent(nextToken, to: "next_token", into: &parameters)
        let payload = try performJSONRequest(
            method: "GET",
            url: try xAPIURL(path: "/2/users/search", query: userPageQueryItems(parameters)),
            authorization: authorization,
            body: nil
        )
        return XGatewayResponseProjector.userPage(payload)
    }

    func searchNews(
        query: String,
        maxResults: Int,
        maxAgeHours: Int,
        authorization: XGatewayRequestAuthorization
    ) throws -> [String: Any] {
        let payload = try performJSONRequest(
            method: "GET",
            url: try xAPIURL(path: "/2/news/search", query: newsQueryItems([
                "query": query,
                "max_results": String(maxResults),
                "max_age_hours": String(maxAgeHours)
            ])),
            authorization: authorization,
            body: nil
        )
        return XGatewayResponseProjector.newsPage(payload)
    }

    func news(id: String, authorization: XGatewayRequestAuthorization) throws -> [String: Any] {
        let payload = try performJSONRequest(
            method: "GET",
            url: try xAPIURL(path: "/2/news/\(urlPathEscape(id))", query: newsQueryItems([:])),
            authorization: authorization,
            body: nil
        )
        return XGatewayResponseProjector.news(payload)
    }

    func trendsByWoeid(
        woeid: Int,
        maxTrends: Int,
        authorization: XGatewayRequestAuthorization
    ) throws -> [String: Any] {
        let payload = try performJSONRequest(
            method: "GET",
            url: try xAPIURL(
                path: "/2/trends/by/woeid/\(woeid)",
                query: queryItems(["max_trends": String(maxTrends), "trend.fields": "trend_name,tweet_count"])
            ),
            authorization: authorization,
            body: nil
        )
        return XGatewayResponseProjector.trendPage(payload)
    }

    func bookmarks(
        maxResults: Int,
        paginationToken: String?,
        readOptions: XGatewayPostReadOptions,
        authorization: XGatewayRequestAuthorization
    ) throws -> [String: Any] {
        let userId = try authenticatedUserId(authorization: authorization)
        let payload = try performJSONRequest(
            method: "GET",
            url: try xAPIURL(
                path: "/2/users/\(urlPathEscape(userId))/bookmarks",
                query: postPageQuery(maxResults: maxResults, paginationToken: paginationToken)
            ),
            authorization: authorization,
            body: nil
        )
        return try XGatewayResponseProjector.postPage(payload, options: readOptions)
    }

    func bookmarkFolders(
        maxResults: Int,
        paginationToken: String?,
        authorization: XGatewayRequestAuthorization
    ) throws -> [String: Any] {
        let userId = try authenticatedUserId(authorization: authorization)
        var parameters: [String: String] = ["max_results": String(maxResults)]
        copyIfPresent(paginationToken, to: "pagination_token", into: &parameters)
        let payload = try performJSONRequest(
            method: "GET",
            url: try xAPIURL(
                path: "/2/users/\(urlPathEscape(userId))/bookmarks/folders",
                query: queryItems(parameters)
            ),
            authorization: authorization,
            body: nil
        )
        return XGatewayResponseProjector.bookmarkFolderPage(payload)
    }

    func bookmarksByFolder(
        folderId: String,
        readOptions: XGatewayPostReadOptions,
        authorization: XGatewayRequestAuthorization
    ) throws -> [String: Any] {
        let userId = try authenticatedUserId(authorization: authorization)
        let payload = try performJSONRequest(
            method: "GET",
            url: try xAPIURL(
                path: "/2/users/\(urlPathEscape(userId))/bookmarks/folders/\(urlPathEscape(folderId))",
                query: timelineQueryItems([:])
            ),
            authorization: authorization,
            body: nil
        )
        return try XGatewayResponseProjector.postPage(payload, options: readOptions)
    }

    func bookmarkPost(postId: String, authorization: XGatewayRequestAuthorization) throws -> [String: Any] {
        let userId = try authenticatedUserId(authorization: authorization)
        let payload = try performJSONRequest(
            method: "POST",
            url: try xAPIURL(path: "/2/users/\(urlPathEscape(userId))/bookmarks"),
            authorization: authorization,
            body: ["tweet_id": postId]
        )
        return XGatewayResponseProjector.bookmark(postId: postId, payload, defaultBookmarked: true)
    }

    func removeBookmark(postId: String, authorization: XGatewayRequestAuthorization) throws -> [String: Any] {
        let userId = try authenticatedUserId(authorization: authorization)
        let payload = try performJSONRequest(
            method: "DELETE",
            url: try xAPIURL(path: "/2/users/\(urlPathEscape(userId))/bookmarks/\(urlPathEscape(postId))"),
            authorization: authorization,
            body: nil
        )
        return XGatewayResponseProjector.bookmark(postId: postId, payload, defaultBookmarked: false)
    }

    func createArticleDraft(
        title: String,
        text: String,
        authorization: XGatewayRequestAuthorization
    ) throws -> [String: Any] {
        let payload = try performJSONRequest(
            method: "POST",
            url: try xArticleAPIURL(path: "/2/articles/draft"),
            authorization: authorization,
            body: XGatewayArticleRequestBuilder.draftBody(title: title, text: text)
        )
        return XGatewayResponseProjector.articleDraft(payload)
    }

    func publishArticle(articleId: String, authorization: XGatewayRequestAuthorization) throws -> [String: Any] {
        let payload = try performJSONRequest(
            method: "POST",
            url: try xArticleAPIURL(path: "/2/articles/\(urlPathEscape(articleId))/publish"),
            authorization: authorization,
            body: [:]
        )
        return XGatewayResponseProjector.articlePublish(payload)
    }
}

private func userPageQuery(maxResults: Int, paginationToken: String?) -> String {
    var items = ["max_results": String(maxResults)]
    copyIfPresent(paginationToken, to: "pagination_token", into: &items)
    return userPageQueryItems(items)
}

private func postPageQuery(maxResults: Int, paginationToken: String?) -> String {
    var items = ["max_results": String(maxResults)]
    copyIfPresent(paginationToken, to: "pagination_token", into: &items)
    return timelineQueryItems(items)
}

private func newsQueryItems(_ additionalItems: [String: String]) -> String {
    var items = additionalItems
    items["news.fields"] = "category,cluster_posts_results,hook,id,keywords,name,summary,updated_at"
    return queryItems(items)
}

private func copyIfPresent(_ value: String?, to key: String, into items: inout [String: String]) {
    guard let value = nonBlank(value) else {
        return
    }
    items[key] = value
}
