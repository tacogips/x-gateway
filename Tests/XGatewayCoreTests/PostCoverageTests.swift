import Foundation
import XCTest
@testable import XGatewayCore

final class PostCoverageTests: XCTestCase {
    func testReferencedMediaMissingExpansionIsExplicitAndRootLookupCanResolveIt() throws {
        let quote: [String: Any] = ["id": "2", "text": "Original", "attachments": ["media_keys": ["3_photo", "7_video"]]]
        let root: [String: Any] = ["id": "1", "text": "Root", "referenced_tweets": [["id": "2", "type": "quoted"]]]
        let post = try XGatewayResponseProjector.post(["data": root, "includes": ["tweets": [quote]]])
        let projected = try XCTUnwrap(post["quote"] as? [String: Any])
        XCTAssertNil(projected["media"])
        XCTAssertEqual(projected["mediaCoverageComplete"] as? Bool, false)
        let missing = try XCTUnwrap(projected["mediaAvailability"] as? [[String: String]])
        XCTAssertEqual(missing.map { $0["reason"] }, ["missing", "missing"])
        XCTAssertEqual(missing.map { $0["mediaKey"] }, ["3_photo", "7_video"])
        let media: [[String: Any]] = [["media_key": "3_photo", "type": "photo", "url": "https://pbs.twimg.com/a.png"],
            ["media_key": "7_video", "type": "video", "variants": [["content_type": "video/mp4", "url": "https://video.twimg.com/a.mp4", "bit_rate": 1]]]]
        let resolved = try XGatewayResponseProjector.post(["data": quote, "includes": ["media": media]])
        XCTAssertEqual(resolved["text"] as? String, "Original")
        XCTAssertEqual((resolved["media"] as? [[String: Any]])?.count, 2)
        XCTAssertEqual(resolved["mediaCoverageComplete"] as? Bool, true)
        XCTAssertEqual((resolved["mediaAvailability"] as? [[String: String]])?.map { $0["reason"] }, ["returned", "returned"])
    }

    func testMissingFilteredAndDepthBoundReferencesAreNotClaimedComplete() throws {
        let root: [String: Any] = ["id": "1", "referenced_tweets": [["id": "2", "type": "quoted"], ["id": "9", "type": "retweeted"]]]
        let second: [String: Any] = ["id": "2", "referenced_tweets": [["id": "3", "type": "quoted"]]]
        let third: [String: Any] = ["id": "3", "referenced_tweets": [["id": "4", "type": "quoted"]]]
        let post = try XGatewayResponseProjector.post(["data": root, "includes": ["tweets": [second, third, ["id": "4"]]]])
        XCTAssertEqual(post["referenceCoverageComplete"] as? Bool, false)
        XCTAssertEqual((post["referenceAvailability"] as? [[String: String]])?.map { $0["reason"] }, ["returned", "missing"])
        let quote = try XCTUnwrap(post["quote"] as? [String: Any])
        XCTAssertEqual(quote["referenceCoverageComplete"] as? Bool, true)
        let level2 = try XCTUnwrap(quote["quote"] as? [String: Any])
        XCTAssertNil(level2["quote"])
        XCTAssertEqual(level2["referenceCoverageComplete"] as? Bool, false)
        XCTAssertEqual((level2["referenceAvailability"] as? [[String: String]])?.first?["reason"], "depth-limit")
        let filtered = postCoverage(root, returnedMediaKeys: [], includedMediaKeys: [], projectedReferences: [], includedReferenceIDs: ["2"], depth: 2)
        XCTAssertEqual((filtered["referenceAvailability"] as? [[String: String]])?.first?["reason"], "filtered")
    }

    func testMalformedAndOverBoundMetadataNeverClaimsCompleteOrLeaksValues() throws {
        for item: Any in [NSNull(), "SECRET", ["media_keys": "SECRET"], ["media_keys": ["bad\nSECRET"]], ["media_keys": Array(repeating: "3_a", count: 101)]] {
            let post = try XGatewayResponseProjector.post(["data": ["id": "1", "attachments": item]])
            XCTAssertEqual(post["mediaCoverageComplete"] as? Bool, false)
            XCTAssertFalse(String(describing: post["mediaAvailability"]).contains("SECRET"))
        }
        for item: Any in [NSNull(), "SECRET", [["id": "SECRET", "type": "quoted"]], Array(repeating: ["id": "2", "type": "quoted"], count: 101)] {
            let value = postCoverage(["referenced_tweets": item], returnedMediaKeys: [], includedMediaKeys: [], projectedReferences: [], includedReferenceIDs: [], depth: 2)
            XCTAssertEqual(value["referenceCoverageComplete"] as? Bool, false)
            XCTAssertLessThanOrEqual((value["referenceAvailability"] as? [Any])?.count ?? 999, 100)
            XCTAssertFalse(String(describing: value["referenceAvailability"]).contains("SECRET"))
        }
    }

    func testUnsupportedVideoAndDeclaredEmptyScope() throws {
        let post = try XGatewayResponseProjector.post(["data": ["id": "1", "attachments": ["media_keys": ["7_v"]]],
            "includes": ["media": [["media_key": "7_v", "type": "video"]]]])
        XCTAssertEqual((post["mediaAvailability"] as? [[String: String]])?.first?["reason"], "unsupported")
        XCTAssertEqual(post["mediaCoverageComplete"] as? Bool, false)
        let empty = try XGatewayResponseProjector.post(["data": ["id": "1", "text": "unchanged"]])
        XCTAssertEqual(empty["mediaCoverageComplete"] as? Bool, true)
        XCTAssertEqual(empty["referenceCoverageComplete"] as? Bool, true)
        XCTAssertTrue(timelineQueryItems([:]).contains("variants"))
    }
}
