import CoreGraphics
import Foundation

public enum HotkeyAction: String, Codable, Sendable {
    case undoCorrection
    case forceCorrection
}

public struct Hotkey: Codable, Equatable, Sendable {
    private static let relevantFlags: CGEventFlags = [
        .maskCommand, .maskControl, .maskAlternate, .maskShift
    ]

    public let keyCode: UInt16
    public let modifiers: UInt64
    public let label: String

    public init(keyCode: UInt16, modifiers: CGEventFlags, label: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers.intersection(Self.relevantFlags).rawValue
        self.label = label
    }

    public func matches(keyCode: UInt16, flags: CGEventFlags) -> Bool {
        self.keyCode == keyCode
            && modifiers == flags.intersection(Self.relevantFlags).rawValue
    }

    public func hasSameCombination(as other: Hotkey) -> Bool {
        keyCode == other.keyCode && modifiers == other.modifiers
    }

    public var isValid: Bool {
        let required: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate]
        let flags = CGEventFlags(rawValue: modifiers)
        return !flags.intersection(required).isEmpty
            && ![54, 55, 56, 57, 58, 59, 60, 61, 62, 63].contains(Int(keyCode))
            && !label.isEmpty
    }

    public var displayName: String {
        let flags = CGEventFlags(rawValue: modifiers)
        var parts: [String] = []
        if flags.contains(.maskControl) { parts.append("Control") }
        if flags.contains(.maskAlternate) { parts.append("Option") }
        if flags.contains(.maskShift) { parts.append("Shift") }
        if flags.contains(.maskCommand) { parts.append("Command") }
        parts.append(label)
        return parts.joined(separator: " + ")
    }
}

public struct HotkeyConfiguration: Codable, Equatable, Sendable {
    public var undo: Hotkey
    public var force: Hotkey

    public static let defaults = HotkeyConfiguration(
        undo: Hotkey(keyCode: 6, modifiers: [.maskControl, .maskAlternate], label: "Z"),
        force: Hotkey(keyCode: 37, modifiers: [.maskControl, .maskAlternate], label: "L")
    )

    public func action(keyCode: UInt16, flags: CGEventFlags) -> HotkeyAction? {
        if undo.matches(keyCode: keyCode, flags: flags) { return .undoCorrection }
        if force.matches(keyCode: keyCode, flags: flags) { return .forceCorrection }
        return nil
    }
}

public final class HotkeyStore {
    private let defaults: UserDefaults
    private let key = "hotkeyConfiguration"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var configuration: HotkeyConfiguration {
        guard let data = defaults.data(forKey: key),
              let configuration = try? JSONDecoder().decode(HotkeyConfiguration.self, from: data),
              configuration.undo.isValid,
              configuration.force.isValid,
              !configuration.undo.hasSameCombination(as: configuration.force) else {
            return .defaults
        }
        return configuration
    }

    @discardableResult
    public func set(_ hotkey: Hotkey, for action: HotkeyAction) -> Bool {
        guard hotkey.isValid else { return false }
        var updated = configuration
        switch action {
        case .undoCorrection: updated.undo = hotkey
        case .forceCorrection: updated.force = hotkey
        }
        guard !updated.undo.hasSameCombination(as: updated.force),
              let data = try? JSONEncoder().encode(updated) else { return false }
        defaults.set(data, forKey: key)
        return true
    }
}
