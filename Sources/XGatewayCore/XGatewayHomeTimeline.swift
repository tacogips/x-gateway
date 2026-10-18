import Foundation

struct HomeTimelineRequestOptions {
    let userId: String?
    let startTime: String?
    let endTime: String?
    let sinceId: String?
    let untilId: String?
    let paginationToken: String?

    init(arguments: String) throws {
        userId = rangeOfGraphQLArgument("userId", in: arguments) == nil
            ? nil : try extractStringArgument("userId", from: arguments, fieldName: "homeTimeline")
        if let userId, userId.isEmpty || !userId.utf8.allSatisfy({ $0 >= 48 && $0 <= 57 }) {
            throw validation("homeTimeline.userId must be a nonempty ASCII numeric user ID.")
        }
        startTime = try extractOptionalStringArgument("startTime", from: arguments, fieldName: "homeTimeline")
        endTime = try extractOptionalStringArgument("endTime", from: arguments, fieldName: "homeTimeline")
        sinceId = try extractOptionalStringArgument("sinceId", from: arguments, fieldName: "homeTimeline")
        untilId = try extractOptionalStringArgument("untilId", from: arguments, fieldName: "homeTimeline")
        paginationToken = try extractOptionalStringArgument("paginationToken", from: arguments, fieldName: "homeTimeline")
    }

    func parameters(maxResults: Int) -> [String: String] {
        var parameters = ["max_results": String(maxResults)]
        if let startTime { parameters["start_time"] = startTime }
        if let endTime { parameters["end_time"] = endTime }
        if let sinceId { parameters["since_id"] = sinceId }
        if let untilId { parameters["until_id"] = untilId }
        if let paginationToken { parameters["pagination_token"] = paginationToken }
        return parameters
    }
}

// The caller may reuse an ID already verified against the authenticated account.
// X still authorizes the user-specific timeline request with the same credentials.
func homeTimelinePayload(
    maxResults: Int,
    options: HomeTimelineRequestOptions,
    traceId: String? = nil,
    request: (URL) throws -> Any
) throws -> Any {
    let userId: String
    if let suppliedId = options.userId {
        userId = suppliedId
    } else {
        userId = try authenticatedUserIdFromPayload(request(xAPIURL(path: "/2/users/me", query: queryItems(["user.fields": "id"]))), traceId: traceId)
    }
    return try request(xAPIURL(
        path: "/2/users/\(urlPathEscape(userId))/timelines/reverse_chronological",
        query: timelineQueryItems(options.parameters(maxResults: maxResults))
    ))
}
