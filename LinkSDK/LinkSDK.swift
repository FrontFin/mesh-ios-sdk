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

public enum LinkTheme: String {
    case dark
    case light
    case system
}

/// Mesh environment an MFS session token belongs to. Names match the web SDK's
/// `LinkEnvironment`. There is deliberately no `local` case: it points at
/// localhost, which on a device is the device itself, and plain http is not
/// allowlisted. Tunnel a local Link through LocalCan instead.
public enum MeshLinkEnvironment: String {
    case prod
    case sbx
    case dev

    var linkUrl: String {
        switch self {
        case .prod: return "https://link.meshpay.com"
        case .sbx: return "https://link.sbx.meshpay.com"
        case .dev: return "https://link.dev.meshpay.com"
        }
    }
}

public struct LinkSettings {
    public var accessTokens: [IntegrationAccessToken]?
    public var language: String?
    public var displayFiatCurrency: String?
    public var theme: LinkTheme?
    public init(accessTokens: [IntegrationAccessToken]? = nil,
                language: String? = nil,
                displayFiatCurrency: String? = nil,
                theme: LinkTheme? = nil) {
        self.accessTokens = accessTokens
        self.language = language
        self.displayFiatCurrency = displayFiatCurrency
        self.theme = theme
    }
}

public class LinkConfiguration {
    var linkToken: String
    var settings: LinkSettings?
    var disableDomainWhiteList: Bool?
    var onIntegrationConnected: ((LinkPayload) -> Void)?
    var onTransferFinished: ((TransferFinishedPayload) -> Void)?
    var onEvent: (([String: Any]?) -> Void)?
    var onExit: ((Bool?) -> Void)?
    var linkViewController: LinkWebViewViewController?

    var catalogLink: String? {
        guard let linkTokenData = Data(base64Encoded: linkToken),
              var catalogLink = String(data: linkTokenData, encoding: .utf8),
              let url = URL(string: catalogLink),
              UIApplication.shared.canOpenURL(url) else {
            return nil
        }
        let addURLParam: ((String, String) -> Void) = { key, value in
            catalogLink += "\(catalogLink.contains("?") ? "&" : "?")\(key)=\(value)"
        }
        if let language = settings?.language {
            addURLParam("lng", language)
        }
        if let displayFiatCurrency = settings?.displayFiatCurrency {
            addURLParam("fiatCur", displayFiatCurrency)
        }
        if var theme = settings?.theme {
            if theme == .system {
                theme = UIScreen.main.traitCollection.userInterfaceStyle == .dark ? .dark : .light
            }
            addURLParam("th", theme.rawValue)
        }
        addURLParam("platform", "iOS")
        return catalogLink
    }
    
    public var isLinkTokenValid: Bool {
        catalogLink != nil
    }
    
    public var isTransferLink: Bool {
        catalogLink?.contains("transfer_token") ?? false
    }

    /// Builds a link token from an MFS session token.
    ///
    /// `POST /v2/sessions` returns a bare session token rather than a link
    /// token, and a bare token carries no host for the WebView to load. This
    /// wraps it into the same base64-of-a-URL shape `LinkConfiguration` already
    /// takes, so the MFS-native and legacy paths converge on one code path.
    ///
    /// The token is percent-encoded rather than interpolated: one carrying a
    /// reserved character (`&`, `#`, `%`, `+`) would otherwise truncate the URL
    /// at it and load Link with no token at all.
    public static func linkToken(sessionToken: String,
                                 environment: MeshLinkEnvironment) -> String {
        // Returning empty rather than trapping keeps the existing failure path:
        // `createHandler()` already reports an unusable token as `.failure`.
        guard !sessionToken.isEmpty else { return "" }
        let unreserved = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        let encoded = sessionToken.addingPercentEncoding(withAllowedCharacters: unreserved) ?? sessionToken
        return Data("\(environment.linkUrl)/?token=\(encoded)".utf8).base64EncodedString()
    }

    /// Opens Link for an MFS session token.
    ///
    /// `environment` is required rather than defaulted: a session token belongs
    /// to exactly one environment, and quietly assuming production would send a
    /// dev token to the wrong Link and fail in a way that is hard to read.
    public convenience init(sessionToken: String,
                            environment: MeshLinkEnvironment,
                            settings: LinkSettings? = nil,
                            disableDomainWhiteList: Bool? = nil,
                            onIntegrationConnected: ((LinkPayload) -> Void)? = nil,
                            onTransferFinished: ((TransferFinishedPayload) -> Void)? = nil,
                            onEvent: (([String: Any]?) -> Void)? = nil,
                            onExit: ((Bool?) -> Void)? = nil) {
        self.init(linkToken: LinkConfiguration.linkToken(sessionToken: sessionToken,
                                                         environment: environment),
                  settings: settings,
                  disableDomainWhiteList: disableDomainWhiteList,
                  onIntegrationConnected: onIntegrationConnected,
                  onTransferFinished: onTransferFinished,
                  onEvent: onEvent,
                  onExit: onExit)
    }

    public init(linkToken: String,
                settings: LinkSettings? = nil,
                disableDomainWhiteList: Bool? = nil,
                onIntegrationConnected: ((LinkPayload) -> Void)? = nil,
                onTransferFinished: ((TransferFinishedPayload) -> Void)? = nil,
                onEvent: (([String: Any]?) -> Void)? = nil,
                onExit: ((Bool?) -> Void)? = nil) {
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
        if configuration.onExit == nil {
            configuration.onExit = { [self] showAlert in
                if showAlert ?? false {
                    showExitAlert()
                } else {
                    configuration.linkViewController?.dismiss(animated: true)
                }
            }
        }
        let linkViewController = LinkWebViewViewController(configuration: configuration)
        linkViewController.modalPresentationStyle = .fullScreen
        viewController.present(linkViewController, animated: true)
        configuration.linkViewController = linkViewController
    }
        
    public func closeLink() -> Void {
        configuration.linkViewController?.dismiss(animated: true)
    }

    public func showExitAlert() {
        let locale = Locale(identifier: configuration.settings?.language ?? "en-US")
        let title = localizedString(forKey: "onExit_alert_title", locale: locale)
        let message = localizedString(forKey: "onExit_alert_message", locale: locale)
        let exit = localizedString(forKey: "onExit_alert_exit", locale: locale)
        let cancel = localizedString(forKey: "onExit_alert_cancel", locale: locale)
        
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        let okAction = UIAlertAction(title: exit, style: .default) { [self] _ in
            configuration.linkViewController?.dismiss(animated: true) { [self] in
                configuration.linkViewController = nil
                configuration.onExit?(false)
            }
        }
        alert.addAction(okAction)
        alert.addAction(UIAlertAction(title: cancel, style: .cancel))
        configuration.linkViewController?.present(alert, animated: true, completion: {
            alert.view.tintColor = UIColor.systemBlue
        })
    }
    
}
