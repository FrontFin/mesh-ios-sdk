//
//  LinkSDKTests.swift
//  LinkSDKTests
//
//  Created by Alexander on 11/23/23.
//

import XCTest
import JavaScriptCore
@testable import LinkSDK

extension UIApplication {
    public func canOpenURL(_ url: URL) -> Bool {
        return true
    }
}

final class LinkSDKTests: XCTestCase {

    override func setUpWithError() throws {
    }

    override func tearDownWithError() throws {
    }

    func testNoOnIntegrationConnected() throws {
        // test invalid configuration: no onIntegrationConnected passsed
        let configuration = LinkConfiguration(linkToken: "")
        let result = configuration.createHandler()
        switch result {
        case .failure(let error):
            XCTAssert(error == "Either 'onIntegrationConnected' or 'onTransferFinished' callback must be provided", "Wrong failure reason")
        case .success(_):
            XCTAssert(false, "Wrong result")
        }
    }
        
    func testInvalidAccessToken() throws {
        let invalidAccessToken = "==="
        let onIntegrationConnected: (LinkPayload)->() = {_ in }
        let configuration = LinkConfiguration(linkToken: invalidAccessToken, onIntegrationConnected: onIntegrationConnected)
        let result = configuration.createHandler()
        switch result {
        case .failure(let error):
            XCTAssert(error == "Invalid linkToken", "Wrong failure reason")
        case .success(_):
            XCTAssert(false, "Wrong result")
        }
    }
    
    func testValidLinkConfiguration() throws {
        let validAccessToken = "aHR0cHM6Ly93ZWIuZ2V0ZnJvbnQuY29tL2IyYi1pZnJhbWUvYjY5NDZhN2YtZGQyNC00ZjNlLTgwODktMDhkYWZkYzc5MmUzL2Jyb2tlci1jb25uZWN0P2F1dGhfY29kZT02MXE2ZllucmRJUWVFcVUtX1FscjhvRkxIR0hWSnVJVGRNLTUtRHZrSnhMeGxCa2ZqY0RWUWNsbnROLVN4SmdLdGh3SmVmTDdhbGVIb1V4ZjZOWDRwUQ=="
        let onIntegrationConnected: (LinkPayload)->() = {_ in }
        let configuration = LinkConfiguration(linkToken: validAccessToken, onIntegrationConnected: onIntegrationConnected)
        let result = configuration.createHandler()
        switch result {
        case .failure(_):
            XCTAssert(false, "Wrong result")
        case .success(_):
            break
        }
    }

    func testCatalogLinkContainsPlatformParam() throws {
        let validAccessToken = "aHR0cHM6Ly93ZWIuZ2V0ZnJvbnQuY29tL2IyYi1pZnJhbWUvYjY5NDZhN2YtZGQyNC00ZjNlLTgwODktMDhkYWZkYzc5MmUzL2Jyb2tlci1jb25uZWN0P2F1dGhfY29kZT02MXE2ZllucmRJUWVFcVUtX1FscjhvRkxIR0hWSnVJVGRNLTUtRHZrSnhMeGxCa2ZqY0RWUWNsbnROLVN4SmdLdGh3SmVmTDdhbGVIb1V4ZjZOWDRwUQ=="
        let onIntegrationConnected: (LinkPayload)->() = { _ in /* required by LinkConfiguration, not under test */ }
        let configuration = LinkConfiguration(linkToken: validAccessToken, onIntegrationConnected: onIntegrationConnected)
        guard let catalogLink = configuration.catalogLink else {
            XCTFail("catalogLink should not be nil for a valid token")
            return
        }
        XCTAssertTrue(catalogLink.contains("platform=iOS"), "catalogLink should contain platform=iOS param")
    }

    // MARK: - Injected scripts

    /// Runs `script` in a fresh JS context with `window` and an `alert` that
    /// records whether anything injected actually executed.
    private func evaluate(_ script: String) -> JSContext {
        let context = JSContext()!
        context.evaluateScript("var window = this; var executed = false; function alert() { executed = true; }")
        context.evaluateScript(script)
        XCTAssertNil(context.exception, "script threw: \(String(describing: context.exception))")
        XCTAssertFalse(context.objectForKeyedSubscript("executed").toBool(), "injected code executed")
        return context
    }

    private let hostileValues = [
        "';alert(1);'",
        "\";alert(1);\"",
        "`${alert(1)}`",
        "\\';alert(1);//",
        "line\nbreak\u{2028}\u{2029}</script>",
    ]

    func testLoadedScriptKeepsAccessTokensAsJsonString() throws {
        for value in hostileValues {
            let tokens = [IntegrationAccessToken(accountId: value, accountName: value, accessToken: value, brokerType: value, brokerName: value)]
            let context = evaluate(LinkWebViewViewController.loadedScript(accessTokens: tokens))
            let injected = context.objectForKeyedSubscript("accessTokens")
            XCTAssertTrue(injected?.isString ?? false, "window.accessTokens must stay a string")
            let decoded = try JSONDecoder().decode([IntegrationAccessToken].self, from: Data(injected!.toString().utf8))
            XCTAssertEqual(decoded.first?.accountName, value)
            XCTAssertEqual(decoded.first?.accessToken, value)
            XCTAssertEqual(context.objectForKeyedSubscript("meshSdkPlatform").toString(), "iOS")
        }
    }

    func testLoadedScriptWithoutAccessTokens() throws {
        let context = evaluate(LinkWebViewViewController.loadedScript(accessTokens: nil))
        XCTAssertTrue(context.objectForKeyedSubscript("accessTokens").isUndefined)
        XCTAssertEqual(context.objectForKeyedSubscript("meshSdkVersion").toString(), meshSDKVersion)
    }

    func testJsStringLiteralRoundTrips() throws {
        for value in hostileValues + ["", "plain", "émoji 🦖"] {
            let context = evaluate("window.value = \(jsStringLiteral(value));")
            XCTAssertEqual(context.objectForKeyedSubscript("value").toString(), value)
        }
    }

}
