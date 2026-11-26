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

    func testAccessTokenPayloadPrefersBrokerLogoOverUrl() throws {
        let payload = try accessTokenPayload(brandInfo: #"{"brokerLogo":"base64logo","brokerLogoUrl":"https://cdn/logo.svg"}"#)
        XCTAssertEqual(payload.brokerBrandInfo.brokerLogo, "base64logo")
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
            "https://applink.robinhood.com/u/connect?applicationId=x",
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

    // MARK: - Link URL and native theme

    private func base64Url(_ json: String) -> String {
        Data(json.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// A link with a session token, the way the latest Link gets it. `envelope` is the token's JSON.
    private func sessionLink(_ envelope: String = "{\"v\":1,\"c\":\"client\"}", extra: String = "") -> String {
        "https://link.meshpay.com/?token=\(base64Url(envelope))&flow=%7B%7D\(extra)"
    }

    private func sessionLink(field: String, extra: String = "") -> String {
        sessionLink("{\"v\":1,\"c\":\"client\",\(field)}", extra: extra)
    }

    /// A legacy link, with the client's style in link_style (standard base64, URL encoded).
    private func legacyLink(_ style: String? = nil, extra: String = "") -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        let param = style.map {
            "&link_style=" + Data($0.utf8).base64EncodedString().addingPercentEncoding(withAllowedCharacters: allowed)!
        } ?? ""
        return "https://link.meshconnect.com/?auth_code=x\(param)\(extra)"
    }

    private let sessionLight = "{\"v\":1,\"c\":\"client\",\"th\":\"LINK_THEME_LIGHT\"}"

    private func build(_ url: String,
                       theme: LinkTheme? = nil,
                       language: String? = nil,
                       fiatCurrency: String? = nil,
                       systemIsDark: Bool = false) -> LinkURL {
        let settings = LinkSettings(language: language, displayFiatCurrency: fiatCurrency, theme: theme)
        return buildLinkURL(linkUrl: url, settings: settings, systemIsDark: systemIsDark, preferredLanguages: ["de-DE"])
    }

    private func isDark(_ url: String, systemIsDark: Bool, appTheme: LinkTheme? = nil) -> Bool {
        resolveLinkAppearance(query: QueryString(url: url), appTheme: appTheme, systemIsDark: systemIsDark).isDarkTheme
    }

    private func background(_ url: String, systemIsDark: Bool = false) -> UInt {
        resolveLinkAppearance(query: QueryString(url: url), appTheme: nil, systemIsDark: systemIsDark).backgroundColor
    }

    private func themeToWrite(_ url: String, systemIsDark: Bool, appTheme: LinkTheme? = nil) -> LinkTheme? {
        resolveLinkAppearance(query: QueryString(url: url), appTheme: appTheme, systemIsDark: systemIsDark).themeToWrite
    }

    // MARK: buildLinkURL

    func testReplacesParamsAlreadyInTheTokenAndKeepsTheRest() throws {
        let base = sessionLink(sessionLight)
        let built = build("\(base)&th=dark&lng=fr&fiatCur=EUR&platform=web#f",
                          theme: .light, language: "de", fiatCurrency: "USD")
        XCTAssertEqual(built.url, "\(base)&th=light&lng=de&fiatCur=USD&platform=iOS#f")
        XCTAssertFalse(built.isDarkTheme)
    }

    func testTokenWithThTwiceEndsUpWithOne() throws {
        let url = build("\(sessionLink(sessionLight))&th=dark&th=dark", theme: .light).url
        XCTAssertEqual(url.components(separatedBy: "th=").count - 1, 1)
        XCTAssertTrue(url.contains("&th=light"))
    }

    func testWithoutAppThemeTheTokenThStaysAndDecidesTheNativeTheme() throws {
        let base = sessionLink(sessionLight)
        let session = build("\(base)&th=dark")
        XCTAssertEqual(session.url, "\(base)&th=dark&platform=iOS")
        XCTAssertTrue(session.isDarkTheme)
        XCTAssertEqual(session.backgroundColor, 0x1C1C1C)

        let legacy = build(legacyLink("{\"th\":\"light\"}"), systemIsDark: true)
        XCTAssertFalse(legacy.isDarkTheme)
        XCTAssertEqual(legacy.backgroundColor, 0xFBFBFB)
    }

    func testSystemIsSentAsSystemAndTheNativeThemeFollowsTheTokenThenTheDevice() throws {
        for systemIsDark in [true, false] {
            let built = build(sessionLink(sessionLight), theme: .system, systemIsDark: systemIsDark)
            XCTAssertTrue(built.url.contains("&th=system&"))
            // the token says light, so the device does not matter
            XCTAssertFalse(built.isDarkTheme)

            XCTAssertEqual(build(sessionLink(), theme: .system, systemIsDark: systemIsDark).isDarkTheme, systemIsDark)
            XCTAssertEqual(build(legacyLink("{\"th\":\"light\"}"), theme: .system, systemIsDark: systemIsDark).isDarkTheme,
                           systemIsDark)
        }
    }

    func testLegacyLinkWritesLightOrDarkWhenTheDeviceDecides() throws {
        let cases: [(String, LinkTheme?)] = [
            (legacyLink(), .system),
            (legacyLink("{\"th\":\"system\"}"), nil),
            (legacyLink(extra: "&th=system"), nil),
        ]
        for (link, theme) in cases {
            XCTAssertTrue(build(link, theme: theme, systemIsDark: true).isDarkTheme)
            XCTAssertTrue(build(link, theme: theme, systemIsDark: true).url.contains("&th=dark&"))
            XCTAssertTrue(build(link, theme: theme, systemIsDark: false).url.contains("&th=light&"))
        }
    }

    func testLegacyLinkDoesNotWriteAThemeTheDeviceDoesNotDecide() throws {
        let link = legacyLink()
        XCTAssertEqual(build(link, systemIsDark: true).url, link + "&platform=iOS")
        XCTAssertEqual(build("https://link.meshconnect.com/").url, "https://link.meshconnect.com/?platform=iOS")
    }

    func testSessionLinkKeepsSystemAsSystem() throws {
        XCTAssertTrue(build(sessionLink(sessionLight), theme: .system, systemIsDark: true).url.contains("&th=system&"))
        let link = sessionLink(sessionLight)
        XCTAssertEqual(build(link, systemIsDark: true).url, link + "&platform=iOS")
    }

    func testSystemReplacesTheThDarkTheBackendAddsOnSilentMigration() throws {
        let base = sessionLink(sessionLight)
        XCTAssertEqual(build("\(base)&th=dark", theme: .system, systemIsDark: true).url, "\(base)&th=system&platform=iOS")
    }

    func testPageColorFromTheToken() throws {
        let link = sessionLink(field: "\"bgl\":\"#112233\",\"bgd\":\"#445566\"")
        XCTAssertEqual(build(link, theme: .dark).backgroundColor, 0x445566)
        XCTAssertEqual(build(link, theme: .light, systemIsDark: true).backgroundColor, 0x112233)
    }

    func testOtherParamsKeptByteForByte() throws {
        let url = "https://link.meshpay.com/?flow=%7B%22flow%22%3A%22login%22%7D&&a=1+2&th=dark#f?th=x"
        XCTAssertEqual(build(url, theme: .light).url,
                       "https://link.meshpay.com/?flow=%7B%22flow%22%3A%22login%22%7D&&a=1+2&th=light&platform=iOS#f?th=x")
    }

    func testEncodedParamNamesAreReplacedToo() throws {
        XCTAssertEqual(build("https://a.com/?%74h=dark&x=1", theme: .light).url, "https://a.com/?x=1&th=light&platform=iOS")
    }

    func testNoQueryOrFragment() throws {
        XCTAssertEqual(build("https://a.com/path").url, "https://a.com/path?platform=iOS")
        XCTAssertEqual(build("https://a.com/#f", theme: .dark).url, "https://a.com/?th=dark&platform=iOS#f")
    }

    func testSystemLanguageIsSentAsTheFullDeviceTag() throws {
        XCTAssertTrue(build(sessionLink(), language: "system").url.contains("&lng=de-DE&"))
    }

    func testBlankLanguageAndCurrencyAreNotSent() throws {
        let link = sessionLink()
        XCTAssertEqual(build(link, language: " ", fiatCurrency: " ").url, link + "&platform=iOS")
    }

    func testValuesAreTrimmedAndEncoded() throws {
        XCTAssertTrue(build(sessionLink(), language: " pt-BR ", fiatCurrency: " EUR ").url.contains("&lng=pt-BR&fiatCur=EUR&"))
        XCTAssertEqual(build("https://a.com/", language: "en US&x=1").url, "https://a.com/?lng=en%20US%26x%3D1&platform=iOS")
    }

    func testAThemeTheSDKDoesNotKnowCannotBeSet() throws {
        XCTAssertNil(LinkTheme(rawValue: "blue"))
    }

    // MARK: Theme of a link with a session token

    func testSessionThInTheUrlWinsOverTheTokenTheme() throws {
        let dark = "\"th\":\"LINK_THEME_DARK\""
        XCTAssertFalse(isDark(sessionLink(field: dark, extra: "&th=light"), systemIsDark: true))
        XCTAssertTrue(isDark(sessionLink(field: "\"th\":\"LINK_THEME_LIGHT\"", extra: "&th=dark"), systemIsDark: false))
        // the app's theme replaces the th in the URL
        XCTAssertFalse(isDark(sessionLink(field: dark, extra: "&th=dark"), systemIsDark: true, appTheme: .light))
    }

    func testSessionThenTheTokenTheme() throws {
        XCTAssertTrue(isDark(sessionLink(field: "\"th\":\"LINK_THEME_DARK\""), systemIsDark: false))
        XCTAssertFalse(isDark(sessionLink(field: "\"th\":\"LINK_THEME_LIGHT\""), systemIsDark: true))
    }

    func testSessionTokenThemeWinsOverThSystem() throws {
        XCTAssertFalse(isDark(sessionLink(field: "\"th\":\"LINK_THEME_LIGHT\"", extra: "&th=system"), systemIsDark: true))
        XCTAssertTrue(isDark(sessionLink(field: "\"th\":\"LINK_THEME_DARK\"", extra: "&th=system"), systemIsDark: false))
    }

    func testSessionThenTheDevice() throws {
        for extra in ["", "&th=system", "&th=blue", "&th="] {
            XCTAssertTrue(isDark(sessionLink(extra: extra), systemIsDark: true))
            XCTAssertFalse(isDark(sessionLink(extra: extra), systemIsDark: false))
        }
    }

    func testSessionTokenThemeUnspecifiedOrUnknownFollowsTheDevice() throws {
        for th in ["\"LINK_THEME_UNSPECIFIED\"", "\"constructor\"", "7", "null"] {
            XCTAssertTrue(isDark(sessionLink(field: "\"th\":\(th)"), systemIsDark: true))
            XCTAssertFalse(isDark(sessionLink(field: "\"th\":\(th)"), systemIsDark: false))
        }
    }

    func testSessionLinkDoesNotReadLinkStyle() throws {
        let style = legacyLink("{\"th\":\"dark\"}").components(separatedBy: "&link_style=")[1]
        XCTAssertFalse(isDark(sessionLink(extra: "&link_style=\(style)"), systemIsDark: false))
    }

    func testATokenThatIsNotASessionTokenIsALegacyLink() throws {
        let notSession = [
            "{\"c\":\"client\",\"th\":\"LINK_THEME_DARK\"}",
            "{\"v\":\"1\",\"c\":\"client\",\"th\":\"LINK_THEME_DARK\"}",
            "{\"v\":true,\"c\":\"client\",\"th\":\"LINK_THEME_DARK\"}",
            "{\"v\":1,\"c\":\"\",\"th\":\"LINK_THEME_DARK\"}",
            "{\"v\":1,\"th\":\"LINK_THEME_DARK\"}",
        ]
        for envelope in notSession {
            // light device, so only a legacy link gives dark here
            XCTAssertTrue(isDark(sessionLink(envelope), systemIsDark: false), envelope)
            XCTAssertEqual(background(sessionLink(envelope)), 0x0E0D0D, envelope)
        }
        XCTAssertTrue(isDark("https://link.meshpay.com/?token=not-json", systemIsDark: false))
    }

    // MARK: Theme of a legacy link

    func testLegacyThInTheUrlWinsOverLinkStyle() throws {
        XCTAssertFalse(isDark(legacyLink("{\"th\":\"dark\"}", extra: "&th=light"), systemIsDark: true))
        XCTAssertTrue(isDark(legacyLink("{\"th\":\"light\"}", extra: "&th=dark"), systemIsDark: false))
    }

    func testLegacyThSystemMeansTheDeviceEvenWhenLinkStyleHasATheme() throws {
        XCTAssertFalse(isDark(legacyLink("{\"th\":\"dark\"}", extra: "&th=system"), systemIsDark: false))
        XCTAssertTrue(isDark(legacyLink("{\"th\":\"light\"}", extra: "&th=system"), systemIsDark: true))
    }

    func testLegacyThenLinkStyleTheme() throws {
        XCTAssertFalse(isDark(legacyLink("{\"th\":\"light\"}"), systemIsDark: true))
        XCTAssertTrue(isDark(legacyLink("{\"th\":\"dark\"}"), systemIsDark: false))
        XCTAssertFalse(isDark(legacyLink("{\"th\":\"light\"}", extra: "&th=blue"), systemIsDark: true))
        XCTAssertFalse(isDark(legacyLink("{\"th\":\"system\"}"), systemIsDark: false))
        XCTAssertTrue(isDark(legacyLink("{\"th\":\"system\"}"), systemIsDark: true))
    }

    func testLegacyLinkStyleWithPlusReadAsSpaceOrStrippedPadding() throws {
        // Standard base64 can carry '+', which URL decoding turns into a space.
        let encoded = Data("{\"th\":\"light\",\"x\":\"?>\"}".utf8).base64EncodedString()
        XCTAssertTrue(encoded.contains("+"))
        let url = { (value: String) in "https://link.meshconnect.com/?link_style=\(value)" }
        XCTAssertFalse(isDark(url(encoded.replacingOccurrences(of: "=", with: "")), systemIsDark: true))
        XCTAssertFalse(isDark(url(encoded.replacingOccurrences(of: "+", with: " ")), systemIsDark: true))
    }

    func testLegacyThenTheDefaultDarkEvenOnALightDevice() throws {
        XCTAssertTrue(isDark(legacyLink(), systemIsDark: false))
        XCTAssertTrue(isDark("https://link.meshconnect.com/", systemIsDark: false))
        for value in ["", "%%%", "bm90IGpzb24=", "e30=", "eyJ0aCI6IiJ9"] {
            XCTAssertTrue(isDark("https://link.meshconnect.com/?link_style=\(value)", systemIsDark: false), value)
        }
    }

    // MARK: Theme to write

    func testThemeToWriteIsTheDeviceThemeOnALegacyLinkTheDeviceDecides() throws {
        XCTAssertEqual(themeToWrite(legacyLink("{\"th\":\"system\"}"), systemIsDark: true), .dark)
        XCTAssertEqual(themeToWrite(legacyLink(), systemIsDark: true, appTheme: .system), .dark)
        XCTAssertEqual(themeToWrite(legacyLink(extra: "&th=system"), systemIsDark: false), .light)
    }

    func testThemeToWriteIsNilWhenTheDeviceDoesNotDecideOrTheLinkHasASessionToken() throws {
        XCTAssertNil(themeToWrite(legacyLink(), systemIsDark: true))
        XCTAssertNil(themeToWrite(legacyLink("{\"th\":\"light\"}"), systemIsDark: true))
        XCTAssertNil(themeToWrite(sessionLink(), systemIsDark: true))
        XCTAssertNil(themeToWrite(sessionLink(), systemIsDark: true, appTheme: .system))
    }

    // MARK: Background color

    func testBackgroundIsBgdOnDarkAndBglOnLightFromTheTokenAndLinkStyle() throws {
        let session = { (th: String) in self.sessionLink(field: "\"bgl\":\"#112233\",\"bgd\":\"#445566\"", extra: "&th=\(th)") }
        XCTAssertEqual(background(session("dark")), 0x445566)
        XCTAssertEqual(background(session("light"), systemIsDark: true), 0x112233)

        let legacy = { (th: String) in self.legacyLink("{\"bgl\":\"#112233\",\"bgd\":\"#445566\"}", extra: "&th=\(th)") }
        XCTAssertEqual(background(legacy("dark")), 0x445566)
        XCTAssertEqual(background(legacy("light"), systemIsDark: true), 0x112233)
    }

    func testShortHexIsExpandedAndAlphaDropped() throws {
        let color = { (bgd: String) in self.background(self.sessionLink(field: "\"bgd\":\"\(bgd)\"", extra: "&th=dark")) }
        XCTAssertEqual(color("#abc"), 0xAABBCC)
        XCTAssertEqual(color("#abcd"), 0xAABBCC)
        XCTAssertEqual(color("#11223344"), 0x112233)
        XCTAssertEqual(color("#ABCDEF"), 0xABCDEF)
    }

    func testMissingOrInvalidColorFallsBackForEachThemeOnItsOwn() throws {
        for bad in ["\"red\"", "\"rgb(1,2,3)\"", "\"#12\"", "\"#12345\"", "\"#ggg\"", "\"\"", "123", "null"] {
            XCTAssertEqual(background(sessionLink(field: "\"bgd\":\(bad)", extra: "&th=dark")), 0x1C1C1C, bad)
        }
        let onlyLight = sessionLink(field: "\"bgl\":\"#123456\"")
        XCTAssertEqual(background(onlyLight + "&th=dark"), 0x1C1C1C)
        XCTAssertEqual(background(onlyLight + "&th=light", systemIsDark: true), 0x123456)
    }

    func testFallbackPairOfTheLinkVersion() throws {
        XCTAssertEqual(background(sessionLink(extra: "&th=light")), 0xF9F9F9)
        XCTAssertEqual(background(legacyLink()), 0x0E0D0D)
        XCTAssertEqual(background(legacyLink("{\"th\":\"light\"}"), systemIsDark: true), 0xFBFBFB)
    }

    func testStatusBarIconsFollowTheBackgroundColor() throws {
        XCTAssertTrue(isDarkColor(0x1C1C1C))
        XCTAssertTrue(isDarkColor(0x0E0D0D))
        XCTAssertFalse(isDarkColor(0xF9F9F9))
        XCTAssertFalse(isDarkColor(0xFFFFFF))
        // a client's light page color on a dark theme
        XCTAssertFalse(isDarkColor(0xEEEEEE))
        XCTAssertTrue(isDarkColor(0x000000))
    }

    func testSystemLanguageResolvesToDeviceLanguage() throws {
        XCTAssertEqual(resolveLanguage("system", preferredLanguages: ["de-DE", "en-US"]), "de-DE")
        XCTAssertEqual(resolveLanguage("system", preferredLanguages: ["pt_BR"]), "pt-BR")
        XCTAssertEqual(resolveLanguage("system", preferredLanguages: ["th-TH-u-ca-buddhist"]), "th-TH")
        XCTAssertEqual(resolveLanguage(" system ", preferredLanguages: ["en-US"]), "en-US")
        XCTAssertEqual(resolveLanguage("system", preferredLanguages: []), "en")
        XCTAssertEqual(resolveLanguage("es", preferredLanguages: ["de-DE"]), "es")
        XCTAssertNil(resolveLanguage(nil, preferredLanguages: ["de-DE"]))
        XCTAssertNil(resolveLanguage("", preferredLanguages: ["de-DE"]))
    }

    func testCatalogLinkUsesBuildLinkURL() throws {
        let token = Data("https://link.meshpay.com/?th=dark".utf8).base64EncodedString()
        let configuration = LinkConfiguration(linkToken: token,
                                              settings: LinkSettings(theme: .light),
                                              onIntegrationConnected: { _ in })
        XCTAssertEqual(configuration.catalogLink, "https://link.meshpay.com/?th=light&platform=iOS")
    }

}
