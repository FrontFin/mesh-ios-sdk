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

/// The URL Link opens, whether it opens dark, and the color around it.
struct LinkURL {
    let url: String
    let isDarkTheme: Bool
    let backgroundColor: UInt
}

/// Builds the Link URL in one pass, the same way as the other mobile SDKs: the params the app set
/// (`th`, `lng`, `fiatCur`, plus `platform`) replace any already in the token URL, and the rest of
/// the URL stays byte for byte. `th` is written when the app sets a theme (`system` is sent as
/// `system`, so Link decides), and, on a legacy link, when the device decides: then the resolved
/// theme is written, so Link and the native colors read the device the same way. Also returns the
/// theme and color Link opens with, see `resolveLinkAppearance`.
func buildLinkURL(linkUrl: String,
                  settings: LinkSettings?,
                  systemIsDark: Bool,
                  preferredLanguages: [String] = Locale.preferredLanguages) -> LinkURL {
    let query = QueryString(url: linkUrl)
    let appTheme = settings?.theme
    let appearance = resolveLinkAppearance(query: query, appTheme: appTheme, systemIsDark: systemIsDark)
    var params: [(name: String, value: String)] = []
    if let theme = appearance.themeToWrite ?? appTheme {
        params.append(("th", theme.rawValue))
    }
    if let language = resolveLanguage(settings?.language, preferredLanguages: preferredLanguages) {
        params.append(("lng", language))
    }
    if let currency = resolveCurrency(settings?.displayFiatCurrency) {
        params.append(("fiatCur", currency))
    }
    params.append(("platform", "iOS"))
    return LinkURL(url: query.replacing(params),
                   isDarkTheme: appearance.isDarkTheme,
                   backgroundColor: appearance.backgroundColor)
}

/// The theme Link opens in and the color around it.
struct LinkAppearance {
    let isDarkTheme: Bool
    let backgroundColor: UInt
    /// Set when a legacy link leaves the theme to the device, see `resolveLinkAppearance`.
    let themeToWrite: LinkTheme?
}

// The color around Link when the page has no valid color of its own, per Link version.
private let sessionColors = (dark: UInt(0x1C1C1C), light: UInt(0xF9F9F9))
private let legacyColors = (dark: UInt(0x0E0D0D), light: UInt(0xFBFBFB))

// Same shape Link accepts for a page color: #RGB, #RGBA, #RRGGBB or #RRGGBBAA.
private let hexColor = try! NSRegularExpression(pattern: "^#(?:[0-9a-fA-F]{3,4}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$")

/// The theme Link opens in and the color around it, read from the URL the way the page reads it,
/// so the status bar and background match with no visible seam. `appTheme` is the app's theme,
/// which replaces the `th` in the URL.
///
/// Theme, first one set wins:
/// 1. `th=light` or `th=dark` (the app's choice, or the one the token came with)
/// 2. the theme in the session token, for a link that has one
/// 3. `th=system` means the device on any link
/// 4. `link_style.th` (legacy links only), `system` meaning the device
/// 5. the device for a link with a session token, otherwise the default (dark, like link-v2)
///
/// Color: the page's own `bgd` (dark) or `bgl` (light) from the session token or `link_style`,
/// otherwise the fallback pair of that Link version (a link with a session token, or a legacy link).
///
/// `themeToWrite` is set for a legacy link whose theme comes from the device. The WebView can read
/// the device differently from the app, so the caller writes this resolved theme into the URL and
/// Link follows the same reading as the native colors.
func resolveLinkAppearance(query: QueryString, appTheme: LinkTheme?, systemIsDark: Bool) -> LinkAppearance {
    let sessionToken = readSessionToken(query)
    let linkStyle = sessionToken == nil ? decodeJsonParam(query.first("link_style")) : nil
    let urlTheme = appTheme?.rawValue ?? query.first("th")

    let choice = resolveChoice(urlTheme: urlTheme, sessionToken: sessionToken, linkStyle: linkStyle)
    let theme: LinkTheme
    switch choice {
    case .fixed(let fixed): theme = fixed
    case .device: theme = systemIsDark ? .dark : .light
    }
    let isDarkTheme = theme == .dark

    let colors = sessionToken != nil ? sessionColors : legacyColors
    let pageStyle = sessionToken ?? linkStyle
    return LinkAppearance(
        isDarkTheme: isDarkTheme,
        backgroundColor: opaqueColor(pageStyle?[isDarkTheme ? "bgd" : "bgl"]) ?? (isDarkTheme ? colors.dark : colors.light),
        themeToWrite: choice == .device && sessionToken == nil ? theme : nil)
}

private enum ThemeChoice: Equatable {
    case fixed(LinkTheme)
    case device
}

/// `light`, `dark` or the device, in the order described at `resolveLinkAppearance`.
private func resolveChoice(urlTheme: String?, sessionToken: [String: Any]?, linkStyle: [String: Any]?) -> ThemeChoice {
    if let theme = fixedTheme(urlTheme) { return .fixed(theme) }
    switch sessionToken?["th"] as? String {
    case "LINK_THEME_DARK": return .fixed(.dark)
    case "LINK_THEME_LIGHT": return .fixed(.light)
    default: break
    }
    if urlTheme == "system" { return .device }
    let styleTheme = linkStyle?["th"] as? String
    if let theme = fixedTheme(styleTheme) { return .fixed(theme) }
    if styleTheme == "system" { return .device }
    return sessionToken != nil ? .device : .fixed(.dark)
}

/// `light` and `dark` as they are, nil for anything else (`system` included).
private func fixedTheme(_ value: String?) -> LinkTheme? {
    switch value {
    case "light": return .light
    case "dark": return .dark
    default: return nil
    }
}

/// The session token's content (`token` param), checked the way Link checks it: a numeric `v` and
/// a non-empty string `c`. Nil for a legacy link, which has no such token. The token is not
/// signed, so nothing in it is trusted.
private func readSessionToken(_ query: QueryString) -> [String: Any]? {
    guard let token = decodeJsonParam(query.first("token")),
          let version = token["v"] as? NSNumber, CFGetTypeID(version) != CFBooleanGetTypeID(),
          let client = token["c"] as? String, !client.isEmpty else { return nil }
    return token
}

/// A param holding base64 JSON (`token`, `link_style`). URL decoding turns its '+' into a space,
/// so that's restored; the URL-safe alphabet and stripped padding are accepted too.
private func decodeJsonParam(_ value: String?) -> [String: Any]? {
    guard let value, !value.isEmpty else { return nil }
    return decodeUrlSafeBase64Json(encodedString: value.replacingOccurrences(of: " ", with: "+"))
}

/// An opaque `0xRRGGBB` from a valid hex color, alpha dropped; nil for anything else.
private func opaqueColor(_ value: Any?) -> UInt? {
    guard let value = value as? String,
          hexColor.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)) != nil else { return nil }
    let digits = value.dropFirst()
    let full = digits.count <= 4 ? digits.flatMap { [$0, $0] } : Array(digits)
    return UInt(String(full.prefix(6)), radix: 16)
}

/// Whether `rgb` (`0xRRGGBB`) is dark, so light status bar icons stay readable on it.
func isDarkColor(_ rgb: UInt) -> Bool {
    let red = Double((rgb >> 16) & 0xFF), green = Double((rgb >> 8) & 0xFF), blue = Double(rgb & 0xFF)
    return (0.299 * red + 0.587 * green + 0.114 * blue) / 255 < 0.5
}

/// A URL split into base, raw query pairs and fragment, so only the params we set change
/// and everything else keeps its exact bytes (URLComponents could re-encode them).
struct QueryString {
    let base: Substring
    let pairs: [Substring]
    let fragment: Substring

    // Letters, digits and -._~ are never encoded in a query.
    private static let unreserved = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    init(url: String) {
        let hash = url.firstIndex(of: "#") ?? url.endIndex
        let beforeFragment = url[..<hash]
        fragment = url[hash...]
        guard let queryStart = beforeFragment.firstIndex(of: "?") else {
            base = beforeFragment
            pairs = []
            return
        }
        base = beforeFragment[..<queryStart]
        // Empty parts are kept.
        pairs = beforeFragment[beforeFragment.index(after: queryStart)...]
            .split(separator: "&", omittingEmptySubsequences: false)
    }

    /// Value of the first `name` param (Link reads the first one), or nil when it's missing.
    func first(_ name: String) -> String? {
        for pair in pairs {
            let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            if Self.decode(parts[0]) == name {
                return parts.count > 1 ? Self.decode(parts[1]) : ""
            }
        }
        return nil
    }

    /// The URL with `params` replacing any existing values, added before the fragment.
    func replacing(_ params: [(name: String, value: String)]) -> String {
        let names = Set(params.map(\.name))
        let kept = pairs.filter { pair in
            !names.contains(Self.decode(pair.prefix { $0 != "=" }))
        }.map(String.init)
        let added = params.map { name, value in
            name + "=" + (value.addingPercentEncoding(withAllowedCharacters: Self.unreserved) ?? value)
        }
        return String(base) + "?" + (kept + added).joined(separator: "&") + fragment
    }

    private static func decode(_ value: Substring) -> String {
        let spaced = value.replacingOccurrences(of: "+", with: " ")
        // A malformed escape like %zz is kept as is.
        return spaced.removingPercentEncoding ?? spaced
    }
}

/// The app's language as a BCP-47 tag (e.g. en-US), with "system" read from the device
/// and falling back to "en"; nil when not set.
func resolveLanguage(_ language: String?, preferredLanguages: [String] = Locale.preferredLanguages) -> String? {
    guard let trimmed = language?.trimmingCharacters(in: .whitespaces), !trimmed.isEmpty else { return nil }
    guard trimmed == "system" else { return trimmed }
    guard let tag = preferredLanguages.first else { return "en" }
    return tag.replacingOccurrences(of: "_", with: "-")
        .replacingOccurrences(of: "-u-.*$", with: "", options: [.regularExpression, .caseInsensitive])
}

/// The app's display currency, or nil when it's not set.
func resolveCurrency(_ currency: String?) -> String? {
    guard let trimmed = currency?.trimmingCharacters(in: .whitespaces), !trimmed.isEmpty else { return nil }
    return trimmed
}

func decodeUrlSafeBase64Json(encodedString: String) -> [String: Any]? {
    guard let data = decodeUrlSafeBase64(encodedString: encodedString) else { return nil }
    return (try? JSONSerialization.jsonObject(with: data, options: [])) as? [String: Any]
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
