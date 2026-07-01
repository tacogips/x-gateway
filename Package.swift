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
    dependencies: [
        .package(url: "https://github.com/apple/swift-crypto.git", from: "3.0.0")
    ],
    targets: [
        .target(
            name: "XGatewayCore",
            dependencies: [
                .product(name: "Crypto", package: "swift-crypto")
            ]
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
