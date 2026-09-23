import AppKit
import LayoutSwitcherCore
import SwiftUI

@main
struct LayoutSwitcherMain: App {
    @StateObject private var controller = AppController()

    var body: some Scene {
        MenuBarExtra("LayoutSwitcher", systemImage: controller.state.systemImage) {
            LayoutSwitcherMenu(controller: controller)
                .environment(\.locale, controller.displayLanguage.locale)
        }
        Window(InterfaceText.dictionaries.localized(controller.displayLanguage), id: "dictionaries") {
            DictionaryManagerView(controller: controller)
                .environment(\.locale, controller.displayLanguage.locale)
        }
        Window(InterfaceText.rules.localized(controller.displayLanguage), id: "rules") {
            RulesManagerView(controller: controller)
                .environment(\.locale, controller.displayLanguage.locale)
        }
        Window(InterfaceText.settings.localized(controller.displayLanguage), id: "settings") {
            ShortcutSettingsView(controller: controller)
                .environment(\.locale, controller.displayLanguage.locale)
        }
    }
}

private struct LayoutSwitcherMenu: View {
    @ObservedObject var controller: AppController
    @Environment(\.openWindow) private var openWindow
    private var language: DisplayLanguage { controller.displayLanguage }

    var body: some View {
        Text(controller.state.title(in: language))
        Toggle(InterfaceText.enableAutomaticCorrection.localized(language), isOn: Binding(
            get: { controller.isEnabled },
            set: { controller.setEnabled($0) }
        ))
        if controller.state == .permissionsRequired {
            Button(InterfaceText.requestPermissions.localized(language)) { controller.requestPermissions() }
            Button(InterfaceText.openPrivacySettings.localized(language)) { controller.openPrivacySettings() }
        }
        if case .error = controller.state {
            Button(InterfaceText.restartMonitor.localized(language)) { controller.restartMonitor() }
        }
        Divider()
        Button(InterfaceText.dictionariesMenu.localized(language)) { openWindow(id: "dictionaries") }
        Button(InterfaceText.rulesMenu.localized(language)) { openWindow(id: "rules") }
        Button(InterfaceText.settingsMenu.localized(language)) { openWindow(id: "settings") }
        if let pair = controller.latestDecisionPair {
            Divider()
            Button(label(pair, action: .alwaysCorrect)) { controller.setLatestRule(.always) }
            Button(label(pair, action: .neverCorrect)) { controller.setLatestRule(.never) }
        }
        Divider()
        Button(InterfaceText.quit.localized(language)) { NSApplication.shared.terminate(nil) }
    }

    private func label(_ pair: CorrectionPair, action: InterfaceText) -> String {
        let text = action.localized(language, pair.source, pair.candidate)
        return text.count <= 56 ? text : String(text.prefix(53)) + "…"
    }
}
