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
            url: "https://github.com/FrontFin/mesh-ios-sdk/releases/download/3.0.13/LinkSDK.xcframework.zip",
            checksum: "03d5edf15b912771df782cb3260028c97f5560c3d3fe13125aa27d2d2f7ef8f1"
        )
    ]
)
