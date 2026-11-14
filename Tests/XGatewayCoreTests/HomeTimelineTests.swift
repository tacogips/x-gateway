import Foundation
import XCTest
@testable import XGatewayCore

final class HomeTimelineTests: XCTestCase {
    func testDateBoundsAndCursorReachDocumentedRequestParameters() throws {
        let document = #"""
        { homeTimeline(maxResults: 100, startTime: "2026-10-16T15:00:00Z", endTime: "2026-10-17T15:00:00Z",
          sinceId: "123", untilId: "456", paginationToken: "opaque+/=") { posts { id createdAt } pageInfo { nextToken } } }
        """#
        let operation = try parseSupportedOperation(document: document, operationType: .query)
        guard case .homeTimeline(let maximum, let options, _, _) = operation else {
            return XCTFail("Expected home timeline")
        }
        let url = try xAPIURL(
            path: "/2/users/789/timelines/reverse_chronological",
            query: timelineQueryItems(options.parameters(maxResults: maximum))
        )
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let values = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(url.path, "/2/users/789/timelines/reverse_chronological")
        XCTAssertEqual(values["max_results"], "100")
        XCTAssertEqual(values["start_time"], "2026-10-16T15:00:00Z")
        XCTAssertEqual(values["end_time"], "2026-10-17T15:00:00Z")
        XCTAssertEqual(values["since_id"], "123")
        XCTAssertEqual(values["until_id"], "456")
        XCTAssertEqual(values["pagination_token"], "opaque+/=")
        XCTAssertNil(values["next_token"])
        XCTAssertNotNil(values["tweet.fields"])
    }

    func testExistingQueryOmitsOptionalBounds() throws {
        let operation = try parseSupportedOperation(document: "{ homeTimeline { posts { id } } }", operationType: .query)
        guard case .homeTimeline(let maximum, let options, _, _) = operation else {
            return XCTFail("Expected home timeline")
        }
        XCTAssertEqual(options.parameters(maxResults: maximum), ["max_results": "10"])
    }

    func testInvalidTypesFailBeforeAuthenticationAndOtherTimelinesStayUnchanged() throws {
        for argument in ["startTime", "endTime", "sinceId", "untilId", "paginationToken"] {
            let result = XGatewayCLI(commandName: "x-gateway-reader", surface: .read).run(
                arguments: ["graphql", "query", "{ homeTimeline(\(argument): 123) { posts { id } } }", "--json"], environment: [:]
            )
            XCTAssertEqual(result.exitCode, 2)
            XCTAssertTrue(result.stderr.contains(argument))
            if argument == "paginationToken" { continue } // Already accepted by the shared timeline argument set.
            XCTAssertThrowsError(try parseSupportedOperation(
                document: "{ userTimeline(userId: \"123\", \(argument): \"value\") { posts { id } } }", operationType: .query
            ))
        }
    }

    func testHomeTimelinePageRetainsContinuationToken() throws {
        let page = try XGatewayResponseProjector.postPage(["meta": ["next_token": "page-two", "result_count": 0]])
        let info = try XCTUnwrap(page["pageInfo"] as? [String: Any])
        XCTAssertEqual(info["nextToken"] as? String, "page-two")
    }
}
