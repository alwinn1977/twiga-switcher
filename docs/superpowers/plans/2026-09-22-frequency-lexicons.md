# Frequency Lexicons and Learning Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the prototype spelling check with fast memory-mapped Russian and English frequency lexicons, add extensible subject dictionaries beginning with Computer Terms, and add private local learning with manual rules and Command-Z reversal.

**Architecture:** `TwigaSwitcherCore` owns normalization, confidence policy, phrase buffering, and platform-independent rule contracts. A new `TwigaSwitcherLexicon` target owns the deterministic binary format, compiler, `mmap` reader, pack validation/import, and immutable catalog snapshots. `TwigaSwitcherApp` composes those pieces with the event tap, local persistence, and native management windows; all slow work happens outside the keyboard callback.

**Tech Stack:** Swift 6, Swift Package Manager, SwiftUI/AppKit, Darwin `mmap`, Foundation JSON/TSV handling, CryptoKit SHA-256, XCTest, Python 3 with build-time `wordfreq` 3.1.1.

**Spec:** `docs/superpowers/specs/2026-09-22-frequency-lexicons-design.md`

## Global Constraints

- macOS 14 or newer; Russian and English only.
- All lookup and learning data stays local; no network, telemetry, or typed-text history at runtime.
- Runtime lookup must not call `NSSpellChecker`, perform normal file reads, or materialize a full lexicon as a Swift collection.
- Base and compiled subject indexes are read-only `mmap` regions with strict bounds and checksum validation.
- Input state is limited to eight whitespace-separated tokens and 128 Unicode scalars and is cleared at every existing focus-safety boundary.
- Base data comes from the pinned official `wordfreq` 3.1.1 artifact and is redistributed with the required Apache-2.0 / CC BY-SA 4.0 notices.
- Imported source is limited to 50 MiB, 1,000,000 entries, 4 KiB per line, languages `en` and `ru`, and scores 0...8,000.
- The built-in Computer Terms pack is enabled by default and supports individual, punctuation-bearing, and multiword terms.
- Implementation stays on `feature/frequency-lexicons`; verified work is merged directly into `main` with `--no-ff`.

## Review Focus

- Truncated or malicious mapped files must fail validation without an out-of-bounds read — exercised in Task 2 index corruption tests.
- A sentence-ending period and the internal period in `.NET` / `Node.js` must take different paths without losing characters — exercised in Task 5 ambiguous punctuation tests.
- Import cancellation or failure must not replace a working pack or catalog snapshot — exercised in Task 4 atomic import tests.
- Command-Z after focus change or subsequent typing must remain the foreground application's normal undo — exercised in Task 7 invalidation tests.
- Updating enabled packs while keys are arriving must expose a complete old or new snapshot, never partially rebuilt state — exercised in Task 4 concurrent snapshot tests.

---

### Task 1: Frequency evidence and conservative decision policy

**Files:**
- Create: `Sources/TwigaSwitcherCore/Detection/TermNormalizer.swift`
- Create: `Sources/TwigaSwitcherCore/Detection/FrequencyLexicon.swift`
- Create: `Sources/TwigaSwitcherCore/Detection/UserCorrectionRule.swift`
- Modify: `Sources/TwigaSwitcherCore/Detection/LanguageDetector.swift`
- Modify temporarily: `Sources/TwigaSwitcherApp/SystemIntegration/SystemLexicon.swift`
- Modify: `Sources/TwigaSwitcherApp/SystemIntegration/KeyboardMonitor.swift`
- Test: `Tests/TwigaSwitcherCoreTests/TermNormalizerTests.swift`
- Test: `Tests/TwigaSwitcherCoreTests/LanguageDetectorFrequencyTests.swift`
- Modify: existing detector and pipeline tests to use frequency fixtures

**Interfaces:**
- Produces: `TermNormalizer.normalize(_:) -> String`.
- Produces: `LexiconMatch(score: Int?, isSubjectTerm: Bool, isStrictPrefix: Bool)`.
- Produces: `FrequencyLexicon.lookup(_ text: String, language: Language) -> LexiconMatch`.
- Produces: `UserCorrectionRuleLookingUp.disposition(source:candidate:) -> UserCorrectionDisposition?`.
- Produces: `NoUserCorrectionRules`, the explicit empty rule provider used until Task 7.
- Produces: `LanguageDetector<Lexicon: FrequencyLexicon, Rules: UserCorrectionRuleLookingUp>.init(lexicon:rules:)`.
- Produces: `CorrectionDecision.unchanged`, `.deferred`, and `.correct(text:targetLayout:)`.
- Consumes later: mapped indexes and catalog snapshots conform to `FrequencyLexicon`; the rule snapshot conforms to `UserCorrectionRuleLookingUp`.

- [ ] **Step 1: Write normalization tests that fail because `TermNormalizer` does not exist**

```swift
func testNormalizesCaseWhitespaceAndCurlyApostropheWithoutRemovingAccents() {
    XCTAssertEqual(TermNormalizer.normalize("  NODE.\u{2019}JS  SDK "), "node.'js sdk")
    XCTAssertEqual(TermNormalizer.normalize("Ёлка"), "ёлка")
    XCTAssertNotEqual(TermNormalizer.normalize("café"), "cafe")
}
```

Run: `swift test --filter TermNormalizerTests`

Expected: FAIL to compile because `TermNormalizer` is missing.

- [ ] **Step 2: Implement the minimal deterministic normalizer and make the test green**

Use NFC (`precomposedStringWithCanonicalMapping`), `lowercased(with: Locale(identifier: "en_US_POSIX"))`, explicit curly quote translation, trimming, and whitespace collapsing. Do not use the user's locale.

Run: `swift test --filter TermNormalizerTests`

Expected: PASS.

- [ ] **Step 3: Write literal-table policy tests for thresholds, subject boost, ambiguity, prefix deferral, and user-rule precedence**

```swift
func testFrequencyPolicyUsesThresholdMarginAndRulePrecedence() {
    assertDecision(original: "ghbdtn", originalScore: nil,
                   candidate: "привет", candidateScore: 2500,
                   rule: nil, expected: .correct(text: "привет", targetLayout: .russian))
    assertDecision(original: "a", originalScore: 5000,
                   candidate: "ф", candidateScore: 5999,
                   rule: nil, expected: .unchanged)
    assertDecision(original: "a", originalScore: 5000,
                   candidate: "ф", candidateScore: 6000,
                   rule: nil, expected: .correct(text: "ф", targetLayout: .russian))
    assertDecision(original: "node.js", originalScore: 1800,
                   candidate: "тщвуоы", candidateScore: nil,
                   rule: .never, expected: .unchanged)
}

func testStrictPhrasePrefixDefersInsteadOfCorrectingShorterSuffix() {
    let result = detector.decision(
        original: "ьфсршту", conversion: .init(text: "machine", targetLayout: .english)
    )
    XCTAssertEqual(result, .deferred)
}
```

The fixture must return independent literal `LexiconMatch` values and assert the detector result, not calls on a mock.

Run: `swift test --filter LanguageDetectorFrequencyTests`

Expected: FAIL to compile because the frequency and rule contracts are absent.

- [ ] **Step 4: Replace boolean containment with frequency evidence**

Implement named policy values `minimumTargetScore = 2_500`, `ambiguityMargin = 1_000`, and `subjectBoost = 1_500`. Apply `never`, then `always`, then strict-prefix deferral, then boosted score comparison. The target must reach the minimum; ties and insufficient margins remain unchanged.

Run: `swift test --filter LanguageDetectorFrequencyTests`

Expected: PASS.

- [ ] **Step 5: Migrate existing fixtures and add a temporary app bridge without weakening assertions**

Replace `SetLexicon` / `PipelineLexicon` with small real score-backed fixtures. Preserve tests for `ghbdtn → привет`, ambiguity, unknown pairs, synthetic events, and unsafe focus. Until Task 6 deletes it, make `SystemLexicon` conform to `FrequencyLexicon` by translating a recognized spelling into a score of 3,000 with no subject/prefix flags; construct the live detector with `NoUserCorrectionRules`. This bridge exists only to keep every intermediate commit buildable and receives no new behavior.

Run: `swift test --filter TwigaSwitcherCoreTests`

Expected: all core tests PASS.

- [ ] **Step 6: Commit the policy increment**

```bash
git add Sources/TwigaSwitcherCore Sources/TwigaSwitcherApp Tests
git commit -m "feat: add frequency recognition policy"
```

---

### Task 2: Deterministic binary compiler and safe mmap reader

**Files:**
- Modify: `Package.swift`
- Create: `Sources/TwigaSwitcherLexicon/Index/LexiconIndexFormat.swift`
- Create: `Sources/TwigaSwitcherLexicon/Index/LexiconIndexCompiler.swift`
- Create: `Sources/TwigaSwitcherLexicon/Index/MappedFile.swift`
- Create: `Sources/TwigaSwitcherLexicon/Index/MappedLexicon.swift`
- Create: `Tests/TwigaSwitcherLexiconTests/LexiconIndexCompilerTests.swift`
- Create: `Tests/TwigaSwitcherLexiconTests/MappedLexiconTests.swift`

**Interfaces:**
- Consumes: `TermNormalizer`, `Language`, `LexiconMatch`, and `FrequencyLexicon` from Task 1.
- Produces: `LexiconEntry(language:key:score:flags:)`.
- Produces: `LexiconIndexCompiler.compile(entries:language:to:) throws -> CompiledIndexMetadata`.
- Produces: `MappedLexicon.init(url:expectedLanguage:) throws`, `lookup(_:language:)`, `entryCount`, and `maximumPhraseWords`.
- Binary schema: little-endian fixed header plus 24-byte fixed records (`offset: UInt64`, `length: UInt32`, `score: Int32`, `flags: UInt32`, `reserved: UInt32`) and sorted UTF-8 string table; every integer read is bounds-checked before pointer access.

- [ ] **Step 1: Add the new library and test targets, then write a failing deterministic compiler test**

```swift
func testCompilerSortsNormalizedKeysAndProducesIdenticalBytes() throws {
    let entries = [
        LexiconEntry(language: .english, key: "World", score: 4100, flags: []),
        LexiconEntry(language: .english, key: "hello", score: 5200, flags: [])
    ]
    let first = temporaryURL("first.lsidx")
    let second = temporaryURL("second.lsidx")
    try LexiconIndexCompiler.compile(entries: entries, language: .english, to: first)
    try LexiconIndexCompiler.compile(entries: Array(entries.reversed()), language: .english, to: second)
    XCTAssertEqual(try Data(contentsOf: first), try Data(contentsOf: second))
}
```

Run: `swift test --filter LexiconIndexCompilerTests`

Expected: FAIL to compile because the compiler API is missing.

- [ ] **Step 2: Implement header/record encoding, sorting, validation, and SHA-256**

Use explicit byte encoding rather than `MemoryLayout` serialization so output is architecture-independent. Reject invalid scores, languages, characters, duplicate normalized keys with different scores, excessive line/term limits, and offsets that cannot fit the format. Write to a sibling temporary file, `fsync`, then rename.

Run: `swift test --filter LexiconIndexCompilerTests`

Expected: PASS for deterministic output, duplicate collapse/rejection, language mismatch, limits, and exact metadata.

- [ ] **Step 3: Write failing real-file mmap lookup and corruption tests**

```swift
func testMappedLookupFindsEdgesPrefixAndMissWithoutMaterializingEntries() throws {
    let url = try compileFixture(["alpha": 3000, "node.js": 4200, "zulu": 2800])
    let lexicon = try MappedLexicon(url: url, expectedLanguage: .english)
    XCTAssertEqual(lexicon.lookup("ALPHA", language: .english).score, 3000)
    XCTAssertTrue(lexicon.lookup("node", language: .english).isStrictPrefix)
    XCTAssertNil(lexicon.lookup("missing", language: .english).score)
    XCTAssertEqual(lexicon.lookup("zulu", language: .english).score, 2800)
}

func testRejectsEveryTruncationBeforePublishingMappedPointers() throws {
    let complete = try Data(contentsOf: compileFixture(["hello": 5000]))
    for length in 0..<complete.count {
        XCTAssertThrowsError(try openMapped(Data(complete.prefix(length))))
    }
}
```

Run: `swift test --filter MappedLexiconTests`

Expected: FAIL because `MappedLexicon` is missing.

- [ ] **Step 4: Implement `MappedFile` and binary search**

Open with `O_RDONLY | O_CLOEXEC`, obtain size with `fstat`, map with `mmap(PROT_READ, MAP_PRIVATE)`, and close the file descriptor after mapping. Validate magic, schema, language, monotonic sorted keys, record/string bounds, maximum phrase metadata, and SHA-256 before making the instance available. Use bytewise UTF-8 comparison for exact and strict-prefix binary searches. Call `munmap` once in `deinit`.

Run: `swift test --filter TwigaSwitcherLexiconTests`

Expected: PASS, including truncation, corrupt checksum, corrupt offset, wrong language, first/middle/last/miss, NFC, and prefix cases.

- [ ] **Step 5: Run the complete suite and commit**

Run: `swift test`

Expected: all tests PASS with no warnings.

```bash
git add Package.swift Sources/TwigaSwitcherLexicon Tests/TwigaSwitcherLexiconTests
git commit -m "feat: add memory mapped lexicon index"
```

---

### Task 3: Reproducible base frequency resources

**Files:**
- Create: `Sources/LexiconCompiler/main.swift`
- Create: `scripts/export-wordfreq.py`
- Create: `scripts/generate-base-lexicons.sh`
- Create: `scripts/test-generate-base-lexicons.sh`
- Modify: `scripts/build-app.sh`
- Modify: `scripts/test-build-app-signing.sh`
- Create: `Sources/TwigaSwitcherLexicon/Resources/Lexicons/Base/manifest.json`
- Create: `Sources/TwigaSwitcherLexicon/Resources/Lexicons/Base/en.lsidx`
- Create: `Sources/TwigaSwitcherLexicon/Resources/Lexicons/Base/ru.lsidx`
- Create: `Sources/TwigaSwitcherLexicon/Resources/Licenses/wordfreq-NOTICE.md`
- Create: `Sources/TwigaSwitcherLexicon/Resources/Licenses/CC-BY-SA-4.0.txt`
- Create: `Sources/TwigaSwitcherLexicon/Bundled/BundledLexiconResources.swift`
- Test: `Tests/TwigaSwitcherLexiconTests/BundledLexiconResourceTests.swift`
- Modify: `Package.swift`

**Interfaces:**
- Consumes: `LexiconIndexCompiler` from Task 2.
- Produces: CLI `LexiconCompiler compile-tsv --input <path> --output-directory <path> --manifest <path>`.
- Produces: deterministic English/Russian indexes and a resource manifest containing wordfreq version, input checksum, output checksums, counts, and license identifiers.
- Produces: `BundledLexiconResources.loadBase(bundle:)` and `loadComputerTerms(bundle:)`, both validating manifest checksums before returning mapped indexes.

- [ ] **Step 1: Write a failing shell integration test for the compiler CLI**

The test creates a literal three-row TSV, invokes `swift run LexiconCompiler compile-tsv`, opens the results through a tiny XCTest fixture or `LexiconCompiler verify`, and asserts exact counts and lookups. It then runs compilation again with reversed source order and compares SHA-256 outputs.

Run: `zsh scripts/test-generate-base-lexicons.sh`

Expected: FAIL because the executable and script do not exist.

- [ ] **Step 2: Implement the compiler CLI and make the fixture test pass**

Parse UTF-8 incrementally with `readLine`/buffered file handles, never by loading the production TSV as a single `String`. Emit actionable `path:line: message` validation errors and a deterministic JSON manifest with sorted keys.

Run: `zsh scripts/test-generate-base-lexicons.sh`

Expected: PASS.

- [ ] **Step 3: Add the pinned wordfreq exporter and notices**

`export-wordfreq.py` must assert the installed package metadata reports `wordfreq` 3.1.1, enumerate the large English and Russian lists, query Zipf scores, normalize through an equivalent documented pipeline, write `language<TAB>score<TAB>term`, and record the wheel SHA-256 supplied by `generate-base-lexicons.sh`. The shell script uses a temporary virtual environment and refuses an unpinned package.

Run: `zsh scripts/generate-base-lexicons.sh --check-tools`

Expected before installing the pinned build dependency: a clear missing-tool/dependency diagnostic, not a partial resource rewrite.

- [ ] **Step 4: Generate and validate the real base indexes**

Run: `zsh scripts/generate-base-lexicons.sh`

Expected: committed resources are regenerated atomically; English and Russian each contain broad frequency coverage, checksums match the manifest, and total resources remain within the agreed 5–20 MiB target unless the generated manifest documents and justifies a smaller result.

Update `build-app.sh` to copy every expected SwiftPM resource bundle explicitly, including `TwigaSwitcher_TwigaSwitcherLexicon.bundle`, before signing. Extend the packaging test to open the packaged bundle resources through `BundledLexiconResources`, so a missing copy fails by behavior.

- [ ] **Step 5: Write and run bundled-resource behavior tests**

```swift
func testBundledBaseIndexesRecognizeCommonWordsAndRequiredInflections() throws {
    let base = try BundledLexiconResources.loadBase(bundle: .module)
    XCTAssertGreaterThan(base.english.lookup("development", language: .english).score ?? 0, 2500)
    XCTAssertGreaterThan(base.russian.lookup("разработчики", language: .russian).score ?? 0, 2500)
    XCTAssertNil(base.russian.lookup("ghbdtn", language: .russian).score)
}
```

Run: `swift test --filter BundledLexiconResourceTests`

Expected: PASS and verify resource checksums and notice presence, not merely filenames.

- [ ] **Step 6: Commit generated resources and reproducibility tooling**

```bash
git add Package.swift Sources/LexiconCompiler scripts Sources/TwigaSwitcherApp/Resources Tests/TwigaSwitcherLexiconTests
git commit -m "feat: bundle frequency lexicon resources"
```

---

### Task 4: Subject pack validation, atomic import, and catalog snapshots

**Files:**
- Create: `Sources/TwigaSwitcherLexicon/Packs/DictionaryPackManifest.swift`
- Create: `Sources/TwigaSwitcherLexicon/Packs/DictionaryPackImporter.swift`
- Create: `Sources/TwigaSwitcherLexicon/Packs/DictionaryPackStore.swift`
- Create: `Sources/TwigaSwitcherLexicon/Catalog/LexiconCatalog.swift`
- Create: `Sources/TwigaSwitcherLexicon/Catalog/LexiconCatalogSnapshot.swift`
- Create: `Tests/TwigaSwitcherLexiconTests/DictionaryPackImporterTests.swift`
- Create: `Tests/TwigaSwitcherLexiconTests/LexiconCatalogTests.swift`

**Interfaces:**
- Consumes: compiler and mapped reader from Task 2; `FrequencyLexicon` from Task 1.
- Produces: `DictionaryPackManifest: Codable, Sendable` with schema/id/name/version/description/attribution.
- Produces: `DictionaryPackImporter.importPackage(at:into:existingPolicy:) async throws -> InstalledDictionaryPack`.
- Produces: `DictionaryPackStore` for installed metadata and enabled identifiers.
- Produces: `LexiconCatalog.snapshot() -> LexiconCatalogSnapshot` and `replaceSnapshot(_:)`; snapshots conform to `FrequencyLexicon`.

- [ ] **Step 1: Write failing manifest and TSV validation tests**

Cover valid bilingual phrases, comments/blank lines, bad UTF-8, invalid language, score -1/8001, missing letter, unsupported symbol, 129 scalars, nine tokens, 4 KiB line overflow, source over 50 MiB, more than one million entries, duplicate identifier, and path traversal attempts.

Run: `swift test --filter DictionaryPackImporterTests`

Expected: FAIL because pack APIs are missing.

- [ ] **Step 2: Implement bounded streaming validation and temporary compilation**

Compile inside a unique temporary sibling directory. Reopen both indexes through `MappedLexicon`, create the generated checksum manifest, then atomically rename. On any thrown error close mappings and delete only the unique temporary directory. Never follow symlinks outside the selected package.

Run: `swift test --filter DictionaryPackImporterTests`

Expected: PASS for valid and invalid fixtures.

- [ ] **Step 3: Write failing tests for atomic install/update/cancel behavior**

```swift
func testFailedUpdatePreservesWorkingPackBytesAndEnabledState() async throws {
    let original = try await importValidPack(id: "dev.twigaswitcher.test")
    let before = try Data(contentsOf: original.englishIndexURL)
    await XCTAssertThrowsErrorAsync { try await importer.importPackage(at: corruptUpdate) }
    XCTAssertEqual(try Data(contentsOf: original.englishIndexURL), before)
    XCTAssertTrue(store.isEnabled(original.identifier))
}
```

Run: `swift test --filter DictionaryPackImporterTests/testFailedUpdatePreservesWorkingPackBytesAndEnabledState`

Expected: FAIL until replacement policy and atomic store behavior exist.

- [ ] **Step 4: Implement install/update/remove persistence and confirmation boundaries**

The store performs no deletion until its caller has confirmed. Tests call the post-confirmation method directly and verify it removes only the resolved pack directory. Enabled IDs persist atomically; a missing pack ID is ignored on reload.

Run: `swift test --filter DictionaryPackImporterTests`

Expected: PASS.

- [ ] **Step 5: Write failing catalog priority and concurrent swap tests**

Create real tiny mapped base/subject indexes. Verify longest phrase, subject flags, enabled/disabled behavior, and that concurrent readers observe only complete snapshots while 100 replacements alternate between two known catalogs.

Run: `swift test --filter LexiconCatalogTests`

Expected: FAIL because catalog snapshots are missing.

- [ ] **Step 6: Implement immutable snapshots and atomic publication**

Build snapshot arrays off-callback. Publish a single retained snapshot under a short lock; each lookup copies the current snapshot reference, releases the lock, then searches mapped indexes. Subject matches return `isSubjectTerm = true`; base matches do not. Prefix lookup uses the same enabled snapshot.

Run: `swift test --filter TwigaSwitcherLexiconTests`

Expected: PASS, including concurrent swap and longest phrase.

- [ ] **Step 7: Commit pack infrastructure**

```bash
git add Sources/TwigaSwitcherLexicon Tests/TwigaSwitcherLexiconTests
git commit -m "feat: add importable subject dictionaries"
```

---

### Task 5: Phrase-aware input buffering and punctuation conversion

**Files:**
- Create: `Sources/TwigaSwitcherCore/Input/PhraseBuffer.swift`
- Modify: `Sources/TwigaSwitcherCore/Input/InputEvent.swift`
- Modify: `Sources/TwigaSwitcherCore/Conversion/LayoutConverter.swift`
- Modify: `Sources/TwigaSwitcherCore/Correction/InputPipeline.swift`
- Delete after migration: `Sources/TwigaSwitcherCore/Input/WordBuffer.swift`
- Create: `Tests/TwigaSwitcherCoreTests/PhraseBufferTests.swift`
- Modify: `Tests/TwigaSwitcherCoreTests/LayoutConverterTests.swift`
- Modify: `Tests/TwigaSwitcherCoreTests/InputPipelineTests.swift`
- Delete after migration: `Tests/TwigaSwitcherCoreTests/WordBufferTests.swift`

**Interfaces:**
- Consumes: `CorrectionDecision.deferred` and `FrequencyLexicon` from Task 1.
- Produces: `BufferedCandidate(text:physicalKeyCount:tokenCount:)` suffixes, longest first.
- Produces: `PhraseBuffer.handle(_:) -> PhraseBufferResult` with explicit provisional punctuation and boundary resolution.
- Extends: `LayoutConverter` to preserve layout-neutral digits and `+ # - _ / \ @`, while continuing to map layout-dependent punctuation.

- [ ] **Step 1: Write failing phrase-window tests**

```swift
func testRetainsDeferredPrefixAndReturnsLongestPhraseWithSpaces() {
    var buffer = PhraseBuffer(maxTokens: 8, maxScalars: 128)
    feed("ьфсршту", to: &buffer)
    let first = buffer.handle(.boundary(" "))
    buffer.resolve(first, disposition: .deferForPhrase)
    feed("дуфктштп", to: &buffer)
    let candidates = decisionCandidates(buffer.handle(.boundary(" ")))
    XCTAssertEqual(candidates.first?.text, "ьфсршту дуфктштп")
    XCTAssertEqual(candidates.first?.physicalKeyCount, 16)
}
```

Also assert reset at 129 scalars/nine tokens, mixed script behavior, backspace across internal punctuation, and preservation of the most recent valid phrase suffix.

Run: `swift test --filter PhraseBufferTests`

Expected: FAIL because `PhraseBuffer` is missing.

- [ ] **Step 2: Implement the bounded rolling phrase buffer**

Store only buffered characters, physical key counts, token boundaries, and at most one provisional punctuation mark. Do not store application names or timestamps. `resolve(... .deferForPhrase)` retains the passed delimiter; unchanged non-prefix decisions discard text that cannot start a future phrase.

Run: `swift test --filter PhraseBufferTests`

Expected: PASS.

- [ ] **Step 3: Write failing conversion tests for neutral and layout-dependent symbols**

Use hand-derived literals for `юТУЕ → .NET`, `тщвуоы → node.js`, `С++ → C++`, digit preservation, and rejection of unsupported emoji/control scalars.

Run: `swift test --filter LayoutConverterTests`

Expected: FAIL for neutral punctuation/digits.

- [ ] **Step 4: Extend the converter minimally and make conversion tests green**

Each source still must contain a coherent Latin or Cyrillic letter script. Neutral characters may accompany it but cannot determine layout alone. Preserve title/all-caps behavior.

Run: `swift test --filter LayoutConverterTests`

Expected: PASS.

- [ ] **Step 5: Write failing pipeline tests for longest phrase and ambiguous period handling**

Test `.NET` at buffer start, `Node.js` inside a sentence, a sentence-ending period followed by a space, a deferred two-word wrong-layout phrase replaced as one plan, and a shorter suffix used when the longer phrase misses.

Run: `swift test --filter InputPipelineTests`

Expected: FAIL while the pipeline still uses `WordBuffer`.

- [ ] **Step 6: Migrate `InputPipeline` to phrase candidates**

At a boundary, evaluate candidate suffixes longest-first. A correction resets the window and emits a deletion count including already-passed internal spaces/punctuation but excluding the currently suppressed delimiter. A strict-prefix decision retains the bounded window. If no candidate corrects or defers, pass through and release stale text.

Run: `swift test --filter TwigaSwitcherCoreTests`

Expected: all core tests PASS.

- [ ] **Step 7: Commit phrase handling**

```bash
git add Sources/TwigaSwitcherCore Tests/TwigaSwitcherCoreTests
git commit -m "feat: recognize phrases and technical punctuation"
```

---

### Task 6: Replace `NSSpellChecker` in the live keyboard path

**Files:**
- Create: `Sources/TwigaSwitcherApp/SystemIntegration/LexiconService.swift`
- Modify: `Sources/TwigaSwitcherApp/SystemIntegration/KeyboardEventNormalizer.swift`
- Modify: `Sources/TwigaSwitcherApp/SystemIntegration/FocusedInputProcessor.swift`
- Modify: `Sources/TwigaSwitcherApp/SystemIntegration/KeyboardMonitor.swift`
- Modify: `Sources/TwigaSwitcherApp/Application/AppController.swift`
- Delete: `Sources/TwigaSwitcherApp/SystemIntegration/SystemLexicon.swift`
- Delete: `Sources/TwigaSwitcherCore/Detection/WordLexicon.swift`
- Delete: `Sources/TwigaSwitcherApp/Resources/en.txt`
- Delete: `Sources/TwigaSwitcherApp/Resources/ru.txt`
- Modify: `Tests/TwigaSwitcherAppTests/KeyboardEventNormalizerTests.swift`
- Modify: `Tests/TwigaSwitcherAppTests/FocusedInputProcessorTests.swift`
- Replace: `Tests/TwigaSwitcherAppTests/SystemLexiconTests.swift` with `LexiconServiceTests.swift`

**Interfaces:**
- Consumes: mapped bundled resources, catalog snapshots, phrase pipeline.
- Produces: `LexiconService.start() throws`, `currentSnapshot`, `reloadPacks() async`, and fatal/nonfatal diagnostics.
- Produces: `KeyboardMonitoring` callbacks for recent decision/correction changes needed by Task 7/8.

- [ ] **Step 1: Write failing service startup tests using real temporary mapped indexes**

Assert valid base resources start correction, missing/corrupt base resources return a fatal diagnostic and do not start the monitor, and a corrupt optional pack is disabled without hiding valid base dictionaries.

Run: `swift test --filter LexiconServiceTests`

Expected: FAIL because `LexiconService` is missing.

- [ ] **Step 2: Implement service loading and remove `SystemLexicon` fallback**

Load and validate base resources before enabling the event tap. Build the first immutable catalog snapshot, report optional-pack failures, and never instantiate `NSSpellChecker`.

Run: `swift test --filter LexiconServiceTests`

Expected: PASS.

- [ ] **Step 3: Write failing normalizer/processor tests for provisional punctuation and focus resets**

Assert Command/Control/Option still reset, period can remain provisional for `.NET`/`Node.js`, sentence punctuation resolves at the next boundary, focus identity is preserved across a deferred phrase, and application/mouse changes clear it.

Run: `swift test --filter KeyboardEventNormalizerTests && swift test --filter FocusedInputProcessorTests`

Expected: FAIL against the word-only normalizer/processor.

- [ ] **Step 4: Integrate phrase events and snapshots into the monitor**

The event callback performs only event normalization, focus snapshots, immutable catalog lookup, and event posting. Pack loading, checksum validation, JSON work, compilation, and normal file I/O remain outside it. Preserve Codex `AXGroup` support and all secure-field exclusions.

Run: `swift test --filter TwigaSwitcherAppTests`

Expected: all app tests PASS.

- [ ] **Step 5: Verify source-level removal through behavior, not grep**

Run a test fixture whose only valid words exist in mapped indexes and whose injected spell checker would trap if called; verify corrections still occur. Then delete obsolete miniature resources and tests.

Run: `swift test`

Expected: all tests PASS with no dependency on `NSSpellChecker` behavior.

- [ ] **Step 6: Commit live integration**

```bash
git add Sources/TwigaSwitcherApp Tests/TwigaSwitcherAppTests
git commit -m "feat: use mapped lexicons for live correction"
```

---

### Task 7: Persistent rules and safe Command-Z learning

**Files:**
- Create: `Sources/TwigaSwitcherApp/Learning/UserRuleStore.swift`
- Create: `Sources/TwigaSwitcherApp/Learning/UserRuleSnapshot.swift`
- Create: `Sources/TwigaSwitcherApp/Learning/LastCorrectionCoordinator.swift`
- Modify: `Sources/TwigaSwitcherApp/SystemIntegration/EventPoster.swift`
- Modify: `Sources/TwigaSwitcherApp/SystemIntegration/ReplacementExecutor.swift`
- Modify: `Sources/TwigaSwitcherApp/SystemIntegration/KeyboardEventNormalizer.swift`
- Modify: `Sources/TwigaSwitcherApp/SystemIntegration/KeyboardMonitor.swift`
- Create: `Tests/TwigaSwitcherAppTests/UserRuleStoreTests.swift`
- Create: `Tests/TwigaSwitcherAppTests/LastCorrectionCoordinatorTests.swift`
- Modify: `Tests/TwigaSwitcherAppTests/ReplacementExecutorTests.swift`

**Interfaces:**
- Consumes: rule contracts from Task 1 and focus identities from existing safety code.
- Produces: `UserRuleStore.loadSnapshot()`, `set(disposition:source:candidate:)`, `remove(_:)`, and `removeAll()`.
- Produces: `LastCorrectionCoordinator.record(_:)`, `invalidate(_:)`, and `handleCommandZ(currentFocus:) -> UndoLearningAction?`.
- Extends: `ReplacementExecutor.reverse(_:) -> ReplacementExecutionResult`.

- [ ] **Step 1: Write failing real-filesystem persistence tests**

Test round-trip, normalized duplicate replacement, malformed JSON quarantine/fresh snapshot, atomic-write failure preserving the old file, delete selected, and confirmed delete-all. Assert persisted JSON contains only schema/rules/dispositions and no context, app ID, or timestamp.

Run: `swift test --filter UserRuleStoreTests`

Expected: FAIL because the store is missing.

- [ ] **Step 2: Implement versioned atomic JSON persistence**

Write to a unique sibling temporary file, synchronize, and replace atomically. Publish a new immutable in-memory snapshot only after a successful write; on failure retain the previous disk snapshot and let the controller show a diagnostic.

Run: `swift test --filter UserRuleStoreTests`

Expected: PASS.

- [ ] **Step 3: Write failing last-correction lifetime and ordinary undo tests**

Use an injected monotonic clock. Verify Command-Z within ten seconds and identical focus produces a reversal plus `.never`; 10.001 seconds, a printable key, mouse click, app activation, focus change, failed replacement, or second correction invalidates it. When invalid, the event disposition is pass-through.

Run: `swift test --filter LastCorrectionCoordinatorTests`

Expected: FAIL because the coordinator is missing.

- [ ] **Step 4: Implement bounded correction state and reversal planning**

Keep exactly one in-memory correction. The reverse plan deletes the corrected text plus its already-posted delimiter, restores source plus delimiter, then selects the original layout. Persist `.never` only after text reversal succeeds; a partial reversal reports an error and does not learn a rule.

Run: `swift test --filter LastCorrectionCoordinatorTests && swift test --filter ReplacementExecutorTests`

Expected: PASS.

- [ ] **Step 5: Integrate Command-Z and manual rule creation with the monitor**

Normalize Command-Z as its own event only when no other unsafe modifier is present. Ask the coordinator before resetting; consume only a successful safe reversal. Publish the latest considered source/candidate pair to `AppController` for menu actions, but retain no list/history.

Run: `swift test --filter TwigaSwitcherAppTests`

Expected: all app tests PASS, including normal Command-Z pass-through.

- [ ] **Step 6: Commit learning behavior**

```bash
git add Sources/TwigaSwitcherApp Tests/TwigaSwitcherAppTests
git commit -m "feat: learn local correction rules"
```

---

### Task 8: Native dictionary and rule management UI

**Files:**
- Create: `Sources/TwigaSwitcherApp/DictionaryUI/DictionaryManagerModel.swift`
- Create: `Sources/TwigaSwitcherApp/DictionaryUI/DictionaryManagerView.swift`
- Create: `Sources/TwigaSwitcherApp/Learning/RulesManagerModel.swift`
- Create: `Sources/TwigaSwitcherApp/Learning/RulesManagerView.swift`
- Create: `Sources/TwigaSwitcherApp/DictionaryUI/DictionaryPackageType.swift`
- Modify: `Sources/TwigaSwitcherApp/Application/AppController.swift`
- Modify: `Sources/TwigaSwitcherApp/Application/TwigaSwitcherMain.swift`
- Modify: `scripts/Info.plist`
- Create: `Tests/TwigaSwitcherAppTests/DictionaryManagerModelTests.swift`
- Create: `Tests/TwigaSwitcherAppTests/RulesManagerModelTests.swift`
- Modify: `Tests/TwigaSwitcherAppTests/AppStateTests.swift`

**Interfaces:**
- Consumes: `DictionaryPackStore`, importer, catalog reload, rule store, and latest pair from Tasks 4/7.
- Produces: `DictionaryManagerModel` async import/toggle/remove operations and published rows/status.
- Produces: `RulesManagerModel` list/delete/delete-all operations.
- Produces: menu actions `Dictionaries…`, `Rules…`, dynamic always/never pair, and undo/remember.

- [ ] **Step 1: Write failing dictionary model tests**

Use real temporary package directories and indexes. Assert base rows cannot toggle/remove; Computer Terms defaults enabled; imported rows can toggle; canceling an import changes nothing; invalid import exposes the precise validation error; removal calls the destructive store only after the model's confirmation closure returns true.

Run: `swift test --filter DictionaryManagerModelTests`

Expected: FAIL because the model is missing.

- [ ] **Step 2: Implement dictionary model and native view**

Declare `dev.twigaswitcher.dictionary` as a package UTI whose filename extension is `.layoutdict` in `Info.plist` and expose it as `UTType.layoutDictionary`. Use `fileImporter` for that type, a list with base/subject sections, toggles, metadata details, import/update/remove buttons, progress, and a license notice action. Compilation runs in a detached task with bounded priority; UI publication and catalog swap happen on `MainActor`.

Run: `swift test --filter DictionaryManagerModelTests`

Expected: PASS.

- [ ] **Step 3: Write failing rules model and dynamic menu tests**

Assert list ordering is deterministic, deletion refreshes the snapshot, delete-all requires confirmation, a latest unchanged pair enables both manual actions, selecting one persists it and updates the live detector, and losing the latest pair disables/hides pair-specific menu commands.

Run: `swift test --filter RulesManagerModelTests && swift test --filter AppStateTests`

Expected: FAIL until models/controller actions exist.

- [ ] **Step 4: Implement rules view and menu commands**

Add SwiftUI `Window` scenes with stable IDs, open them through `openWindow`, and keep the menu-bar extra lightweight. Escape pair display text and truncate labels without truncating stored rules. Confirmation dialogs name only the pack/rule being removed.

Run: `swift test --filter TwigaSwitcherAppTests`

Expected: all app tests PASS.

- [ ] **Step 5: Build the release app to catch SwiftUI scene/resource integration errors**

Run: `zsh scripts/build-app.sh`

Expected: `build/TwigaSwitcher.app` builds, plist validation succeeds, and signing succeeds.

- [ ] **Step 6: Commit UI management**

```bash
git add Sources/TwigaSwitcherApp Tests/TwigaSwitcherAppTests
git commit -m "feat: manage dictionaries and learned rules"
```

---

### Task 9: Computer Terms pack, benchmarks, documentation, and delivery

**Files:**
- Create: `Dictionaries/Computer Terms.layoutdict/manifest.json`
- Create: `Dictionaries/Computer Terms.layoutdict/entries.tsv`
- Create: `Dictionaries/Computer Terms.layoutdict/NOTICE.txt`
- Create: `Sources/TwigaSwitcherLexicon/Resources/Lexicons/ComputerTerms/manifest.json`
- Create: generated `en.lsidx` and `ru.lsidx` under that resource directory
- Create: `Sources/LexiconBenchmark/main.swift`
- Create: `scripts/benchmark-lexicons.sh`
- Create: `Tests/TwigaSwitcherAppTests/ComputerTermsResourceTests.swift`
- Modify: `Package.swift`
- Modify: `README.md`

**Interfaces:**
- Consumes: subject pack compiler/import format and mapped catalog.
- Produces: enabled-by-default built-in pack `dev.twigaswitcher.dictionary.computer-terms`.
- Produces: `LexiconBenchmark <en-index> <ru-index> --lookups 10000 --budget-ms 250` reporting total, median, p99, hit count, miss count, mapped bytes, and resident-memory delta.

- [ ] **Step 1: Write failing required-term resource tests**

```swift
func testComputerTermsPackCoversRequiredWordsPhrasesAndPunctuation() throws {
    let pack = try BundledLexiconResources.loadComputerTerms(bundle: .module)
    for term in ["kubernetes", "typescript", "node.js", ".net", "c++", "postgresql"] {
        XCTAssertTrue(pack.lookup(term, language: .english).isSubjectTerm, term)
    }
    for term in ["машинное обучение", "база данных"] {
        XCTAssertTrue(pack.lookup(term, language: .russian).isSubjectTerm, term)
    }
}
```

Run: `swift test --filter ComputerTermsResourceTests`

Expected: FAIL because the pack resource is absent.

- [ ] **Step 2: Author, compile, and validate the Computer Terms pack**

Include reviewed operating-system, programming-language, database, networking, cloud, development-tool, hardware, security, and AI terminology in both languages. Use a documented project-authored scoring rubric; do not copy an unattributed third-party list. Compile with the same CLI used for imports and include source TSV for reviewability.

Run: `swift run LexiconCompiler compile-tsv --input "Dictionaries/Computer Terms.layoutdict/entries.tsv" --output-directory Sources/TwigaSwitcherLexicon/Resources/Lexicons/ComputerTerms --manifest "Dictionaries/Computer Terms.layoutdict/manifest.json"`

Expected: compilation and verification succeed.

Run: `swift test --filter ComputerTermsResourceTests`

Expected: PASS.

- [ ] **Step 3: Write the failing benchmark acceptance script**

The script must execute the release benchmark against bundled indexes, parse its exit code rather than grepping source, and fail for a deliberately injected zero-millisecond budget.

Run: `zsh scripts/benchmark-lexicons.sh --self-test`

Expected: FAIL because the benchmark executable is missing.

- [ ] **Step 4: Implement and run the release benchmark**

Use a deterministic mixed set of common hits, rare hits, prefixes, and misses. Warm every mapped index before timing. Measure lookup only, not process startup or resource validation. Report resident-memory delta with Mach `task_info` and verify it remains below mapped bytes plus a fixed 8 MiB process allowance, which catches accidental parallel `Set`/dictionary materialization. Exit nonzero when 10,000 total lookups exceed 250 ms or the memory allowance is exceeded.

Run: `zsh scripts/benchmark-lexicons.sh`

Expected: PASS and print total/median/p99 below budget.

- [ ] **Step 5: Update documentation and privacy statements**

Document dictionary management, `.layoutdict` schema with examples, Command-Z learning, manual rules, Application Support paths, license notices, regeneration commands, benchmark command, and the fact that rule pairs—but not surrounding text/history—are persisted locally.

- [ ] **Step 6: Run full automated verification from a clean build state**

Run:

```bash
swift test
zsh scripts/test-generate-base-lexicons.sh
zsh scripts/benchmark-lexicons.sh
zsh scripts/test-build-app-signing.sh
codesign --verify --deep --strict build/TwigaSwitcher.app
plutil -lint build/TwigaSwitcher.app/Contents/Info.plist
git diff --check
```

Expected: every command exits 0; all XCTest cases pass; time and memory benchmarks stay within budget; signature and plist validate. `build-app.sh` copies both SwiftPM resource bundles (`TwigaSwitcher_TwigaSwitcherApp.bundle` and `TwigaSwitcher_TwigaSwitcherLexicon.bundle`) into the app resources before signing.

- [ ] **Step 7: Perform the manual smoke matrix**

In TextEdit, Codex, and a browser field verify:

- several ordinary words not present in the old miniature lists in both directions;
- `Node.js`, `.NET`, `C++`, and a two-word Russian/English term;
- an ambiguous valid word remains untouched;
- Command-Z reverses the immediately preceding correction and learns `never`;
- ordinary Command-Z still reaches the host app after typing/focus change/timeout;
- manual `always` and `never` take effect without restart;
- disabling Computer Terms removes its boost; re-enabling restores it;
- import/toggle/remove of a temporary custom pack;
- Terminal and a secure password field remain untouched.

Expected: all cases match the specification with no perceptible typing pause.

- [ ] **Step 8: Commit final resources and verification tooling**

```bash
git add Package.swift Dictionaries Sources scripts README.md Tests
git commit -m "feat: ship computer terms and lexicon benchmarks"
```

- [ ] **Step 9: Apply the verification-before-completion gate, review the entire branch, and merge**

Read `superpowers:verification-before-completion`, rerun its required fresh evidence, inspect `git diff main...HEAD`, and resolve every review finding with a new failing test first. When the branch is clean and verified:

```bash
git switch main
git merge --no-ff feature/frequency-lexicons -m "merge: frequency lexicons and learning"
git status --short --branch
```

Expected: merge succeeds directly into `main`, the working tree is clean, and no `develop` branch is involved.
