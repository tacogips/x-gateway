import Foundation
import XCTest
@testable import XGatewayCore

final class NullablePaginationTests: XCTestCase {
    func testOptionalStringNullIsOmittedFromRecentSearchRequest() throws {
        let operation = try parseSupportedOperation(document:
            #"{ searchPosts(query: "from:kenn", maxResults: 25, nextToken: null, sinceId: null) { posts { id } pageInfo { nextToken } } }"#,
            operationType: .query)
        guard case .searchPosts(let query, let maximum, let since, let next, _, _, _, _) = operation else {
            return XCTFail("Expected recent search")
        }
        let values = recentSearchParameters(query: query, maxResults: maximum, sinceId: since, nextToken: next)
        XCTAssertEqual(values["query"], "from:kenn")
        XCTAssertEqual(values["max_results"], "25")
        XCTAssertNil(values["next_token"])
        XCTAssertNil(values["since_id"])
    }

    func testNullStringRemainsAStringAndMalformedNullDoesNotPass() throws {
        XCTAssertEqual(try extractOptionalStringArgument("nextToken", from: #"nextToken: "null""#, fieldName: "searchPosts"), "null")
        for value in ["nullish", "null0", "null.foo", "123", "true", "[null]"] {
            XCTAssertThrowsError(try extractOptionalStringArgument("nextToken", from: "nextToken: " + value, fieldName: "searchPosts"), value)
        }
        XCTAssertThrowsError(try parseSupportedOperation(document: #"{ searchPosts(query: null) { posts { id } } }"#, operationType: .query))
    }

    func testTerminalAndEmptyPagesHaveExplicitNullCursor() throws {
        for input: [String: Any] in [["data": [["id": "123", "text": "fixture"]]], ["meta": ["result_count": 0]]] {
            let page = try XGatewayResponseProjector.postPage(input)
            let info = try XCTUnwrap(page["pageInfo"] as? [String: Any])
            XCTAssertTrue(info["nextToken"] is NSNull)
            let encoded = try JSONSerialization.data(withJSONObject: page)
            let decoded = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
            XCTAssertTrue((decoded["pageInfo"] as? [String: Any])?["nextToken"] is NSNull)
        }
        let page = try XGatewayResponseProjector.postPage(["meta": ["next_token": "opaque+/="]])
        XCTAssertEqual((page["pageInfo"] as? [String: Any])?["nextToken"] as? String, "opaque+/=")
    }
}
