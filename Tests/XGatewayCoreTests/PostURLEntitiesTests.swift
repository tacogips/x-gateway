import Foundation
import XCTest
@testable import XGatewayCore

final class PostURLEntitiesTests: XCTestCase {
    func testProviderMetadataPreservesTextAndBothEntityOriginsAtTwoQuoteLevels() throws {
        let short = "https://t.co/abc"
        let root: [String: Any] = [
            "id": "1", "text": "Original \(short)",
            "entities": ["urls": [["url": short, "expanded_url": "https://x.com/user/status/123", "display_url": "x.com/user/status/…"]]],
            "note_tweet": ["text": "Full original \(short)", "entities": ["urls": [["url": short, "expanded_url": "https://example.com/long?a=1&b=2"]]]],
            "referenced_tweets": [["id": "2", "type": "quoted"], ["id": "3", "type": "retweeted"]]
        ]
        let quote: [String: Any] = ["id": "2", "text": "Quote", "entities": root["entities"] as Any,
                                   "referenced_tweets": [["id": "3", "type": "quoted"]]]
        let nested: [String: Any] = ["id": "3", "text": "Nested", "note_tweet": root["note_tweet"] as Any]
        let payload: [String: Any] = ["data": root, "includes": ["tweets": [quote, nested]]]
        let post = try XGatewayResponseProjector.post(payload)
        XCTAssertEqual(post["text"] as? String, "Full original \(short)")
        let entities = try XCTUnwrap(post["urlEntities"] as? [[String: String]])
        XCTAssertEqual(entities.count, 2)
        XCTAssertEqual(entities[0], ["url": short, "expandedUrl": "https://x.com/user/status/123", "displayUrl": "x.com/user/status/…", "source": "entities"])
        XCTAssertEqual(entities[1]["source"], "note_tweet.entities")
        let projectedQuote = try XCTUnwrap(post["quote"] as? [String: Any])
        XCTAssertEqual((projectedQuote["urlEntities"] as? [[String: String]])?.count, 1)
        let level2 = try XCTUnwrap(projectedQuote["quote"] as? [String: Any])
        XCTAssertEqual((level2["urlEntities"] as? [[String: String]])?.first?["source"], "note_tweet.entities")
        XCTAssertNil(level2["quote"])
        XCTAssertNotNil((post["repost"] as? [String: Any])?["urlEntities"])
        var pagePayload = payload
        pagePayload["data"] = [root]
        let page = try XGatewayResponseProjector.postPage(pagePayload)
        XCTAssertEqual(((page["posts"] as? [[String: Any]])?.first?["urlEntities"] as? [[String: String]]), entities)
    }

    func testMalformedUnsafeOptionalAndDuplicateMetadataNeverChangesText() throws {
        let malformed: [Any] = [NSNull(), "bad", ["url": 42], ["url": "javascript:alert(1)"],
                                ["url": "https://user:pass@example.com"], ["url": "https://example.com/\n"],
                                ["url": "https://example.com/" + String(repeating: "a", count: 8192)]]
        let good: [String: Any] = ["url": "https://t.co/abc", "expanded_url": "file:///etc/passwd", "display_url": "bad\nlabel"]
        let post = try XGatewayResponseProjector.post(["data": ["id": "1", "text": "unchanged", "entities": ["urls": malformed + [good, good]]]])
        XCTAssertEqual(post["text"] as? String, "unchanged")
        XCTAssertEqual(post["urlEntities"] as? [[String: String]], [["url": "https://t.co/abc", "source": "entities"]])
        for entities: Any in [NSNull(), "bad", ["urls": "bad"], [:]] {
            let empty = try XGatewayResponseProjector.post(["data": ["id": "1", "entities": entities]])
            XCTAssertEqual((empty["urlEntities"] as? [[String: String]])?.count, 0)
        }
    }
}
