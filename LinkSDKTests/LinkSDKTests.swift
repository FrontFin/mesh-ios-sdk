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

    // MARK: - Payloads

    private func accessTokenPayload(brandInfo: String) throws -> AccessTokenPayload {
        let json = """
        {"accountTokens":[{"account":{"accountId":"conn-1","accountName":"MetaMask","frontAccountId":""},"accessToken":"conn-1","tokenId":"conn-1"}],
         "brokerBrandInfo":\(brandInfo),"brokerType":"metamask","brokerName":"MetaMask"}
        """
        return try JSONDecoder().decode(AccessTokenPayload.self, from: Data(json.utf8))
    }

    func testAccessTokenPayloadWithBrokerLogo() throws {
        let payload = try accessTokenPayload(brandInfo: ##"{"brokerLogo":"base64logo","brokerPrimaryColor":"#000"}"##)
        XCTAssertEqual(payload.brokerBrandInfo.brokerLogo, "base64logo")
        XCTAssertEqual(payload.brokerBrandInfo.brokerPrimaryColor, "#000")
    }

    func testAccessTokenPayloadFromMfsUsesBrokerLogoUrl() throws {
        let payload = try accessTokenPayload(brandInfo: #"{"brokerLogoUrl":"https://cdn/logo.svg","logoLightUrl":"https://cdn/logo.svg","logoDarkUrl":"https://cdn/dark.svg"}"#)
        XCTAssertEqual(payload.brokerBrandInfo.brokerLogo, "https://cdn/logo.svg")
        XCTAssertEqual(payload.accountTokens.first?.account.accountId, "conn-1")
        XCTAssertEqual(payload.brokerType, "metamask")
    }

    func testAccessTokenPayloadWithoutAnyLogo() throws {
        let payload = try accessTokenPayload(brandInfo: "{}")
        XCTAssertEqual(payload.brokerBrandInfo.brokerLogo, "")
        XCTAssertNil(payload.brokerBrandInfo.brokerPrimaryColor)
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

    // MARK: - Theme

    private func base64Url(_ json: String) -> String {
        Data(json.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private func mfsLink(theme: String?, extra: String = "") -> String {
        let th = theme.map { ",\"th\":\"\($0)\"" } ?? ""
        return "https://link.meshpay.com/?token=\(base64Url("{\"v\":1,\"c\":\"client\"\(th)}"))\(extra)"
    }

    func testFirstThParamWins() throws {
        // Silent migration puts th=dark first; the SDK's own th is appended after it.
        let link = mfsLink(theme: "LINK_THEME_LIGHT", extra: "&th=dark&th=light")
        XCTAssertTrue(isDarkLinkTheme(linkUrl: link, systemIsDark: false))
        XCTAssertFalse(isDarkLinkTheme(linkUrl: "https://web.meshconnect.com/?th=light&th=dark", systemIsDark: true))
    }

    func testInvalidThParamIsIgnored() throws {
        XCTAssertTrue(isDarkLinkTheme(linkUrl: mfsLink(theme: "LINK_THEME_DARK", extra: "&th=system"), systemIsDark: false))
    }

    func testLegacyLinkStyleTheme() throws {
        let style = { (th: String) in "https://web.meshconnect.com/?link_style=\(self.base64Url("{\"th\":\"\(th)\"}"))" }
        XCTAssertTrue(isDarkLinkTheme(linkUrl: style("dark"), systemIsDark: false))
        XCTAssertFalse(isDarkLinkTheme(linkUrl: style("light"), systemIsDark: true))
        XCTAssertTrue(isDarkLinkTheme(linkUrl: style("system"), systemIsDark: true))
        XCTAssertFalse(isDarkLinkTheme(linkUrl: style("system"), systemIsDark: false))
    }

    func testMfsTokenTheme() throws {
        XCTAssertTrue(isDarkLinkTheme(linkUrl: mfsLink(theme: "LINK_THEME_DARK"), systemIsDark: false))
        XCTAssertFalse(isDarkLinkTheme(linkUrl: mfsLink(theme: "LINK_THEME_LIGHT"), systemIsDark: true))
    }

    func testMfsTokenWithoutThemeFollowsDevice() throws {
        XCTAssertTrue(isDarkLinkTheme(linkUrl: mfsLink(theme: nil), systemIsDark: true))
        XCTAssertFalse(isDarkLinkTheme(linkUrl: mfsLink(theme: nil), systemIsDark: false))
        XCTAssertTrue(isDarkLinkTheme(linkUrl: mfsLink(theme: "LINK_THEME_UNSPECIFIED"), systemIsDark: true))
    }

    func testLegacyLinkWithoutThemeStaysLight() throws {
        XCTAssertFalse(isDarkLinkTheme(linkUrl: "https://web.meshconnect.com/b2b-iframe/abc/broker-connect", systemIsDark: true))
        // A token param that is not an MFS envelope is not treated as MFS.
        XCTAssertFalse(isDarkLinkTheme(linkUrl: "https://link.meshconnect.com/?token=\(base64Url("{\"a\":1}"))", systemIsDark: true))
        XCTAssertFalse(isDarkLinkTheme(linkUrl: "https://link.meshconnect.com/?token=not-base64", systemIsDark: true))
        XCTAssertFalse(isDarkLinkTheme(linkUrl: "https://link.meshpay.com/?token=\(base64Url("{\"v\":1,\"c\":\"\"}"))", systemIsDark: true))
    }

    private func catalogLink(for url: String, theme: LinkTheme? = nil, language: String? = nil) -> String? {
        let token = Data(url.utf8).base64EncodedString()
        let settings = LinkSettings(language: language, theme: theme)
        return LinkConfiguration(linkToken: token, settings: settings, onIntegrationConnected: { _ in }).catalogLink
    }

    func testAppThemeReplacesTokenTheme() throws {
        let url = mfsLink(theme: nil, extra: "&flow=%7B%22flow%22%3A%22login%22%7D&th=dark")
        let link = try XCTUnwrap(catalogLink(for: url, theme: .light))
        XCTAssertEqual(URLComponents(string: link)?.queryItems?.filter { $0.name == "th" }.map(\.value), ["light"])
        // Everything else in the token URL is kept byte for byte.
        XCTAssertTrue(link.hasPrefix(mfsLink(theme: nil, extra: "&flow=%7B%22flow%22%3A%22login%22%7D&")))
        XCTAssertFalse(isDarkLinkTheme(linkUrl: link, systemIsDark: true))
    }

    func testLegacyLinkUrlUnchanged() throws {
        // Legacy tokens carry the theme only inside link_style, so nothing is removed.
        let url = "https://link.meshconnect.com/?clientId=c&auth_code=a-b_c&link_style=\(base64Url("{\"th\":\"system\"}"))"
        XCTAssertEqual(catalogLink(for: url, theme: .dark), url + "&th=dark&platform=iOS")
        XCTAssertEqual(catalogLink(for: url, theme: nil), url + "&platform=iOS")
    }

    func testTokenThemeKeptWithoutAppTheme() throws {
        let url = mfsLink(theme: nil, extra: "&th=dark")
        let link = try XCTUnwrap(catalogLink(for: url, theme: nil))
        XCTAssertTrue(link.contains("th=dark"))
    }

    func testSystemLanguageResolvesToDeviceLanguage() throws {
        XCTAssertEqual(resolveLanguage("system", preferredLanguages: ["de-DE", "en-US"]), "de-DE")
        XCTAssertEqual(resolveLanguage("system", preferredLanguages: ["pt_BR"]), "pt-BR")
        XCTAssertEqual(resolveLanguage("system", preferredLanguages: ["th-TH-u-ca-buddhist"]), "th-TH")
        XCTAssertEqual(resolveLanguage("system", preferredLanguages: []), "en")
        XCTAssertEqual(resolveLanguage("es", preferredLanguages: ["de-DE"]), "es")
        XCTAssertNil(resolveLanguage(nil, preferredLanguages: ["de-DE"]))
    }

    func testSystemLanguageNeverReachesLink() throws {
        let link = try XCTUnwrap(catalogLink(for: "https://link.meshconnect.com/?clientId=c", language: "system"))
        XCTAssertFalse(link.contains("lng=system"))
        XCTAssertTrue(link.contains("lng="))
    }

    func testAddingQueryParamKeepsFragmentLast() throws {
        XCTAssertEqual(addingQueryParam(url: "https://a.com/?x=1#f", name: "th", value: "light"), "https://a.com/?x=1&th=light#f")
        XCTAssertEqual(addingQueryParam(url: "https://a.com/#f", name: "th", value: "light"), "https://a.com/?th=light#f")
        XCTAssertEqual(addingQueryParam(url: "https://a.com/", name: "th", value: "light"), "https://a.com/?th=light")
    }

    func testAppThemeReplacesTokenThemeBeforeFragment() throws {
        let link = try XCTUnwrap(catalogLink(for: "https://link.meshpay.com/?x=1&th=dark#f", theme: .light))
        XCTAssertEqual(link, "https://link.meshpay.com/?x=1&th=light&platform=iOS#f")
        XCTAssertFalse(isDarkLinkTheme(linkUrl: link, systemIsDark: true))
    }

    func testRemovingQueryParam() throws {
        XCTAssertEqual(removingQueryParam(url: "https://a.com/?th=dark", name: "th"), "https://a.com/")
        XCTAssertEqual(removingQueryParam(url: "https://a.com/?x=1&th=dark&thx=2&th=light#f", name: "th"), "https://a.com/?x=1&thx=2#f")
        XCTAssertEqual(removingQueryParam(url: "https://a.com/path", name: "th"), "https://a.com/path")
        XCTAssertEqual(removingQueryParam(url: "https://a.com/?%74h=dark&x=1", name: "th"), "https://a.com/?x=1")
        XCTAssertEqual(removingQueryParam(url: "https://a.com/#f?th=dark", name: "th"), "https://a.com/#f?th=dark")
    }

    func testDetectsMfsLinks() throws {
        XCTAssertTrue(isMfsLinkUrl(linkUrl: mfsLink(theme: nil, extra: "&th=dark")))
        XCTAssertFalse(isMfsLinkUrl(linkUrl: "https://web.meshconnect.com/b2b-iframe/abc/broker-connect?th=dark"))
        XCTAssertFalse(isMfsLinkUrl(linkUrl: "https://link.meshconnect.com/?token=\(base64Url("{\"a\":1}"))"))
    }

    func testLinkStyleBeatsMfsTokenTheme() throws {
        let link = mfsLink(theme: "LINK_THEME_DARK", extra: "&link_style=\(base64Url("{\"th\":\"light\"}"))")
        XCTAssertFalse(isDarkLinkTheme(linkUrl: link, systemIsDark: true))
    }

}
