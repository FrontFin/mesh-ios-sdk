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
    let atomicToken: String

    init(url: String, resultHandler: @escaping (String) -> Void) {
        self.url = url
        self.resultHandler = resultHandler
        self.atomicToken= atomicToken
    }
}

class TrueAuthWebViewController: UIViewController {

    private var quantum: Quantum
    private var configuration: TrueAuthConfiguration
    private var jsMessageHandler = "jsMessageHandler"
    private let webView: WKWebView = {
        let configuration = WKWebViewConfiguration()
        let contentController = WKUserContentController()
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
            // when done setup Quantum and open sign in page
            self.setupQuantum()
        }
    }


    private func setupQuantum() {
        Task {
            do {
                try await quantum.initialize(token: self.atomicToken,view: webView, controller: self)
                _ = try await quantum.goto(url: configuration.url)
            } catch {
                print("❌ Failed to initialize Quantum: \(error)")
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
