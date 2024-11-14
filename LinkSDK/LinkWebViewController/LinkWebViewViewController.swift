//
//  LinkWebViewViewController.swift
//  LinkSDK
//
//  Created by Mesh Connect, Inc
//

import UIKit
@preconcurrency import WebKit

let DARK_THEME_COLOR_TOP : UInt = 0x1E1E24
let LIGHT_THEME_COLOR_TOP : UInt = 0xF3F4F5
let DARK_THEME_COLOR_BOTTOM : UInt = 0x0E0D0D
let LIGHT_THEME_COLOR_BOTTOM : UInt = 0xFBFBFB

enum JSMessageType: String {
    case showClose
    case close
    case done
    case brokerageAccountAccessToken
    case delayedAuthentication
    case showNativeNavbar
    case transferFinished
    case loaded
}

public enum TransferFinishedStatus: String {
    case transferFinishedSuccess = "success"
    case transferFinishedError = "error"
}

class LinkWebViewViewController: UIViewController {
    @IBOutlet weak var webView: WKWebView!
    @IBOutlet weak var topBar: UIView!
    @IBOutlet weak var statusBarBackgroundView: UIView!
    
    var configuration: LinkConfiguration
    
    private var showNativeNavBarDelayed = false
    private var isDarkTheme = false
    private var themeColorTop = LIGHT_THEME_COLOR_TOP
    private var themeColorBottom = LIGHT_THEME_COLOR_BOTTOM
    
    let jsMessageHandler = "jsMessageHandler"

    init(configuration: LinkConfiguration) {
        self.configuration = configuration
        let bundle = Bundle(for: LinkWebViewViewController.self)
        super.init(nibName: "LinkWebViewViewController", bundle: bundle)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        let appearance = UINavigationBarAppearance()
        appearance.configureWithTransparentBackground()
        appearance.titleTextAttributes = [.foregroundColor: UIColor.white]
        
        navigationController?.navigationBar.standardAppearance = appearance
        navigationController?.navigationBar.scrollEdgeAppearance = appearance
        navigationController?.navigationBar.compactAppearance = appearance
        navigationItem.hidesBackButton = true
        
        setupWebView()
    }
    
    func setupWebView() {
        guard let catalogLink = configuration.catalogLink,
        let url = URL(string: catalogLink) else { return }
        
        updateThemeVars(linkUrl: catalogLink)
        view.backgroundColor = UIColorFromRGB(rgbValue: themeColorBottom)
        statusBarBackgroundView.backgroundColor = UIColorFromRGB(rgbValue: themeColorTop)
        
        let request = URLRequest(url: url)
        webView.load(request)
        webView.navigationDelegate = self
        webView.addObserver(self, forKeyPath: "URL", options: .new, context: nil)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.bounces = false
        
        let contentController = WKUserContentController()
        webView.configuration.userContentController = contentController
        webView.configuration.userContentController.add(self, name: jsMessageHandler)
        webView.uiDelegate = self
    }
    
    private func updateThemeVars(linkUrl: String){
        let linkTheme = getThemeFromLinkUrl(linkUrl: linkUrl)
        
        isDarkTheme = linkTheme == "dark"
            ? true
            : linkTheme == "system"
                ? webView.traitCollection.userInterfaceStyle == .dark
                : false
        
        themeColorTop = isDarkTheme
            ? DARK_THEME_COLOR_TOP
            : LIGHT_THEME_COLOR_TOP
        
        themeColorBottom = isDarkTheme
            ? DARK_THEME_COLOR_BOTTOM
            : LIGHT_THEME_COLOR_BOTTOM
    }
    
    override var preferredStatusBarStyle: UIStatusBarStyle {
        return isDarkTheme ? .lightContent : .darkContent
    }
    
    @IBAction func closeTapped() {
        configuration.onExit?()
    }
    
    @IBAction func backTapped() {
        webView.goBack()
    }
    
}

internal extension LinkWebViewViewController {
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        //viewModel.observeValue(forKeyPath: keyPath, change: change)

        if let keyUrl = change?[NSKeyValueChangeKey.newKey] as? URL {
            let key = keyUrl.absoluteString
            updateUI(currentUrl: key)
        }
    }

    func updateUI(currentUrl: String) {
        if let url = URL(string: currentUrl), let host = url.host,
           let catalogAppHost = webView.backForwardList.backList.first?.url.host,
           host == catalogAppHost {
            showNativeNavbar(false)
        }
    }
    
    func showNativeNavbar(_ show: Bool) {
        if show {
            if showNativeNavBarDelayed {
                topBar.isHidden = false
                showNativeNavBarDelayed = false
            } else {
                showNativeNavBarDelayed = true
            }
        } else {
            topBar.isHidden = true
            showNativeNavBarDelayed = false
        }
    }
}

let allowedUrls = [
    "https://link.trustwallet.com",
    "https://appopener.meshconnect.com"
]

extension LinkWebViewViewController: WKNavigationDelegate {
    
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Swift.Void) {
        if let url = navigationAction.request.url {
            if allowedUrls.contains(where: { url.absoluteString.starts(with: $0) }) {
                decisionHandler(.cancel)
                if UIApplication.shared.canOpenURL(url) {
                    UIApplication.shared.open(url, options: [:], completionHandler: nil)
                }
                return
            }
        }
        decisionHandler(.allow)
    }
    
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
#if DEBUG
        configuration.onEvent?(["type": "webViewEvent", "payload": "didStartProvisionalNavigation"])
#endif
    }
    
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        showNativeNavbar(true)
#if DEBUG
        configuration.onEvent?(["type": "webViewEvent", "payload": "didFailProvisionalNavigation", "error": error.localizedDescription])
#endif
    }
    
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        showNativeNavbar(true)
#if DEBUG
        configuration.onEvent?(["type": "webViewEvent", "payload": "didFinish"])
#endif
    }
    
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        showNativeNavbar(true)
#if DEBUG
        configuration.onEvent?(["type": "webViewEvent", "payload": "didFail", "error": error.localizedDescription])
#endif
    }
    
    func webView(_ webView: WKWebView, didReceiveServerRedirectForProvisionalNavigation navigation: WKNavigation!) {
        showNativeNavbar(true)
#if DEBUG
        configuration.onEvent?(["type": "webViewEvent", "payload": "didReceiveServerRedirectForProvisionalNavigation"])
#endif
    }
}

extension LinkWebViewViewController: WKUIDelegate, WKScriptMessageHandler {

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == jsMessageHandler,
              let messageBody = message.body as? [String: Any],
              let type = messageBody["type"] as? String else {
            configuration.onEvent?(["Undefined message": message.body])
            return
        }
        let messageType = JSMessageType(rawValue: type)
        switch messageType {
        case .showNativeNavbar:
            guard let show = messageBody["payload"] as? Bool else { return }
            showNativeNavbar(show)
        case .brokerageAccountAccessToken:
            guard let payload = messageBody["payload"] as? [String: Any],
                  let jsonData = try? JSONSerialization.data(withJSONObject: payload),
                  let accessTokenPayload = try? JSONDecoder().decode(AccessTokenPayload.self, from: jsonData) else { return }
            configuration.onIntegrationConnected?(.accessToken(accessTokenPayload))
        case .delayedAuthentication:
            guard let payload = messageBody["payload"] as? [String: Any],
                  let jsonData = try? JSONSerialization.data(withJSONObject: payload),
                  let delayedAuthPayload = try? JSONDecoder().decode(DelayedAuthPayload.self, from: jsonData) else { return }
            configuration.onIntegrationConnected?(.delayedAuth(delayedAuthPayload))
        case .transferFinished:
            configuration.onEvent?(messageBody)
            guard let payload = messageBody["payload"] as? [String: Any],
                  let status = TransferFinishedStatus(rawValue: payload["status"] as? String ?? "") else { return }
            switch status {
            case .transferFinishedSuccess:
                guard let payload = messageBody["payload"] as? [String: Any],
                      let jsonData = try? JSONSerialization.data(withJSONObject: payload),
                      let transferFinishedSuccessPayload = try? JSONDecoder().decode(TransferFinishedSuccessPayload.self, from: jsonData) else { return }
                configuration.onTransferFinished?(.success(transferFinishedSuccessPayload))
            case .transferFinishedError:
                guard let payload = messageBody["payload"] as? [String: Any],
                      let jsonData = try? JSONSerialization.data(withJSONObject: payload),
                      let transferFinishedErrorPayload = try? JSONDecoder().decode(TransferFinishedErrorPayload.self, from: jsonData) else { return }
                configuration.onTransferFinished?(.error(transferFinishedErrorPayload))
            }
        case .showClose, .close, .done:
            configuration.onExit?()
        case .loaded:
            configuration.onEvent?(messageBody)

            var script = "window.meshSdkPlatform = 'iOS';"
            let bundle = Bundle(identifier: "com.meshconnect.LinkSDK")
            if let version = bundle?.infoDictionary?["CFBundleShortVersionString"] {
                script += "window.meshSdkVersion = '\(version)';"
            }
            
            if let accessTokens = configuration.settings?.accessTokens {
                if let data = try? JSONEncoder().encode(accessTokens),
                   let jsonString = String(data: data, encoding: String.Encoding.utf8) {
                    script += "window.accessTokens = '\(jsonString)';"
                }
            }
            if let transferDestinationTokens = configuration.settings?.transferDestinationTokens {
                if let data = try? JSONEncoder().encode(transferDestinationTokens),
                   let jsonString = String(data: data, encoding: String.Encoding.utf8) {
                    script += "window.transferDestinationTokens = '\(jsonString)';"
                }
            }
            
            webView.evaluateJavaScript(script)
        case .none:
            configuration.onEvent?(messageBody)
        }
    }
    
    @objc(webView:createWebViewWithConfiguration:forNavigationAction:windowFeatures:)
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        guard !(navigationAction.targetFrame?.isMainFrame ?? false) else { return nil }
        webView.load(navigationAction.request)
        return nil
    }
}
