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

    init(url: String, resultHandler: @escaping (String) -> Void) {
        self.url = url
        self.resultHandler = resultHandler
    }
}

class TrueAuthWebViewController: UIViewController {

    private var quantum: Quantum
    private var configuration: TrueAuthConfiguration
    private var jsMessageHandler = "jsMessageHandler"

    private let webView: WKWebView = {
        let configuration = WKWebViewConfiguration()
        let contentController = WKUserContentController()
        let wkWebView = WKWebView(frame: .zero, configuration: configuration)
        
        wkWebView.contentMode = .scaleToFill
        wkWebView.configuration.userContentController = contentController
        wkWebView.translatesAutoresizingMaskIntoConstraints = false
        wkWebView.backgroundColor = UIColor(
            cgColor: CGColor(genericGrayGamma2_2Gray: 1, alpha: 1)
        )
        #if DEBUG
            if #available(iOS 16.4, *) {
                wkWebView.isInspectable = true
            }
        #endif
        return wkWebView
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
        setupQuantum()
    }

    private func setupWebView() {
        webView.configuration.userContentController.add(
            self,
            name: jsMessageHandler
        )
        view.addSubview(webView)
    }

    private func setupQuantum() {
        Task {
            do {
                try await quantum.initialize(
                    view: webView,
                    controller: self
                )
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
            let result = messageBody["result"] as? String
            result.map { configuration.resultHandler($0) }
            self.dismiss(animated: true)
        }
    }
}
