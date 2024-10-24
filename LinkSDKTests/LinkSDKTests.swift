//
//  LinkSDKTests.swift
//  LinkSDKTests
//
//  Created by Alexander on 11/23/23.
//

import XCTest
import LinkSDK

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

}
