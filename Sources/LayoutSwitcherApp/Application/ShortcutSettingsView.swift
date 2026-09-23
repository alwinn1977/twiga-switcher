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

private struct ShortcutModifiersChoice: Identifiable {
    let id: UInt64
    let label: String

    static let all: [Self] = [
        Self(id: CGEventFlags.maskControl.rawValue | CGEventFlags.maskAlternate.rawValue, label: "Control + Option"),
        Self(id: CGEventFlags.maskControl.rawValue | CGEventFlags.maskShift.rawValue, label: "Control + Shift"),
        Self(id: CGEventFlags.maskCommand.rawValue | CGEventFlags.maskAlternate.rawValue, label: "Command + Option"),
        Self(id: CGEventFlags.maskCommand.rawValue | CGEventFlags.maskShift.rawValue, label: "Command + Shift"),
        Self(id: CGEventFlags.maskControl.rawValue | CGEventFlags.maskCommand.rawValue, label: "Control + Command"),
        Self(id: CGEventFlags.maskAlternate.rawValue | CGEventFlags.maskShift.rawValue, label: "Option + Shift"),
    ]
}

struct ShortcutSettingsView: View {
    @ObservedObject var controller: AppController

    var body: some View {
        Form {
            Section("Keyboard shortcuts") {
                shortcutRow("Undo last correction", action: .undoCorrection, hotkey: controller.hotkeys.undo)
                shortcutRow("Force-correct current word", action: .forceCorrection, hotkey: controller.hotkeys.force)
                Text("Shortcuts work in supported editable fields. Force correction also works immediately after a space.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let error = controller.shortcutError {
                    Text(error).foregroundStyle(.red)
                }
            }

            Section("Feedback") {
                Toggle("Play sound when layout changes", isOn: Binding(
                    get: { controller.soundEnabled },
                    set: { controller.setSoundEnabled($0) }
                ))
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 560, minHeight: 250)
    }

    private func shortcutRow(
        _ title: String,
        action: HotkeyAction,
        hotkey: Hotkey
    ) -> some View {
        HStack {
            Text(title)
            Spacer()
            Picker("Modifiers", selection: Binding(
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
                    Text(choice.label).tag(choice.id)
                }
            }
            .labelsHidden()
            .frame(width: 180)

            Picker("Key", selection: Binding(
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
                    Text(choice.label).tag(choice.id)
                }
            }
            .labelsHidden()
            .frame(width: 100)
        }
    }
}
