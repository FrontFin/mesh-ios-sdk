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
        .package(url: "git@github.com:atomicfi/quantum-ios.git", exact: "3.12.0")
    ],
    targets: [
        .binaryTarget(
            name: "LinkSDK",
            url: "https://github.com/FrontFin/mesh-ios-sdk/releases/download/3.0.16/LinkSDK.xcframework.zip",
            checksum: "47d3a279cc877d8c922806482a122110325504f75855c9760f4590a978bd2d0e"
        )
    ]
)
