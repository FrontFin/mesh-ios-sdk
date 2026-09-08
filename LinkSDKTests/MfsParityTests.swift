//
//  MfsParityTests.swift
//  LinkSDKTests
//
//  Cross-SDK MFS parity suite.
//
//  The same numbered cases (P1.x, P2.x, ...) exist in every mobile SDK, so
//  "parity" is something that can be pointed at rather than asserted. Keep the
//  case ids and the fixtures below identical across repos; when one SDK's
//  behaviour has to differ, keep the case and document why in its body rather
//  than deleting it.
//
//  The contract being pinned:
//    P1  a link token is base64 of a URL, so the token alone decides which Link
//        loads. v1, v2 and MFS all arrive through this one path.
//    P2  the origin allowlist must accept both meshconnect and meshpay, and must
//        still reject lookalikes.
//    P3  Link v3 emits only four legacy events, one of which (`close`) carries
//        no payload at all.
//    P4  the v1/v2 payload shapes must keep working throughout the migration.
//

import XCTest
@testable import LinkSDK

final class MfsParityTests: XCTestCase {

    // MARK: - Shared fixtures. Keep byte-identical across SDKs.

    private let v1Url = "https://web.meshconnect.com/broker-connect/catalog"
    private let v2Url = "https://link.meshconnect.com/?clientId=abc&auth_code=xyz"
    private let mfsUrl = "https://link.meshpay.com/?token=ory_ac_abc123"

    private func tokenFor(_ url: String) -> String {
        Data(url.utf8).base64EncodedString()
    }

    private func catalogLink(for url: String) -> String? {
        let configuration = LinkConfiguration(
            linkToken: tokenFor(url),
            // Required by createHandler(), which rejects a configuration
            // with neither connection callback. Never invoked here.
            onIntegrationConnected: { _ in }
        )
        return configuration.catalogLink
    }

    /// Mirrors the host check in `decidePolicyFor`: a URL is kept in the WebView
    /// when it matches an entry by prefix or its host by suffix.
    private func isAllowlisted(_ urlString: String) -> Bool {
        guard let url = URL(string: urlString) else { return false }
        return whitelistedOrigins.contains {
            url.absoluteString.hasPrefix($0) || (url.host?.hasSuffix($0) ?? false)
        }
    }

    // MARK: - P1  token resolution: the token decides which Link loads

    func testP1_1_v1TokenResolvesToV1Host() throws {
        let link = try XCTUnwrap(catalogLink(for: v1Url))
        XCTAssertTrue(link.contains("web.meshconnect.com"))
    }

    func testP1_2_v2TokenResolvesToV2Host() throws {
        let link = try XCTUnwrap(catalogLink(for: v2Url))
        XCTAssertTrue(link.contains("link.meshconnect.com"))
    }

    func testP1_3_mfsTokenResolvesToMfsHostWithSessionTokenIntact() throws {
        let link = try XCTUnwrap(catalogLink(for: mfsUrl))
        XCTAssertTrue(link.contains("link.meshpay.com"))
        XCTAssertTrue(link.contains("token=ory_ac_abc123"))
    }

    func testP1_4_sdkParamsAppendedWithoutDroppingTokenParams() throws {
        let link = try XCTUnwrap(catalogLink(for: v2Url))
        XCTAssertTrue(link.contains("platform=iOS"))
        // The token's own params survive.
        XCTAssertTrue(link.contains("clientId=abc"))
        XCTAssertTrue(link.contains("auth_code=xyz"))
    }

    func testP1_5_malformedTokenDoesNotYieldALoadableURL() {
        let configuration = LinkConfiguration(
            linkToken: "===",
            // Required by createHandler(), which rejects a configuration
            // with neither connection callback. Never invoked here.
            onIntegrationConnected: { _ in }
        )
        XCTAssertNil(configuration.catalogLink)
        XCTAssertFalse(configuration.isLinkTokenValid)
    }

    // MARK: - P2  origin allowlist accepts both platforms

    func testP2_1_meshconnectHostsAreAllowed() {
        XCTAssertTrue(isAllowlisted("https://link.meshconnect.com"))
        XCTAssertTrue(isAllowlisted("https://web.meshconnect.com"))
    }

    func testP2_2_meshpayMfsHostsAreAllowed() {
        XCTAssertTrue(isAllowlisted("https://link.meshpay.com"))
        XCTAssertTrue(isAllowlisted("https://link.dev.meshpay.com"))
        XCTAssertTrue(isAllowlisted("https://api.meshpay.com"))
    }

    func testP2_3_lookalikeHostsAreRejected() {
        // iOS entries carry a leading dot (".meshpay.com") and are matched with
        // host.hasSuffix, so the dot boundary holds here. Flutter's wildcard
        // matcher has no such boundary; see its P2.5.
        XCTAssertFalse(isAllowlisted("https://evilmeshpay.com"))
        XCTAssertFalse(isAllowlisted("https://evilmeshconnect.com"))
        XCTAssertFalse(isAllowlisted("https://meshpay.com.evil.com"))
    }

    func testP2_4_unrelatedHostsAreRejected() {
        XCTAssertFalse(isAllowlisted("https://example.com"))
    }

    /// KNOWN GAP, pre-existing and unrelated to MFS. The explicit (non-dotted)
    /// entries are matched with `hasPrefix` and no boundary, so an
    /// attacker-registered host that merely begins with one of them passes.
    /// Documented rather than asserted as desired behaviour; the fix belongs in
    /// its own PR off main.
    ///
    /// Note iOS fails OPEN rather than closed: a non-allowlisted https URL is
    /// opened in Safari rather than blocked, so before `.meshpay.com` was added
    /// an MFS token would have launched Link outside the host app entirely.
    func testP2_5_allowlistBoundaryGapOnExplicitEntries_known() {
        XCTAssertTrue(isAllowlisted("https://robinhood.com.evil.com"))
    }

    // MARK: - P3  Link v3 emits only four legacy events

    func testP3_1_loadedIsRecognised() {
        XCTAssertEqual(JSMessageType(rawValue: "loaded"), .loaded)
    }

    func testP3_2_closeArrivesWithNoPayloadAndMustStillClose() {
        // v1/v2 always attach an event summary; v3 sends {"type":"close"} alone.
        // iOS keys on the type only, so this already held before MFS.
        XCTAssertEqual(JSMessageType(rawValue: "close"), .close)
    }

    func testP3_3_brokerageAccountAccessTokenCarriesTheConnectionId() throws {
        // Link v3: the connection-id architecture keeps real tokens server-side,
        // so accessToken/accountId/tokenId all carry the connectionId and there
        // is no refreshToken.
        let json = """
        {"accountTokens":[{"account":{"accountId":"conn_123","accountName":"Coinbase"},
        "accessToken":"conn_123","tokenId":"conn_123"}],
        "brokerBrandInfo":{"brokerLogo":"","brokerName":"Coinbase","brokerType":"coinbase"},
        "expiresInSeconds":0,"brokerType":"coinbase","brokerName":"Coinbase"}
        """
        let payload = try JSONDecoder().decode(
            AccessTokenPayload.self,
            from: Data(json.utf8)
        )
        let token = try XCTUnwrap(payload.accountTokens.first)
        // The contract change: this is a connection handle, not a token.
        XCTAssertEqual(token.accessToken, "conn_123")
        XCTAssertNil(token.refreshToken)
    }

    func testP3_4_transferFinishedParsesTheV3SuccessOnlyShape() throws {
        // v3 is success-only and v1-shaped: no previewId, fiatCurrency,
        // amountInUSD or smartFunding fields.
        let json = """
        {"status":"success","txId":"tx_1","transferId":"tx_1",
        "fromAddress":"0xfrom","toAddress":"0xto","symbol":"USDC",
        "amount":10.5,"networkId":"base","networkName":"base"}
        """
        let payload = try JSONDecoder().decode(
            TransferFinishedSuccessPayload.self,
            from: Data(json.utf8)
        )
        XCTAssertEqual(payload.txId, "tx_1")
        XCTAssertEqual(payload.symbol, "USDC")
    }

    // MARK: - P4  v1/v2 payloads keep working during the migration

    func testP4_2_legacyBrokerageAccountAccessTokenStillParses() throws {
        let json = """
        {"accountTokens":[{"account":{"accountId":"acc_1","accountName":"Coinbase"},
        "accessToken":"real-access-token","refreshToken":"real-refresh-token",
        "tokenId":"tok_1"}],
        "brokerBrandInfo":{"brokerLogo":"https://cdn/logo.png","brokerName":"Coinbase",
        "brokerType":"coinbase"},
        "expiresInSeconds":3600,"brokerType":"coinbase","brokerName":"Coinbase"}
        """
        let payload = try JSONDecoder().decode(
            AccessTokenPayload.self,
            from: Data(json.utf8)
        )
        let token = try XCTUnwrap(payload.accountTokens.first)
        XCTAssertEqual(token.accessToken, "real-access-token")
        XCTAssertEqual(token.refreshToken, "real-refresh-token")
    }

    func testP4_3_theV2TransferFinishedErrorBranchStillParses() throws {
        // v3 has no error variant, so this asserts the v2 path is untouched.
        let json = """
        {"status":"error","errorMessage":"insufficient funds"}
        """
        let payload = try JSONDecoder().decode(
            TransferFinishedErrorPayload.self,
            from: Data(json.utf8)
        )
        XCTAssertEqual(payload.errorMessage, "insufficient funds")
    }

    // MARK: - P5  the MFS-native session entry point
    //
    // Flutter and RN keep these in their own file (mesh_session_configuration_test,
    // sessionLinkToken.test). iOS keeps them here so a new test file does not have
    // to be registered in the Xcode project.

    private func decodedUrl(fromLinkToken token: String) throws -> String {
        let data = try XCTUnwrap(Data(base64Encoded: token))
        return try XCTUnwrap(String(data: data, encoding: .utf8))
    }

    func testP5_1_sessionTokenBecomesALinkTokenForTheChosenEnvironment() throws {
        let cases: [(MeshLinkEnvironment, String)] = [
            (.prod, "https://link.meshpay.com/?token=ory_ac_abc"),
            (.sbx, "https://link.sbx.meshpay.com/?token=ory_ac_abc"),
            (.dev, "https://link.dev.meshpay.com/?token=ory_ac_abc")
        ]
        for (environment, expected) in cases {
            let token = LinkConfiguration.linkToken(sessionToken: "ory_ac_abc", environment: environment)
            XCTAssertEqual(try decodedUrl(fromLinkToken: token), expected)
        }
    }

    func testP5_2_reservedCharactersAreEncodedRatherThanTruncatingTheUrl() throws {
        // Interpolating raw would cut the URL at `&` and lose the rest.
        let token = LinkConfiguration.linkToken(sessionToken: "abc&x=1#frag", environment: .prod)
        let url = try decodedUrl(fromLinkToken: token)
        XCTAssertEqual(url, "https://link.meshpay.com/?token=abc%26x%3D1%23frag")
        let parsed = try XCTUnwrap(URLComponents(string: url))
        let value = parsed.queryItems?.first { $0.name == "token" }?.value
        XCTAssertEqual(value, "abc&x=1#frag", "the token must survive a round trip intact")
    }

    func testP5_3_theSessionInitialiserProducesAUsableConfiguration() throws {
        let configuration = LinkConfiguration(
            sessionToken: "ory_ac_abc",
            environment: .prod,
            // Required by createHandler(), which rejects a configuration
            // with neither connection callback. Never invoked here.
            onIntegrationConnected: { _ in }
        )
        XCTAssertTrue(configuration.isLinkTokenValid)
        let link = try XCTUnwrap(configuration.catalogLink)
        XCTAssertTrue(link.hasPrefix("https://link.meshpay.com/?token=ory_ac_abc"))
    }

    func testP5_4_anEmptySessionTokenIsRejectedRatherThanOpeningLinkWithNoToken() {
        let configuration = LinkConfiguration(
            sessionToken: "",
            environment: .prod,
            // Required by createHandler(), which rejects a configuration
            // with neither connection callback. Never invoked here.
            onIntegrationConnected: { _ in }
        )
        XCTAssertFalse(configuration.isLinkTokenValid)
        if case .failure = configuration.createHandler() {} else {
            XCTFail("an empty session token must not produce a handler")
        }
    }

    // MARK: - P6  Link v3's OAuth redirect must leave the WebView

    func testP6_1_theChildSessionRedirectIsOpenedExternally() {
        for host in ["api.meshpay.com", "api.sbx.meshpay.com", "api.dev.meshpay.com"] {
            let url = URL(string: "https://\(host)/v2/sessions/s1/child-sessions/c1:redirect?code=x")!
            XCTAssertTrue(isMfsOAuthRedirect(url), "\(host) should open externally")
        }
    }

    func testP6_2_theRedirectHostIsStillAllowlistedForTheWebView() {
        // Both must hold: the host is trusted, and this one path leaves anyway.
        XCTAssertTrue(isAllowlisted("https://api.meshpay.com/v2/sessions"))
    }

    func testP6_3_lookalikePathsAndHostsAreNotTreatedAsTheRedirect() {
        let notRedirects = [
            "https://api.meshpay.com/v2/sessions/s1/child-sessions/c1:redirectevil",
            "https://api.meshpay.com/v2/sessions/s1/child-sessions",
            "https://api.meshpay.com/v2/sessions/s1",
            "https://apievil.meshpay.com/v2/sessions/s1/child-sessions/c1:redirect",
            "https://api.meshpay.com.evil.com/v2/sessions/s1/child-sessions/c1:redirect",
            "http://api.meshpay.com/v2/sessions/s1/child-sessions/c1:redirect"
        ]
        for urlString in notRedirects {
            let url = URL(string: urlString)!
            XCTAssertFalse(isMfsOAuthRedirect(url), "\(urlString) must not match")
        }
    }

    func testP6_4_ordinaryLinkNavigationIsUnaffected() {
        let url = URL(string: "https://link.meshpay.com/?token=ory_ac_abc")!
        XCTAssertFalse(isMfsOAuthRedirect(url))
    }
}
