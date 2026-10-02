import Foundation
import XCTest
import TwigaSwitcherCore
@testable import TwigaSwitcherApp

final class DefaultConfigurationTests: XCTestCase {
    func testApplicationConfigurationRejectsAmbiguousBundleIDs() {
        let json = #"""
        {
          "applications": [
            {"bundleID":"test.browser","name":"Browser","mode":"disabled"},
            {"bundleID":"test.browser","name":"Browser","mode":"compatibility"}
          ],
          "browserDiscovery":{"urlSchemes":["http","https"],"mode":"compatibility"}
        }
        """#
        XCTAssertThrowsError(try JSONDecoder().decode(ApplicationDefaultsConfiguration.self, from: Data(json.utf8)))
    }

    func testKeyboardConfigurationRejectsSourceSharedByBothLanguages() {
        let json = #"""
        {
          "english":{"inputSourceIDs":["custom.shared"],"primaryLanguage":"en"},
          "russian":{"inputSourceIDs":["custom.shared"],"primaryLanguage":"ru"}
        }
        """#
        XCTAssertThrowsError(try JSONDecoder().decode(KeyboardLayoutsConfiguration.self, from: Data(json.utf8)))
    }

    func testDiscoveredBrowsersAreDeduplicatedAndExplicitConfigurationWins() throws {
        let configuration = try applicationConfiguration()
        let rules = ApplicationRulesStore.makeBuiltIns(configuration: configuration, browsers: [
            .init(bundleID: "test.new-browser", name: "New Browser"),
            .init(bundleID: "test.configured-browser", name: "Discovered Name"),
            .init(bundleID: "test.new-browser", name: "New Browser"),
            .init(bundleID: "test.https-browser", name: "HTTPS Browser"),
        ])
        XCTAssertEqual(rules.count, 3)
        XCTAssertEqual(rules.first { $0.bundleID == "test.configured-browser" }?.mode, .disabled)
        XCTAssertEqual(rules.first { $0.bundleID == "test.configured-browser" }?.name, "Configured Browser")
        XCTAssertEqual(rules.first { $0.bundleID == "test.new-browser" }?.mode, .compatibility)
        XCTAssertEqual(rules.first { $0.bundleID == "test.https-browser" }?.mode, .compatibility)
    }

    func testBrowserUserOverrideSurvivesReloadAndDisappearanceFromDiscovery() throws {
        let suite = "BrowserConfiguration-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let builtIns = ApplicationRulesStore.makeBuiltIns(configuration: try applicationConfiguration(), browsers: [
            .init(bundleID: "test.browser", name: "Browser"),
        ])
        let store = ApplicationRulesStore(defaults: defaults, builtIns: builtIns)
        XCTAssertEqual(store.mode(for: "test.browser"), .compatibility)
        store.setMode(.disabled, for: "test.browser")
        let restored = ApplicationRulesStore(defaults: defaults, builtIns: builtIns)
        XCTAssertEqual(restored.mode(for: "test.browser"), .disabled)
        XCTAssertFalse(FocusSafetyPolicy(overrides: restored.overrides).allowsApplicationLevelFallback(bundleID: "test.browser"))
        let withoutBrowser = ApplicationRulesStore(defaults: defaults, builtIns: [])
        let rule = try XCTUnwrap(withoutBrowser.rules.first { $0.bundleID == "test.browser" })
        XCTAssertEqual(rule.mode, .disabled)
        XCTAssertFalse(rule.isBuiltIn)
        withoutBrowser.removeApplication(bundleID: rule.bundleID)
        XCTAssertEqual(withoutBrowser.mode(for: rule.bundleID), .standard)
    }

    func testConfiguredSourceOrderAndPreferredSelectionOverrideLanguageFallback() throws {
        let json = #"""
        {
          "english":{"inputSourceIDs":["custom.second","custom.first"],"primaryLanguage":"en"},
          "russian":{"inputSourceIDs":["custom.russian"],"primaryLanguage":"ru"}
        }
        """#
        let configuration = try JSONDecoder().decode(KeyboardLayoutsConfiguration.self, from: Data(json.utf8))
        let sources = [
            InputSourceDescriptor(id: "custom.fallback", languages: ["en-GB"]),
            .init(id: "custom.first", languages: []),
            .init(id: "custom.second", languages: []),
            .init(id: "custom.russian", languages: []),
        ]
        XCTAssertEqual(InputSourceResolver.resolve(.english, from: sources, configuration: configuration)?.id, "custom.second")
        XCTAssertEqual(InputSourceResolver.resolve(
            .english, from: sources, preferredID: "custom.first", configuration: configuration
        )?.id, "custom.first")
        XCTAssertEqual(InputSourceResolver.resolve(
            .english, from: sources, preferredID: "custom.russian", configuration: configuration
        )?.id, "custom.second")
        XCTAssertEqual(InputSourceResolver.resolve(.russian, from: sources, configuration: configuration)?.id, "custom.russian")
        XCTAssertEqual(InputSourceResolver.resolve(
            .english, from: [.init(id: "custom.fallback", languages: ["en_GB"])], configuration: configuration
        )?.id, "custom.fallback")
        XCTAssertNil(InputSourceResolver.language(
            of: .init(id: "custom.other", languages: ["bg", "en"]), configuration: configuration
        ))
    }

    private func applicationConfiguration() throws -> ApplicationDefaultsConfiguration {
        let json = #"""
        {
          "applications":[{"bundleID":"test.configured-browser","name":"Configured Browser","mode":"disabled"}],
          "browserDiscovery":{"urlSchemes":["http","https"],"mode":"compatibility"}
        }
        """#
        return try JSONDecoder().decode(ApplicationDefaultsConfiguration.self, from: Data(json.utf8))
    }
}
