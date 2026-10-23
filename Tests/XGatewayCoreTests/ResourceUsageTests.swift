import Foundation
import XCTest
@testable import XGatewayCore

final class ResourceUsageTests: XCTestCase {
    func testCountsWireResourcesBeforeCachedAuthorRestoration() throws {
        let usage = XGatewayResourceUsage()
        let memory = try XGatewayUserMemory(json: #"[{"id":"1","username":"known"}]"#)
        let url = try xAPIURL(path: "/2/tweets", query: timelineQueryItems([:]))
        _ = try memory.read(url: url) { target in
            let value: [String: Any] = target.path == "/2/users"
                ? ["data": [["id": "2", "username": "new"]]]
                : ["data": [["id": "10", "author_id": "1"], ["id": "11", "author_id": "2"]],
                   "includes": ["tweets": [["id": "12", "author_id": "1"]]]]
            usage.record(method: "GET", url: target, status: 200, payload: value)
            return value
        }
        XCTAssertEqual(usage.snapshot.httpResponses, 2)
        XCTAssertEqual(usage.snapshot.resources.filter { $0.kind == .post }.count, 3)
        XCTAssertEqual(usage.snapshot.resources.filter { $0.kind == .user }.count, 1)
        XCTAssertEqual(usage.snapshot.unclassifiedResources, 0)
    }

    func testDuplicateResourcesAreRetainedForDailyDedupAndContainNoSourceContent() throws {
        let usage = XGatewayResourceUsage()
        let url = try xAPIURL(path: "/2/tweets", query: nil)
        let date = Date(timeIntervalSince1970: 1_792_771_200)
        for _ in 0..<2 {
            usage.record(method: "GET", url: url, status: 200,
                payload: ["data": [["id": "123456789", "text": "PRIVATE BODY"]]], at: date)
        }
        XCTAssertEqual(usage.snapshot.resources.count, 2)
        XCTAssertEqual(usage.snapshot.resources[0].idHash, usage.snapshot.resources[1].idHash)
        XCTAssertEqual(usage.snapshot.resources[0].idHash.count, 64)
        let json = try JSONSerialization.data(withJSONObject: usage.snapshot.jsonObject())
        let text = try XCTUnwrap(String(data: json, encoding: .utf8))
        XCTAssertFalse(text.contains("123456789"))
        XCTAssertFalse(text.contains("PRIVATE BODY"))
    }

    func testFailedResponsesAndUnclassifiedReadsAreNotFabricatedBillableCounts() throws {
        let usage = XGatewayResourceUsage()
        let url = try xAPIURL(path: "/2/users/me", query: nil)
        usage.record(method: "GET", url: url, status: 403, payload: ["detail": "PRIVATE"])
        XCTAssertEqual(usage.snapshot.httpResponses, 1)
        XCTAssertEqual(usage.snapshot.successfulResponses, 0)
        XCTAssertTrue(usage.snapshot.resources.isEmpty)
        usage.record(method: "GET", url: try xAPIURL(path: "/2/lists/1", query: nil), status: 200,
            payload: ["data": ["id": "1"]])
        XCTAssertEqual(usage.snapshot.unclassifiedResources, 1)
        let error = XGatewayErrorPayload(code: .permissionDenied, summary: "fixture", details: "fixture",
            likelyCauses: [], remediations: [], classification: "fixture", retryable: false,
            traceId: nil, resourceUsage: usage.snapshot).withTokenSource("fixture")
        XCTAssertEqual(error.resourceUsage?.httpResponses, 2)
        XCTAssertNotNil(error.jsonObject()["resourceUsage"])
        usage.record(method: "GET", url: url, status: 200, payload: NSNull())
        XCTAssertEqual(usage.snapshot.httpResponses, 3)
        XCTAssertEqual(usage.snapshot.unclassifiedResources, 2)
    }
}
