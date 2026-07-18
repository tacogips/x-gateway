import Foundation

struct XGatewayDoctor {
    let surface: XGatewaySurface
    let environment: [String: String]
    let token: String?
    let appToken: String?
    let oauth1Credentials: XGatewayOAuth1SigningCredentials?
    let configuredCredentialVariables: Set<String>
    let transport: TransportSettings
    let traceId: String?
    let online: Bool

    func run() -> [String: Any] {
        let oauth1Variables = [
            "X_GW_CONSUMER_KEY",
            "X_GW_CONSUMER_SECRET",
            "X_GW_ACCESS_TOKEN",
            "X_GW_ACCESS_TOKEN_SECRET"
        ]
        let oauth1SetCount = oauth1Variables.filter { configuredCredentialVariables.contains($0) }.count
        let oauth1Status = familyStatus(configuredCount: oauth1SetCount, requiredCount: oauth1Variables.count)
        let userBearerStatus = token == nil ? "missing" : oauth2TokenStatus()
        let appBearerStatus = appToken == nil ? "missing" : "configured"

        let authChecks: [[String: Any]] = [
            authCheck(
                id: "oauth2-user-bearer",
                status: userBearerStatus,
                variables: ["X_GW_TOKEN", "X_GW_OAUTH2_EXPIRES_AT"],
                message: userBearerMessage(status: userBearerStatus),
                onlineResult: onlineResult(for: .userBearer)
            ),
            authCheck(
                id: "oauth1-user-context",
                status: oauth1Status,
                variables: oauth1Variables,
                message: oauth1Message(status: oauth1Status, configuredCount: oauth1SetCount),
                onlineResult: onlineResult(for: .oauth1)
            ),
            authCheck(
                id: "app-only-bearer",
                status: appBearerStatus,
                variables: ["X_GW_APP_TOKEN"],
                message: appToken == nil
                    ? "X_GW_APP_TOKEN is not set; app-context operations are unavailable unless X_GW_TOKEN can be used as fallback."
                    : "X_GW_APP_TOKEN is configured.",
                onlineResult: onlineResult(for: .appBearer)
            )
        ]

        let onlineFailures = authChecks.filter {
            (($0["online"] as? [String: Any])?["status"] as? String) == "failed"
        }.count
        let hasCompleteUserAuth = token != nil || oauth1Credentials != nil
        let configuredFamilies = [token != nil, oauth1Credentials != nil, appToken != nil].filter { $0 }.count
        let overallStatus: String
        if onlineFailures > 0 || userBearerStatus == "expired" {
            overallStatus = "error"
        } else if !hasCompleteUserAuth
                    || oauth1Status == "partial"
                    || userBearerStatus == "configured-expiry-invalid" {
            overallStatus = "warning"
        } else {
            overallStatus = "ok"
        }

        return [
            "status": overallStatus,
            "surface": surface.rawValue,
            "checkedAt": ISO8601DateFormatter().string(from: Date()),
            "onlineChecksEnabled": online,
            "summary": [
                "configuredAuthFamilies": configuredFamilies,
                "hasUserContextAuth": hasCompleteUserAuth,
                "onlineFailures": onlineFailures
            ],
            "auth": authChecks,
            "oauth2Client": oauth2ClientCheck(),
            "configuration": configurationReport(),
            "notes": [
                "Credential values are never included in doctor output.",
                "A configured token is only confirmed against X when online checks are enabled.",
                "Different X API operations may require additional OAuth2 scopes or app permissions."
            ]
        ]
    }

    private enum OnlineFamily {
        case userBearer
        case oauth1
        case appBearer
    }

    private func onlineResult(for family: OnlineFamily) -> [String: Any] {
        guard online else {
            return ["status": "skipped", "message": "Online checks were disabled with --online false."]
        }

        let executor: XGatewayLiveExecutor
        let document: String
        switch family {
        case .userBearer:
            guard let token else {
                return ["status": "skipped", "message": "No user bearer token is configured."]
            }
            executor = liveExecutor(token: token, appToken: nil, oauth1Credentials: nil)
            document = "{ accountMe { id username } }"
        case .oauth1:
            guard let oauth1Credentials else {
                return ["status": "skipped", "message": "Complete OAuth1 credentials are not configured."]
            }
            executor = liveExecutor(token: nil, appToken: nil, oauth1Credentials: oauth1Credentials)
            document = "{ accountMe { id username } }"
        case .appBearer:
            guard let appToken else {
                return ["status": "skipped", "message": "No app-only bearer token is configured."]
            }
            executor = liveExecutor(token: appToken, appToken: appToken, oauth1Credentials: nil)
            document = "{ userByUsername(username: \"X\") { id username } }"
        }

        do {
            _ = try executor.executeGraphQL(document: document, operationType: .query)
            return ["status": "valid", "message": "X accepted the configured credential for a read-only verification request."]
        } catch let error as XGatewayErrorPayload {
            return [
                "status": "failed",
                "code": error.code.rawValue,
                "message": error.summary
            ]
        } catch {
            return ["status": "failed", "code": "INTERNAL_ERROR", "message": String(describing: error)]
        }
    }

    private func liveExecutor(
        token: String?,
        appToken: String?,
        oauth1Credentials: XGatewayOAuth1SigningCredentials?
    ) -> XGatewayLiveExecutor {
        XGatewayLiveExecutor(
            token: token,
            appToken: appToken,
            oauth1Credentials: oauth1Credentials,
            mediaRootDir: nil,
            traceId: traceId,
            transport: transport
        )
    }

    private func authCheck(
        id: String,
        status: String,
        variables: [String],
        message: String,
        onlineResult: [String: Any]
    ) -> [String: Any] {
        [
            "id": id,
            "status": status,
            "variables": variables.map { variableReport(name: $0) },
            "message": message,
            "online": onlineResult
        ]
    }

    private func variableReport(name: String) -> [String: Any] {
        let isSet = configuredCredentialVariables.contains(name) || nonBlank(environment[name]) != nil
        return ["name": name, "status": isSet ? "set" : "missing"]
    }

    private func familyStatus(configuredCount: Int, requiredCount: Int) -> String {
        if configuredCount == 0 { return "missing" }
        if configuredCount == requiredCount { return "configured" }
        return "partial"
    }

    private func oauth2TokenStatus() -> String {
        guard let rawExpiration = nonBlank(environment["X_GW_OAUTH2_EXPIRES_AT"]) else {
            return "configured"
        }
        guard let seconds = TimeInterval(rawExpiration) else {
            return "configured-expiry-invalid"
        }
        return Date(timeIntervalSince1970: seconds) <= Date() ? "expired" : "configured"
    }

    private func userBearerMessage(status: String) -> String {
        switch status {
        case "missing":
            return "X_GW_TOKEN is not set; OAuth2 user-context operations are unavailable."
        case "expired":
            return "X_GW_TOKEN is set, but X_GW_OAUTH2_EXPIRES_AT indicates that it has expired."
        case "configured-expiry-invalid":
            return "X_GW_TOKEN is set, but X_GW_OAUTH2_EXPIRES_AT is not a Unix timestamp."
        default:
            return "X_GW_TOKEN is configured and its local expiry metadata does not indicate expiration."
        }
    }

    private func oauth1Message(status: String, configuredCount: Int) -> String {
        switch status {
        case "missing":
            return "OAuth1 credentials are not configured."
        case "partial":
            return "OAuth1 credentials are incomplete (\(configuredCount) of 4 required variables are set)."
        default:
            return "All four OAuth1 credential variables are configured."
        }
    }

    private func oauth2ClientCheck() -> [String: Any] {
        let clientIdSet = nonBlank(environment["X_GW_OAUTH2_CLIENT_ID"]) != nil
        let redirect = nonBlank(environment["X_GW_OAUTH2_REDIRECT_URI"])
            ?? "http://127.0.0.1:8765/callback"
        return [
            "status": clientIdSet ? "configured" : "optional",
            "clientId": variableReport(name: "X_GW_OAUTH2_CLIENT_ID"),
            "clientSecret": variableReport(name: "X_GW_OAUTH2_CLIENT_SECRET"),
            "refreshToken": variableReport(name: "X_GW_OAUTH2_REFRESH_TOKEN"),
            "redirectURI": redirect,
            "message": clientIdSet
                ? "The OAuth2 authorization helper has a client id."
                : "Set X_GW_OAUTH2_CLIENT_ID when using the built-in auth oauth2 flow."
        ]
    }

    private func configurationReport() -> [String: Any] {
        [
            "output": environment["X_GW_OUTPUT"] ?? "text",
            "mediaRootDir": nonBlank(environment["X_GW_MEDIA_ROOT_DIR"]) == nil ? "not-set" : "set",
            "transport": [
                "timeoutMs": transport.timeoutMs,
                "retryCount": transport.retryCount,
                "retryBackoff": transport.retryBackoff,
                "retryBaseMs": transport.retryBaseMs,
                "retryMaxMs": transport.retryMaxMs
            ]
        ]
    }
}
