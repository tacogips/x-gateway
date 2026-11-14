import CoreFoundation
import Foundation

/// Finite machine diagnostics only; never infer a cause from free-form provider text.
public enum XGatewayProviderProblem: String, Sendable {
    case clientForbidden = "client-forbidden"
    case notAuthorized = "not-authorized-for-resource"
    case unsupportedAuthentication = "unsupported-authentication"
    case insufficientScope = "insufficient-scope"
    case usageCapped = "usage-capped"
    case rateLimited = "rate-limit-exceeded"
    case invalidRequest = "invalid-request"
    case resourceNotFound = "resource-not-found"
    case unknown
}

public enum XGatewayProviderReason: String, Sendable {
    case clientNotEnrolled = "client-not-enrolled"
    case insufficientScope = "insufficient-scope"
    case unsupportedAuthentication = "unsupported-authentication"
    case usageCapped = "usage-capped"
    case unknown
}

extension XGatewayErrorPayload {
    func withProviderDiagnostics(_ payload: Any) -> XGatewayErrorPayload {
        var result = self
        guard let object = payload as? [String: Any] else { return result }
        let entries = [object] + Array((object["errors"] as? [[String: Any]] ?? []).prefix(16))
        result.providerProblem = .unknown
        result.providerReason = .unknown
        for entry in entries {
            if let type = entry["type"] as? String, type.utf8.count <= 128 {
                for host in ["https://api.x.com/2/problems/", "https://api.twitter.com/2/problems/"] where type.hasPrefix(host) {
                    if let problem = XGatewayProviderProblem(rawValue: String(type.dropFirst(host.count))), problem != .unknown {
                        result.providerProblem = problem
                    }
                }
            }
            if let reason = (entry["reason"] ?? entry["error"]) as? String, reason.utf8.count <= 64 {
                let normalized = reason == "insufficient_scope" ? "insufficient-scope" : reason
                if let known = XGatewayProviderReason(rawValue: normalized), known != .unknown {
                    result.providerReason = known
                }
            }
            if result.providerErrorCode == nil, let number = entry["code"] as? NSNumber,
               CFGetTypeID(number) != CFBooleanGetTypeID(),
               (0...99_999).contains(number.doubleValue), number.doubleValue == Double(number.intValue) {
                result.providerErrorCode = number.intValue
            }
        }
        return result
    }
}
