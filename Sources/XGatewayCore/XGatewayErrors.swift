import Foundation

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
    public var httpStatus: Int?
    public var providerProblem: XGatewayProviderProblem?
    public var providerReason: XGatewayProviderReason?
    public var providerErrorCode: Int?

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
        if let httpStatus { object["httpStatus"] = httpStatus }
        if let providerProblem { object["providerProblem"] = providerProblem.rawValue }
        if let providerReason { object["providerReason"] = providerReason.rawValue }
        if let providerErrorCode { object["providerErrorCode"] = providerErrorCode }
        return object
    }
}
