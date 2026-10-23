import Foundation
import XCTest
@testable import XGatewayCore

final class UserMemoryTests: XCTestCase {
    func testKnownAuthorsNeverAppearInLookupAndSecondReadReusesNewUsers() throws {
        let memory = try XGatewayUserMemory(json: #"[{"id":"1","username":"known","name":"Known"}]"#)
        let url = try xAPIURL(path: "/2/users/9/timelines/reverse_chronological", query: timelineQueryItems(["pagination_token": "opaque+/="]))
        var lookupIDs: [String] = []
        var reads = 0
        let request: (URL) throws -> Any = { target in
            let fields = Dictionary(uniqueKeysWithValues: (URLComponents(url: target, resolvingAgainstBaseURL: false)?.queryItems ?? []).map { ($0.name, $0.value ?? "") })
            if target.path == "/2/users" {
                lookupIDs.append(fields["ids"] ?? "")
                return ["data": [["id": "2", "username": "new_user", "name": "New"]]]
            }
            reads += 1
            XCTAssertEqual(fields["pagination_token"], "opaque+/=")
            XCTAssertTrue(target.absoluteString.contains("pagination_token=opaque%2B%2F%3D"))
            XCTAssertNil(fields["user.fields"])
            XCTAssertFalse(fields["expansions", default: ""].split(separator: ",").contains("author_id"))
            XCTAssertTrue(fields["expansions", default: ""].contains("attachments.media_keys"))
            return ["data": [["id": "100", "author_id": "1"], ["id": "101", "author_id": "2"]],
                    "includes": ["tweets": [["id": "102", "author_id": "2"]]], "meta": ["next_token": "next"]]
        }
        for _ in 0..<2 {
            let payload = try XCTUnwrap(memory.read(url: url, request: request) as? [String: Any])
            let includes = try XCTUnwrap(payload["includes"] as? [String: Any])
            XCTAssertEqual((includes["users"] as? [[String: String]])?.count, 2)
            XCTAssertEqual((payload["meta"] as? [String: String])?["next_token"], "next")
            let page = try XGatewayResponseProjector.postPage(payload)
            let posts = try XCTUnwrap(page["posts"] as? [[String: Any]])
            XCTAssertEqual((posts[0]["author"] as? [String: Any])?["username"] as? String, "known")
        }
        XCTAssertEqual(reads, 2)
        XCTAssertEqual(lookupIDs, ["2"])
        XCTAssertEqual(memory.delta.map { $0["id"] }, ["2"])
    }

    func testLookupFailurePreservesPostsAndDoesNotRememberMissingUser() throws {
        let memory = try XGatewayUserMemory(json: "[]")
        let url = try xAPIURL(path: "/2/tweets", query: timelineQueryItems(["ids": "10"]))
        var lookups = 0
        for _ in 0..<2 {
            let result = try memory.read(url: url) { target in
                if target.path == "/2/users" { lookups += 1; throw validation("fixture unavailable") }
                return ["data": [["id": "10", "author_id": "2"]]]
            }
            XCTAssertEqual(((result as? [String: Any])?["data"] as? [[String: String]])?.count, 1)
        }
        XCTAssertEqual(lookups, 2)
        XCTAssertTrue(memory.delta.isEmpty)
    }

    func testInvalidMemoryIsRejectedBeforeNetworkAndUnrequestedUsersAreIgnored() throws {
        for json in [#"[{"id":"1","username":"bad handle"}]"#, #"[{"id":"1","username":"ok","token":"secret"}]"#] {
            XCTAssertThrowsError(try XGatewayUserMemory(json: json))
        }
        let memory = try XGatewayUserMemory(json: "[]")
        let url = try xAPIURL(path: "/2/tweets", query: timelineQueryItems([:]))
        _ = try memory.read(url: url) { target in
            target.path == "/2/users" ? ["data": [["id": "3", "username": "unrequested"]]] : ["data": [["id": "10", "author_id": "2"]]]
        }
        XCTAssertTrue(memory.users.isEmpty)
    }

    func testNestedAuthorExpansionsAreRemovedButOtherUsersAndAuthorIDsSurvive() throws {
        let memory = try XGatewayUserMemory(json: #"[{"id":"1","username":"known"}]"#)
        let url = try xAPIURL(path: "/2/tweets", query: queryItems([
            "expansions": "referenced_tweets.id.author_id,entities.mentions.username", "user.fields": "username,verified", "tweet.fields": "text"
        ]))
        let result = try memory.read(url: url) { target in
            let values = Dictionary(uniqueKeysWithValues: (URLComponents(url: target, resolvingAgainstBaseURL: false)?.queryItems ?? []).map { ($0.name, $0.value ?? "") })
            XCTAssertEqual(values["expansions"], "entities.mentions.username,referenced_tweets.id")
            XCTAssertEqual(values["user.fields"], "username,verified")
            XCTAssertEqual(values["tweet.fields"], "text,author_id")
            return ["data": [["id": "10", "author_id": "1"]], "includes": ["users": [["id": "2", "username": "mention", "verified": true]]]]
        }
        let users = ((result as? [String: Any])?["includes"] as? [String: Any])?["users"] as? [[String: Any]]
        XCTAssertEqual(users?.count, 2)
        XCTAssertEqual(users?.first?["verified"] as? Bool, true)
    }

    func testFullMemorySkipsNewLookupsWithoutFailingPosts() throws {
        let users = (1...10_000).map { ["id": String($0), "username": "user_\($0)"] }
        let json = try XCTUnwrap(String(data: JSONSerialization.data(withJSONObject: users), encoding: .utf8))
        let memory = try XGatewayUserMemory(json: json)
        let url = try xAPIURL(path: "/2/tweets", query: timelineQueryItems([:]))
        var requests = 0
        _ = try memory.read(url: url) { target in
            requests += 1
            XCTAssertEqual(target.path, "/2/tweets")
            return ["data": [["id": "10", "author_id": "10001"]]]
        }
        XCTAssertEqual(requests, 1)
        XCTAssertEqual(memory.unavailableCount, 1)
        XCTAssertTrue(memory.delta.isEmpty)
        XCTAssertNotNil(try XGatewayUserMemory.from(environment: ["X_GW_USER_MEMORY_PARTS": "2",
            "X_GW_USER_MEMORY_JSON_0": "[", "X_GW_USER_MEMORY_JSON_1": "]"]))
    }
}
