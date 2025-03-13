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
    }
    
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        linkToken = linkTokenTextField.text
        let configuration = LinkConfiguration(linkToken: linkToken ?? "")
        guard configuration.isLinkTokenValid else {
            connectAccountButton.isEnabled = false
            return false
        }
        connectAccountButton.isEnabled = true
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
        
        var settings = LinkSettings()
        
        // Configure Quantum settings
        settings.quantumConfig = [
            "environment": "sandbox",  // Use "production" for production environment
            "theme": "system",        // Use "light" or "dark" for specific themes
            "debug": true             // Enable debug logging
        ]
        
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
            
            // Handle Quantum events
            if let type = payload?["type"] as? String,
               type == "quantumEvent",
               let quantumPayload = payload?["payload"] as? [String: Any] {
                
                // Handle different Quantum event types
                if let status = quantumPayload["status"] as? String {
                    switch status {
                    case "success":
                        self.statusLabel.text = "Quantum flow completed successfully"
                    case "error":
                        if let error = quantumPayload["error"] as? String {
                            self.statusLabel.text = "Quantum error: \(error)"
                        }
                    case "cancel":
                        self.statusLabel.text = "Quantum flow cancelled"
                    default:
                        self.statusLabel.text = "Quantum event: \(status)"
                    }
                }
            }
        }
        
        let onExit: ()->() = {
        }
        
        let configuration = LinkConfiguration(
            linkToken: linkToken,
            settings: settings,
            disableDomainWhiteList: false,
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
