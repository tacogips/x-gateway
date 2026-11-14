import Foundation
import XGatewayCrypto

public struct XGatewayOAuth1SigningCredentials: Sendable {
    public let consumerKey: String
    public let consumerSecret: String
    public let accessToken: String
    public let accessTokenSecret: String

    public init(
        consumerKey: String,
        consumerSecret: String,
        accessToken: String,
        accessTokenSecret: String
    ) {
        self.consumerKey = consumerKey
        self.consumerSecret = consumerSecret
        self.accessToken = accessToken
        self.accessTokenSecret = accessTokenSecret
    }
}

public enum XGatewayOAuth1Signer {
    public static func signatureBaseString(
        method: String,
        url: URL,
        queryParameters: [(String, String)] = [],
        oauthParameters: [(String, String)]
    ) -> String {
        let parameters = normalizedParameterString(
            queryParameters: queryParameters + queryParametersFromURL(url),
            oauthParameters: oauthParameters
        )
        return [
            oauthPercentEncode(method.uppercased()),
            oauthPercentEncode(normalizedBaseURL(url)),
            oauthPercentEncode(parameters)
        ].joined(separator: "&")
    }

    public static func signature(
        method: String,
        url: URL,
        credentials: XGatewayOAuth1SigningCredentials,
        nonce: String,
        timestamp: String,
        queryParameters: [(String, String)] = []
    ) -> String {
        let oauthParameters = baseOAuthParameters(
            credentials: credentials,
            nonce: nonce,
            timestamp: timestamp
        )
        let base = signatureBaseString(
            method: method,
            url: url,
            queryParameters: queryParameters,
            oauthParameters: oauthParameters
        )
        let signingKey = "\(oauthPercentEncode(credentials.consumerSecret))&\(oauthPercentEncode(credentials.accessTokenSecret))"
        return hmacSHA1Base64(message: base, key: signingKey)
    }

    public static func authorizationHeader(
        method: String,
        url: URL,
        credentials: XGatewayOAuth1SigningCredentials,
        nonce: String = UUID().uuidString,
        timestamp: String = String(Int(Date().timeIntervalSince1970)),
        queryParameters: [(String, String)] = []
    ) -> String {
        var oauthParameters = baseOAuthParameters(
            credentials: credentials,
            nonce: nonce,
            timestamp: timestamp
        )
        oauthParameters.append((
            "oauth_signature",
            signature(
                method: method,
                url: url,
                credentials: credentials,
                nonce: nonce,
                timestamp: timestamp,
                queryParameters: queryParameters
            )
        ))
        let sortedParameters = sortedParameters(oauthParameters)
        var headerParts: [String] = []
        headerParts.reserveCapacity(sortedParameters.count)
        for parameter in sortedParameters {
            headerParts.append("\(oauthPercentEncode(parameter.0))=\"\(oauthPercentEncode(parameter.1))\"")
        }
        let headerParameters = headerParts.joined(separator: ", ")
        return "OAuth \(headerParameters)"
    }

    public static func hmacSHA1Base64(message: String, key: String) -> String {
        let keyBytes: [UInt8] = Array(key.utf8)
        let messageBytes: [UInt8] = Array(message.utf8)
        var output: [UInt8] = Array(repeating: UInt8(0), count: 20)
        keyBytes.withUnsafeBufferPointer { keyBuffer in
            messageBytes.withUnsafeBufferPointer { messageBuffer in
                output.withUnsafeMutableBufferPointer { outputBuffer in
                    xgw_hmac_sha1(
                        keyBuffer.baseAddress,
                        keyBuffer.count,
                        messageBuffer.baseAddress,
                        messageBuffer.count,
                        outputBuffer.baseAddress
                    )
                }
            }
        }
        return Data(output).base64EncodedString()
    }

    private static func baseOAuthParameters(
        credentials: XGatewayOAuth1SigningCredentials,
        nonce: String,
        timestamp: String
    ) -> [(String, String)] {
        return [
            ("oauth_consumer_key", credentials.consumerKey),
            ("oauth_nonce", nonce),
            ("oauth_signature_method", "HMAC-SHA1"),
            ("oauth_timestamp", timestamp),
            ("oauth_token", credentials.accessToken),
            ("oauth_version", "1.0")
        ]
    }

    private static func normalizedBaseURL(_ url: URL) -> String {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false) ?? URLComponents()
        components.scheme = components.scheme?.lowercased()
        components.host = components.host?.lowercased()
        components.query = nil
        components.fragment = nil
        if let scheme = components.scheme,
           let port = components.port,
           (scheme == "http" && port == 80) || (scheme == "https" && port == 443) {
            components.port = nil
        }
        if components.path.isEmpty {
            components.path = "/"
        }
        return components.string ?? url.absoluteString
    }

    private static func normalizedParameterString(
        queryParameters: [(String, String)],
        oauthParameters: [(String, String)]
    ) -> String {
        var encoded: [(String, String)] = []
        encoded.reserveCapacity(queryParameters.count + oauthParameters.count)
        for parameter in queryParameters {
            encoded.append((oauthPercentEncode(parameter.0), oauthPercentEncode(parameter.1)))
        }
        for parameter in oauthParameters {
            encoded.append((oauthPercentEncode(parameter.0), oauthPercentEncode(parameter.1)))
        }

        var parts: [String] = []
        let sortedEncoded = sortedParameters(encoded)
        parts.reserveCapacity(sortedEncoded.count)
        for parameter in sortedEncoded {
            parts.append("\(parameter.0)=\(parameter.1)")
        }
        return parts.joined(separator: "&")
    }

    private static func queryParametersFromURL(_ url: URL) -> [(String, String)] {
        guard let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else {
            return []
        }
        var parameters: [(String, String)] = []
        parameters.reserveCapacity(items.count)
        for item in items {
            parameters.append((item.name, item.value ?? ""))
        }
        return parameters
    }

    private static func sortedParameters(_ parameters: [(String, String)]) -> [(String, String)] {
        return parameters.sorted { left, right in
            if left.0 == right.0 {
                return left.1 < right.1
            }
            return left.0 < right.0
        }
    }

    private static func oauthPercentEncode(_ value: String) -> String {
        var result = ""
        for byte in value.utf8 {
            if isOAuthUnreserved(byte),
               let scalar = UnicodeScalar(Int(byte)) {
                result.append(Character(scalar))
            } else {
                result += String(format: "%%%02X", byte)
            }
        }
        return result
    }

    private static func isOAuthUnreserved(_ byte: UInt8) -> Bool {
        return (byte >= 0x41 && byte <= 0x5a)
            || (byte >= 0x61 && byte <= 0x7a)
            || (byte >= 0x30 && byte <= 0x39)
            || byte == 0x2d
            || byte == 0x2e
            || byte == 0x5f
            || byte == 0x7e
    }

}
