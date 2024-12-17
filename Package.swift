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
    targets: [
        .binaryTarget(
            name: "LinkSDK",
            url: "https://github.com/FrontFin/mesh-ios-sdk/releases/download/3.0.10/LinkSDK.xcframework.zip",
            checksum: "3be23a40ec3851d20d45c7795c250b7425faf9c1a36d37d8b07b262d6ec7f7aa"
        )
    ]
)
