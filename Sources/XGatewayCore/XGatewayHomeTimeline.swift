import Foundation

struct HomeTimelineRequestOptions {
    let startTime: String?
    let endTime: String?
    let sinceId: String?
    let untilId: String?
    let paginationToken: String?

    init(arguments: String) throws {
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
