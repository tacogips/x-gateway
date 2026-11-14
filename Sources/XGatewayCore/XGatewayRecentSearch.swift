import Foundation

func recentSearchParameters(query: String, maxResults: Int, sinceId: String?, nextToken: String?, startTime: String? = nil, endTime: String? = nil) -> [String: String] {
    var parameters = ["query": query, "max_results": String(maxResults)]
    if let sinceId { parameters["since_id"] = sinceId }
    if let startTime, sinceId == nil { parameters["start_time"] = startTime }
    if let endTime { parameters["end_time"] = endTime }
    if let nextToken { parameters["next_token"] = nextToken }
    return parameters
}
