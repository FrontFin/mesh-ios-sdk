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
            url: "https://github.com/FrontFin/mesh-ios-sdk/releases/download/3.0.6/LinkSDK.xcframework.zip",
            checksum: "1c59d0afa33179b5bb0a8fe4df6d53aa0354dfa4b8b5b00f981a10bf0a9865fc"
        )
    ]
)
