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
    return decodeUrlSafeBase64Json(encodedString: encodedStyle)?["th"] as? String
}

/// Whether Link will render dark, resolved the way the page does so the native
/// background matches it: the first `th` param wins, then legacy `link_style`,
/// then the MFS token's theme. An MFS token without a theme follows the device;
/// legacy links default to light.
func isDarkLinkTheme(linkUrl: String, systemIsDark: Bool) -> Bool {
    switch getQueryStringParameter(url: linkUrl, param: "th") {
    case "dark": return true
    case "light": return false
    default: break
    }

    switch getThemeFromLinkUrl(linkUrl: linkUrl) {
    case "dark": return true
    case "light": return false
    case "system": return systemIsDark
    default: break
    }

    guard let envelope = mfsTokenEnvelope(linkUrl: linkUrl) else { return false }

    switch envelope["th"] as? String {
    case "LINK_THEME_DARK": return true
    case "LINK_THEME_LIGHT": return false
    default: return systemIsDark
    }
}

func isMfsLinkUrl(linkUrl: String) -> Bool {
    mfsTokenEnvelope(linkUrl: linkUrl) != nil
}

/// The decoded MFS `token` param, validated the way MFS Link does; nil for legacy links.
private func mfsTokenEnvelope(linkUrl: String) -> [String: Any]? {
    guard let encodedToken = getQueryStringParameter(url: linkUrl, param: "token"),
          let envelope = decodeUrlSafeBase64Json(encodedString: encodedToken),
          envelope["v"] is NSNumber,
          let clientId = envelope["c"] as? String, !clientId.isEmpty else { return nil }
    return envelope
}

func decodeUrlSafeBase64Json(encodedString: String) -> [String: Any]? {
    guard let data = decodeUrlSafeBase64(encodedString: encodedString) else { return nil }
    return (try? JSONSerialization.jsonObject(with: data, options: [])) as? [String: Any]
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
            
    var path = Bundle.main.path(forResource: languageCode, ofType: "lproj", inDirectory: "LinkSDK_LinkSDK.bundle")
    if path == nil {
        path = Bundle.main.path(forResource: "en", ofType: "lproj", inDirectory: "LinkSDK_LinkSDK.bundle")
    }
    if path == nil {
        path = Bundle.main.path(forResource: "en", ofType: "lproj", inDirectory: "Frameworks/LinkSDK.framework")
    }
    if let path, let langBundle = Bundle(path: path) {
        return NSLocalizedString(key, tableName: tableName, bundle: langBundle, value: "", comment: "")
    }

    let bundle = Bundle(for: LinkConfiguration.self)
    return NSLocalizedString(key, bundle: bundle, comment: "")
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

/// Encodes `value` as a JavaScript string literal (quotes included) so a script
/// can carry it as data. Nothing in `value` can end the literal or run as code.
func jsStringLiteral(_ value: String) -> String {
    // Encoded as a one-element array, then the brackets are stripped.
    guard let data = try? JSONSerialization.data(withJSONObject: [value]),
          let json = String(data: data, encoding: .utf8) else { return "\"\"" }
    // Older JS engines treat U+2028/U+2029 as line breaks inside literals.
    return String(json.dropFirst().dropLast())
        .replacingOccurrences(of: "\u{2028}", with: "\\u2028")
        .replacingOccurrences(of: "\u{2029}", with: "\\u2029")
}
