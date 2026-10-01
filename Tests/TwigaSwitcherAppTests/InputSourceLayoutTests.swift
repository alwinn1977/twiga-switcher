import Carbon
import XCTest
import TwigaSwitcherCore
@testable import TwigaSwitcherApp

final class InputSourceLayoutTests: XCTestCase {
    private struct TestLexicon: FrequencyLexicon {
        func lookup(_ text: String, language: Language) -> LexiconMatch {
            let words = language == .english ? ["hello", "yes"] : ["привет", "да", "бюджет"]
            return LexiconMatch(score: words.contains(text) ? 5_000 : nil,
                                isSubjectTerm: false, isStrictPrefix: false)
        }
    }

    func testPhysicalTypingThroughSystemTablesAndPipeline() throws {
        let focus = FocusSnapshot(identity: .init(processID: 42, elementHash: 1))
        for english in ["ABC", "USInternational-PC", "British"] {
            for russian in ["Russian", "RussianWin"] {
                let tables = KeyboardLayoutTables(english: try table(english), russian: try table(russian))
                let normalizer = KeyboardEventNormalizer(syntheticMarker: 123)
                var processor = FocusedInputProcessor(pipeline: InputPipeline(
                    converter: tables.converter,
                    detector: LanguageDetector(lexicon: TestLexicon(), rules: NoUserCorrectionRules())))
                var active = KeyboardLayout.english
                var editor = ""
                let phrases: [(String, KeyboardLayout)] = [
                    ("привет ", .russian), ("hello ", .english), ("да? ", .russian),
                    ("yes. ", .english), ("бюджет ", .russian)
                ]
                for (phrase, intended) in phrases {
                    let target = intended == .english ? tables.english : tables.russian
                    for character in phrase {
                        let key = try XCTUnwrap(target.keys.sorted().first {
                            target[$0] == String(character) && tables.english[$0] != nil && tables.russian[$0] != nil
                        })
                        let raw = try XCTUnwrap(tables.text(keyCode: key % 128, shifted: key >= 128, layout: active))
                        let event = normalizer.normalize(.init(text: raw, keyCode: key % 128,
                            flags: key >= 128 ? .maskShift : [], marker: 0), tables: tables)
                        switch processor.handle(event, focus: focus) {
                        case .passThrough: editor += raw
                        case let .replace(plan):
                            XCTAssertLessThanOrEqual(plan.deleteKeyCount, editor.count)
                            editor = String(editor.dropLast(plan.deleteKeyCount)) + plan.replacement + plan.delimiter
                            active = plan.targetLayout
                        }
                    }
                }
                XCTAssertEqual(editor, phrases.map(\.0).joined(), "\(english)/\(russian)")
            }
        }
    }

    private func table(_ name: String) throws -> [UInt16: String] {
        let filter = [kTISPropertyInputSourceID as String: "com.apple.keylayout." + name] as CFDictionary
        let list = TISCreateInputSourceList(filter, true).takeRetainedValue() as! [TISInputSource]
        return InputSourceManager.keyTable(for: try XCTUnwrap(list.first, name))
    }

    func testCommonSystemLayoutsConvertPhysicalKeysInBothDirections() throws {
        for english in ["US", "ABC", "USInternational-PC", "USExtended", "British", "British-PC", "Canadian", "Irish"] {
            for russian in ["Russian", "RussianWin"] {
                let tables = KeyboardLayoutTables(english: try table(english), russian: try table(russian))
                XCTAssertEqual(tables.converter.convert("ghbdtn")?.text, "привет", "\(english)/\(russian)")
                XCTAssertEqual(tables.converter.convert("руддщ")?.text, "hello", "\(english)/\(russian)")
                XCTAssertEqual(tables.converter.convert("GHBDTN")?.text, "ПРИВЕТ", "\(english)/\(russian)")
                // ё is on different physical positions in Mac and PC Russian.
                let key = try XCTUnwrap(tables.russian.keys.sorted().first(where: { tables.russian[$0] == "ё" && tables.english[$0] != nil }))
                let raw = try XCTUnwrap(tables.english[key])
                XCTAssertEqual(tables.converter.convert(raw + "k")?.text, "ёл", "\(english)/\(russian)")
            }
        }
    }

    func testMacAndPCPunctuationUsesActualTargetLayout() throws {
        let normalizer = KeyboardEventNormalizer(syntheticMarker: 123)
        for russian in ["Russian", "RussianWin"] {
            let tables = KeyboardLayoutTables(english: try table("ABC"), russian: try table(russian))
            for punctuation in [".", ",", "?", ";", ":"] {
                let key = try XCTUnwrap(tables.russian.keys.sorted().first(where: { $0 < 256 && tables.russian[$0] == punctuation }))
                let english = try XCTUnwrap(tables.english[key])
                guard english != punctuation else { continue }
                XCTAssertEqual(normalizer.normalize(.init(text: english, keyCode: key % 128,
                    flags: key >= 128 ? .maskShift : [], marker: 0), tables: tables),
                    .punctuation(text: english, english: english, russian: punctuation))
            }
        }
    }

    func testSelectedVariantIsPreferredToCanonicalUS() {
        let sources = [InputSourceDescriptor(id: "com.apple.keylayout.US", languages: ["en"]),
                       .init(id: "com.apple.keylayout.British", languages: ["en"])]
        XCTAssertEqual(InputSourceResolver.resolve(.english, from: sources, preferredID: sources[1].id), sources[1])
    }

    func testPhysicalNormalizationHandlesStalePayloadCaseAndPunctuation() throws {
        let normalizer = KeyboardEventNormalizer(syntheticMarker: 123)
        let tables = KeyboardLayoutTables(english: try table("ABC"), russian: try table("RussianWin"))
        let cases: [(String, UInt16, CGEventFlags, KeyboardLayout, InputEvent)] = [
            ("п", 5, [], .english, .character("g")),
            ("g", 5, [], .russian, .character("п")),
            ("G", 5, .maskShift, .russian, .character("П")),
            ("G", 5, .maskAlphaShift, .russian, .character("П")),
            ("/", 44, .maskAlphaShift, .russian, .punctuation(text: ".", english: "/", russian: ".")),
            ("?", 44, .maskShift, .russian, .punctuation(text: ",", english: "?", russian: ",")),
            ("", 5, [], .english, .reset),
            ("é", 14, [], .english, .character("é")), // Composed text isn't a stale layout glyph.
            ("snippet", 0, [], .russian, .reset),
            ("g", 5, .maskCommand, .russian, .reset)
        ]
        for (text, key, flags, layout, expected) in cases {
            XCTAssertEqual(normalizer.normalize(.init(text: text, keyCode: key, flags: flags, marker: 0),
                                                 tables: tables, currentLayout: layout), expected)
        }
        XCTAssertEqual(normalizer.normalize(.init(text: "g", keyCode: 5, flags: [], marker: 123),
                                             tables: tables, currentLayout: .russian), .synthetic)
        // Unicode insertion from another process supplies no physical layout.
        XCTAssertEqual(normalizer.normalize(.init(text: "g", keyCode: 0, flags: [], marker: 0),
                                             tables: tables), .character("g"))
    }

    func testDeadKeyDoesNotCountAsInsertedText() throws {
        let normalizer = KeyboardEventNormalizer(syntheticMarker: 123)
        let tables = KeyboardLayoutTables(english: try table("USInternational-PC"), russian: try table("RussianWin"))
        // International dead keys insert nothing until the composition completes.
        // Treating their display glyph as inserted text would over-delete on force.
        for key: UInt16 in [39, 50] {
            XCTAssertEqual(normalizer.normalize(.init(text: "", keyCode: key, flags: [], marker: 0),
                                                 tables: tables, currentLayout: .english), .reset)
        }
        XCTAssertEqual(normalizer.normalize(.init(text: "è", keyCode: 14, flags: [], marker: 0),
                                             tables: tables, currentLayout: .english), .character("è"))
    }
}
