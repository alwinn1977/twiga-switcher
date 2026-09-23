# Mixed-Language Typing Regression Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make both 24-line mixed-language typing scenarios reproduce the literal expected text, including multiple wrong-layout punctuation-key words, and retain them as regression tests.

**Architecture:** A test-only physical-key driver renders ABC/RussianWin key positions into `CGEvent`s and passes them through `KeyboardMonitor.handle`. A virtual editor applies only unsuppressed original events and the real executor's posted backspace/Unicode requests; a simulated input source records layout changes. Focused core tests isolate each first divergence before production changes, and an optional native TextEdit run checks the OS boundary.

**Tech Stack:** Swift 6, Swift Package Manager, XCTest, CoreGraphics, AppKit/Carbon keyboard layouts, bundled `mmap` lexicons, macOS 14+.

**Spec:** `docs/superpowers/specs/2026-09-23-mixed-typing-regression-design.md`

## Global Constraints

- The 24 literal UTF-8 lines in the spec, including the final newline, are the independent expected result; never derive expected text through `LayoutConverter` or rewrite it merely to pass a failing test.
- Every line mixes Russian and English; the corpus covers both directions, subject terms, multiword terms, sentence punctuation, and at least eight distinct words whose wrong-layout keystrokes contain `.`. `,.l;tn` and `k.,jq` also exercise layout-dependent `,` and `;`.
- Scenario A starts in English and never manually selects a layout. Scenario B selects the intended word's layout at each Cyrillic/Latin transition while automatic correction remains enabled. Both use the same expected text.
- Compare actual and expected UTF-8 bytes after every line and at the end; assert manual versus automatic layout transitions, correction direction/count, safe focus, and synthetic-event immunity independently.
- Test rules and imported-dictionary roots are isolated temporary data; never read or modify the user's rule file, dictionary settings, or documents.
- Keep the existing conservative safety policy, local `mmap` lookup, and bounded eight-token/128-scalar input buffer. No network or normal file I/O in the key callback.
- Run `swift test`, `scripts/build-app.sh`, and `scripts/benchmark-lexicons.sh`. Attempt native TextEdit typing only with verified foreground focus and reliable key delivery; report an environmental limitation honestly.
- Commit implementation directly to `main`, as the user requested, after each independently passing increment.

## Review Focus

- A leading `,.` in `,.l;tn` must remain part of a possible wrong-layout word without swallowing an ordinary comma/period — Task 3 tests both paths.
- Consecutive internal `.,` in `k.,jq` and `;` in `,.l;tn` must survive prefix deferral — Task 3 tests both literal streams.
- `.NET`, `Node.js`, `C++`, and sentence-ending periods must not be turned into Cyrillic letters or lose punctuation — Task 3 and Task 4 tests.
- A manual layout selection at a script transition must not reuse stale buffered text or trigger a reverse correction — Task 4 manual scenario and targeted assertion.
- Synthetic replacement events must not enter the editor twice or recursively trigger a new correction — Task 2 test.

---

### Task 1: Literal corpus and independent physical-key map

**Files:**
- Create: `Tests/LayoutSwitcherAppTests/MixedTypingCorpus.swift`
- Create: `Tests/LayoutSwitcherAppTests/PhysicalTypingKeys.swift`
- Create: `Tests/LayoutSwitcherAppTests/PhysicalTypingKeysTests.swift`

**Interfaces:**
- Produces: `MixedTypingCorpus.expected: String` containing the exact 24 lines from the spec plus one final newline, `expectedLines: [String]`, and `expectedLinePrefixes: [String]`.
- Produces: `PhysicalStroke(keyCode: CGKeyCode, flags: CGEventFlags, expectedLanguage: KeyboardLayout)` and `PhysicalTypingKeys.stroke(for:language:) -> PhysicalStroke?`.
- Produces: `PhysicalTypingKeys.render(_:in:) -> String`, the character actually emitted by ABC or RussianWin for that physical position.
- Task 2 consumes these test-only types. No production API changes.

- [ ] **Step 1: Write failing fixture/key-map tests before creating the helper**

```swift
func testCorpusIsTwentyFourMixedLinesWithFinalNewline() {
    let lines = MixedTypingCorpus.expected.split(separator: "\n", omittingEmptySubsequences: false)
    XCTAssertEqual(lines.count, 25)
    XCTAssertEqual(lines.last, "")
    XCTAssertTrue(lines.dropLast().allSatisfy { line in
        line.unicodeScalars.contains { (0x0400...0x04FF).contains($0.value) }
            && line.unicodeScalars.contains {
                (0x0041...0x005A).contains($0.value) || (0x0061...0x007A).contains($0.value)
            }
    })
}

func testWrongLayoutPunctuationKeysAreIndependentLiteralCases() {
    let cases = [
        ("компьютер", "rjvgm.nth"), ("меню", "vty."),
        ("люди", "k.lb"), ("бюджет", ",.l;tn"),
        ("любой", "k.,jq"), ("ключ", "rk.x"),
        ("мьютекс", "vm.ntrc"), ("плюс", "gk.c")
    ]
    for (word, literalRaw) in cases {
        XCTAssertEqual(PhysicalTypingKeys.rawKeys(for: word, intendedLayout: .russian, activeLayout: .english), literalRaw)
    }
}
```

- [ ] **Step 2: Run the new tests and confirm red**

Run: `swift test --filter PhysicalTypingKeysTests`. Expected: compile failure because the corpus and key map do not yet exist.

- [ ] **Step 3: Add the exact corpus and map; validate the host's punctuation positions**

Copy the 24 lines verbatim from the spec's “Literal expected text” into a multiline Swift literal and append `"\n"`. Use a test-only position table with ABC keycodes `q=12, a=0, z=6, comma=43, period=47, semicolon=41, plus=Shift+24` and their RussianWin counterparts (`й, ф, я, б, ю, ж`; the shared physical positions map `.`→`ю`, `,`→`б`, `;`→`ж`). RussianWin literal period is keycode 44 without Shift, comma is keycode 44 with Shift; ABC literal comma/period are keycodes 43/47. Do not call production `LayoutConverter` from this helper.

```swift
struct PhysicalStroke {
    let keyCode: CGKeyCode
    let flags: CGEventFlags
    let expectedLanguage: KeyboardLayout
}

enum PhysicalTypingKeys {
    private static let positions: [(CGKeyCode, Character, Character)] = [
        (50,"`","ё"),(12,"q","й"),(13,"w","ц"),(14,"e","у"),(15,"r","к"),
        (17,"t","е"),(16,"y","н"),(32,"u","г"),(34,"i","ш"),(31,"o","щ"),
        (35,"p","з"),(33,"[","х"),(30,"]","ъ"),(0,"a","ф"),(1,"s","ы"),
        (2,"d","в"),(3,"f","а"),(5,"g","п"),(4,"h","р"),(38,"j","о"),
        (40,"k","л"),(37,"l","д"),(41,";","ж"),(39,"'","э"),(6,"z","я"),
        (7,"x","ч"),(8,"c","с"),(9,"v","м"),(11,"b","и"),(45,"n","т"),
        (46,"m","ь"),(43,",","б"),(47,".","ю")
    ]

    static func stroke(for intended: Character, language: KeyboardLayout) -> PhysicalStroke? {
        if intended == " " { return .init(keyCode: 49, flags: [], expectedLanguage: language) }
        if intended == "\n" { return .init(keyCode: 36, flags: [], expectedLanguage: language) }
        if intended == "+" { return .init(keyCode: 24, flags: .maskShift, expectedLanguage: language) }
        if language == .russian && intended == "." { return .init(keyCode: 44, flags: [], expectedLanguage: language) }
        if language == .russian && intended == "," { return .init(keyCode: 44, flags: .maskShift, expectedLanguage: language) }
        let lower = Character(String(intended).lowercased())
        guard let position = positions.first(where: { language == .english ? $0.1 == lower : $0.2 == lower }) else { return nil }
        let shifted = String(intended) != String(lower)
        return .init(keyCode: position.0, flags: shifted ? .maskShift : [], expectedLanguage: language)
    }

    static func render(_ stroke: PhysicalStroke, in activeLayout: KeyboardLayout) -> String {
        if stroke.keyCode == 49 { return " " }
        if stroke.keyCode == 36 { return "\n" }
        if stroke.keyCode == 24 && stroke.flags.contains(.maskShift) { return "+" }
        if stroke.keyCode == 44 {
            if activeLayout == .russian { return stroke.flags.contains(.maskShift) ? "," : "." }
            return stroke.flags.contains(.maskShift) ? "?" : "/"
        }
        guard let position = positions.first(where: { $0.0 == stroke.keyCode }) else { return "\u{FFFD}" }
        let character = activeLayout == .english ? position.1 : position.2
        return stroke.flags.contains(.maskShift) ? String(character).uppercased() : String(character)
    }

    static func rawKeys(for word: String, intendedLayout: KeyboardLayout, activeLayout: KeyboardLayout) -> String {
        word.map { character in
            guard let key = stroke(for: character, language: intendedLayout) else { return "\u{FFFD}" }
            return render(key, in: activeLayout)
        }.joined()
    }
}
```

The table must cover every alphabetic/punctuation character in the literal corpus, uppercase via Shift, space (49), Return (36), `+` (Shift+24), and term-internal punctuation. Add literal punctuation cases for `Node.js`, `.NET`, and `C++`; a missing mapping produces `\u{FFFD}` and fails rather than dropping a key. For sentence delimiters, choose the physical key that produces the requested punctuation in the **active** layout; for punctuation inside a term, use the intended word layout so a wrong-layout letter can be observed.

- [ ] **Step 4: Run the physical-key tests and confirm green**

Run: `swift test --filter PhysicalTypingKeysTests`. Expected: PASS and exactly eight literal raw-key word cases.

- [ ] **Step 5: Commit the test corpus and key map**

```bash
git add Tests/LayoutSwitcherAppTests/MixedTypingCorpus.swift Tests/LayoutSwitcherAppTests/PhysicalTypingKeys.swift Tests/LayoutSwitcherAppTests/PhysicalTypingKeysTests.swift
git commit -m "test: add literal mixed typing corpus and physical keys"
```

### Task 2: Virtual editor and monitor-backed typing driver

**Files:**
- Modify: `Package.swift` (add the lexicon target to the app test target's dependencies)
- Create: `Tests/LayoutSwitcherAppTests/TypingSessionDriver.swift`
- Create: `Tests/LayoutSwitcherAppTests/TypingSessionDriverTests.swift`

**Interfaces:**
- Consumes: `MixedTypingCorpus`, `PhysicalTypingKeys`, `KeyboardMonitor.handle(type:event:)`, `EventPosting`, `InputSourceManaging`, `FocusSnapshotProviding`.
- Produces: `TypingSessionDriver.init(initialLayout:) throws`, `type(_ expected:mode:) throws -> TypingTrace`, `TypingTrace.editorText`, `TypingTrace.linePrefixes`, `TypingTrace.layoutSelections`, `TypingTrace.manualSelections`, `TypingTrace.automaticSelections`, `TypingTrace.words`, `TypingTrace.corrections`, and `TypingTrace.firstDivergence`.
- Produces: `TypedWord(intended:raw:layoutBefore:layoutAfter:corrected:)`, where `corrected` means the monitor selected a layout while resolving that word or its containing phrase.
- Produces: `CorrectionRecord(layoutBefore:layoutAfter:source:replacement:)`; record it only when the monitor successfully applies a replacement, never for a manual selection.
- Produces: `TypingMode.automatic` and `.manualAtScriptChanges`. Task 4 consumes the completed driver.

- [ ] **Step 1: Test an observable replacement and synthetic immunity with a missing driver**

```swift
func testDriverAppliesMonitorReplacementToEditor() throws {
    let session = try TypingSessionDriver(initialLayout: .english)
    let trace = try session.type("привет \n", mode: .automatic)
    XCTAssertEqual(trace.editorText, "привет \n")
    XCTAssertEqual(trace.layoutSelections, [.russian])
    XCTAssertEqual(trace.manualSelections.count, 0)
    XCTAssertEqual(trace.automaticSelections, [.russian])
    XCTAssertEqual(trace.words.first?.raw, "ghbdtn")
}

func testSyntheticReplacementIsNotInsertedTwice() throws {
    let session = try TypingSessionDriver(initialLayout: .english)
    let trace = try session.type("привет ", mode: .automatic, echoSyntheticEvents: true)
    XCTAssertEqual(trace.editorText, "привет ")
    XCTAssertEqual(trace.corrections.count, 1)
}
```

- [ ] **Step 2: Run the driver tests and confirm red**

Run: `swift test --filter TypingSessionDriverTests`. Expected: compile failure because `TypingSessionDriver` does not exist.

- [ ] **Step 3: Implement the virtual editor at the external event boundary**

Use `LexiconService(baseLoader: { try BundledLexiconResources.loadBase() }, packsRootURL: temporaryRoot, computerTermsLoader: { try BundledLexiconResources.loadComputerTerms() }, computerTermsSettings: isolatedSettings)` and `UserRuleStore(fileURL: temporaryRoot/rules.json)`; add `LayoutSwitcherLexicon` to the app test target's dependencies in `Package.swift` so those bundled loaders can be imported. `isolatedSettings` uses a temporary `UserDefaults(suiteName:)` and is set to enabled. Call `lexiconService.start()` **before** constructing the monitor: its catalog starts empty, and the test must actually use the bundled frequency data. Do not call the default `LexiconService()` or shared rule store.

```swift
final class VirtualEditor: EventPosting, InputSourceManaging {
    var text = ""
    var layout: KeyboardLayout = .english
    var selections: [KeyboardLayout] = []
    var isAvailable: Bool { true }
    func postBackspaces(count: Int) -> Bool {
        guard count <= text.count else { return false }
        for _ in 0..<count { text.removeLast() }
        return true
    }
    func postUnicode(_ value: String) -> Bool { text += value; return true }
    func select(_ target: KeyboardLayout) -> Bool { layout = target; selections.append(target); return true }
}
```

Lex the literal corpus into letter runs and term-internal punctuation (`Node.js`, `.NET`, `C++`) versus sentence separators. Annotate each run's intended script from its letters; the leading dot of `.NET` and the plus signs of `C++` inherit the Latin run. In manual mode, call the simulated `InputSourceManaging.select` before the first key of a run when its script differs from the active layout; count this separately as a manual selection. In automatic mode, never call it directly. Count selections made by `ReplacementExecutor` as automatic. The driver must record raw rendered keys per run independently of corrected editor text. For sentence punctuation, choose a physical key that emits that mark under the **current** layout; for term-internal punctuation, choose the intended run's physical position. Reject an unmapped corpus character instead of skipping it.

For each `PhysicalStroke`, create a `CGEvent` with its physical `keyCode`, `flags`, and `keyboardSetUnicodeString` set to the character rendered under the virtual editor's **current** layout. Call `monitor.handle(type: .keyDown, event:)`; append the unsuppressed original rendered character only if it returns a non-`nil` event. Replacement backspaces and Unicode are applied by the real `ReplacementExecutor` through `VirtualEditor`. For a synthetic echo, set `EventPoster.syntheticMarker` on a follow-up event and prove the monitor neither corrects nor selects a layout; do not append the echoed event a second time because `VirtualEditor` already applied the posted Unicode operation.

- [ ] **Step 4: Run driver and monitor-path tests**

Run: `swift test --filter TypingSessionDriverTests`. Expected: PASS; the synthetic echo causes no additional editor insertion or layout selection. Then run `swift test --filter KeyboardMonitorHotkeyTests` to detect tap-path regressions.

- [ ] **Step 5: Commit the driver**

```bash
git add Package.swift Tests/LayoutSwitcherAppTests/TypingSessionDriver.swift Tests/LayoutSwitcherAppTests/TypingSessionDriverTests.swift
git commit -m "test: drive keyboard monitor through a virtual editor"
```

### Task 3: Preserve ambiguous punctuation inside wrong-layout words

**Files:**
- Modify: `Sources/LayoutSwitcherCore/Input/PhraseBuffer.swift`
- Test: `Tests/LayoutSwitcherCoreTests/PhraseBufferTests.swift`
- Test: `Tests/LayoutSwitcherCoreTests/InputPipelineTests.swift`
- Test: `Tests/LayoutSwitcherAppTests/KeyboardEventNormalizerTests.swift`

**Interfaces:**
- Consumes: the existing `InputEvent.boundary(String)` and `PhraseBuffer.resolve(_:disposition:)` contract.
- Produces: bounded provisional leading punctuation and deferred punctuation-bearing candidates without changing `InputEvent` or `ReplacementPlan` public signatures.

- [ ] **Step 1: Add focused failing tests for leading and internal punctuation**

```swift
func testLeadingCommaPeriodAndDeferredSemicolonFormBudgetCandidate() throws {
    var buffer = PhraseBuffer()
    _ = buffer.handle(.boundary(","))
    _ = buffer.handle(.boundary("."))
    _ = buffer.handle(.character("l"))
    let semicolon = buffer.handle(.boundary(";"))
    let prefix = try XCTUnwrap(semicolon.candidates.first)
    buffer.resolve(semicolon, disposition: .deferForPhrase(prefix))
    for letter in "tn" { _ = buffer.handle(.character(letter)) }
    XCTAssertEqual(buffer.handle(.boundary(" ")).candidates.first?.text, ",.l;tn")
}

func testDeferredPeriodThenCommaFormsAnyCandidate() throws {
    var buffer = PhraseBuffer()
    _ = buffer.handle(.character("k"))
    let dot = buffer.handle(.boundary("."))
    buffer.resolve(dot, disposition: .deferForPhrase(try XCTUnwrap(dot.candidates.first)))
    let comma = buffer.handle(.boundary(","))
    buffer.resolve(comma, disposition: .deferForPhrase(try XCTUnwrap(comma.candidates.first)))
    for letter in "jq" { _ = buffer.handle(.character(letter)) }
    XCTAssertEqual(buffer.handle(.boundary(" ")).candidates.first?.text, "k.,jq")
}
```

Also assert an isolated literal comma/period followed by space passes through without a candidate, and `Node.js`, `.NET`, `C++` remain unchanged while `rjvgm.nth`, `k.,jq`, and `,.l;tn` produce their literal Russian targets through `InputPipeline`.

- [ ] **Step 2: Run the punctuation tests and confirm red**

Run: `swift test --filter PhraseBufferTests` and `swift test --filter InputPipelineTests`. Expected: the two new buffer assertions and punctuation correction assertions FAIL on current code for the recorded reasons, not for test setup.

- [ ] **Step 3: Implement minimal bounded punctuation retention**

Allow a leading `,` or `.` to remain provisional until a letter or whitespace arrives; permit at most two consecutive leading punctuation keys. Allow `,` and `;` as deferred internal delimiters only when the detector already chose `.deferred`, preserving the existing eight-token/128-scalar limit. A literal punctuation mark followed by whitespace remains pass-through. Keep the detector's score/ambiguity thresholds unchanged. Replace the dot-only `hasProvisionalPunctuation` Boolean with a trailing ambiguous-punctuation count derived from `text`; otherwise `k.,jq` would still be rejected after the dot.

```swift
// In PhraseBuffer.handle(.boundary), before makeCandidates():
if script == nil, text.count < 2,
   text.allSatisfy({ ",.".contains($0) }), [",", "."].contains(delimiter) {
    text += delimiter
    return .buffered
}
// In appendDeferredDelimiter(), after changing canRetain to accept "," and ";":
if [".", ",", ";"].contains(delimiter),
   text.reversed().prefix(while: { ".,;".contains($0) }).count < 2 {
    text += delimiter
    return true
}
```

Refine the provisional flag so consecutive punctuation needed by `k.,jq` and leading `,.` is accepted but an unbounded punctuation run is blocked.

- [ ] **Step 4: Run the punctuation and core tests until green**

Run: `swift test --filter PhraseBufferTests`, `swift test --filter InputPipelineTests`, and `swift test --filter LayoutSwitcherCoreTests`. Expected: all PASS, with no existing punctuation regression.

- [ ] **Step 5: Commit the punctuation fix**

```bash
git add Sources/LayoutSwitcherCore/Input/PhraseBuffer.swift Tests/LayoutSwitcherCoreTests/PhraseBufferTests.swift Tests/LayoutSwitcherCoreTests/InputPipelineTests.swift Tests/LayoutSwitcherAppTests/KeyboardEventNormalizerTests.swift
git commit -m "fix: retain layout-dependent punctuation in words"
```

### Task 4: Both full-corpus scenarios and first-divergence repairs

**Files:**
- Create: `Tests/LayoutSwitcherAppTests/MixedTypingIntegrationTests.swift`
- Modify as the first divergence proves necessary: `Sources/LayoutSwitcherCore/Input/PhraseBuffer.swift`, `Sources/LayoutSwitcherCore/Correction/InputPipeline.swift`, `Sources/LayoutSwitcherCore/Detection/LanguageDetector.swift`, `Sources/LayoutSwitcherApp/SystemIntegration/FocusedInputProcessor.swift`, `Sources/LayoutSwitcherApp/SystemIntegration/KeyboardEventNormalizer.swift`
- Modify only for a genuine general/domain term: `Dictionaries/Computer Terms.layoutdict/entries.tsv` and `Sources/LayoutSwitcherLexicon/Resources/Lexicons/ComputerTerms/*`
- Test at the matching boundary: `Tests/LayoutSwitcherCoreTests/InputPipelineTests.swift`, `Tests/LayoutSwitcherCoreTests/LanguageDetectorFrequencyTests.swift`, or `Tests/LayoutSwitcherAppTests/FocusedInputProcessorTests.swift`

**Interfaces:**
- Consumes: `TypingSessionDriver.type(_:mode:) -> TypingTrace` and the unchanged literal `MixedTypingCorpus.expected`.
- Produces: two passing full-path tests with line-by-line UTF-8 assertions and correction/layout traces.

- [ ] **Step 1: Add the two tests before production fixes**

```swift
func testTwentyFourLinesWithoutManualLayoutSwitches() throws {
    let session = try TypingSessionDriver(initialLayout: .english)
    let trace = try session.type(MixedTypingCorpus.expected, mode: .automatic)
    XCTAssertEqual(trace.linePrefixes.count, 24)
    for (index, actual) in trace.linePrefixes.enumerated() {
        XCTAssertEqual(Array(actual.utf8), Array(MixedTypingCorpus.expectedLinePrefixes[index].utf8), "line \(index + 1): \(trace.firstDivergence)")
    }
    XCTAssertEqual(Array(trace.editorText.utf8), Array(MixedTypingCorpus.expected.utf8))
    XCTAssertEqual(trace.manualSelections.count, 0)
    XCTAssertFalse(trace.automaticSelections.isEmpty)
    XCTAssertEqual(trace.words.first?.raw, "rjvgm.nth")
    XCTAssertEqual(trace.words.first?.layoutAfter, .russian)
    XCTAssertTrue(trace.corrections.contains { $0.layoutBefore == .english && $0.layoutAfter == .russian })
    XCTAssertTrue(trace.corrections.contains { $0.layoutBefore == .russian && $0.layoutAfter == .english })
}

func testTwentyFourLinesWithManualLayoutSwitches() throws {
    let session = try TypingSessionDriver(initialLayout: .english)
    let trace = try session.type(MixedTypingCorpus.expected, mode: .manualAtScriptChanges)
    XCTAssertEqual(trace.linePrefixes.count, 24)
    for (index, actual) in trace.linePrefixes.enumerated() {
        XCTAssertEqual(Array(actual.utf8), Array(MixedTypingCorpus.expectedLinePrefixes[index].utf8), "line \(index + 1): \(trace.firstDivergence)")
    }
    XCTAssertEqual(Array(trace.editorText.utf8), Array(MixedTypingCorpus.expected.utf8))
    XCTAssertFalse(trace.manualSelections.isEmpty)
    XCTAssertEqual(trace.automaticSelections.count, 0)
    XCTAssertEqual(trace.corrections.count, 0, "Correctly typed words were changed: \(trace.corrections)")
    XCTAssertEqual(trace.words.first?.raw, "компьютер")
    XCTAssertEqual(trace.words.first?.layoutAfter, .russian)
}
```

`TypingTrace.firstDivergence` must include line, physical keycode, active layout, raw rendered character, expected prefix, and actual prefix. `expectedLinePrefixes` is made only from the committed literal fixture, not production conversion.

- [ ] **Step 2: Run both scenarios and record the first divergence**

Run: `swift test --filter MixedTypingIntegrationTests`. Expected: RED on the first real mismatch; record the exact diagnostic rather than editing the corpus.

- [ ] **Step 3: Repair each distinct mismatch with a smaller red-green test**

For a first divergence in a punctuation-bearing word, add a literal raw-stream assertion to `InputPipelineTests` and fix buffering/normalization. For an incorrect language decision, add a literal score/prefix/rule assertion to `LanguageDetectorFrequencyTests`; change the general detector policy only if it improves the decision without reversing a correct word. For a missing genuine computer term such as `мьютекс`, assert its bundled lookup is present, add it to the project-authored TSV with a justified subject score, then regenerate the read-only index and manifest using the exact command below. For a focus or boundary reset, add a `FocusedInputProcessorTests` reproduction. In every case watch the narrow test fail, make one production change, rerun the narrow test, then rerun both 24-line scenarios before taking the next divergence. Do not add exact-pair `always` rules or modify the literal expected text to force green.

```bash
swift run LexiconCompiler compile-tsv \
  --input "Dictionaries/Computer Terms.layoutdict/entries.tsv" \
  --output-directory Sources/LayoutSwitcherLexicon/Resources/Lexicons/ComputerTerms \
  --manifest Sources/LayoutSwitcherLexicon/Resources/Lexicons/ComputerTerms/manifest.json \
  --source-name dev.layoutswitcher.dictionary.computer-terms \
  --source-version 1.0.0 --source-sha256 project-authored \
  --license CC0-1.0 --minimum-score 0 --subject-terms
```

```swift
// A literal raw stream, not a character-only helper that skips boundaries:
for key in ",.l;tn" {
    let input: InputEvent = ",.;".contains(key) ? .boundary(String(key)) : .character(key)
    _ = pipeline.handle(input, focusIsSafe: true)
}
XCTAssertEqual(pipeline.handle(.boundary(" "), focusIsSafe: true),
               .replace(.init(deleteKeyCount: 6, replacement: "бюджет", delimiter: " ", targetLayout: .russian)))
```

- [ ] **Step 4: Verify the complete corpus behavior**

Run: `swift test --filter MixedTypingIntegrationTests`; expected: two PASS, 24 line assertions each, exact UTF-8 final text. Run: `swift test`; expected: zero failures. Inspect `git diff --check`.

- [ ] **Step 5: Commit the complete corpus behavior**

```bash
git add Tests/LayoutSwitcherAppTests/MixedTypingIntegrationTests.swift Tests/LayoutSwitcherCoreTests Sources/LayoutSwitcherCore Sources/LayoutSwitcherApp Sources/LayoutSwitcherLexicon Dictionaries
git commit -m "test: cover sustained mixed-layout typing in both modes"
```

### Task 5: Release performance and native acceptance

**Files:**
- Modify: `README.md` (document the two corpus commands and native reproduction procedure)
- No production-code edits unless a new red-green regression is created first.

**Interfaces:**
- Consumes: the committed 24-line corpus and two green integration tests.
- Produces: build/test/benchmark evidence and an honest TextEdit verification status.

- [ ] **Step 1: Run the full verification commands and record outputs**

```bash
swift test
scripts/build-app.sh
scripts/benchmark-lexicons.sh
git diff --check
```

Expect zero test failures, a valid signed app bundle, and the existing 10,000-lookup budget of 250 ms. Record sustained corpus processing time separately; do not add a flaky wall-clock assertion to `swift test`.

- [ ] **Step 2: Attempt the two native TextEdit runs without touching existing documents**

Open a fresh disposable TextEdit document, verify it is foreground/focused, send actual key presses for the corpus in each mode, and read back the text via accessibility. Compare with `MixedTypingCorpus.expected` byte-for-byte. If UI automation injects characters outside the event tap or focus cannot be established, report the specific evidence and provide the same physical-key instructions for a human check; do not claim native success from `paste`, AX `setValue`, or a pure simulation. Do not discard a document through an irreversible UI action without the required confirmation.

- [ ] **Step 3: Update usage guidance and commit**

Add to `README.md` the two `swift test --filter MixedTypingIntegrationTests` cases, the 24-line corpus path, initial English layout for automatic typing, manual switching at script transitions for the second scenario, and the raw punctuation-key examples. Run `git diff --check`, then:

```bash
git add README.md
git commit -m "docs: explain mixed typing regression checks"
```

Finally run `git status --short` and report the two scenario results, native-smoke status, benchmark, release build, and commit IDs. Do not claim full macOS-level verification if the native run was inconclusive.
