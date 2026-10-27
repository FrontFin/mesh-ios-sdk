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

    func testTrueAuthResultScriptKeepsResultAsString() throws {
        for value in hostileValues + ["", "eyJzdGF0dXMiOiJvayJ9"] {
            let context = evaluate(LinkWebViewViewController.trueAuthResultScript(value))
            let injected = context.objectForKeyedSubscript("trueAuthResult")
            XCTAssertTrue(injected?.isString ?? false, "window.trueAuthResult must stay a string")
            XCTAssertEqual(injected?.toString(), value)
        }
    }

    func testNativeLinkScriptKeepsUrlAsString() throws {
        let links = [
            "wallet://open?x=';alert(1);'",
            "wallet://open?x=%27);alert(1);(%27",
            "wallet://a'+alert(1)+'",
            "metamask://dapp/link.meshconnect.com?a=1&b=2",
        ]
        for link in links {
            guard let url = URL(string: link) else { XCTFail("not a URL: \(link)"); continue }
            let context = evaluate(LinkWebViewViewController.nativeLinkScript(url: url, canOpen: true))
            let handle = context.objectForKeyedSubscript("handleNativeLink")
            XCTAssertEqual(handle?.objectForKeyedSubscript("url").toString(), url.absoluteString)
            XCTAssertTrue(handle?.objectForKeyedSubscript("canOpen").toBool() ?? false)
        }
    }

    // MARK: - Origin whitelist

    func testWhitelistAllowsKnownOrigins() throws {
        let allowed = [
            "https://robinhood.com/login",
            "https://ROBINHOOD.com",
            "https://js.stripe.com/v3/",
            "https://m.stripe.network/inner.html",
            "https://app.usercentrics.eu/session",
            "https://contentmx.okcoin.com/x",
            "https://www.recaptcha.net/recaptcha/api.js",
            "https://web.meshconnect.com/b2b-iframe",
            "https://pay.meshpay.com/",
            "https://applications.robinhood.com/x",
            "https://www.google.com/recaptcha",
        ]
        for link in allowed {
            XCTAssertTrue(isWhitelistedOrigin(URL(string: link)!), link)
        }
    }

    func testWhitelistRejectsLookalikeOrigins() throws {
        let rejected = [
            "https://robinhood.com.attacker.example/",
            "https://robinhood.com@attacker.example/",
            "https://js.stripe.com.attacker.example/",
            "https://www.recaptcha.net.attacker.example/",
            "https://evilrobinhood.com/",
            "https://evilmeshconnect.com/",
            "https://evilmeshpay.com/",
            "https://attacker.example/?u=https://robinhood.com",
            "http://robinhood.com/",
            "https://web3.okx.com/",
        ]
        for link in rejected {
            XCTAssertFalse(isWhitelistedOrigin(URL(string: link)!), link)
        }
    }

    // MARK: - Popups

    func testPopupFromMainFrameLoadsInWebView() throws {
        let links = ["https://web.meshconnect.com/oauth", "https://attacker.example/", "metamask://dapp"]
        for link in links {
            XCTAssertEqual(LinkWebViewViewController.popupAction(sourceIsMainFrame: true, url: URL(string: link)), .loadInWebView, link)
        }
    }

    func testPopupFromSubframeNeverLoadsInWebView() throws {
        let external = [
            "https://web.meshconnect.com/b2b-iframe",
            "https://www.google.com/recaptcha",
            "https://attacker.example/",
            "metamask://dapp",
        ]
        for link in external {
            XCTAssertEqual(LinkWebViewViewController.popupAction(sourceIsMainFrame: false, url: URL(string: link)), .openExternally, link)
        }

        let ignored = ["javascript:alert(1)", "data:text/html,hi", "file:///etc/hosts", "about:blank", "blob:https://x/y"]
        for link in ignored {
            XCTAssertEqual(LinkWebViewViewController.popupAction(sourceIsMainFrame: false, url: URL(string: link)), .ignore, link)
        }
        XCTAssertEqual(LinkWebViewViewController.popupAction(sourceIsMainFrame: false, url: nil), .ignore)
    }

    func testPopupFromUnknownSourceIsTreatedAsSubframe() throws {
        XCTAssertEqual(LinkWebViewViewController.popupAction(sourceIsMainFrame: nil, url: URL(string: "https://www.google.com/")), .openExternally)
        XCTAssertEqual(LinkWebViewViewController.popupAction(sourceIsMainFrame: nil, url: URL(string: "javascript:alert(1)")), .ignore)
    }

    // MARK: - Link OAuth redirect

    func testLinkOAuthRedirectMatchesEveryEnvironment() throws {
        for host in ["api.meshpay.com", "api.sbx.meshpay.com", "api.dev.meshpay.com", "API.MeshPay.com"] {
            let url = URL(string: "https://\(host)/v2/sessions/s1/child-sessions/c1:redirect?access_token=x&integrationId=i&sessionType=oauth")!
            XCTAssertTrue(isLinkOAuthRedirect(url), host)
        }
    }

    func testLinkOAuthRedirectHostStaysAllowlisted() throws {
        // Both hold: the host is trusted, and only this one path leaves the webview.
        XCTAssertTrue(isWhitelistedOrigin(URL(string: "https://api.meshpay.com/v2/sessions")!))
    }

    func testLinkOAuthRedirectRejectsLookalikes() throws {
        let rejected = [
            "https://api.meshpay.com/v2/sessions/s1/child-sessions/c1:redirectevil",
            "https://api.meshpay.com/v2/sessions/s1/child-sessions",
            "https://api.meshpay.com/v2/sessions/s1",
            "https://api.meshpay.com/v2/sessions/s1/child-sessions/c1/x:redirect",
            "https://api.meshpay.com/v2//sessions/s1/child-sessions/c1:redirect",
            "https://api.meshpay.com/v2/sessions//child-sessions/c1:redirect",
            "https://api.meshpay.com/v2/sessions/s1/child-sessions/:redirect",
            "https://apievil.meshpay.com/v2/sessions/s1/child-sessions/c1:redirect",
            "https://api.meshpay.com.evil.com/v2/sessions/s1/child-sessions/c1:redirect",
            "https://api.evilmeshpay.com/v2/sessions/s1/child-sessions/c1:redirect",
            "http://api.meshpay.com/v2/sessions/s1/child-sessions/c1:redirect",
            "https://link.meshpay.com/?token=abc",
        ]
        for link in rejected {
            XCTAssertFalse(isLinkOAuthRedirect(URL(string: link)!), link)
        }
    }

    // MARK: - Native navbar

    func testLinkSiteCoversLinkHostAndItsSiblings() throws {
        let cases: [(host: String, linkHost: String)] = [
            ("link.meshpay.com", "link.meshpay.com"),
            ("api.meshpay.com", "link.meshpay.com"),
            ("meshpay.com", "link.meshpay.com"),
            ("API.MeshPay.com", "link.meshpay.com"),
            ("api.dev.meshpay.com", "link.dev.meshpay.com"),
            ("integration-api.meshconnect.com", "link.meshconnect.com"),
            ("web.meshconnect.com", "link.meshconnect.com"),
            ("192.168.1.5", "192.168.1.5"),
            ("api.mesh.co.uk", "link.mesh.co.uk"),
            ("api.mesh.io", "link.mesh.io"),
        ]
        for (host, linkHost) in cases {
            XCTAssertTrue(LinkWebViewViewController.isLinkSite(host, linkHost: linkHost), "\(host) on \(linkHost)")
        }
    }

    func testLinkSiteExcludesOtherSites() throws {
        let cases: [(host: String?, linkHost: String?)] = [
            ("robinhood.com", "link.meshconnect.com"),
            ("exchange.gemini.com", "link.meshpay.com"),
            ("link.meshconnect.com", "link.meshpay.com"),
            ("evilmeshpay.com", "link.meshpay.com"),
            ("meshpay.com.attacker.example", "link.meshpay.com"),
            ("api.meshpay.com", "link.dev.meshpay.com"),
            ("api.other.com", "localhost"),
            ("10.168.1.5", "192.168.1.5"),
            ("hsbc.co.uk", "link.co.uk"),
            ("anything.com.au", "pay.com.au"),
            (nil, "link.meshpay.com"),
            ("link.meshpay.com", nil),
        ]
        for (host, linkHost) in cases {
            XCTAssertFalse(LinkWebViewViewController.isLinkSite(host, linkHost: linkHost), "\(host ?? "nil") on \(linkHost ?? "nil")")
        }
    }

    func testNativeNavbarStaysHiddenOnLinkSiteUnlessALoadReallyFails() throws {
        let hidden = LinkWebViewViewController.keepsNativeNavbarHidden
        let cancelled = NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled)
        let interrupted = NSError(domain: "WebKitErrorDomain", code: 102)
        let offline = NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet)

        XCTAssertTrue(hidden("link.meshpay.com", "link.meshpay.com", nil))
        XCTAssertTrue(hidden("api.meshpay.com", "link.meshpay.com", cancelled))
        XCTAssertTrue(hidden("link.meshpay.com", "link.meshpay.com", interrupted))
        XCTAssertFalse(hidden("link.meshpay.com", "link.meshpay.com", offline))
        XCTAssertFalse(hidden("robinhood.com", "link.meshconnect.com", nil))
        XCTAssertFalse(hidden("link.meshpay.com", nil, nil))
    }

    func testNativeNavbarComesBackOnRealFailureAfterRedirectsAndCommit() throws {
        let controller = LinkWebViewViewController(configuration: LinkConfiguration(linkToken: ""))
        controller.showNativeNavbar(true)
        controller.showNativeNavbar(true)
        controller.pageCommitted(host: "link.meshpay.com")
        XCTAssertTrue(controller.topBar.isHidden)

        controller.showNativeNavbarAfterPageLoad(error: NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet))
        XCTAssertFalse(controller.topBar.isHidden)
    }

}
