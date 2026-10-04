import ApplicationServices
import XCTest
import TwigaSwitcherCore
@testable import TwigaSwitcherApp

private struct SpotlightTestLexicon: FrequencyLexicon {
    func lookup(_ text: String, language: Language) -> LexiconMatch {
        guard language == .russian else { return .missing }
        return .init(score: text == "привет" ? 5_100 : nil, isSubjectTerm: false,
                     isStrictPrefix: "привет".hasPrefix(text) && text != "привет")
    }

    func hasCompletion(for prefix: String, language: Language, minimumScore: Int) -> Bool {
        language == .russian && minimumScore <= 5_100 && "привет".hasPrefix(prefix)
    }
}

private final class StubFocusAccessibilityReader: FocusAccessibilityReading {
    var element = AXUIElementCreateApplication(42)
    var owner: FocusApplication? = .init(processID: 42, bundleID: "com.apple.Spotlight")
    var systemResult: AXError = .success
    var applicationResult: AXError = .success
    var focusedApplicationOwner: FocusApplication?
    var field: FocusDescriptor? = .init(
        bundleID: nil, role: "AXTextField", subrole: "AXSearchField", valueIsSettable: true
    )
    var queries = 0

    func focusedElement() -> (result: AXError, element: AXUIElement?) {
        queries += 1
        return (systemResult, systemResult == .success ? element : nil)
    }

    func focusedElement(in application: FocusApplication) -> (result: AXError, element: AXUIElement?) {
        queries += 1
        return (applicationResult, applicationResult == .success ? element : nil)
    }

    func focusedApplication() -> FocusApplication? { queries += 1; return focusedApplicationOwner ?? owner }
    func application(for element: AXUIElement) -> FocusApplication? { queries += 1; return owner }

    func descriptor(for element: AXUIElement, bundleID: String?) -> FocusDescriptor? {
        queries += 1
        guard let field else { return nil }
        return .init(
            bundleID: bundleID, role: field.role, subrole: field.subrole,
            valueIsSettable: field.valueIsSettable,
            subroleLookupSucceeded: field.subroleLookupSucceeded,
            settableLookupSucceeded: field.settableLookupSucceeded,
            elementIdentifier: field.elementIdentifier
        )
    }
}

final class FocusSafetyGuardTests: XCTestCase {
    func testCompatibilityCorrectsInCustomContainerAndRetainsFieldIdentity() throws {
        let id = "com.example.CustomEditor"
        let reader = StubFocusAccessibilityReader()
        reader.owner = .init(processID: 10, bundleID: id)
        reader.field = .init(bundleID: nil, role: "AXScrollArea", subrole: nil, valueIsSettable: false)
        let guardUnderTest = try makeGuard(reader, frontmostID: id, overrides: [id: .compatibility])
        let initial = try XCTUnwrap(guardUnderTest.snapshot())
        XCTAssertEqual(initial.identity.elementHash, CFHash(reader.element))
        var processor = FocusedInputProcessor(pipeline: InputPipeline(
            converter: LayoutConverter(), detector: LanguageDetector(
                lexicon: SpotlightTestLexicon(), rules: NoUserCorrectionRules()
            )
        ))
        for character in "ghb" { _ = processor.handle(.character(character), focus: initial) }
        var sameFieldProcessor = processor
        XCTAssertEqual(sameFieldProcessor.handle(.character("d"), focus: guardUnderTest.snapshot()), .replace(.init(
            deleteKeyCount: 3, replacement: "прив", delimiter: "", targetLayout: .russian
        )))

        // A different container in the same app must not inherit the old word.
        reader.element = AXUIElementCreateApplication(43)
        let other = try XCTUnwrap(guardUnderTest.snapshot())
        XCTAssertNotEqual(initial.identity, other.identity)
        XCTAssertEqual(processor.handle(.character("d"), focus: other), .passThrough)
        XCTAssertEqual(processor.handle(.boundary(" "), focus: other), .passThrough)
        reader.field = .init(bundleID: nil, role: "AXTextField", subrole: "AXSecureTextField", valueIsSettable: false)
        XCTAssertNil(guardUnderTest.snapshot())
        reader.applicationResult = .cannotComplete
        XCTAssertNil(guardUnderTest.snapshot())
    }

    func testMissingSystemFocusReadsFrontmostCodexAndPreservesCompatibilityFallback() throws {
        let reader = StubFocusAccessibilityReader()
        reader.owner = nil
        reader.systemResult = .noValue
        let guardUnderTest = try makeGuard(reader, frontmostID: "com.openai.codex")
        let fieldSnapshot = try XCTUnwrap(guardUnderTest.snapshot())
        XCTAssertEqual(fieldSnapshot.bundleID, "com.openai.codex")
        XCTAssertEqual(fieldSnapshot.identity.elementHash, CFHash(reader.element))

        reader.applicationResult = .noValue
        let appSnapshot = try XCTUnwrap(guardUnderTest.snapshot())
        XCTAssertEqual(appSnapshot.bundleID, "com.openai.codex")
        XCTAssertEqual(appSnapshot.identity, .init(processID: 10, elementHash: 10))
    }

    func testMissingSystemFocusDoesNotBypassApplicationFieldSafety() throws {
        let reader = StubFocusAccessibilityReader()
        reader.owner = nil
        reader.systemResult = .noValue
        reader.applicationResult = .noValue
        XCTAssertNil(try makeGuard(reader, frontmostID: "com.example.Editor").snapshot())
        XCTAssertNil(try makeGuard(
            reader, frontmostID: "com.openai.codex", overrides: ["com.openai.codex": .disabled]
        ).snapshot())
        reader.applicationResult = .cannotComplete
        XCTAssertNil(try makeGuard(reader, frontmostID: "com.openai.codex").snapshot())
        reader.applicationResult = .success
        reader.field = .init(
            bundleID: nil, role: "AXTextField", subrole: "AXSecureTextField", valueIsSettable: true
        )
        XCTAssertNil(try makeGuard(reader, frontmostID: "com.openai.codex").snapshot())
    }

    func testFrontmostSiriHostedSpotlightKeepsSystemSearchFieldLookup() throws {
        let reader = StubFocusAccessibilityReader()
        reader.owner = .init(processID: 10, bundleID: "com.apple.campo")
        reader.applicationResult = .noValue
        reader.field = .init(
            bundleID: nil, role: "AXTextField", subrole: "AXSearchField", valueIsSettable: true,
            elementIdentifier: "SpotlightSearchField"
        )
        let snapshot = try XCTUnwrap(makeGuard(reader, frontmostID: "com.apple.campo").snapshot())
        XCTAssertTrue(snapshot.isSpotlightSearch)
        XCTAssertEqual(snapshot.identity.elementHash, CFHash(reader.element))
    }

    func testCodexScopedFieldStillRespectsDisabledModeAndSecureFields() throws {
        let reader = StubFocusAccessibilityReader()
        reader.owner = .init(processID: 10, bundleID: "com.openai.codex")
        XCTAssertNil(try makeGuard(
            reader, frontmostID: "com.openai.codex", overrides: ["com.openai.codex": .disabled]
        ).snapshot())
        reader.field = .init(
            bundleID: nil, role: "AXTextField", subrole: "AXSecureTextField", valueIsSettable: true
        )
        XCTAssertNil(try makeGuard(reader, frontmostID: "com.openai.codex").snapshot())
    }

    func testCodexApplicationFocusStillWorksWhenSystemFieldLookupIsUnsupported() throws {
        let reader = StubFocusAccessibilityReader()
        reader.owner = .init(processID: 10, bundleID: "com.openai.codex")
        reader.systemResult = .attributeUnsupported
        let snapshot = try XCTUnwrap(makeGuard(reader, frontmostID: "com.openai.codex").snapshot())
        XCTAssertEqual(snapshot.identity.processID, 10)
        XCTAssertEqual(snapshot.bundleID, "com.openai.codex")
    }

    func testCodexRendererUsesHostApplicationCompatibilityRule() throws {
        let reader = StubFocusAccessibilityReader()
        reader.owner = .init(processID: 42, bundleID: "com.openai.codex.helper")
        reader.focusedApplicationOwner = .init(processID: 10, bundleID: "com.openai.codex")
        reader.field = .init(bundleID: nil, role: "AXGroup", subrole: nil, valueIsSettable: true)
        let snapshot = try XCTUnwrap(makeGuard(reader, frontmostID: "com.openai.codex").snapshot())
        XCTAssertEqual(snapshot.bundleID, "com.openai.codex")
        XCTAssertEqual(snapshot.identity.processID, 10)
    }

    func testCodexApplicationNoValueKeepsCompatibilityFallback() throws {
        let reader = StubFocusAccessibilityReader()
        reader.owner = .init(processID: 10, bundleID: "com.openai.codex")
        reader.applicationResult = .noValue
        reader.field = .init(bundleID: nil, role: "AXWebArea", subrole: nil, valueIsSettable: false)
        let snapshot = try XCTUnwrap(makeGuard(reader, frontmostID: "com.openai.codex").snapshot())
        XCTAssertEqual(snapshot.identity, .init(processID: 10, elementHash: 10))
        XCTAssertEqual(snapshot.bundleID, "com.openai.codex")
    }

    func testSiriHostedSpotlightCarriesSearchIdentityAndUsesSpotlightRule() throws {
        let reader = StubFocusAccessibilityReader()
        reader.owner = .init(processID: 42, bundleID: "com.apple.campo")
        reader.field = .init(
            bundleID: nil, role: "AXTextField", subrole: "AXSearchField", valueIsSettable: true,
            elementIdentifier: "SpotlightSearchField"
        )
        let snapshot = try XCTUnwrap(makeGuard(reader).snapshot())
        XCTAssertEqual(snapshot.bundleID, "com.apple.campo")
        XCTAssertEqual(snapshot.elementIdentifier, "SpotlightSearchField")
        XCTAssertTrue(snapshot.isSpotlightSearch)
        XCTAssertNil(try makeGuard(reader, overrides: ["com.apple.Spotlight": .disabled]).snapshot())
        reader.field = .init(
            bundleID: nil, role: "AXTextField", subrole: nil, valueIsSettable: true,
            elementIdentifier: "ConversationInput"
        )
        XCTAssertNotNil(try makeGuard(reader, overrides: ["com.apple.Spotlight": .disabled]).snapshot())
    }

    private func makeGuard(
        _ reader: StubFocusAccessibilityReader,
        frontmostID: String = "com.apple.TextEdit",
        overrides: [String: ApplicationCorrectionMode] = [:]
    ) throws -> FocusSafetyGuard {
        let suite = "FocusSafetyGuard-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let store = ApplicationRulesStore(defaults: defaults)
        for (id, mode) in overrides { store.setMode(mode, for: id) }
        return FocusSafetyGuard(
            defaults: defaults,
            frontmostApplication: { .init(processID: 10, bundleID: frontmostID) },
            accessibility: reader
        )
    }

    func testSpotlightFieldUsesItsOwnerEvenAboveDisabledApplication() throws {
        let reader = StubFocusAccessibilityReader()
        let guardUnderTest = try makeGuard(reader, frontmostID: "com.apple.Terminal")
        let snapshot = try XCTUnwrap(guardUnderTest.snapshot())
        XCTAssertEqual(snapshot.identity.processID, 42)
        XCTAssertEqual(snapshot.bundleID, "com.apple.Spotlight")
        XCTAssertEqual(snapshot.identity.elementHash, CFHash(reader.element))
    }

    func testDisabledSpotlightCannotInheritBackgroundApplicationCompatibility() throws {
        let reader = StubFocusAccessibilityReader()
        let guardUnderTest = try makeGuard(
            reader, frontmostID: "com.openai.codex", overrides: ["com.apple.Spotlight": .disabled]
        )
        XCTAssertNil(guardUnderTest.snapshot())
    }

    func testSpotlightWithoutFieldMetadataUsesItsOwnApplicationFallback() throws {
        let reader = StubFocusAccessibilityReader()
        reader.systemResult = .noValue
        let snapshot = try XCTUnwrap(makeGuard(reader).snapshot())
        XCTAssertEqual(snapshot.identity, .init(processID: 42, elementHash: 42))
    }

    func testApplicationFallbackNeverUsesBackgroundApplicationRule() throws {
        let reader = StubFocusAccessibilityReader()
        reader.systemResult = .noValue
        reader.owner = .init(processID: 42, bundleID: "com.example.Editor")
        XCTAssertNil(try makeGuard(reader, frontmostID: "com.openai.codex").snapshot())
    }

    func testFocusLookupFailureNeverFallsBackToBackgroundField() throws {
        for error in [AXError.cannotComplete, .apiDisabled, .attributeUnsupported] {
            let reader = StubFocusAccessibilityReader()
            reader.systemResult = error
            XCTAssertNil(try makeGuard(reader, frontmostID: "com.openai.codex").snapshot(), "\(error)")
        }
    }

    func testUnresolvableOwnerNeverUsesBackgroundApplicationFallback() throws {
        let reader = StubFocusAccessibilityReader()
        reader.owner = nil
        XCTAssertNil(try makeGuard(reader, frontmostID: "com.openai.codex").snapshot())
        reader.systemResult = .cannotComplete
        XCTAssertNil(try makeGuard(reader, frontmostID: "com.openai.codex").snapshot())
    }

    func testKnownSecureFieldInSpotlightRemainsRejected() throws {
        let reader = StubFocusAccessibilityReader()
        reader.field = .init(bundleID: nil, role: "AXTextField", subrole: "AXSecureTextField", valueIsSettable: true)
        XCTAssertNil(try makeGuard(reader).snapshot())
    }

    func testUncheckedFrontmostApplicationDoesNotQueryAccessibility() throws {
        let reader = StubFocusAccessibilityReader()
        let guardUnderTest = try makeGuard(reader, overrides: ["com.apple.TextEdit": .unchecked])
        XCTAssertEqual(guardUnderTest.snapshot()?.identity, .init(processID: 10, elementHash: 10))
        XCTAssertEqual(reader.queries, 0)
    }

    func testClosingSpotlightCannotCorrectBufferedQueryInUnderlyingEditor() throws {
        let reader = StubFocusAccessibilityReader()
        let guardUnderTest = try makeGuard(reader)
        var processor = FocusedInputProcessor(pipeline: InputPipeline(
            converter: LayoutConverter(), detector: LanguageDetector(
                lexicon: SpotlightTestLexicon(), rules: NoUserCorrectionRules()
            )
        ))
        let searchFocus = try XCTUnwrap(guardUnderTest.snapshot())
        for character in "ghb" { _ = processor.handle(.character(character), focus: searchFocus) }
        var searchProcessor = processor
        XCTAssertEqual(searchProcessor.handle(.character("d"), focus: searchFocus), .replace(.init(
            deleteKeyCount: 3, replacement: "прив", delimiter: "", targetLayout: .russian
        )))
        reader.owner = .init(processID: 10, bundleID: "com.apple.TextEdit")
        let editorFocus = try XCTUnwrap(guardUnderTest.snapshot())
        XCTAssertEqual(processor.handle(.character("d"), focus: editorFocus), .passThrough)
        XCTAssertEqual(processor.handle(.boundary(" "), focus: editorFocus), .passThrough)
    }
}
