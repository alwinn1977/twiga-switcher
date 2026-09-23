import CoreGraphics
import SwiftUI

private struct ShortcutKeyChoice: Identifiable {
    let id: UInt16
    let label: String

    static let all: [Self] = [
        (0, "A"), (11, "B"), (8, "C"), (2, "D"), (14, "E"), (3, "F"),
        (5, "G"), (4, "H"), (34, "I"), (38, "J"), (40, "K"), (37, "L"),
        (46, "M"), (45, "N"), (31, "O"), (35, "P"), (12, "Q"), (15, "R"),
        (1, "S"), (17, "T"), (32, "U"), (9, "V"), (13, "W"), (7, "X"),
        (16, "Y"), (6, "Z"), (49, "Space"), (122, "F1"), (120, "F2"),
        (99, "F3"), (118, "F4"), (96, "F5"), (97, "F6"), (98, "F7"),
        (100, "F8"), (101, "F9"), (109, "F10"), (103, "F11"), (111, "F12"),
    ].map { Self(id: $0.0, label: $0.1) }
}

private struct ShortcutModifiersChoice: Identifiable, Sendable {
    let id: UInt64
    let label: InterfaceText

    static let all: [Self] = [
        Self(id: CGEventFlags.maskControl.rawValue | CGEventFlags.maskAlternate.rawValue, label: .controlOption),
        Self(id: CGEventFlags.maskControl.rawValue | CGEventFlags.maskShift.rawValue, label: .controlShift),
        Self(id: CGEventFlags.maskCommand.rawValue | CGEventFlags.maskAlternate.rawValue, label: .commandOption),
        Self(id: CGEventFlags.maskCommand.rawValue | CGEventFlags.maskShift.rawValue, label: .commandShift),
        Self(id: CGEventFlags.maskControl.rawValue | CGEventFlags.maskCommand.rawValue, label: .controlCommand),
        Self(id: CGEventFlags.maskAlternate.rawValue | CGEventFlags.maskShift.rawValue, label: .optionShift),
    ]
}

struct ShortcutSettingsView: View {
    @ObservedObject var controller: AppController
    private var language: DisplayLanguage { controller.displayLanguage }

    var body: some View {
        Form {
            Section(InterfaceText.language.localized(language)) {
                Picker(InterfaceText.languageChoice.localized(language), selection: Binding(
                    get: { controller.interfaceLanguage },
                    set: { controller.setInterfaceLanguage($0) }
                )) {
                    Text(InterfaceText.systemLanguage.localized(language)).tag(InterfaceLanguage.system)
                    Text(InterfaceText.russianLanguage.localized(language)).tag(InterfaceLanguage.russian)
                    Text(InterfaceText.englishLanguage.localized(language)).tag(InterfaceLanguage.english)
                }
                .accessibilityIdentifier("interfaceLanguagePicker")
            }

            Section(InterfaceText.keyboardShortcuts.localized(language)) {
                shortcutRow(InterfaceText.undoLastCorrection.localized(language), action: .undoCorrection, hotkey: controller.hotkeys.undo)
                shortcutRow(InterfaceText.forceCorrectCurrentWord.localized(language), action: .forceCorrection, hotkey: controller.hotkeys.force)
                Text(InterfaceText.shortcutHelp.localized(language))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if controller.shortcutError != nil {
                    Text(InterfaceText.shortcutConflict.localized(language)).foregroundStyle(.red)
                }
            }

            Section(InterfaceText.feedback.localized(language)) {
                Toggle(InterfaceText.playSound.localized(language), isOn: Binding(
                    get: { controller.soundEnabled },
                    set: { controller.setSoundEnabled($0) }
                ))
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 560, minHeight: 320)
    }

    private func shortcutRow(
        _ title: String,
        action: HotkeyAction,
        hotkey: Hotkey
    ) -> some View {
        HStack {
            Text(title)
            Spacer()
            Picker(InterfaceText.modifiers.localized(language), selection: Binding(
                get: { hotkey.modifiers },
                set: { modifiers in
                    controller.setHotkey(Hotkey(
                        keyCode: hotkey.keyCode,
                        modifiers: CGEventFlags(rawValue: modifiers),
                        label: hotkey.label
                    ), for: action)
                }
            )) {
                ForEach(ShortcutModifiersChoice.all) { choice in
                    Text(choice.label.localized(language)).tag(choice.id)
                }
            }
            .labelsHidden()
            .frame(width: 180)

            Picker(InterfaceText.key.localized(language), selection: Binding(
                get: { hotkey.keyCode },
                set: { keyCode in
                    guard let choice = ShortcutKeyChoice.all.first(where: { $0.id == keyCode }) else { return }
                    controller.setHotkey(Hotkey(
                        keyCode: keyCode,
                        modifiers: CGEventFlags(rawValue: hotkey.modifiers),
                        label: choice.label
                    ), for: action)
                }
            )) {
                ForEach(ShortcutKeyChoice.all) { choice in
                    Text(choice.id == 49 ? InterfaceText.space.localized(language) : choice.label).tag(choice.id)
                }
            }
            .labelsHidden()
            .frame(width: 100)
        }
    }
}
