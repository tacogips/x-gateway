public enum XGatewaySurface: String, Sendable {
    case read
    case write
}

public enum XGatewayGraphQLOperationType: String, Sendable {
    case query
    case mutation
}
