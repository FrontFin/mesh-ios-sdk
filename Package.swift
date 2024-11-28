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
            url: "https://github.com/FrontFin/mesh-ios-sdk/releases/download/3.0.7/LinkSDK.xcframework.zip",
            checksum: "02b953935d42bdbda716cf43baa4b608ce652d6351c06ad1f43a4b1879dd2032"
        ),
        .target(
            name: "LinkSDKResources",
            resources: [
                .process("LinkSDKResources.bundle")
            ]
        )
    ]
)
