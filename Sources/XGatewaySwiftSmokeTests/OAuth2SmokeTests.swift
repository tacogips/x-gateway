import Foundation
import XGatewayCore

func runOAuth2SmokeTests() throws {
    let verifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
    let challenge = XGatewayOAuth2.codeChallenge(for: verifier)
    try assert(challenge == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM", "OAuth2 PKCE S256 challenge should match RFC 7636")

    let defaultScopes = XGatewayOAuth2.parseScopes(nil)
    try assert(defaultScopes.contains("tweet.write"), "OAuth2 default scopes should include tweet.write")
    try assert(defaultScopes.contains("dm.write"), "OAuth2 default scopes should include dm.write")
    try assert(defaultScopes.contains("media.write"), "OAuth2 default scopes should include media.write")
    try assert(defaultScopes.contains("offline.access"), "OAuth2 default scopes should include offline.access")

    let parsedScopes = XGatewayOAuth2.parseScopes("tweet.read,tweet.write users.read\noffline.access")
    try assert(parsedScopes == ["tweet.read", "tweet.write", "users.read", "offline.access"], "OAuth2 scopes should parse comma and whitespace separators")

    let secretSentinel = "secret-value-that-must-not-appear-in-argv"
    let kinkoArguments = XGatewayOAuth2.kinkoSetArguments()
    try assert(!kinkoArguments.contains(secretSentinel), "OAuth2 kinko storage argv should not contain secret values")
    try assert(!kinkoArguments.contains("--value"), "OAuth2 kinko storage should avoid argv value passing")

    let authURL = try XGatewayOAuth2.authorizationURL(
        clientId: "client",
        redirectURI: "http://127.0.0.1:8765/callback",
        scopes: ["tweet.read", "offline.access"],
        state: "state",
        codeChallenge: "challenge"
    )
    let authURLString = authURL.absoluteString
    try assert(authURLString.contains("https://x.com/i/oauth2/authorize"), "OAuth2 authorization URL should use X authorization endpoint")
    try assert(authURLString.contains("response_type=code"), "OAuth2 authorization URL should request authorization code")
    try assert(authURLString.contains("code_challenge_method=S256"), "OAuth2 authorization URL should request PKCE S256")
    try assert(
        XGatewayOAuth2.manualAuthorizationMessage(for: authURL).contains(authURLString),
        "OAuth2 manual mode should expose the authorization URL before waiting"
    )

    let readCli = XGatewayCLI(commandName: "x-gateway-reader", surface: .read)
    let missingClientId = readCli.run(
        arguments: ["auth", "oauth2", "--open-browser", "false", "--json"],
        environment: [:]
    )
    try assert(missingClientId.exitCode == 2, "auth oauth2 should require a client id before opening a browser")
    try assert(missingClientId.stderr.contains("client-id"), "missing OAuth2 client id error should name the flag")

    let invalidRedirect = readCli.run(
        arguments: [
            "auth",
            "oauth2",
            "--client-id", "client",
            "--redirect-uri", "https://example.com/callback",
            "--open-browser", "false",
            "--json"
        ],
        environment: [:]
    )
    try assert(invalidRedirect.exitCode == 2, "auth oauth2 should reject non-loopback redirect URIs")
    try assert(invalidRedirect.stderr.contains("OAuth2 redirect URI is invalid"), "invalid redirect error should explain loopback requirement")

    let invalidStore = readCli.run(
        arguments: ["auth", "oauth2", "--client-id", "client", "--store", "file", "--open-browser", "false", "--json"],
        environment: [:]
    )
    try assert(invalidStore.exitCode == 2, "auth oauth2 should reject unsupported store modes")
    try assert(invalidStore.stderr.contains("store"), "invalid OAuth2 store error should name the flag")
}
