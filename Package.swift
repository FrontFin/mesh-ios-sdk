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
            url: "https://github.com/FrontFin/mesh-ios-sdk/releases/download/3.0.8/LinkSDK.xcframework.zip",
            checksum: "4ef4fc14a5029ad0c6ee8266ba8b6d8c2a9e9b6aa769a59aaaadfc92f4294da7"
        )
    ]
)
