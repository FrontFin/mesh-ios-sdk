//
//  LinkWebViewViewController.swift
//  LinkSDK
//
//  Created by Mesh Connect, Inc
//

import UIKit
@preconcurrency import WebKit
import SafariServices

let meshSDKVersion = "3.4.1"

let DARK_THEME_COLOR_TOP : UInt = 0x1E1E24
let LIGHT_THEME_COLOR_TOP : UInt = 0xF3F4F5
let DARK_THEME_COLOR_BOTTOM : UInt = 0x0E0D0D
let LIGHT_THEME_COLOR_BOTTOM : UInt = 0xFBFBFB

let allowedUrls = [
    "https://link.trustwallet.com",
    "https://integration-api.meshconnect.com",
    "https://sandbox-integration-api.meshconnect.com",
    "https://dev-integration-api.meshconnect.com",
    "https://dev-sandbox-integration-api.meshconnect.com",
    "https://www.coinbase.com",
    "https://api.cb-device-intelligence.com"
]

let whitelistedOrigins = [
    ".meshconnect.com",
    ".meshpay.com",
    ".walletconnect.com",
    ".walletconnect.org",
    ".walletlink.org",
    ".okx.com",
    ".gemini.com",
    ".hcaptcha.com",
    ".robinhood.com",
    //recaptcha
    ".google.com",
    //Robinhood
    "https://robinhood.com",
    "https://m.stripe.network",
    "https://js.stripe.com",
    "https://app.usercentrics.eu",
    //Okx
    "https://contentmx.okcoin.com",
    "https://www.recaptcha.net"
]

/// Hosts that match a whitelisted origin above by suffix but are actually a
/// different product than the one that entry is for, so they should NOT be
/// loaded in our own webview. `web3.okx.com` is OKX Wallet's connect/deep-link
/// host, not OKX Exchange (why `.okx.com` is whitelisted in the first place),
/// and needs to be handed to iOS like any other wallet link.
let whitelistedOriginExceptions = [
    "web3.okx.com"
]

func isWhitelistedOrigin(_ url: URL) -> Bool {
    guard let host = url.host?.lowercased() else { return false }
    if whitelistedOriginExceptions.contains(host) {
        return false
    }
    return whitelistedOrigins.contains { entry in
        if entry.hasPrefix(".") {
            return host.hasSuffix(entry)
        }
        // Full origins match on scheme + exact host, never a raw string prefix,
        // which `robinhood.com.evil.com` or `robinhood.com@evil.com` would pass.
        guard let origin = URL(string: entry) else { return false }
        return url.scheme?.lowercased() == origin.scheme && host == origin.host
    }
}

/// MFS's OAuth hand-off (`/v2/sessions/{id}/child-sessions/{id}:redirect`),
/// which must leave the webview: its host is allowlisted, so loading it in place
/// would unload Link and lose the session that finishes the connection.
func isMfsOAuthRedirect(_ url: URL) -> Bool {
    guard url.scheme?.lowercased() == "https",
          let host = url.host?.lowercased(),
          host.hasPrefix("api."), host.hasSuffix(".meshpay.com") else {
        return false
    }
    // Keeps empty segments, so `//` or a missing ID can't still line up.
    let parts = url.path.components(separatedBy: "/")
    let suffix = ":redirect"
    return parts.count == 6
        && parts[0].isEmpty
        && parts[1] == "v2"
        && parts[2] == "sessions"
        && !parts[3].isEmpty
        && parts[4] == "child-sessions"
        && parts[5].count > suffix.count
        && parts[5].hasSuffix(suffix)
}

enum JSMessageType: String {
    case showClose
    case close
    case done
    case brokerageAccountAccessToken
    case delayedAuthentication
    case showNativeNavbar
    case transferFinished
    case loaded
    case integrationSelected
    case openTrueAuth
}

public enum TransferFinishedStatus: String {
    case transferFinishedSuccess = "success"
    case transferFinishedError = "error"
}

class LinkWebViewViewController: UIViewController {
    /// Schemes never handed to the OS from web content. `javascript:`/`data:`
    /// execute in whatever context receives them, `file:` reaches local
    /// storage, `about:`/`blob:` are inert but meaningless to launch.
    /// Everything else non-http(s) is treated as a wallet deep link.
    static let blockedSchemes: Set<String> = [
        "javascript", "data", "file", "about", "blob"
    ]

    enum PopupAction: Equatable {
        case loadInWebView
        case openExternally
        case ignore
    }

    /// Where a `window.open()` / `target=_blank` request goes. Only the top-level
    /// page may load it in place: it can already navigate itself, but a subframe
    /// doing so would replace the Mesh page with its own document. An unknown
    /// source (`nil`) is treated as a subframe.
    static func popupAction(sourceIsMainFrame: Bool?, url: URL?) -> PopupAction {
        if sourceIsMainFrame == true {
            return .loadInWebView
        }
        guard let scheme = url?.scheme?.lowercased(), !blockedSchemes.contains(scheme) else {
            return .ignore
        }
        return .openExternally
    }

    /// Script run on `loaded`. Link reads `window.accessTokens` as a JSON
    /// string, so the tokens are encoded to JSON and then passed as a string.
    static func loadedScript(accessTokens: [IntegrationAccessToken]?) -> String {
        var script = "window.meshSdkPlatform = 'iOS';window.meshSdkVersion = '\(meshSDKVersion)';"
        if let accessTokens = accessTokens,
           let data = try? JSONEncoder().encode(accessTokens),
           let jsonString = String(data: data, encoding: .utf8) {
            script += "window.accessTokens = \(jsStringLiteral(jsonString));"
        }
        return script
    }

    /// Script answering `integrationSelected`. The link comes from web content,
    /// and `'` is legal in a URL, so it is passed as an escaped string.
    static func nativeLinkScript(url: URL, canOpen: Bool) -> String {
        return "window.handleNativeLink = { url: \(jsStringLiteral(url.absoluteString)), canOpen: \(canOpen) };"
    }

    /// Script handing the TrueAuth result to Link. The result comes from web
    /// content in the TrueAuth webview, so it is passed as an escaped string.
    static func trueAuthResultScript(_ result: String) -> String {
        return "window.trueAuthResult = \(jsStringLiteral(result));"
    }

    private let webView: WKWebView = {
        // Without this, WebKit silently blocks any `window.open()` that isn't
        // inside a live user gesture (e.g. an auto-open fired from an async
        // event) and never even calls createWebViewWith below - so wallet
        // deep links and OAuth handoffs that should open automatically just
        // dead-end instead.
        let configuration = WKWebViewConfiguration()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
        let wkWebView = WKWebView(frame: .zero, configuration: configuration)
        wkWebView.contentMode = .scaleToFill
        wkWebView.translatesAutoresizingMaskIntoConstraints = false
        wkWebView.backgroundColor = UIColor(cgColor: CGColor(genericGrayGamma2_2Gray: 1, alpha: 1))
        return wkWebView
    }()

    private let topBar: UIView = {
        let view = UIView()
        view.isHidden = true
        view.contentMode = .scaleToFill
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = UIColor(cgColor: CGColor(genericGrayGamma2_2Gray: 1, alpha: 1))
        return view
    }()

    private let statusBarBackgroundView: UIView = {
        let view = UIView()
        view.contentMode = .scaleToFill
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .systemBackground
        return view
    }()
    
    private let stackView: UIStackView = {
        let stackView = UIStackView()
        stackView.contentMode = .scaleToFill
        stackView.axis = .vertical
        stackView.translatesAutoresizingMaskIntoConstraints = false
        return stackView
    }()
    
    private lazy var backButton: UIButton = {
        let button = UIButton()
        button.contentMode = .scaleToFill
        button.contentHorizontalAlignment = .center
        button.contentVerticalAlignment = .center
        button.translatesAutoresizingMaskIntoConstraints = false
        button.titleLabel?.font = .systemFont(ofSize: 18)
        button.tintColor = UIColor(cgColor: CGColor(genericGrayGamma2_2Gray: 0.0, alpha: 1))
        button.setImage(UIImage(systemName: "chevron.left"), for: .normal)
        button.addTarget(self, action: #selector(backTapped), for: .touchUpInside)
        return button
    }()
    
    private lazy var closeButton: UIButton = {
        let button = UIButton()
        button.contentMode = .scaleToFill
        button.contentHorizontalAlignment = .center
        button.contentVerticalAlignment = .center
        button.translatesAutoresizingMaskIntoConstraints = false
        button.titleLabel?.font = .systemFont(ofSize: 26)
        button.tintColor = UIColor(cgColor: CGColor(genericGrayGamma2_2Gray: 0.0, alpha: 1))
        button.setImage(UIImage(systemName: "xmark"), for: .normal)
        button.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        return button
    }()
    
    var configuration: LinkConfiguration
    
    private var safariViewController: SFSafariViewController?
    
    private var showNativeNavBarDelayed = false
    /// Host of the first page Link committed, after any redirects.
    private var linkHost: String?
    private var isDarkTheme = false
    private var themeColorTop = LIGHT_THEME_COLOR_TOP
    private var themeColorBottom = LIGHT_THEME_COLOR_BOTTOM
    
    let jsMessageHandler = "jsMessageHandler"

    init(configuration: LinkConfiguration) {
        self.configuration = configuration
        super.init(nibName: nil, bundle: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(didEnterBackground), name: UIScene.didEnterBackgroundNotification, object: nil)
        setupGeneratedViews()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    @objc func didEnterBackground() {
        safariViewController?.dismiss(animated: false)
        safariViewController = nil
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
        
        setupGeneratedViews()
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
        
        if #available(iOS 16.4, *) {
            webView.isInspectable = true
        }
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
    
    @objc func closeTapped() {
        configuration.onExit?(true)
    }
    
    @objc func backTapped() {
        webView.goBack()
    }
    
}

internal extension LinkWebViewViewController {
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
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
    
    /// True when `host` is Link's own site: `linkHost` itself or a sibling under
    /// its parent domain (`link.x.com` covers `api.x.com`). An IP has no siblings.
    static func isLinkSite(_ host: String?, linkHost: String?) -> Bool {
        guard let host = host?.lowercased(), let linkHost = linkHost?.lowercased() else { return false }
        if host == linkHost { return true }
        let labels = linkHost.split(separator: ".")
        guard labels.count > 2, !labels.allSatisfy({ Int($0) != nil }) else { return false }
        let site = labels.dropFirst().joined(separator: ".")
        return host == site || host.hasSuffix("." + site)
    }

    /// A navigation we stopped on purpose (e.g. a URL handed to Safari), not a failed load.
    static func isCancellation(_ error: Error) -> Bool {
        let error = error as NSError
        return (error.domain == NSURLErrorDomain && error.code == NSURLErrorCancelled)
            || (error.domain == "WebKitErrorDomain" && error.code == 102)
    }

    /// Link draws its own controls on its own site, so page loads there keep the
    /// native bar hidden. A real load failure still gets it as a way out.
    static func keepsNativeNavbarHidden(host: String?, linkHost: String?, error: Error?) -> Bool {
        guard isLinkSite(host, linkHost: linkHost) else { return false }
        guard let error = error else { return true }
        return isCancellation(error)
    }

    /// Page-load trigger for the native bar. A hidden load still counts towards
    /// the next off-site page, as before.
    func showNativeNavbarAfterPageLoad(error: Error? = nil) {
        guard Self.keepsNativeNavbarHidden(host: webView.url?.host, linkHost: linkHost, error: error) else {
            showNativeNavbar(true)
            return
        }
        topBar.isHidden = true
        showNativeNavBarDelayed = true
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
    
    func setupGeneratedViews() {
        view.backgroundColor = .systemBackground
        
        addSubViews()
        setupConstraints()
    }

    func addSubViews() {
        view.addSubview(statusBarBackgroundView)
        view.addSubview(stackView)
        stackView.addArrangedSubview(topBar)
        stackView.addArrangedSubview(webView)
        topBar.addSubview(backButton)
        topBar.addSubview(closeButton)
        
    }

    func setupConstraints() {
        NSLayoutConstraint.activate([
            backButton.leadingAnchor.constraint(equalTo: topBar.leadingAnchor, constant: 6),
            backButton.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),
            backButton.widthAnchor.constraint(equalToConstant: 44),
            backButton.heightAnchor.constraint(equalToConstant: 44),
        
            closeButton.trailingAnchor.constraint(equalTo: topBar.trailingAnchor, constant: -6),
            closeButton.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: 44),
            closeButton.heightAnchor.constraint(equalToConstant: 44),
        
            topBar.heightAnchor.constraint(equalToConstant: 68),
        
            stackView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            stackView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            stackView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
        
            view.trailingAnchor.constraint(equalTo: statusBarBackgroundView.trailingAnchor),
        
            statusBarBackgroundView.topAnchor.constraint(equalTo: view.topAnchor),
            statusBarBackgroundView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
        
            view.safeAreaLayoutGuide.topAnchor.constraint(equalTo: statusBarBackgroundView.bottomAnchor),
        
        ])
        
    }
}

extension LinkWebViewViewController: WKNavigationDelegate {
    
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }

        // Check if the URL is in allowedUrls (only for http/https)
        if ["http", "https"].contains(url.scheme) {
            // if a url is in allowedUrls open it inSafari
            if allowedUrls.contains(where: { url.absoluteString.starts(with: $0) }) ||
                isMfsOAuthRedirect(url) ||
                // or if domain whitelisting is not disable and url is not included in the list, open it inSafari
                (!(configuration.disableDomainWhiteList ?? false) &&
                 !isWhitelistedOrigin(url)) {
                UIApplication.shared.open(url, options: [:], completionHandler: nil)
                decisionHandler(.cancel) // Cancel WebView navigation
                return
            }
        }

        // Handle custom schemes (e.g., wallet://)
        if !["http", "https"].contains(url.scheme) {
            // Deliberately NOT gated on `canOpenURL`: it answers false for any
            // scheme the integrator's Info.plist omits, installed or not, and iOS
            // caps that list at 50 against a 900+ wallet catalog. `open` needs no
            // declaration and reports the real result.
            if Self.blockedSchemes.contains((url.scheme ?? "").lowercased()) {
                decisionHandler(.cancel)
                return
            }
            UIApplication.shared.open(url, options: [:]) { opened in
                if !opened {
#if DEBUG
                    print("Could not open URL scheme: \(url.scheme ?? "unknown")")
#endif
                }
            }
            decisionHandler(.cancel) // Cancel WebView navigation
            return
        }

        // Allow other http/https URLs to load in WebView
        decisionHandler(.allow)
    }
    
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
#if DEBUG
        configuration.onEvent?(["type": "webViewEvent", "payload": "didStartProvisionalNavigation"])
#endif
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        if linkHost == nil {
            linkHost = webView.url?.host?.lowercased()
        }
        // Redirects before this commit may have shown the bar before Link's host was known.
        if Self.isLinkSite(webView.url?.host, linkHost: linkHost) {
            topBar.isHidden = true
        }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        showNativeNavbarAfterPageLoad(error: error)
#if DEBUG
        configuration.onEvent?(["type": "webViewEvent", "payload": "didFailProvisionalNavigation", "error": error.localizedDescription])
#endif
    }
    
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        showNativeNavbarAfterPageLoad()
#if DEBUG
        configuration.onEvent?(["type": "webViewEvent", "payload": "didFinish"])
#endif
    }
    
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        showNativeNavbarAfterPageLoad(error: error)
#if DEBUG
        configuration.onEvent?(["type": "webViewEvent", "payload": "didFail", "error": error.localizedDescription])
#endif
    }
    
    func webView(_ webView: WKWebView, didReceiveServerRedirectForProvisionalNavigation navigation: WKNavigation!) {
        showNativeNavbarAfterPageLoad()
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
            configuration.onExit?(messageType == .showClose)
        case .integrationSelected:
            configuration.onEvent?(messageBody)
            guard let payload = messageBody["payload"] as? [String: Any],
                  let nativeLink = payload["nativeLink"] as? String,
                  let url = URL(string: nativeLink),
                  !["http", "https"].contains(url.scheme ?? "") else { return }
            // Reports what this SDK will actually do, not what `canOpenURL` says.
            // Otherwise the web UI falls back to the universal link for every
            // scheme the integrator's Info.plist omits, which we now open fine.
            let canOpen = !Self.blockedSchemes.contains((url.scheme ?? "").lowercased())
            webView.evaluateJavaScript(Self.nativeLinkScript(url: url, canOpen: canOpen))
        case .loaded:
            configuration.onEvent?(messageBody)

            webView.evaluateJavaScript(Self.loadedScript(accessTokens: configuration.settings?.accessTokens))
        case .openTrueAuth:
                guard let link = messageBody["link"] as? String else { return }
                guard let atomicToken = messageBody["atomicToken"] as? String else { return }
                let resultHandler: (String)->() = { result in
                    self.webView.evaluateJavaScript(Self.trueAuthResultScript(result))
                }
                let trueAuthViewController = TrueAuthWebViewController(
                    configuration: TrueAuthConfiguration(url: link, atomicToken: atomicToken, resultHandler: resultHandler)
                )
                trueAuthViewController.modalPresentationStyle = .fullScreen
                present(trueAuthViewController, animated: true)
        case .none:
            configuration.onEvent?(messageBody)
        }
    }
    
    @objc(webView:createWebViewWithConfiguration:forNavigationAction:windowFeatures:)
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        // Read via KVC: WebKit can hand back no source frame despite the
        // non-optional Swift type, so it has to stay optional here.
        let sourceFrame = navigationAction.value(forKey: "sourceFrame") as? WKFrameInfo
        let url = navigationAction.request.url
        switch Self.popupAction(sourceIsMainFrame: sourceFrame?.isMainFrame, url: url) {
        case .loadInWebView:
            webView.load(navigationAction.request)
        case .openExternally:
            if let url = url {
                UIApplication.shared.open(url, options: [:], completionHandler: nil)
            }
        case .ignore:
            break
        }
        return nil
    }
}
