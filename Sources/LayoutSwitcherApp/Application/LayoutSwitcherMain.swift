import AppKit
import LayoutSwitcherCore
import SwiftUI

@main
struct LayoutSwitcherMain: App {
    @StateObject private var controller = AppController(presentDialogs: true)

    var body: some Scene {
        MenuBarExtra {
            LayoutSwitcherMenu(controller: controller)
                .environment(\.locale, controller.displayLanguage.locale)
        } label: {
            Image(nsImage: MenuBarIcon.image(for: controller.state))
                .accessibilityLabel("Twiga Switcher")
                .accessibilityValue(controller.state.title(in: controller.displayLanguage))
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
            Button(InterfaceText.setupPermissions.localized(language)) { showWindow(id: "settings") }
        }
        if case .error = controller.state {
            Button(InterfaceText.restartMonitor.localized(language)) { controller.restartMonitor() }
        }
        Divider()
        Button(InterfaceText.dictionariesMenu.localized(language)) { showWindow(id: "dictionaries") }
        Button(InterfaceText.rulesMenu.localized(language)) { showWindow(id: "rules") }
        Button(InterfaceText.settingsMenu.localized(language)) { showWindow(id: "settings") }
        Divider()
        Button(InterfaceText.quit.localized(language)) { NSApplication.shared.terminate(nil) }
    }

    private func showWindow(id: String) {
        // Opening a MenuBarExtra does not activate this accessory application.
        NSApplication.shared.activate()
        openWindow(id: id)
        // Wait for the menu to dismiss and SwiftUI to create/order the scene.
        DispatchQueue.main.async {
            guard let window = NSApplication.shared.windows.first(where: {
                $0.identifier?.rawValue == id
            }) else { return }
            if window.isMiniaturized { window.deminiaturize(nil) }
            NSApplication.shared.activate()
            window.makeKeyAndOrderFront(nil)
        }
    }
}
