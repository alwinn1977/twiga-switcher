import Carbon
import TwigaSwitcherCore

public struct InputSourceDescriptor: Equatable, Sendable {
    public let id: String
    public let languages: [String]

    public init(id: String, languages: [String]) {
        self.id = id
        self.languages = languages
    }
}

public enum InputSourceResolver {
    public static func language(
        of source: InputSourceDescriptor,
        configuration: KeyboardLayoutsConfiguration = .bundled
    ) -> KeyboardLayout? {
        if configuration.russian.inputSourceIDs.contains(source.id) { return .russian }
        if configuration.english.inputSourceIDs.contains(source.id) { return .english }
        // Subsequent languages describe script coverage, not the layout's language.
        let primary = source.languages.first?.lowercased().split(whereSeparator: { $0 == "-" || $0 == "_" }).first
        if primary == Substring(configuration.russian.primaryLanguage) { return .russian }
        if primary == Substring(configuration.english.primaryLanguage) { return .english }
        return nil
    }

    public static func resolve(
        _ layout: KeyboardLayout,
        from sources: [InputSourceDescriptor],
        preferredID: String? = nil,
        configuration: KeyboardLayoutsConfiguration = .bundled
    ) -> InputSourceDescriptor? {
        let candidates = sources.filter { language(of: $0, configuration: configuration) == layout }
        if let preferredID, let preferred = candidates.first(where: { $0.id == preferredID }) { return preferred }
        let ids = configuration.sources(for: layout).inputSourceIDs
        for id in ids {
            if let source = candidates.first(where: { $0.id == id }) { return source }
        }
        return candidates.first
    }
}

public protocol InputSourceManaging {
    func select(_ layout: KeyboardLayout) -> Bool
}

// Immutable physical-key tables built once when the enabled/selected source changes.
struct KeyboardLayoutTables: Equatable {
    let english: [UInt16: String]
    let russian: [UInt16: String]

    func text(keyCode: UInt16, shifted: Bool, capsLocked: Bool = false, layout: KeyboardLayout) -> String? {
        (layout == .english ? english : russian)[keyCode + (shifted ? 128 : 0) + (capsLocked ? 256 : 0)]
    }

    var converter: LayoutConverter {
        var forward: [Character: Character] = [:]
        var reverse: [Character: Character] = [:]
        for key in english.keys.sorted() where key < 256 {
            guard let en = english[key], let ru = russian[key], en.count == 1, ru.count == 1,
                  let e = en.first, let r = ru.first, e.isLetter || r.isLetter else { continue }
            // Prefer the unshifted position when a glyph occurs on several keys.
            if forward[e] == nil { forward[e] = r }
            if reverse[r] == nil { reverse[r] = e }
        }
        return LayoutConverter(englishToRussian: forward, russianToEnglish: reverse)
    }
}

public final class InputSourceManager: InputSourceManaging {
    private let currentSource: () -> TISInputSource?
    private let availableSources: () -> [TISInputSource]
    private let selectSource: (TISInputSource) -> OSStatus
    private var preferred: [KeyboardLayout: String] = [:]
    private var selectedSources: [KeyboardLayout: TISInputSource] = [:]
    private(set) var tables: KeyboardLayoutTables?
    private(set) var currentID: String?
    private(set) var currentLayout: KeyboardLayout?
    public private(set) var missingLayouts: [KeyboardLayout] = []

    public convenience init() {
        self.init(
            currentSource: { TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() },
            availableSources: { TISCreateInputSourceList(nil, false).takeRetainedValue() as! [TISInputSource] },
            selectSource: { TISSelectInputSource($0) }
        )
    }

    init(
        currentSource: @escaping () -> TISInputSource?,
        availableSources: @escaping () -> [TISInputSource],
        selectSource: @escaping (TISInputSource) -> OSStatus
    ) {
        self.currentSource = currentSource
        self.availableSources = availableSources
        self.selectSource = selectSource
    }

    // Read the selection independently of distributed notifications. A transient
    // nil selection or incomplete catalog must not disable correction forever.
    // Healthy selections do not rebuild the physical-key tables on every key.
    @discardableResult
    func refreshIfNeeded(retryUnavailable: Bool = false) -> Bool {
        let current = currentSource()
        let id = current.flatMap { stringProperty(kTISPropertyInputSourceID, from: $0) }
        guard id != currentID || (retryUnavailable && (currentLayout == nil || tables == nil)) else { return false }
        return refresh(current: current)
    }

    // Returns true only for an external change. select() records our own selection
    // synchronously, so its later distributed notification cannot erase a live word.
    @discardableResult
    func refresh() -> Bool {
        refresh(current: currentSource())
    }

    private func refresh(current: TISInputSource?) -> Bool {
        let id = current.flatMap { stringProperty(kTISPropertyInputSourceID, from: $0) }
        let oldID = currentID
        let oldTables = tables
        let oldLayout = currentLayout
        let oldMissing = missingLayouts
        currentID = id
        let list = availableSources()
        let candidates = list.compactMap { source -> (TISInputSource, InputSourceDescriptor)? in
            guard boolProperty(kTISPropertyInputSourceIsSelectCapable, from: source),
                  boolProperty(kTISPropertyInputSourceIsEnabled, from: source),
                  TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) != nil,
                  let id = stringProperty(kTISPropertyInputSourceID, from: source) else { return nil }
            return (source, .init(id: id, languages: stringArrayProperty(kTISPropertyInputSourceLanguages, from: source)))
        }
        currentLayout = candidates.first(where: { $0.1.id == id }).flatMap { InputSourceResolver.language(of: $0.1) }
        if let currentLayout, let id { preferred[currentLayout] = id }
        selectedSources = [:]
        missingLayouts = []
        for layout in [KeyboardLayout.english, .russian] {
            if let descriptor = InputSourceResolver.resolve(layout, from: candidates.map(\.1), preferredID: preferred[layout]),
               let source = candidates.first(where: { $0.1.id == descriptor.id })?.0 {
                selectedSources[layout] = source
                preferred[layout] = descriptor.id
            } else { missingLayouts.append(layout) }
        }
        if let english = selectedSources[.english], let russian = selectedSources[.russian] {
            tables = KeyboardLayoutTables(english: Self.keyTable(for: english), russian: Self.keyTable(for: russian))
        } else { tables = nil }
        return oldID != currentID || oldTables != tables || oldLayout != currentLayout || oldMissing != missingLayouts
    }

    public func select(_ layout: KeyboardLayout) -> Bool {
        if selectedSources.isEmpty { refresh() }
        guard let source = selectedSources[layout] else { return false }
        guard selectSource(source) == noErr else { return false }
        currentID = stringProperty(kTISPropertyInputSourceID, from: source)
        currentLayout = layout
        return true
    }

    static func keyTable(for source: TISInputSource) -> [UInt16: String] {
        guard let property = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return [:] }
        let data = unsafeBitCast(property, to: CFData.self)
        let layout = UnsafeRawPointer(CFDataGetBytePtr(data)!).assumingMemoryBound(to: UCKeyboardLayout.self)
        var table: [UInt16: String] = [:]
        for modifiers in [0, shiftKey, alphaLock, shiftKey | alphaLock] {
            for key in UInt16(0)..<128 {
                var deadKey: UInt32 = 0
                var length = 0
                var units = [UniChar](repeating: 0, count: 8)
                let status = UCKeyTranslate(layout, key, UInt16(kUCKeyActionDisplay),
                    UInt32(modifiers >> 8), UInt32(LMGetKbdType()),
                    OptionBits(kUCKeyTranslateNoDeadKeysMask), &deadKey, units.count, &length, &units)
                guard status == noErr, length > 0 else { continue }
                let text = String(utf16CodeUnits: units, count: length)
                guard !text.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { continue }
                let shifted = modifiers & shiftKey != 0
                let capsLocked = modifiers & alphaLock != 0
                table[key + (shifted ? 128 : 0) + (capsLocked ? 256 : 0)] = text
            }
        }
        return table
    }

    private func boolProperty(_ key: CFString, from source: TISInputSource) -> Bool {
        guard let property = TISGetInputSourceProperty(source, key) else { return false }
        return CFBooleanGetValue(unsafeBitCast(property, to: CFBoolean.self))
    }

    private func stringProperty(_ key: CFString, from source: TISInputSource) -> String? {
        guard let property = TISGetInputSourceProperty(source, key) else { return nil }
        return unsafeBitCast(property, to: CFString.self) as String
    }

    private func stringArrayProperty(_ key: CFString, from source: TISInputSource) -> [String] {
        guard let property = TISGetInputSourceProperty(source, key) else { return [] }
        return unsafeBitCast(property, to: CFArray.self) as? [String] ?? []
    }
}
