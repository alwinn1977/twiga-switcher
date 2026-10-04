import ApplicationServices
import Foundation
import TwigaSwitcherCore

struct FocusedTextState {
    let value: String
    let selection: NSRange
}

enum FocusedTextReadResult {
    case unavailable
    case failed
    case value(FocusedTextState)
}

enum FocusedTextWriteResult {
    case written
    case rejected
    case uncertain
}

protocol FocusedTextEditing {
    func read(_ focus: FocusSnapshot) -> FocusedTextReadResult
    func setValue(_ value: String, in focus: FocusSnapshot) -> FocusedTextWriteResult
    func setSelection(_ selection: NSRange, in focus: FocusSnapshot) -> Bool
}

enum FocusedTextReplacementResult {
    case replaced
    case failedBeforeMutation
    case partialFailure
}

struct SpotlightTextReplacer {
    private let editor: any FocusedTextEditing

    init() { editor = AccessibilityFocusedTextEditor() }
    init(editor: any FocusedTextEditing) { self.editor = editor }

    func replace(_ plan: ReplacementPlan, focus: FocusSnapshot?, sourceText: String? = nil) -> FocusedTextReplacementResult? {
        guard let focus, focus.isSpotlightSearch else { return nil }
        let state: FocusedTextState
        switch editor.read(focus) {
        case .unavailable: return nil // Preserve explicit application-level correction modes.
        case .failed: return .failedBeforeMutation
        case let .value(value): state = value
        }
        guard plan.deleteKeyCount >= 0,
              state.selection.location >= 0, state.selection.length >= 0,
              state.selection.location <= state.value.utf16.count,
              state.selection.length <= state.value.utf16.count - state.selection.location,
              let selection = Range(state.selection, in: state.value),
              selection.isEmpty || selection.upperBound == state.value.endIndex else {
            return .failedBeforeMutation
        }

        // Spotlight may select an inline completion after the typed query. A
        // Backspace consumes that selection before deleting any source letters.
        // Replace the source and completion together, preserving the query prefix.
        var sourceCount = plan.deleteKeyCount
        if let sourceText, !sourceText.isEmpty {
            let prefix = state.value[..<selection.lowerBound]
            let bufferedDelimiterCount = max(0, plan.deleteKeyCount - sourceText.count)
            guard bufferedDelimiterCount <= plan.delimiter.count else { return .failedBeforeMutation }
            let bufferedSource = sourceText + plan.delimiter.prefix(bufferedDelimiterCount)
            if !plan.delimiter.isEmpty, prefix.hasSuffix(sourceText + plan.delimiter) {
                sourceCount = sourceText.count + plan.delimiter.count
            } else if prefix.hasSuffix(bufferedSource) {
                // Include punctuation already buffered before the triggering key.
                sourceCount = bufferedSource.count
            } else if plan.delimiter.isEmpty, sourceText.count - 1 == plan.deleteKeyCount,
                      prefix.hasSuffix(sourceText.dropLast()) {
                sourceCount = plan.deleteKeyCount
            } else {
                return .failedBeforeMutation
            }
        }
        var start = selection.lowerBound
        for _ in 0..<sourceCount {
            guard start > state.value.startIndex else { return .failedBeforeMutation }
            start = state.value.index(before: start)
        }
        let insertion = plan.replacement + plan.delimiter
        let caret = state.value[..<start].utf16.count + insertion.utf16.count
        var updated = state.value
        updated.replaceSubrange(start..<selection.upperBound, with: insertion)
        switch editor.setValue(updated, in: focus) {
        case .written: break
        case .rejected: return .failedBeforeMutation
        case .uncertain: return .partialFailure
        }
        guard editor.setSelection(.init(location: caret, length: 0), in: focus) else { return .partialFailure }
        return .replaced
    }
}

private struct AccessibilityFocusedTextEditor: FocusedTextEditing {
    func read(_ focus: FocusSnapshot) -> FocusedTextReadResult {
        guard let element = focus.identity.accessibilityElement else { return .unavailable }
        guard isSettable(kAXValueAttribute, in: element),
              isSettable(kAXSelectedTextRangeAttribute, in: element) else { return .failed }
        var value: CFTypeRef?
        var selectedRange: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value) == .success,
              let text = value as? String,
              AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &selectedRange) == .success,
              let selectedRange, CFGetTypeID(selectedRange) == AXValueGetTypeID() else { return .failed }
        let axRange = unsafeDowncast(selectedRange as AnyObject, to: AXValue.self)
        var range = CFRange()
        guard AXValueGetType(axRange) == .cfRange,
              AXValueGetValue(axRange, .cfRange, &range), range.location >= 0, range.length >= 0 else { return .failed }
        return .value(.init(value: text, selection: .init(location: range.location, length: range.length)))
    }

    func setValue(_ value: String, in focus: FocusSnapshot) -> FocusedTextWriteResult {
        guard let element = focus.identity.accessibilityElement else { return .rejected }
        switch AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, value as CFString) {
        case .success: return .written
        // A timeout can arrive after the target has already changed its value.
        // Do not replay the original key or retry a keyboard replacement then.
        case .cannotComplete, .failure: return .uncertain
        default: return .rejected
        }
    }

    func setSelection(_ selection: NSRange, in focus: FocusSnapshot) -> Bool {
        guard let element = focus.identity.accessibilityElement else { return false }
        var range = CFRange(location: selection.location, length: selection.length)
        guard let value = AXValueCreate(.cfRange, &range) else { return false }
        return AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, value) == .success
    }

    private func isSettable(_ attribute: String, in element: AXUIElement) -> Bool {
        var settable = DarwinBoolean(false)
        return AXUIElementIsAttributeSettable(element, attribute as CFString, &settable) == .success && settable.boolValue
    }
}
