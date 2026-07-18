func xGatewayUsage(commandName: String, surface: XGatewaySurface) -> String {
    let graphQLLine: String
    if surface == .read {
        graphQLLine = "  \(commandName) graphql query '<query>'"
    } else {
        graphQLLine = "  \(commandName) graphql query '<mutation>'"
    }
    return [
        "\(commandName) command usage:",
        "  \(commandName) auth verify|scopes",
        "  \(commandName) auth oauth2 --client-id <id> [--client-secret <secret>] [--store kinko]",
        "  \(commandName) doctor [--online false]",
        graphQLLine,
        "  \(commandName) graphql schema",
        surface == .read ? "  \(commandName) stream sample|filtered [--max-events 100] [--duration-seconds 30]" : nil,
        "  \(commandName) capabilities list",
        "  \(commandName) capabilities get --id <capabilityId>",
        "  \(commandName) health",
        "  \(commandName) version",
        "",
        "Notes:",
        "  - Swift read and write commands are separate installable products.",
        "  - 'graphql' refers to the owned x-gateway contract, not direct upstream X GraphQL.",
        "  - Live X API execution is ported behind XGatewayCore capability adapters."
    ].compactMap { $0 }.joined(separator: "\n")
}
