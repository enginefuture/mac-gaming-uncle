import Foundation

public enum AppLanguage {
    public static let preferenceKey = "appLanguage"
    // Freeze the language for the process so background status messages and
    // in-flight Store responses cannot mix languages after a preference change.
    public static let identifier = resolve(UserDefaults.standard.string(forKey: preferenceKey), preferred: Locale.preferredLanguages)
    public static func resolve(_ selected: String?, preferred: [String]) -> String {
        if selected == "en" || selected == "zh-Hans" { return selected! }
        return preferred.first?.hasPrefix("zh") == true ? "zh-Hans" : "en"
    }
    public static var locale: Locale { Locale(identifier: identifier) }
    public static var steamLanguage: String { identifier == "zh-Hans" ? "schinese" : "english" }
    public static func date(_ value: Date, time: Bool = false) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateStyle = .medium
        formatter.timeStyle = time ? .short : .none
        return formatter.string(from: value)
    }
    private static let resources = PackagedResources.bundle(named: "MacGamingUncle_IndieCore", development: Bundle.module)
    public static func text(_ message: LocalizedMessage, language: String? = nil) -> String {
        let selected = language ?? identifier
        let bundle = resources?.path(forResource: selected, ofType: "lproj").flatMap(Bundle.init(path:))
        let translated = bundle?.localizedString(forKey: message.key, value: message.key, table: nil) ?? message.key
        let parts = translated.components(separatedBy: "%@")
        guard parts.count == message.arguments.count + 1 else { return translated }
        var result = parts[0]
        for (index, argument) in message.arguments.enumerated() { result += argument + parts[index + 1] }
        return result
    }
}

public struct LocalizedMessage: ExpressibleByStringLiteral, ExpressibleByStringInterpolation, Sendable {
    public let key: String
    public let arguments: [String]
    public init(stringLiteral value: String) { key = value; arguments = [] }
    public init(stringInterpolation value: StringInterpolation) { key = value.key; arguments = value.arguments }
    public struct StringInterpolation: StringInterpolationProtocol {
        var key = ""
        var arguments: [String] = []
        public init(literalCapacity: Int, interpolationCount: Int) { arguments.reserveCapacity(interpolationCount) }
        public mutating func appendLiteral(_ literal: String) { key += literal }
        public mutating func appendInterpolation<T>(_ value: T) { key += "%@"; arguments.append(String(describing: value)) }
    }
}

public func L(_ message: LocalizedMessage) -> String { AppLanguage.text(message) }
