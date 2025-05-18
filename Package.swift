// swift-tools-version: 5.7
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "LinkSDK",
    platforms: [
      .iOS(.v15),
    ],
    products: [
        .library(
            name: "LinkSDK",
            targets: ["LinkSDK"]),
    ],
    targets: [
        .binaryTarget(
            name: "LinkSDK",
            url: "https://github.com/FrontFin/mesh-ios-sdk/releases/download/3.0.15/LinkSDK.xcframework.zip",
            checksum: "af37e6ef1f44b9fdda31689a23c35b8007cb14a61e3c2add4046d3ba83ddc406"
        )
    ]
)
