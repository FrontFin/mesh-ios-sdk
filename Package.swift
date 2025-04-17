// swift-tools-version: 5.7
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "LinkSDK",
    platforms: [
        .iOS(.v13)
    ],
    products: [
        .library(
            name: "LinkSDK",
            type: .dynamic,
            targets: ["LinkSDK"]),
    ],
    dependencies: [
        .package(url: "https://github.com/atomicfi/quantum-ios.git", branch: "main")
    ],
    targets: [
        .target(
            name: "LinkSDK",
            dependencies: [
                .product(name: "QuantumIOS", package: "quantum-ios")
            ],
            path: "LinkSDK",
            linkerSettings: [
                .linkedFramework("QuantumIOS")
            ]
        )
    ]
)
