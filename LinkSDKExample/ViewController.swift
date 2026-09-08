//
//  ViewController.swift
//  LinkSDKExample
//
//  Created by Mesh Connect, Inc
//

import UIKit
import LinkSDK
import SwiftUI

class ViewController: UIViewController, UITextFieldDelegate {
    @IBOutlet var linkTokenTextField: UITextField!
    @IBOutlet var connectAccountButton: UIButton!
    @IBOutlet var statusLabel: UILabel!

    var linkToken: String?

    /// Environment for the MFS-native path. A link token carries its own host,
    /// so this is read only when the field holds a bare session token.
    private lazy var environmentControl: UISegmentedControl = {
        let control = UISegmentedControl(items: ["Prod", "Sbx", "Dev"])
        control.selectedSegmentIndex = 0
        control.translatesAutoresizingMaskIntoConstraints = false
        control.addTarget(self, action: #selector(environmentChanged), for: .valueChanged)
        return control
    }()

    private var selectedEnvironment: MeshLinkEnvironment {
        switch environmentControl.selectedSegmentIndex {
        case 1: return .sbx
        case 2: return .dev
        default: return .prod
        }
    }

    override func viewDidLoad() {
        linkTokenTextField.delegate = self
        connectAccountButton.layer.borderColor = UIColor.black.cgColor
        connectAccountButton.layer.borderWidth = 1
        connectAccountButton.layer.cornerRadius = connectAccountButton.bounds.size.height * 0.5

        view.addSubview(environmentControl)
        NSLayoutConstraint.activate([
            environmentControl.centerXAnchor.constraint(equalTo: linkTokenTextField.centerXAnchor),
            environmentControl.widthAnchor.constraint(equalTo: linkTokenTextField.widthAnchor),
            environmentControl.bottomAnchor.constraint(equalTo: linkTokenTextField.topAnchor, constant: -16)
        ])

        if let pasted = UIPasteboard.general.string, !pasted.isEmpty {
            linkTokenTextField.text = pasted
            validateLinkToken(pasted)
        }
    }

    /// The field takes either kind of token. A link token is base64 of a URL and
    /// carries its own host; an MFS session token is a bare string that does
    /// not, so the picker supplies one. Detected by decoding rather than by
    /// prefix, so it does not depend on how MFS happens to name its tokens.
    private func resolvedLinkToken(from input: String) -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        if let data = Data(base64Encoded: trimmed),
           let decoded = String(data: data, encoding: .utf8),
           let url = URL(string: decoded),
           url.scheme != nil {
            return trimmed
        }
        return LinkConfiguration.linkToken(sessionToken: trimmed, environment: selectedEnvironment)
    }

    @discardableResult func validateLinkToken(_ input: String) -> Bool {
        let resolved = resolvedLinkToken(from: input)
        guard LinkConfiguration(linkToken: resolved).isLinkTokenValid else {
            self.linkToken = nil
            connectAccountButton.isEnabled = false
            return false
        }
        self.linkToken = resolved
        connectAccountButton.isEnabled = true
        return true
    }

    @objc private func environmentChanged() {
        // A session token already in the field resolves against the new host.
        validateLinkToken(linkTokenTextField.text ?? "")
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        guard validateLinkToken(linkTokenTextField.text ?? "") else { return false }
        linkTokenTextField.resignFirstResponder()
        return true
    }

    @IBAction func editingChanged(_ sender: Any){
        validateLinkToken(linkTokenTextField.text ?? "")
    }
    
    @IBAction func connectAccountTapped(_ sender: Any) {
        guard let linkToken else {
            print("linkToken is not assigned")
            return
        }
        
        let settings = LinkSettings(language: "en-US",          // optional, locale identifier
                                    displayFiatCurrency: "USD", // optional, preferred display fiat currency
                                    theme: .system)             // optional, preferred Link theme [light|dark|system]
        
        let onIntegrationConnected: (LinkPayload)->() = { linkPayload in
            var message: String
            switch linkPayload {
            case .accessToken(let accessTokenPayload):
                let accounts = accessTokenPayload.accountTokens.map() { $0.account.accountName }.joined(separator: "\n")
                let brokerName = accessTokenPayload.brokerName
                message = "Successfully connected \(brokerName) account(s):\n\(accounts)"
                print(accessTokenPayload)
            case .delayedAuth(let delayedAuthPayload):
                let brokerName = delayedAuthPayload.brokerName
                message = "Delayed authentication \(brokerName)"
                print(delayedAuthPayload)
            @unknown default:
                message = "unknown LinkPayload value"
            }
            self.statusLabel.text = message
        }
        var linkHandler: LinkHandler?
        let onTransferFinished: (TransferFinishedPayload)->() = { transferFinishedPayload in
            var message: String
            switch transferFinishedPayload {
            case .success(let successPayload):
                let amount = successPayload.amount
                let symbol = successPayload.symbol
                message = "Transfered \(amount) \(symbol)"
                let fromAddr = successPayload.fromAddress ?? ""
                if fromAddr.count != 0 {
                    message += " from \(fromAddr)"
                }
                let toAddr = successPayload.toAddress ?? ""
                if toAddr.count != 0 {
                    message += " to \(toAddr)"
                }
                let txId = successPayload.txId ?? ""
                if txId.count != 0 {
                    message += " txId \(txId)"
                }
            case .error(let errorPayload):
                message = errorPayload.errorMessage
            @unknown default:
                message = "unknown TransferFinishedPayload value"
            }
            self.statusLabel.text = message
            print(message)
        }
        let onEvent: ([String: Any]?)->() = { payload in
            print("Event: \(payload ?? [:])")
        }
        let onExit: (Bool?)->() = { showAlert in
            // showAlert is true when 'x' button is tapped
            // showAlert is false when 'Done' button is tapped on a Transfer Success screen
            if showAlert ?? false {
                // in case a custom alert is implemented, linkHandler?.closeLink() must be called to close Link
                linkHandler?.showExitAlert() // default Exit alert
            } else {
                linkHandler?.closeLink()
            }
        }
        
        let configuration = LinkConfiguration(
            linkToken: linkToken,
            settings: settings,
            disableDomainWhiteList: false,
            onIntegrationConnected: onIntegrationConnected,
            onTransferFinished: onTransferFinished,
            onEvent: onEvent,
            // onExit is optional, a default alert is shown in case onExit is omitted
            onExit: onExit)
        let result = configuration.createHandler()
        switch result {
        case .failure(let error):
            self.statusLabel.text = error
        case .success(let handler):
            linkHandler = handler
            handler.present(in: self)
        @unknown default:
            print("unknown LinkResult value")
        }
        linkTokenTextField.text = nil
        connectAccountButton.isEnabled = false
        linkTokenTextField.resignFirstResponder()
    }

}
