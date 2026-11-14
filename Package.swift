// swift-tools-version: 5.8

import PackageDescription

let package = Package(
    name: "x-gateway",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "XGatewayCore",
            targets: ["XGatewayCore"]
        ),
        .executable(
            name: "x-gateway-reader",
            targets: ["XGatewayRead"]
        ),
        .executable(
            name: "x-gateway-writer",
            targets: ["XGatewayWrite"]
        ),
        .executable(
            name: "x-gateway-swift-smoke-tests",
            targets: ["XGatewaySwiftSmokeTests"]
        )
    ],
    targets: [
        .target(
            name: "XGatewayCrypto"
        ),
        .target(
            name: "XGatewayCore",
            dependencies: ["XGatewayCrypto"]
        ),
        .executableTarget(
            name: "XGatewayRead",
            dependencies: ["XGatewayCore"]
        ),
        .executableTarget(
            name: "XGatewayWrite",
            dependencies: ["XGatewayCore"]
        ),
        .executableTarget(
            name: "XGatewaySwiftSmokeTests",
            dependencies: ["XGatewayCore"]
        )
    ]
)
