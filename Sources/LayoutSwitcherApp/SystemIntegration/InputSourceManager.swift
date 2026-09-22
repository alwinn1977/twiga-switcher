import Carbon
import LayoutSwitcherCore

public struct InputSourceDescriptor: Equatable, Sendable {
    public let id: String
    public let languages: [String]

    public init(id: String, languages: [String]) {
        self.id = id
        self.languages = languages
    }
}

public enum InputSourceResolver {
    public static func resolve(
        _ layout: KeyboardLayout,
        from sources: [InputSourceDescriptor]
    ) -> InputSourceDescriptor? {
        let exactID = layout == .english
            ? "com.apple.keylayout.US"
            : "com.apple.keylayout.Russian"
        let languagePrefix = layout == .english ? "en" : "ru"

        return sources.first { $0.id == exactID }
            ?? sources.first { descriptor in
                descriptor.languages.contains { $0.hasPrefix(languagePrefix) }
            }
    }
}

public protocol InputSourceManaging {
    func select(_ layout: KeyboardLayout) -> Bool
}

public final class InputSourceManager: InputSourceManaging {
    public init() {}

    public func select(_ layout: KeyboardLayout) -> Bool {
        let list = TISCreateInputSourceList(nil, false).takeRetainedValue() as! [TISInputSource]
        let candidates = list.compactMap { source -> (TISInputSource, InputSourceDescriptor)? in
            guard isSelectCapable(source),
                  let id = stringProperty(kTISPropertyInputSourceID, from: source) else {
                return nil
            }
            return (source, InputSourceDescriptor(
                id: id,
                languages: stringArrayProperty(kTISPropertyInputSourceLanguages, from: source)
            ))
        }

        guard let resolved = InputSourceResolver.resolve(
            layout,
            from: candidates.map(\.1)
        ), let source = candidates.first(where: { $0.1 == resolved })?.0 else {
            return false
        }
        return TISSelectInputSource(source) == noErr
    }

    private func isSelectCapable(_ source: TISInputSource) -> Bool {
        guard let property = TISGetInputSourceProperty(
            source,
            kTISPropertyInputSourceIsSelectCapable
        ) else {
            return false
        }
        let value = unsafeBitCast(property, to: CFBoolean.self)
        return CFBooleanGetValue(value)
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
