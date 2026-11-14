import XCTest
@testable import XGatewayCore

final class TokenSourceDiagnosticsTests: XCTestCase {
    func testAuthFailurePreservesCodeAndIdentifiesSelectedOverrideWithoutToken() throws {
        let executor = XGatewayLiveExecutor(
            token: "secret-sentinel", appToken: nil, oauth1Credentials: nil, mediaRootDir: nil, traceId: "trace",
            transport: TransportSettings(timeoutMs: 100, retryCount: 0, retryBackoff: "fixed", retryBaseMs: 0, retryMaxMs: 0),
            tokenSource: "COMMAND_LINE (--token)"
        )
        let operation = try parseSupportedOperation(document: "{ accountMe { id } }", operationType: .query)
        let source = executor.tokenSourceDescription(operation: operation, authorization: .bearer("secret-sentinel"))
        let error = executor.mapHTTPError(statusCode: 401, payload: ["error": "Unauthorized"]).withTokenSource(source)
        XCTAssertEqual(error.code, .authInvalid)
        XCTAssertEqual(error.traceId, "trace")
        XCTAssertTrue(error.details.contains("COMMAND_LINE (--token)"))
        XCTAssertTrue(error.remediations.joined().contains("X_GW_TOKEN"))
        XCTAssertFalse(error.details.contains("secret-sentinel"))
        XCTAssertFalse(error.remediations.joined().contains("secret-sentinel"))
    }
}
