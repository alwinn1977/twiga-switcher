import XCTest
import TwigaSwitcherCore
@testable import TwigaSwitcherApp

final class SystemPolicyTests: XCTestCase {
    func testSpotlightIsAvailableInApplicationSettingsAndRespectsSavedMode() throws {
        let suite = "SpotlightApplicationRules-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = ApplicationRulesStore(defaults: defaults)
        let rule = try XCTUnwrap(store.rules.first { $0.bundleID == "com.apple.Spotlight" })
        XCTAssertEqual(rule.name, "Spotlight")
        XCTAssertTrue(rule.isBuiltIn)
        XCTAssertEqual(rule.mode, .compatibility)
        XCTAssertTrue(FocusSafetyPolicy().allowsApplicationLevelFallback(bundleID: rule.bundleID))
        store.setMode(.disabled, for: rule.bundleID)
        let restored = ApplicationRulesStore(defaults: defaults)
        XCTAssertEqual(restored.rules.first { $0.bundleID == rule.bundleID }?.mode, .disabled)
        XCTAssertFalse(FocusSafetyPolicy(overrides: restored.overrides).isSafe(.init(
            bundleID: rule.bundleID, role: "AXTextField", subrole: "AXSearchField", valueIsSettable: true
        )))
    }

    func testUncheckedApplicationModePersistsAndDoesNotRequireFieldMetadata() throws {
        let unchecked = try XCTUnwrap(ApplicationCorrectionMode(rawValue: "unchecked"))
        let suite = "UncheckedApplicationRules-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = ApplicationRulesStore(defaults: defaults)
        store.setMode(unchecked, for: "com.apple.iWork.Pages")
        let restored = ApplicationRulesStore(defaults: defaults)
        XCTAssertEqual(restored.mode(for: "com.apple.iWork.Pages"), unchecked)
        XCTAssertEqual(restored.mode(for: "com.apple.TextEdit"), .standard)
        let policy = FocusSafetyPolicy(overrides: restored.overrides)
        XCTAssertTrue(policy.isSafe(.init(
            bundleID: "com.apple.iWork.Pages", role: nil, subrole: nil, valueIsSettable: false,
            subroleLookupSucceeded: false, settableLookupSucceeded: false
        )))
        XCTAssertFalse(policy.isSafe(.init(
            bundleID: "com.apple.Terminal", role: nil, subrole: nil, valueIsSettable: false
        )))
        XCTAssertFalse(policy.isSafe(.init(
            bundleID: nil, role: nil, subrole: nil, valueIsSettable: false
        )))
    }

    func testAppleOfficeApplicationsUseCompatibilityWithSecureFieldProtection() throws {
        let suite = "AppleApplicationRules-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = ApplicationRulesStore(defaults: defaults)
        let policy = FocusSafetyPolicy(overrides: store.overrides)
        for id in ["com.apple.iWork.Pages", "com.apple.iWork.Numbers", "com.apple.iWork.Keynote"] {
            let rule = try XCTUnwrap(store.rules.first { $0.bundleID == id })
            XCTAssertEqual(rule.mode, .compatibility)
            XCTAssertTrue(rule.isBuiltIn)
            XCTAssertTrue(policy.allowsApplicationLevelFallback(bundleID: id))
            XCTAssertTrue(policy.isSafe(.init(bundleID: id, role: "AXGroup", subrole: nil, valueIsSettable: true)))
            XCTAssertFalse(policy.usesApplicationFocus(bundleID: id))
            XCTAssertFalse(policy.isSafe(.init(bundleID: id, role: "AXTextField", subrole: "AXSecureTextField", valueIsSettable: true)))
            XCTAssertTrue(policy.isSafe(.init(bundleID: id, role: "AXTextArea", subrole: nil, valueIsSettable: false)))
        }
        for id in ["com.apple.TextEdit", "com.apple.Notes", "com.apple.mail"] {
            XCTAssertEqual(store.mode(for: id), .standard)
        }
    }

    func testITermAndVNCApplicationsHaveNoDefaultRule() throws {
        let suite = "RemovedApplicationRules-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = ApplicationRulesStore(defaults: defaults)
        for id in ["com.googlecode.iterm2", "com.realvnc.vncviewer", "com.apple.ScreenSharing"] {
            XCTAssertFalse(store.rules.contains { $0.bundleID == id })
            XCTAssertEqual(store.mode(for: id), .standard)
        }
    }

    func testRemovedDefaultApplicationKeepsExplicitModeVisibleAndRemovable() throws {
        let suite = "SavedApplicationRules-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(["com.googlecode.iterm2": "disabled"], forKey: "applicationCorrectionModes")
        let store = ApplicationRulesStore(defaults: defaults)
        let rule = try XCTUnwrap(store.rules.first { $0.bundleID == "com.googlecode.iterm2" })
        XCTAssertEqual(rule.mode, .disabled)
        XCTAssertFalse(rule.isBuiltIn)
        store.removeApplication(bundleID: rule.bundleID)
        XCTAssertEqual(store.mode(for: rule.bundleID), .standard)
        XCTAssertFalse(store.rules.contains { $0.bundleID == rule.bundleID })
    }

    func testInstalledSafariUsesCompatibilityModeButNeverPermitsSecureFields() {
        let policy = FocusSafetyPolicy()
        XCTAssertTrue(policy.allowsApplicationLevelFallback(bundleID: "com.apple.Safari"))
        XCTAssertTrue(policy.isSafe(.init(
            bundleID: "com.apple.Safari", role: "AXGroup", subrole: nil, valueIsSettable: true
        )))
        XCTAssertFalse(policy.isSafe(.init(
            bundleID: "com.apple.Safari", role: "AXTextField", subrole: "AXSecureTextField", valueIsSettable: true
        )))
    }

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

    func testCompatibilityDoesNotRequireAnEditableAccessibilityRoleOrValue() {
        let id = "com.example.CustomEditor"
        let policy = FocusSafetyPolicy(overrides: [id: .compatibility])
        // Custom editors can expose a container, an unknown role, or no role.
        // None of these describes whether keyboard input is accepted.
        for role: String? in ["AXScrollArea", "AXGroup", "AXTextArea", "CustomCanvas", nil] {
            XCTAssertTrue(policy.isSafe(.init(
                bundleID: id, role: role, subrole: nil, valueIsSettable: false,
                settableLookupSucceeded: false
            )), "role=\(role ?? "nil")")
        }
    }

    func testCompatibilityStillRejectsSecureFieldsAndFailedSecurityLookups() {
        let id = "com.example.CustomEditor"
        let policy = FocusSafetyPolicy(overrides: [id: .compatibility])
        for descriptor in [
            FocusDescriptor(bundleID: id, role: "AXTextField", subrole: "AXSecureTextField", valueIsSettable: false),
            FocusDescriptor(bundleID: id, role: "AXSecureTextField", subrole: nil, valueIsSettable: false),
            FocusDescriptor(bundleID: id, role: "AXScrollArea", subrole: nil, valueIsSettable: false,
                            subroleLookupSucceeded: false)
        ] {
            XCTAssertFalse(policy.isSafe(descriptor))
        }
        let container = FocusDescriptor(bundleID: id, role: "AXScrollArea", subrole: nil, valueIsSettable: false)
        XCTAssertFalse(FocusSafetyPolicy(overrides: [id: .standard]).isSafe(container))
        XCTAssertFalse(FocusSafetyPolicy(overrides: [id: .disabled]).isSafe(container))
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
            bundleID: "com.example.Editor",
            role: "AXGroup",
            subrole: nil,
            valueIsSettable: true
        )))
        XCTAssertTrue(policy.allowsApplicationLevelFallback(bundleID: "com.openai.codex"))
        XCTAssertFalse(policy.allowsApplicationLevelFallback(bundleID: "com.example.Editor"))
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
