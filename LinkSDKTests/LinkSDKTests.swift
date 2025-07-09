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

    // MARK: - Version Retrieval Tests
    
    func testEmbeddedGitVersionExists() throws {
        // Test that getEmbeddedGitVersion() returns a valid version string
        let gitVersion = getEmbeddedGitVersion()
        XCTAssertNotNil(gitVersion, "Git version should be available")
        
        if let version = gitVersion {
            XCTAssertFalse(version.isEmpty, "Git version should not be empty")
            XCTAssertFalse(version == "unknown", "Git version should not be 'unknown' in normal circumstances")
            
            // Test that version follows semantic versioning pattern (e.g., "3.1.3")
            let versionRegex = try NSRegularExpression(pattern: "^\\d+\\.\\d+\\.\\d+", options: [])
            let range = NSRange(location: 0, length: version.utf16.count)
            let matches = versionRegex.matches(in: version, options: [], range: range)
            XCTAssertGreaterThan(matches.count, 0, "Version should follow semantic versioning pattern (x.y.z)")
        }
    }
    
    func testVersionConsistency() throws {
        // Test that getEmbeddedGitVersion() returns consistent results
        let version1 = getEmbeddedGitVersion()
        let version2 = getEmbeddedGitVersion()
        
        XCTAssertEqual(version1, version2, "Git version should be consistent across calls")
    }
    
    func testVersionInWebViewScript() throws {
        // Test that version gets properly included in the JavaScript
        let gitVersion = getEmbeddedGitVersion()
        XCTAssertNotNil(gitVersion, "Git version should be available for script injection")
        
        if let version = gitVersion {
            let expectedScript = "window.meshSdkVersion = '\(version)';"
            
            // Verify the script format is correct
            XCTAssertTrue(expectedScript.contains("window.meshSdkVersion"), "Script should set window.meshSdkVersion")
            XCTAssertTrue(expectedScript.contains(version), "Script should contain the actual version")
        }
    }
    
    func testVersionRetrievalMatchesImplementation() throws {
        // Test that the version retrieval matches the actual implementation in LinkWebViewViewController
        // Since we now use pure git version approach, this should always return git version
        let version = getEmbeddedGitVersion()
        
        XCTAssertNotNil(version, "Version should be available")
        
        if let actualVersion = version {
            XCTAssertFalse(actualVersion.isEmpty, "Version should not be empty")
            XCTAssertNotEqual(actualVersion, "1.0", "Should not return default bundle version")
            
            // Verify it matches the current git tag
            XCTAssertEqual(actualVersion, "3.1.3", "Should return the current git tag version")
        }
    }

}
