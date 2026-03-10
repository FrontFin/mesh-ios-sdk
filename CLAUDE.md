# LinkSDK - iOS SDK for Mesh Connect

## Project Overview
LinkSDK is an iOS SDK that provides WebKit-based UI controllers for connecting to financial integrations via Mesh Connect. It uses a JavaScript bridge for web-to-native communication.

## Build Commands

Build the SDK (SPM):
```bash
swift build --sdk $(xcrun --show-sdk-path --sdk iphonesimulator) \
  -Xswiftc -target -Xswiftc arm64-apple-ios13.0-simulator
```

Build with Xcode:
```bash
xcodebuild -scheme LinkSDK \
  -destination 'generic/platform=iOS Simulator' \
  build
```

Run tests:
```bash
xcodebuild -scheme LinkSDKTests \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  test
```

Build XCFramework for release:
```bash
./build-framework.sh [version]
```

## Key Conventions
- Swift 5.7+, iOS 13+ minimum deployment target
- Swift Package Manager is the primary package manager (Package.swift)
- Xcode project (LinkSDK.xcodeproj) is also maintained for the example app and tests
- No CocoaPods or Carthage

## Architecture
- `LinkSDK/LinkSDK.swift` — Public API: `LinkConfiguration`, `LinkHandler`, `LinkResult`
- `LinkSDK/LinkWebViewController/` — Main WebView controller with JS message bridge
- `LinkSDK/Models/Payload.swift` — Data models for integration payloads
- `LinkSDK/Utils.swift` — Shared utilities
- `LinkSDKTests/` — XCTest unit tests
- `LinkSDKExample/` — Demo app showing SDK integration

## File Structure
```
LinkSDK/              # SDK source code
LinkSDKTests/         # Unit tests
LinkSDKExample/       # Example/demo app
LinkSDK.xcodeproj/    # Xcode project
Package.swift         # SPM manifest
build-framework.sh    # Release build script
```
