// swift-tools-version: 5.7
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "LinkSDK",
    platforms: [
        .iOS(.v15)
    ],
    products: [
        .library(
            name: "LinkSDK",
            targets: ["LinkSDK"]
        )
    ],
    dependencies: [
        .package(
            url: "https://github.com/atomicfi/quantum-ios.git",
            exact: "3.12.0"
        )
    ],
    targets: [
        .target(
            name: "LinkSDK",
            dependencies: [
                .product(name: "QuantumIOS", package: "quantum-ios")
            ],
            path: "Sources",
            linkerSettings: [
                .linkedFramework("QuantumIOS")
            ]
        )
    ]
)
