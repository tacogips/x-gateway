import Foundation

extension XGatewayLiveExecutor {
    func followingTimeline(
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

    func authenticatedUserId(authorization: XGatewayRequestAuthorization) throws -> String {
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
                details: "The Swift adapter could not read data.id from GET /2/users/me.",
                likelyCauses: ["Unexpected X API response shape", "Bearer token is not user-context capable"],
                remediations: ["Verify X_GW_TOKEN user context and retry.", "Inspect the upstream user lookup response."],
                classification: "upstream",
                retryable: false,
                traceId: traceId
            )
        }
        return id
    }
}
