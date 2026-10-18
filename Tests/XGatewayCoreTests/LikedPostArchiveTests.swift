import XCTest
@testable import XGatewayCore

final class LikedPostArchiveTests: XCTestCase {
    private func executor(token: String? = nil, oauth1: Bool = false) -> XGatewayLiveExecutor {
        XGatewayLiveExecutor(
            token: token, appToken: nil,
            oauth1Credentials: oauth1 ? XGatewayOAuth1SigningCredentials(
                consumerKey: "fixture-key", consumerSecret: "fixture-secret",
                accessToken: "fixture-access", accessTokenSecret: "fixture-access-secret"
            ) : nil,
            mediaRootDir: nil, traceId: nil,
            transport: TransportSettings(timeoutMs: 100, retryCount: 0, retryBackoff: "fixed", retryBaseMs: 0, retryMaxMs: 0)
        )
    }

    func testLikesPreferOAuth1WithMixedCredentialsAndKeepBearerFallback() throws {
        let operation = try parseSupportedOperation(document: #"{ likedPosts(userId: "123") { posts { id } } }"#, operationType: .query)
        for token in [nil, "stale-bearer"] as [String?] {
            guard case .oauth1 = try executor(token: token, oauth1: true).requireAuthorization(operation: operation) else {
                return XCTFail("Likes must use supported OAuth1 credentials")
            }
        }
        guard case .bearer(let token) = try executor(token: "fixture-bearer").requireAuthorization(operation: operation) else {
            return XCTFail("Bearer-only likes must remain supported")
        }
        XCTAssertEqual(token, "fixture-bearer")
        XCTAssertThrowsError(try executor().requireAuthorization(operation: operation)) { error in
            XCTAssertEqual((error as? XGatewayErrorPayload)?.code, .authMissing)
        }
        let bookmarks = try parseSupportedOperation(document: "{ bookmarks { posts { id } } }", operationType: .query)
        XCTAssertThrowsError(try executor(oauth1: true).requireAuthorization(operation: bookmarks))
    }

    func testMissingExpansionsPreserveReferenceIDsWithoutInventingBodies() throws {
        let post = try XGatewayResponseProjector.post(["data": [
            "id": "1", "text": "fixture", "referenced_tweets": [
                ["id": "2", "type": "quoted"], ["id": "3", "type": "retweeted"],
                ["id": "4", "type": "replied_to"], ["id": "5", "type": "unknown"], ["id": "", "type": "quoted"]
            ]
        ]])
        XCTAssertEqual(post["references"] as? [[String: String]], [
            ["id": "2", "relation": "quoted"], ["id": "3", "relation": "retweeted"], ["id": "4", "relation": "replied_to"]
        ])
        XCTAssertNil(post["quote"])
        XCTAssertNil(post["repost"])
    }

    func testNestedReferencesRetainMissingGrandchildWithinExistingDepthLimit() throws {
        let post = try XGatewayResponseProjector.post([
            "data": ["id": "1", "referenced_tweets": [["id": "2", "type": "quoted"]]],
            "includes": ["tweets": [["id": "2", "referenced_tweets": [["id": "3", "type": "quoted"]]]]]
        ])
        let quote = try XCTUnwrap(post["quote"] as? [String: Any])
        XCTAssertEqual(quote["references"] as? [[String: String]], [["id": "3", "relation": "quoted"]])
        XCTAssertNil(quote["quote"])
        let plain = try XGatewayResponseProjector.post(["data": ["id": "9"]])
        XCTAssertEqual(plain["references"] as? [[String: String]], [])
    }

    func testHTTPStatusSurvivesStructuredDiagnosticAnnotation() {
        for status in [400, 401, 403, 404, 429, 500] {
            let error = executor().mapHTTPError(statusCode: status, payload: ["detail": "fixture"])
                .withTokenSource("INJECTED_TOKEN")
            XCTAssertEqual(error.httpStatus, status)
            XCTAssertEqual(error.jsonObject()["httpStatus"] as? Int, status)
        }
    }
}
