import XCTest
@testable import XGatewayCore

final class XGatewayCoreTests: XCTestCase {
    func testAutomaticRetryPolicyKeepsReadsAndDisablesMutationRetries() throws {
        XCTAssertEqual(
            XGatewayRetryPolicy.automaticRetryCount(forHTTPMethod: "GET", configuredRetryCount: 2),
            2
        )
        XCTAssertEqual(
            XGatewayRetryPolicy.automaticRetryCount(forHTTPMethod: " get ", configuredRetryCount: 3),
            3
        )
        XCTAssertEqual(
            XGatewayRetryPolicy.automaticRetryCount(forHTTPMethod: "GET", configuredRetryCount: -1),
            0
        )

        for mutationMethod in ["POST", "PUT", "PATCH", "DELETE"] {
            XCTAssertEqual(
                XGatewayRetryPolicy.automaticRetryCount(
                    forHTTPMethod: mutationMethod,
                    configuredRetryCount: 2
                ),
                0,
                "\(mutationMethod) must not be automatically retried because X v2 write endpoints do not provide idempotency keys."
            )
        }
    }

    func testOAuthFixtures() throws {
        XCTAssertEqual(
            XGatewayOAuth1Signer.hmacSHA1Base64(
                message: "The quick brown fox jumps over the lazy dog",
                key: "key"
            ),
            "3nybhbi3iqa8ino29wqQcBydtNk="
        )
        XCTAssertEqual(
            XGatewayOAuth2.codeChallenge(for: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"),
            "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM"
        )
    }

    func testAttachmentKindAndExtensionValidation() throws {
        let writeCli = XGatewayCLI(commandName: "x-gateway-writer", surface: .write)

        let imageWithVideoFile = writeCli.run(
            arguments: [
                "graphql",
                "query",
                "mutation { createPost(text: \"hi\", attachments: [{ kind: \"image\", filePath: \"/tmp/x-gateway-video.mp4\" }]) { id } }",
                "--json"
            ],
            environment: [:]
        )
        XCTAssertEqual(imageWithVideoFile.exitCode, 2)
        XCTAssertTrue(imageWithVideoFile.stderr.contains("filePath extension"))

        let videoWithAltText = writeCli.run(
            arguments: [
                "graphql",
                "query",
                "mutation { createPost(text: \"hi\", attachments: [{ kind: \"video\", filePath: \"/tmp/x-gateway-video.mp4\", altText: \"caption\" }]) { id } }",
                "--json"
            ],
            environment: [:]
        )
        XCTAssertEqual(videoWithAltText.exitCode, 2)
        XCTAssertTrue(videoWithAltText.stderr.contains("altText"))

        let mixedVideoAttachments = writeCli.run(
            arguments: [
                "graphql",
                "query",
                "mutation { createPost(text: \"hi\", attachments: [" +
                    "{ kind: \"video\", filePath: \"/tmp/x-gateway-a.mp4\" }, " +
                    "{ kind: \"video\", filePath: \"/tmp/x-gateway-b.mp4\" }]) { id } }",
                "--json"
            ],
            environment: [:]
        )
        XCTAssertEqual(mixedVideoAttachments.exitCode, 2)
        XCTAssertTrue(mixedVideoAttachments.stderr.contains("only one video"))

        let gifAttachment = writeCli.run(
            arguments: [
                "graphql",
                "query",
                "mutation { createPost(text: \"hi\", attachments: [{ kind: \"gif\", filePath: \"/tmp/x-gateway-animation.gif\" }]) { id } }",
                "--json"
            ],
            environment: [:]
        )
        XCTAssertEqual(gifAttachment.exitCode, 3)
        XCTAssertTrue(gifAttachment.stderr.contains("createPost requires X_GW_TOKEN"))
    }

    func testAttachmentFileSizeValidationBeforeUpload() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("x-gateway-oversize-image-\(UUID().uuidString).jpg")
        try Data(repeating: 0, count: 5_000_001).write(to: fileURL)
        defer {
            try? FileManager.default.removeItem(at: fileURL)
        }

        let writeCli = XGatewayCLI(commandName: "x-gateway-writer", surface: .write)
        let oversizeImage = writeCli.run(
            arguments: [
                "graphql",
                "query",
                "mutation { createPost(text: \"hi\", attachments: [{ kind: \"image\", filePath: \"\(fileURL.path)\" }]) { id } }",
                "--json"
            ],
            environment: [
                "X_GW_CONSUMER_KEY": "consumer-key",
                "X_GW_CONSUMER_SECRET": "consumer-secret",
                "X_GW_ACCESS_TOKEN": "access-token",
                "X_GW_ACCESS_TOKEN_SECRET": "access-token-secret"
            ]
        )
        XCTAssertEqual(oversizeImage.exitCode, 2)
        XCTAssertTrue(oversizeImage.stderr.contains("<= 5 MB"))
    }

    func testDirectMessageCreationEnvelopeProjection() throws {
        let projected = XGatewayExtendedProjector.dmEvent([
            "data": [
                "dm_conversation_id": "111-222",
                "dm_event_id": "333"
            ]
        ])

        XCTAssertEqual(projected["id"] as? String, "333")
        XCTAssertEqual(projected["eventType"] as? String, "MessageCreate")
        XCTAssertEqual(projected["conversationId"] as? String, "111-222")
    }

    func testSpacesAndStreamRuleSurfacesReachAuthValidation() throws {
        let readCli = XGatewayCLI(commandName: "x-gateway-reader", surface: .read)
        let writeCli = XGatewayCLI(commandName: "x-gateway-writer", surface: .write)

        let schema = readCli.run(arguments: ["graphql", "schema"], environment: [:])
        XCTAssertEqual(schema.exitCode, 0)
        XCTAssertTrue(schema.stdout.contains("spaces(ids: [ID!]!): SpacePage!"))
        XCTAssertTrue(schema.stdout.contains("type Space"))
        XCTAssertTrue(schema.stdout.contains("streamRules(ids: [ID!], maxResults: Int, paginationToken: String): StreamRulePage!"))
        XCTAssertTrue(schema.stdout.contains("updateStreamRules(addJSON: String"))
        XCTAssertTrue(schema.stdout.contains("StreamRuleUpdateResult!"))

        let spaces = readCli.run(
            arguments: [
                "graphql",
                "query",
                "{ spaces(ids: [\"1SLjjRYNejbKM\"]) { spaces { id title creatorId hostIds } pageInfo { resultCount nextToken } } }",
                "--json"
            ],
            environment: [:]
        )
        XCTAssertEqual(spaces.exitCode, 3)
        XCTAssertTrue(spaces.stderr.contains("spaces requires X_GW_TOKEN"))

        let streamRules = readCli.run(
            arguments: [
                "graphql",
                "query",
                "{ streamRules(maxResults: 10) { rules { id value tag } pageInfo { resultCount nextToken } } }",
                "--json"
            ],
            environment: [:]
        )
        XCTAssertEqual(streamRules.exitCode, 3)
        XCTAssertTrue(streamRules.stderr.contains("streamRules requires X_GW_APP_TOKEN"))

        let updateRules = writeCli.run(
            arguments: [
                "graphql",
                "query",
                #"mutation { updateStreamRules(addJSON: "[{\"value\":\"from:xdev\",\"tag\":\"xdev\"}]") { rules { id value tag } summary { created valid } } }"#,
                "--json"
            ],
            environment: [:]
        )
        XCTAssertEqual(updateRules.exitCode, 3)
        XCTAssertTrue(updateRules.stderr.contains("updateStreamRules requires X_GW_APP_TOKEN"))
    }

    func testBoundedStreamCommandValidation() throws {
        let readCli = XGatewayCLI(commandName: "x-gateway-reader", surface: .read)
        let writeCli = XGatewayCLI(commandName: "x-gateway-writer", surface: .write)

        let missingAuth = readCli.run(
            arguments: ["stream", "sample", "--max-events", "1", "--duration-seconds", "1", "--json"],
            environment: [:]
        )
        XCTAssertEqual(missingAuth.exitCode, 3)
        XCTAssertTrue(missingAuth.stderr.contains("stream sample requires X_GW_APP_TOKEN"))

        let invalidMaxEvents = readCli.run(
            arguments: ["stream", "filtered", "--max-events", "0", "--json"],
            environment: [:]
        )
        XCTAssertEqual(invalidMaxEvents.exitCode, 2)
        XCTAssertTrue(invalidMaxEvents.stderr.contains("max-events"))

        let unsupportedAction = readCli.run(
            arguments: ["stream", "unknown", "--json"],
            environment: [:]
        )
        XCTAssertEqual(unsupportedAction.exitCode, 2)
        XCTAssertTrue(unsupportedAction.stderr.contains("stream unknown"))

        let wrongSurface = writeCli.run(
            arguments: ["stream", "sample", "--json"],
            environment: [:]
        )
        XCTAssertEqual(wrongSurface.exitCode, 10)
        XCTAssertTrue(wrongSurface.stderr.contains("read-only long-running command"))
    }

    func testSpaceProjector() throws {
        let payload: [String: Any] = [
            "data": [
                [
                    "id": "1SLjjRYNejbKM",
                    "state": "live",
                    "title": "Swift",
                    "creator_id": "123",
                    "host_ids": ["123"],
                    "speaker_ids": ["456"],
                    "participant_count": 12,
                    "subscriber_count": "3",
                    "is_ticketed": "false"
                ]
            ],
            "meta": [
                "result_count": 1,
                "next_token": "next"
            ]
        ]

        let projected = XGatewayResponseProjector.spacePage(payload)
        let spaces = try XCTUnwrap(projected["spaces"] as? [[String: Any]])
        let first = try XCTUnwrap(spaces.first)
        XCTAssertEqual(first["id"] as? String, "1SLjjRYNejbKM")
        XCTAssertEqual(first["creatorId"] as? String, "123")
        XCTAssertEqual(first["hostIds"] as? [String], ["123"])
        XCTAssertEqual(first["subscriberCount"] as? Int, 3)
        XCTAssertEqual(first["isTicketed"] as? Bool, false)
        let pageInfo = try XCTUnwrap(projected["pageInfo"] as? [String: Any])
        XCTAssertEqual(pageInfo["resultCount"] as? Int, 1)
        XCTAssertEqual(pageInfo["nextToken"] as? String, "next")
    }

    func testStreamRuleProjector() throws {
        let payload: [String: Any] = [
            "data": [
                [
                    "id": "120897978112909812",
                    "value": "coffee -is:retweet",
                    "tag": "Non-retweeted coffee Posts"
                ]
            ],
            "meta": [
                "sent": "2026-07-01T00:00:00Z",
                "result_count": 1,
                "summary": [
                    "created": 1,
                    "not_created": 0,
                    "valid": 1,
                    "invalid": 0
                ]
            ]
        ]

        let projected = XGatewayResponseProjector.streamRuleUpdateResult(payload)
        let rules = try XCTUnwrap(projected["rules"] as? [[String: Any]])
        let first = try XCTUnwrap(rules.first)
        XCTAssertEqual(first["id"] as? String, "120897978112909812")
        XCTAssertEqual(first["value"] as? String, "coffee -is:retweet")
        XCTAssertEqual(first["tag"] as? String, "Non-retweeted coffee Posts")
        let summary = try XCTUnwrap(projected["summary"] as? [String: Any])
        XCTAssertEqual(summary["created"] as? Int, 1)
        XCTAssertEqual(summary["notCreated"] as? Int, 0)
        XCTAssertEqual(projected["sent"] as? String, "2026-07-01T00:00:00Z")
    }

    func testArticleRichContentStateValidation() throws {
        let body = try XGatewayArticleRequestBuilder.draftBody(
            title: "Rich",
            contentStateJSON: #"{"blocks":[{"key":"a","text":"Body","type":"unstyled","inline_style_ranges":[{"offset":0,"length":4,"style":"BOLD"}],"entity_ranges":[],"data":{}}],"entities":[]}"#
        )
        let contentState = try XCTUnwrap(body["content_state"] as? [String: Any])
        let blocks = try XCTUnwrap(contentState["blocks"] as? [[String: Any]])
        let ranges = try XCTUnwrap(blocks.first?["inline_style_ranges"] as? [[String: Any]])
        XCTAssertEqual(ranges.first?["style"] as? String, "BOLD")

        XCTAssertThrowsError(
            try XGatewayArticleRequestBuilder.draftBody(title: "Invalid", contentStateJSON: #"{"blocks":[]}"#)
        )
    }
}
