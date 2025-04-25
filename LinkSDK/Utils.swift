//
//  Utils.swift
//  LinkSDK
//
//  Created by Mesh Connect, Inc
//

import Foundation
import UIKit

func UIColorFromRGB(rgbValue: UInt) -> UIColor {
    return UIColor(
        red: CGFloat((rgbValue & 0xFF0000) >> 16) / 255.0,
        green: CGFloat((rgbValue & 0x00FF00) >> 8) / 255.0,
        blue: CGFloat(rgbValue & 0x0000FF) / 255.0,
        alpha: CGFloat(1.0)
    )
}

func getThemeFromLinkUrl(linkUrl: String) -> String? {
    guard let encodedStyle = getQueryStringParameter(url: linkUrl, param: "link_style") else { return nil }
    
    guard let styleData = decodeUrlSafeBase64(encodedString: encodedStyle) else { return nil}
    
    do {
        if let jsonObject = try JSONSerialization.jsonObject(with: styleData, options: []) as? [String: Any] {
            if let thField = jsonObject["th"] as? String { return thField }
        }
    } catch { }
    
    return nil
}

func getQueryStringParameter(url: String, param: String) -> String? {
    guard let urlComponents = URLComponents(string: url),
          let param = urlComponents.queryItems?.first(where: { $0.name == param })?.value
    else { return nil }
    return param
}


func decodeUrlSafeBase64(encodedString: String) -> Data? {
    let adjustedLinkStyle = encodedString.replacingOccurrences(of: "-", with: "+")
                                     .replacingOccurrences(of: "_", with: "/")
                                     .padding(toLength: ((encodedString.count + 3) / 4) * 4, withPad: "=", startingAt: 0)

    guard let decodedData = Data(base64Encoded: adjustedLinkStyle) else { return nil }
    
    return decodedData
}

func localizedString(forKey key: String, locale: Locale, tableName: String? = nil) -> String {
    guard let languageCode = locale.languageCode else {
        return NSLocalizedString(key, comment: "")
    }
    
    // Try to find the path for the language bundle
    if let path = Bundle.main.path(forResource: languageCode, ofType: "lproj"),
       let bundle = Bundle(path: path) {
        return NSLocalizedString(key, tableName: tableName, bundle: bundle, value: "", comment: "")
    }
    
    // Fallback to the default localization
    return NSLocalizedString(key, comment: "")
}

import CryptoKit

extension String {
    var MD5: String {
        let digest = Insecure.MD5.hash(data: self.data(using: .utf8) ?? Data())
        return digest.map {
            String(format: "%02hhx", $0)
        }.joined()
    }
}
