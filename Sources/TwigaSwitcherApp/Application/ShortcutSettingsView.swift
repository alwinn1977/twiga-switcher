import CoreGraphics
import AppKit
import SwiftUI
import UniformTypeIdentifiers

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
        Self(id: CGEventFlags.maskAlternate.rawValue, label: .option),
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
    @State private var applicationError: String?
    private var language: DisplayLanguage { controller.displayLanguage }

    var body: some View {
        Form {
            Section(InterfaceText.startup.localized(language)) {
                Toggle(InterfaceText.launchAtLogin.localized(language), isOn: Binding(
                    get: { controller.launchAtLoginEnabled },
                    set: { controller.setLaunchAtLoginEnabled($0) }
                ))
                .accessibilityIdentifier("launchAtLoginToggle")
                Text(InterfaceText.launchAtLoginHelp.localized(language))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if controller.launchAtLoginStatus == .requiresApproval {
                    Text(InterfaceText.loginItemApprovalRequired.localized(language))
                        .font(.caption)
                        .foregroundStyle(.orange)
                    Button(InterfaceText.openSystemSettings.localized(language)) {
                        controller.openLoginItemSettings()
                    }
                } else if controller.launchAtLoginStatus == .notFound {
                    Text(InterfaceText.loginItemUnavailable.localized(language))
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                if let error = controller.launchAtLoginError {
                    Text(InterfaceText.loginItemUpdateFailed.localized(language, error))
                        .foregroundStyle(.red)
                }
            }

            if let message = controller.inputSourceError {
                Section(InterfaceText.inputSources.localized(language)) {
                    Text(InterfaceText.diagnostic(message, in: language)).foregroundStyle(.orange)
                    Text(InterfaceText.addInputSourcesHelp.localized(language)).font(.caption)
                    Button(InterfaceText.openSystemSettings.localized(language)) {
                        SuggestionDialogs.openKeyboardSettings()
                    }
                }
            }
            Section(InterfaceText.permissionsSection.localized(language)) {
                Text(InterfaceText.permissionsHelp.localized(language))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                permissionRow(.accessibility, granted: controller.permissionSnapshot.accessibility)
                permissionRow(.inputMonitoring, granted: controller.permissionSnapshot.inputMonitoring)
                Button(InterfaceText.checkAgain.localized(language)) { controller.refresh() }
            }

            Section(InterfaceText.applications.localized(language)) {
                Text(InterfaceText.applicationsHelp.localized(language))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(controller.applicationRules) { rule in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(rule.name)
                            Text(rule.bundleID).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Picker(rule.name, selection: Binding(
                            get: { rule.mode },
                            set: { controller.setApplicationMode($0, for: rule.bundleID) }
                        )) {
                            Text(InterfaceText.standardMode.localized(language)).tag(ApplicationCorrectionMode.standard)
                            Text(InterfaceText.disabledMode.localized(language)).tag(ApplicationCorrectionMode.disabled)
                            Text(InterfaceText.compatibilityMode.localized(language)).tag(ApplicationCorrectionMode.compatibility)
                            Text(InterfaceText.uncheckedMode.localized(language)).tag(ApplicationCorrectionMode.unchecked)
                        }
                        .labelsHidden()
                        .frame(width: 190)
                        if !rule.isBuiltIn {
                            Button {
                                controller.removeApplication(bundleID: rule.bundleID)
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .help(InterfaceText.removeApplication.localized(language))
                        }
                    }
                }
                Text(InterfaceText.compatibilityWarning.localized(language))
                    .font(.caption)
                    .foregroundStyle(.orange)
                Text(InterfaceText.uncheckedWarning.localized(language))
                    .font(.caption)
                    .foregroundStyle(.orange)
                Button(InterfaceText.addApplication.localized(language)) { addApplication() }
                if let applicationError {
                    Text(applicationError).foregroundStyle(.red)
                }
            }

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
        .frame(minWidth: 650, minHeight: 640)
        .onAppear { controller.refresh() }
    }

    private func permissionRow(_ kind: PermissionKind, granted: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text((kind == .accessibility ? InterfaceText.accessibility : .inputMonitoring).localized(language))
                    .fontWeight(.medium)
                Spacer()
                Label(
                    (granted ? InterfaceText.granted : .missing).localized(language),
                    systemImage: granted ? "checkmark.circle.fill" : "exclamationmark.circle"
                )
                .foregroundStyle(granted ? .green : .orange)
            }
            Text((kind == .accessibility ? InterfaceText.accessibilityHelp : .inputMonitoringHelp).localized(language))
                .font(.caption)
                .foregroundStyle(.secondary)
            if !granted {
                HStack {
                    Button(InterfaceText.requestAccess.localized(language)) { controller.requestPermission(kind) }
                    Button(InterfaceText.openSystemSettings.localized(language)) { controller.openPermissionSettings(kind) }
                }
            }
        }
    }

    private func addApplication() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let bundle = Bundle(url: url), let id = bundle.bundleIdentifier else {
            applicationError = InterfaceText.invalidApplication.localized(language)
            return
        }
        controller.addApplication(bundleID: id, name: bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? url.deletingPathExtension().lastPathComponent)
        applicationError = nil
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
