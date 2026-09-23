import CoreGraphics
import Foundation
import LayoutSwitcherCore
import LayoutSwitcherLexicon
@testable import LayoutSwitcherApp

enum TypingMode {
    case automatic
    case manualAtScriptChanges
}

struct TypedWord {
    let intended: String
    let raw: String
    let layoutBefore: KeyboardLayout
    let layoutAfter: KeyboardLayout
    let corrected: Bool
}

struct CorrectionRecord {
    let layoutBefore: KeyboardLayout
    let layoutAfter: KeyboardLayout
    let source: String
    let replacement: String
}

struct TypingTrace {
    let editorText: String
    let linePrefixes: [String]
    let layoutSelections: [KeyboardLayout]
    let manualSelections: [KeyboardLayout]
    let automaticSelections: [KeyboardLayout]
    let words: [TypedWord]
    let corrections: [CorrectionRecord]
    let firstDivergence: String
}

private final class VirtualEditor: EventPosting, InputSourceManaging {
    var text = ""
    var layout: KeyboardLayout
    var manualSelections: [KeyboardLayout] = []
    var automaticSelections: [KeyboardLayout] = []
    var corrections: [CorrectionRecord] = []
    var isAvailable: Bool { true }

    private var removedText: String?
    private var replacementText: String?
    private var layoutBeforeReplacement: KeyboardLayout?

    init(layout: KeyboardLayout) { self.layout = layout }

    func postBackspaces(count: Int) -> Bool {
        guard count <= text.count else { return false }
        layoutBeforeReplacement = layout
        removedText = String(text.suffix(count))
        replacementText = nil
        for _ in 0..<count { text.removeLast() }
        return true
    }

    func postUnicode(_ value: String) -> Bool {
        if replacementText == nil { replacementText = value }
        text += value
        return true
    }

    func select(_ target: KeyboardLayout) -> Bool {
        if let source = removedText,
           let replacement = replacementText,
           let before = layoutBeforeReplacement {
            corrections.append(.init(
                layoutBefore: before,
                layoutAfter: target,
                source: source,
                replacement: replacement
            ))
        }
        removedText = nil
        replacementText = nil
        layoutBeforeReplacement = nil
        layout = target
        automaticSelections.append(target)
        return true
    }

    func selectManually(_ target: KeyboardLayout) {
        layout = target
        manualSelections.append(target)
    }
}

private struct StableTypingFocus: FocusSnapshotProviding {
    func snapshot() -> FocusSnapshot? {
        FocusSnapshot(identity: .init(processID: 4242, elementHash: 8080))
    }
}

private enum TypingToken {
    case word(String, KeyboardLayout)
    case separator(String)
}

enum TypingSessionError: Error {
    case unsupportedCharacter(Character)
    case eventCreationFailed
}

final class TypingSessionDriver {
    private let temporaryRoot: URL
    private let editor: VirtualEditor
    private let monitor: KeyboardMonitor
    private let source: CGEventSource

    init(initialLayout: KeyboardLayout) throws {
        temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("layoutswitcher-typing-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)

        let defaults = UserDefaults(suiteName: "layoutswitcher-typing-\(UUID().uuidString)")!
        defaults.register(defaults: ["computerTermsDictionaryEnabled": true])
        let service = LexiconService(
            baseLoader: { try BundledLexiconResources.loadBase() },
            packsRootURL: temporaryRoot.appendingPathComponent("dictionaries", isDirectory: true),
            computerTermsLoader: { try BundledLexiconResources.loadComputerTerms() },
            computerTermsSettings: ComputerTermsSettings(defaults: defaults)
        )
        try service.start()
        let rules = try UserRuleStore(fileURL: temporaryRoot.appendingPathComponent("rules.json"))
        editor = VirtualEditor(layout: initialLayout)
        monitor = KeyboardMonitor(
            lexiconService: service,
            ruleStore: rules,
            focusProvider: StableTypingFocus(),
            executor: ReplacementExecutor(eventPoster: editor, inputSources: editor),
            hotkeys: .defaults,
            soundEnabled: false
        )
        guard let eventSource = CGEventSource(stateID: .hidSystemState) else {
            throw TypingSessionError.eventCreationFailed
        }
        source = eventSource
    }

    deinit {
        try? FileManager.default.removeItem(at: temporaryRoot)
    }

    func type(
        _ expected: String,
        mode: TypingMode,
        echoSyntheticEvents: Bool = false
    ) throws -> TypingTrace {
        let tokens = Self.tokenize(expected)
        var words: [TypedWord] = []
        var pending: (intended: String, raw: String, before: KeyboardLayout, automaticCount: Int)?
        var linePrefixes: [String] = []
        var expectedPrefix = ""
        var firstDivergence = "none"
        var line = 1
        var lastKeyCode: CGKeyCode = 0
        var lastRaw = ""
        var lastLayout = editor.layout

        for token in tokens {
            switch token {
            case let .word(word, language):
                if mode == .manualAtScriptChanges && editor.layout != language {
                    editor.selectManually(language)
                }
                let before = editor.layout
                let selectionCount = editor.automaticSelections.count
                var raw = ""
                for character in word {
                    let stroke = try Self.stroke(for: character, language: language)
                    let rendered = PhysicalTypingKeys.render(stroke, in: editor.layout)
                    try send(stroke, rendered: rendered, echoSyntheticEvents: echoSyntheticEvents)
                    raw += rendered
                    lastKeyCode = stroke.keyCode
                    lastRaw = rendered
                    lastLayout = before
                }
                pending = (word, raw, before, selectionCount)
                expectedPrefix += word

            case let .separator(separator):
                for character in separator {
                    let layout = editor.layout
                    let stroke = try Self.stroke(for: character, language: layout)
                    let rendered = PhysicalTypingKeys.render(stroke, in: layout)
                    try send(stroke, rendered: rendered, echoSyntheticEvents: echoSyntheticEvents)
                    lastKeyCode = stroke.keyCode
                    lastRaw = rendered
                    lastLayout = layout
                    expectedPrefix.append(character)
                    if character == "\n" {
                        linePrefixes.append(editor.text)
                        if editor.text != expectedPrefix && firstDivergence == "none" {
                            firstDivergence = "line \(line), keycode \(lastKeyCode), layout \(lastLayout), raw \(lastRaw.debugDescription), expected \(expectedPrefix.debugDescription), actual \(editor.text.debugDescription)"
                        }
                        line += 1
                    }
                }
                if let word = pending {
                    words.append(.init(
                        intended: word.intended,
                        raw: word.raw,
                        layoutBefore: word.before,
                        layoutAfter: editor.layout,
                        corrected: editor.automaticSelections.count != word.automaticCount
                    ))
                    pending = nil
                }
            }
        }
        if let word = pending {
            words.append(.init(
                intended: word.intended,
                raw: word.raw,
                layoutBefore: word.before,
                layoutAfter: editor.layout,
                corrected: editor.automaticSelections.count != word.automaticCount
            ))
        }
        return .init(
            editorText: editor.text,
            linePrefixes: linePrefixes,
            layoutSelections: editor.manualSelections + editor.automaticSelections,
            manualSelections: editor.manualSelections,
            automaticSelections: editor.automaticSelections,
            words: words,
            corrections: editor.corrections,
            firstDivergence: firstDivergence
        )
    }

    private func send(_ stroke: PhysicalStroke, rendered: String, echoSyntheticEvents: Bool) throws {
        guard let event = CGEvent(keyboardEventSource: source, virtualKey: stroke.keyCode, keyDown: true) else {
            throw TypingSessionError.eventCreationFailed
        }
        event.flags = stroke.flags
        let units = Array(rendered.utf16)
        units.withUnsafeBufferPointer {
            event.keyboardSetUnicodeString(stringLength: $0.count, unicodeString: $0.baseAddress)
        }
        let correctionCount = editor.corrections.count
        if monitor.handle(type: .keyDown, event: event) != nil {
            editor.text += rendered
        }
        if echoSyntheticEvents && editor.corrections.count > correctionCount {
            guard let echo = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true) else {
                throw TypingSessionError.eventCreationFailed
            }
            echo.setIntegerValueField(.eventSourceUserData, value: EventPoster.syntheticMarker)
            let replacement = editor.corrections.last!.replacement
            let echoUnits = Array(replacement.prefix(8).utf16)
            echoUnits.withUnsafeBufferPointer {
                echo.keyboardSetUnicodeString(stringLength: $0.count, unicodeString: $0.baseAddress)
            }
            _ = monitor.handle(type: .keyDown, event: echo)
        }
    }

    private static func stroke(for character: Character, language: KeyboardLayout) throws -> PhysicalStroke {
        guard let stroke = PhysicalTypingKeys.stroke(for: character, language: language) else {
            throw TypingSessionError.unsupportedCharacter(character)
        }
        return stroke
    }

    private static func tokenize(_ text: String) -> [TypingToken] {
        let characters = Array(text)
        var tokens: [TypingToken] = []
        var index = 0
        while index < characters.count {
            let character = characters[index]
            let leadingDot = character == "." && index + 2 < characters.count
                && script(of: characters[index + 1]) == .english
                && script(of: characters[index + 2]) == .english
                && String(characters[index + 1]) == String(characters[index + 1]).uppercased()
            if let language = script(of: character) ?? (leadingDot ? .english : nil) {
                var word = ""
                if leadingDot { word.append("."); index += 1 }
                while index < characters.count {
                    let current = characters[index]
                    if script(of: current) == language {
                        word.append(current)
                        index += 1
                    } else if current == ".", language == .english,
                              index + 1 < characters.count,
                              script(of: characters[index + 1]) == .english {
                        word.append(current)
                        index += 1
                    } else if current == "+", language == .english,
                              (word.last == "+" || index + 1 < characters.count && characters[index + 1] == "+") {
                        word.append(current)
                        index += 1
                    } else {
                        break
                    }
                }
                if !word.isEmpty {
                    tokens.append(.word(word, language))
                    continue
                }
            }
            var separator = ""
            while index < characters.count && script(of: characters[index]) == nil {
                let current = characters[index]
                let isLeadingDot = current == "." && index + 2 < characters.count
                    && script(of: characters[index + 1]) == .english
                    && script(of: characters[index + 2]) == .english
                    && String(characters[index + 1]) == String(characters[index + 1]).uppercased()
                if isLeadingDot { break }
                separator.append(current)
                index += 1
            }
            if !separator.isEmpty { tokens.append(.separator(separator)) }
        }
        return tokens
    }

    private static func script(of character: Character) -> KeyboardLayout? {
        guard let scalar = character.unicodeScalars.first, character.unicodeScalars.count == 1 else { return nil }
        switch scalar.value {
        case 0x0041...0x005A, 0x0061...0x007A: return .english
        case 0x0410...0x044F, 0x0401, 0x0451: return .russian
        default: return nil
        }
    }
}
