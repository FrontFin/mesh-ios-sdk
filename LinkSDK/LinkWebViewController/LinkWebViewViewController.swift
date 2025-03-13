//
//  LinkWebViewViewController.swift
//  LinkSDK
//
//  Created by Mesh Connect, Inc
//

import UIKit
@preconcurrency import WebKit
import SafariServices
import QuantumIOS

let DARK_THEME_COLOR_TOP : UInt = 0x1E1E24
let LIGHT_THEME_COLOR_TOP : UInt = 0xF3F4F5
let DARK_THEME_COLOR_BOTTOM : UInt = 0x0E0D0D
let LIGHT_THEME_COLOR_BOTTOM : UInt = 0xFBFBFB

let allowedUrls = [
    "https://link.trustwallet.com",
    "https://appopener.meshconnect.com"
]

let whitelistedOrigins = [
    ".meshconnect.com",
    ".walletconnect.com",
    ".walletconnect.org",
    ".walletlink.org",
    ".coinbase.com",
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
    //Coinbase
    "https://api.cb-device-intelligence.com",
    //Okx
    "https://contentmx.okcoin.com",
    "https://www.recaptcha.net",
    //Revolut
    "https://ramp.revolut.codes",
    "https://sso.revolut.codes",
    "https://ramp.revolut.com"
]

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
}

public enum TransferFinishedStatus: String {
    case transferFinishedSuccess = "success"
    case transferFinishedError = "error"
}

public class LinkWebViewViewController: UIViewController {
    internal let webView: WKWebView = {
        let configuration = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.contentMode = .scaleToFill
        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.backgroundColor = UIColor(cgColor: CGColor(genericGrayGamma2_2Gray: 1, alpha: 1))
        #if DEBUG
        if #available(iOS 16.4, *) {
            webView.isInspectable = true
        }
        #endif
        return webView
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
    
    internal var quantum: Quantum?
    public var configuration: LinkConfiguration
    
    private var safariViewController: SFSafariViewController?
    
    private var showNativeNavBarDelayed = false
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

    public override func viewDidLoad() {
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
        setupQuantum()
    }
    
    public func setupWebView() {
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
    
    public override var preferredStatusBarStyle: UIStatusBarStyle {
        return isDarkTheme ? .lightContent : .darkContent
    }
    
    @objc func closeTapped() {
        configuration.onExit?()
    }
    
    @objc func backTapped() {
        webView.goBack()
    }
    
    public func setupQuantum() {
        // Initialize Quantum
        quantum = Quantum()
        
        // Initialize with webView and controller
        Task {
            do {
                try await quantum?.initialize(view: webView, controller: self)
                print("✅ Quantum initialized successfully")
                #if DEBUG
                if #available(iOS 16.4, *) {
                    webView.isInspectable = true
                }
                #endif
            } catch {
                print("❌ Failed to initialize Quantum: \(error)")
            }
        }
    }
}

public extension LinkWebViewViewController {
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
    
    public func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }

        // Check if the URL is in allowedUrls (only for http/https)
        if ["http", "https"].contains(url.scheme) {
            // if a url is in allowedUrls open it inSafari
            if allowedUrls.contains(where: { url.absoluteString.starts(with: $0) }) ||
                // or if domain whitelisting is not disable and url is not included in the list, open it inSafari
                (!(configuration.disableDomainWhiteList ?? false) &&
                 !whitelistedOrigins.contains(where: { url.absoluteString.hasPrefix($0) || url.host?.hasSuffix($0) ?? false })) {
                UIApplication.shared.open(url, options: [:], completionHandler: nil)
                decisionHandler(.cancel) // Cancel WebView navigation
                return
            }
        }

        // Handle custom schemes (e.g., wallet://)
        if !["http", "https"].contains(url.scheme) {
            // Open in external app if the scheme is supported
            if UIApplication.shared.canOpenURL(url) {
                UIApplication.shared.open(url, options: [:], completionHandler: nil)
                decisionHandler(.cancel) // Cancel WebView navigation
                return
            } else {
                print("Unsupported URL scheme: \(url.scheme ?? "unknown")")
            }
        }

        // Allow other http/https URLs to load in WebView
        decisionHandler(.allow)
    }
    
    public func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
#if DEBUG
        configuration.onEvent?(["type": "webViewEvent", "payload": "didStartProvisionalNavigation"])
#endif
    }
    
    public func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        showNativeNavbar(true)
#if DEBUG
        configuration.onEvent?(["type": "webViewEvent", "payload": "didFailProvisionalNavigation", "error": error.localizedDescription])
#endif
    }
    
    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        showNativeNavbar(true)
#if DEBUG
        configuration.onEvent?(["type": "webViewEvent", "payload": "didFinish"])
#endif
    }
    
    public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        showNativeNavbar(true)
#if DEBUG
        configuration.onEvent?(["type": "webViewEvent", "payload": "didFail", "error": error.localizedDescription])
#endif
    }
    
    public func webView(_ webView: WKWebView, didReceiveServerRedirectForProvisionalNavigation navigation: WKNavigation!) {
        showNativeNavbar(true)
#if DEBUG
        configuration.onEvent?(["type": "webViewEvent", "payload": "didReceiveServerRedirectForProvisionalNavigation"])
#endif
    }
}

extension LinkWebViewViewController: WKUIDelegate, WKScriptMessageHandler {

    public func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        print("🔍 WebView received message: \(message.body)")
        
        // Handle Quantum messages
        if message.name == "quantumHandler" {
            handleQuantumMessage(message)
            return
        }
        
        guard message.name == jsMessageHandler,
              let messageBody = message.body as? [String: Any],
              let type = messageBody["type"] as? String else {
            print("❌ Undefined message received: \(message.body)")
            configuration.onEvent?(["Undefined message": message.body])
            return
        }
        
        print("📝 Message type: \(type)")
        let messageType = JSMessageType(rawValue: type)
        switch messageType {
        case .showNativeNavbar:
            guard let show = messageBody["payload"] as? Bool else { return }
            print("🎯 Show native navbar: \(show)")
            showNativeNavbar(show)
        case .brokerageAccountAccessToken:
            print("🔑 Processing brokerage account access token")
            guard let payload = messageBody["payload"] as? [String: Any],
                  let jsonData = try? JSONSerialization.data(withJSONObject: payload),
                  let accessTokenPayload = try? JSONDecoder().decode(AccessTokenPayload.self, from: jsonData) else { 
                print("❌ Failed to process brokerage account access token")
                return 
            }
            print("✅ Successfully processed access token")
            configuration.onIntegrationConnected?(.accessToken(accessTokenPayload))
        case .delayedAuthentication:
            print("🕒 Processing delayed authentication")
            guard let payload = messageBody["payload"] as? [String: Any],
                  let jsonData = try? JSONSerialization.data(withJSONObject: payload),
                  let delayedAuthPayload = try? JSONDecoder().decode(DelayedAuthPayload.self, from: jsonData) else { 
                print("❌ Failed to process delayed authentication")
                return 
            }
            print("✅ Successfully processed delayed authentication")
            configuration.onIntegrationConnected?(.delayedAuth(delayedAuthPayload))
        case .transferFinished:
            print("💸 Transfer finished event received")
            configuration.onEvent?(messageBody)
            guard let payload = messageBody["payload"] as? [String: Any],
                  let status = TransferFinishedStatus(rawValue: payload["status"] as? String ?? "") else { 
                print("❌ Failed to process transfer finished status")
                return 
            }
            switch status {
            case .transferFinishedSuccess:
                print("✅ Transfer finished successfully")
                guard let payload = messageBody["payload"] as? [String: Any],
                      let jsonData = try? JSONSerialization.data(withJSONObject: payload),
                      let transferFinishedSuccessPayload = try? JSONDecoder().decode(TransferFinishedSuccessPayload.self, from: jsonData) else { 
                    print("❌ Failed to process transfer success payload")
                    return 
                }
                configuration.onTransferFinished?(.success(transferFinishedSuccessPayload))
            case .transferFinishedError:
                print("❌ Transfer finished with error")
                guard let payload = messageBody["payload"] as? [String: Any],
                      let jsonData = try? JSONSerialization.data(withJSONObject: payload),
                      let transferFinishedErrorPayload = try? JSONDecoder().decode(TransferFinishedErrorPayload.self, from: jsonData) else { 
                    print("❌ Failed to process transfer error payload")
                    return 
                }
                configuration.onTransferFinished?(.error(transferFinishedErrorPayload))
            }
        case .showClose, .close, .done:
            print("🚪 Exit event received: \(type)")
            configuration.onExit?()
        case .integrationSelected:
            print("🔗 Integration selected")
            guard let payload = messageBody["payload"] as? [String: Any] else {
                print("❌ Invalid payload for integration selection")
                return
            }
            
            // Check if this is KrakenDirect integration
            if let integrationName = payload["integrationName"] as? String,
               integrationName == "KrakenDirect" {
                print("🦑 KrakenDirect integration detected - triggering Quantum")
                
                // Create a new WebViewController for Quantum
                let quantumViewController = WebViewController()
                let quantumWebView = WebView.makeWebView()
                quantumViewController.webView = quantumWebView
                
                // Load the Quantum web app directly
                let quantumUrl = "http://localhost:3000" // Use your actual Quantum URL in production
                quantumWebView.load(URLRequest(url: URL(string: quantumUrl)!))
                
                #if DEBUG
                if #available(iOS 16.4, *) {
                    quantumWebView.isInspectable = true
                }
                #endif
                
                // Present the Quantum view controller
                quantumViewController.modalPresentationStyle = .fullScreen
                present(quantumViewController, animated: true) {
                    print("✅ Presented Quantum web view controller")
                }
                
                return
            }
            
            // Handle other integrations as before
            guard let nativeLink = payload["nativeLink"] as? String,
                  let url = URL(string: nativeLink),
                  !["http", "https"].contains(url.scheme ?? "") else { 
                print("❌ Invalid native link or HTTP/HTTPS scheme")
                return 
            }
            let canOpen = UIApplication.shared.canOpenURL(url)
            print("🔗 Native link can be opened: \(canOpen)")
            let js = "window.handleNativeLink = { url: '\(url.absoluteString)', canOpen: \(canOpen) };"
            webView.evaluateJavaScript(js)
        case .loaded:
            print("📱 WebView loaded")
            configuration.onEvent?(messageBody)

            var script = "window.meshSdkPlatform = 'iOS';"
            let bundle = Bundle(identifier: "com.meshconnect.LinkSDK")
            if let version = bundle?.infoDictionary?["CFBundleShortVersionString"] {
                script += "window.meshSdkVersion = '\(version)';"
                print("📦 SDK Version: \(version)")
            }
            
            if let accessTokens = configuration.settings?.accessTokens {
                if let data = try? JSONEncoder().encode(accessTokens),
                   let jsonString = String(data: data, encoding: String.Encoding.utf8) {
                    script += "window.accessTokens = '\(jsonString)';"
                    print("🔑 Access tokens configured")
                }
            }
            
            if let quantumConfig = configuration.settings?.quantumConfig {
                if let data = try? JSONSerialization.data(withJSONObject: quantumConfig),
                   let jsonString = String(data: data, encoding: .utf8) {
                    script += "window.quantumConfig = \(jsonString);"
                    print("🔮 Quantum configuration set")
                }
            }
            
            if let transferDestinationTokens = configuration.settings?.transferDestinationTokens {
                if let data = try? JSONEncoder().encode(transferDestinationTokens),
                   let jsonString = String(data: data, encoding: String.Encoding.utf8) {
                    script += "window.transferDestinationTokens = '\(jsonString)';"
                    print("🎯 Transfer destination tokens configured")
                }
            }
            
            webView.evaluateJavaScript(script)
        case .none:
            print("⚠️ Unhandled message type received")
            configuration.onEvent?(messageBody)
        }
    }
    
    @objc(webView:createWebViewWithConfiguration:forNavigationAction:windowFeatures:)
    public func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        guard !(navigationAction.targetFrame?.isMainFrame ?? false) else { return nil }
        webView.load(navigationAction.request)
        return nil
    }
    
    internal func handleQuantumMessage(_ message: WKScriptMessage) {
        guard let messageBody = message.body as? [String: Any],
              let type = messageBody["type"] as? String else {
            print("❌ Invalid Quantum message format")
            return
        }
        
        switch type {
        case "launchBrowser":
            guard let url = messageBody["url"] as? String,
                  let url = URL(string: url) else {
                print("❌ Invalid URL in launchBrowser message")
                return
            }
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
            
        case "authenticate":
            // Handle authentication if needed
            print("🔐 Quantum authentication requested")
            
        default:
            print("⚠️ Unhandled Quantum message type: \(type)")
        }
    }
}
