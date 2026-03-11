//
//  Quantum.swift
//  LinkSDK
//
//  Created by Mesh Connect, Inc
//

// import QuantumIOS // disabled — placeholder below replaces this dependency
import UIKit
import WebKit

/// Placeholder that replaces QuantumIOS.Quantum.
/// Re-enable the real import above and remove this class to restore Quantum functionality.
class Quantum {
    func initialize(token: String, view: WKWebView, controller: UIViewController) async throws {
        // no-op placeholder
    }

    @discardableResult
    func goto(url: String) async throws -> Any? {
        // no-op placeholder — caller is responsible for loading the URL
        return nil
    }

    func cleanup() {
        // no-op placeholder
    }
}
