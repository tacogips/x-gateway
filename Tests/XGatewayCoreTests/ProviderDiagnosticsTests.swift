import Foundation
import XCTest
@testable import XGatewayCore

final class ProviderDiagnosticsTests: XCTestCase {
    private let executor = XGatewayLiveExecutor(
        token: nil, appToken: nil, oauth1Credentials: nil, mediaRootDir: nil, traceId: nil,
        transport: TransportSettings(timeoutMs: 100, retryCount: 0, retryBackoff: "fixed", retryBaseMs: 0, retryMaxMs: 0)
    )

    func testKnownProblemsAndReasonsSurviveTokenAnnotationWithoutCopyingText() throws {
        for host in ["api.x.com", "api.twitter.com"] {
            for problem in ["client-forbidden", "unsupported-authentication", "insufficient-scope", "usage-capped", "not-authorized-for-resource", "spend-cap-reached"] {
                let error = executor.mapHTTPError(statusCode: 403, payload: [
                    "type": "https://\(host)/2/problems/\(problem)", "reason": "client-not-enrolled",
                    "detail": "secret-access-token", "title": "private post", "client_id": "private-client"
                ]).withTokenSource("private-source")
                XCTAssertEqual(error.providerProblem?.rawValue, problem)
                XCTAssertEqual(error.providerReason, .clientNotEnrolled)
                let safe = error.jsonObject().filter { $0.key.hasPrefix("provider") }
                let encoded = try JSONSerialization.data(withJSONObject: safe)
                let text = try XCTUnwrap(String(data: encoded, encoding: .utf8))
                for secret in ["secret-access-token", "private post", "private-client", "private-source", "https:"] {
                    XCTAssertFalse(text.contains(secret))
                }
            }
        }
        for reason in ["insufficient_scope", "insufficient-scope", "unsupported-authentication", "usage-capped"] {
            let error = executor.mapHTTPError(statusCode: 403, payload: ["error": reason])
            XCTAssertEqual(error.providerReason?.rawValue, reason.replacingOccurrences(of: "_", with: "-"))
        }
    }

    func testUnknownProblemAndReasonAreFiniteAndArbitraryURLsAreRejected() {
        for type in ["https://attacker.invalid/2/problems/client-forbidden", "https://api.x.com/2/problems/client-forbidden?token=secret", "secret", "about:blank"] {
            let error = executor.mapHTTPError(statusCode: 403, payload: ["type": type, "reason": "private-token"])
            XCTAssertEqual(error.providerProblem, .unknown)
            XCTAssertEqual(error.providerReason, .unknown)
        }
    }

    func testNumericProviderCodesAreBoundedIntegersAndNestedErrorsAreSupported() {
        let error = executor.mapHTTPError(statusCode: 403, payload: ["errors": [["code": 453, "message": "private-token"]]])
        XCTAssertEqual(error.providerErrorCode, 453)
        XCTAssertEqual(error.withTokenSource("fixture").jsonObject()["providerErrorCode"] as? Int, 453)
        for invalid in [true, -1, 100_000, 1.5, "453"] as [Any] {
            XCTAssertNil(executor.mapHTTPError(statusCode: 403, payload: ["code": invalid]).providerErrorCode)
        }
    }
}
