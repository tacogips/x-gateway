import Foundation
import XCTest
@testable import XGatewayCore

final class PublicPostRequestTests: XCTestCase {
    private func parameters(_ query: String) throws -> [String: String] {
        let url = try xAPIURL(path: "/2/tweets", query: query)
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        return Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
    }

    func testOrdinaryReadRequestsExcludePrivateMetricsAndPreserveExpansions() throws {
        let requests = [
            tweetLookupQuery,
            timelineQueryItems(["ids": "123,456"]),
            extendedPostPageQuery(maxResults: 5, paginationToken: "opaque+/="),
            timelineQueryItems(["query": "public search", "since_id": "123"])
        ]
        for query in requests {
            let values = try parameters(query)
            let fields = Set((values["tweet.fields"] ?? "").split(separator: ",").map(String.init))
            XCTAssertTrue(fields.contains("public_metrics"))
            XCTAssertTrue(fields.isDisjoint(with: ["organic_metrics", "promoted_metrics", "non_public_metrics"]))
            XCTAssertEqual(values["expansions"], "author_id,attachments.media_keys,referenced_tweets.id")
            XCTAssertTrue((values["media.fields"] ?? "").contains("url"))
        }
        let page = try parameters(extendedPostPageQuery(maxResults: 5, paginationToken: "opaque+/="))
        XCTAssertEqual(page["max_results"], "5")
        XCTAssertEqual(page["pagination_token"], "opaque+/=")
        XCTAssertEqual(try parameters(timelineQueryItems(["ids": "123,456"]))["ids"], "123,456")
    }

    func testPrivateMetricsRequireExplicitOptIn() throws {
        let values = try parameters(timelineQueryItems([:], includeOwnerMetrics: true))
        let fields = Set((values["tweet.fields"] ?? "").split(separator: ",").map(String.init))
        XCTAssertTrue(fields.isSuperset(of: ["public_metrics", "organic_metrics", "promoted_metrics"]))
    }
}
