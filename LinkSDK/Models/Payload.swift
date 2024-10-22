//
//  Payload.swift
//  LinkSDK
//
//  Created by Mesh Connect, Inc
//

import Foundation

public enum LinkPayload {
    case accessToken(AccessTokenPayload)
    case delayedAuth(DelayedAuthPayload)
}

public struct AccessTokenPayload: Codable {
    public var id: String {
        let fullString = brokerType + (accountTokens.first?.account.accountId ?? "")
        return fullString.MD5
    }
    public var accountTokens: [AccountToken]
    public var brokerBrandInfo: BrandInfo
    public var expiresInSeconds: Int?
    public var refreshTokenExpiresInSeconds: Int?
    public var brokerType: String
    public var brokerName: String
    
    public func integrationAccessToken(accountToken: AccountToken) -> IntegrationAccessToken {
        IntegrationAccessToken(accountId: accountToken.account.accountId, accountName: accountToken.account.accountName, accessToken: accountToken.accessToken, brokerType: brokerType, brokerName: brokerName)
    }
}

public struct DelayedAuthPayload: Codable {
    public var refreshTokenExpiresInSeconds: Int?
    public var brokerType: String
    public var refreshToken: String
    public var brokerName: String
    public var brokerBrandInfo: BrandInfo
}

public struct AccountToken: Codable {
    public var account: Account
    public var accessToken: String
    public var refreshToken: String?
}

public struct Account: Codable {
    public var accountId: String
    public var accountName: String
    public var frontAccountId: String?
    public var fund: Double?
    public var cash: Double?
    public var isReconnected: Bool?
}

public struct BrandInfo: Codable {
    public var brokerLogo: String
    public var brokerPrimaryColor: String?
}

public enum TransferFinishedPayload {
    case success(TransferFinishedSuccessPayload)
    case error(TransferFinishedErrorPayload)
}

public struct TransferFinishedSuccessPayload: Codable {
    public var txId: String?
    public var fromAddress: String?
    public var toAddress: String?
    public var symbol: String
    public var amount: Double
    public var networkId: String?
}

public struct TransferFinishedErrorPayload: Codable {
    public var errorMessage: String
}

public struct IntegrationAccessToken: Codable {
    public var accountId: String
    public var accountName: String
    public var accessToken: String
    public var brokerType: String
    public var brokerName: String
}
