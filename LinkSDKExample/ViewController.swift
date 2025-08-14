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
    
    override func viewDidLoad() {
        linkTokenTextField.delegate = self
        connectAccountButton.layer.borderColor = UIColor.black.cgColor
        connectAccountButton.layer.borderWidth = 1
        connectAccountButton.layer.cornerRadius = connectAccountButton.bounds.size.height * 0.5
        
        if let linkToken = UIPasteboard.general.string,
           let linkTokenData = Data(base64Encoded: linkToken),
           let catalogLink = String(data: linkTokenData, encoding: .utf8),
           let _ = URL(string: catalogLink) {
            linkTokenTextField.text = linkToken
            validateLinkToken(linkToken)
        }
    }
    
    @discardableResult func validateLinkToken(_ linkToken: String) -> Bool {
        let configuration = LinkConfiguration(linkToken: linkToken)
        guard configuration.isLinkTokenValid else {
            connectAccountButton.isEnabled = false
            return false
        }
        self.linkToken = linkToken
        connectAccountButton.isEnabled = true
        return true
    }
    
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        guard validateLinkToken(linkTokenTextField.text ?? "") else { return false }
        linkTokenTextField.resignFirstResponder()
        return true
    }
    
    @IBAction func editingChanged(_ sender: Any){
        linkToken = linkTokenTextField.text
        let configuration = LinkConfiguration(linkToken: linkToken ?? "")
        if !configuration.isLinkTokenValid {
            connectAccountButton.isEnabled = false
            return
        }
        connectAccountButton.isEnabled = true
        
    }
    
    @IBAction func connectAccountTapped(_ sender: Any) {
        guard let linkToken else {
            print("linkToken is not assigned")
            return
        }
        
        let settings = LinkSettings(language: "en-US")
        
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
        let onExit: ()->() = {
            print("Exit")
        }
        
        let configuration = LinkConfiguration(
            linkToken: linkToken,
            settings: settings,
            disableDomainWhiteList: true,
            onIntegrationConnected: onIntegrationConnected,
            onTransferFinished: onTransferFinished,
            onEvent: onEvent,
            onExit: onExit)
        let result = configuration.createHandler()
        switch result {
        case .failure(let error):
            self.statusLabel.text = error
        case .success(let handler):
            handler.present(in: self)
        @unknown default:
            print("unknown LinkResult value")
        }
        linkTokenTextField.text = nil
        connectAccountButton.isEnabled = false
        linkTokenTextField.resignFirstResponder()
    }

}
