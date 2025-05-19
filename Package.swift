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
        .package(url: "https://github.com/FrontFin/mesh-ios-sdk/releases/download/3.0.16/LinkSDK.xcframework.zip")
    ],
    targets: [
        .binaryTarget(
            name: "LinkSDK",
            url: "https://github.com/FrontFin/mesh-ios-sdk/releases/download/3.0.16/LinkSDK.xcframework.zip",
            checksum: "791858e6e75bb2d67140a0cc751d9201d1759610bfa5ab97facb0a5392db4366"
        )
    ]
)
