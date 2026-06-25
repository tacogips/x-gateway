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
    let mediaRootDir: String?
    let consumerKey: String?
    let consumerSecret: String?
    let accessToken: String?
    let accessTokenSecret: String?
    let transport: TransportSettings
}

private struct TransportSettings: Sendable {
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
    "client-secret"
]

private let publicGraphQLSchema = """
type Query {
  accountMe: AccountProfile!
  apiUsage(days: Int): ApiUsage!
  post(id: ID!, mediaRootDir: String, downloadMedia: Boolean, forceDownload: Boolean, includePromoted: Boolean): Post!
  searchPosts(query: String!, maxResults: Int, mediaRootDir: String, downloadMedia: Boolean, forceDownload: Boolean, includePromoted: Boolean): PostPage!
  homeTimeline(maxResults: Int, mediaRootDir: String, downloadMedia: Boolean, forceDownload: Boolean, includePromoted: Boolean): PostPage!
  followingTimeline(maxResults: Int, maxUsers: Int, maxResultsPerUser: Int, mediaRootDir: String, downloadMedia: Boolean, forceDownload: Boolean, includePromoted: Boolean): PostPage!
  userTimeline(userId: ID!, maxResults: Int, mediaRootDir: String, downloadMedia: Boolean, forceDownload: Boolean, includePromoted: Boolean): PostPage!
  mentionsTimeline(userId: ID!, maxResults: Int, mediaRootDir: String, downloadMedia: Boolean, forceDownload: Boolean, includePromoted: Boolean): PostPage!
}

type Mutation {
  createPost(text: String!, attachments: [PostAttachmentInput!]): Post!
  deletePost(postId: ID!): DeletePostResult!
  replyToPost(text: String!, replyToPostId: ID!, attachments: [PostAttachmentInput!]): Post!
  quotePost(text: String!, quotedPostId: ID!, attachments: [PostAttachmentInput!]): Post!
  repostPost(postId: ID!): RepostResult!
  unrepostPost(postId: ID!): RepostResult!
}

input PostAttachmentInput {
  kind: String!
  filePath: String!
  altText: String
}

type AccountProfile {
  id: ID!
  username: String!
  name: String!
}

type MediaAsset {
  kind: String!
  contentType: String!
  sourceUrl: String!
  localFilePath: String
  previewImageUrl: String
}

type PostMetrics {
  likeCount: Int
  replyCount: Int
  repostCount: Int
  quoteCount: Int
  bookmarkCount: Int
  impressionCount: Int
}

type ReferencedPost {
  id: ID!
  text: String!
  promotionStatus: String!
  metrics: PostMetrics!
  createdAt: String
  conversationId: String
  replyToUserId: String
  author: AccountProfile
  media: [MediaAsset!]
  relation: String!
  replyTo: ReferencedPostLevel2
  quote: ReferencedPostLevel2
  repost: ReferencedPostLevel2
}

type ReferencedPostLevel2 {
  id: ID!
  text: String!
  promotionStatus: String!
  metrics: PostMetrics!
  createdAt: String
  conversationId: String
  replyToUserId: String
  author: AccountProfile
  media: [MediaAsset!]
  relation: String!
}

type Post {
  id: ID!
  text: String!
  promotionStatus: String!
  metrics: PostMetrics!
  createdAt: String
  conversationId: String
  replyToUserId: String
  author: AccountProfile
  media: [MediaAsset!]
  referencedPosts: [ReferencedPost!]
  replies(maxResults: Int, paginationToken: String, mediaRootDir: String, downloadMedia: Boolean, forceDownload: Boolean, includePromoted: Boolean): PostPage!
  replyTo: ReferencedPost
  quote: ReferencedPost
  repost: ReferencedPost
}

type PostLookupResult {
  post: Post!
}

type PostPage {
  posts: [Post!]!
  pageInfo: PageInfo!
}

type PageInfo {
  resultCount: Int!
  nextToken: String
  previousToken: String
  newestId: String
  oldestId: String
}

type ApiUsage {
  projectUsage: Int
}

type DeletePostResult {
  deleted: Boolean!
}

type RepostResult {
  id: ID!
  reposted: Boolean!
}
"""

public struct XGatewayCLI: Sendable {
    private let commandName: String
    private let surface: XGatewaySurface

    public init(commandName: String, surface: XGatewaySurface) {
        self.commandName = commandName
        self.surface = surface
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
            let payload = try execute(parsed: parsed, globalFlags: globals, environment: environment)
            return XGatewayCommandResult(
                exitCode: 0,
                stdout: formatSuccess(payload, asJson: asJson, pretty: pretty),
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
        environment: [String: String]
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
                "version": "0.1.0",
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
            throw unknownCommand("\(group) \(action ?? "")".trimmingCharacters(in: .whitespaces))
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
                    "Use x-gateway-write for mutation operations.",
                    "Re-run with a read-only project-owned GraphQL query if the workflow should remain read-only."
                ],
                traceId: nil
            )
        case (.write, .query):
            throw unsupported(
                summary: "\(commandName) supports write commands only",
                details: "The command 'graphql query' contains a read query and is disabled for \(commandName).",
                remediations: [
                    "Use x-gateway-read for read-only operations.",
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
            graphQLLine,
            "  \(commandName) graphql schema",
            "  \(commandName) capabilities list",
            "  \(commandName) capabilities get --id <capabilityId>",
            "  \(commandName) health",
            "  \(commandName) version",
            "",
            "Notes:",
            "  - Swift read and write commands are separate installable products.",
            "  - 'graphql' refers to the owned x-gateway contract, not direct upstream X GraphQL.",
            "  - Live X API execution is ported behind XGatewayCore capability adapters."
        ].joined(separator: "\n")
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

private func nonBlank(_ value: String?) -> String? {
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

    for key in parsed.flags.keys where !allowed.contains(key) {
        throw validation("Unknown flag --\(key).")
    }
}

private func assertSupportedCommand(group: String, action: String?) throws {
    let supported: Set<String> = ["health", "version", "graphql", "auth", "capabilities"]
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

private func validation(_ details: String) -> XGatewayErrorPayload {
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
    let hasOAuth1 = resolveOAuth1Credentials(globalFlags: globalFlags, environment: environment) != nil
    let modes = authModes(hasBearer: hasBearer, hasOAuth1: hasOAuth1)
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
    let hasOAuth1 = resolveOAuth1Credentials(globalFlags: globalFlags, environment: environment) != nil
    return [
        "authMode": authModes(hasBearer: hasBearer, hasOAuth1: hasOAuth1).joined(separator: ", "),
        "notes": [
            "Swift auth diagnostics only inspect configured credential families.",
            "OAuth1 signing is available for non-usage Swift live requests; apiUsage remains bearer-only.",
            "Live scope verification still requires an upstream X API request."
        ]
    ]
}

private func authModes(hasBearer: Bool, hasOAuth1: Bool) -> [String] {
    var modes: [String] = []
    if hasOAuth1 {
        modes.append("oauth1")
    }
    if hasBearer {
        modes.append("bearer")
    }
    return modes
}

private func capabilityRows() -> [[String: Any]] {
    let oauth1PreferredStatus = "swift-oauth1-preferred-bearer-fallback"
    return [
        [
            "id": "account.me",
            "operation": "accountMe",
            "access": "read",
            "status": oauth1PreferredStatus
        ],
        [
            "id": "usage.tweets",
            "operation": "apiUsage",
            "access": "read",
            "status": "swift-bearer-baseline"
        ],
        [
            "id": "timeline.following",
            "operation": "followingTimeline",
            "access": "read",
            "status": oauth1PreferredStatus
        ],
        [
            "id": "post.get",
            "operation": "post",
            "access": "read",
            "status": oauth1PreferredStatus
        ],
        [
            "id": "post.replies",
            "operation": "Post.replies",
            "access": "read",
            "status": oauth1PreferredStatus
        ],
        [
            "id": "timeline.search",
            "operation": "searchPosts",
            "access": "read",
            "status": oauth1PreferredStatus
        ],
        [
            "id": "timeline.user",
            "operation": "userTimeline",
            "access": "read",
            "status": oauth1PreferredStatus
        ],
        [
            "id": "timeline.home",
            "operation": "homeTimeline",
            "access": "read",
            "status": oauth1PreferredStatus
        ],
        [
            "id": "timeline.mentions",
            "operation": "mentionsTimeline",
            "access": "read",
            "status": oauth1PreferredStatus
        ],
        [
            "id": "post.create",
            "operation": "createPost",
            "access": "write",
            "status": oauth1PreferredStatus
        ],
        [
            "id": "post.delete",
            "operation": "deletePost",
            "access": "write",
            "status": oauth1PreferredStatus
        ],
        [
            "id": "post.reply",
            "operation": "replyToPost",
            "access": "write",
            "status": oauth1PreferredStatus
        ],
        [
            "id": "post.quote",
            "operation": "quotePost",
            "access": "write",
            "status": oauth1PreferredStatus
        ],
        [
            "id": "post.repost",
            "operation": "repostPost",
            "access": "write",
            "status": oauth1PreferredStatus
        ],
        [
            "id": "post.unrepost",
            "operation": "unrepostPost",
            "access": "write",
            "status": oauth1PreferredStatus
        ]
    ]
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

private func jsonString(_ payload: Any, pretty: Bool) -> String {
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

public enum XGatewayResponseProjector {
    public static func account(_ payload: Any) -> [String: Any] {
        let data = dataObject(payload)
        return [
            "id": stringValue(data["id"]),
            "username": stringValue(data["username"]),
            "name": stringValue(data["name"])
        ]
    }

    public static func apiUsage(_ payload: Any) -> [String: Any] {
        let data = dataObject(payload)
        let dailyProjectUsage: [String: Any] = [
            "projectId": stringValue((data["daily_project_usage"] as? [String: Any])?["project_id"]),
            "usage": usageDays((data["daily_project_usage"] as? [String: Any])?["usage"])
        ]
        return [
            "capResetDay": intValue(data["cap_reset_day"]),
            "dailyClientAppUsage": ((data["daily_client_app_usage"] as? [[String: Any]]) ?? []).map { app in
                [
                    "clientAppId": stringValue(app["client_app_id"]),
                    "usageResultCount": intValue(app["usage_result_count"]),
                    "usage": usageDays(app["usage"])
                ] as [String: Any]
            },
            "dailyProjectUsage": dailyProjectUsage,
            "projectCap": intValue(data["project_cap"]),
            "projectId": stringValue(data["project_id"]),
            "projectUsage": intValue(data["project_usage"])
        ]
    }

    public static func post(_ payload: Any, options: XGatewayPostReadOptions = XGatewayPostReadOptions()) throws -> [String: Any] {
        let root = object(payload)
        let context = ProjectionContext(root: root)
        guard let post = try postObject(dataObject(payload), context: context, maxReferenceDepth: 2, options: options) else {
            throw XGatewayErrorPayload(
                code: .permissionDenied,
                summary: "Promoted post filtered from the stable read surface",
                details: "The requested post was identified as promoted in the upstream payload and x-gateway excluded it because includePromoted was not enabled.",
                likelyCauses: [
                    "The post is currently promoted for the authenticated author context",
                    "The request relied on the default includePromoted: false behavior"
                ],
                remediations: [
                    "Retry with includePromoted: true if you want promoted posts returned."
                ],
                classification: "permission",
                retryable: false,
                traceId: nil
            )
        }
        return post
    }

    public static func post(_ payload: Any, includePromoted: Bool) throws -> [String: Any] {
        return try post(payload, options: XGatewayPostReadOptions(includePromoted: includePromoted))
    }

    public static func postPage(_ payload: Any, options: XGatewayPostReadOptions = XGatewayPostReadOptions()) throws -> [String: Any] {
        let root = object(payload)
        let context = ProjectionContext(root: root)
        let tweets = (root["data"] as? [[String: Any]]) ?? []
        var posts: [[String: Any]] = []
        for tweet in tweets {
            if let post = try postObject(tweet, context: context, maxReferenceDepth: 2, options: options) {
                posts.append(post)
            }
        }
        let meta = (root["meta"] as? [String: Any]) ?? [:]
        var pageInfo: [String: Any] = [
            "resultCount": intValue(meta["result_count"], fallback: posts.count)
        ]
        copyString(meta, from: "next_token", to: "nextToken", into: &pageInfo)
        copyString(meta, from: "previous_token", to: "previousToken", into: &pageInfo)
        if let newestId = posts.first?["id"] as? String {
            pageInfo["newestId"] = newestId
        } else {
            copyString(meta, from: "newest_id", to: "newestId", into: &pageInfo)
        }
        if let oldestId = posts.last?["id"] as? String {
            pageInfo["oldestId"] = oldestId
        } else {
            copyString(meta, from: "oldest_id", to: "oldestId", into: &pageInfo)
        }
        return [
            "posts": posts,
            "pageInfo": pageInfo
        ]
    }

    public static func postPage(_ payload: Any, includePromoted: Bool) throws -> [String: Any] {
        return try postPage(payload, options: XGatewayPostReadOptions(includePromoted: includePromoted))
    }

    public static func createdPost(_ payload: Any) -> [String: Any] {
        let data = dataObject(payload)
        return [
            "id": stringValue(data["id"]),
            "text": stringValue(data["text"])
        ]
    }

    public static func deletedPost(postId: String, _ payload: Any) -> [String: Any] {
        let data = dataObject(payload)
        return [
            "id": stringValue(data["id"], fallback: postId),
            "deleted": boolValue(data["deleted"], fallback: true)
        ]
    }

    public static func repost(postId: String, _ payload: Any, defaultReposted: Bool) -> [String: Any] {
        let data = dataObject(payload)
        return [
            "id": stringValue(data["id"], fallback: stringValue(data["tweet_id"], fallback: postId)),
            "reposted": boolValue(data["retweeted"], fallback: boolValue(data["reposted"], fallback: defaultReposted))
        ]
    }
}

private func object(_ payload: Any) -> [String: Any] {
    return (payload as? [String: Any]) ?? [:]
}

private func dataObject(_ payload: Any) -> [String: Any] {
    return object(payload)["data"] as? [String: Any] ?? [:]
}

private func stringValue(_ value: Any?, fallback: String = "") -> String {
    if let value = value as? String {
        return value
    }
    if let value = value {
        return String(describing: value)
    }
    return fallback
}

private func intValue(_ value: Any?, fallback: Int = 0) -> Int {
    if let value = value as? Int {
        return value
    }
    if let value = value as? Double {
        return Int(value)
    }
    if let value = value as? String, let parsed = Int(value) {
        return parsed
    }
    return fallback
}

private func boolValue(_ value: Any?, fallback: Bool) -> Bool {
    if let value = value as? Bool {
        return value
    }
    if let value = value as? String {
        return value == "true" || value == "1" || value == "yes"
    }
    return fallback
}

private func usageDays(_ value: Any?) -> [[String: Any]] {
    return ((value as? [[String: Any]]) ?? []).map { day in
        [
            "date": stringValue(day["date"]),
            "usage": intValue(day["usage"])
        ]
    }
}

private struct ProjectionContext {
    let usersById: [String: [String: Any]]
    let mediaByKey: [String: [String: Any]]
    let tweetsById: [String: [String: Any]]

    init(root: [String: Any]) {
        let includes = root["includes"] as? [String: Any]
        var users: [String: [String: Any]] = [:]
        for user in (includes?["users"] as? [[String: Any]]) ?? [] {
            if let id = user["id"] as? String {
                users[id] = user
            }
        }
        var media: [String: [String: Any]] = [:]
        for item in (includes?["media"] as? [[String: Any]]) ?? [] {
            if let mediaKey = item["media_key"] as? String {
                media[mediaKey] = item
            }
        }
        var tweets: [String: [String: Any]] = [:]
        if let data = root["data"] as? [String: Any],
           let id = data["id"] as? String {
            tweets[id] = data
        }
        for tweet in (root["data"] as? [[String: Any]]) ?? [] {
            if let id = tweet["id"] as? String {
                tweets[id] = tweet
            }
        }
        for tweet in (includes?["tweets"] as? [[String: Any]]) ?? [] {
            if let id = tweet["id"] as? String {
                tweets[id] = tweet
            }
        }
        usersById = users
        mediaByKey = media
        tweetsById = tweets
    }
}

private func postObject(
    _ tweet: [String: Any],
    context: ProjectionContext,
    maxReferenceDepth: Int,
    options: XGatewayPostReadOptions,
    relation: String? = nil
) throws -> [String: Any]? {
    guard !stringValue(tweet["id"]).isEmpty else {
        return nil
    }
    let promotionStatus = detectPromotionStatus(tweet)
    if !options.includePromoted,
       promotionStatus == "PROMOTED" {
        return nil
    }
    var post: [String: Any] = [
        "id": stringValue(tweet["id"]),
        "text": stringValue(tweet["text"]),
        "promotionStatus": promotionStatus,
        "metrics": metricsObject(tweet)
    ]
    copyString(tweet, from: "created_at", to: "createdAt", into: &post)
    copyString(tweet, from: "conversation_id", to: "conversationId", into: &post)
    copyString(tweet, from: "in_reply_to_user_id", to: "replyToUserId", into: &post)
    if let authorId = tweet["author_id"] as? String,
       let user = context.usersById[authorId] {
        post["author"] = [
            "id": stringValue(user["id"]),
            "username": stringValue(user["username"]),
            "name": stringValue(user["name"])
        ]
    }
    if let relation {
        post["relation"] = relation
    }
    let media = try mediaAssets(for: tweet, context: context, options: options)
    if !media.isEmpty {
        post["media"] = media
    }
    if maxReferenceDepth > 0 {
        let referencedPosts = try referencedPostObjects(
            tweet,
            context: context,
            maxReferenceDepth: maxReferenceDepth,
            options: options
        )
        if !referencedPosts.isEmpty {
            post["referencedPosts"] = referencedPosts
        }
        if let replyTo = referencedPosts.first(where: { ($0["relation"] as? String) == "replied_to" }) {
            post["replyTo"] = replyTo
        }
        if let quote = referencedPosts.first(where: { ($0["relation"] as? String) == "quoted" }) {
            post["quote"] = quote
        }
        if let repost = referencedPosts.first(where: { ($0["relation"] as? String) == "retweeted" }) {
            post["repost"] = repost
        }
    }
    return post
}

private func referencedPostObjects(
    _ tweet: [String: Any],
    context: ProjectionContext,
    maxReferenceDepth: Int,
    options: XGatewayPostReadOptions
) throws -> [[String: Any]] {
    let references = (tweet["referenced_tweets"] as? [[String: Any]]) ?? []
    var posts: [[String: Any]] = []
    for reference in references {
        guard let relation = reference["type"] as? String,
              ["replied_to", "quoted", "retweeted"].contains(relation),
              let id = reference["id"] as? String,
              let referencedTweet = context.tweetsById[id] else {
            continue
        }
        if let post = try postObject(
            referencedTweet,
            context: context,
            maxReferenceDepth: maxReferenceDepth - 1,
            options: options,
            relation: relation
        ) {
            posts.append(post)
        }
    }
    return posts
}

private func mediaAssets(
    for tweet: [String: Any],
    context: ProjectionContext,
    options: XGatewayPostReadOptions
) throws -> [[String: Any]] {
    let mediaKeys = ((tweet["attachments"] as? [String: Any])?["media_keys"] as? [String]) ?? []
    var assets: [[String: Any]] = []
    for mediaKey in mediaKeys {
        guard let media = context.mediaByKey[mediaKey],
              let source = mediaSource(media) else {
            continue
        }
        var asset: [String: Any] = [
            "kind": mediaKind(media["type"]),
            "contentType": source.contentType,
            "sourceUrl": source.sourceUrl
        ]
        copyString(media, from: "preview_image_url", to: "previewImageUrl", into: &asset)
        assets.append(try materializeMediaAsset(
            asset,
            mediaKey: mediaKey,
            postId: stringValue(tweet["id"], fallback: "post"),
            options: options
        ))
    }
    return assets
}

private func mediaKind(_ value: Any?) -> String {
    let type = stringValue(value, fallback: "photo")
    if ["photo", "video", "animated_gif"].contains(type) {
        return type
    }
    return "photo"
}

private func mediaSource(_ media: [String: Any]) -> (contentType: String, sourceUrl: String)? {
    let type = stringValue(media["type"])
    if type == "photo",
       let url = media["url"] as? String,
       !url.isEmpty {
        let extensionValue = URL(string: url)?.pathExtension.lowercased()
        return (extensionValue == "png" ? "image/png" : "image/jpeg", url)
    }
    let variants = ((media["variants"] as? [[String: Any]]) ?? [])
        .filter { ($0["content_type"] as? String) == "video/mp4" && ($0["url"] as? String)?.isEmpty == false }
        .sorted { intValue($0["bit_rate"]) > intValue($1["bit_rate"]) }
    if let variant = variants.first,
       let url = variant["url"] as? String {
        return ("video/mp4", url)
    }
    return nil
}

private func materializeMediaAsset(
    _ asset: [String: Any],
    mediaKey: String,
    postId: String,
    options: XGatewayPostReadOptions
) throws -> [String: Any] {
    guard options.downloadMedia,
          let mediaRootDir = nonBlank(options.mediaRootDir),
          let sourceUrlValue = asset["sourceUrl"] as? String else {
        return asset
    }
    guard let sourceUrl = URL(string: sourceUrlValue),
          let scheme = sourceUrl.scheme?.lowercased(),
          ["http", "https"].contains(scheme) else {
        throw XGatewayErrorPayload(
            code: .upstreamFailure,
            summary: "Media source URL is not downloadable",
            details: "The upstream media asset did not include a supported http or https source URL.",
            likelyCauses: [
                "The X API response included an unexpected media URL shape",
                "The media asset is missing a direct downloadable URL"
            ],
            remediations: [
                "Retry with downloadMedia: false to return source URLs only.",
                "Capture the upstream payload and verify the media URL field."
            ],
            classification: "upstream",
            retryable: false,
            traceId: nil
        )
    }

    let rootUrl = URL(fileURLWithPath: mediaRootDir, isDirectory: true)
    let postDirectory = rootUrl.appendingPathComponent(sanitizePathComponent(postId, fallback: "post"), isDirectory: true)
    let localUrl = postDirectory.appendingPathComponent(
        mediaFileName(mediaKey: mediaKey, sourceUrl: sourceUrl, contentType: stringValue(asset["contentType"])),
        isDirectory: false
    )
    var materialized = asset
    if FileManager.default.fileExists(atPath: localUrl.path),
       !options.forceDownload {
        materialized["localFilePath"] = localUrl.path
        return materialized
    }

    do {
        try FileManager.default.createDirectory(at: postDirectory, withIntermediateDirectories: true)
        let data = try Data(contentsOf: sourceUrl)
        try data.write(to: localUrl, options: .atomic)
        materialized["localFilePath"] = localUrl.path
        return materialized
    } catch {
        throw XGatewayErrorPayload(
            code: .networkFailure,
            summary: "Media download failed",
            details: "x-gateway could not download \(sourceUrlValue) to \(localUrl.path): \(error.localizedDescription)",
            likelyCauses: [
                "The media URL expired or was unreachable",
                "The local mediaRootDir is not writable",
                "Network connectivity failed while downloading media"
            ],
            remediations: [
                "Retry the read operation.",
                "Retry with forceDownload: false if the file already exists locally.",
                "Retry with downloadMedia: false to return source URLs without local materialization.",
                "Verify that mediaRootDir exists or can be created by this process."
            ],
            classification: "network",
            retryable: true,
            traceId: nil
        )
    }
}

private func mediaFileName(mediaKey: String, sourceUrl: URL, contentType: String) -> String {
    let lastPathComponent = sourceUrl.lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
    let base = lastPathComponent.isEmpty ? mediaKey : lastPathComponent
    let sanitizedBase = sanitizePathComponent(base, fallback: "media")
    if !sourceUrl.pathExtension.isEmpty {
        return sanitizedBase
    }
    return sanitizedBase + mediaExtension(contentType: contentType)
}

private func mediaExtension(contentType: String) -> String {
    switch contentType.lowercased() {
    case "image/jpeg":
        return ".jpg"
    case "image/png":
        return ".png"
    case "image/gif":
        return ".gif"
    case "video/mp4":
        return ".mp4"
    case "application/vnd.apple.mpegurl":
        return ".m3u8"
    default:
        return ""
    }
}

private func sanitizePathComponent(_ value: String, fallback: String) -> String {
    let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._-")
    let sanitized = String(value.unicodeScalars.map { scalar in
        allowed.contains(scalar) ? Character(scalar) : "_"
    })
    let trimmed = sanitized.trimmingCharacters(in: CharacterSet(charactersIn: "._-"))
    return trimmed.isEmpty ? fallback : sanitized
}

private func metricsObject(_ tweet: [String: Any]?) -> [String: Any] {
    let publicMetrics = tweet?["public_metrics"] as? [String: Any]
    let organicMetrics = tweet?["organic_metrics"] as? [String: Any]
    let promotedMetrics = tweet?["promoted_metrics"] as? [String: Any]
    return [
        "likeCount": nullableInt(publicMetrics?["like_count"]),
        "replyCount": nullableInt(publicMetrics?["reply_count"]),
        "repostCount": nullableInt(publicMetrics?["retweet_count"]),
        "quoteCount": nullableInt(publicMetrics?["quote_count"]),
        "bookmarkCount": nullableInt(publicMetrics?["bookmark_count"]),
        "impressionCount": firstNullableInt([
            publicMetrics?["impression_count"],
            organicMetrics?["impression_count"],
            promotedMetrics?["impression_count"]
        ])
    ]
}

private func detectPromotionStatus(_ tweet: [String: Any]) -> String {
    if hasFiniteMetricValue(tweet["promoted_metrics"] as? [String: Any]) {
        return "PROMOTED"
    }
    if hasFiniteMetricValue(tweet["organic_metrics"] as? [String: Any]) {
        return "NOT_PROMOTED"
    }
    return "UNKNOWN"
}

private func hasFiniteMetricValue(_ metrics: [String: Any]?) -> Bool {
    guard let metrics else {
        return false
    }
    return metrics.values.contains { value in
        if let value = value as? Int {
            return value >= 0
        }
        if let value = value as? Double {
            return value.isFinite
        }
        return false
    }
}

private func firstNullableInt(_ values: [Any?]) -> Any {
    for value in values {
        if value != nil,
           !(value is NSNull) {
            return nullableInt(value)
        }
    }
    return NSNull()
}

private func nullableInt(_ value: Any?) -> Any {
    guard let value else {
        return NSNull()
    }
    if value is NSNull {
        return NSNull()
    }
    return intValue(value)
}

private func copyString(_ source: [String: Any], from sourceKey: String, to targetKey: String, into target: inout [String: Any]) {
    guard let value = source[sourceKey] as? String,
          !value.isEmpty else {
        return
    }
    target[targetKey] = value
}

private enum XGatewayRequestAuthorization {
    case bearer(String)
    case oauth1(XGatewayOAuth1SigningCredentials)
}

private enum MultipartPart {
    case field(name: String, value: String)
    case file(name: String, filename: String, mimeType: String, data: Data)
}

public struct XGatewayPostReadOptions: Sendable {
    public let mediaRootDir: String?
    public let downloadMedia: Bool
    public let forceDownload: Bool
    public let includePromoted: Bool

    public init(
        mediaRootDir: String? = nil,
        downloadMedia: Bool = true,
        forceDownload: Bool = false,
        includePromoted: Bool = false
    ) {
        self.mediaRootDir = nonBlank(mediaRootDir)
        self.downloadMedia = downloadMedia
        self.forceDownload = forceDownload
        self.includePromoted = includePromoted
    }

    func withDefaultMediaRootDir(_ defaultMediaRootDir: String?) -> XGatewayPostReadOptions {
        return XGatewayPostReadOptions(
            mediaRootDir: mediaRootDir ?? defaultMediaRootDir,
            downloadMedia: downloadMedia,
            forceDownload: forceDownload,
            includePromoted: includePromoted
        )
    }
}

private final class ReplyExpansionRequest {
    let maxResults: Int
    let paginationToken: String?
    let readOptions: XGatewayPostReadOptions
    let child: ReplyExpansionRequest?

    init(
        maxResults: Int,
        paginationToken: String?,
        readOptions: XGatewayPostReadOptions,
        child: ReplyExpansionRequest?
    ) {
        self.maxResults = maxResults
        self.paginationToken = paginationToken
        self.readOptions = readOptions
        self.child = child
    }
}

private final class ReplyExpansionState {
    var count = 0
}

private let maxReplyExpansions = 25

private struct XGatewayLiveExecutor {
    let token: String?
    let oauth1Credentials: XGatewayOAuth1SigningCredentials?
    let mediaRootDir: String?
    let traceId: String?
    let transport: TransportSettings

    func executeGraphQL(document: String, operationType: XGatewayGraphQLOperationType) throws -> [String: Any] {
        let operation = try parseSupportedOperation(document: document, operationType: operationType)
        let authorization = try requireAuthorization(operation: operation)
        let response = try execute(operation: operation, authorization: authorization)
        return ["data": response]
    }

    private func requireAuthorization(operation: SupportedGraphQLOperation) throws -> XGatewayRequestAuthorization {
        if operation.requiresOAuth1 {
            guard let oauth1Credentials else {
                throw XGatewayErrorPayload(
                    code: .authMissing,
                    summary: "OAuth1 authentication configuration missing",
                    details: "\(operation.fieldName).attachments requires complete OAuth1 credentials because Swift media upload uses the X media upload API.",
                    likelyCauses: [
                        "Attachment-backed posting was requested",
                        "OAuth1 credentials were not fully configured"
                    ],
                    remediations: [
                        "Set X_GW_CONSUMER_KEY, X_GW_CONSUMER_SECRET, X_GW_ACCESS_TOKEN, and X_GW_ACCESS_TOKEN_SECRET.",
                        "Retry without attachments if text-only bearer-token posting is sufficient."
                    ],
                    classification: "auth",
                    retryable: false,
                    traceId: traceId
                )
            }
            return .oauth1(oauth1Credentials)
        }
        if !operation.supportsOAuth1 {
            return try requireBearerAuthorization(operation: operation, oauth1Supported: false)
        }
        if let oauth1Credentials {
            return .oauth1(oauth1Credentials)
        }
        return try requireBearerAuthorization(operation: operation, oauth1Supported: true)
    }

    private func requireBearerAuthorization(
        operation: SupportedGraphQLOperation,
        oauth1Supported: Bool
    ) throws -> XGatewayRequestAuthorization {
        guard let token,
              !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            let oauth1Cause = oauth1Supported
                ? "OAuth1 credentials were not fully configured"
                : "OAuth1 credentials are not supported by this Swift usage endpoint"
            let oauth1Remediation = oauth1Supported
                ? "Set X_GW_CONSUMER_KEY, X_GW_CONSUMER_SECRET, X_GW_ACCESS_TOKEN, and X_GW_ACCESS_TOKEN_SECRET for OAuth1 usage."
                : "Set X_GW_TOKEN for bearer-token usage."
            let credentialDetails = oauth1Supported
                ? "\(operation.fieldName) requires X_GW_TOKEN or complete OAuth1 credentials for the current Swift transport slice."
                : "\(operation.fieldName) requires X_GW_TOKEN or --token for the current Swift transport slice."
            throw XGatewayErrorPayload(
                code: .authMissing,
                summary: "Authentication configuration missing",
                details: credentialDetails,
                likelyCauses: [
                    "No bearer token was configured",
                    oauth1Cause
                ],
                remediations: [
                    "Set X_GW_TOKEN to a user-context bearer token with the required X API scope.",
                    oauth1Remediation
                ],
                classification: "auth",
                retryable: false,
                traceId: traceId
            )
        }
        return .bearer(token.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func execute(operation: SupportedGraphQLOperation, authorization: XGatewayRequestAuthorization) throws -> [String: Any] {
        switch operation {
        case .accountMe:
            let payload = try performJSONRequest(
                method: "GET",
                url: URL(string: "https://api.twitter.com/2/users/me?user.fields=id,name,username")!,
                authorization: authorization,
                body: nil
            )
            return [operation.fieldName: XGatewayResponseProjector.account(payload)]
        case .apiUsage(let days):
            let payload = try performJSONRequest(
                method: "GET",
                url: URL(string: "https://api.x.com/2/usage/tweets?\(queryItems(["days": String(days)]))")!,
                authorization: authorization,
                body: nil
            )
            return [operation.fieldName: XGatewayResponseProjector.apiUsage(payload)]
        case .post(let postId, let readOptions, let replyExpansion):
            let options = readOptions.withDefaultMediaRootDir(mediaRootDir)
            let payload = try performJSONRequest(
                method: "GET",
                url: URL(string: "https://api.twitter.com/2/tweets/\(urlPathEscape(postId))?\(tweetLookupQuery)")!,
                authorization: authorization,
                body: nil
            )
            let post = try XGatewayResponseProjector.post(payload, options: options)
            return [operation.fieldName: try hydrateReplies(in: post, expansion: replyExpansion, authorization: authorization)]
        case .searchPosts(let query, let maxResults, let readOptions, let replyExpansion):
            let options = readOptions.withDefaultMediaRootDir(mediaRootDir)
            let payload = try performJSONRequest(
                method: "GET",
                url: URL(string: "https://api.twitter.com/2/tweets/search/recent?\(timelineQueryItems(["query": query, "max_results": String(maxResults)]))")!,
                authorization: authorization,
                body: nil
            )
            let page = try XGatewayResponseProjector.postPage(payload, options: options)
            return [operation.fieldName: try hydrateReplies(inPage: page, expansion: replyExpansion, authorization: authorization)]
        case .homeTimeline(let maxResults, let readOptions, let replyExpansion):
            let options = readOptions.withDefaultMediaRootDir(mediaRootDir)
            let userId = try authenticatedUserId(authorization: authorization)
            let payload = try performJSONRequest(
                method: "GET",
                url: URL(string: "https://api.twitter.com/2/users/\(urlPathEscape(userId))/timelines/reverse_chronological?\(timelineQueryItems(["max_results": String(maxResults)]))")!,
                authorization: authorization,
                body: nil
            )
            let page = try XGatewayResponseProjector.postPage(payload, options: options)
            return [operation.fieldName: try hydrateReplies(inPage: page, expansion: replyExpansion, authorization: authorization)]
        case .followingTimeline(let maxResults, let maxUsers, let maxResultsPerUser, let readOptions, let replyExpansion):
            let options = readOptions.withDefaultMediaRootDir(mediaRootDir)
            let payload = try followingTimeline(
                authorization: authorization,
                maxResults: maxResults,
                maxUsers: maxUsers,
                maxResultsPerUser: maxResultsPerUser
            )
            let page = try XGatewayResponseProjector.postPage(payload, options: options)
            return [operation.fieldName: try hydrateReplies(inPage: page, expansion: replyExpansion, authorization: authorization)]
        case .userTimeline(let userId, let maxResults, let readOptions, let replyExpansion):
            let options = readOptions.withDefaultMediaRootDir(mediaRootDir)
            let payload = try performJSONRequest(
                method: "GET",
                url: URL(string: "https://api.twitter.com/2/users/\(urlPathEscape(userId))/tweets?\(timelineQueryItems(["max_results": String(maxResults)]))")!,
                authorization: authorization,
                body: nil
            )
            let page = try XGatewayResponseProjector.postPage(payload, options: options)
            return [operation.fieldName: try hydrateReplies(inPage: page, expansion: replyExpansion, authorization: authorization)]
        case .mentionsTimeline(let userId, let maxResults, let readOptions, let replyExpansion):
            let options = readOptions.withDefaultMediaRootDir(mediaRootDir)
            let payload = try performJSONRequest(
                method: "GET",
                url: URL(string: "https://api.twitter.com/2/users/\(urlPathEscape(userId))/mentions?\(timelineQueryItems(["max_results": String(maxResults)]))")!,
                authorization: authorization,
                body: nil
            )
            let page = try XGatewayResponseProjector.postPage(payload, options: options)
            return [operation.fieldName: try hydrateReplies(inPage: page, expansion: replyExpansion, authorization: authorization)]
        case .createPost(let text, let attachments):
            var body: [String: Any] = ["text": text]
            if let media = try buildTweetMediaPayload(attachments: attachments, authorization: authorization) {
                body["media"] = media
            }
            let payload = try performJSONRequest(
                method: "POST",
                url: URL(string: "https://api.twitter.com/2/tweets")!,
                authorization: authorization,
                body: body
            )
            return [operation.fieldName: XGatewayResponseProjector.createdPost(payload)]
        case .deletePost(let postId):
            let payload = try performJSONRequest(
                method: "DELETE",
                url: URL(string: "https://api.twitter.com/2/tweets/\(urlPathEscape(postId))")!,
                authorization: authorization,
                body: nil
            )
            return [operation.fieldName: XGatewayResponseProjector.deletedPost(postId: postId, payload)]
        case .replyToPost(let text, let replyToPostId, let attachments):
            var body: [String: Any] = [
                "text": text,
                "reply": ["in_reply_to_tweet_id": replyToPostId]
            ]
            if let media = try buildTweetMediaPayload(attachments: attachments, authorization: authorization) {
                body["media"] = media
            }
            let payload = try performJSONRequest(
                method: "POST",
                url: URL(string: "https://api.twitter.com/2/tweets")!,
                authorization: authorization,
                body: body
            )
            return [operation.fieldName: XGatewayResponseProjector.createdPost(payload)]
        case .quotePost(let text, let quotedPostId, let attachments):
            var body: [String: Any] = [
                "text": text,
                "quote_tweet_id": quotedPostId
            ]
            if let media = try buildTweetMediaPayload(attachments: attachments, authorization: authorization) {
                body["media"] = media
            }
            let payload = try performJSONRequest(
                method: "POST",
                url: URL(string: "https://api.twitter.com/2/tweets")!,
                authorization: authorization,
                body: body
            )
            return [operation.fieldName: XGatewayResponseProjector.createdPost(payload)]
        case .repostPost(let postId):
            let userId = try authenticatedUserId(authorization: authorization)
            let payload = try performJSONRequest(
                method: "POST",
                url: URL(string: "https://api.twitter.com/2/users/\(urlPathEscape(userId))/retweets")!,
                authorization: authorization,
                body: ["tweet_id": postId]
            )
            return [operation.fieldName: XGatewayResponseProjector.repost(postId: postId, payload, defaultReposted: true)]
        case .unrepostPost(let postId):
            let userId = try authenticatedUserId(authorization: authorization)
            let payload = try performJSONRequest(
                method: "DELETE",
                url: URL(string: "https://api.twitter.com/2/users/\(urlPathEscape(userId))/retweets/\(urlPathEscape(postId))")!,
                authorization: authorization,
                body: nil
            )
            return [operation.fieldName: XGatewayResponseProjector.repost(postId: postId, payload, defaultReposted: false)]
        }
    }

    private func hydrateReplies(
        in post: [String: Any],
        expansion: ReplyExpansionRequest?,
        authorization: XGatewayRequestAuthorization
    ) throws -> [String: Any] {
        return try hydrateReplies(in: post, expansion: expansion, authorization: authorization, state: ReplyExpansionState())
    }

    private func hydrateReplies(
        inPage page: [String: Any],
        expansion: ReplyExpansionRequest?,
        authorization: XGatewayRequestAuthorization
    ) throws -> [String: Any] {
        return try hydrateReplies(inPage: page, expansion: expansion, authorization: authorization, state: ReplyExpansionState())
    }

    private func hydrateReplies(
        inPage page: [String: Any],
        expansion: ReplyExpansionRequest?,
        authorization: XGatewayRequestAuthorization,
        state: ReplyExpansionState
    ) throws -> [String: Any] {
        guard let expansion else {
            return page
        }
        var hydrated = page
        var posts: [[String: Any]] = []
        for post in (page["posts"] as? [[String: Any]]) ?? [] {
            posts.append(try hydrateReplies(in: post, expansion: expansion, authorization: authorization, state: state))
        }
        hydrated["posts"] = posts
        return hydrated
    }

    private func hydrateReplies(
        in post: [String: Any],
        expansion: ReplyExpansionRequest?,
        authorization: XGatewayRequestAuthorization,
        state: ReplyExpansionState
    ) throws -> [String: Any] {
        guard let expansion else {
            return post
        }
        guard let postId = post["id"] as? String,
              !postId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw XGatewayErrorPayload(
                code: .internalError,
                summary: "Projected post is missing an id for reply lookup",
                details: "Nested Post.replies requires the parent post projection to include a stable string id.",
                likelyCauses: ["The upstream post payload did not project into the stable Post shape"],
                remediations: ["Retry without selecting Post.replies and inspect the parent post payload."],
                classification: "internal",
                retryable: false,
                traceId: traceId
            )
        }
        let safePostId = try validateReplyLookupPostId(postId)
        state.count += 1
        if state.count > maxReplyExpansions {
            throw validation("Public GraphQL selection 'Post.replies' exceeded the nested reply expansion limit of \(maxReplyExpansions) reply lookups in a single request. Reduce replies maxResults or nesting depth.")
        }

        var query: [String: String] = [
            "query": "in_reply_to_tweet_id:\(safePostId)",
            "max_results": String(expansion.maxResults)
        ]
        if let paginationToken = expansion.paginationToken {
            query["next_token"] = paginationToken
        }
        let payload = try performJSONRequest(
            method: "GET",
            url: URL(string: "https://api.twitter.com/2/tweets/search/recent?\(timelineQueryItems(query))")!,
            authorization: authorization,
            body: nil
        )
        let options = expansion.readOptions.withDefaultMediaRootDir(mediaRootDir)
        let repliesPage = try XGatewayResponseProjector.postPage(payload, options: options)
        var hydrated = post
        hydrated["replies"] = try hydrateReplies(
            inPage: repliesPage,
            expansion: expansion.child,
            authorization: authorization,
            state: state
        )
        return hydrated
    }

    private func followingTimeline(
        authorization: XGatewayRequestAuthorization,
        maxResults: Int,
        maxUsers: Int,
        maxResultsPerUser: Int
    ) throws -> [String: Any] {
        let userId = try authenticatedUserId(authorization: authorization)
        let followingPayload = try performJSONRequest(
            method: "GET",
            url: URL(string: "https://api.twitter.com/2/users/\(urlPathEscape(userId))/following?\(timelineQueryItems(["max_results": String(maxUsers)], includeTweetFields: false))")!,
            authorization: authorization,
            body: nil
        )
        let followedUserIds = extractUserIds(followingPayload).prefix(maxUsers)
        var posts: [[String: Any]] = []
        var includes: [[String: Any]] = []

        for followedUserId in followedUserIds {
            let page = try performJSONRequest(
                method: "GET",
                url: URL(string: "https://api.twitter.com/2/users/\(urlPathEscape(followedUserId))/tweets?\(timelineQueryItems(["max_results": String(maxResultsPerUser)], includeOwnerMetrics: false))")!,
                authorization: authorization,
                body: nil
            )
            if let root = page as? [String: Any] {
                posts.append(contentsOf: (root["data"] as? [[String: Any]]) ?? [])
                if let pageIncludes = root["includes"] as? [String: Any] {
                    includes.append(pageIncludes)
                }
            }
        }

        posts.sort { left, right in
            let leftCreatedAt = (left["created_at"] as? String) ?? ""
            let rightCreatedAt = (right["created_at"] as? String) ?? ""
            return leftCreatedAt > rightCreatedAt
        }

        var result: [String: Any] = [
            "data": Array(posts.prefix(maxResults)),
            "meta": [
                "result_count": min(posts.count, maxResults)
            ]
        ]
        if !includes.isEmpty {
            result["includes"] = mergeIncludes(includes)
        }
        return result
    }

    private func authenticatedUserId(authorization: XGatewayRequestAuthorization) throws -> String {
        let payload = try performJSONRequest(
            method: "GET",
            url: URL(string: "https://api.twitter.com/2/users/me?user.fields=id")!,
            authorization: authorization,
            body: nil
        )
        guard let root = payload as? [String: Any],
              let data = root["data"] as? [String: Any],
              let id = data["id"] as? String,
              !id.isEmpty else {
            throw XGatewayErrorPayload(
                code: .upstreamFailure,
                summary: "Authenticated user id was missing",
                details: "The Swift repost adapter could not read data.id from GET /2/users/me.",
                likelyCauses: ["Unexpected X API response shape", "Bearer token is not user-context capable"],
                remediations: ["Verify X_GW_TOKEN user context and retry.", "Inspect the upstream user lookup response."],
                classification: "upstream",
                retryable: false,
                traceId: traceId
            )
        }
        return id
    }

    private func buildTweetMediaPayload(
        attachments: [PostAttachmentInput]?,
        authorization: XGatewayRequestAuthorization
    ) throws -> [String: Any]? {
        guard let attachments,
              !attachments.isEmpty else {
            return nil
        }
        guard case .oauth1 = authorization else {
            throw XGatewayErrorPayload(
                code: .authMissing,
                summary: "OAuth1 authentication configuration missing",
                details: "Attachment-backed Swift posting requires OAuth1 because media upload is not available through the bearer-token baseline.",
                likelyCauses: ["Attachment-backed posting was requested without complete OAuth1 credentials"],
                remediations: [
                    "Set X_GW_CONSUMER_KEY, X_GW_CONSUMER_SECRET, X_GW_ACCESS_TOKEN, and X_GW_ACCESS_TOKEN_SECRET.",
                    "Retry without attachments if text-only bearer-token posting is sufficient."
                ],
                classification: "auth",
                retryable: false,
                traceId: traceId
            )
        }

        var mediaIds: [String] = []
        mediaIds.reserveCapacity(attachments.count)
        for attachment in attachments {
            let mediaId = try uploadImageAttachment(attachment, authorization: authorization)
            if let altText = attachment.altText {
                try createMediaMetadata(mediaId: mediaId, altText: altText, authorization: authorization)
            }
            mediaIds.append(mediaId)
        }
        return ["media_ids": mediaIds]
    }

    private func uploadImageAttachment(
        _ attachment: PostAttachmentInput,
        authorization: XGatewayRequestAuthorization
    ) throws -> String {
        let media = try readAttachmentData(attachment)
        let mediaType = mimeType(for: attachment.filePath)
        let mediaCategory = mediaCategory(for: mediaType)
        let uploadURL = URL(string: "https://upload.twitter.com/1.1/media/upload.json")!
        let initPayload = try performFormRequest(
            method: "POST",
            url: uploadURL,
            authorization: authorization,
            parameters: [
                ("command", "INIT"),
                ("total_bytes", String(media.count)),
                ("media_type", mediaType),
                ("media_category", mediaCategory)
            ]
        )
        let mediaId = try extractMediaId(from: initPayload)
        let chunkSize = 1_024 * 1_024
        var offset = 0
        var segmentIndex = 0
        while offset < media.count {
            let end = min(offset + chunkSize, media.count)
            let chunk = media.subdata(in: offset..<end)
            _ = try performMultipartRequest(
                method: "POST",
                url: uploadURL,
                authorization: authorization,
                parts: [
                    .field(name: "command", value: "APPEND"),
                    .field(name: "media_id", value: mediaId),
                    .field(name: "segment_index", value: String(segmentIndex)),
                    .file(name: "media", filename: URL(fileURLWithPath: attachment.filePath).lastPathComponent, mimeType: mediaType, data: chunk)
                ]
            )
            offset = end
            segmentIndex += 1
        }

        let finalizePayload = try performFormRequest(
            method: "POST",
            url: uploadURL,
            authorization: authorization,
            parameters: [
                ("command", "FINALIZE"),
                ("media_id", mediaId)
            ]
        )
        try ensureMediaProcessingComplete(mediaId: mediaId, payload: finalizePayload, authorization: authorization)
        return mediaId
    }

    private func createMediaMetadata(
        mediaId: String,
        altText: String,
        authorization: XGatewayRequestAuthorization
    ) throws {
        _ = try performJSONRequest(
            method: "POST",
            url: URL(string: "https://upload.twitter.com/1.1/media/metadata/create.json")!,
            authorization: authorization,
            body: [
                "media_id": mediaId,
                "alt_text": ["text": altText]
            ]
        )
    }

    private func readAttachmentData(_ attachment: PostAttachmentInput) throws -> Data {
        let expandedPath = NSString(string: attachment.filePath).expandingTildeInPath
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: expandedPath, isDirectory: &isDirectory),
              !isDirectory.boolValue else {
            throw validation("attachments.filePath must point to a readable image file.")
        }
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: expandedPath), options: [.mappedIfSafe])
            guard !data.isEmpty else {
                throw validation("attachments.filePath must point to a non-empty image file.")
            }
            return data
        } catch let error as XGatewayErrorPayload {
            throw error
        } catch {
            throw validation("attachments.filePath could not be read: \(error.localizedDescription)")
        }
    }

    private func mimeType(for filePath: String) -> String {
        switch URL(fileURLWithPath: filePath).pathExtension.lowercased() {
        case "png":
            return "image/png"
        case "webp":
            return "image/webp"
        case "gif":
            return "image/gif"
        default:
            return "image/jpeg"
        }
    }

    private func mediaCategory(for mediaType: String) -> String {
        if mediaType == "image/gif" {
            return "TweetGif"
        }
        return "TweetImage"
    }

    private func extractMediaId(from payload: Any) throws -> String {
        guard let root = payload as? [String: Any] else {
            throw XGatewayErrorPayload(
                code: .upstreamFailure,
                summary: "Media upload response was invalid",
                details: "The Swift media upload adapter expected an object response.",
                likelyCauses: ["Unexpected X media upload response shape"],
                remediations: ["Retry and inspect upstream media upload diagnostics if the issue persists."],
                classification: "upstream",
                retryable: false,
                traceId: traceId
            )
        }
        if let mediaId = root["media_id_string"] as? String,
           !mediaId.isEmpty {
            return mediaId
        }
        if let mediaId = root["media_id"] {
            return String(describing: mediaId)
        }
        throw XGatewayErrorPayload(
            code: .upstreamFailure,
            summary: "Media id was missing",
            details: "The Swift media upload adapter could not read media_id_string from the upload response.",
            likelyCauses: ["Unexpected X media upload response shape"],
            remediations: ["Retry and inspect upstream media upload diagnostics if the issue persists."],
            classification: "upstream",
            retryable: false,
            traceId: traceId
        )
    }

    private func ensureMediaProcessingComplete(
        mediaId: String,
        payload: Any,
        authorization: XGatewayRequestAuthorization
    ) throws {
        var currentPayload = payload
        let uploadURL = URL(string: "https://upload.twitter.com/1.1/media/upload.json")!
        for _ in 0..<10 {
            guard let processingInfo = processingInfo(from: currentPayload),
                  let state = processingInfo["state"] as? String else {
                return
            }
            if state == "succeeded" {
                return
            }
            if state == "failed" {
                throw XGatewayErrorPayload(
                    code: .upstreamFailure,
                    summary: "Media processing failed",
                    details: jsonString(processingInfo, pretty: false),
                    likelyCauses: ["X media processing rejected the uploaded file"],
                    remediations: ["Verify the image file format and retry with a supported file."],
                    classification: "upstream",
                    retryable: false,
                    traceId: traceId
                )
            }
            let waitSeconds = max(1, min(intValue(processingInfo["check_after_secs"]), 5))
            Thread.sleep(forTimeInterval: TimeInterval(waitSeconds))
            currentPayload = try performJSONRequest(
                method: "GET",
                url: URL(string: "\(uploadURL.absoluteString)?\(queryItems(["command": "STATUS", "media_id": mediaId]))")!,
                authorization: authorization,
                body: nil
            )
        }
        throw XGatewayErrorPayload(
            code: .upstreamFailure,
            summary: "Media processing did not finish",
            details: "The Swift media upload adapter timed out while waiting for media id \(mediaId).",
            likelyCauses: ["X media processing is still pending"],
            remediations: ["Retry the request later.", "Use a smaller supported image file if processing repeatedly times out."],
            classification: "upstream",
            retryable: true,
            traceId: traceId
        )
    }

    private func processingInfo(from payload: Any) -> [String: Any]? {
        guard let root = payload as? [String: Any] else {
            return nil
        }
        return root["processing_info"] as? [String: Any]
    }

    private func performJSONRequest(
        method: String,
        url: URL,
        authorization: XGatewayRequestAuthorization,
        body: [String: Any]?
    ) throws -> Any {
        return try performRequestWithRetry {
            try performSingleJSONRequest(method: method, url: url, authorization: authorization, body: body)
        }
    }

    private func performFormRequest(
        method: String,
        url: URL,
        authorization: XGatewayRequestAuthorization,
        parameters: [(String, String)]
    ) throws -> Any {
        return try performRequestWithRetry {
            let body = formURLEncodedData(parameters)
            return try performSingleRequest(
                method: method,
                url: url,
                authorization: authorization,
                contentType: "application/x-www-form-urlencoded",
                body: body,
                signatureParameters: parameters
            )
        }
    }

    private func performMultipartRequest(
        method: String,
        url: URL,
        authorization: XGatewayRequestAuthorization,
        parts: [MultipartPart]
    ) throws -> Any {
        return try performRequestWithRetry {
            let boundary = "x-gateway-\(UUID().uuidString)"
            let body = multipartData(parts: parts, boundary: boundary)
            return try performSingleRequest(
                method: method,
                url: url,
                authorization: authorization,
                contentType: "multipart/form-data; boundary=\(boundary)",
                body: body,
                signatureParameters: []
            )
        }
    }

    private func performRequestWithRetry(_ perform: () throws -> Any) throws -> Any {
        var attempt = 0
        while true {
            do {
                return try perform()
            } catch let error as XGatewayErrorPayload {
                guard error.retryable,
                      attempt < transport.retryCount else {
                    throw error
                }
                sleepBeforeRetry(attempt: attempt)
                attempt += 1
            }
        }
    }

    private func performSingleJSONRequest(
        method: String,
        url: URL,
        authorization: XGatewayRequestAuthorization,
        body: [String: Any]?
    ) throws -> Any {
        let bodyData: Data?
        if let body {
            bodyData = try JSONSerialization.data(withJSONObject: body, options: [])
        } else {
            bodyData = nil
        }
        return try performSingleRequest(
            method: method,
            url: url,
            authorization: authorization,
            contentType: body == nil ? nil : "application/json",
            body: bodyData,
            signatureParameters: []
        )
    }

    private func performSingleRequest(
        method: String,
        url: URL,
        authorization: XGatewayRequestAuthorization,
        contentType: String?,
        body: Data?,
        signatureParameters: [(String, String)]
    ) throws -> Any {
        var request = URLRequest(url: url)
        request.httpMethod = method
        applyAuthorizationHeader(
            to: &request,
            method: method,
            url: url,
            authorization: authorization,
            signatureParameters: signatureParameters
        )
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let contentType {
            request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        }
        request.httpBody = body

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = transport.timeoutSeconds
        configuration.timeoutIntervalForResource = transport.timeoutSeconds
        let session = URLSession(configuration: configuration)
        let semaphore = DispatchSemaphore(value: 0)
        var result: Result<(Data, URLResponse), Error>?
        let task = session.dataTask(with: request) { data, response, error in
            if let error {
                result = .failure(error)
            } else {
                result = .success((data ?? Data(), response ?? URLResponse()))
            }
            semaphore.signal()
        }
        task.resume()
        let waitResult = semaphore.wait(timeout: .now() + .milliseconds(max(1, transport.timeoutMs) + 1_000))
        if waitResult == .timedOut {
            task.cancel()
            session.invalidateAndCancel()
            throw XGatewayErrorPayload(
                code: .networkFailure,
                summary: "Network request timed out",
                details: "No response was received within \(transport.timeoutMs)ms.",
                likelyCauses: ["Temporary connectivity loss", "X API did not respond before the configured timeout"],
                remediations: ["Retry with a larger --timeout-ms value", "Check network connectivity and DNS"],
                classification: "network",
                retryable: true,
                traceId: traceId
            )
        }
        session.finishTasksAndInvalidate()

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try result?.get() ?? (Data(), URLResponse())
        } catch {
            throw XGatewayErrorPayload(
                code: .networkFailure,
                summary: "Network request failed",
                details: error.localizedDescription,
                likelyCauses: ["DNS or connection issue", "Temporary connectivity loss", "Timeout while calling X API"],
                remediations: ["Retry with backoff", "Check network connectivity and DNS"],
                classification: "network",
                retryable: true,
                traceId: traceId
            )
        }

        guard let http = response as? HTTPURLResponse else {
            throw XGatewayErrorPayload(
                code: .upstreamFailure,
                summary: "X API returned an invalid response",
                details: "The Swift transport did not receive an HTTP response.",
                likelyCauses: ["Unexpected URLSession response type"],
                remediations: ["Retry and inspect transport diagnostics if the issue persists."],
                classification: "upstream",
                retryable: true,
                traceId: traceId
            )
        }

        let parsed = try parseJSON(data: data)
        if (200...299).contains(http.statusCode) {
            return parsed
        }
        throw mapHTTPError(statusCode: http.statusCode, payload: parsed)
    }

    private func applyAuthorizationHeader(
        to request: inout URLRequest,
        method: String,
        url: URL,
        authorization: XGatewayRequestAuthorization,
        signatureParameters: [(String, String)]
    ) {
        switch authorization {
        case .bearer(let token):
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        case .oauth1(let credentials):
            request.setValue(
                XGatewayOAuth1Signer.authorizationHeader(
                    method: method,
                    url: url,
                    credentials: credentials,
                    queryParameters: signatureParameters
                ),
                forHTTPHeaderField: "Authorization"
            )
        }
    }

    private func sleepBeforeRetry(attempt: Int) {
        let delayMs: Int
        switch transport.retryBackoff {
        case "none":
            delayMs = 0
        case "fixed":
            delayMs = transport.retryBaseMs
        default:
            let exponent = min(attempt, 10)
            let uncapped = transport.retryBaseMs * (1 << exponent)
            let capped = min(uncapped, transport.retryMaxMs)
            delayMs = capped == 0 ? 0 : Int(Double(capped) * Double.random(in: 0.5...1.0))
        }
        if delayMs > 0 {
            Thread.sleep(forTimeInterval: TimeInterval(delayMs) / 1_000)
        }
    }

    private func parseJSON(data: Data) throws -> Any {
        if data.isEmpty {
            return [:] as [String: Any]
        }
        do {
            return try JSONSerialization.jsonObject(with: data, options: [])
        } catch {
            throw XGatewayErrorPayload(
                code: .upstreamFailure,
                summary: "X API returned malformed JSON",
                details: error.localizedDescription,
                likelyCauses: ["Unexpected upstream response body", "Proxy or network middleware returned non-JSON content"],
                remediations: ["Inspect the upstream response and retry after confirming the endpoint."],
                classification: "upstream",
                retryable: false,
                traceId: traceId
            )
        }
    }

    private func mapHTTPError(statusCode: Int, payload: Any) -> XGatewayErrorPayload {
        let detail = jsonString(payload, pretty: false)
        if statusCode == 401 {
            return XGatewayErrorPayload(
                code: .authInvalid,
                summary: "Authentication failed",
                details: detail,
                likelyCauses: ["Bearer token is invalid, expired, revoked, or not user-context capable"],
                remediations: ["Re-issue X_GW_TOKEN and retry", "Confirm token/app pairing and auth mode"],
                classification: "auth",
                retryable: false,
                traceId: traceId
            )
        }
        if statusCode == 403 {
            return XGatewayErrorPayload(
                code: .permissionDenied,
                summary: "Authorization failed",
                details: detail,
                likelyCauses: ["Token lacks required scope", "X API plan or app settings do not permit this operation"],
                remediations: ["Grant required read/write scope", "Use credentials for an app with the required access"],
                classification: "permission",
                retryable: false,
                traceId: traceId
            )
        }
        if statusCode == 404 {
            return XGatewayErrorPayload(
                code: .resourceNotFound,
                summary: "Requested resource was not found",
                details: detail,
                likelyCauses: ["Resource id is invalid", "Resource is deleted or inaccessible"],
                remediations: ["Verify the resource identifier", "Check resource visibility"],
                classification: "upstream",
                retryable: false,
                traceId: traceId
            )
        }
        if statusCode == 429 {
            return XGatewayErrorPayload(
                code: .rateLimited,
                summary: "Rate limit exceeded",
                details: detail,
                likelyCauses: ["Too many requests in current window", "Quota exhausted"],
                remediations: ["Retry after the rate-limit window", "Lower request frequency"],
                classification: "rate_limit",
                retryable: true,
                traceId: traceId
            )
        }
        return XGatewayErrorPayload(
            code: .upstreamFailure,
            summary: "X API returned an error",
            details: detail,
            likelyCauses: ["API credentials are missing required access", "Requested operation is blocked by account/app settings"],
            remediations: ["Verify credential scopes and X app permissions", "Review X developer portal app/token status"],
            classification: "upstream",
            retryable: statusCode >= 500,
            traceId: traceId
        )
    }
}

private enum SupportedGraphQLOperation {
    case accountMe
    case apiUsage(days: Int)
    case post(postId: String, readOptions: XGatewayPostReadOptions, replyExpansion: ReplyExpansionRequest?)
    case searchPosts(query: String, maxResults: Int, readOptions: XGatewayPostReadOptions, replyExpansion: ReplyExpansionRequest?)
    case homeTimeline(maxResults: Int, readOptions: XGatewayPostReadOptions, replyExpansion: ReplyExpansionRequest?)
    case followingTimeline(maxResults: Int, maxUsers: Int, maxResultsPerUser: Int, readOptions: XGatewayPostReadOptions, replyExpansion: ReplyExpansionRequest?)
    case userTimeline(userId: String, maxResults: Int, readOptions: XGatewayPostReadOptions, replyExpansion: ReplyExpansionRequest?)
    case mentionsTimeline(userId: String, maxResults: Int, readOptions: XGatewayPostReadOptions, replyExpansion: ReplyExpansionRequest?)
    case createPost(text: String, attachments: [PostAttachmentInput]?)
    case deletePost(postId: String)
    case replyToPost(text: String, replyToPostId: String, attachments: [PostAttachmentInput]?)
    case quotePost(text: String, quotedPostId: String, attachments: [PostAttachmentInput]?)
    case repostPost(postId: String)
    case unrepostPost(postId: String)

    var fieldName: String {
        switch self {
        case .accountMe:
            return "accountMe"
        case .apiUsage:
            return "apiUsage"
        case .post:
            return "post"
        case .searchPosts:
            return "searchPosts"
        case .homeTimeline:
            return "homeTimeline"
        case .followingTimeline:
            return "followingTimeline"
        case .userTimeline:
            return "userTimeline"
        case .mentionsTimeline:
            return "mentionsTimeline"
        case .createPost:
            return "createPost"
        case .deletePost:
            return "deletePost"
        case .replyToPost:
            return "replyToPost"
        case .quotePost:
            return "quotePost"
        case .repostPost:
            return "repostPost"
        case .unrepostPost:
            return "unrepostPost"
        }
    }

    var supportsOAuth1: Bool {
        switch self {
        case .apiUsage:
            return false
        default:
            return true
        }
    }

    var requiresOAuth1: Bool {
        switch self {
        case .createPost(_, let attachments),
             .replyToPost(_, _, let attachments),
             .quotePost(_, _, let attachments):
            return attachments?.isEmpty == false
        default:
            return false
        }
    }
}

private struct PostAttachmentInput {
    let kind: String
    let filePath: String
    let altText: String?
}

private enum GraphQLInputValue {
    case string(String)
    case null
}

private struct GraphQLRootField {
    let name: String
    let argumentLiteral: String
}

private struct ResolvedGraphQLRootOperation {
    let fieldName: String?
    let argumentLiteral: String
}

private let supportedQueryGraphQLFields = [
    "accountMe",
    "apiUsage",
    "searchPosts",
    "homeTimeline",
    "followingTimeline",
    "userTimeline",
    "mentionsTimeline",
    "post"
]

private let supportedMutationGraphQLFields = [
    "createPost",
    "deletePost",
    "replyToPost",
    "quotePost",
    "unrepostPost",
    "repostPost"
]

private func parseSupportedOperation(
    document: String,
    operationType: XGatewayGraphQLOperationType
) throws -> SupportedGraphQLOperation {
    let resolvedOperation = try resolveSupportedGraphQLRootOperation(in: document, operationType: operationType)
    let fieldName = resolvedOperation.fieldName
    let arguments = resolvedOperation.argumentLiteral
    switch operationType {
    case .query:
        if fieldName == "accountMe" {
            try validateGraphQLArguments(in: arguments, allowed: [], fieldName: "accountMe")
            return .accountMe
        }
        if fieldName == "apiUsage" {
            try validateGraphQLArguments(in: arguments, allowed: ["days"], fieldName: "apiUsage")
            return .apiUsage(days: try extractOptionalIntArgument("days", from: arguments, defaultValue: 1, minimum: 1, maximum: 90, fieldName: "apiUsage"))
        }
        if fieldName == "searchPosts" {
            try validateGraphQLArguments(
                in: arguments,
                allowed: ["query", "maxResults", "paginationToken", "mediaRootDir", "downloadMedia", "forceDownload", "includePromoted"],
                fieldName: "searchPosts"
            )
            return .searchPosts(
                query: try extractStringArgument("query", from: arguments, fieldName: "searchPosts"),
                maxResults: try extractOptionalIntArgument("maxResults", from: arguments, defaultValue: 10, minimum: 10, maximum: 100, fieldName: "searchPosts"),
                readOptions: try extractPostReadOptions(from: arguments, fieldName: "searchPosts"),
                replyExpansion: try extractReplyExpansion(from: document, selectionPath: "searchPosts.posts")
            )
        }
        if fieldName == "homeTimeline" {
            try validateGraphQLArguments(
                in: arguments,
                allowed: ["maxResults", "paginationToken", "mediaRootDir", "downloadMedia", "forceDownload", "includePromoted"],
                fieldName: "homeTimeline"
            )
            return .homeTimeline(
                maxResults: try extractOptionalIntArgument("maxResults", from: arguments, defaultValue: 10, minimum: 5, maximum: 100, fieldName: "homeTimeline"),
                readOptions: try extractPostReadOptions(from: arguments, fieldName: "homeTimeline"),
                replyExpansion: try extractReplyExpansion(from: document, selectionPath: "homeTimeline.posts")
            )
        }
        if fieldName == "followingTimeline" {
            try validateGraphQLArguments(
                in: arguments,
                allowed: ["maxResults", "maxUsers", "maxResultsPerUser", "paginationToken", "mediaRootDir", "downloadMedia", "forceDownload", "includePromoted"],
                fieldName: "followingTimeline"
            )
            return .followingTimeline(
                maxResults: try extractOptionalIntArgument("maxResults", from: arguments, defaultValue: 10, minimum: 1, maximum: 100, fieldName: "followingTimeline"),
                maxUsers: try extractOptionalIntArgument("maxUsers", from: arguments, defaultValue: 25, minimum: 1, maximum: 100, fieldName: "followingTimeline"),
                maxResultsPerUser: try extractOptionalIntArgument("maxResultsPerUser", from: arguments, defaultValue: 10, minimum: 5, maximum: 100, fieldName: "followingTimeline"),
                readOptions: try extractPostReadOptions(from: arguments, fieldName: "followingTimeline"),
                replyExpansion: try extractReplyExpansion(from: document, selectionPath: "followingTimeline.posts")
            )
        }
        if fieldName == "userTimeline" {
            try validateGraphQLArguments(
                in: arguments,
                allowed: ["userId", "maxResults", "paginationToken", "mediaRootDir", "downloadMedia", "forceDownload", "includePromoted"],
                fieldName: "userTimeline"
            )
            return .userTimeline(
                userId: try extractStringArgument("userId", from: arguments, fieldName: "userTimeline"),
                maxResults: try extractOptionalIntArgument("maxResults", from: arguments, defaultValue: 10, minimum: 5, maximum: 100, fieldName: "userTimeline"),
                readOptions: try extractPostReadOptions(from: arguments, fieldName: "userTimeline"),
                replyExpansion: try extractReplyExpansion(from: document, selectionPath: "userTimeline.posts")
            )
        }
        if fieldName == "mentionsTimeline" {
            try validateGraphQLArguments(
                in: arguments,
                allowed: ["userId", "maxResults", "paginationToken", "mediaRootDir", "downloadMedia", "forceDownload", "includePromoted"],
                fieldName: "mentionsTimeline"
            )
            return .mentionsTimeline(
                userId: try extractStringArgument("userId", from: arguments, fieldName: "mentionsTimeline"),
                maxResults: try extractOptionalIntArgument("maxResults", from: arguments, defaultValue: 10, minimum: 5, maximum: 100, fieldName: "mentionsTimeline"),
                readOptions: try extractPostReadOptions(from: arguments, fieldName: "mentionsTimeline"),
                replyExpansion: try extractReplyExpansion(from: document, selectionPath: "mentionsTimeline.posts")
            )
        }
        if fieldName == "post" {
            try validateGraphQLArguments(
                in: arguments,
                allowed: ["id", "mediaRootDir", "downloadMedia", "forceDownload", "includePromoted"],
                fieldName: "post"
            )
            return .post(
                postId: try extractStringArgument("id", from: arguments, fieldName: "post"),
                readOptions: try extractPostReadOptions(from: arguments, fieldName: "post"),
                replyExpansion: try extractReplyExpansion(from: document, selectionPath: "post")
            )
        }
    case .mutation:
        if fieldName == "createPost" {
            try validateGraphQLArguments(in: arguments, allowed: ["text", "attachments"], fieldName: "createPost")
            return .createPost(
                text: try extractStringArgument("text", from: arguments, fieldName: "createPost"),
                attachments: try extractPostAttachmentsIfPresent(from: arguments, fieldName: "createPost")
            )
        }
        if fieldName == "deletePost" {
            try validateGraphQLArguments(in: arguments, allowed: ["postId"], fieldName: "deletePost")
            return .deletePost(postId: try extractStringArgument("postId", from: arguments, fieldName: "deletePost"))
        }
        if fieldName == "replyToPost" {
            try validateGraphQLArguments(in: arguments, allowed: ["text", "replyToPostId", "attachments"], fieldName: "replyToPost")
            return .replyToPost(
                text: try extractStringArgument("text", from: arguments, fieldName: "replyToPost"),
                replyToPostId: try extractStringArgument("replyToPostId", from: arguments, fieldName: "replyToPost"),
                attachments: try extractPostAttachmentsIfPresent(from: arguments, fieldName: "replyToPost")
            )
        }
        if fieldName == "quotePost" {
            try validateGraphQLArguments(in: arguments, allowed: ["text", "quotedPostId", "attachments"], fieldName: "quotePost")
            return .quotePost(
                text: try extractStringArgument("text", from: arguments, fieldName: "quotePost"),
                quotedPostId: try extractStringArgument("quotedPostId", from: arguments, fieldName: "quotePost"),
                attachments: try extractPostAttachmentsIfPresent(from: arguments, fieldName: "quotePost")
            )
        }
        if fieldName == "unrepostPost" {
            try validateGraphQLArguments(in: arguments, allowed: ["postId"], fieldName: "unrepostPost")
            return .unrepostPost(postId: try extractStringArgument("postId", from: arguments, fieldName: "unrepostPost"))
        }
        if fieldName == "repostPost" {
            try validateGraphQLArguments(in: arguments, allowed: ["postId"], fieldName: "repostPost")
            return .repostPost(postId: try extractStringArgument("postId", from: arguments, fieldName: "repostPost"))
        }
    }

    throw XGatewayErrorPayload(
        code: .unsupported,
        summary: "Swift GraphQL field is not implemented yet",
        details: "This Swift migration slice supports accountMe, apiUsage, post, searchPosts, homeTimeline, followingTimeline, userTimeline, mentionsTimeline, createPost, deletePost, replyToPost, quotePost, repostPost, and unrepostPost.",
        likelyCauses: ["The requested project-owned GraphQL field has not been ported to Swift yet"],
        remediations: [
            "Use one of the Swift-supported project-owned GraphQL fields listed in this error.",
            "Add a reviewed Swift transport adapter before exposing another project-owned GraphQL field."
        ],
        classification: "unsupported",
        retryable: false,
        traceId: nil
    )
}

private func resolveSupportedGraphQLRootOperation(
    in document: String,
    operationType: XGatewayGraphQLOperationType
) throws -> ResolvedGraphQLRootOperation {
    try validateSingleGraphQLExecutableDocument(in: document)

    let supportedFields: [String]
    switch operationType {
    case .query:
        supportedFields = supportedQueryGraphQLFields
    case .mutation:
        supportedFields = supportedMutationGraphQLFields
    }
    let supported = Set(supportedFields)

    if let rootSelection = try graphQLRootSelectionLiteral(in: document, operationType: operationType) {
        let rootFields = try graphQLRootFields(in: rootSelection)
        if rootFields.isEmpty {
            throw validation("Public GraphQL requests support exactly one top-level field; found none.")
        }
        if rootFields.count > 1 {
            throw validation("Public GraphQL requests support exactly one top-level field; found \(rootFields.map(\.name).joined(separator: ", ")).")
        }
        if let field = rootFields.first,
           supported.contains(field.name) {
            return ResolvedGraphQLRootOperation(fieldName: field.name, argumentLiteral: field.argumentLiteral)
        }
        return ResolvedGraphQLRootOperation(fieldName: nil, argumentLiteral: "")
    }

    if let field = supportedFields.first(where: { hasGraphQLField($0, in: document) }) {
        return ResolvedGraphQLRootOperation(
            fieldName: field,
            argumentLiteral: try graphQLFieldArgumentLiteral(field, in: document)
        )
    }
    return ResolvedGraphQLRootOperation(fieldName: nil, argumentLiteral: "")
}

private func validateSingleGraphQLExecutableDocument(in source: String) throws {
    var operationDefinitionCount = 0
    var index = skipGraphQLIgnored(in: source, from: source.startIndex)
    while index < source.endIndex {
        if let nextIndex = indexAfterGraphQLComment(in: source, from: index) {
            index = skipGraphQLIgnored(in: source, from: nextIndex)
            continue
        }
        if source[index] == "{" {
            operationDefinitionCount += 1
            try validateSingleGraphQLOperationDefinitionCount(operationDefinitionCount)
            index = try extractBalancedLiteral(
                from: source,
                startingAt: index,
                opening: "{",
                closing: "}",
                context: "anonymous query selection"
            ).nextIndex
            index = skipGraphQLIgnored(in: source, from: index)
            continue
        }
        guard isGraphQLNameStart(source[index]) else {
            throw validation("Unexpected GraphQL token '\(source[index])' outside the operation definition. Public GraphQL requests support exactly one query or mutation operation definition.")
        }

        let start = index
        index = source.index(after: index)
        while index < source.endIndex,
              isGraphQLIdentifierCharacter(source[index]) {
            index = source.index(after: index)
        }
        let token = String(source[start..<index])
        if token == "fragment" {
            throw validation("Public GraphQL fragments are not supported yet.")
        }
        if token == "subscription" {
            throw validation("Public GraphQL subscriptions are not supported.")
        }
        if token == "query" || token == "mutation" {
            operationDefinitionCount += 1
            try validateSingleGraphQLOperationDefinitionCount(operationDefinitionCount)
            index = try indexAfterGraphQLOperationDefinition(
                in: source,
                from: index,
                operationLabel: token
            )
            index = skipGraphQLIgnored(in: source, from: index)
            continue
        }
        throw validation("Unexpected GraphQL token '\(token)' outside the operation definition. Public GraphQL requests support exactly one query or mutation operation definition.")
    }
}

private func validateSingleGraphQLOperationDefinitionCount(_ count: Int) throws {
    if count > 1 {
        throw validation("Public GraphQL requests support exactly one operation definition.")
    }
}

private func hasGraphQLField(_ name: String, in source: String) -> Bool {
    return rangeOfGraphQLField(name, in: source) != nil
}

private func graphQLRootSelectionLiteral(
    in source: String,
    operationType: XGatewayGraphQLOperationType
) throws -> String? {
    let firstToken = skipGraphQLIgnored(in: source, from: source.startIndex)
    if operationType == .query,
       firstToken < source.endIndex,
       source[firstToken] == "{" {
        return try extractBalancedLiteral(
            from: source,
            startingAt: firstToken,
            opening: "{",
            closing: "}",
            context: "root selection"
        ).literal
    }

    var inString = false
    var escaping = false
    var index = firstToken

    while index < source.endIndex {
        let character = source[index]
        if inString {
            if escaping {
                escaping = false
            } else if character == "\\" {
                escaping = true
            } else if character == "\"" {
                inString = false
            }
            index = source.index(after: index)
            continue
        }

        if character == "\"" {
            inString = true
            index = source.index(after: index)
            continue
        }
        if let nextIndex = indexAfterGraphQLComment(in: source, from: index) {
            index = nextIndex
            continue
        }
        if character == "{" {
            index = try extractBalancedLiteral(
                from: source,
                startingAt: index,
                opening: "{",
                closing: "}",
                context: "non-operation selection"
            ).nextIndex
            continue
        }
        guard isGraphQLNameStart(character) else {
            index = source.index(after: index)
            continue
        }

        let start = index
        index = source.index(after: index)
        while index < source.endIndex,
              isGraphQLIdentifierCharacter(source[index]) {
            index = source.index(after: index)
        }
        if source[start..<index] == operationType.rawValue[...] {
            if let rootSelection = try graphQLRootSelectionLiteralAfterOperationKeyword(
                in: source,
                from: index,
                operationType: operationType
            ) {
                return rootSelection
            }
        }
    }

    return nil
}

private func graphQLRootSelectionLiteralAfterOperationKeyword(
    in source: String,
    from keywordEnd: String.Index,
    operationType: XGatewayGraphQLOperationType
) throws -> String? {
    return try graphQLOperationRootSelection(
        in: source,
        from: keywordEnd,
        operationLabel: operationType.rawValue
    )?.literal
}

private func indexAfterGraphQLOperationDefinition(
    in source: String,
    from keywordEnd: String.Index,
    operationLabel: String
) throws -> String.Index {
    return try graphQLOperationRootSelection(
        in: source,
        from: keywordEnd,
        operationLabel: operationLabel
    )?.nextIndex ?? keywordEnd
}

private func graphQLOperationRootSelection(
    in source: String,
    from keywordEnd: String.Index,
    operationLabel: String
) throws -> (literal: String, nextIndex: String.Index)? {
    var index = skipGraphQLIgnored(in: source, from: keywordEnd)
    if index < source.endIndex,
       isGraphQLNameStart(source[index]) {
        index = source.index(after: index)
        while index < source.endIndex,
              isGraphQLIdentifierCharacter(source[index]) {
            index = source.index(after: index)
        }
        index = skipGraphQLIgnored(in: source, from: index)
    }
    if index < source.endIndex,
       source[index] == "(" {
        index = try extractBalancedLiteral(
            from: source,
            startingAt: index,
            opening: "(",
            closing: ")",
            context: "\(operationLabel) variable definitions"
        ).nextIndex
    }
    index = try rejectGraphQLDirectivesIfPresent(in: source, from: index)
    index = skipGraphQLIgnored(in: source, from: index)
    guard index < source.endIndex,
          source[index] == "{" else {
        return nil
    }
    return try extractBalancedLiteral(
        from: source,
        startingAt: index,
        opening: "{",
        closing: "}",
        context: "root selection"
    )
}

private func graphQLRootFields(in selectionLiteral: String) throws -> [GraphQLRootField] {
    var fields: [GraphQLRootField] = []
    var inString = false
    var escaping = false
    var depth = 0
    var index = selectionLiteral.startIndex

    while index < selectionLiteral.endIndex {
        let character = selectionLiteral[index]
        if inString {
            if escaping {
                escaping = false
            } else if character == "\\" {
                escaping = true
            } else if character == "\"" {
                inString = false
            }
            index = selectionLiteral.index(after: index)
            continue
        }

        if character == "\"" {
            inString = true
            index = selectionLiteral.index(after: index)
            continue
        }
        if let nextIndex = indexAfterGraphQLComment(in: selectionLiteral, from: index) {
            index = nextIndex
            continue
        }
        if selectionLiteral[index...].hasPrefix("...") {
            throw validation("Public GraphQL fragments are not supported yet.")
        }
        if character == "@" {
            throw validation("Public GraphQL directives are not supported yet.")
        }
        if character == "{" {
            depth += 1
            index = selectionLiteral.index(after: index)
            continue
        }
        if character == "}" {
            depth -= 1
            index = selectionLiteral.index(after: index)
            continue
        }
        guard depth == 1,
              isGraphQLNameStart(character) else {
            index = selectionLiteral.index(after: index)
            continue
        }

        let firstNameStart = index
        index = selectionLiteral.index(after: index)
        while index < selectionLiteral.endIndex,
              isGraphQLIdentifierCharacter(selectionLiteral[index]) {
            index = selectionLiteral.index(after: index)
        }
        if firstNameStart > selectionLiteral.startIndex,
           selectionLiteral[selectionLiteral.index(before: firstNameStart)] == "@" {
            throw validation("Public GraphQL directives are not supported yet.")
        }
        if firstNameStart > selectionLiteral.startIndex,
           selectionLiteral[selectionLiteral.index(before: firstNameStart)] == "$" {
            continue
        }
        let hasFragmentSpread = hasGraphQLFragmentSpreadBeforeName(in: selectionLiteral, before: firstNameStart)
        if hasFragmentSpread {
            throw validation("Public GraphQL fragments are not supported yet.")
        }
        let fieldName = String(selectionLiteral[firstNameStart..<index])
        let afterFirstName = skipGraphQLIgnored(in: selectionLiteral, from: index)
        if afterFirstName < selectionLiteral.endIndex,
           selectionLiteral[afterFirstName] == ":" {
            throw validation("Public GraphQL aliases are not supported yet.")
        }
        let tail = try skipGraphQLRootFieldTail(in: selectionLiteral, from: index)
        fields.append(GraphQLRootField(name: fieldName, argumentLiteral: tail.argumentLiteral))
        index = tail.nextIndex
    }

    return fields
}

private func skipGraphQLRootFieldTail(
    in selectionLiteral: String,
    from startIndex: String.Index
) throws -> (argumentLiteral: String, nextIndex: String.Index) {
    var index = skipGraphQLIgnored(in: selectionLiteral, from: startIndex)
    var argumentLiteral = ""
    if index < selectionLiteral.endIndex,
       selectionLiteral[index] == "(" {
        let extracted = try extractBalancedLiteral(
            from: selectionLiteral,
            startingAt: index,
            opening: "(",
            closing: ")",
            context: "root field arguments"
        )
        argumentLiteral = extracted.literal
        index = extracted.nextIndex
    }
    return (argumentLiteral, try rejectGraphQLDirectivesIfPresent(in: selectionLiteral, from: index))
}

private func rejectGraphQLDirectivesIfPresent(in selectionLiteral: String, from startIndex: String.Index) throws -> String.Index {
    let index = skipGraphQLIgnored(in: selectionLiteral, from: startIndex)
    if index < selectionLiteral.endIndex,
       selectionLiteral[index] == "@" {
        throw validation("Public GraphQL directives are not supported yet.")
    }
    return index
}

private func graphQLFieldArgumentLiteral(_ name: String, in source: String) throws -> String {
    guard let fieldRange = rangeOfGraphQLField(name, in: source) else {
        throw validation("Public GraphQL field '\(name)' was not found.")
    }
    let index = skipGraphQLIgnored(in: source, from: fieldRange.upperBound)
    guard index < source.endIndex,
          source[index] == "(" else {
        return ""
    }
    return try extractBalancedLiteral(
        from: source,
        startingAt: index,
        opening: "(",
        closing: ")",
        context: "\(name) arguments"
    ).literal
}

private func extractPostAttachmentsIfPresent(
    from document: String,
    fieldName: String
) throws -> [PostAttachmentInput]? {
    guard let nameRange = rangeOfGraphQLArgument("attachments", in: document) else {
        return nil
    }

    let index = skipGraphQLIgnored(in: document, from: nameRange.upperBound)
    guard index < document.endIndex,
          document[index] == "[" else {
        throw validation("attachments must contain between 1 and 4 items when provided.")
    }

    let extracted = try extractBalancedLiteral(
        from: document,
        startingAt: index,
        opening: "[",
        closing: "]",
        context: "\(fieldName).attachments"
    )
    return try parsePostAttachmentList(extracted.literal, fieldName: fieldName)
}

private func extractPostReadOptions(from document: String, fieldName: String) throws -> XGatewayPostReadOptions {
    return XGatewayPostReadOptions(
        mediaRootDir: try extractOptionalStringArgument("mediaRootDir", from: document, fieldName: fieldName),
        downloadMedia: try extractOptionalBoolArgument("downloadMedia", from: document, defaultValue: true, fieldName: fieldName),
        forceDownload: try extractOptionalBoolArgument("forceDownload", from: document, defaultValue: false, fieldName: fieldName),
        includePromoted: try extractOptionalBoolArgument("includePromoted", from: document, defaultValue: false, fieldName: fieldName)
    )
}

private func extractReplyExpansion(from document: String, selectionPath: String) throws -> ReplyExpansionRequest? {
    guard let fieldRange = rangeOfGraphQLField("replies", in: document) else {
        return nil
    }
    var index = skipGraphQLIgnored(in: document, from: fieldRange.upperBound)
    let argumentLiteral: String
    if index < document.endIndex,
       document[index] == "(" {
        let extracted = try extractBalancedLiteral(
            from: document,
            startingAt: index,
            opening: "(",
            closing: ")",
            context: "\(selectionPath).replies"
        )
        argumentLiteral = extracted.literal
        index = skipGraphQLIgnored(in: document, from: extracted.nextIndex)
    } else {
        argumentLiteral = ""
    }

    let allowedArguments: Set<String> = [
        "maxResults",
        "paginationToken",
        "mediaRootDir",
        "downloadMedia",
        "forceDownload",
        "includePromoted"
    ]
    for argumentName in graphQLArgumentNames(in: argumentLiteral) where !allowedArguments.contains(argumentName) {
        throw validation("Public GraphQL selection '\(selectionPath).replies' does not accept argument '\(argumentName)'.")
    }

    guard index < document.endIndex,
          document[index] == "{" else {
        throw validation("Public GraphQL selection '\(selectionPath).replies' must include a nested selection set.")
    }
    let selectionLiteral = try extractBalancedLiteral(
        from: document,
        startingAt: index,
        opening: "{",
        closing: "}",
        context: "\(selectionPath).replies"
    ).literal

    return ReplyExpansionRequest(
        maxResults: try extractOptionalIntArgument("maxResults", from: argumentLiteral, defaultValue: 10, minimum: 10, maximum: 100, fieldName: "\(selectionPath).replies"),
        paginationToken: try extractOptionalStringArgument("paginationToken", from: argumentLiteral, fieldName: "\(selectionPath).replies"),
        readOptions: try extractPostReadOptions(from: argumentLiteral, fieldName: "\(selectionPath).replies"),
        child: try extractReplyExpansion(from: selectionLiteral, selectionPath: "\(selectionPath).replies.posts")
    )
}

private func validateGraphQLArguments(in argumentLiteral: String, allowed: Set<String>, fieldName: String) throws {
    for argumentName in graphQLArgumentNames(in: argumentLiteral) where !allowed.contains(argumentName) {
        throw validation("Public GraphQL field '\(fieldName)' does not accept argument '\(argumentName)'.")
    }
}

private func rangeOfGraphQLArgument(_ name: String, in source: String) -> Range<String.Index>? {
    var inString = false
    var escaping = false
    var index = source.startIndex
    var nestingDepth = 0
    let targetDepth = graphQLTopLevelArgumentDepth(in: source)

    while index < source.endIndex {
        let character = source[index]
        if inString {
            if escaping {
                escaping = false
            } else if character == "\\" {
                escaping = true
            } else if character == "\"" {
                inString = false
            }
            index = source.index(after: index)
            continue
        }

        if character == "\"" {
            inString = true
            index = source.index(after: index)
            continue
        }
        if let nextIndex = indexAfterGraphQLComment(in: source, from: index) {
            index = nextIndex
            continue
        }
        if character == "(" || character == "[" || character == "{" {
            nestingDepth += 1
            index = source.index(after: index)
            continue
        }
        if character == ")" || character == "]" || character == "}" {
            nestingDepth = max(0, nestingDepth - 1)
            index = source.index(after: index)
            continue
        }

        guard nestingDepth == targetDepth,
              isGraphQLNameStart(character) else {
            index = source.index(after: index)
            continue
        }

        let start = index
        index = source.index(after: index)
        while index < source.endIndex,
              isGraphQLIdentifierCharacter(source[index]) {
            index = source.index(after: index)
        }
        if source[start..<index] == name[...] {
            let colonIndex = skipGraphQLIgnored(in: source, from: index)
            if colonIndex < source.endIndex,
               source[colonIndex] == ":" {
                return start..<source.index(after: colonIndex)
            }
        }
    }

    return nil
}

private func rangeOfGraphQLField(_ name: String, in source: String) -> Range<String.Index>? {
    var inString = false
    var escaping = false
    var index = source.startIndex
    var previousName: String?

    while index < source.endIndex {
        let character = source[index]
        if inString {
            if escaping {
                escaping = false
            } else if character == "\\" {
                escaping = true
            } else if character == "\"" {
                inString = false
            }
            index = source.index(after: index)
            continue
        }

        if character == "\"" {
            inString = true
            index = source.index(after: index)
            continue
        }
        if let nextIndex = indexAfterGraphQLComment(in: source, from: index) {
            index = nextIndex
            continue
        }

        guard isGraphQLNameStart(character) else {
            if !isGraphQLWhitespace(character) {
                previousName = nil
            }
            index = source.index(after: index)
            continue
        }

        let start = index
        index = source.index(after: index)
        while index < source.endIndex,
              isGraphQLIdentifierCharacter(source[index]) {
            index = source.index(after: index)
        }
        let foundName = String(source[start..<index])
        if foundName == name {
            let afterName = skipGraphQLIgnored(in: source, from: index)
            let isAliasName = afterName < source.endIndex && source[afterName] == ":"
            let isDefinitionName = previousName == "query"
                || previousName == "mutation"
                || previousName == "subscription"
                || previousName == "fragment"
                || previousName == "on"
            let isDirectiveName = start > source.startIndex && source[source.index(before: start)] == "@"
            let isVariableName = start > source.startIndex && source[source.index(before: start)] == "$"
            let isFragmentSpreadName = hasGraphQLFragmentSpreadBeforeName(in: source, before: start)
            if !isAliasName && !isDefinitionName && !isDirectiveName && !isVariableName && !isFragmentSpreadName {
                return start..<index
            }
        }
        previousName = foundName
    }

    return nil
}

private func graphQLArgumentNames(in argumentLiteral: String) -> [String] {
    var names: [String] = []
    var inString = false
    var escaping = false
    var index = argumentLiteral.startIndex
    var nestingDepth = 0
    let targetDepth = graphQLTopLevelArgumentDepth(in: argumentLiteral)

    while index < argumentLiteral.endIndex {
        let character = argumentLiteral[index]
        if inString {
            if escaping {
                escaping = false
            } else if character == "\\" {
                escaping = true
            } else if character == "\"" {
                inString = false
            }
            index = argumentLiteral.index(after: index)
            continue
        }

        if character == "\"" {
            inString = true
            index = argumentLiteral.index(after: index)
            continue
        }
        if let nextIndex = indexAfterGraphQLComment(in: argumentLiteral, from: index) {
            index = nextIndex
            continue
        }
        if character == "(" || character == "[" || character == "{" {
            nestingDepth += 1
            index = argumentLiteral.index(after: index)
            continue
        }
        if character == ")" || character == "]" || character == "}" {
            nestingDepth = max(0, nestingDepth - 1)
            index = argumentLiteral.index(after: index)
            continue
        }

        guard nestingDepth == targetDepth,
              isGraphQLNameStart(character) else {
            index = argumentLiteral.index(after: index)
            continue
        }

        let start = index
        index = argumentLiteral.index(after: index)
        while index < argumentLiteral.endIndex,
              isGraphQLIdentifierCharacter(argumentLiteral[index]) {
            index = argumentLiteral.index(after: index)
        }
        let name = String(argumentLiteral[start..<index])
        let afterName = skipGraphQLIgnored(in: argumentLiteral, from: index)
        if afterName < argumentLiteral.endIndex,
           argumentLiteral[afterName] == ":" {
            names.append(name)
        }
    }

    return names
}

private func graphQLTopLevelArgumentDepth(in source: String) -> Int {
    let firstToken = skipGraphQLIgnored(in: source, from: source.startIndex)
    if firstToken < source.endIndex,
       source[firstToken] == "(" {
        return 1
    }
    return 0
}

private func isGraphQLNameStart(_ character: Character) -> Bool {
    return character == "_" || character.isLetter
}

private func isGraphQLIdentifierCharacter(_ character: Character) -> Bool {
    return character == "_" || character.isLetter || character.isNumber
}

private func isGraphQLWhitespace(_ character: Character) -> Bool {
    return character == " " || character == "\n" || character == "\t" || character == "\r"
}

private func hasGraphQLFragmentSpreadBeforeName(in source: String, before nameStart: String.Index) -> Bool {
    var index = nameStart
    while index > source.startIndex {
        let previous = source.index(before: index)
        if !isGraphQLWhitespace(source[previous]) {
            break
        }
        index = previous
    }

    var dotIndex = index
    for _ in 0..<3 {
        guard dotIndex > source.startIndex else {
            return false
        }
        dotIndex = source.index(before: dotIndex)
        guard source[dotIndex] == "." else {
            return false
        }
    }
    return true
}

private func parsePostAttachmentList(_ literal: String, fieldName: String) throws -> [PostAttachmentInput] {
    let inner = String(literal.dropFirst().dropLast())
    var attachments: [PostAttachmentInput] = []
    var index = skipGraphQLIgnored(in: inner, from: inner.startIndex)

    while index < inner.endIndex {
        if inner[index] == "," {
            index = skipGraphQLIgnored(in: inner, from: inner.index(after: index))
            continue
        }

        guard inner[index] == "{" else {
            throw validation("attachments[\(attachments.count)] must be an object with kind, filePath, and optional altText.")
        }

        let extracted = try extractBalancedLiteral(
            from: inner,
            startingAt: index,
            opening: "{",
            closing: "}",
            context: "\(fieldName).attachments[\(attachments.count)]"
        )
        attachments.append(try parsePostAttachmentObject(extracted.literal, index: attachments.count))
        index = skipGraphQLIgnored(in: inner, from: extracted.nextIndex)

        if index < inner.endIndex,
           inner[index] != "," {
            throw validation("attachments[\(attachments.count)] must be separated by commas.")
        }
    }

    guard !attachments.isEmpty,
          attachments.count <= 4 else {
        throw validation("attachments must contain between 1 and 4 items when provided.")
    }

    return attachments
}

private func parsePostAttachmentObject(_ literal: String, index attachmentIndex: Int) throws -> PostAttachmentInput {
    let inner = String(literal.dropFirst().dropLast())
    var fields: [String: GraphQLInputValue] = [:]
    var index = skipGraphQLIgnored(in: inner, from: inner.startIndex)

    while index < inner.endIndex {
        if inner[index] == "," {
            index = skipGraphQLIgnored(in: inner, from: inner.index(after: index))
            continue
        }

        let keyStart = index
        while index < inner.endIndex,
              inner[index].isLetter || inner[index].isNumber || inner[index] == "_" {
            index = inner.index(after: index)
        }
        guard keyStart < index else {
            throw validation("attachments[\(attachmentIndex)] must be an object with kind, filePath, and optional altText.")
        }
        let key = String(inner[keyStart..<index])
        guard ["kind", "filePath", "altText"].contains(key) else {
            throw validation("attachments[\(attachmentIndex)] does not accept field '\(key)'. Supported fields: kind, filePath, altText.")
        }

        index = skipGraphQLIgnored(in: inner, from: index)
        guard index < inner.endIndex,
              inner[index] == ":" else {
            throw validation("attachments[\(attachmentIndex)].\(key) requires a value.")
        }
        index = skipGraphQLIgnored(in: inner, from: inner.index(after: index))

        let parsed = try parseGraphQLInputValue(from: inner, at: index, context: "attachments[\(attachmentIndex)].\(key)")
        fields[key] = parsed.value
        index = skipGraphQLIgnored(in: inner, from: parsed.nextIndex)

        if index < inner.endIndex,
           inner[index] != "," {
            throw validation("attachments[\(attachmentIndex)] fields must be separated by commas.")
        }
    }

    guard case .string(let kind)? = fields["kind"],
          kind == "image" else {
        throw validation("attachments[\(attachmentIndex)].kind must be 'image' in the current reviewed posting slice.")
    }

    guard case .string(let filePath)? = fields["filePath"],
          !filePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        throw validation("attachments[\(attachmentIndex)].filePath must be a non-empty string.")
    }

    let altText: String?
    switch fields["altText"] {
    case .none:
        altText = nil
    case .string(let value):
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              value.count <= 1_000 else {
            throw validation("attachments[\(attachmentIndex)].altText must be between 1 and 1000 characters when provided.")
        }
        altText = value
    case .null:
        throw validation("attachments[\(attachmentIndex)].altText must be between 1 and 1000 characters when provided.")
    }

    return PostAttachmentInput(kind: kind, filePath: filePath, altText: altText)
}

private func parseGraphQLInputValue(
    from source: String,
    at startIndex: String.Index,
    context: String
) throws -> (value: GraphQLInputValue, nextIndex: String.Index) {
    guard startIndex < source.endIndex else {
        throw validation("\(context) requires a value.")
    }
    if source[startIndex] == "\"" {
        let parsed = try parseStringLiteral(from: source, at: startIndex, context: context)
        return (.string(parsed.value), parsed.nextIndex)
    }
    if source[startIndex...].hasPrefix("null") {
        return (.null, source.index(startIndex, offsetBy: 4))
    }
    throw validation("\(context) must be a string literal.")
}

private func parseStringLiteral(
    from source: String,
    at startQuote: String.Index,
    context: String
) throws -> (value: String, nextIndex: String.Index) {
    var value = ""
    var escaping = false
    var index = source.index(after: startQuote)
    while index < source.endIndex {
        let character = source[index]
        if escaping {
            switch character {
            case "\"", "\\":
                value.append(character)
            case "n":
                value.append("\n")
            case "r":
                value.append("\r")
            case "t":
                value.append("\t")
            default:
                value.append(character)
            }
            escaping = false
        } else if character == "\\" {
            escaping = true
        } else if character == "\"" {
            return (value, source.index(after: index))
        } else {
            value.append(character)
        }
        index = source.index(after: index)
    }
    throw validation("\(context) string literal is unterminated.")
}

private func extractBalancedLiteral(
    from source: String,
    startingAt startIndex: String.Index,
    opening: Character,
    closing: Character,
    context: String
) throws -> (literal: String, nextIndex: String.Index) {
    var depth = 0
    var inString = false
    var escaping = false
    var index = startIndex

    while index < source.endIndex {
        let character = source[index]
        if inString {
            if escaping {
                escaping = false
            } else if character == "\\" {
                escaping = true
            } else if character == "\"" {
                inString = false
            }
        } else if character == "\"" {
            inString = true
        } else if let nextIndex = indexAfterGraphQLComment(in: source, from: index) {
            index = nextIndex
            continue
        } else if character == opening {
            depth += 1
        } else if character == closing {
            depth -= 1
            if depth == 0 {
                let endIndex = source.index(after: index)
                return (String(source[startIndex..<endIndex]), endIndex)
            }
        }
        index = source.index(after: index)
    }

    throw validation("\(context) literal is unterminated.")
}

private func skipWhitespace(in source: String, from startIndex: String.Index) -> String.Index {
    var index = startIndex
    while index < source.endIndex,
          isGraphQLWhitespace(source[index]) {
        index = source.index(after: index)
    }
    return index
}

private func skipGraphQLIgnored(in source: String, from startIndex: String.Index) -> String.Index {
    var index = startIndex
    while index < source.endIndex {
        let afterWhitespace = skipWhitespace(in: source, from: index)
        if let afterComment = indexAfterGraphQLComment(in: source, from: afterWhitespace) {
            index = afterComment
            continue
        }
        return afterWhitespace
    }
    return index
}

private func indexAfterGraphQLComment(in source: String, from startIndex: String.Index) -> String.Index? {
    guard startIndex < source.endIndex,
          source[startIndex] == "#" else {
        return nil
    }

    var index = source.index(after: startIndex)
    while index < source.endIndex,
          source[index] != "\n",
          source[index] != "\r" {
        index = source.index(after: index)
    }
    return index
}

private func extractOptionalIntArgument(
    _ name: String,
    from document: String,
    defaultValue: Int,
    minimum: Int,
    maximum: Int,
    fieldName: String
) throws -> Int {
    guard let nameRange = rangeOfGraphQLArgument(name, in: document) else {
        return defaultValue
    }
    var index = skipGraphQLIgnored(in: document, from: nameRange.upperBound)
    let digitStart = index
    while index < document.endIndex,
          document[index] >= "0",
          document[index] <= "9" {
        index = document.index(after: index)
    }
    let digits = document[digitStart..<index]
    guard digitStart < index,
          isGraphQLValueTerminated(in: document, at: index),
          let parsed = Int(digits),
          parsed >= minimum,
          parsed <= maximum else {
        throw validation("\(fieldName).\(name) must be an integer between \(minimum) and \(maximum).")
    }
    return parsed
}

private func extractOptionalBoolArgument(
    _ name: String,
    from document: String,
    defaultValue: Bool,
    fieldName: String
) throws -> Bool {
    guard let nameRange = rangeOfGraphQLArgument(name, in: document) else {
        return defaultValue
    }
    let index = skipGraphQLIgnored(in: document, from: nameRange.upperBound)
    guard index < document.endIndex else {
        throw validation("\(fieldName).\(name) must be a boolean literal.")
    }
    if document[index...].hasPrefix("true"),
       isGraphQLValueTerminated(in: document, at: document.index(index, offsetBy: 4)) {
        return true
    }
    if document[index...].hasPrefix("false"),
       isGraphQLValueTerminated(in: document, at: document.index(index, offsetBy: 5)) {
        return false
    }
    throw validation("\(fieldName).\(name) must be a boolean literal.")
}

private func extractOptionalStringArgument(_ name: String, from document: String, fieldName: String) throws -> String? {
    guard let nameRange = rangeOfGraphQLArgument(name, in: document) else {
        return nil
    }
    let index = skipGraphQLIgnored(in: document, from: nameRange.upperBound)
    guard index < document.endIndex,
          document[index] == "\"" else {
        throw validation("\(fieldName).\(name) must be a string literal.")
    }
    let parsed = try parseStringLiteral(from: document, at: index, context: "\(fieldName).\(name)")
    guard isGraphQLValueTerminated(in: document, at: parsed.nextIndex) else {
        throw validation("\(fieldName).\(name) must be a string literal.")
    }
    return nonBlank(parsed.value)
}

private func extractStringArgument(_ name: String, from document: String, fieldName: String) throws -> String {
    guard let nameRange = rangeOfGraphQLArgument(name, in: document) else {
        throw validation("\(fieldName) requires \(name).")
    }
    let startQuote = skipGraphQLIgnored(in: document, from: nameRange.upperBound)
    guard startQuote < document.endIndex,
          document[startQuote] == "\"" else {
        throw validation("\(fieldName).\(name) must be a string literal.")
    }

    var value = ""
    var escaping = false
    var index = document.index(after: startQuote)
    while index < document.endIndex {
        let character = document[index]
        if escaping {
            switch character {
            case "\"", "\\":
                value.append(character)
            case "n":
                value.append("\n")
            case "r":
                value.append("\r")
            case "t":
                value.append("\t")
            default:
                value.append(character)
            }
            escaping = false
        } else if character == "\\" {
            escaping = true
        } else if character == "\"" {
            if value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw validation("\(fieldName).\(name) must not be empty.")
            }
            guard isGraphQLValueTerminated(in: document, at: document.index(after: index)) else {
                throw validation("\(fieldName).\(name) must be a string literal.")
            }
            return value
        } else {
            value.append(character)
        }
        index = document.index(after: index)
    }

    throw validation("\(fieldName).\(name) string literal is unterminated.")
}

private func isGraphQLValueTerminated(in source: String, at index: String.Index) -> Bool {
    let next = skipGraphQLIgnored(in: source, from: index)
    guard next < source.endIndex else {
        return true
    }
    return source[next] == "," || source[next] == ")" || source[next] == "]" || source[next] == "}"
}

private func validateReplyLookupPostId(_ value: String) throws -> String {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
        throw validation("postId must not be empty.")
    }
    if trimmed.contains(where: { $0.isWhitespace }) {
        throw validation("postId must be a single token without whitespace.")
    }
    let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_:-")
    for scalar in trimmed.unicodeScalars where !allowed.contains(scalar) {
        throw validation("postId contains unsupported characters for reply lookup search.")
    }
    return trimmed
}

private func urlPathEscape(_ value: String) -> String {
    return value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? value
}

private let tweetLookupQuery = timelineQueryItems([:])

private func queryItems(_ items: [String: String]) -> String {
    return items
        .sorted { $0.key < $1.key }
        .map { key, value in
            "\(urlQueryEscape(key))=\(urlQueryEscape(value))"
        }
        .joined(separator: "&")
}

private func timelineQueryItems(
    _ additionalItems: [String: String],
    includeTweetFields: Bool = true,
    includeOwnerMetrics: Bool = true
) -> String {
    var items = additionalItems
    if includeTweetFields {
        var tweetFields = "attachments,author_id,conversation_id,created_at,in_reply_to_user_id,public_metrics,referenced_tweets"
        if includeOwnerMetrics {
            tweetFields += ",organic_metrics,promoted_metrics"
        }
        items["tweet.fields"] = tweetFields
        items["expansions"] = "author_id,attachments.media_keys,referenced_tweets.id"
        items["media.fields"] = "alt_text,duration_ms,height,media_key,preview_image_url,type,url,width"
    }
    items["user.fields"] = "id,name,username"
    return queryItems(items)
}

private func urlQueryEscape(_ value: String) -> String {
    var allowed = CharacterSet.urlQueryAllowed
    allowed.remove(charactersIn: ":#[]@!$&'()*+,;=")
    return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
}

private func formURLEncodedData(_ items: [(String, String)]) -> Data {
    let encoded = items
        .map { key, value in
            "\(urlQueryEscape(key))=\(urlQueryEscape(value))"
        }
        .joined(separator: "&")
    return Data(encoded.utf8)
}

private func multipartData(parts: [MultipartPart], boundary: String) -> Data {
    var data = Data()
    for part in parts {
        appendUTF8("--\(boundary)\r\n", to: &data)
        switch part {
        case .field(let name, let value):
            appendUTF8("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n", to: &data)
            appendUTF8("\(value)\r\n", to: &data)
        case .file(let name, let filename, let mimeType, let body):
            appendUTF8("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n", to: &data)
            appendUTF8("Content-Type: \(mimeType)\r\n\r\n", to: &data)
            data.append(body)
            appendUTF8("\r\n", to: &data)
        }
    }
    appendUTF8("--\(boundary)--\r\n", to: &data)
    return data
}

private func appendUTF8(_ string: String, to data: inout Data) {
    data.append(Data(string.utf8))
}

private func extractUserIds(_ payload: Any) -> [String] {
    guard let root = payload as? [String: Any],
          let data = root["data"] as? [[String: Any]] else {
        return []
    }
    return data.compactMap { $0["id"] as? String }
}

private func mergeIncludes(_ includes: [[String: Any]]) -> [String: Any] {
    var usersById: [String: [String: Any]] = [:]
    var mediaByKey: [String: [String: Any]] = [:]
    var tweetsById: [String: [String: Any]] = [:]

    for include in includes {
        for user in (include["users"] as? [[String: Any]]) ?? [] {
            if let id = user["id"] as? String {
                usersById[id] = user
            }
        }
        for media in (include["media"] as? [[String: Any]]) ?? [] {
            if let key = media["media_key"] as? String {
                mediaByKey[key] = media
            }
        }
        for tweet in (include["tweets"] as? [[String: Any]]) ?? [] {
            if let id = tweet["id"] as? String {
                tweetsById[id] = tweet
            }
        }
    }

    var merged: [String: Any] = [:]
    if !usersById.isEmpty {
        merged["users"] = Array(usersById.values)
    }
    if !mediaByKey.isEmpty {
        merged["media"] = Array(mediaByKey.values)
    }
    if !tweetsById.isEmpty {
        merged["tweets"] = Array(tweetsById.values)
    }
    return merged
}
