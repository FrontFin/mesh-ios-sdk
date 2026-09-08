# Mesh Connect iOS SDK

iOS library for integrating with Mesh Connect.

## Installation

Add a [package dependency](https://developer.apple.com/documentation/xcode/adding-package-dependencies-to-your-app#Add-a-package-dependency) to your Xcode project using the source control repository URL:
```
https://github.com/FrontFin/mesh-ios-sdk
```

## Get Link token

Link token should be obtained from the POST `/api/v1/linktoken` endpoint. API reference for this request is available [here](https://docs.meshconnect.com/api-reference/managed-account-authentication/get-link-token-with-parameters). The request must be performed from the server side because it requires the client's secret. You will get the response in the following format:
```json
{
    "content": {
        "linkToken": "{linkToken}"
    },
    "status": "ok",
    "message": ""
}
```

## Launch Link

Create a `LinkConfiguration` instance with the `linkToken` and the callbacks:

```swift
let configuration = LinkConfiguration(
    linkToken: linkToken,
    settings: LinkSettings?,
    disableDomainWhiteList: Bool?,
    onIntegrationConnected: onIntegrationConnected,
    onTransferFinished: onTransferFinished,
    onEvent: onEvent,
    onExit: onExit)
```

The `LinkSettings` class allows to configure the Link behaviour:
- `accessTokens` - an array of `IntegrationAccessToken` objects that is used as an origin for crypto transfer flow;
- `language` - a locale identifier for Link UI
- `displayFiatCurrency` - a preferred display fiat currency
- `theme` - a preferred Link theme [dark|light|system]

The `disableDomainWhiteList` parameter is a boolean flag that allows to disable origin whitelisting. By default, the origin is whitelisted, with the predefined domains set

The `AccessTokenPayload.integrationAccessToken(accountToken: AccountToken)` function is used to convert an `AccessTokenPayload` to the `IntegrationAccessToken` object.

The callback `onIntegrationConnected` is called with `LinkPayload` once an integration has been connected.

```swift
let onIntegrationConnected: (LinkPayload)->() = { linkPayload in
    switch linkPayload {
    case .accessToken(let accessTokenPayload):
        print(accessTokenPayload)
    case .delayedAuth(let delayedAuthPayload):
        print(delayedAuthPayload)
    }
}
```

The callback `onTransferFinished` is called once a crypto transfer has been executed or failed.

```swift
let onTransferFinished: (TransferFinishedPayload)->() = { transferFinishedPayload in
    switch transferFinishedPayload {
    case .success(let successPayload):
        print(successPayload)
    case .error(let errorPayload):
        print(errorPayload.errorMessage)
    }
}
```

The callback `onEvent` is called to provide more details on the user's progress while interacting with the Link.
This is a list of possible event types, some of them may have additional parameters:
- `loaded`
- `integrationConnectionError`
- `integrationSelected`
- `credentialsEntered`
- `transferStarted`
- `transferPreviewed`
- `transferPreviewError`
- `transferExecutionError`

The `onExit` callback is optional, it's called once a user exits the Link flow. It might be used to dismiss the Link view controller in case the app manages its life cycle (see `LinkHandler.create()`)

Callback closures are optional, but either `onIntegrationConnected` or `onTransferFinished` must be provided.

Create a `LinkHandler` instance by calling `createHandler()` function, or handle an error.
The following errors can be returned:
- `Invalid linkToken`
- `Either 'onIntegrationConnected' or 'onTransferFinished' callback must be provided`

```swift
let result = configuration.createHandler()
switch result {
case .failure(let error):
    print(error)
case .success(let handler):
    handler.present(in: self)
}
```

In case of success, you can call `LinkHandler.present(in viewController)` function to let `LinkSDK` modally present the Link view controller and dismiss it on exit, or get the reference to a view controller by calling `LinkHandler.create()` if you prefer your app to manage its life cycle.

## Returning to your app with deep links

Some integrations cannot complete inside the Link web view and are handed off to the device's external browser. When the provider finishes, it redirects to a **return URL** that must bring your app back to the foreground so the in-progress Link flow can resume. There are a few approaches that make it happen.

### Native deep link

A custom URL scheme (for example `yourapp://`) is the quickest option and works without any web hosting.

1. Register the scheme in your app's `Info.plist` under `CFBundleURLTypes`:

```xml
<key>CFBundleURLTypes</key>
<array>
    <dict>
        <key>CFBundleURLName</key>
        <string>com.yourcompany.yourapp</string>
        <key>CFBundleURLSchemes</key>
        <array>
            <string>yourapp</string>
        </array>
    </dict>
</array>
```

2. Handle the incoming URL in your `UIWindowSceneDelegate`. Handle both the running-app case (`openURLContexts`) and the cold-launch case (`connectionOptions.urlContexts` in `willConnectTo`):

```swift
func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
    guard URLContexts.contains(where: { $0.url.scheme?.caseInsensitiveCompare("yourapp") == .orderedSame })
    else { return }
    // No action needed beyond returning focus: iOS foregrounds the existing
    // scene and the presented Link view controller resumes automatically.
}
```

> **iOS shows a confirmation prompt** — `Open in "YourApp"?` (Cancel / Open) — on every custom-scheme redirect from web content. It **cannot be suppressed**; use a Universal Link if you need the app to open without it.

### Universal Link (recommended, opens the app with no prompt)

A Universal Link is a regular `https://` URL that iOS routes straight to your app — with **no confirmation prompt** — as long as the app has a verified association with the website that serves it.

1. In Xcode, add the *Associated Domains* capability and declare the host that serves your return URL:

```xml
<key>com.apple.developer.associated-domains</key>
<array>
    <string>applinks:links.yourcompany.com</string>
</array>
```

2. Add an **`apple-app-site-association` (AASA) file** hosted on that domain at `https://links.yourcompany.com/.well-known/apple-app-site-association`, served over HTTPS with no redirect. `appID` is `<TeamID>.<BundleID>`:

```json
{
  "applinks": {
    "details": [
      {
        "appID": "ABCDE12345.com.yourcompany.yourapp",
        "components": [{ "/": "/link/return*" }]
      }
    ]
  }
}
```

3. **Handle the link** in your scene delegate. Universal Links are delivered as an `NSUserActivity` (not a URL context), via `scene(_:continue:)` while running and `connectionOptions.userActivities` on cold launch:

```swift
func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
    guard userActivity.activityType == NSUserActivityTypeBrowsingWeb,
          let url = userActivity.webpageURL,
          url.scheme?.caseInsensitiveCompare("https") == .orderedSame,
          url.host?.caseInsensitiveCompare("links.yourcompany.com") == .orderedSame
    else { return }
    // As with the custom scheme, no action is needed beyond returning focus.
}
```

Official references:
- [Allowing apps and websites to link to your content](https://developer.apple.com/documentation/xcode/allowing-apps-and-websites-to-link-to-your-content)
- [Supporting associated domains](https://developer.apple.com/documentation/xcode/supporting-associated-domains)
- [Defining a custom URL scheme for your app](https://developer.apple.com/documentation/xcode/defining-a-custom-url-scheme-for-your-app)
- [Debugging universal links (TN3155)](https://developer.apple.com/documentation/technotes/tn3155-debugging-universal-links)
