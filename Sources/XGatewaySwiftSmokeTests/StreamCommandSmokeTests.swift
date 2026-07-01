import XGatewayCore

func runStreamCommandSmokeTests() throws {
    let readCli = XGatewayCLI(commandName: "x-gateway-reader", surface: .read)
    let writeCli = XGatewayCLI(commandName: "x-gateway-writer", surface: .write)

    let missingAuth = readCli.run(
        arguments: ["stream", "sample", "--max-events", "1", "--duration-seconds", "1", "--json"],
        environment: [:]
    )
    try assert(missingAuth.exitCode == 3, "stream sample should require bearer auth before opening a stream")
    try assert(missingAuth.stderr.contains("stream sample requires X_GW_APP_TOKEN"), "stream auth error should name the stream action")

    let invalidDuration = readCli.run(
        arguments: ["stream", "filtered", "--duration-seconds", "0", "--json"],
        environment: [:]
    )
    try assert(invalidDuration.exitCode == 2, "stream duration should be bounded")
    try assert(invalidDuration.stderr.contains("duration-seconds"), "stream duration validation should name the flag")

    let writerStream = writeCli.run(
        arguments: ["stream", "sample", "--json"],
        environment: [:]
    )
    try assert(writerStream.exitCode == 10, "writer stream command should be unsupported")
    try assert(writerStream.stderr.contains("read-only long-running command"), "writer stream rejection should explain read-only routing")
}
