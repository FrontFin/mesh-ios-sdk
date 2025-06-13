//
//  TrueAuthWebViewController.swift
//  LinkSDK
//
//  Created by Mesh Connect, Inc
//

import QuantumIOS
import SafariServices
import UIKit
@preconcurrency import WebKit

internal class TrueAuthConfiguration {
    let url: String
    let resultHandler: (String) -> Void
    let userAgent: String?

    init(url: String,  userAgent: String, resultHandler: @escaping (String) -> Void) {
        self.url = url
        self.resultHandler = resultHandler
        self.userAgent = userAgent
    }
}

class TrueAuthWebViewController: UIViewController {

    private var quantum: Quantum
    private var configuration: TrueAuthConfiguration
    private var jsMessageHandler = "jsMessageHandler"

    private lazy var webView: WKWebView = {
        let configuration = WKWebViewConfiguration()
        let contentController = WKUserContentController()
        // ✅ Inject user agent before page load
        if let ua = self.configuration.userAgent {
                let escapedUserAgent = ua.replacingOccurrences(of: "'", with: "\\'")
                let script = "window.nativeUserAgent = '\(escapedUserAgent)';"
                let userScript = WKUserScript(source: script, injectionTime: .atDocumentStart, forMainFrameOnly: false)
                contentController.addUserScript(userScript)
            }
        
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.contentMode = .scaleToFill
        webView.configuration.userContentController = contentController
        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.backgroundColor = UIColor(
            cgColor: CGColor(genericGrayGamma2_2Gray: 1, alpha: 1)
        )
        if #available(iOS 16.4, *) {
            webView.isInspectable = true
        }
        
        return webView
    }()

    init(configuration: TrueAuthConfiguration) {
        self.quantum = Quantum()
        self.configuration = configuration
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        self.getNativeUserAgent { userAgent in
            guard let userAgent = userAgent else {
                print("❌ Could not retrieve native user agent")
                return
            }

            // Step 3: Inject user agent into JS context
            let escapedUserAgent = userAgent.replacingOccurrences(of: "'", with: "\\'")
            let script = "window.nativeUserAgent = '\(escapedUserAgent)';"
            DispatchQueue.main.async {
                self.webView.evaluateJavaScript(script)
                let userScript = WKUserScript(
                    source: script,
                    injectionTime: .atDocumentStart,
                    forMainFrameOnly: false
                )
                self.webView.configuration.userContentController.addUserScript(userScript)
            }
        }
    }

    override func viewDidLoad() {
        setupWebView()
    }

    private func setupWebView() {
        // attach js message handler
        webView.configuration.userContentController.add(
            self,
            name: jsMessageHandler
        )
        // add web view
        view.addSubview(webView)
        
        // clean session cookies before auth
        let cookieStore = WKWebsiteDataStore.default().httpCookieStore
        cookieStore.getAllCookies { cookies in
            for cookie in cookies {
                if cookie.isSessionOnly {
                    cookieStore.delete(cookie)
                }
            }
            // After cookie cleanup, fetch native User-Agent
            // Clean cookies
            let cookieStore = WKWebsiteDataStore.default().httpCookieStore
            cookieStore.getAllCookies { cookies in
                for cookie in cookies where cookie.isSessionOnly {
                    cookieStore.delete(cookie)
                }
                    // ✅ Now safe to initialize and load page
                    DispatchQueue.main.async {
                        self.setupQuantum()
                    }
                
            }
        }
    }
        
    private func getNativeUserAgent(completion: @escaping (String?) -> Void) {
        let config = URLSessionConfiguration.default
        config.httpAdditionalHeaders = nil
        let session = URLSession(configuration: config)

        var request = URLRequest(url: URL(string: "https://httpbin.org/headers")!)
        request.httpMethod = "GET"

        let task = session.dataTask(with: request) { data, _, error in
            guard let data = data, error == nil else {
                completion(nil)
                return
            }

            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let headers = json["headers"] as? [String: Any],
               let userAgent = headers["User-Agent"] as? String {
                completion(userAgent)
            } else {
                completion(nil)
            }
        }

        task.resume()
    }
    
    func traverseWindows() {
        for window in UIApplication.shared.windows {
            print("Window: \(window), Frame: \(window.frame)")
            let tempWindow = window.rootViewController?.view
            if let rootView = window.rootViewController?.view {
                traverseSubviews(of: rootView)
            }
        }

    }
    
    func traverseSubviews(of view: UIView) {
        print("View: \(view), Frame: \(view.frame)")
        for subView in view.subviews {
            traverseSubviews(of: subView)
        }

    }



    private func setupQuantum() {
        self.getNativeUserAgent { userAgent in
            guard let userAgent = userAgent else {
                print("❌ Could not retrieve native user agent")
                return
            }
            
            // Step 3: Inject user agent into JS context
            guard let urlEncoded = userAgent.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {return}
            Task {
                do {
                    try await self.quantum.initialize(view: self.webView, controller: self)
                    
                    _ = try await self.quantum.goto(url: self.configuration.url + urlEncoded)
                } catch {
                    print("❌ Failed to initialize Quantum: \(error)")
                }
            }
        }
        
    }

}

extension TrueAuthWebViewController: WKScriptMessageHandler {
    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard message.name == jsMessageHandler,
            let messageBody = message.body as? [String: Any],
            let type = messageBody["type"] as? String
        else {
            return
        }
        if type == "trueAuthResult" {
            if let result = messageBody["result"] as? String {
                configuration.resultHandler(result)
            }
            quantum.cleanup()
            self.dismiss(animated: true)
        }
    }
}
