import Foundation
import XCTest
@testable import XGatewayCore

final class PostLookupAvailabilityTests: XCTestCase {
    private func error(_ id: String, _ problem: String) -> [String: Any] {
        ["resource_id": id, "resource_type": "tweet", "type": "https://api.x.com/2/problems/" + problem,
         "title": "PRIVATE", "detail": "PRIVATE provider text"]
    }

    func testPartialLookupBindsOnlyRequestedPostErrorsAndKeepsOriginalPosts() throws {
        let root: [String: Any] = ["data": [["id": "1", "text": "original"]],
            "errors": [error("2", "resource-not-found"), error("3", "not-authorized-for-resource"), error("999", "resource-not-found")]]
        let page = try XGatewayResponseProjector.postPage(root, requestedIDs: ["1", "2", "3", "4", "1"])
        let rows = try XCTUnwrap(page["lookupAvailability"] as? [[String: String]])
        XCTAssertEqual(rows, [
            ["postId": "1", "status": "available", "reason": "returned"],
            ["postId": "2", "status": "unavailable", "reason": "not-found"],
            ["postId": "3", "status": "unavailable", "reason": "forbidden"],
            ["postId": "4", "status": "unknown", "reason": "missing"]])
        XCTAssertEqual((page["posts"] as? [[String: Any]])?.first?["text"] as? String, "original")
        XCTAssertFalse(String(data: try JSONSerialization.data(withJSONObject: rows), encoding: .utf8)!.contains("PRIVATE"))
        let legacy = try XGatewayResponseProjector.postPage(root)
        XCTAssertNil(legacy["lookupAvailability"])
        XCTAssertEqual(try JSONSerialization.data(withJSONObject: legacy["posts"]!, options: .sortedKeys),
                       try JSONSerialization.data(withJSONObject: page["posts"]!, options: .sortedKeys))
    }

    func testUnboundMalformedConflictingAndUnrecognizedErrorsRemainUnknown() throws {
        var user = error("2", "resource-not-found"); user["resource_type"] = "user"
        var guessed = error("3", "resource-not-found"); guessed.removeValue(forKey: "resource_id")
        var forged = error("4", "resource-not-found"); forged["type"] = "https://evil.example/resource-not-found"
        let root: [String: Any] = ["errors": [user, guessed, forged, error("5", "resource-not-found"),
            error("5", "not-authorized-for-resource"), error("6", "future-provider-reason")]]
        let page = try XGatewayResponseProjector.postPage(root, requestedIDs: ["2", "3", "4", "5", "6"])
        let rows = try XCTUnwrap(page["lookupAvailability"] as? [[String: String]])
        XCTAssertTrue(rows.allSatisfy { $0["status"] == "unknown" })
        XCTAssertEqual(rows.count, 5)
    }

    func testProviderReturnedButGatewayFilteredIsNotDeclaredUnavailable() {
        let rows = XGatewayResponseProjector.lookupAvailability(root: ["data": [["id": "1"]]], posts: [], requestedIDs: ["1"])
        XCTAssertEqual(rows.first?["status"] as? String, "unknown")
        XCTAssertEqual(rows.first?["reason"] as? String, "filtered")
    }

    func testOverflowCannotAssertUnavailableFromTruncatedEvidence() throws {
        var errors = Array(repeating: error("2", "resource-not-found"), count: 1_000)
        errors.append(error("2", "not-authorized-for-resource"))
        let page = try XGatewayResponseProjector.postPage(["data": [["id": "1"]], "errors": errors], requestedIDs: ["1", "2", "3"])
        let rows = try XCTUnwrap(page["lookupAvailability"] as? [[String: String]])
        XCTAssertEqual(rows[0]["status"], "available")
        XCTAssertEqual(rows[1]["status"], "unknown")
        XCTAssertEqual(rows[2]["status"], "unknown")
    }

    func testFullLookupAndGraphQLSelectionAreBackwardCompatible() throws {
        let page = try XGatewayResponseProjector.postPage(["data": [["id": "1"], ["id": "2"]]], requestedIDs: ["2", "1"])
        let rows = try XCTUnwrap(page["lookupAvailability"] as? [[String: String]])
        XCTAssertEqual(rows.map { $0["postId"] }, ["2", "1"])
        XCTAssertTrue(rows.allSatisfy { $0["status"] == "available" })
        _ = try parseSupportedOperation(document: "{ posts(ids:[\"1\",\"2\"]) { posts { id } pageInfo { resultCount } lookupAvailability { postId status reason } } }", operationType: .query)
    }
}
