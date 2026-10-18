import Foundation
import XCTest
@testable import XGatewayCore

final class RecentSearchTests: XCTestCase {
    func testIncrementalSearchParsesAndEncodesOpaqueCursorWithoutChangingQuery() throws {
        let operation = try parseSupportedOperation(
            document: #"query { searchPosts(query: "from:example", maxResults: 20, sinceId: "123", nextToken: "opaque+/=") { posts { id } pageInfo { nextToken newestId } } }"#,
            operationType: .query
        )
        guard case .searchPosts(let query, let maximum, let sinceId, let nextToken, _, _) = operation else {
            return XCTFail("Expected recent search")
        }
        let url = try xAPIURL(
            path: "/2/tweets/search/recent",
            query: timelineQueryItems(recentSearchParameters(query: query, maxResults: maximum, sinceId: sinceId, nextToken: nextToken))
        )
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let values = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(url.path, "/2/tweets/search/recent")
        XCTAssertEqual(values["query"], "from:example")
        XCTAssertEqual(values["max_results"], "20")
        XCTAssertEqual(values["since_id"], "123")
        XCTAssertEqual(values["next_token"], "opaque+/=")
        XCTAssertNil(values["sinceId"])
        XCTAssertNil(values["pagination_token"])
    }

    func testExistingSearchOmitsCursorsAndBadCursorTypeFailsBeforeAuthentication() throws {
        let operation = try parseSupportedOperation(document: #"{ searchPosts(query: "swift") { posts { id } } }"#, operationType: .query)
        guard case .searchPosts(let query, let maximum, let sinceId, let nextToken, _, _) = operation else {
            return XCTFail("Expected recent search")
        }
        XCTAssertEqual(recentSearchParameters(query: query, maxResults: maximum, sinceId: sinceId, nextToken: nextToken), ["query": "swift", "max_results": "10"])
        for argument in ["sinceId", "nextToken"] {
            let result = XGatewayCLI(commandName: "x-gateway-reader", surface: .read).run(
                arguments: ["graphql", "query", "{ searchPosts(query: \"swift\", \(argument): 123) { posts { id } } }", "--json"], environment: [:]
            )
            XCTAssertEqual(result.exitCode, 2)
            XCTAssertTrue(result.stderr.contains(argument))
        }
    }

    func testPageCursorAndWatermarkRemainAvailableWithNoPosts() throws {
        let page = try XGatewayResponseProjector.postPage(["meta": ["next_token": "page-two", "newest_id": "200", "oldest_id": "124", "result_count": 0]])
        let info = try XCTUnwrap(page["pageInfo"] as? [String: Any])
        XCTAssertEqual(info["nextToken"] as? String, "page-two")
        XCTAssertEqual(info["newestId"] as? String, "200")
        XCTAssertEqual(info["oldestId"] as? String, "124")
    }
}
