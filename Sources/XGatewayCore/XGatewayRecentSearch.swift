import Foundation

func recentSearchParameters(query: String, maxResults: Int, sinceId: String?, nextToken: String?) -> [String: String] {
    var parameters = ["query": query, "max_results": String(maxResults)]
    if let sinceId { parameters["since_id"] = sinceId }
    if let nextToken { parameters["next_token"] = nextToken }
    return parameters
}
