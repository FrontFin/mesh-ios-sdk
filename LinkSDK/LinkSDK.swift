//
//  LinkSDK.swift
//  LinkSDK
//
//  Created by Mesh Connect, Inc
//

import Foundation
import UIKit

public enum LinkResult {
    case failure(String)
    case success(LinkHandler)
}

public struct LinkSettings {
    public var accessTokens: [IntegrationAccessToken]?
    public var transferDestinationTokens: [IntegrationAccessToken]?
    public var quantumConfig: [String: Any]?
    
    public init(accessTokens: [IntegrationAccessToken]? = nil,
                transferDestinationTokens: [IntegrationAccessToken]? = nil,
                quantumConfig: [String: Any]? = nil) {
        self.accessTokens = accessTokens
        self.transferDestinationTokens = transferDestinationTokens
        self.quantumConfig = quantumConfig
    }
}

public class LinkConfiguration {
    var linkToken: String
    var settings: LinkSettings?
    var disableDomainWhiteList: Bool?
    var onIntegrationConnected: ((LinkPayload) -> Void)?
    var onTransferFinished: ((TransferFinishedPayload) -> Void)?
    var onEvent: (([String: Any]?) -> Void)?
    var onExit: (() -> Void)?
    
    var catalogLink: String? {
        guard let linkTokenData = Data(base64Encoded: linkToken),
              let catalogLink = String(data: linkTokenData, encoding: .utf8),
              let url = URL(string: catalogLink),
              UIApplication.shared.canOpenURL(url) else {
            return nil
        }
        return catalogLink
    }
    
    public var isLinkTokenValid: Bool {
        catalogLink != nil
    }
    
    public var isTransferLink: Bool {
        catalogLink?.contains("transfer_token") ?? false
    }

    public init(linkToken: String,
                settings: LinkSettings? = nil,
                disableDomainWhiteList: Bool? = nil,
                onIntegrationConnected: ((LinkPayload) -> Void)? = nil,
                onTransferFinished: ((TransferFinishedPayload) -> Void)? = nil,
                onEvent: (([String: Any]?) -> Void)? = nil,
                onExit: (() -> Void)? = nil) {
        self.linkToken = linkToken
        self.settings = settings
        self.disableDomainWhiteList = disableDomainWhiteList
        self.onIntegrationConnected = onIntegrationConnected
        self.onTransferFinished = onTransferFinished
        self.onEvent = onEvent
        self.onExit = onExit
    }
    
    public func createHandler() -> LinkResult {
        guard onIntegrationConnected != nil || onTransferFinished != nil else {
            return .failure("Either 'onIntegrationConnected' or 'onTransferFinished' callback must be provided")
        }
        let handler = LinkHandler(configuration: self)
        guard handler.configuration.isLinkTokenValid else {
            return .failure("Invalid linkToken")
        }
        return .success(handler)
    }
}

public class LinkHandler {
    var configuration: LinkConfiguration
    
    init(configuration: LinkConfiguration) {
        self.configuration = configuration
    }
    
    public func create() -> UIViewController {
        return LinkWebViewViewController(configuration: configuration)
    }
    
    public func present(in viewController: UIViewController) {
        let originalOnExit = configuration.onExit
        configuration.onExit = {
            originalOnExit?()
            viewController.dismiss(animated: true)
        }
        let linkViewController = LinkWebViewViewController(configuration: configuration)
        linkViewController.modalPresentationStyle = .fullScreen
        viewController.present(linkViewController, animated: true)
    }
}
