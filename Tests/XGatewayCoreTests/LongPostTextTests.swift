import Foundation
import XCTest
@testable import XGatewayCore

final class LongPostTextTests: XCTestCase {
    func testFullTextSurvivesSingleAndPageProjectionIncludingTwoReferenceLevels() throws {
        let texts = (1...4).map { "  \($0): " + String(repeating: "長い本文🙂\n", count: 70) + " END\n" }
        let root: [String: Any] = [
            "id": "1", "text": "root truncated", "note_tweet": ["text": texts[0]],
            "referenced_tweets": [["id": "2", "type": "quoted"], ["id": "4", "type": "retweeted"]]
        ]
        let includes: [String: Any] = ["tweets": [
            ["id": "2", "text": "quote truncated", "note_tweet": ["text": texts[1]],
             "referenced_tweets": [["id": "3", "type": "quoted"]]],
            ["id": "3", "text": "nested truncated", "note_tweet": ["text": texts[2]],
             "referenced_tweets": [["id": "4", "type": "quoted"]]],
            ["id": "4", "text": "original truncated", "note_tweet": ["text": texts[3]]]
        ]]
        let single = try XGatewayResponseProjector.post(["data": root, "includes": includes])
        let page = try XGatewayResponseProjector.postPage(["data": [root], "includes": includes])
        let posts = try XCTUnwrap(page["posts"] as? [[String: Any]])
        XCTAssertEqual(posts.count, 1)
        for post in [single, try XCTUnwrap(posts.first)] {
            XCTAssertEqual(post["text"] as? String, texts[0])
            let quote = try XCTUnwrap(post["quote"] as? [String: Any])
            XCTAssertEqual(quote["text"] as? String, texts[1])
            let nested = try XCTUnwrap(quote["quote"] as? [String: Any])
            XCTAssertEqual(nested["text"] as? String, texts[2])
            XCTAssertNil(nested["quote"], "Existing two-level reference bound must remain intact")
            let original = try XCTUnwrap(post["repost"] as? [String: Any])
            XCTAssertEqual(original["text"] as? String, texts[3])
        }
    }

    func testAbsentBlankAndMalformedNotesFallBackToOrdinaryText() throws {
        let notes: [Any?] = [nil, NSNull(), "invalid", 42, [], [:], ["text": NSNull()],
                             ["text": 42], ["text": true], ["text": ["nested"]],
                             ["text": ""], ["text": " \n\t\r\u{3000}"]]
        for note in notes {
            var tweet: [String: Any] = ["id": "1", "text": "ordinary complete text"]
            tweet["note_tweet"] = note
            let post = try XGatewayResponseProjector.post(["data": tweet])
            XCTAssertEqual(post["text"] as? String, "ordinary complete text")
            let parent = try XGatewayResponseProjector.post([
                "data": ["id": "2", "referenced_tweets": [["id": "1", "type": "quoted"]]],
                "includes": ["tweets": [tweet]]
            ])
            XCTAssertEqual((parent["quote"] as? [String: Any])?["text"] as? String, "ordinary complete text")
        }
        let missing = try XGatewayResponseProjector.post(["data": ["id": "1", "note_tweet": ["text": false]]])
        XCTAssertEqual(missing["text"] as? String, "")
    }

    func testReadPathsRequestFullTextWithoutPrivateMetricsOrAdditionalExpansions() throws {
        let requests = [
            ("/2/tweets/123", tweetLookupQuery),
            ("/2/tweets", timelineQueryItems(["ids": "123,456"])),
            ("/2/users/123/liked_tweets", extendedPostPageQuery(maxResults: 5, paginationToken: "opaque+/=")),
            ("/2/users/123/timelines/reverse_chronological", timelineQueryItems(["max_results": "5"])),
            ("/2/users/123/tweets", timelineQueryItems(["max_results": "5"], includeOwnerMetrics: false)),
            ("/2/tweets/search/recent", timelineQueryItems(recentSearchParameters(query: "from:fixture", maxResults: 10, sinceId: nil, nextToken: nil))),
            ("/2/tweets/search/all", timelineQueryItems(["query": "from:fixture"]))
        ]
        for (path, query) in requests {
            let url = try xAPIURL(path: path, query: query)
            let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
            let values = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
            let fields = Set((values["tweet.fields"] ?? "").split(separator: ",").map(String.init))
            XCTAssertTrue(fields.contains("note_tweet"), path)
            XCTAssertTrue(fields.contains("entities"), path)
            XCTAssertTrue(fields.isDisjoint(with: ["organic_metrics", "promoted_metrics", "non_public_metrics"]), path)
            XCTAssertEqual(values["expansions"], "author_id,attachments.media_keys,referenced_tweets.id", path)
        }
        XCTAssertFalse(timelineQueryItems([:], includeTweetFields: false).contains("note_tweet"))
    }
}
