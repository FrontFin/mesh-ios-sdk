# Mesh Connect iOS SDK

iOS library for integrating with Mesh Connect.

## Installation

Add package [LinkSDK](https://github.com/FrontFin/mesh-ios-sdk) in your project's Package Dependencies
or download [LinkSDK.xcframework](https://github.com/FrontFin/mesh-ios-sdk/LinkSDK.xcframework).

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
    onIntegrationConnected: onIntegrationConnected,
    onTransferFinished: onTransferFinished,
    onEvent: onEvent,
    onExit: onExit)
```

The parameter `useSecureOnDeviceStorage`  can be used to enable connected accounts storage in the keychain (disabled by default):

```swift
let settings = LinkSettings(useSecureOnDeviceStorage: true)
```

The `LinkStore` class is responsible for adding, removing, and retrieving connected accounts.

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

The callback `onTransferFinished` callback is called once a crypto transfer has been executed or failed. The parameter is either `success(TransferFinishedSuccessPayload)` or `error(TransferFinishedErrorPayload)`

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

## Store/Load connected accounts

The `LinkStore` keeps the connected account data in the keychain and allows to load it.
- `accessTokens` is an array of connected accounts
- `add(accessToken: AccessTokenPayload)` is called by SDK automatically on a successful account connection if `settings.useSecureOnDeviceStorage == true`
- `remove(accessToken: AccessTokenPayload)` the [Remove connection API](https://docs.meshconnect.com/reference/delete_api-v1-account) must be called before removing an account from `LinkStore`
- `saveAccessTokens()` is called automatically when an account is added/removed, and can be called by the app if some account's fields need to be modified

## V1 -> V2 migration guide

In Mesh Connect iOS SDK v2 the connected accounts are stored in the keychain as `AccessTokenPayload` instances.
Accounts, that were connected in an app using SDK v1, are converted to `AccessTokenPayload` automatically

```swift
let linkStore = LinkStore()
let accessTokens = linkStore.accessTokens
```

The following table explains how SDK classes and structures changed from v1 to v2

| SDK v1 | SDK v2 |
| ------ | ------ |
| GetFrontLinkSDK | LinkConfiguration, LinkHandler |
| GetFrontLinkSDK.brokerConnectWebViewController | LinkHandler.create() |
| GetFrontLinkSDK.connectBrokers(in:, delegate:) | LinkHandler.present(in viewController:) |
| BrokerConnectViewControllerDelegate | LinkConfiguration callbacks |
| accountsConnected(accounts:) | onIntegrationConnected: ((LinkPayload) -> Void) |
| transferFinished(transfer:) | onTransferFinished: ((TransferFinishedPayload) -> Void) |
| closeViewController(withConfirmation:) | onExit: (() -> Void) |
| GetFrontLinkSDK.defaultBrokersManager | LinkStore |
| BrokerAccount | AccessTokenPayload |
