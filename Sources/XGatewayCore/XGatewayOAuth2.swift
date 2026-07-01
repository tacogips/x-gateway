import Foundation
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

#if os(Linux)
import Glibc
#else
import Darwin
#endif

public enum XGatewayOAuth2StoreMode: String, Sendable {
    case none
    case kinko
}

public struct XGatewayOAuth2Options: Sendable {
    public let clientId: String
    public let clientSecret: String?
    public let redirectURI: String
    public let scopes: [String]
    public let storeMode: XGatewayOAuth2StoreMode
    public let openBrowser: Bool
    public let timeoutSeconds: Int
    public let traceId: String?

    public init(
        clientId: String,
        clientSecret: String?,
        redirectURI: String,
        scopes: [String],
        storeMode: XGatewayOAuth2StoreMode,
        openBrowser: Bool,
        timeoutSeconds: Int,
        traceId: String?
    ) {
        self.clientId = clientId
        self.clientSecret = clientSecret
        self.redirectURI = redirectURI
        self.scopes = scopes
        self.storeMode = storeMode
        self.openBrowser = openBrowser
        self.timeoutSeconds = timeoutSeconds
        self.traceId = traceId
    }
}

struct XGatewayOAuth2TokenResponse: Decodable {
    let tokenType: String?
    let expiresIn: Int?
    let accessToken: String
    let refreshToken: String?
    let scope: String?

    private enum CodingKeys: String, CodingKey {
        case tokenType = "token_type"
        case expiresIn = "expires_in"
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case scope
    }
}

public enum XGatewayOAuth2 {
    public static let allKnownScopes = [
        "tweet.read",
        "tweet.write",
        "tweet.moderate.write",
        "users.read",
        "follows.read",
        "follows.write",
        "like.read",
        "like.write",
        "bookmark.read",
        "bookmark.write",
        "space.read",
        "list.read",
        "list.write",
        "mute.read",
        "mute.write",
        "block.read",
        "block.write",
        "dm.read",
        "dm.write",
        "media.write",
        "offline.access"
    ]

    public static func authorizationURL(
        clientId: String,
        redirectURI: String,
        scopes: [String],
        state: String,
        codeChallenge: String
    ) throws -> URL {
        guard var components = URLComponents(string: "https://x.com/i/oauth2/authorize") else {
            throw oauth2Internal("OAuth2 authorization URL could not be constructed.")
        }
        components.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: scopes.joined(separator: " ")),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256")
        ]
        guard let url = components.url else {
            throw oauth2Internal("OAuth2 authorization URL query could not be encoded.")
        }
        return url
    }

    public static func codeChallenge(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return base64URLEncoded(Data(digest))
    }

    public static func randomBase64URL(byteCount: Int) -> String {
        var bytes: [UInt8] = []
        bytes.reserveCapacity(byteCount)
        for _ in 0..<byteCount {
            bytes.append(UInt8.random(in: UInt8.min...UInt8.max))
        }
        return base64URLEncoded(Data(bytes))
    }

    public static func parseScopes(_ value: String?) -> [String] {
        guard let value,
              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() != "all" else {
            return allKnownScopes
        }
        return value
            .split { $0 == "," || $0 == " " || $0 == "\n" || $0 == "\t" }
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    public static func kinkoSetArguments() -> [String] {
        return ["kinko", "set", "--force"]
    }

    public static func manualAuthorizationMessage(for url: URL) -> String {
        return "Open this X OAuth2 authorization URL to continue: \(url.absoluteString)\n"
    }

    private static func base64URLEncoded(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "=", with: "")
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
    }
}

public struct XGatewayOAuth2LoopbackFlow {
    private let options: XGatewayOAuth2Options

    public init(options: XGatewayOAuth2Options) {
        self.options = options
    }

    public func run() throws -> [String: Any] {
        let redirect = try LoopbackRedirectURI(options.redirectURI, traceId: options.traceId)
        let verifier = XGatewayOAuth2.randomBase64URL(byteCount: 64)
        let state = XGatewayOAuth2.randomBase64URL(byteCount: 24)
        let authURL = try XGatewayOAuth2.authorizationURL(
            clientId: options.clientId,
            redirectURI: options.redirectURI,
            scopes: options.scopes,
            state: state,
            codeChallenge: XGatewayOAuth2.codeChallenge(for: verifier)
        )

        let server = try XGatewayLoopbackHTTPServer(redirect: redirect, traceId: options.traceId)
        let waitHandle = server.waitForCallback(expectedState: state, timeoutSeconds: options.timeoutSeconds)

        if options.openBrowser {
            try openAuthorizationURL(authURL)
        } else {
            FileHandle.standardError.write(Data(XGatewayOAuth2.manualAuthorizationMessage(for: authURL).utf8))
        }

        let callback = try waitHandle()
        let token = try exchangeToken(code: callback.code, verifier: verifier)
        try store(token: token)

        var result: [String: Any] = [
            "authorizationUrl": authURL.absoluteString,
            "redirectUri": options.redirectURI,
            "requestedScopes": options.scopes,
            "tokenType": token.tokenType ?? "bearer",
            "accessTokenStored": options.storeMode == .kinko,
            "refreshTokenStored": options.storeMode == .kinko && token.refreshToken != nil
        ]
        if let scope = token.scope {
            result["grantedScope"] = scope
        }
        if let expiresIn = token.expiresIn {
            result["expiresIn"] = expiresIn
        }
        if options.storeMode == .none {
            result["notes"] = [
                "OAuth2 succeeded, but token values are intentionally not printed.",
                "Re-run with --store kinko to save X_GW_TOKEN and refresh metadata in kinko."
            ]
        } else {
            result["storedKeys"] = storedKeys(for: token)
        }
        return result
    }

    private func exchangeToken(code: String, verifier: String) throws -> XGatewayOAuth2TokenResponse {
        guard let url = URL(string: "https://api.x.com/2/oauth2/token") else {
            throw oauth2Internal("OAuth2 token endpoint URL could not be constructed.")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = TimeInterval(options.timeoutSeconds)
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        if let secret = options.clientSecret {
            let basic = Data("\(options.clientId):\(secret)".utf8).base64EncodedString()
            request.setValue("Basic \(basic)", forHTTPHeaderField: "Authorization")
        }
        var body = URLComponents()
        body.queryItems = [
            URLQueryItem(name: "grant_type", value: "authorization_code"),
            URLQueryItem(name: "code", value: code),
            URLQueryItem(name: "redirect_uri", value: options.redirectURI),
            URLQueryItem(name: "client_id", value: options.clientId),
            URLQueryItem(name: "code_verifier", value: verifier)
        ]
        request.httpBody = body.percentEncodedQuery?.data(using: .utf8)

        let response = try performSynchronousRequest(request)
        guard (200..<300).contains(response.statusCode) else {
            throw XGatewayErrorPayload(
                code: .upstreamFailure,
                summary: "OAuth2 token exchange failed",
                details: "X returned HTTP \(response.statusCode) for POST /2/oauth2/token.",
                likelyCauses: ["OAuth2 client id or secret is invalid", "The authorization code expired", "The redirect URI does not match the X app settings"],
                remediations: ["Restart the OAuth2 flow and authorize again.", "Verify X_GW_OAUTH2_CLIENT_ID and X_GW_OAUTH2_CLIENT_SECRET."],
                classification: "upstream",
                retryable: false,
                traceId: options.traceId
            )
        }
        do {
            return try JSONDecoder().decode(XGatewayOAuth2TokenResponse.self, from: response.data)
        } catch {
            throw XGatewayErrorPayload(
                code: .upstreamFailure,
                summary: "OAuth2 token response could not be decoded",
                details: "X returned a token response that did not match the expected OAuth2 JSON shape.",
                likelyCauses: ["Unexpected X API response shape"],
                remediations: ["Retry the OAuth2 flow and inspect upstream X API status if it recurs."],
                classification: "upstream",
                retryable: true,
                traceId: options.traceId
            )
        }
    }

    private func performSynchronousRequest(_ request: URLRequest) throws -> (data: Data, statusCode: Int) {
        let semaphore = DispatchSemaphore(value: 0)
        final class Box: @unchecked Sendable {
            var value: Result<(Data, Int), Error>?
        }
        let box = Box()
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error {
                box.value = .failure(error)
            } else {
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
                box.value = .success((data ?? Data(), statusCode))
            }
            semaphore.signal()
        }
        task.resume()
        if semaphore.wait(timeout: .now() + .seconds(options.timeoutSeconds)) == .timedOut {
            task.cancel()
            throw XGatewayErrorPayload(
                code: .networkFailure,
                summary: "OAuth2 token exchange timed out",
                details: "No response was received from X before the configured timeout.",
                likelyCauses: ["Network connectivity issue", "X API token endpoint is slow or unavailable"],
                remediations: ["Retry the OAuth2 flow.", "Increase --timeout-seconds if the network is slow."],
                classification: "network",
                retryable: true,
                traceId: options.traceId
            )
        }
        do {
            return try box.value!.get()
        } catch {
            throw XGatewayErrorPayload(
                code: .networkFailure,
                summary: "OAuth2 token exchange request failed",
                details: String(describing: error),
                likelyCauses: ["Network connectivity issue", "TLS or DNS failure"],
                remediations: ["Retry the OAuth2 flow after checking network connectivity."],
                classification: "network",
                retryable: true,
                traceId: options.traceId
            )
        }
    }

    private func openAuthorizationURL(_ url: URL) throws {
        #if os(macOS)
        let executable = "/usr/bin/open"
        let arguments = [url.absoluteString]
        #elseif os(Linux)
        let executable = "/usr/bin/env"
        let arguments = ["xdg-open", url.absoluteString]
        #else
        return
        #endif
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        try process.run()
    }

    private func store(token: XGatewayOAuth2TokenResponse) throws {
        guard options.storeMode == .kinko else {
            return
        }
        try storeKinko(key: "X_GW_OAUTH2_CLIENT_ID", value: options.clientId)
        if let clientSecret = options.clientSecret {
            try storeKinko(key: "X_GW_OAUTH2_CLIENT_SECRET", value: clientSecret)
        }
        try storeKinko(key: "X_GW_TOKEN", value: token.accessToken)
        if let refreshToken = token.refreshToken {
            try storeKinko(key: "X_GW_OAUTH2_REFRESH_TOKEN", value: refreshToken)
        }
        if let scope = token.scope {
            try storeKinko(key: "X_GW_OAUTH2_SCOPE", value: scope)
        }
        if let expiresIn = token.expiresIn {
            let expiresAt = String(Int(Date().timeIntervalSince1970) + expiresIn)
            try storeKinko(key: "X_GW_OAUTH2_EXPIRES_AT", value: expiresAt)
        }
    }

    private func storeKinko(key: String, value: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = XGatewayOAuth2.kinkoSetArguments()
        let stderr = Pipe()
        let stdin = Pipe()
        process.standardInput = stdin
        process.standardError = stderr
        process.standardOutput = Pipe()
        try process.run()
        stdin.fileHandleForWriting.write(Data("\(key)=\(value)\n".utf8))
        try? stdin.fileHandleForWriting.close()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw XGatewayErrorPayload(
                code: .internalError,
                summary: "OAuth2 token storage failed",
                details: "kinko set-key failed for \(key).",
                likelyCauses: ["kinko is not installed or unlocked", "The current path scope is not initialized"],
                remediations: ["Run kinko status and unlock or initialize the vault.", "Re-run without --store kinko if you only need a one-time authorization check."],
                classification: "internal",
                retryable: false,
                traceId: options.traceId
            )
        }
    }

    private func storedKeys(for token: XGatewayOAuth2TokenResponse) -> [String] {
        var keys = ["X_GW_OAUTH2_CLIENT_ID"]
        if options.clientSecret != nil {
            keys.append("X_GW_OAUTH2_CLIENT_SECRET")
        }
        keys.append("X_GW_TOKEN")
        if token.refreshToken != nil {
            keys.append("X_GW_OAUTH2_REFRESH_TOKEN")
        }
        if token.scope != nil {
            keys.append("X_GW_OAUTH2_SCOPE")
        }
        if token.expiresIn != nil {
            keys.append("X_GW_OAUTH2_EXPIRES_AT")
        }
        return keys
    }
}

private struct LoopbackRedirectURI {
    let host: String
    let port: Int
    let path: String

    init(_ redirectURI: String, traceId: String?) throws {
        guard let components = URLComponents(string: redirectURI),
              components.scheme == "http",
              let host = components.host,
              let port = components.port,
              port > 0,
              port <= 65_535 else {
            throw XGatewayErrorPayload(
                code: .validationError,
                summary: "OAuth2 redirect URI is invalid",
                details: "--redirect-uri must be an http:// loopback URL with an explicit port.",
                likelyCauses: ["Missing port", "Unsupported scheme", "Malformed URL"],
                remediations: ["Use a redirect URI such as http://127.0.0.1:8765/callback and register it in the X app settings."],
                classification: "validation",
                retryable: false,
                traceId: traceId
            )
        }
        guard ["127.0.0.1", "localhost"].contains(host.lowercased()) else {
            throw XGatewayErrorPayload(
                code: .validationError,
                summary: "OAuth2 redirect URI must be loopback-only",
                details: "The Swift OAuth2 helper only binds localhost or 127.0.0.1 callback servers.",
                likelyCauses: ["Redirect URI points to a non-local host"],
                remediations: ["Use http://127.0.0.1:<port>/callback or http://localhost:<port>/callback."],
                classification: "validation",
                retryable: false,
                traceId: traceId
            )
        }
        self.host = host.lowercased() == "localhost" ? "127.0.0.1" : host
        self.port = port
        self.path = components.path.isEmpty ? "/" : components.path
    }
}

private struct XGatewayOAuth2Callback {
    let code: String
}

private struct XGatewayLoopbackHTTPServer {
    private let redirect: LoopbackRedirectURI
    private let socketFileDescriptor: Int32
    private let traceId: String?

    init(redirect: LoopbackRedirectURI, traceId: String?) throws {
        self.redirect = redirect
        self.traceId = traceId
        #if os(Linux)
        let streamSocket = Int32(SOCK_STREAM.rawValue)
        #else
        let streamSocket = SOCK_STREAM
        #endif
        let fd = socket(AF_INET, streamSocket, 0)
        guard fd >= 0 else {
            throw oauth2Socket("Could not create OAuth2 callback socket.", traceId: traceId)
        }
        var reuse: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = UInt16(redirect.port).bigEndian
        address.sin_addr = in_addr(s_addr: inet_addr(redirect.host))

        let bindResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                bind(fd, socketAddress, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else {
            close(fd)
            throw oauth2Socket("Could not bind OAuth2 callback server to \(redirect.host):\(redirect.port).", traceId: traceId)
        }
        guard listen(fd, 1) == 0 else {
            close(fd)
            throw oauth2Socket("Could not listen for OAuth2 callback.", traceId: traceId)
        }
        self.socketFileDescriptor = fd
    }

    func waitForCallback(expectedState: String, timeoutSeconds: Int) -> () throws -> XGatewayOAuth2Callback {
        final class Box: @unchecked Sendable {
            var result: Result<XGatewayOAuth2Callback, Error>?
        }
        let box = Box()
        let semaphore = DispatchSemaphore(value: 0)
        let fd = socketFileDescriptor
        let redirect = redirect
        let traceId = traceId

        DispatchQueue.global(qos: .userInitiated).async {
            box.result = Result {
                try acceptOneCallback(socketFileDescriptor: fd, redirect: redirect, expectedState: expectedState, traceId: traceId)
            }
            semaphore.signal()
        }

        return {
            if semaphore.wait(timeout: .now() + .seconds(timeoutSeconds)) == .timedOut {
                close(fd)
                throw XGatewayErrorPayload(
                    code: .networkFailure,
                    summary: "OAuth2 callback timed out",
                    details: "No request reached the local OAuth2 callback server before the timeout.",
                    likelyCauses: ["The browser authorization was not completed", "The X app redirect URI does not match --redirect-uri"],
                    remediations: ["Restart the OAuth2 flow and complete browser authorization.", "Confirm the redirect URI is registered exactly in the X app settings."],
                    classification: "network",
                    retryable: true,
                    traceId: traceId
                )
            }
            close(fd)
            return try box.result!.get()
        }
    }
}

private func acceptOneCallback(
    socketFileDescriptor: Int32,
    redirect: LoopbackRedirectURI,
    expectedState: String,
    traceId: String?
) throws -> XGatewayOAuth2Callback {
    let client = accept(socketFileDescriptor, nil, nil)
    guard client >= 0 else {
        throw oauth2Socket("OAuth2 callback connection could not be accepted.", traceId: traceId)
    }
    defer {
        close(client)
    }

    var buffer = Array(repeating: UInt8(0), count: 8192)
    let count = recv(client, &buffer, buffer.count, 0)
    guard count > 0,
          let request = String(bytes: buffer.prefix(count), encoding: .utf8),
          let firstLine = request.split(separator: "\r\n", maxSplits: 1).first else {
        try writeHTTPResponse(client, status: "400 Bad Request", body: "OAuth2 callback request was malformed.\n")
        throw oauth2Socket("OAuth2 callback request was malformed.", traceId: traceId)
    }
    let parts = firstLine.split(separator: " ")
    guard parts.count >= 2,
          parts[0] == "GET" else {
        try writeHTTPResponse(client, status: "405 Method Not Allowed", body: "OAuth2 callback requires GET.\n")
        throw oauth2Socket("OAuth2 callback used an unsupported HTTP method.", traceId: traceId)
    }
    let target = String(parts[1])
    guard let callbackURL = URL(string: "http://\(redirect.host):\(redirect.port)\(target)"),
          let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
          components.path == redirect.path else {
        try writeHTTPResponse(client, status: "404 Not Found", body: "OAuth2 callback path did not match.\n")
        throw oauth2Socket("OAuth2 callback path did not match the configured redirect URI.", traceId: traceId)
    }
    let query = components.queryItems ?? []
    if let error = query.first(where: { $0.name == "error" })?.value {
        try writeHTTPResponse(client, status: "400 Bad Request", body: "OAuth2 authorization was denied.\n")
        throw XGatewayErrorPayload(
            code: .permissionDenied,
            summary: "OAuth2 authorization was denied",
            details: "X redirected back with error '\(error)'.",
            likelyCauses: ["The browser authorization was cancelled", "The requested scopes were rejected"],
            remediations: ["Restart the OAuth2 flow and approve the requested app access."],
            classification: "auth",
            retryable: false,
            traceId: traceId
        )
    }
    guard query.first(where: { $0.name == "state" })?.value == expectedState else {
        try writeHTTPResponse(client, status: "400 Bad Request", body: "OAuth2 state did not match.\n")
        throw XGatewayErrorPayload(
            code: .authInvalid,
            summary: "OAuth2 callback state did not match",
            details: "The callback state did not match the state generated for this flow.",
            likelyCauses: ["Stale browser callback", "Unexpected request reached the local callback port"],
            remediations: ["Restart the OAuth2 flow."],
            classification: "auth",
            retryable: false,
            traceId: traceId
        )
    }
    guard let code = query.first(where: { $0.name == "code" })?.value,
          !code.isEmpty else {
        try writeHTTPResponse(client, status: "400 Bad Request", body: "OAuth2 callback did not include a code.\n")
        throw oauth2Socket("OAuth2 callback did not include an authorization code.", traceId: traceId)
    }
    try writeHTTPResponse(client, status: "200 OK", body: "x-gateway OAuth2 authorization complete. You can close this tab.\n")
    return XGatewayOAuth2Callback(code: code)
}

private func writeHTTPResponse(_ client: Int32, status: String, body: String) throws {
    let response = [
        "HTTP/1.1 \(status)",
        "Content-Type: text/plain; charset=utf-8",
        "Content-Length: \(body.utf8.count)",
        "Connection: close",
        "",
        body
    ].joined(separator: "\r\n")
    _ = response.withCString { pointer in
        send(client, pointer, strlen(pointer), 0)
    }
}

private func oauth2Internal(_ details: String) -> XGatewayErrorPayload {
    XGatewayErrorPayload(
        code: .internalError,
        summary: "OAuth2 helper failed internally",
        details: details,
        likelyCauses: ["Unexpected OAuth2 helper state"],
        remediations: ["Retry the command and report the failure if it recurs."],
        classification: "internal",
        retryable: false,
        traceId: nil
    )
}

private func oauth2Socket(_ details: String, traceId: String?) -> XGatewayErrorPayload {
    XGatewayErrorPayload(
        code: .networkFailure,
        summary: "OAuth2 callback server failed",
        details: details,
        likelyCauses: ["The callback port is already in use", "Local socket permissions prevented binding"],
        remediations: ["Choose a different --redirect-uri port.", "Close the process currently using the callback port."],
        classification: "network",
        retryable: true,
        traceId: traceId
    )
}
