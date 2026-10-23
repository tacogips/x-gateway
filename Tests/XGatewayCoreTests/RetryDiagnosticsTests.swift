import Foundation
import XCTest
@testable import XGatewayCore

final class RetryDiagnosticsTests: XCTestCase {
    private func transport(retries: Int = 2, backoff: String = "exponential-jitter") -> TransportSettings {
        TransportSettings(timeoutMs: 100, retryCount: retries, retryBackoff: backoff, retryBaseMs: 300, retryMaxMs: 10_000)
    }

    private func failure(status: Int, transport: TransportSettings) -> XGatewayErrorPayload {
        XGatewayLiveExecutor(token: nil, appToken: nil, oauth1Credentials: nil, mediaRootDir: nil, traceId: nil,
                             transport: transport).mapHTTPError(statusCode: status, payload: ["detail": "PRIVATE_BODY_TOKEN"])
    }

    func testRetryableFailureRecordsActualAttemptsAndJitteredDelays() throws {
        let settings = transport()
        var sleeps: [Int] = []
        var attempts = 0
        XCTAssertThrowsError(try XGatewayRetryPolicy.perform(method: "GET", transport: settings,
            sleep: { sleeps.append($0) }, jitter: { 0.5 }, perform: { () -> Int in
            attempts += 1
            throw failure(status: 429, transport: settings)
        })) { error in
            guard let error = error as? XGatewayErrorPayload else { return XCTFail("wrong error") }
            let json = error.jsonObject()
            XCTAssertEqual(json["requestAttempts"] as? Int, 3)
            XCTAssertEqual(json["retryAttempts"] as? Int, 2)
            XCTAssertEqual(json["backoffMs"] as? Int, 450)
            XCTAssertEqual(json["retryStopReason"] as? String, "retry-exhausted")
            XCTAssertEqual(json["httpStatus"] as? Int, 429)
        }
        XCTAssertEqual(attempts, 3)
        XCTAssertEqual(sleeps, [150, 300])
    }

    func testNoRetryReasonsAndTokenAnnotationPreserveEvidence() {
        for (status, retries, method, reason) in [(401, 2, "GET", "non-retryable"), (403, 2, "GET", "non-retryable"),
            (503, 0, "GET", "retry-disabled"), (503, 2, "POST", "method-not-retryable")] {
            let settings = transport(retries: retries)
            XCTAssertThrowsError(try XGatewayRetryPolicy.perform(method: method, transport: settings,
                sleep: { _ in XCTFail("must not sleep") }, perform: { () -> Int in throw failure(status: status, transport: settings) })) { error in
                guard let error = error as? XGatewayErrorPayload else { return XCTFail("wrong error") }
                let annotated = error.withTokenSource("private-source").jsonObject()
                XCTAssertEqual(annotated["requestAttempts"] as? Int, 1)
                XCTAssertEqual(annotated["retryAttempts"] as? Int, 0)
                XCTAssertEqual(annotated["backoffMs"] as? Int, 0)
                XCTAssertEqual(annotated["retryStopReason"] as? String, reason)
            }
        }
    }

    func testUninstrumentedErrorDoesNotInventZeroHTTPAttempts() {
        let error = failure(status: 503, transport: transport())
        XCTAssertNil(error.jsonObject()["requestAttempts"])
        XCTAssertNil(error.jsonObject()["retryStopReason"])
    }

    func testMaximumConfiguredBackoffEvidenceIsAccurate() {
        let settings = TransportSettings(timeoutMs: 1, retryCount: 10, retryBackoff: "exponential-jitter", retryBaseMs: 60_000, retryMaxMs: 600_000)
        var slept = 0
        XCTAssertThrowsError(try XGatewayRetryPolicy.perform(method: "GET", transport: settings,
            sleep: { slept += $0 }, jitter: { 1 }, perform: { () -> Int in throw failure(status: 503, transport: settings) })) { error in
            guard let error = error as? XGatewayErrorPayload else { return XCTFail("wrong error") }
            XCTAssertEqual(error.retryDiagnostics?.backoffMs, slept)
            XCTAssertGreaterThan(slept, 600_000)
            XCTAssertEqual(error.retryDiagnostics?.requestAttempts, 11)
        }
    }

    func testRecoveredRequestKeepsExistingSuccessBehavior() throws {
        let settings = transport()
        var attempts = 0
        var sleeps: [Int] = []
        let value = try XGatewayRetryPolicy.perform(method: "GET", transport: settings,
            sleep: { sleeps.append($0) }, jitter: { 1 }, perform: {
            attempts += 1
            if attempts == 1 { throw failure(status: 503, transport: settings) }
            return "ok"
        })
        XCTAssertEqual(value, "ok")
        XCTAssertEqual(attempts, 2)
        XCTAssertEqual(sleeps, [300])
    }

    func testPreflightFailureExplicitlyRecordsNoTransportAttempt() throws {
        let result = XGatewayCLI(commandName: "x-gateway-reader", surface: .read).run(
            arguments: ["graphql", "query", "query { accountMe { id } }", "--json"], environment: [:])
        let envelope = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(result.stderr.utf8)) as? [String: Any])
        let error = try XCTUnwrap(envelope["error"] as? [String: Any])
        XCTAssertEqual(error["requestAttempts"] as? Int, 0)
        XCTAssertEqual(error["retryStopReason"] as? String, "not-started")
    }
}
