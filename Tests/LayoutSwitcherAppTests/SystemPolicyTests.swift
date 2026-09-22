import XCTest
import LayoutSwitcherCore
@testable import LayoutSwitcherApp

final class SystemPolicyTests: XCTestCase {
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
    func testResolverPrefersAppleIDThenLanguageFallback() {
        let s = [InputSourceDescriptor(id: "custom.en", languages: ["en"]), .init(id: "com.apple.keylayout.US", languages: ["en"]), .init(id: "custom.ru", languages: ["ru"])]
        XCTAssertEqual(InputSourceResolver.resolve(.english, from: s)?.id, "com.apple.keylayout.US")
        XCTAssertEqual(InputSourceResolver.resolve(.russian, from: s)?.id, "custom.ru")
        XCTAssertNil(InputSourceResolver.resolve(.russian, from: []))
    }
}
