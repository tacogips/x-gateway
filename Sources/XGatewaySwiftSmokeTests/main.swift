import Foundation
import XGatewayCore

enum SmokeTestFailure: Error, CustomStringConvertible {
    case assertionFailed(String)

    var description: String {
        switch self {
        case .assertionFailed(let message):
            return message
        }
    }
}

func assert(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() {
        throw SmokeTestFailure.assertionFailed(message)
    }
}

struct ProcessResult {
    let exitCode: Int32
    let stderr: String
}

let environmentExecutable = "/usr/bin/env"
let formulaSmokeVersion = "0.1.4"

func runProcess(
    executable: String,
    arguments: [String],
    environment extraEnvironment: [String: String] = [:]
) throws -> ProcessResult {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    var environment = ProcessInfo.processInfo.environment
    for (key, value) in extraEnvironment {
        environment[key] = value
    }
    process.environment = environment

    let standardOutput = Pipe()
    let stderr = Pipe()
    process.standardOutput = standardOutput
    process.standardError = stderr

    try process.run()
    process.waitUntilExit()
    _ = standardOutput.fileHandleForReading.readDataToEndOfFile()

    return ProcessResult(
        exitCode: process.terminationStatus,
        stderr: String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    )
}

func runSmokeTests() throws {
    try runCryptoAndSurfaceSmokeTests()
    try runSchemaAndFormulaSmokeTests()
    try runRepliesAndMetadataSmokeTests()
    try runMCPParitySmokeTests()
    try runOAuth2SmokeTests()
    try runReadAuthSmokeTests()
    try runStreamCommandSmokeTests()
    try runGraphQLSelectionParsingSmokeTests()
    try runGraphQLArgumentSyntaxSmokeTests()
    try runMutationValidationSmokeTests()
    try runProjectionSmokeTests()
}

func runCryptoAndSurfaceSmokeTests() throws {
    let hmac = XGatewayOAuth1Signer.hmacSHA1Base64(
        message: "The quick brown fox jumps over the lazy dog",
        key: "key"
    )
    try assert(hmac == "3nybhbi3iqa8ino29wqQcBydtNk=", "HMAC-SHA1 fixture should match RFC-compatible output")

    let oauthCredentials = XGatewayOAuth1SigningCredentials(
        consumerKey: "dpf43f3p2l4k3l03",
        consumerSecret: "kd94hf93k423kf44",
        accessToken: "nnch734d00sl2jdk",
        accessTokenSecret: "pfkkdhi9sl3r4s00"
    )
    let oauthURL = URL(string: "http://photos.example.net/photos?file=vacation.jpg&size=original")!
    let oauthSignature = XGatewayOAuth1Signer.signature(
        method: "GET",
        url: oauthURL,
        credentials: oauthCredentials,
        nonce: "kllo9940pd9333jh",
        timestamp: "1191242096"
    )
    try assert(oauthSignature == "tR3+Ty81lMeYAr/Fid0kMTYa/WM=", "OAuth1 RFC signature fixture should match")
    let oauthHeader = XGatewayOAuth1Signer.authorizationHeader(
        method: "GET",
        url: oauthURL,
        credentials: oauthCredentials,
        nonce: "kllo9940pd9333jh",
        timestamp: "1191242096"
    )
    try assert(oauthHeader.contains("oauth_signature=\"tR3%2BTy81lMeYAr%2FFid0kMTYa%2FWM%3D\""), "OAuth1 header should contain percent-encoded signature")

    let anonymousQuery = try XGatewayCLI.classifyGraphQLOperation("{ accountMe { id } }")
    try assert(anonymousQuery == .query, "anonymous selection should classify as query")

    let mutation = try XGatewayCLI.classifyGraphQLOperation("mutation { createPost(text: \"hi\") { id } }")
    try assert(mutation == .mutation, "mutation document should classify as mutation")

    var invalidOperationKeywordRejected = false
    do {
        _ = try XGatewayCLI.classifyGraphQLOperation("queryName { accountMe { id } }")
    } catch {
        invalidOperationKeywordRejected = true
    }
    try assert(invalidOperationKeywordRejected, "operation classifier should require exact query/mutation keywords")

    let readCli = XGatewayCLI(commandName: "x-gateway-reader", surface: .read)
    let readReject = readCli.run(
        arguments: ["graphql", "query", "mutation { createPost(text: \"hi\") { id } }", "--json"],
        environment: [:]
    )
    try assert(readReject.exitCode == 10, "read command should reject mutations")
    try assert(readReject.stderr.contains("\"ok\""), "read rejection should use JSON envelope")
    try assert(readReject.stderr.contains("read-only"), "read rejection should explain read-only surface")

    let writeCli = XGatewayCLI(commandName: "x-gateway-writer", surface: .write)
    let writeReject = writeCli.run(
        arguments: ["graphql", "query", "{ accountMe { id } }", "--json"],
        environment: [:]
    )
    try assert(writeReject.exitCode == 10, "write command should reject queries")
    try assert(writeReject.stderr.contains("\"ok\""), "write rejection should use JSON envelope")
    try assert(writeReject.stderr.contains("write commands only"), "write rejection should explain write-only surface")

    let invalidTimeout = readCli.run(
        arguments: ["graphql", "query", "{ accountMe { id } }", "--timeout-ms", "invalid", "--json"],
        environment: [:]
    )
    try assert(invalidTimeout.exitCode == 2, "invalid timeout flag should fail validation")
    try assert(invalidTimeout.stderr.contains("VALIDATION_ERROR"), "invalid timeout should use validation envelope")
    try assert(invalidTimeout.stderr.contains("\"ok\""), "--json should format early validation errors as JSON")

    let invalidBackoff = readCli.run(
        arguments: ["graphql", "query", "{ accountMe { id } }", "--retry-backoff", "random", "--json"],
        environment: [:]
    )
    try assert(invalidBackoff.exitCode == 2, "invalid retry backoff should fail validation")
    try assert(invalidBackoff.stderr.contains("retry-backoff"), "invalid retry backoff should name the flag")

    let invalidEnvTimeout = readCli.run(
        arguments: ["graphql", "query", "{ accountMe { id } }"],
        environment: ["X_GW_TIMEOUT_MS": "invalid", "X_GW_OUTPUT": "json"]
    )
    try assert(invalidEnvTimeout.exitCode == 2, "invalid timeout env var should fail validation")
    try assert(invalidEnvTimeout.stderr.contains("X_GW_TIMEOUT_MS"), "invalid timeout env var should be named")
    try assert(invalidEnvTimeout.stderr.contains("\"ok\""), "X_GW_OUTPUT=json should format early validation errors as JSON")

    let invalidEnvBackoff = readCli.run(
        arguments: ["graphql", "query", "{ accountMe { id } }"],
        environment: ["X_GW_RETRY_BACKOFF": "random", "X_GW_OUTPUT": "json"]
    )
    try assert(invalidEnvBackoff.exitCode == 2, "invalid retry backoff env var should fail validation")
    try assert(invalidEnvBackoff.stderr.contains("X_GW_RETRY_BACKOFF"), "invalid retry backoff env var should be named")
}

func runSchemaAndFormulaSmokeTests() throws {
    let readCli = XGatewayCLI(commandName: "x-gateway-reader", surface: .read)

    let schema = readCli.run(arguments: ["graphql", "schema"], environment: [:])
    try assert(schema.exitCode == 0, "schema command should succeed")
    try assert(schema.stdout.contains("type Query"), "schema should include Query type")
    try assert(schema.stdout.contains("type Mutation"), "schema should include Mutation type")
    try assert(schema.stdout.contains("apiUsage(days: Int): ApiUsage!"), "schema should expose apiUsage days argument")
    try assert(schema.stdout.contains("input PostAttachmentInput"), "schema should include attachment input")
    try assert(schema.stdout.contains("createPost(text: String!, attachments:"), "schema should expose createPost attachments")
    try assert(schema.stdout.contains("includePromoted: Boolean"), "schema should expose includePromoted arguments")
    try assert(schema.stdout.contains("mediaRootDir: String"), "schema should expose mediaRootDir arguments")
    try assert(schema.stdout.contains("downloadMedia: Boolean"), "schema should expose downloadMedia arguments")
    try assert(schema.stdout.contains("forceDownload: Boolean"), "schema should expose forceDownload arguments")
    try assert(schema.stdout.contains("replies(maxResults: Int"), "schema should expose nested Post.replies")
    try assert(schema.stdout.components(separatedBy: "deleted: Boolean!").count == 3, "schema should expose delete result booleans")

    let unsafeFormulaURL = try runProcess(
        executable: environmentExecutable,
        arguments: ["bash", "scripts/render-homebrew-formula.sh", formulaSmokeVersion, "reader"],
        environment: ["RELEASE_BASE_URL": "https://example.com/releases/\"#{Kernel.exit}"]
    )
    try assert(unsafeFormulaURL.exitCode != 0, "formula renderer should reject unsafe release URL before rendering")
    try assert(unsafeFormulaURL.stderr.contains("unsafe release base URL"), "unsafe release URL rejection should be explicit")

    let unsafeFormulaVersion = try runProcess(
        executable: environmentExecutable,
        arguments: ["bash", "scripts/render-homebrew-formula.sh", "../\(formulaSmokeVersion)", "reader"]
    )
    try assert(unsafeFormulaVersion.exitCode != 0, "formula renderer should reject unsafe versions before rendering")
    try assert(unsafeFormulaVersion.stderr.contains("unsafe release version"), "unsafe version rejection should be explicit")

    let temporaryReleaseDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("x-gateway-smoke-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: temporaryReleaseDirectory, withIntermediateDirectories: true)
    defer {
        try? FileManager.default.removeItem(at: temporaryReleaseDirectory)
    }
    let validSha = String(repeating: "a", count: 64)
    try "not-a-sha\n".write(
        to: temporaryReleaseDirectory.appendingPathComponent("x-gateway-\(formulaSmokeVersion)-darwin-arm64.tar.gz.sha256"),
        atomically: true,
        encoding: .utf8
    )
    try "\(validSha)\n".write(
        to: temporaryReleaseDirectory.appendingPathComponent("x-gateway-\(formulaSmokeVersion)-darwin-x64.tar.gz.sha256"),
        atomically: true,
        encoding: .utf8
    )
    let invalidFormulaSha = try runProcess(
        executable: environmentExecutable,
        arguments: ["bash", "scripts/render-homebrew-formula.sh", formulaSmokeVersion, "reader"],
        environment: [
            "RELEASE_BASE_URL": "https://example.com/releases",
            "RELEASE_DIR": temporaryReleaseDirectory.path
        ]
    )
    try assert(invalidFormulaSha.exitCode != 0, "formula renderer should reject invalid checksums")
    try assert(invalidFormulaSha.stderr.contains("invalid sha256 for darwin-arm64"), "invalid checksum rejection should name the target")
}

func runRepliesAndMetadataSmokeTests() throws {
    let readCli = XGatewayCLI(commandName: "x-gateway-reader", surface: .read)
    let writeCli = XGatewayCLI(commandName: "x-gateway-writer", surface: .write)

    let invalidRepliesArgument = readCli.run(
        arguments: [
            "graphql",
            "query",
            "query { post(id: \"post-1\") { replies(limit: 10) { pageInfo { resultCount } } } }",
            "--json"
        ],
        environment: [:]
    )
    try assert(invalidRepliesArgument.exitCode == 2, "invalid replies argument should fail validation")
    try assert(invalidRepliesArgument.stderr.contains("does not accept argument 'limit'"), "invalid replies argument should name unsupported argument")

    let nestedReferencedReplies = readCli.run(
        arguments: [
            "graphql",
            "query",
            "query { post(id: \"post-1\") { referencedPosts { replies(limit: 10) { pageInfo { resultCount } } } } }",
            "--json"
        ],
        environment: [:]
    )
    try assert(
        nestedReferencedReplies.exitCode == 3,
        "replies outside the requested post selection path should not drive root reply expansion validation"
    )
    try assert(
        nestedReferencedReplies.stderr.contains("post requires X_GW_TOKEN"),
        "non-target nested replies should keep post auth validation"
    )

    let nestedRepliesMaxResultsIsScoped = readCli.run(
        arguments: [
            "graphql",
            "query",
            "query { homeTimeline { posts { replies(maxResults: 3) { pageInfo { resultCount } } } } }",
            "--json"
        ],
        environment: [:]
    )
    try assert(nestedRepliesMaxResultsIsScoped.exitCode == 2, "nested replies maxResults should be validated as a nested argument")
    try assert(nestedRepliesMaxResultsIsScoped.stderr.contains("homeTimeline.posts.replies.maxResults"), "nested maxResults should not be treated as top-level homeTimeline.maxResults")

    let oauthFlagAuth = readCli.run(
        arguments: [
            "auth",
            "verify",
            "--consumer-key", "ck",
            "--consumer-secret", "cs",
            "--access-token", "at",
            "--access-token-secret", "ats",
            "--json"
        ],
        environment: [:]
    )
    try assert(oauthFlagAuth.exitCode == 0, "auth verify should accept explicit OAuth1 flags")
    try assert(oauthFlagAuth.stdout.contains("\"oauth1\""), "auth verify should report OAuth1 from flags")

    let oauthScopeNotes = readCli.run(
        arguments: [
            "auth",
            "scopes",
            "--consumer-key", "ck",
            "--consumer-secret", "cs",
            "--access-token", "at",
            "--access-token-secret", "ats",
            "--json"
        ],
        environment: [:]
    )
    try assert(oauthScopeNotes.exitCode == 0, "auth scopes should accept explicit OAuth1 flags")
    try assert(oauthScopeNotes.stdout.contains("bookmark operations remain bearer-only"), "auth scopes should document bearer-only usage")

    let createCapability = writeCli.run(
        arguments: ["capabilities", "get", "--id", "post.create", "--json"],
        environment: [:]
    )
    try assert(createCapability.exitCode == 0, "capability metadata should expose post.create")
    try assert(createCapability.stdout.contains("swift-oauth1-preferred-bearer-fallback"), "post.create should advertise OAuth1-preferred routing")

    let repliesCapability = readCli.run(
        arguments: ["capabilities", "get", "--id", "post.replies", "--json"],
        environment: [:]
    )
    try assert(repliesCapability.exitCode == 0, "capability metadata should expose post.replies")
    try assert(repliesCapability.stdout.contains("Post.replies"), "post.replies should name the nested replies operation")
}

func runReadAuthSmokeTests() throws {
    let readCli = XGatewayCLI(commandName: "x-gateway-reader", surface: .read)

    let accountMeMissingAuth = readCli.run(
        arguments: ["graphql", "query", "{ accountMe { id username name } }", "--json"],
        environment: [:]
    )
    try assert(accountMeMissingAuth.exitCode == 3, "supported read operation should reach auth validation")
    try assert(accountMeMissingAuth.stderr.contains("AUTH_MISSING"), "supported read operation should report missing auth")

    let usageMissingAuth = readCli.run(
        arguments: ["graphql", "query", "{ apiUsage(days: 1) { projectUsage } }", "--json"],
        environment: [:]
    )
    try assert(usageMissingAuth.exitCode == 3, "apiUsage should reach auth validation")
    try assert(usageMissingAuth.stderr.contains("apiUsage requires X_GW_TOKEN"), "apiUsage should report missing auth")

    let postMissingAuth = readCli.run(
        arguments: ["graphql", "query", "{ post(id: \"123\") { id text } }", "--json"],
        environment: [:]
    )
    try assert(postMissingAuth.exitCode == 3, "post read should reach auth validation")
    try assert(postMissingAuth.stderr.contains("post requires X_GW_TOKEN"), "post read should report missing auth")

    let searchMissingAuth = readCli.run(
        arguments: ["graphql", "query", "{ searchPosts(query: \"swift\", maxResults: 10) { posts { id } } }", "--json"],
        environment: [:]
    )
    try assert(searchMissingAuth.exitCode == 3, "searchPosts should reach auth validation")
    try assert(searchMissingAuth.stderr.contains("searchPosts requires X_GW_TOKEN"), "searchPosts should report missing auth")

    let homeMissingAuth = readCli.run(
        arguments: ["graphql", "query", "{ homeTimeline(maxResults: 10) { posts { id } } }", "--json"],
        environment: [:]
    )
    try assert(homeMissingAuth.exitCode == 3, "homeTimeline should reach auth validation")
    try assert(homeMissingAuth.stderr.contains("homeTimeline requires X_GW_TOKEN"), "homeTimeline should report missing auth")

    let followingMissingAuth = readCli.run(
        arguments: ["graphql", "query", "{ followingTimeline(maxResults: 5, maxUsers: 2, maxResultsPerUser: 5) { posts { id } } }", "--json"],
        environment: [:]
    )
    try assert(followingMissingAuth.exitCode == 3, "followingTimeline should reach auth validation")
    try assert(followingMissingAuth.stderr.contains("followingTimeline requires X_GW_TOKEN"), "followingTimeline should report missing auth")

    let timelineMissingAuth = readCli.run(
        arguments: ["graphql", "query", "{ userTimeline(userId: \"42\", maxResults: 10) { posts { id } } }", "--json"],
        environment: [:]
    )
    try assert(timelineMissingAuth.exitCode == 3, "userTimeline should reach auth validation")
    try assert(timelineMissingAuth.stderr.contains("userTimeline requires X_GW_TOKEN"), "userTimeline should report missing auth")

    let mentionsMissingAuth = readCli.run(
        arguments: ["graphql", "query", "{ mentionsTimeline(userId: \"42\", maxResults: 10) { posts { id } } }", "--json"],
        environment: [:]
    )
    try assert(mentionsMissingAuth.exitCode == 3, "mentionsTimeline should reach auth validation")
    try assert(mentionsMissingAuth.stderr.contains("mentionsTimeline requires X_GW_TOKEN"), "mentionsTimeline should report missing auth")
}

func runGraphQLSelectionParsingSmokeTests() throws {
    let readCli = XGatewayCLI(commandName: "x-gateway-reader", surface: .read)
    let writeCli = XGatewayCLI(commandName: "x-gateway-writer", surface: .write)

    let createPostMissingAuth = writeCli.run(
        arguments: ["graphql", "query", "mutation { createPost(text: \"hi\") { id } }", "--json"],
        environment: [:]
    )
    try assert(createPostMissingAuth.exitCode == 3, "supported write operation should reach auth validation")
    try assert(createPostMissingAuth.stderr.contains("AUTH_MISSING"), "supported write operation should report missing auth")

    let createPostTextMentioningAttachments = writeCli.run(
        arguments: ["graphql", "query", "mutation { createPost(text: \"literal attachments: text\") { id } }", "--json"],
        environment: [:]
    )
    try assert(createPostTextMentioningAttachments.exitCode == 3, "attachments literal inside text should not be parsed as an argument")
    try assert(createPostTextMentioningAttachments.stderr.contains("AUTH_MISSING"), "text-only post should keep normal auth validation")

    let quoteTextMentioningQuotedPostId = writeCli.run(
        arguments: ["graphql", "query", "mutation { quotePost(text: \"literal quotedPostId: text\", quotedPostId: \"123\") { id } }", "--json"],
        environment: [:]
    )
    try assert(quoteTextMentioningQuotedPostId.exitCode == 3, "argument names inside strings should not override real string arguments")
    try assert(quoteTextMentioningQuotedPostId.stderr.contains("AUTH_MISSING"), "quotePost should keep normal auth validation")

    let searchQueryMentioningMaxResults = readCli.run(
        arguments: ["graphql", "query", "query { searchPosts(query: \"literal maxResults: text\", maxResults: 10) { posts { id } } }", "--json"],
        environment: [:]
    )
    try assert(searchQueryMentioningMaxResults.exitCode == 3, "argument names inside strings should not override real integer arguments")
    try assert(searchQueryMentioningMaxResults.stderr.contains("AUTH_MISSING"), "searchPosts should keep normal auth validation")

    let searchQueryMentioningAccountMe = readCli.run(
        arguments: ["graphql", "query", "query { searchPosts(query : \"literal accountMe text\", maxResults : 10) { posts { id } } }", "--json"],
        environment: [:]
    )
    try assert(searchQueryMentioningAccountMe.exitCode == 3, "field names inside strings should not select a different operation")
    try assert(searchQueryMentioningAccountMe.stderr.contains("searchPosts requires X_GW_TOKEN"), "searchPosts with spaced arguments should keep search auth validation")

    let variableDefaultMentionsAccountMe = readCli.run(
        arguments: ["graphql", "query", "query Search($input: Input = { accountMe: \"literal\" }) { searchPosts(query: \"swift\", maxResults: 10) { posts { id } } }", "--json"],
        environment: [:]
    )
    try assert(variableDefaultMentionsAccountMe.exitCode == 3, "field names inside variable defaults should not replace the root operation")
    try assert(variableDefaultMentionsAccountMe.stderr.contains("searchPosts requires X_GW_TOKEN"), "searchPosts after variable definitions should keep search auth validation")

    let searchQueryMentioningFragmentInString = readCli.run(
        arguments: ["graphql", "query", "query { searchPosts(query: \"literal fragment text\", maxResults: 10) { posts { id } } }", "--json"],
        environment: [:]
    )
    try assert(searchQueryMentioningFragmentInString.exitCode == 3, "fragment keyword inside string literals should not fail validation")
    try assert(searchQueryMentioningFragmentInString.stderr.contains("searchPosts requires X_GW_TOKEN"), "fragment keyword inside search text should keep search auth validation")

    let searchQuerySelectingFragmentFieldName = readCli.run(
        arguments: ["graphql", "query", "query { searchPosts(query: \"swift\", maxResults: 10) { posts { fragment } } }", "--json"],
        environment: [:]
    )
    try assert(searchQuerySelectingFragmentFieldName.exitCode == 3, "nested fields named fragment should not be rejected as fragment definitions")
    try assert(searchQuerySelectingFragmentFieldName.stderr.contains("searchPosts requires X_GW_TOKEN"), "fragment-like nested fields should keep search auth validation")

    let searchQuerySelectingAccountMeProjection = readCli.run(
        arguments: ["graphql", "query", "query { searchPosts(query: \"swift\", maxResults: 10) { posts { accountMe } } }", "--json"],
        environment: [:]
    )
    try assert(searchQuerySelectingAccountMeProjection.exitCode == 3, "nested projection field names should not replace the root operation")
    try assert(searchQuerySelectingAccountMeProjection.stderr.contains("searchPosts requires X_GW_TOKEN"), "nested accountMe projection should keep search auth validation")

    let multiFieldQuery = readCli.run(
        arguments: ["graphql", "query", "query { accountMe { id } searchPosts(query: \"swift\", maxResults: 10) { posts { id } } }", "--json"],
        environment: [:]
    )
    try assert(multiFieldQuery.exitCode == 2, "multiple top-level query fields should fail validation")
    try assert(multiFieldQuery.stderr.contains("exactly one top-level field"), "multiple top-level query fields should explain the public contract limit")

    let emptyRootQuery = readCli.run(
        arguments: ["graphql", "query", "query { }", "--json"],
        environment: [:]
    )
    try assert(emptyRootQuery.exitCode == 2, "empty top-level query selection should fail validation")
    try assert(emptyRootQuery.stderr.contains("found none"), "empty query selection should explain that one top-level field is required")

    let multiOperationQuery = readCli.run(
        arguments: ["graphql", "query", "query First { searchPosts(query: \"swift\", maxResults: 10) { posts { id } } } query Second { accountMe { id } }", "--json"],
        environment: [:]
    )
    try assert(multiOperationQuery.exitCode == 2, "multiple query operation definitions should fail validation")
    try assert(multiOperationQuery.stderr.contains("exactly one operation definition"), "multiple operation definitions should explain the public contract limit")

    let anonymousQueryWithTrailingOperation = readCli.run(
        arguments: ["graphql", "query", "{ accountMe { id } } query Extra { accountMe { id } }", "--json"],
        environment: [:]
    )
    try assert(anonymousQueryWithTrailingOperation.exitCode == 2, "anonymous query plus named operation should fail validation")
    try assert(anonymousQueryWithTrailingOperation.stderr.contains("exactly one operation definition"), "mixed anonymous and named operations should explain the public contract limit")

    let queryWithTrailingToken = readCli.run(
        arguments: ["graphql", "query", "query { accountMe { id } } trailing", "--json"],
        environment: [:]
    )
    try assert(queryWithTrailingToken.exitCode == 2, "trailing query tokens should fail validation before auth or execution")
    try assert(queryWithTrailingToken.stderr.contains("Unexpected GraphQL token 'trailing'"), "trailing query token diagnostic should name the unexpected token")

    let supportedNameAsUnsupportedArgument = readCli.run(
        arguments: ["graphql", "query", "query { unsupported(post: \"123\") { id } }", "--json"],
        environment: [:]
    )
    try assert(supportedNameAsUnsupportedArgument.exitCode == 10, "supported field names inside unsupported root arguments should not select an operation")
    try assert(supportedNameAsUnsupportedArgument.stderr.contains("UNSUPPORTED"), "unsupported root field should keep the unsupported-field diagnostic")

    let searchQueryWithUnexpectedRootArgument = readCli.run(
        arguments: ["graphql", "query", "query { searchPosts(query: \"swift\", maxResults: 10, sinceId: \"1\") { posts { id } } }", "--json"],
        environment: [:]
    )
    try assert(searchQueryWithUnexpectedRootArgument.exitCode == 2, "unexpected root query arguments should fail validation")
    try assert(searchQueryWithUnexpectedRootArgument.stderr.contains("searchPosts"), "unexpected root query argument should name the public field")
    try assert(searchQueryWithUnexpectedRootArgument.stderr.contains("sinceId"), "unexpected root query argument should name the unsupported argument")
}

func runGraphQLArgumentSyntaxSmokeTests() throws {
    let readCli = XGatewayCLI(commandName: "x-gateway-reader", surface: .read)

    let searchQueryWithMalformedIntegerArgument = readCli.run(
        arguments: ["graphql", "query", "query { searchPosts(query: \"swift\", maxResults: 10foo) { posts { id } } }", "--json"],
        environment: [:]
    )
    try assert(searchQueryWithMalformedIntegerArgument.exitCode == 2, "integer arguments should reject trailing identifier characters")
    try assert(searchQueryWithMalformedIntegerArgument.stderr.contains("searchPosts.maxResults"), "malformed integer diagnostic should name the argument")

    let searchQueryWithMalformedBooleanArgument = readCli.run(
        arguments: ["graphql", "query", "query { searchPosts(query: \"swift\", maxResults: 10, includePromoted: trueish) { posts { id } } }", "--json"],
        environment: [:]
    )
    try assert(searchQueryWithMalformedBooleanArgument.exitCode == 2, "boolean arguments should reject trailing identifier characters")
    try assert(searchQueryWithMalformedBooleanArgument.stderr.contains("searchPosts.includePromoted"), "malformed boolean diagnostic should name the argument")

    let searchQueryWithMalformedStringArgument = readCli.run(
        arguments: ["graphql", "query", "query { searchPosts(query: \"swift\"suffix, maxResults: 10) { posts { id } } }", "--json"],
        environment: [:]
    )
    try assert(searchQueryWithMalformedStringArgument.exitCode == 2, "string arguments should reject trailing identifier characters")
    try assert(searchQueryWithMalformedStringArgument.stderr.contains("searchPosts.query"), "malformed string diagnostic should name the argument")

    let searchQueryWithCommentedArgumentValues = readCli.run(
        arguments: ["graphql", "query", "query { searchPosts(query: # query value\n \"swift\", maxResults: # result count\n 10, downloadMedia: # boolean value\n false) { posts { id } } }", "--json"],
        environment: [:]
    )
    try assert(searchQueryWithCommentedArgumentValues.exitCode == 3, "comments after argument colons should not fail argument parsing")
    try assert(searchQueryWithCommentedArgumentValues.stderr.contains("searchPosts requires X_GW_TOKEN"), "commented argument values should keep search auth validation")

    let searchQueryCommentMentioningAccountMe = readCli.run(
        arguments: ["graphql", "query", "query { # accountMe\n searchPosts(query: \"swift\", maxResults: 10) { posts { id } } }", "--json"],
        environment: [:]
    )
    try assert(searchQueryCommentMentioningAccountMe.exitCode == 3, "field names inside comments should not select a different operation")
    try assert(searchQueryCommentMentioningAccountMe.stderr.contains("searchPosts requires X_GW_TOKEN"), "searchPosts after a comment should keep search auth validation")

    let searchQueryAliasedAsAccountMe = readCli.run(
        arguments: ["graphql", "query", "query { accountMe: searchPosts(query: \"swift\", maxResults: 10) { posts { id } } }", "--json"],
        environment: [:]
    )
    try assert(searchQueryAliasedAsAccountMe.exitCode == 2, "field aliases should fail validation before auth")
    try assert(searchQueryAliasedAsAccountMe.stderr.contains("aliases are not supported"), "aliased searchPosts should explain unsupported alias syntax")

    let searchQueryWithAccountMeOperationName = readCli.run(
        arguments: ["graphql", "query", "query accountMe { searchPosts(query: \"swift\", maxResults: 10) { posts { id } } }", "--json"],
        environment: [:]
    )
    try assert(searchQueryWithAccountMeOperationName.exitCode == 3, "operation names should not select a different field")
    try assert(searchQueryWithAccountMeOperationName.stderr.contains("searchPosts requires X_GW_TOKEN"), "named searchPosts query should keep search auth validation")

    let searchQueryAliasWithCommentedColon = readCli.run(
        arguments: ["graphql", "query", "query { accountMe # alias comment\n : searchPosts(query: \"swift\", maxResults: 10) { posts { id } } }", "--json"],
        environment: [:]
    )
    try assert(searchQueryAliasWithCommentedColon.exitCode == 2, "comments between alias names and colons should still fail as aliases")
    try assert(searchQueryAliasWithCommentedColon.stderr.contains("aliases are not supported"), "commented aliases should explain unsupported alias syntax")

    let searchQueryWithAccountMeFragmentName = readCli.run(
        arguments: ["graphql", "query", "query { ...accountMe } fragment accountMe on Query { searchPosts(query: \"swift\", maxResults: 10) { posts { id } } }", "--json"],
        environment: [:]
    )
    try assert(searchQueryWithAccountMeFragmentName.exitCode == 2, "fragment names should fail validation before auth")
    try assert(searchQueryWithAccountMeFragmentName.stderr.contains("fragments are not supported"), "fragment syntax should explain unsupported fragments")

    let spacedAccountMeFragmentSpread = readCli.run(
        arguments: ["graphql", "query", "query { ... accountMe } fragment accountMe on Query { searchPosts(query: \"swift\", maxResults: 10) { posts { id } } }", "--json"],
        environment: [:]
    )
    try assert(spacedAccountMeFragmentSpread.exitCode == 2, "fragment spreads with whitespace should fail validation before auth")
    try assert(spacedAccountMeFragmentSpread.stderr.contains("fragments are not supported"), "spaced fragment spread should explain unsupported fragments")

    let searchQueryWithUnusedFragmentDefinition = readCli.run(
        arguments: ["graphql", "query", "query { searchPosts(query: \"swift\", maxResults: 10) { posts { id } } } fragment F on Query { searchPosts(query: \"bad\", maxResults: 5) { posts { id } } }", "--json"],
        environment: [:]
    )
    try assert(searchQueryWithUnusedFragmentDefinition.exitCode == 2, "unused fragment definitions should fail validation before auth")
    try assert(searchQueryWithUnusedFragmentDefinition.stderr.contains("fragments are not supported"), "unused fragment definitions should explain unsupported fragments")

    let searchQueryWithAccountMeDirectiveName = readCli.run(
        arguments: ["graphql", "query", "query { searchPosts(query: \"swift\", maxResults: 10) @accountMe { posts { id } } }", "--json"],
        environment: [:]
    )
    try assert(searchQueryWithAccountMeDirectiveName.exitCode == 2, "directive names should fail validation before auth")
    try assert(searchQueryWithAccountMeDirectiveName.stderr.contains("directives are not supported"), "directive syntax should explain unsupported directives")

    let repliesCommentMentioningInvalidArgument = readCli.run(
        arguments: [
            "graphql",
            "query",
            "query { post(id: \"post-1\") { replies(# limit: 10\n maxResults: 10) { pageInfo { resultCount } } } }",
            "--json"
        ],
        environment: [:]
    )
    try assert(repliesCommentMentioningInvalidArgument.exitCode == 3, "argument names inside comments should not fail nested replies validation")
    try assert(repliesCommentMentioningInvalidArgument.stderr.contains("post requires X_GW_TOKEN"), "replies arguments after a comment should keep post auth validation")

    let repliesWithIgnoredTokensAroundSyntax = readCli.run(
        arguments: [
            "graphql",
            "query",
            "query { post(id: # post id\n \"post-1\") { replies # replies args\n (maxResults: # result count\n 10) # replies selection\n { pageInfo { resultCount } } } }",
            "--json"
        ],
        environment: [:]
    )
    try assert(repliesWithIgnoredTokensAroundSyntax.exitCode == 3, "comments around replies syntax should not fail nested replies parsing")
    try assert(repliesWithIgnoredTokensAroundSyntax.stderr.contains("post requires X_GW_TOKEN"), "commented replies syntax should keep post auth validation")
}

func runMutationValidationSmokeTests() throws {
    let writeCli = XGatewayCLI(commandName: "x-gateway-writer", surface: .write)

    let createAttachmentMissingAuth = writeCli.run(
        arguments: [
            "graphql",
            "query",
            "mutation { createPost(text: \"hi\", attachments: [{ kind: \"image\", filePath: \"/tmp/x-gateway-missing-swift-upload-fixture-a.png\", altText: \"example\" }]) { id } }",
            "--json"
        ],
        environment: [:]
    )
    try assert(createAttachmentMissingAuth.exitCode == 3, "createPost attachments without credentials should fail auth before live posting")
    try assert(createAttachmentMissingAuth.stderr.contains("AUTH_MISSING"), "createPost attachments should report missing auth")
    try assert(createAttachmentMissingAuth.stderr.contains("createPost requires X_GW_TOKEN"), "createPost attachment auth rejection should name bearer auth")

    let createVideoAttachmentMissingAuth = writeCli.run(
        arguments: [
            "graphql",
            "query",
            "mutation { createPost(text: \"hi\", attachments: [{ kind: \"video\", filePath: \"/tmp/x-gateway-missing-swift-upload-fixture-video.mp4\" }]) { id } }",
            "--json"
        ],
        environment: [:]
    )
    try assert(createVideoAttachmentMissingAuth.exitCode == 3, "createPost video attachments should parse and reach auth validation")
    try assert(createVideoAttachmentMissingAuth.stderr.contains("createPost requires X_GW_TOKEN"), "video attachment auth rejection should name bearer auth")

    let createVideoAttachmentWithAltText = writeCli.run(
        arguments: [
            "graphql",
            "query",
            "mutation { createPost(text: \"hi\", attachments: [{ kind: \"video\", filePath: \"/tmp/x-gateway-video.mp4\", altText: \"not supported\" }]) { id } }",
            "--json"
        ],
        environment: [:]
    )
    try assert(createVideoAttachmentWithAltText.exitCode == 2, "video attachment alt text should fail validation")
    try assert(createVideoAttachmentWithAltText.stderr.contains("altText"), "video attachment alt text validation should name altText")

    let createAttachmentWithCommentedValues = writeCli.run(
        arguments: [
            "graphql",
            "query",
            "mutation { createPost(text: \"hi\", attachments: # attachments value\n " +
                "[{ kind: # kind value\n \"image\", filePath: # path value\n " +
                "\"/tmp/x-gateway-missing-swift-upload-fixture-commented.png\", altText: # alt value\n " +
                "\"example\" }]) { id } }",
            "--json"
        ],
        environment: [:]
    )
    try assert(createAttachmentWithCommentedValues.exitCode == 3, "comments inside attachment input should not fail attachment parsing")
    try assert(createAttachmentWithCommentedValues.stderr.contains("createPost requires X_GW_TOKEN"), "commented attachment input should still require auth before live posting")

    let createAttachmentMissingFile = writeCli.run(
        arguments: [
            "graphql", "query",
            "mutation { createPost(text: \"hi\", attachments: [{ kind: \"image\", filePath: \"/tmp/x-gateway-missing-swift-upload-fixture-a.png\", altText: \"example\" }]) { id } }",
            "--token", "bearer",
            "--json"
        ],
        environment: [:]
    )
    try assert(createAttachmentMissingFile.exitCode == 2, "createPost attachments should validate local image path before upload")
    try assert(createAttachmentMissingFile.stderr.contains("filePath"), "missing image validation should name filePath")

    let createAttachmentUnexpectedField = writeCli.run(
        arguments: ["graphql", "query", "mutation { createPost(text: \"hi\", attachments: [{ kind: \"image\", filePath: \"/tmp/a.png\", upstreamId: \"1\" }]) { id } }", "--json"],
        environment: [:]
    )
    try assert(createAttachmentUnexpectedField.exitCode == 2, "unexpected attachment fields should fail validation")
    try assert(createAttachmentUnexpectedField.stderr.contains("upstreamId"), "unexpected attachment field should be named")

    let createPostWithUnexpectedRootArgument = writeCli.run(
        arguments: ["graphql", "query", "mutation { createPost(text: \"hi\", upstream: { text: \"nested\" }) { id } }", "--json"],
        environment: [:]
    )
    try assert(createPostWithUnexpectedRootArgument.exitCode == 2, "unexpected root mutation arguments should fail validation")
    try assert(createPostWithUnexpectedRootArgument.stderr.contains("createPost"), "unexpected root mutation argument should name the public field")
    try assert(createPostWithUnexpectedRootArgument.stderr.contains("upstream"), "unexpected root mutation argument should name the unsupported argument")

    let createAttachmentEmptyList = writeCli.run(
        arguments: ["graphql", "query", "mutation { createPost(text: \"hi\", attachments: []) { id } }", "--json"],
        environment: [:]
    )
    try assert(createAttachmentEmptyList.exitCode == 2, "empty attachments should fail validation")
    try assert(createAttachmentEmptyList.stderr.contains("between 1 and 4"), "empty attachments should explain supported bounds")

    let replyMissingAuth = writeCli.run(
        arguments: ["graphql", "query", "mutation { replyToPost(text: \"hi\", replyToPostId: \"123\") { id } }", "--json"],
        environment: [:]
    )
    try assert(replyMissingAuth.exitCode == 3, "replyToPost should reach auth validation")
    try assert(replyMissingAuth.stderr.contains("replyToPost requires X_GW_TOKEN"), "replyToPost should report missing auth")

    let replyTextMentioningCreatePost = writeCli.run(
        arguments: ["graphql", "query", "mutation { replyToPost(text: \"literal createPost text\", replyToPostId : \"123\") { id } }", "--json"],
        environment: [:]
    )
    try assert(replyTextMentioningCreatePost.exitCode == 3, "operation names inside mutation strings should not select a different operation")
    try assert(replyTextMentioningCreatePost.stderr.contains("replyToPost requires X_GW_TOKEN"), "replyToPost with spaced arguments should keep reply auth validation")

    let replyAliasedAsCreatePost = writeCli.run(
        arguments: ["graphql", "query", "mutation { createPost: replyToPost(text: \"hi\", replyToPostId: \"123\") { id } }", "--json"],
        environment: [:]
    )
    try assert(replyAliasedAsCreatePost.exitCode == 2, "mutation aliases should fail validation before auth")
    try assert(replyAliasedAsCreatePost.stderr.contains("aliases are not supported"), "aliased replyToPost should explain unsupported alias syntax")

    let replyWithCreatePostOperationName = writeCli.run(
        arguments: ["graphql", "query", "mutation createPost { replyToPost(text: \"hi\", replyToPostId: \"123\") { id } }", "--json"],
        environment: [:]
    )
    try assert(replyWithCreatePostOperationName.exitCode == 3, "mutation operation names should not select a different field")
    try assert(replyWithCreatePostOperationName.stderr.contains("replyToPost requires X_GW_TOKEN"), "named replyToPost mutation should keep reply auth validation")

    let multiFieldMutation = writeCli.run(
        arguments: ["graphql", "query", "mutation { createPost(text: \"hi\") { id } deletePost(postId: \"123\") { id } }", "--json"],
        environment: [:]
    )
    try assert(multiFieldMutation.exitCode == 2, "multiple top-level mutation fields should fail validation")
    try assert(multiFieldMutation.stderr.contains("exactly one top-level field"), "multiple top-level mutation fields should explain the public contract limit")

    let emptyRootMutation = writeCli.run(
        arguments: ["graphql", "query", "mutation { }", "--json"],
        environment: [:]
    )
    try assert(emptyRootMutation.exitCode == 2, "empty top-level mutation selection should fail validation")
    try assert(emptyRootMutation.stderr.contains("found none"), "empty mutation selection should explain that one top-level field is required")

    let mutationWithTrailingToken = writeCli.run(
        arguments: ["graphql", "query", "mutation { createPost(text: \"hi\") { id } } trailing", "--json"],
        environment: [:]
    )
    try assert(mutationWithTrailingToken.exitCode == 2, "trailing mutation tokens should fail validation before auth or execution")
    try assert(mutationWithTrailingToken.stderr.contains("Unexpected GraphQL token 'trailing'"), "trailing mutation token diagnostic should name the unexpected token")

    let replyAttachmentMissingAuth = writeCli.run(
        arguments: [
            "graphql",
            "query",
            "mutation { replyToPost(text: \"hi\", replyToPostId: \"123\", attachments: [{ kind: \"image\", filePath: \"/tmp/x-gateway-missing-swift-upload-fixture-b.png\" }]) { id } }",
            "--json"
        ],
        environment: [:]
    )
    try assert(replyAttachmentMissingAuth.exitCode == 3, "replyToPost attachments without credentials should fail auth before live posting")
    try assert(replyAttachmentMissingAuth.stderr.contains("replyToPost requires X_GW_TOKEN"), "reply attachment auth rejection should name bearer auth")

    let quoteMissingAuth = writeCli.run(
        arguments: ["graphql", "query", "mutation { quotePost(text: \"hi\", quotedPostId: \"123\") { id } }", "--json"],
        environment: [:]
    )
    try assert(quoteMissingAuth.exitCode == 3, "quotePost should reach auth validation")
    try assert(quoteMissingAuth.stderr.contains("quotePost requires X_GW_TOKEN"), "quotePost should report missing auth")

    let quoteAttachmentMissingAuth = writeCli.run(
        arguments: [
            "graphql",
            "query",
            "mutation { quotePost(text: \"hi\", quotedPostId: \"123\", attachments: [{ kind: \"image\", filePath: \"/tmp/x-gateway-missing-swift-upload-fixture-c.png\" }]) { id } }",
            "--json"
        ],
        environment: [:]
    )
    try assert(quoteAttachmentMissingAuth.exitCode == 3, "quotePost attachments without credentials should fail auth before live posting")
    try assert(quoteAttachmentMissingAuth.stderr.contains("quotePost requires X_GW_TOKEN"), "quote attachment auth rejection should name bearer auth")

    let repostMissingAuth = writeCli.run(
        arguments: ["graphql", "query", "mutation { repostPost(postId: \"123\") { id } }", "--json"],
        environment: [:]
    )
    try assert(repostMissingAuth.exitCode == 3, "repostPost should reach auth validation")
    try assert(repostMissingAuth.stderr.contains("repostPost requires X_GW_TOKEN"), "repostPost should report missing auth")

    let unrepostMissingAuth = writeCli.run(
        arguments: ["graphql", "query", "mutation { unrepostPost(postId: \"123\") { id } }", "--json"],
        environment: [:]
    )
    try assert(unrepostMissingAuth.exitCode == 3, "unrepostPost should reach auth validation")
    try assert(unrepostMissingAuth.stderr.contains("unrepostPost requires X_GW_TOKEN"), "unrepostPost should report missing auth")
}

func runProjectionSmokeTests() throws {
    let account = XGatewayResponseProjector.account([
        "data": ["id": "u1", "username": "alice", "name": "Alice"]
    ])
    try assert(account["username"] as? String == "alice", "account projection should expose username")

    let usagePayload: [String: Any] = [
        "data": [
            "cap_reset_day": 15,
            "daily_client_app_usage": [
                [
                    "client_app_id": "app1",
                    "usage_result_count": 1,
                    "usage": [["date": "2026-06-19", "usage": 3] as [String: Any]]
                ] as [String: Any]
            ],
            "daily_project_usage": [
                "project_id": "project1",
                "usage": [["date": "2026-06-19", "usage": 5] as [String: Any]]
            ] as [String: Any],
            "project_cap": 100,
            "project_id": "project1",
            "project_usage": 5
        ] as [String: Any]
    ]
    let usage = XGatewayResponseProjector.apiUsage(usagePayload)
    try assert(usage["projectUsage"] as? Int == 5, "apiUsage projection should expose projectUsage")

    let postPagePayload: [String: Any] = [
        "data": [
            [
                "id": "p1",
                "text": "hello",
                "author_id": "u1",
                "created_at": "2026-06-19T00:00:00Z",
                "conversation_id": "c1",
                "attachments": ["media_keys": ["m1"]],
                "referenced_tweets": [["type": "quoted", "id": "p0"] as [String: Any]],
                "public_metrics": [
                    "like_count": 1,
                    "reply_count": 2,
                    "retweet_count": 3,
                    "quote_count": 4,
                    "bookmark_count": 5,
                    "impression_count": 6
                ] as [String: Any]
            ] as [String: Any]
        ],
        "includes": [
            "users": [
                ["id": "u1", "username": "alice", "name": "Alice"] as [String: Any],
                ["id": "u2", "username": "bob", "name": "Bob"] as [String: Any]
            ],
            "media": [
                [
                    "media_key": "m1",
                    "type": "photo",
                    "url": "https://example.com/media/photo.png",
                    "preview_image_url": "https://example.com/media/preview.jpg"
                ] as [String: Any]
            ],
            "tweets": [
                [
                    "id": "p0",
                    "text": "quoted",
                    "author_id": "u2",
                    "created_at": "2026-06-18T00:00:00Z",
                    "public_metrics": [
                        "like_count": 10,
                        "reply_count": 20,
                        "retweet_count": 30,
                        "quote_count": 40
                    ] as [String: Any]
                ] as [String: Any]
            ]
        ] as [String: Any],
        "meta": [
            "result_count": 1,
            "newest_id": "p1",
            "oldest_id": "p1"
        ] as [String: Any]
    ]
    let postPage = try XGatewayResponseProjector.postPage(postPagePayload)
    let posts = postPage["posts"] as? [[String: Any]]
    let projectedPost = posts?.first
    let projectedMetrics = projectedPost?["metrics"] as? [String: Any]
    let projectedAuthor = projectedPost?["author"] as? [String: Any]
    let projectedMedia = (projectedPost?["media"] as? [[String: Any]])?.first
    let projectedQuote = projectedPost?["quote"] as? [String: Any]
    let projectedReferences = projectedPost?["referencedPosts"] as? [[String: Any]]
    try assert(projectedPost?["id"] as? String == "p1", "postPage projection should expose post id")
    try assert(projectedPost?["conversationId"] as? String == "c1", "postPage projection should expose conversationId")
    try assert(projectedMetrics?["impressionCount"] as? Int == 6, "postPage projection should map impressionCount")
    try assert(projectedAuthor?["username"] as? String == "alice", "postPage projection should attach author")
    try assert(projectedMedia?["kind"] as? String == "photo", "postPage projection should attach media kind")
    try assert(projectedMedia?["contentType"] as? String == "image/png", "postPage projection should infer media content type")
    try assert(projectedMedia?["sourceUrl"] as? String == "https://example.com/media/photo.png", "postPage projection should attach media source URL")
    try assert(projectedQuote?["id"] as? String == "p0", "postPage projection should expose quote shortcut")
    try assert(projectedQuote?["relation"] as? String == "quoted", "postPage projection should expose reference relation")
    try assert(projectedReferences?.count == 1, "postPage projection should expose referencedPosts")

    let mediaRoot = FileManager.default.temporaryDirectory
        .appendingPathComponent("x-gateway-swift-media-\(UUID().uuidString)", isDirectory: true)
    defer {
        try? FileManager.default.removeItem(at: mediaRoot)
    }
    let existingMediaDirectory = mediaRoot.appendingPathComponent("p1", isDirectory: true)
    let existingMediaFile = existingMediaDirectory.appendingPathComponent("photo.png", isDirectory: false)
    try FileManager.default.createDirectory(at: existingMediaDirectory, withIntermediateDirectories: true)
    try Data("already downloaded".utf8).write(to: existingMediaFile)

    let materializedPage = try XGatewayResponseProjector.postPage(
        postPagePayload,
        options: XGatewayPostReadOptions(mediaRootDir: mediaRoot.path)
    )
    let materializedMedia = (((materializedPage["posts"] as? [[String: Any]])?.first)?["media"] as? [[String: Any]])?.first
    try assert(materializedMedia?["localFilePath"] as? String == existingMediaFile.path, "postPage projection should reuse existing local media")
    let existingMediaContents = try Data(contentsOf: existingMediaFile)
    try assert(existingMediaContents == Data("already downloaded".utf8), "existing local media should not be overwritten by default")

    let sourceOnlyPage = try XGatewayResponseProjector.postPage(
        postPagePayload,
        options: XGatewayPostReadOptions(mediaRootDir: mediaRoot.path, downloadMedia: false)
    )
    let sourceOnlyMedia = (((sourceOnlyPage["posts"] as? [[String: Any]])?.first)?["media"] as? [[String: Any]])?.first
    try assert(sourceOnlyMedia?["localFilePath"] == nil, "downloadMedia false should keep media source-only")

    let promotedPagePayload: [String: Any] = [
        "data": [
            [
                "id": "promoted",
                "text": "promoted",
                "promoted_metrics": ["impression_count": 10] as [String: Any]
            ] as [String: Any],
            [
                "id": "organic",
                "text": "organic",
                "organic_metrics": ["impression_count": 20] as [String: Any]
            ] as [String: Any]
        ],
        "meta": [
            "result_count": 2,
            "newest_id": "promoted",
            "oldest_id": "organic"
        ] as [String: Any]
    ]
    let filteredPromotedPage = try XGatewayResponseProjector.postPage(promotedPagePayload)
    let filteredPromotedPosts = filteredPromotedPage["posts"] as? [[String: Any]]
    let filteredPromotedPageInfo = filteredPromotedPage["pageInfo"] as? [String: Any]
    try assert(filteredPromotedPosts?.count == 1, "postPage projection should filter promoted posts by default")
    try assert(filteredPromotedPosts?.first?["id"] as? String == "organic", "postPage projection should keep organic posts")
    try assert(filteredPromotedPosts?.first?["promotionStatus"] as? String == "NOT_PROMOTED", "organic metrics should mark posts as not promoted")
    try assert(filteredPromotedPageInfo?["newestId"] as? String == "organic", "filtered pageInfo should use projected newest id")

    let includedPromotedPage = try XGatewayResponseProjector.postPage(promotedPagePayload, includePromoted: true)
    let includedPromotedPosts = includedPromotedPage["posts"] as? [[String: Any]]
    try assert(includedPromotedPosts?.count == 2, "includePromoted should keep promoted posts")
    try assert(includedPromotedPosts?.first?["promotionStatus"] as? String == "PROMOTED", "promoted metrics should mark promoted posts")

    do {
        _ = try XGatewayResponseProjector.post(["data": ["id": "promoted", "text": "promoted", "promoted_metrics": ["impression_count": 1] as [String: Any]] as [String: Any]])
        try assert(false, "promoted post lookup should throw by default")
    } catch let error as XGatewayErrorPayload {
        try assert(error.code == .permissionDenied, "promoted post lookup should use permission denied")
    }

    let includedPromotedPost = try XGatewayResponseProjector.post(
        ["data": ["id": "promoted", "text": "promoted", "promoted_metrics": ["impression_count": 1] as [String: Any]] as [String: Any]],
        includePromoted: true
    )
    try assert(includedPromotedPost["promotionStatus"] as? String == "PROMOTED", "includePromoted should return promoted post lookups")

    let created = XGatewayResponseProjector.createdPost([
        "data": ["id": "p2", "text": "created"]
    ])
    try assert(created["id"] as? String == "p2", "createdPost projection should expose id")

    let deleted = XGatewayResponseProjector.deletedPost(postId: "p2", [
        "data": ["deleted": true]
    ])
    try assert(deleted["id"] as? String == "p2", "deletedPost projection should fall back to requested id")
    try assert(deleted["deleted"] as? Bool == true, "deletedPost projection should expose deleted")

    let repost = XGatewayResponseProjector.repost(postId: "p3", [
        "data": ["retweeted": true]
    ], defaultReposted: true)
    try assert(repost["id"] as? String == "p3", "repost projection should fall back to requested id")
    try assert(repost["reposted"] as? Bool == true, "repost projection should expose reposted")
}

do {
    try runSmokeTests()
    print("Swift smoke tests passed")
} catch {
    FileHandle.standardError.write(Data("Swift smoke tests failed: \(error)\n".utf8))
    exit(1)
}
