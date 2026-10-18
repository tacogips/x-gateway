import XCTest
@testable import XGatewayCore

final class HelpCommandTests: XCTestCase {
    func testHelpAliasesWorkForBothRolesWithoutCredentialsOrOAuthSideEffects() {
        for surface in [XGatewaySurface.read, .write] {
            let commandName = surface == .read ? "x-gateway-reader" : "x-gateway-writer"
            let cli = XGatewayCLI(commandName: commandName, surface: surface)
            for arguments in [["--help"], ["-h"], ["help"], ["auth", "oauth2", "--help"], ["graphql", "query", "-h"]] {
                let result = cli.run(arguments: arguments, environment: ["X_GW_TIMEOUT_MS": "invalid", "X_GW_TOKEN": "private-fixture"])
                XCTAssertEqual(result.exitCode, 0, result.stderr)
                XCTAssertTrue(result.stdout.contains(commandName))
                XCTAssertTrue(result.stdout.contains("auth oauth2"))
                XCTAssertTrue(result.stderr.isEmpty)
                XCTAssertFalse(result.stdout.contains("private-fixture"))
            }
        }
    }

    func testHelpPreservesJSONOutputContractAndDefaultUsage() {
        let cli = XGatewayCLI(commandName: "x-gateway-reader", surface: .read)
        let defaultUsage = cli.run(arguments: [], environment: [:])
        let help = cli.run(arguments: ["--help"], environment: [:])
        XCTAssertEqual(help.exitCode, 0)
        XCTAssertEqual(help.stdout, defaultUsage.stdout)
        let jsonHelp = cli.run(arguments: ["help", "--json"], environment: [:])
        XCTAssertEqual(jsonHelp.exitCode, 0)
        XCTAssertTrue(jsonHelp.stdout.contains("\"ok\":true"))
        XCTAssertTrue(jsonHelp.stdout.contains("auth oauth2"))
    }
}
