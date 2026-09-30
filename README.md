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
- `withdrawalRequested`

When a user confirms a withdrawal, `onEvent` receives a `withdrawalRequested` event, then Link asks to close and calls `onExit`.
If you provide `onExit`, Link does not dismiss itself: dismiss it there with a completion, from the view controller you passed to `present(in:)` or from your own after `create()`.
With `create()`, Link never dismisses itself, so provide an `onExit` that does.
Keep the `transferId` and continue the withdrawal in that completion, for example with your own 2FA prompt: presenting a view controller while Link is still on screen conflicts with its dismissal.
Treat the event, not `onExit`, as confirmation of the withdrawal.
The payload carries no address or amount: read the transfer details from the webhook or the transfer API.

```swift
let onEvent: ([String: Any]?)->() = { event in
    guard event?["type"] as? String == "withdrawalRequested",
          let payload = event?["payload"] as? [String: Any],
          let transferId = payload["transferId"] as? String else { return }
    let status = payload["status"] as? String // "pending" or "success"; treat any other value as pending
}
```

The `onExit` callback is optional, it's called once a user exits the Link flow.
If you provide it, it must dismiss the Link view controller: `present(in:)` dismisses Link itself only when `onExit` is not provided.

Callback closures are optional, but at least one of `onIntegrationConnected`, `onTransferFinished` or `onEvent` must be provided.

Create a `LinkHandler` instance by calling `createHandler()` function, or handle an error.
The following errors can be returned:
- `Invalid linkToken`
- `Either 'onIntegrationConnected', 'onTransferFinished' or 'onEvent' callback must be provided`

```swift
let result = configuration.createHandler()
switch result {
case .failure(let error):
    print(error)
case .success(let handler):
    handler.present(in: self)
}
```

In case of success, you can call `LinkHandler.present(in viewController)` function to let `LinkSDK` modally present the Link view controller and dismiss it on exit (when no `onExit` is provided), or get the reference to a view controller by calling `LinkHandler.create()` if you prefer your app to manage its life cycle.

## Returning to your app with deep links

Some integrations complete in the device's external browser, then redirect to a **return URL** that must bring your app back to the foreground so the flow can resume.

### Native deep link

A custom URL scheme (e.g. `yourapp://`) is the quickest option. Register the scheme under `CFBundleURLTypes` in your app's `Info.plist` and handle the incoming URL in your scene delegate. iOS shows an `Open in "YourApp"?` confirmation prompt on every redirect from web content, and this prompt can't be suppressed. See [Defining a custom URL scheme for your app](https://developer.apple.com/documentation/xcode/defining-a-custom-url-scheme-for-your-app) for details.

### Universal Link (recommended)

A verified `https://` URL that iOS opens directly in your app, without a confirmation prompt. Add the *Associated Domains* capability with an `applinks:` entry for your host, and associate your website with the app by hosting an `apple-app-site-association` file. See [Supporting associated domains](https://developer.apple.com/documentation/xcode/supporting-associated-domains) for details.
