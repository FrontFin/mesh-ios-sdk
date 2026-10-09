//
//  LinkSDKTests.swift
//  LinkSDKTests
//
//  Created by Alexander on 11/23/23.
//

import XCTest
import WebKit
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
            XCTAssert(error == "Either 'onIntegrationConnected', 'onTransferFinished' or 'onEvent' callback must be provided", "Wrong failure reason")
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

    func testOnEventAloneCreatesHandler() throws {
        let configuration = LinkConfiguration(linkToken: validLinkToken, onEvent: { _ in })
        guard case .success = configuration.createHandler() else {
            XCTFail("onEvent alone should create a handler")
            return
        }
    }

    func testWithdrawalRequestedFromLinkReachesOnEventBeforeOnExit() throws {
        let received = expectation(description: "onEvent and onExit")
        received.expectedFulfillmentCount = 2
        var calls: [String] = []
        var event: [String: Any]?
        let configuration = LinkConfiguration(
            linkToken: validLinkToken,
            onEvent: { payload in
                event = payload
                calls.append("onEvent")
                received.fulfill()
            },
            onExit: { _ in
                calls.append("onExit")
                received.fulfill()
            })
        let controller = LinkWebViewViewController(configuration: configuration)
        let window = UIWindow(frame: UIScreen.main.bounds)
        let webView = WKWebView(frame: window.bounds)
        window.addSubview(webView)
        window.makeKeyAndVisible()
        webView.configuration.userContentController.add(controller, name: controller.jsMessageHandler)

        webView.loadHTMLString("""
            <script>
            const handler = window.webkit.messageHandlers.jsMessageHandler;
            handler.postMessage({ type: 'withdrawalRequested', payload: { transferId: 'transfer-1', status: 'pending' } });
            handler.postMessage({ type: 'close' });
            </script>
            """, baseURL: nil)

        wait(for: [received], timeout: 30)
        XCTAssertEqual(calls, ["onEvent", "onExit"])
        XCTAssertEqual(event?["type"] as? String, "withdrawalRequested")
        let payload = event?["payload"] as? [String: Any]
        XCTAssertEqual(payload?["transferId"] as? String, "transfer-1")
        XCTAssertEqual(payload?["status"] as? String, "pending")
    }

    func testWithdrawalRequestedWithUnknownStatusReachesOnEvent() throws {
        var event: [String: Any]?
        let configuration = LinkConfiguration(linkToken: validLinkToken, onEvent: { event = $0 })
        let controller = LinkWebViewViewController(configuration: configuration)

        controller.userContentController(WKUserContentController(), didReceive: FakeScriptMessage(
            name: controller.jsMessageHandler,
            body: ["type": "withdrawalRequested", "payload": ["transferId": "transfer-1", "status": "failed"]]))

        let payload = event?["payload"] as? [String: Any]
        XCTAssertEqual(event?["type"] as? String, "withdrawalRequested")
        XCTAssertEqual(payload?["status"] as? String, "failed")
    }

    func testTransferFinishedStillReachesOnEventAndOnTransferFinished() throws {
        var event: [String: Any]?
        var transferFinished: TransferFinishedPayload?
        let configuration = LinkConfiguration(
            linkToken: validLinkToken,
            onTransferFinished: { transferFinished = $0 },
            onEvent: { event = $0 })
        let controller = LinkWebViewViewController(configuration: configuration)

        controller.userContentController(WKUserContentController(), didReceive: FakeScriptMessage(
            name: controller.jsMessageHandler,
            body: ["type": "transferFinished", "payload": ["status": "success", "symbol": "ETH", "amount": 1.5]]))

        XCTAssertEqual(event?["type"] as? String, "transferFinished")
        guard case .success(let payload) = transferFinished else {
            XCTFail("onTransferFinished should receive a success payload")
            return
        }
        XCTAssertEqual(payload.symbol, "ETH")
    }

    private let validLinkToken = "aHR0cHM6Ly93ZWIuZ2V0ZnJvbnQuY29tL2IyYi1pZnJhbWUvYjY5NDZhN2YtZGQyNC00ZjNlLTgwODktMDhkYWZkYzc5MmUzL2Jyb2tlci1jb25uZWN0P2F1dGhfY29kZT02MXE2ZllucmRJUWVFcVUtX1FscjhvRkxIR0hWSnVJVGRNLTUtRHZrSnhMeGxCa2ZqY0RWUWNsbnROLVN4SmdLdGh3SmVmTDdhbGVIb1V4ZjZOWDRwUQ=="
}

private final class FakeScriptMessage: WKScriptMessage {
    private let fakeName: String
    private let fakeBody: Any

    init(name: String, body: Any) {
        fakeName = name
        fakeBody = body
        super.init()
    }

    override var name: String { fakeName }
    override var body: Any { fakeBody }
}
