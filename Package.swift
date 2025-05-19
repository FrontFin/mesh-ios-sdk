// swift-tools-version: 5.7
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "LinkSDK",
    platforms: [
      .iOS(.v13),
    ],
    products: [
        .library(
            name: "LinkSDK",
            targets: ["LinkSDK"]),
    ],
    dependencies: [
        .package(url: "https://github.com/atomicfi/quantum-ios.git", .exact("3.12.0"))
    ],
    targets: [
        .binaryTarget(
            name: "LinkSDK",
            url: "https://github.com/FrontFin/mesh-ios-sdk/releases/download/3.0.16/LinkSDK.xcframework.zip",
            checksum: "685fd85f1b1308175c6f09ca1c2f8c69a8eeee63c02e7dfbff7719f60414dea1"
        )
    ]
)
