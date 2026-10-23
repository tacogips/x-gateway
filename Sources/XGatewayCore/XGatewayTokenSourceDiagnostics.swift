import Foundation

extension XGatewayErrorPayload {
    func withTokenSource(_ source: String) -> XGatewayErrorPayload {
        guard [.authInvalid, .authExpired, .authRevoked, .permissionDenied].contains(code) else { return self }
        return XGatewayErrorPayload(
            code: code, summary: summary, details: "\(details) (tokenSource=\(source))",
            likelyCauses: likelyCauses,
            remediations: remediations + [
                "After auth oauth2 --store kinko, refresh X_GW_TOKEN from kinko in the calling environment; existing shell values are not updated.",
                "Remove a stale --token override. Complete OAuth1 credentials or X_GW_APP_TOKEN may select a different authentication mode for this operation."
            ],
            classification: classification, retryable: retryable, traceId: traceId, httpStatus: httpStatus,
            providerProblem: providerProblem, providerReason: providerReason, providerErrorCode: providerErrorCode,
            retryDiagnostics: retryDiagnostics
        )
    }
}
