# Mesh Connect iOS SDK

iOS library for integrating with Mesh Connect.

## Installation

Add package [LinkSDK](https://github.com/FrontFin/mesh-ios-sdk) in your project's Package Dependencies
or download [LinkSDK.xcframework](https://github.com/FrontFin/mesh-ios-sdk/tree/main/LinkSDK.xcframework).

## Get Link token

Link token should be obtained from the POST `/api/v1/linktoken` endpoint. API reference for this request is available [here](https://docs.meshconnect.com/reference/post_api-v1-linktoken). The request must be performed from the server side because it requires the client's secret. You will get the response in the following format:
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
- `transferDestinationTokens` - an array of `IntegrationAccessToken` objects that is used as a destination for crypto transfer flow;

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

The callback `onExit` is called once a user exits the Link flow. It might be used to dismiss the Link view controller in case the app manages its life cycle (see `LinkHandler.create()`)

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
