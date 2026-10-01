import XCTest
import TwigaSwitcherCore
@testable import TwigaSwitcherApp

final class SystemPolicyTests: XCTestCase {
    func testApplicationModesOverrideBuiltInRulesButNeverPermitSecureFields() {
        let policy = FocusSafetyPolicy(overrides: [
            "com.apple.Terminal": .standard,
            "com.openai.codex": .disabled,
            "com.example.Editor": .compatibility,
        ])
        XCTAssertTrue(policy.isSafe(.init(bundleID: "com.apple.Terminal", role: "AXTextArea", subrole: nil, valueIsSettable: true)))
        XCTAssertFalse(policy.isSafe(.init(bundleID: "com.openai.codex", role: "AXTextArea", subrole: nil, valueIsSettable: true)))
        XCTAssertTrue(policy.isSafe(.init(bundleID: "com.example.Editor", role: "AXGroup", subrole: nil, valueIsSettable: true)))
        XCTAssertTrue(policy.allowsApplicationLevelFallback(bundleID: "com.example.Editor"))
        XCTAssertFalse(policy.isSafe(.init(bundleID: "com.example.Editor", role: "AXTextField", subrole: "AXSecureTextField", valueIsSettable: true)))
    }

    func testApplicationSettingsPersistChangesAndKeepBuiltInRulesVisible() throws {
        let suite = "ApplicationRules-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = ApplicationRulesStore(defaults: defaults)
        XCTAssertEqual(store.mode(for: "com.apple.Terminal"), .disabled)
        XCTAssertEqual(store.mode(for: "us.zoom.xos"), .compatibility)
        store.setMode(.standard, for: "com.apple.Terminal")
        store.addApplication(bundleID: "com.example.Editor", name: "Editor")
        store.setMode(.disabled, for: "com.example.Editor")
        let restored = ApplicationRulesStore(defaults: defaults)
        XCTAssertEqual(restored.mode(for: "com.apple.Terminal"), .standard)
        XCTAssertEqual(restored.mode(for: "com.example.Editor"), .disabled)
        XCTAssertTrue(restored.rules.contains { $0.bundleID == "com.example.Editor" && $0.name == "Editor" })
        restored.removeApplication(bundleID: "com.example.Editor")
        XCTAssertFalse(restored.rules.contains { $0.bundleID == "com.example.Editor" })
    }

    func testFocusPolicyFailsClosed() {
        let p = FocusSafetyPolicy()
        XCTAssertFalse(p.isSafe(.init(bundleID: "com.apple.Terminal", role: "AXTextArea", subrole: nil, valueIsSettable: true)))
        XCTAssertFalse(p.isSafe(.init(bundleID: "com.apple.Safari", role: "AXTextField", subrole: "AXSecureTextField", valueIsSettable: true)))
        XCTAssertFalse(p.isSafe(.init(bundleID: "com.apple.TextEdit", role: "AXTextArea", subrole: nil, valueIsSettable: false)))
        XCTAssertTrue(p.isSafe(.init(bundleID: "com.apple.TextEdit", role: "AXTextArea", subrole: nil, valueIsSettable: true)))
    }

    func testFocusPolicyRejectsUnknownAccessibilityLookups() {
        let policy = FocusSafetyPolicy()
        XCTAssertFalse(policy.isSafe(.init(
            bundleID: "com.apple.TextEdit", role: "AXTextArea", subrole: nil, valueIsSettable: true,
            subroleLookupSucceeded: false, settableLookupSucceeded: true
        )))
        XCTAssertFalse(policy.isSafe(.init(
            bundleID: "com.apple.TextEdit", role: "AXTextArea", subrole: nil, valueIsSettable: true,
            subroleLookupSucceeded: true, settableLookupSucceeded: false
        )))
    }

    func testCodexAllowsItsEditableGroupWithoutRelaxingOtherApps() {
        let policy = FocusSafetyPolicy()

        XCTAssertTrue(policy.isSafe(.init(
            bundleID: "com.openai.codex",
            role: "AXGroup",
            subrole: nil,
            valueIsSettable: true
        )))
        XCTAssertFalse(policy.isSafe(.init(
            bundleID: "com.apple.Safari",
            role: "AXGroup",
            subrole: nil,
            valueIsSettable: true
        )))
        XCTAssertTrue(policy.allowsApplicationLevelFallback(bundleID: "com.openai.codex"))
        XCTAssertFalse(policy.allowsApplicationLevelFallback(bundleID: "com.apple.Safari"))
        XCTAssertFalse(policy.allowsApplicationLevelFallback(bundleID: nil))
    }

    func testZoomApplicationFallbackStillRejectsKnownSecureFields() {
        let policy = FocusSafetyPolicy()

        XCTAssertTrue(policy.allowsApplicationLevelFallback(bundleID: "us.zoom.xos"))
        XCTAssertFalse(policy.allowsApplicationLevelFallback(bundleID: "us.zoom.zCefWebView"))
        XCTAssertFalse(policy.isSafe(.init(
            bundleID: "us.zoom.xos",
            role: "AXTextField",
            subrole: "AXSecureTextField",
            valueIsSettable: true
        )))
    }

    func testResolverDoesNotTreatSecondaryLanguageSupportAsRussianOrAmerican() {
        let sources = [InputSourceDescriptor(id: "com.apple.keylayout.Bulgarian", languages: ["bg", "ru"]),
                       InputSourceDescriptor(id: "com.apple.keylayout.French", languages: ["fr", "en"])]
        XCTAssertNil(InputSourceResolver.resolve(.russian, from: sources))
        XCTAssertNil(InputSourceResolver.resolve(.english, from: sources))
    }

    func testKnownRussianAndUSVariantsResolveWithoutLanguageMetadata() {
        for id in ["Russian", "RussianWin"] {
            XCTAssertNotNil(InputSourceResolver.resolve(.russian, from: [.init(id: "com.apple.keylayout." + id, languages: [])]))
        }
        for id in ["US", "ABC", "USExtended", "USInternational-PC", "British", "British-PC", "Canadian", "Irish"] {
            XCTAssertNotNil(InputSourceResolver.resolve(.english, from: [.init(id: "com.apple.keylayout." + id, languages: [])]))
        }
    }

    func testResolverPrefersAppleIDThenLanguageFallback() {
        let s = [InputSourceDescriptor(id: "custom.en", languages: ["en"]), .init(id: "com.apple.keylayout.US", languages: ["en"]), .init(id: "custom.ru", languages: ["ru"])]
        XCTAssertEqual(InputSourceResolver.resolve(.english, from: s)?.id, "com.apple.keylayout.US")
        XCTAssertEqual(InputSourceResolver.resolve(.russian, from: s)?.id, "custom.ru")
        XCTAssertNil(InputSourceResolver.resolve(.russian, from: []))
    }
}
