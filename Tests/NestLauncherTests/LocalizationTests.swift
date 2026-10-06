import XCTest
@testable import NestLauncher

final class LocalizationTests: XCTestCase {
    func testSystemLanguageResolution() {
        XCTAssertEqual(AppLanguage.system.resolvedCode(preferredLanguages: ["zh-Hant-TW", "en"]), "zh-Hans")
        XCTAssertEqual(AppLanguage.system.resolvedCode(preferredLanguages: ["en-US", "zh-Hans"]), "en")
        XCTAssertEqual(AppLanguage.system.resolvedCode(preferredLanguages: ["fr-FR"]), "en")
        XCTAssertEqual(AppLanguage.system.resolvedCode(preferredLanguages: []), "en")
        XCTAssertEqual(AppLanguage.english.resolvedCode(preferredLanguages: ["zh-Hans"]), "en")
        XCTAssertEqual(AppLanguage.chinese.resolvedCode(preferredLanguages: ["en"]), "zh-Hans")
    }

    @MainActor func testPreferencePersistenceAndInvalidValueFallback() async throws {
        let suite = "nest-language-tests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let notifications = NotificationCenter()
        let changed = expectation(description: "Language changes are announced")
        changed.expectedFulfillmentCount = 2
        let observer = notifications.addObserver(forName: .launcherLanguageChanged, object: nil, queue: nil) { _ in
            changed.fulfill()
        }
        defer { notifications.removeObserver(observer) }
        let manager = LanguageManager(defaults: defaults, notifications: notifications)
        XCTAssertEqual(manager.selection, .system)
        manager.selection = .english
        manager.selection = .english // No duplicate change notification.
        XCTAssertEqual(LanguageManager(defaults: defaults).selection, .english)
        manager.selection = .chinese
        XCTAssertEqual(LanguageManager(defaults: defaults).selection, .chinese)
        defaults.set("invalid", forKey: "appLanguage")
        XCTAssertEqual(LanguageManager(defaults: defaults).selection, .system)
        await fulfillment(of: [changed], timeout: 1)
    }

    func testTranslationAndUnknownKeyFallback() {
        XCTAssertEqual(L10n.translate("设置…", language: .english), "Settings…")
        XCTAssertEqual(L10n.translate("设置…", language: .chinese), "设置…")
        XCTAssertEqual(L10n.translate("my custom category", language: .english), "my custom category")
        XCTAssertEqual(L10n.translate("手动", language: .english), "Manual")
    }

    func testFormatArgumentsPreserveUserText() {
        let result = L10n.format("无法打开“%@”。应用可能已被移动、删除，或被系统阻止。请检查启动项路径。\n%@", language: .english, arguments: ["工具 100%", "/Applications/工具.app"])
        XCTAssertTrue(result.hasPrefix("Could not open"))
        XCTAssertTrue(result.contains("工具 100%"))
        XCTAssertTrue(result.hasSuffix("\n/Applications/工具.app"))
    }

    func testCatalogsHaveIdenticalKeysAndMatchingFormatArguments() throws {
        func catalog(_ code: String) throws -> [String: String] {
            let path = try XCTUnwrap(L10n.resources.path(forResource: code, ofType: "lproj"))
            let bundle = try XCTUnwrap(Bundle(path: path))
            let url = try XCTUnwrap(bundle.url(forResource: "Localizable", withExtension: "strings"))
            let plist = try PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil)
            return try XCTUnwrap(plist as? [String: String])
        }
        let chinese = try catalog("zh-Hans"), english = try catalog("en")
        XCTAssertGreaterThan(chinese.count, 100)
        XCTAssertEqual(Set(chinese.keys), Set(english.keys))
        for (key, value) in chinese {
            XCTAssertEqual(value, key)
            let translation = try XCTUnwrap(english[key])
            XCTAssertFalse(translation.isEmpty)
            XCTAssertEqual(key.components(separatedBy: "%@").count, translation.components(separatedBy: "%@").count, key)
            XCTAssertEqual(L10n.translate(key, language: .english), translation)
        }
    }
}
