import Foundation
import Combine

enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case chinese = "zh-Hans"
    case english = "en"

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .system: return L10n.tr("跟随系统")
        case .chinese: return "简体中文"
        case .english: return "English"
        }
    }

    func resolvedCode(preferredLanguages: [String] = Locale.preferredLanguages) -> String {
        guard self == .system else { return rawValue }
        return preferredLanguages.first?.hasPrefix("zh") == true ? "zh-Hans" : "en"
    }
}

extension Notification.Name {
    static let launcherLanguageChanged = Notification.Name("launcherLanguageChanged")
}

@MainActor
final class LanguageManager: ObservableObject {
    static let shared = LanguageManager()
    private let defaults: UserDefaults
    private let notifications: NotificationCenter
    @Published var selection: AppLanguage {
        didSet {
            guard selection != oldValue else { return }
            defaults.set(selection.rawValue, forKey: "appLanguage")
            notifications.post(name: .launcherLanguageChanged, object: nil)
        }
    }

    var locale: Locale { Locale(identifier: selection.resolvedCode()) }

    init(defaults: UserDefaults = .standard, notifications: NotificationCenter = .default) {
        self.defaults = defaults
        self.notifications = notifications
        selection = AppLanguage(rawValue: defaults.string(forKey: "appLanguage") ?? "system") ?? .system
    }
}

enum L10n {
    // Explicit language bundles support live switching without changing AppleLanguages.
    static let resources: Bundle = {
        if let url = Bundle.main.url(forResource: "NestLauncher_NestLauncher", withExtension: "bundle"),
           let bundle = Bundle(url: url) { return bundle }
        return Bundle.module
    }()
    private static let bundles: [String: Bundle] = {
        var result: [String: Bundle] = [:]
        for code in ["zh-Hans", "en"] {
            if let path = resources.path(forResource: code, ofType: "lproj"),
               let bundle = Bundle(path: path) { result[code] = bundle }
        }
        return result
    }()

    static func translate(_ key: String, language: AppLanguage) -> String {
        bundles[language.resolvedCode()]?.localizedString(forKey: key, value: key, table: nil) ?? key
    }

    static func tr(_ key: String, _ arguments: CVarArg...) -> String {
        let language = AppLanguage(rawValue: UserDefaults.standard.string(forKey: "appLanguage") ?? "system") ?? .system
        return format(key, language: language, arguments: arguments)
    }

    static func format(_ key: String, language: AppLanguage, arguments: [CVarArg]) -> String {
        let value = translate(key, language: language)
        guard !arguments.isEmpty else { return value }
        return String(format: value, locale: Locale(identifier: language.resolvedCode()), arguments: arguments)
    }
}
