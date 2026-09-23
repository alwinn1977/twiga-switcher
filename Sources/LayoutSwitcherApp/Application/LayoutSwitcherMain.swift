import AppKit
import LayoutSwitcherCore
import SwiftUI

@main
struct LayoutSwitcherMain: App {
    @StateObject private var controller = AppController()

    var body: some Scene {
        MenuBarExtra("LayoutSwitcher", systemImage: controller.state.systemImage) {
            LayoutSwitcherMenu(controller: controller)
        }
        Window("Dictionaries", id: "dictionaries") {
            DictionaryManagerView(controller: controller)
        }
        Window("Rules", id: "rules") {
            RulesManagerView()
        }
        Window("Settings", id: "settings") {
            ShortcutSettingsView(controller: controller)
        }
    }
}

private struct LayoutSwitcherMenu: View {
    @ObservedObject var controller: AppController
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text(controller.state.title)
        Toggle("Enable Automatic Correction", isOn: Binding(
            get: { controller.isEnabled },
            set: { controller.setEnabled($0) }
        ))
        if controller.state == .permissionsRequired {
            Button("Request Required Permissions") { controller.requestPermissions() }
            Button("Open Privacy Settings") { controller.openPrivacySettings() }
        }
        if case .error = controller.state {
            Button("Restart Monitor") { controller.restartMonitor() }
        }
        Divider()
        Button("Dictionaries…") { openWindow(id: "dictionaries") }
        Button("Rules…") { openWindow(id: "rules") }
        Button("Shortcuts & Sound…") { openWindow(id: "settings") }
        if let pair = controller.latestDecisionPair {
            Divider()
            Button("Always correct \(label(pair))") { controller.setLatestRule(.always) }
            Button("Never correct \(label(pair))") { controller.setLatestRule(.never) }
        }
        Divider()
        Button("Quit LayoutSwitcher") { NSApplication.shared.terminate(nil) }
    }

    private func label(_ pair: CorrectionPair) -> String {
        let text = "“\(pair.source)” → “\(pair.candidate)”"
        return text.count <= 56 ? text : String(text.prefix(53)) + "…"
    }
}
