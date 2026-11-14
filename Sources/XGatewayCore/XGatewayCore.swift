import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum XGatewaySurface: String, Sendable {
    case read
    case write
}

public enum XGatewayGraphQLOperationType: String, Sendable {
    case query
    case mutation
}

public struct XGatewayCommandResult: Sendable {
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String
}

public typealias XGatewayStreamEventSink = @Sendable (String) -> Void

public enum XGatewayErrorCode: String, Sendable {
    case validationError = "VALIDATION_ERROR"
    case authMissing = "AUTH_MISSING"
    case authInvalid = "AUTH_INVALID"
    case authExpired = "AUTH_EXPIRED"
    case authRevoked = "AUTH_REVOKED"
    case permissionDenied = "PERMISSION_DENIED"
    case rateLimited = "RATE_LIMITED"
    case resourceNotFound = "RESOURCE_NOT_FOUND"
    case conflict = "CONFLICT"
    case upstreamFailure = "UPSTREAM_FAILURE"
    case networkFailure = "NETWORK_FAILURE"
    case unsupported = "UNSUPPORTED"
    case internalError = "INTERNAL_ERROR"
}

public struct XGatewayErrorPayload: Error, Sendable {
    public let code: XGatewayErrorCode
    public let summary: String
    public let details: String
    public let likelyCauses: [String]
    public let remediations: [String]
    public let classification: String
    public let retryable: Bool
    public let traceId: String?

    func jsonObject() -> [String: Any] {
        var object: [String: Any] = [
            "code": code.rawValue,
            "summary": summary,
            "details": details,
            "likelyCauses": likelyCauses,
            "remediations": remediations,
            "classification": classification,
            "retryable": retryable
        ]
        if let traceId {
            object["traceId"] = traceId
        }
        return object
    }
}

private struct ParsedFlagValue {
    let value: String
    let explicit: Bool
}

private struct ParsedArgs {
    let positionals: [String]
    let flags: [String: [ParsedFlagValue]]
}

private struct GlobalFlags {
    let asJson: Bool
    let pretty: Bool
    let traceId: String?
    let token: String?
    let appToken: String?
    let mediaRootDir: String?
    let consumerKey: String?
    let consumerSecret: String?
    let accessToken: String?
    let accessTokenSecret: String?
    let transport: TransportSettings
}

struct TransportSettings: Sendable {
    let timeoutMs: Int
    let retryCount: Int
    let retryBackoff: String
    let retryBaseMs: Int
    let retryMaxMs: Int

    var timeoutSeconds: TimeInterval {
        TimeInterval(timeoutMs) / 1_000
    }
}

private let globalFlagNames: Set<String> = [
    "json",
    "pretty",
    "trace-id",
    "config-mode",
    "auth-mode",
    "timeout-ms",
    "retry",
    "retry-backoff",
    "retry-base-ms",
    "retry-max-ms",
    "strict-capability-checks",
    "token",
    "media-root-dir",
    "consumer-key",
    "consumer-secret",
    "access-token",
    "access-token-secret",
    "client-id",
    "client-secret",
    "redirect-uri",
    "scopes",
    "store",
    "open-browser",
    "timeout-seconds"
]

public struct XGatewayCLI: Sendable {
    private let commandName: String
    private let surface: XGatewaySurface
    private let streamEventSink: XGatewayStreamEventSink?

    public init(commandName: String, surface: XGatewaySurface, streamEventSink: XGatewayStreamEventSink? = nil) {
        self.commandName = commandName
        self.surface = surface
        self.streamEventSink = streamEventSink
    }

    public func run(arguments: [String], environment: [String: String]) -> XGatewayCommandResult {
        var asJson = environment["X_GW_OUTPUT"] == "json"
        var pretty = false
        var traceId: String?

        do {
            let parsed = parseArguments(arguments)
            asJson = asJson || ((try? booleanFlag(parsed, key: "json")) ?? false)
            pretty = (try? booleanFlag(parsed, key: "pretty")) ?? false
            let globals = try readGlobalFlags(parsed, environment: environment)
            asJson = globals.asJson || asJson
            pretty = globals.pretty
            traceId = globals.traceId
            let payload = try execute(
                parsed: parsed,
                globalFlags: globals,
                environment: environment,
                streamEventSink: asJson ? nil : streamEventSink
            )
            let suppressStdout = parsed.positionals.first == "stream" && streamEventSink != nil && !asJson
            return XGatewayCommandResult(
                exitCode: 0,
                stdout: suppressStdout ? "" : formatSuccess(payload, asJson: asJson, pretty: pretty),
                stderr: ""
            )
        } catch let error as XGatewayErrorPayload {
            return XGatewayCommandResult(
                exitCode: mapErrorToExitCode(error),
                stdout: "",
                stderr: formatError(error, asJson: asJson, pretty: pretty)
            )
        } catch {
            let payload = XGatewayErrorPayload(
                code: .internalError,
                summary: "Unexpected internal error",
                details: String(describing: error),
                likelyCauses: ["Unhandled Swift runtime failure"],
                remediations: ["Inspect the input payload and retry after validation."],
                classification: "internal",
                retryable: false,
                traceId: traceId
            )
            return XGatewayCommandResult(
                exitCode: mapErrorToExitCode(payload),
                stdout: "",
                stderr: formatError(payload, asJson: asJson, pretty: pretty)
            )
        }
    }

    private func execute(
        parsed: ParsedArgs,
        globalFlags: GlobalFlags,
        environment: [String: String],
        streamEventSink: XGatewayStreamEventSink?
    ) throws -> Any {
        let group = parsed.positionals.first
        let action = parsed.positionals.dropFirst().first

        try assertAllowedFlags(parsed, group: group, action: action)

        guard let group else {
            return usage()
        }

        try assertSupportedCommand(group: group, action: action)

        if group == "health" {
            return [
                "status": "ok",
                "time": ISO8601DateFormatter().string(from: Date()),
                "runtime": "swift"
            ]
        }

        if group == "version" {
            return [
                "name": "x-gateway",
                "version": "0.1.4",
                "runtime": "swift"
            ]
        }

        if group == "graphql" {
            if action == "schema" {
                try assertNoExtraPositionals(parsed, expectedCount: 2, commandLabel: "graphql schema")
                return publicGraphQLSchema
            }
            if action == "query" {
                let document = try readGraphQLDocument(parsed)
                let operationType = try Self.classifyGraphQLOperation(document)
                try enforceSurface(operationType: operationType)
                return try XGatewayLiveExecutor(
                    token: globalFlags.token ?? environment["X_GW_TOKEN"],
                    appToken: globalFlags.appToken ?? environment["X_GW_APP_TOKEN"],
                    oauth1Credentials: resolveOAuth1Credentials(globalFlags: globalFlags, environment: environment),
                    mediaRootDir: resolveMediaRootDir(globalFlags: globalFlags, environment: environment),
                    traceId: globalFlags.traceId,
                    transport: globalFlags.transport
                ).executeGraphQL(document: document, operationType: operationType)
            }
            throw unknownCommand("\(group) \(action ?? "")".trimmingCharacters(in: .whitespaces))
        }

        if group == "auth" {
            if action == "verify" {
                return authVerify(globalFlags: globalFlags, environment: environment)
            }
            if action == "scopes" {
                return authScopes(globalFlags: globalFlags, environment: environment)
            }
            if action == "oauth2" {
                return try authOAuth2(parsed: parsed, globalFlags: globalFlags, environment: environment)
            }
            throw unknownCommand("\(group) \(action ?? "")".trimmingCharacters(in: .whitespaces))
        }

        if group == "stream" {
            guard surface == .read else {
                throw unsupported(
                    summary: "\(commandName) supports write commands only",
                    details: "Stream consumption is a read-only long-running command and is disabled for \(commandName).",
                    remediations: ["Use x-gateway-reader for stream commands."],
                    traceId: globalFlags.traceId
                )
            }
            return try streamCommand(
                parsed: parsed,
                action: action,
                globalFlags: globalFlags,
                environment: environment,
                eventSink: streamEventSink
            )
        }

        if group == "capabilities" {
            if action == "list" {
                return capabilityRows()
            }
            if action == "get" {
                let id = try requiredFlag(parsed, key: "id")
                guard let row = capabilityRows().first(where: { ($0["id"] as? String) == id }) else {
                    throw XGatewayErrorPayload(
                        code: .resourceNotFound,
                        summary: "Capability was not found",
                        details: "No stable Swift capability metadata row exists for id '\(id)'.",
                        likelyCauses: ["Capability id is misspelled", "Capability has not been ported to Swift metadata yet"],
                        remediations: ["Run \(commandName) capabilities list to inspect current Swift metadata."],
                        classification: "upstream",
                        retryable: false,
                        traceId: globalFlags.traceId
                    )
                }
                return row
            }
            throw unknownCommand("\(group) \(action ?? "")".trimmingCharacters(in: .whitespaces))
        }

        throw unknownCommand(group)
    }

    public static func classifyGraphQLOperation(_ document: String) throws -> XGatewayGraphQLOperationType {
        var index = skipGraphQLIgnored(in: document, from: document.startIndex)
        guard index < document.endIndex else {
            throw XGatewayErrorPayload(
                code: .validationError,
                summary: "GraphQL operation type could not be inferred",
                details: "The document must start with 'query', 'mutation', or an anonymous query selection set.",
                likelyCauses: ["Malformed GraphQL document", "Unsupported shorthand operation syntax"],
                remediations: ["Pass a complete project-owned GraphQL query or mutation document."],
                classification: "validation",
                retryable: false,
                traceId: nil
            )
        }
        if document[index] == "{" {
            return .query
        }
        guard isGraphQLNameStart(document[index]) else {
            throw XGatewayErrorPayload(
                code: .validationError,
                summary: "GraphQL operation type could not be inferred",
                details: "The document must start with 'query', 'mutation', or an anonymous query selection set.",
                likelyCauses: ["Malformed GraphQL document", "Unsupported shorthand operation syntax"],
                remediations: ["Pass a complete project-owned GraphQL query or mutation document."],
                classification: "validation",
                retryable: false,
                traceId: nil
            )
        }
        let start = index
        index = document.index(after: index)
        while index < document.endIndex,
              isGraphQLIdentifierCharacter(document[index]) {
            index = document.index(after: index)
        }

        let token = String(document[start..<index])
        if token == "mutation" {
            return .mutation
        }
        if token == "query" {
            return .query
        }
        throw XGatewayErrorPayload(
            code: .validationError,
            summary: "GraphQL operation type could not be inferred",
            details: "The document must start with 'query', 'mutation', or an anonymous query selection set.",
            likelyCauses: ["Malformed GraphQL document", "Unsupported shorthand operation syntax"],
            remediations: ["Pass a complete project-owned GraphQL query or mutation document."],
            classification: "validation",
            retryable: false,
            traceId: nil
        )
    }

    private func enforceSurface(operationType: XGatewayGraphQLOperationType) throws {
        switch (surface, operationType) {
        case (.read, .mutation):
            throw unsupported(
                summary: "\(commandName) supports read-only commands only",
                details: "The command 'graphql query' contains a mutation and is disabled for \(commandName).",
                remediations: [
                    "Use x-gateway-writer for mutation operations.",
                    "Re-run with a read-only project-owned GraphQL query if the workflow should remain read-only."
                ],
                traceId: nil
            )
        case (.write, .query):
            throw unsupported(
                summary: "\(commandName) supports write commands only",
                details: "The command 'graphql query' contains a read query and is disabled for \(commandName).",
                remediations: [
                    "Use x-gateway-reader for read-only operations.",
                    "Re-run with a project-owned GraphQL mutation if the workflow should perform a write."
                ],
                traceId: nil
            )
        default:
            return
        }
    }

    private func usage() -> String {
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
}

private func parseArguments(_ arguments: [String]) -> ParsedArgs {
    var positionals: [String] = []
    var flags: [String: [ParsedFlagValue]] = [:]
    var index = 0

    while index < arguments.count {
        let current = arguments[index]
        if !current.hasPrefix("--") {
            positionals.append(current)
            index += 1
            continue
        }

        let trimmed = String(current.dropFirst(2))
        let parts = trimmed.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
        guard let rawKey = parts.first else {
            index += 1
            continue
        }
        let key = String(rawKey).trimmingCharacters(in: .whitespacesAndNewlines)
        if key.isEmpty {
            index += 1
            continue
        }

        var value: String
        var explicit = parts.count == 2
        if parts.count == 2 {
            value = String(parts[1])
        } else if index + 1 < arguments.count && !arguments[index + 1].hasPrefix("--") {
            value = arguments[index + 1]
            explicit = true
            index += 1
        } else {
            value = "true"
        }

        flags[key, default: []].append(ParsedFlagValue(value: value, explicit: explicit))
        index += 1
    }

    return ParsedArgs(positionals: positionals, flags: flags)
}

private func readGlobalFlags(_ parsed: ParsedArgs, environment: [String: String]) throws -> GlobalFlags {
    return GlobalFlags(
        asJson: try booleanFlag(parsed, key: "json"),
        pretty: try booleanFlag(parsed, key: "pretty"),
        traceId: try optionalStringFlag(parsed, key: "trace-id"),
        token: try optionalStringFlag(parsed, key: "token"),
        appToken: try optionalStringFlag(parsed, key: "token"),
        mediaRootDir: try optionalStringFlag(parsed, key: "media-root-dir"),
        consumerKey: try optionalStringFlag(parsed, key: "consumer-key"),
        consumerSecret: try optionalStringFlag(parsed, key: "consumer-secret"),
        accessToken: try optionalStringFlag(parsed, key: "access-token"),
        accessTokenSecret: try optionalStringFlag(parsed, key: "access-token-secret"),
        transport: TransportSettings(
            timeoutMs: try optionalIntFlag(
                parsed,
                key: "timeout-ms",
                environment: environment,
                environmentKey: "X_GW_TIMEOUT_MS",
                defaultValue: 30_000,
                minimum: 1,
                maximum: 600_000
            ),
            retryCount: try optionalIntFlag(
                parsed,
                key: "retry",
                environment: environment,
                environmentKey: "X_GW_RETRY",
                defaultValue: 2,
                minimum: 0,
                maximum: 10
            ),
            retryBackoff: try optionalEnumFlag(
                parsed,
                key: "retry-backoff",
                environment: environment,
                environmentKey: "X_GW_RETRY_BACKOFF",
                defaultValue: "exponential-jitter",
                allowed: ["exponential-jitter", "fixed", "none"]
            ),
            retryBaseMs: try optionalIntFlag(
                parsed,
                key: "retry-base-ms",
                environment: environment,
                environmentKey: "X_GW_RETRY_BASE_MS",
                defaultValue: 300,
                minimum: 0,
                maximum: 60_000
            ),
            retryMaxMs: try optionalIntFlag(
                parsed,
                key: "retry-max-ms",
                environment: environment,
                environmentKey: "X_GW_RETRY_MAX_MS",
                defaultValue: 10_000,
                minimum: 0,
                maximum: 600_000
            )
        )
    )
}

private func resolveOAuth1Credentials(
    globalFlags: GlobalFlags,
    environment: [String: String]
) -> XGatewayOAuth1SigningCredentials? {
    guard let consumerKey = nonBlank(globalFlags.consumerKey ?? environment["X_GW_CONSUMER_KEY"]),
          let consumerSecret = nonBlank(globalFlags.consumerSecret ?? environment["X_GW_CONSUMER_SECRET"]),
          let accessToken = nonBlank(globalFlags.accessToken ?? environment["X_GW_ACCESS_TOKEN"]),
          let accessTokenSecret = nonBlank(globalFlags.accessTokenSecret ?? environment["X_GW_ACCESS_TOKEN_SECRET"]) else {
        return nil
    }
    return XGatewayOAuth1SigningCredentials(
        consumerKey: consumerKey,
        consumerSecret: consumerSecret,
        accessToken: accessToken,
        accessTokenSecret: accessTokenSecret
    )
}

private func resolveMediaRootDir(
    globalFlags: GlobalFlags,
    environment: [String: String]
) -> String? {
    return nonBlank(globalFlags.mediaRootDir ?? environment["X_GW_MEDIA_ROOT_DIR"])
}

func nonBlank(_ value: String?) -> String? {
    guard let value else {
        return nil
    }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}

private func assertAllowedFlags(_ parsed: ParsedArgs, group: String?, action: String?) throws {
    var allowed = globalFlagNames
    if group == "capabilities" && action == "get" {
        allowed.insert("id")
    }
    if group == "auth" && action == "oauth2" {
        allowed.formUnion([
            "client-id",
            "client-secret",
            "redirect-uri",
            "scopes",
            "store",
            "open-browser",
            "timeout-seconds"
        ])
    }
    if group == "stream" {
        allowed.formUnion([
            "max-events",
            "duration-seconds",
            "reconnect"
        ])
    }

    for key in parsed.flags.keys where !allowed.contains(key) {
        throw validation("Unknown flag --\(key).")
    }
}

private func assertSupportedCommand(group: String, action: String?) throws {
    let supported: Set<String> = ["health", "version", "graphql", "auth", "capabilities", "stream"]
    if supported.contains(group) {
        return
    }
    let attempted = action == nil ? group : "\(group) \(action!)"
    throw validation("The command '\(attempted)' is not recognized by the Swift x-gateway port.")
}

private func assertNoExtraPositionals(
    _ parsed: ParsedArgs,
    expectedCount: Int,
    commandLabel: String
) throws {
    if parsed.positionals.count > expectedCount {
        throw validation("\(commandLabel) does not accept additional positional arguments.")
    }
}

private func readGraphQLDocument(_ parsed: ParsedArgs) throws -> String {
    let queryPositionals = Array(parsed.positionals.dropFirst(2))
    if queryPositionals.isEmpty {
        throw validation("graphql query requires a single shell-quoted GraphQL document positional argument.")
    }
    if queryPositionals.count > 1 {
        throw validation("graphql query accepts exactly one shell-quoted GraphQL document positional argument.")
    }
    let query = queryPositionals[0].trimmingCharacters(in: .whitespacesAndNewlines)
    if query.isEmpty {
        throw validation("graphql query requires a non-empty GraphQL document positional argument.")
    }
    return query
}

private func optionalStringFlag(_ parsed: ParsedArgs, key: String) throws -> String? {
    guard let value = parsed.flags[key]?.last else {
        return nil
    }
    if !value.explicit {
        throw validation("Flag --\(key) requires a value.")
    }
    return value.value
}

private func requiredFlag(_ parsed: ParsedArgs, key: String) throws -> String {
    guard let value = try optionalStringFlag(parsed, key: key),
          !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        throw validation("Missing required flag --\(key).")
    }
    return value
}

private func booleanFlag(_ parsed: ParsedArgs, key: String) throws -> Bool {
    guard let value = parsed.flags[key]?.last?.value else {
        return false
    }
    switch value.lowercased() {
    case "true", "1", "yes":
        return true
    case "false", "0", "no":
        return false
    default:
        throw validation("Flag --\(key) must be a boolean value ('true' or 'false').")
    }
}

private func optionalBooleanFlag(
    _ parsed: ParsedArgs,
    key: String,
    environment: [String: String] = [:],
    environmentKey: String? = nil,
    defaultValue: Bool
) throws -> Bool {
    let rawValue: String
    let label: String
    if let value = parsed.flags[key]?.last {
        rawValue = value.value
        label = "Flag --\(key)"
    } else if let environmentKey,
              let value = nonBlank(environment[environmentKey]) {
        rawValue = value
        label = "Environment variable \(environmentKey)"
    } else {
        return defaultValue
    }
    switch rawValue.lowercased() {
    case "true", "1", "yes":
        return true
    case "false", "0", "no":
        return false
    default:
        throw validation("\(label) must be a boolean value ('true' or 'false').")
    }
}

private func optionalIntFlag(
    _ parsed: ParsedArgs,
    key: String,
    environment: [String: String] = [:],
    environmentKey: String? = nil,
    defaultValue: Int,
    minimum: Int,
    maximum: Int
) throws -> Int {
    let rawValue: String
    let label: String
    if let value = parsed.flags[key]?.last {
        if !value.explicit {
            throw validation("Flag --\(key) requires a value.")
        }
        rawValue = value.value
        label = "Flag --\(key)"
    } else if let environmentKey,
              let value = nonBlank(environment[environmentKey]) {
        rawValue = value
        label = "Environment variable \(environmentKey)"
    } else {
        return defaultValue
    }
    guard let parsedValue = Int(rawValue),
          parsedValue >= minimum,
          parsedValue <= maximum else {
        throw validation("\(label) must be an integer between \(minimum) and \(maximum).")
    }
    return parsedValue
}

private func optionalEnumFlag(
    _ parsed: ParsedArgs,
    key: String,
    environment: [String: String] = [:],
    environmentKey: String? = nil,
    defaultValue: String,
    allowed: Set<String>
) throws -> String {
    let rawValue: String
    let label: String
    if let value = parsed.flags[key]?.last {
        if !value.explicit {
            throw validation("Flag --\(key) requires a value.")
        }
        rawValue = value.value
        label = "Flag --\(key)"
    } else if let environmentKey,
              let value = nonBlank(environment[environmentKey]) {
        rawValue = value
        label = "Environment variable \(environmentKey)"
    } else {
        return defaultValue
    }
    let normalized = rawValue.lowercased()
    guard allowed.contains(normalized) else {
        throw validation("\(label) must be one of: \(allowed.sorted().joined(separator: ", ")).")
    }
    return normalized
}

func validation(_ details: String) -> XGatewayErrorPayload {
    return XGatewayErrorPayload(
        code: .validationError,
        summary: "CLI flag validation failed",
        details: details,
        likelyCauses: ["A required flag is missing", "A flag contains malformed input"],
        remediations: ["Review the command usage and required flags."],
        classification: "validation",
        retryable: false,
        traceId: nil
    )
}

private func unsupported(
    summary: String,
    details: String,
    remediations: [String],
    traceId: String?
) -> XGatewayErrorPayload {
    return XGatewayErrorPayload(
        code: .unsupported,
        summary: summary,
        details: details,
        likelyCauses: ["The requested behavior is outside the current Swift command surface"],
        remediations: remediations,
        classification: "unsupported",
        retryable: false,
        traceId: traceId
    )
}

private func unknownCommand(_ attempted: String) -> XGatewayErrorPayload {
    return XGatewayErrorPayload(
        code: .validationError,
        summary: "Unknown command",
        details: "The command '\(attempted)' is not recognized by the Swift x-gateway port.",
        likelyCauses: ["Command name is misspelled", "The command has not been ported yet"],
        remediations: ["Run the command with no arguments to view supported commands."],
        classification: "validation",
        retryable: false,
        traceId: nil
    )
}

private func authVerify(globalFlags: GlobalFlags, environment: [String: String]) -> [String: Any] {
    let hasBearer = nonBlank(globalFlags.token ?? environment["X_GW_TOKEN"]) != nil
    let hasAppBearer = nonBlank(globalFlags.appToken ?? environment["X_GW_APP_TOKEN"]) != nil
    let hasOAuth1 = resolveOAuth1Credentials(globalFlags: globalFlags, environment: environment) != nil
    let modes = authModes(hasBearer: hasBearer, hasAppBearer: hasAppBearer, hasOAuth1: hasOAuth1)
    let authMode = modes.count > 1 ? "mixed" : (modes.first ?? "none")
    let message: String
    if modes.isEmpty {
        message = "No Swift-supported X API credentials are configured."
    } else {
        message = "Swift configuration has credential material for: \(modes.joined(separator: ", "))."
    }
    return [
        "ready": !modes.isEmpty,
        "verifiedAt": ISO8601DateFormatter().string(from: Date()),
        "authMode": authMode,
        "availableAuthModes": modes,
        "transport": "swift",
        "message": message
    ]
}

private func authScopes(globalFlags: GlobalFlags, environment: [String: String]) -> [String: Any] {
    let hasBearer = nonBlank(globalFlags.token ?? environment["X_GW_TOKEN"]) != nil
    let hasAppBearer = nonBlank(globalFlags.appToken ?? environment["X_GW_APP_TOKEN"]) != nil
    let hasOAuth1 = resolveOAuth1Credentials(globalFlags: globalFlags, environment: environment) != nil
    return [
        "authMode": authModes(hasBearer: hasBearer, hasAppBearer: hasAppBearer, hasOAuth1: hasOAuth1).joined(separator: ", "),
        "notes": [
            "Swift auth diagnostics only inspect configured credential families.",
            "OAuth1 signing is available only for operations that support OAuth1; usage, search/news/trends, and bookmark operations remain bearer-only.",
            "X_GW_APP_TOKEN is preferred for app-only public endpoints such as full-archive search, counts, stream rules, and OpenAPI spec reads.",
            "Live scope verification still requires an upstream X API request."
        ]
    ]
}

private func authOAuth2(
    parsed: ParsedArgs,
    globalFlags: GlobalFlags,
    environment: [String: String]
) throws -> [String: Any] {
    try assertNoExtraPositionals(parsed, expectedCount: 2, commandLabel: "auth oauth2")
    guard let clientId = nonBlank(try optionalStringFlag(parsed, key: "client-id") ?? environment["X_GW_OAUTH2_CLIENT_ID"]) else {
        throw validation("auth oauth2 requires --client-id or X_GW_OAUTH2_CLIENT_ID.")
    }
    let clientSecret = nonBlank(try optionalStringFlag(parsed, key: "client-secret") ?? environment["X_GW_OAUTH2_CLIENT_SECRET"])
    let redirectURI = nonBlank(try optionalStringFlag(parsed, key: "redirect-uri") ?? environment["X_GW_OAUTH2_REDIRECT_URI"])
        ?? "http://127.0.0.1:8765/callback"
    let scopes = XGatewayOAuth2.parseScopes(try optionalStringFlag(parsed, key: "scopes") ?? environment["X_GW_OAUTH2_SCOPES"])
    let storeValue = try optionalEnumFlag(
        parsed,
        key: "store",
        environment: environment,
        environmentKey: "X_GW_OAUTH2_STORE",
        defaultValue: "none",
        allowed: ["none", "kinko"]
    )
    let storeMode = XGatewayOAuth2StoreMode(rawValue: storeValue) ?? .none
    let openBrowser = try optionalBooleanFlag(
        parsed,
        key: "open-browser",
        environment: environment,
        environmentKey: "X_GW_OAUTH2_OPEN_BROWSER",
        defaultValue: true
    )
    let timeoutSeconds = try optionalIntFlag(
        parsed,
        key: "timeout-seconds",
        environment: environment,
        environmentKey: "X_GW_OAUTH2_TIMEOUT_SECONDS",
        defaultValue: 600,
        minimum: 1,
        maximum: 3_600
    )
    return try XGatewayOAuth2LoopbackFlow(
        options: XGatewayOAuth2Options(
            clientId: clientId,
            clientSecret: clientSecret,
            redirectURI: redirectURI,
            scopes: scopes,
            storeMode: storeMode,
            openBrowser: openBrowser,
            timeoutSeconds: timeoutSeconds,
            traceId: globalFlags.traceId
        )
    ).run()
}

private func streamCommand(
    parsed: ParsedArgs,
    action: String?,
    globalFlags: GlobalFlags,
    environment: [String: String],
    eventSink: XGatewayStreamEventSink?
) throws -> [String: Any] {
    guard let action else {
        throw validation("stream requires an action: sample or filtered.")
    }
    let endpoint: XGatewayStreamEndpoint
    switch action {
    case "sample":
        endpoint = .sample
    case "filtered":
        endpoint = .filtered
    default:
        throw unknownCommand("stream \(action)")
    }
    try assertNoExtraPositionals(parsed, expectedCount: 2, commandLabel: "stream \(action)")

    let options = XGatewayStreamOptions(
        endpoint: endpoint,
        maxEvents: try optionalIntFlag(parsed, key: "max-events", defaultValue: 100, minimum: 1, maximum: 1_000),
        durationSeconds: try optionalIntFlag(parsed, key: "duration-seconds", defaultValue: 30, minimum: 1, maximum: 86_400),
        reconnect: try optionalBooleanFlag(parsed, key: "reconnect", defaultValue: false)
    )

    guard let token = nonBlank(globalFlags.token ?? environment["X_GW_APP_TOKEN"] ?? environment["X_GW_TOKEN"]) else {
        throw XGatewayErrorPayload(
            code: .authMissing,
            summary: "Authentication configuration missing",
            details: "stream \(action) requires X_GW_APP_TOKEN, X_GW_TOKEN, or --token for bearer-token stream consumption.",
            likelyCauses: ["No bearer token was configured"],
            remediations: ["Set X_GW_APP_TOKEN to an app-only bearer token with access to the requested X stream endpoint."],
            classification: "auth",
            retryable: false,
            traceId: globalFlags.traceId
        )
    }
    return try XGatewayLiveExecutor(
        token: token,
        appToken: nil,
        oauth1Credentials: nil,
        mediaRootDir: nil,
        traceId: globalFlags.traceId,
        transport: globalFlags.transport
    ).executeStream(options: options, authorization: .bearer(token), eventSink: eventSink)
}

private func authModes(hasBearer: Bool, hasAppBearer: Bool, hasOAuth1: Bool) -> [String] {
    var modes: [String] = []
    if hasOAuth1 {
        modes.append("oauth1")
    }
    if hasAppBearer {
        modes.append("app-bearer")
    }
    if hasBearer {
        modes.append("bearer")
    }
    return modes
}

private func formatSuccess(_ payload: Any, asJson: Bool, pretty: Bool) -> String {
    if asJson {
        return jsonString(["ok": true, "data": payload], pretty: pretty) + "\n"
    }
    if let text = payload as? String {
        return text + "\n"
    }
    return jsonString(payload, pretty: true) + "\n"
}

private func formatError(_ error: XGatewayErrorPayload, asJson: Bool, pretty: Bool) -> String {
    if asJson {
        let envelope: [String: Any] = ["ok": false, "error": error.jsonObject()]
        return jsonString(envelope, pretty: pretty) + "\n"
    }

    var lines: [String] = [
        "ERROR [\(error.code.rawValue)] \(error.summary)",
        "Details: \(error.details)"
    ]
    if let traceId = error.traceId {
        lines.append("Trace ID: \(traceId)")
    }
    lines.append("Likely causes:")
    lines.append(contentsOf: error.likelyCauses.map { "- \($0)" })
    lines.append("Remediations:")
    lines.append(contentsOf: error.remediations.map { "- \($0)" })
    return lines.joined(separator: "\n") + "\n"
}

func jsonString(_ payload: Any, pretty: Bool) -> String {
    let options: JSONSerialization.WritingOptions = pretty ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]
    guard JSONSerialization.isValidJSONObject(payload),
          let data = try? JSONSerialization.data(withJSONObject: payload, options: options),
          let text = String(data: data, encoding: .utf8) else {
        return "{}"
    }
    return text
}

private func mapErrorToExitCode(_ error: XGatewayErrorPayload) -> Int32 {
    switch error.code {
    case .validationError:
        return 2
    case .authMissing:
        return 3
    case .authInvalid, .authExpired, .authRevoked:
        return 4
    case .permissionDenied:
        return 5
    case .resourceNotFound:
        return 6
    case .conflict:
        return 7
    case .rateLimited:
        return 8
    case .upstreamFailure, .networkFailure:
        return 9
    case .unsupported, .internalError:
        return 10
    }
}
