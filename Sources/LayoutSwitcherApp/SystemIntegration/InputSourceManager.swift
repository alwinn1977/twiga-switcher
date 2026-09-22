import Carbon
import LayoutSwitcherCore

public struct InputSourceDescriptor: Equatable, Sendable { public let id: String; public let languages: [String]; public init(id: String, languages: [String]) { self.id=id; self.languages=languages } }
public enum InputSourceResolver {
    public static func resolve(_ layout: KeyboardLayout, from sources: [InputSourceDescriptor]) -> InputSourceDescriptor? { let exact = layout == .english ? "com.apple.keylayout.US" : "com.apple.keylayout.Russian"; let lang = layout == .english ? "en" : "ru"; return sources.first{$0.id == exact} ?? sources.first{$0.languages.contains(where:{$0.hasPrefix(lang)})} }
}
public protocol InputSourceManaging { func select(_ layout: KeyboardLayout) -> Bool }
public final class InputSourceManager: InputSourceManaging {
    public init() {}
    public func select(_ layout: KeyboardLayout) -> Bool {
        let list = TISCreateInputSourceList(nil, false).takeRetainedValue() as! [TISInputSource]
        let exact = layout == .english ? "com.apple.keylayout.US" : "com.apple.keylayout.Russian"
        for source in list { if let p=TISGetInputSourceProperty(source,kTISPropertyInputSourceID), (unsafeBitCast(p,to:CFString.self) as String)==exact { return TISSelectInputSource(source)==noErr } }
        return false
    }
}
