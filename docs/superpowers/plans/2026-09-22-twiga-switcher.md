# TwigaSwitcher Prototype Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a native macOS menu-bar prototype that conservatively corrects Russian/English words typed in the wrong keyboard layout at word boundaries.

**Architecture:** A pure `TwigaSwitcherCore` target owns conversion, buffering, classification, and replacement planning. A macOS-only `TwigaSwitcherApp` executable adapts CoreGraphics, Accessibility, Text Input Source Services, spelling services, and SwiftUI to those pure interfaces. Swift Package Manager runs deterministic unit tests; a shell script packages the release executable and resources as a local agent `.app`.

**Tech Stack:** Swift 6, Swift Package Manager, SwiftUI, AppKit, CoreGraphics, ApplicationServices, Carbon, XCTest, macOS 14+

**Spec:** `docs/superpowers/specs/2026-09-22-twiga-switcher-design.md`

## Global Constraints

- Swift 6 language mode and Swift Package Manager.
- macOS 14.0 deployment target.
- Apple frameworks only; no package dependencies, server, network entitlement, privileged helper, persistence of typed text, signing, or notarization.
- Support only standard US-English and Russian input sources.
- Prefer no correction whenever language or focused-field safety is uncertain.
- Never log, persist, or transmit captured words.
- Terminal, iTerm2, screen-sharing, VNC, and remote-desktop applications remain excluded.

## Review Focus

- Mixed scripts, digits, emoji, and unsupported punctuation must block correction until the next boundary, never salvage a misleading suffix; Task 2 pins this behavior.
- Words accepted in both languages or neither language must remain unchanged; Task 3 pins both ambiguous outcomes.
- Secure, noneditable, excluded-app, and unknown Accessibility states must remain unchanged; Task 5 pins fail-closed behavior.
- Repeated event-tap disablement must stop the monitor instead of entering a re-enable loop; Task 4 pins the retry limit.
- A missing target input source must not crash, retry text insertion, or duplicate text; Tasks 5 and 6 pin resolution and execution behavior.

---

### Task 1: Swift package and complete layout conversion

**Files:**
- Create: `Package.swift`
- Create: `Sources/TwigaSwitcherCore/Conversion/KeyboardLayout.swift`
- Create: `Sources/TwigaSwitcherCore/Conversion/LayoutConverter.swift`
- Create: `Tests/TwigaSwitcherCoreTests/LayoutConverterTests.swift`

**Interfaces:**
- Produces: `KeyboardLayout`, `LayoutConversion`, and `LayoutConverter.convert(_:) -> LayoutConversion?`.
- Consumes: Nothing; this is the first production unit.

- [ ] **Step 1: Define the package and write failing converter tests**

Create `Package.swift`:

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TwigaSwitcher",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "TwigaSwitcherCore", targets: ["TwigaSwitcherCore"]),
    ],
    targets: [
        .target(name: "TwigaSwitcherCore"),
        .testTarget(name: "TwigaSwitcherCoreTests", dependencies: ["TwigaSwitcherCore"]),
    ],
    swiftLanguageModes: [.v6]
)
```

Create literal tests that catch a wrong key-position map and broken case handling:

```swift
import XCTest
@testable import TwigaSwitcherCore

final class LayoutConverterTests: XCTestCase {
    private let converter = LayoutConverter()

    func testConvertsBothDirections() {
        XCTAssertEqual(converter.convert("ghbdtn"),
                       LayoutConversion(text: "привет", targetLayout: .russian))
        XCTAssertEqual(converter.convert("руддщ"),
                       LayoutConversion(text: "hello", targetLayout: .english))
    }

    func testPreservesTitleAndUppercasePerCharacter() {
        XCTAssertEqual(converter.convert("Ghbdtn")?.text, "Привет")
        XCTAssertEqual(converter.convert("GHBDTN")?.text, "ПРИВЕТ")
        XCTAssertEqual(converter.convert("Руддщ")?.text, "Hello")
        XCTAssertEqual(converter.convert("РУДДЩ")?.text, "HELLO")
    }

    func testRoundTripsEveryMappedKeyPosition() {
        let english = "`qwertyuiop[]asdfghjkl;'zxcvbnm,."
        let russian = "ёйцукенгшщзхъфывапролджэячсмитьбю"
        XCTAssertEqual(converter.convert(english)?.text, russian)
        XCTAssertEqual(converter.convert(russian)?.text, english)
    }

    func testRejectsMixedScriptsDigitsAndEmptyInput() {
        XCTAssertNil(converter.convert("ghбdtn"))
        XCTAssertNil(converter.convert("hello2"))
        XCTAssertNil(converter.convert(""))
    }
}
```

- [ ] **Step 2: Run the focused test and verify RED**

Run: `swift test --filter LayoutConverterTests`

Expected: compilation fails because `LayoutConverter`, `LayoutConversion`, and `KeyboardLayout` do not exist.

- [ ] **Step 3: Implement the minimal converter**

Create these public types and construct two dictionaries by zipping the literal strings in the test. `convert(_:)` identifies exactly one source alphabet, maps each character by lowercase key position, uppercases each mapped character when the source character is uppercase, and returns `nil` for empty, unmapped, digit-containing, or mixed-script input.

```swift
public enum KeyboardLayout: String, Equatable, Sendable { case english, russian }

public struct LayoutConversion: Equatable, Sendable {
    public let text: String
    public let targetLayout: KeyboardLayout
    public init(text: String, targetLayout: KeyboardLayout) {
        self.text = text
        self.targetLayout = targetLayout
    }
}

public struct LayoutConverter: Sendable {
    private static let english = Array("`qwertyuiop[]asdfghjkl;'zxcvbnm,.")
    private static let russian = Array("ёйцукенгшщзхъфывапролджэячсмитьбю")
    private static let englishToRussian = Dictionary(uniqueKeysWithValues: zip(english, russian))
    private static let russianToEnglish = Dictionary(uniqueKeysWithValues: zip(russian, english))

    public init() {}

    public func convert(_ source: String) -> LayoutConversion? {
        guard !source.isEmpty else { return nil }
        var sourceLayout: KeyboardLayout?
        var result = ""
        for character in source {
            let loweredText = String(character).lowercased()
            guard loweredText.count == 1, let lowered = loweredText.first else { return nil }
            let mapped: Character
            let characterLayout: KeyboardLayout
            if let value = Self.englishToRussian[lowered] {
                mapped = value
                characterLayout = .english
            } else if let value = Self.russianToEnglish[lowered] {
                mapped = value
                characterLayout = .russian
            } else {
                return nil
            }
            guard sourceLayout == nil || sourceLayout == characterLayout else { return nil }
            sourceLayout = characterLayout
            let isUppercase = String(character) != loweredText && String(character) == String(character).uppercased()
            result += isUppercase ? String(mapped).uppercased() : String(mapped)
        }
        let target: KeyboardLayout = sourceLayout == .english ? .russian : .english
        return LayoutConversion(text: result, targetLayout: target)
    }
}
```

- [ ] **Step 4: Run tests and verify GREEN**

Run: `swift test --filter LayoutConverterTests`

Expected: 4 tests pass with no warnings.

- [ ] **Step 5: Commit**

```bash
git add Package.swift Sources Tests
git commit -m "feat: add keyboard layout conversion"
```

---

### Task 2: Safe in-memory word buffering

**Files:**
- Create: `Sources/TwigaSwitcherCore/Input/InputEvent.swift`
- Create: `Sources/TwigaSwitcherCore/Input/WordBuffer.swift`
- Create: `Tests/TwigaSwitcherCoreTests/WordBufferTests.swift`

**Interfaces:**
- Produces: `InputEvent`, `BufferedWord`, and mutating `WordBuffer.handle(_:) -> WordBufferResult`.
- Consumes: `Character` and delimiter strings normalized later by `KeyboardMonitor`.

- [ ] **Step 1: Write failing tests for accumulation, deletion, boundaries, and blocking**

Use this event vocabulary:

```swift
public enum InputEvent: Equatable, Sendable {
    case character(Character)
    case boundary(String)
    case backspace
    case reset
    case synthetic
}
```

Write tests:

```swift
func testBoundaryReturnsWordAndClearsBuffer() {
    var buffer = WordBuffer()
    "ghbdtn".forEach { _ = buffer.handle(.character($0)) }
    XCTAssertEqual(buffer.handle(.boundary(" ")),
                   .completed(BufferedWord(text: "ghbdtn", physicalKeyCount: 6), delimiter: " "))
    XCTAssertEqual(buffer.handle(.boundary(" ")), .emptyBoundary(" "))
}

func testBackspaceRemovesLastCapturedKey() {
    var buffer = WordBuffer()
    "ghbdto".forEach { _ = buffer.handle(.character($0)) }
    _ = buffer.handle(.backspace)
    XCTAssertEqual(buffer.handle(.boundary(".")),
                   .completed(BufferedWord(text: "ghbdt", physicalKeyCount: 5), delimiter: "."))
}

func testMixedScriptBlocksSuffixUntilBoundary() {
    var buffer = WordBuffer()
    "ghбdtn".forEach { _ = buffer.handle(.character($0)) }
    XCTAssertEqual(buffer.handle(.boundary(" ")), .blockedBoundary(" "))
    "ghbdtn".forEach { _ = buffer.handle(.character($0)) }
    XCTAssertEqual(buffer.handle(.boundary(" ")),
                   .completed(BufferedWord(text: "ghbdtn", physicalKeyCount: 6), delimiter: " "))
}

func testDigitEmojiAndResetNeverCompleteOldText() {
    var buffer = WordBuffer()
    "gh2dtn".forEach { _ = buffer.handle(.character($0)) }
    XCTAssertEqual(buffer.handle(.boundary(" ")), .blockedBoundary(" "))
    "gh🙂dtn".forEach { _ = buffer.handle(.character($0)) }
    XCTAssertEqual(buffer.handle(.boundary(" ")), .blockedBoundary(" "))
    "gh#dtn".forEach { _ = buffer.handle(.character($0)) }
    XCTAssertEqual(buffer.handle(.boundary(" ")), .blockedBoundary(" "))
    "ghbdtn".forEach { _ = buffer.handle(.character($0)) }
    XCTAssertEqual(buffer.handle(.reset), .cleared)
    XCTAssertEqual(buffer.handle(.boundary(" ")), .emptyBoundary(" "))
}
```

- [ ] **Step 2: Run the focused test and verify RED**

Run: `swift test --filter WordBufferTests`

Expected: compilation fails because `WordBuffer` and its result types do not exist.

- [ ] **Step 3: Implement a three-state buffer**

Implement `idle`, `collecting(text:keyCount:script:)`, and `blocked` internal states. A different script, digit, emoji, or unmapped character moves to `blocked`; only a boundary or reset returns it to `idle`. Backspace edits a collecting word, keeps blocked input blocked, and is harmless in idle state.

```swift
public struct BufferedWord: Equatable, Sendable {
    public let text: String
    public let physicalKeyCount: Int
}

public enum WordBufferResult: Equatable, Sendable {
    case buffered
    case completed(BufferedWord, delimiter: String)
    case emptyBoundary(String)
    case blockedBoundary(String)
    case cleared
}
```

- [ ] **Step 4: Run focused and full tests**

Run: `swift test --filter WordBufferTests && swift test`

Expected: all tests pass with no warnings.

- [ ] **Step 5: Commit**

```bash
git add Sources/TwigaSwitcherCore/Input Tests/TwigaSwitcherCoreTests/WordBufferTests.swift
git commit -m "feat: buffer words conservatively"
```

---

### Task 3: Conservative language decisions

**Files:**
- Create: `Sources/TwigaSwitcherCore/Detection/WordLexicon.swift`
- Create: `Sources/TwigaSwitcherCore/Detection/LanguageDetector.swift`
- Create: `Tests/TwigaSwitcherCoreTests/LanguageDetectorTests.swift`

**Interfaces:**
- Produces: `Language`, `WordLexicon`, `CorrectionDecision`, and `LanguageDetector.decision(original:conversion:)`.
- Consumes: `LayoutConversion` from Task 1.

- [ ] **Step 1: Write failing tests with a literal set lexicon**

```swift
private struct SetLexicon: WordLexicon {
    let english: Set<String>
    let russian: Set<String>
    func contains(_ word: String, language: Language) -> Bool {
        language == .english ? english.contains(word.lowercased()) : russian.contains(word.lowercased())
    }
}

func testCorrectsOnlyInvalidOriginalToValidCandidate() {
    let detector = LanguageDetector(
        lexicon: SetLexicon(english: ["hello"], russian: ["привет"]), allowlist: ["docker"])
    XCTAssertEqual(detector.decision(original: "ghbdtn",
        conversion: .init(text: "привет", targetLayout: .russian)),
        .correct(text: "привет", targetLayout: .russian))
}

func testLeavesAllowlistedValidAndAmbiguousWordsUnchanged() {
    let detector = LanguageDetector(
        lexicon: SetLexicon(english: ["docker", "a"], russian: ["ф"]), allowlist: ["docker"])
    XCTAssertEqual(detector.decision(original: "docker",
        conversion: .init(text: "вщслук", targetLayout: .russian)), .unchanged)
    XCTAssertEqual(detector.decision(original: "a",
        conversion: .init(text: "ф", targetLayout: .russian)), .unchanged)
    XCTAssertEqual(detector.decision(original: "zzz",
        conversion: .init(text: "яяя", targetLayout: .russian)), .unchanged)
}
```

- [ ] **Step 2: Run the test and verify RED**

Run: `swift test --filter LanguageDetectorTests`

Expected: compilation fails because the detector interfaces do not exist.

- [ ] **Step 3: Implement the fail-closed detector**

```swift
public enum Language: Equatable, Sendable { case english, russian }
public protocol WordLexicon: Sendable { func contains(_ word: String, language: Language) -> Bool }
public enum CorrectionDecision: Equatable, Sendable {
    case unchanged
    case correct(text: String, targetLayout: KeyboardLayout)
}
```

Make `LanguageDetector<Lexicon: WordLexicon>` a `Sendable` value. Infer the original language from `conversion.targetLayout`; normalize both words and the allowlist with `lowercased()`. Correct only when the original is not allowlisted and not accepted, while the candidate is accepted. Both-valid and both-invalid outcomes are unchanged.

- [ ] **Step 4: Run focused and full tests**

Run: `swift test --filter LanguageDetectorTests && swift test`

Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/TwigaSwitcherCore/Detection Tests/TwigaSwitcherCoreTests/LanguageDetectorTests.swift
git commit -m "feat: add conservative language detection"
```

---

### Task 4: Input pipeline, replacement plans, and tap health

**Files:**
- Create: `Sources/TwigaSwitcherCore/Correction/InputPipeline.swift`
- Create: `Sources/TwigaSwitcherCore/Correction/ReplacementPlan.swift`
- Create: `Sources/TwigaSwitcherCore/Input/TapHealth.swift`
- Create: `Tests/TwigaSwitcherCoreTests/InputPipelineTests.swift`
- Create: `Tests/TwigaSwitcherCoreTests/TapHealthTests.swift`

**Interfaces:**
- Produces: `ReplacementPlan`, `PipelineOutcome`, `InputPipeline.handle(_:focusIsSafe:)`, and `TapHealth.handleDisable()`.
- Consumes: Tasks 1–3.

- [ ] **Step 1: Write failing end-to-end core tests**

```swift
private struct PipelineLexicon: WordLexicon {
    let english: Set<String>
    let russian: Set<String>
    func contains(_ word: String, language: Language) -> Bool {
        language == .english ? english.contains(word.lowercased()) : russian.contains(word.lowercased())
    }
}

private func makePipeline(english: Set<String>, russian: Set<String>) -> InputPipeline<PipelineLexicon> {
    InputPipeline(
        converter: LayoutConverter(),
        detector: LanguageDetector(
            lexicon: PipelineLexicon(english: english, russian: russian),
            allowlist: []
        )
    )
}

func testSafeBoundaryBuildsLiteralReplacementPlan() {
    var pipeline = makePipeline(english: ["hello"], russian: ["привет"])
    "ghbdtn".forEach { XCTAssertEqual(pipeline.handle(.character($0), focusIsSafe: true), .passThrough) }
    XCTAssertEqual(pipeline.handle(.boundary(" "), focusIsSafe: true),
        .replace(.init(deleteKeyCount: 6, replacement: "привет",
                       delimiter: " ", targetLayout: .russian)))
}

func testUnsafeFocusNeverCreatesReplacement() {
    var pipeline = makePipeline(english: ["hello"], russian: ["привет"])
    "ghbdtn".forEach { _ = pipeline.handle(.character($0), focusIsSafe: false) }
    XCTAssertEqual(pipeline.handle(.boundary(" "), focusIsSafe: false), .passThrough)
}

func testSyntheticEventDoesNotMutateBufferedUserText() {
    var pipeline = makePipeline(english: ["hello"], russian: ["привет"])
    "ghbdtn".forEach { _ = pipeline.handle(.character($0), focusIsSafe: true) }
    XCTAssertEqual(pipeline.handle(.synthetic, focusIsSafe: true), .passThrough)
    XCTAssertEqual(pipeline.handle(.boundary(" "), focusIsSafe: true),
                   .replace(.init(deleteKeyCount: 6, replacement: "привет",
                                  delimiter: " ", targetLayout: .russian)))
}

func testTapRetriesOnceThenStopsUntilHealthyEvent() {
    var health = TapHealth(maximumReenableAttempts: 1)
    XCTAssertEqual(health.handleDisable(), .reenable)
    XCTAssertEqual(health.handleDisable(), .stop)
    health.recordHealthyEvent()
    XCTAssertEqual(health.handleDisable(), .reenable)
}
```

- [ ] **Step 2: Run tests and verify RED**

Run: `swift test --filter InputPipelineTests && swift test --filter TapHealthTests`

Expected: compilation fails because the pipeline and tap-health types do not exist.

- [ ] **Step 3: Implement pure orchestration**

```swift
public struct ReplacementPlan: Equatable, Sendable {
    public let deleteKeyCount: Int
    public let replacement: String
    public let delimiter: String
    public let targetLayout: KeyboardLayout
    public init(deleteKeyCount: Int, replacement: String, delimiter: String,
                targetLayout: KeyboardLayout) {
        self.deleteKeyCount = deleteKeyCount
        self.replacement = replacement
        self.delimiter = delimiter
        self.targetLayout = targetLayout
    }
}
public enum PipelineOutcome: Equatable, Sendable { case passThrough, replace(ReplacementPlan) }
```

`InputPipeline<Lexicon: WordLexicon>` owns the real buffer, converter, and detector. It converts and classifies only a completed word with safe focus, always clears completed/blocked input, and never mutates buffer for `.synthetic`. `TapHealth` counts consecutive disablements, resets on a healthy real event, returns `.reenable` up to its limit, then `.stop`.

- [ ] **Step 4: Run focused and full tests**

Run: `swift test --filter InputPipelineTests && swift test --filter TapHealthTests && swift test`

Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/TwigaSwitcherCore Tests/TwigaSwitcherCoreTests
git commit -m "feat: plan safe word replacements"
```

---

### Task 5: System lexicon, focus safety, permissions, and input sources

**Files:**
- Modify: `Package.swift`
- Create: `Sources/TwigaSwitcherApp/SystemIntegration/SystemLexicon.swift`
- Create: `Sources/TwigaSwitcherApp/SystemIntegration/FocusSafetyGuard.swift`
- Create: `Sources/TwigaSwitcherApp/SystemIntegration/PermissionManager.swift`
- Create: `Sources/TwigaSwitcherApp/SystemIntegration/InputSourceManager.swift`
- Create: `Sources/TwigaSwitcherApp/Resources/en.txt`
- Create: `Sources/TwigaSwitcherApp/Resources/ru.txt`
- Create: `Tests/TwigaSwitcherAppTests/FocusSafetyPolicyTests.swift`
- Create: `Tests/TwigaSwitcherAppTests/InputSourceResolverTests.swift`

**Interfaces:**
- Produces: `SystemLexicon`, `FocusSafetyGuard.isSafe()`, `PermissionManager.snapshot()`, and `InputSourceManaging.select(_:) -> Bool`.
- Consumes: Core language and layout types.

- [ ] **Step 1: Write failing policy and resolver tests**

```swift
func testFocusPolicyFailsClosed() {
    let policy = FocusSafetyPolicy()
    XCTAssertFalse(policy.isSafe(.init(bundleID: "com.apple.Terminal", role: "AXTextArea", subrole: nil, valueIsSettable: true)))
    XCTAssertFalse(policy.isSafe(.init(bundleID: "com.apple.Safari", role: "AXTextField", subrole: "AXSecureTextField", valueIsSettable: true)))
    XCTAssertFalse(policy.isSafe(.init(bundleID: "com.apple.TextEdit", role: "AXTextArea", subrole: nil, valueIsSettable: false)))
    XCTAssertFalse(policy.isSafe(.init(bundleID: "com.apple.Safari", role: nil, subrole: nil, valueIsSettable: false)))
    XCTAssertTrue(policy.isSafe(.init(bundleID: "com.apple.TextEdit", role: "AXTextArea", subrole: nil, valueIsSettable: true)))
}

func testResolverPrefersAppleIDThenLanguageFallback() {
    let sources = [InputSourceDescriptor(id: "custom.en", languages: ["en"]),
                   InputSourceDescriptor(id: "com.apple.keylayout.US", languages: ["en"]),
                   InputSourceDescriptor(id: "custom.ru", languages: ["ru"])]
    XCTAssertEqual(InputSourceResolver.resolve(.english, from: sources)?.id, "com.apple.keylayout.US")
    XCTAssertEqual(InputSourceResolver.resolve(.russian, from: sources)?.id, "custom.ru")
    XCTAssertNil(InputSourceResolver.resolve(.russian, from: []))
}
```

- [ ] **Step 2: Run tests and verify RED**

Run: `swift test --filter FocusSafetyPolicyTests && swift test --filter InputSourceResolverTests`

Expected: compilation fails because policy and resolver types do not exist.

- [ ] **Step 3: Implement fail-closed system adapters**

First extend `Package.swift` with a regular `TwigaSwitcherApp` target depending on Core and processing `Resources`, plus a `TwigaSwitcherAppTests` target depending on App and Core. Keep it a library target for Tasks 5–6 so system adapters can be tested without requiring an application entry point.

```swift
.target(
    name: "TwigaSwitcherApp",
    dependencies: ["TwigaSwitcherCore"],
    resources: [.process("Resources")]
),
.testTarget(
    name: "TwigaSwitcherAppTests",
    dependencies: ["TwigaSwitcherApp", "TwigaSwitcherCore"]
),
```

- `SystemLexicon` loads lowercase lines from both resources, then consults `NSSpellChecker` with explicit `en_US`/`ru`; a word is accepted on a bundled hit or a whole-word `NSNotFound` spelling result.
- `FocusSafetyGuard` reads focused application/UI element through AX, creates a `FocusDescriptor`, and applies `FocusSafetyPolicy`.
- Reject bundles `com.apple.Terminal`, `com.googlecode.iterm2`, `com.apple.ScreenSharing`, `com.microsoft.rdc.macos`, `com.realvnc.vncviewer`; reject `AXSecureTextField`, non-settable values, missing attributes, and AX errors. Accept editable `AXTextField`, `AXTextArea`, and `AXComboBox`.
- `PermissionManager` uses `AXIsProcessTrustedWithOptions`, `CGPreflightListenEventAccess`, and `CGRequestListenEventAccess`, and can open `Privacy_Accessibility` or `Privacy_ListenEvent` System Settings URLs.
- `InputSourceManager` queries enabled keyboard TIS sources, prefers `com.apple.keylayout.US`/`com.apple.keylayout.Russian`, falls back by `en`/`ru` language, and returns `false` when resolution or selection fails.

Use these deterministic resources, ignoring blank/comment lines:

```text
# en.txt
hello
world
swift
xcode
docker
github
json
http
ssh
```

```text
# ru.txt
привет
мир
мак
код
текст
слово
```

- [ ] **Step 4: Run focused and full tests**

Run: `swift test --filter FocusSafetyPolicyTests && swift test --filter InputSourceResolverTests && swift test`

Expected: all tests pass; missing system dictionaries do not affect resource-backed words.

- [ ] **Step 5: Commit**

```bash
git add Sources/TwigaSwitcherApp Tests/TwigaSwitcherAppTests
git commit -m "feat: integrate macOS language and safety services"
```

---

### Task 6: Global monitor and one-shot replacement execution

**Files:**
- Create: `Sources/TwigaSwitcherApp/SystemIntegration/KeyboardEventNormalizer.swift`
- Create: `Sources/TwigaSwitcherApp/SystemIntegration/KeyboardMonitor.swift`
- Create: `Sources/TwigaSwitcherApp/SystemIntegration/EventPoster.swift`
- Create: `Sources/TwigaSwitcherApp/SystemIntegration/ReplacementExecutor.swift`
- Create: `Tests/TwigaSwitcherAppTests/KeyboardEventNormalizerTests.swift`
- Create: `Tests/TwigaSwitcherAppTests/ReplacementExecutorTests.swift`

**Interfaces:**
- Produces: `KeyboardMonitor.start() -> Bool`, `stop()`, `resetBuffer()`, and `ReplacementExecutor.execute(_:)`.
- Consumes: pipeline, guard, source manager, plan, and tap health.

- [ ] **Step 1: Write failing normalizer and executor tests**

```swift
func testNormalizerMapsTextBoundariesModifiersAndMarker() {
    let normalizer = KeyboardEventNormalizer(syntheticMarker: 0x4C535743)
    XCTAssertEqual(normalizer.normalize(.init(text: "g", keyCode: 5, flags: [], marker: 0)), .character("g"))
    XCTAssertEqual(normalizer.normalize(.init(text: " ", keyCode: 49, flags: [], marker: 0)), .boundary(" "))
    XCTAssertEqual(normalizer.normalize(.init(text: "\n", keyCode: 36, flags: [], marker: 0)), .boundary("\n"))
    XCTAssertEqual(normalizer.normalize(.init(text: ".", keyCode: 47, flags: [], marker: 0)), .boundary("."))
    XCTAssertEqual(normalizer.normalize(.init(text: "", keyCode: 51, flags: [], marker: 0)), .backspace)
    XCTAssertEqual(normalizer.normalize(.init(text: "g", keyCode: 5, flags: [.command], marker: 0)), .reset)
    XCTAssertEqual(normalizer.normalize(.init(text: "g", keyCode: 5, flags: [], marker: 0x4C535743)), .synthetic)
}

private final class RecordingEventPoster: EventPosting {
    enum Action: Equatable { case backspace(count: Int), unicode(String) }
    private(set) var actions: [Action] = []
    func postBackspaces(count: Int) -> Bool { actions.append(.backspace(count: count)); return true }
    func postUnicode(_ text: String) -> Bool { actions.append(.unicode(text)); return true }
}

private final class RecordingInputSourceManager: InputSourceManaging {
    let result: Bool
    private(set) var selectedLayouts: [KeyboardLayout] = []
    init(result: Bool) { self.result = result }
    func select(_ layout: KeyboardLayout) -> Bool {
        selectedLayouts.append(layout)
        return result
    }
}

func testExecutorPostsExactlyOnceThenSelectsLayout() {
    let events = RecordingEventPoster()
    let sources = RecordingInputSourceManager(result: true)
    let executor = ReplacementExecutor(eventPoster: events, inputSources: sources)
    XCTAssertEqual(executor.execute(.init(deleteKeyCount: 6, replacement: "привет",
                                          delimiter: " ", targetLayout: .russian)), .completed)
    XCTAssertEqual(events.actions, [.backspace(count: 6), .unicode("привет"), .unicode(" ")])
    XCTAssertEqual(sources.selectedLayouts, [.russian])
}

func testMissingInputSourceDoesNotRepeatText() {
    let events = RecordingEventPoster()
    let sources = RecordingInputSourceManager(result: false)
    let executor = ReplacementExecutor(eventPoster: events, inputSources: sources)
    XCTAssertEqual(executor.execute(.init(deleteKeyCount: 5, replacement: "hello",
                                          delimiter: " ", targetLayout: .english)),
                   .textReplacedLayoutUnavailable)
    XCTAssertEqual(events.actions, [.backspace(count: 5), .unicode("hello"), .unicode(" ")])
}
```

- [ ] **Step 2: Run tests and verify RED**

Run: `swift test --filter KeyboardEventNormalizerTests && swift test --filter ReplacementExecutorTests`

Expected: compilation fails because the system event types do not exist.

- [ ] **Step 3: Implement adapters and monitor**

`EventPoster` posts paired Backspace events with key code 51 and Unicode down/up events through `keyboardSetUnicodeString`; mark every event `0x4C535743` via `.eventSourceUserData` and post at `.cghidEventTap`. `ReplacementExecutor` invokes backspace, replacement, and delimiter exactly once, then selects the layout once. Posting failure returns `.failed`; selection failure returns `.textReplacedLayoutUnavailable`; neither retries.

`KeyboardMonitor` creates a `.cgSessionEventTap` at `.headInsertEventTap` for key-down, flags-changed, and mouse-down masks. The callback handles tap-disable events through `TapHealth`, normalizes key events, checks focus only at a boundary, feeds the pipeline, and returns the original event or executes the plan and returns `nil`. Install on the main run loop. Reset on mouse-down and `NSWorkspace.didActivateApplicationNotification`. Stop and remove sources/observers idempotently.

- [ ] **Step 4: Run focused and full tests**

Run: `swift test --filter KeyboardEventNormalizerTests && swift test --filter ReplacementExecutorTests && swift test`

Expected: all tests pass without generating global input.

- [ ] **Step 5: Commit**

```bash
git add Sources/TwigaSwitcherApp/SystemIntegration Tests/TwigaSwitcherAppTests
git commit -m "feat: monitor and replace global keyboard input"
```

---

### Task 7: Menu-bar lifecycle and state model

**Files:**
- Modify: `Package.swift`
- Create: `Sources/TwigaSwitcherApp/Application/AppState.swift`
- Create: `Sources/TwigaSwitcherApp/Application/AppController.swift`
- Create: `Sources/TwigaSwitcherApp/Application/TwigaSwitcherApp.swift`
- Create: `Tests/TwigaSwitcherAppTests/AppStateTests.swift`

**Interfaces:**
- Produces: executable app and Active, Paused, Permissions Required, and Error menu states.
- Consumes: permission and monitor adapters.

- [ ] **Step 1: Write failing state tests**

```swift
func testEnabledAppStartsOnlyWithBothPermissions() {
    XCTAssertEqual(AppState.resolve(enabled: true, permissions: .granted,
                                    monitorRunning: true, error: nil), .active)
    XCTAssertEqual(AppState.resolve(enabled: true,
        permissions: .init(accessibility: true, inputMonitoring: false),
        monitorRunning: false, error: nil), .permissionsRequired)
}

func testDisabledAndFailureStatesRemainVisible() {
    XCTAssertEqual(AppState.resolve(enabled: false, permissions: .granted,
                                    monitorRunning: false, error: nil), .paused)
    XCTAssertEqual(AppState.resolve(enabled: true, permissions: .granted,
                                    monitorRunning: false, error: "Event monitor stopped"),
                   .error("Event monitor stopped"))
}
```

- [ ] **Step 2: Run test and verify RED**

Run: `swift test --filter AppStateTests`

Expected: compilation fails because `AppState` and `PermissionSnapshot` do not exist.

- [ ] **Step 3: Implement controller and menu**

`AppController` is `@MainActor`, persists only the enabled flag in `UserDefaults`, owns adapters, refreshes permissions on launch/activation, and starts or stops monitoring. Disabling clears the buffer.

Change the existing `TwigaSwitcherApp` package target to `.executableTarget` and add `.executable(name: "TwigaSwitcherApp", targets: ["TwigaSwitcherApp"])` to products before adding the entry point.

```swift
products: [
    .library(name: "TwigaSwitcherCore", targets: ["TwigaSwitcherCore"]),
    .executable(name: "TwigaSwitcherApp", targets: ["TwigaSwitcherApp"]),
],
// existing targets remain, except:
.executableTarget(
    name: "TwigaSwitcherApp",
    dependencies: ["TwigaSwitcherCore"],
    resources: [.process("Resources")]
),
```

Create an `@main` SwiftUI app with this menu body:

```swift
MenuBarExtra("TwigaSwitcher", systemImage: controller.state.systemImage) {
    Text(controller.state.title)
    Toggle("Enable Automatic Correction", isOn: Binding(
        get: { controller.isEnabled },
        set: { controller.setEnabled($0) }
    ))
    if controller.state == .permissionsRequired {
        Button("Request Required Permissions") { controller.requestPermissions() }
        Button("Open Privacy Settings") { controller.openPrivacySettings() }
    }
    Divider()
    Button("Quit TwigaSwitcher") { NSApplication.shared.terminate(nil) }
}
```

Do not display or persist captured text.

- [ ] **Step 4: Run full tests and release build**

Run: `swift test && swift build -c release`

Expected: all tests pass and the release executable is produced without warnings.

- [ ] **Step 5: Commit**

```bash
git add Sources/TwigaSwitcherApp/Application Tests/TwigaSwitcherAppTests/AppStateTests.swift
git commit -m "feat: add menu bar application lifecycle"
```

---

### Task 8: App packaging, documentation, and smoke verification

**Files:**
- Create: `scripts/build-app.sh`
- Create: `README.md`
- Create: `.gitignore`

**Interfaces:**
- Produces: `build/TwigaSwitcher.app` runnable with `open build/TwigaSwitcher.app`.
- Consumes: release executable and resource bundle.

- [ ] **Step 1: Run a failing packaging behavior check**

Run: `test -x scripts/build-app.sh && scripts/build-app.sh && test -x build/TwigaSwitcher.app/Contents/MacOS/TwigaSwitcher`

Expected: FAIL because the script does not exist.

- [ ] **Step 2: Implement deterministic `.app` packaging**

Use `set -euo pipefail`, `swift build -c release --show-bin-path`, and recreate only repository-local `build/TwigaSwitcher.app`. Copy the executable as `Contents/MacOS/TwigaSwitcher` and its generated resource bundle beside it. Write this plist and validate it with `plutil -lint`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>TwigaSwitcher</string>
  <key>CFBundleIdentifier</key><string>dev.twigaswitcher.prototype</string>
  <key>CFBundleName</key><string>TwigaSwitcher</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
</dict></plist>
```

- [ ] **Step 3: Verify packaging GREEN**

Run:

```bash
chmod +x scripts/build-app.sh
scripts/build-app.sh
test -x build/TwigaSwitcher.app/Contents/MacOS/TwigaSwitcher
plutil -lint build/TwigaSwitcher.app/Contents/Info.plist
codesign --verify --deep --strict build/TwigaSwitcher.app
```

Expected: executable check passes and plist/signature verification succeeds. If Swift emits an unsigned binary, add `codesign --force --deep --sign - build/TwigaSwitcher.app` to the script and rerun.

- [ ] **Step 4: Document exact use and limitations**

`README.md` documents macOS 14+/Xcode/US+Russian prerequisites, `swift test`, packaging, opening the app, granting both permissions, relaunching, the two acceptance examples, exclusions, and privacy. Include optional `tccutil reset Accessibility dev.twigaswitcher.prototype` with a warning that it revokes the current grant. `.gitignore` contains `.build/`, `build/`, and `.DS_Store`.

- [ ] **Step 5: Run complete automated verification**

Run: `swift test && swift build -c release && scripts/build-app.sh && git diff --check`

Expected: all tests and build pass, app bundle is produced, and diff check is clean.

- [ ] **Step 6: Perform the manual smoke matrix**

Open the generated app, grant both permissions, relaunch, and verify the manual scenarios from the spec in TextEdit, Notes, Safari/Chrome, Visual Studio Code, a password field, and Terminal/iTerm. Record OS prompts or host limitations in `README.md`; never weaken fail-closed behavior to force correction.

- [ ] **Step 7: Commit**

```bash
git add .gitignore README.md scripts/build-app.sh
git commit -m "build: package and document TwigaSwitcher"
```

---

## Final Verification

Run:

```bash
swift test
swift build -c release
scripts/build-app.sh
plutil -lint build/TwigaSwitcher.app/Contents/Info.plist
codesign --verify --deep --strict build/TwigaSwitcher.app
git status --short
```

Expected: tests and build pass without warnings, plist and signature verify, and `git status --short` is empty. Then run the manual smoke matrix and report unsupported host fields separately from code failures.
