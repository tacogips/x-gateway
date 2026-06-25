import Foundation
import XGatewayCore

#if os(Linux)
import Glibc
#else
import Darwin
#endif

let cli = XGatewayCLI(commandName: "x-gateway-writer", surface: .write)
let result = cli.run(
    arguments: Array(CommandLine.arguments.dropFirst()),
    environment: ProcessInfo.processInfo.environment
)

if !result.stdout.isEmpty {
    FileHandle.standardOutput.write(Data(result.stdout.utf8))
}
if !result.stderr.isEmpty {
    FileHandle.standardError.write(Data(result.stderr.utf8))
}

exit(result.exitCode)
