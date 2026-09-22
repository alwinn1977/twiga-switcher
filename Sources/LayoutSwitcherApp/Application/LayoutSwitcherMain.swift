import AppKit
import SwiftUI

@main
struct LayoutSwitcherMain: App {
    @StateObject private var controller = AppController()

    var body: some Scene {
        MenuBarExtra("LayoutSwitcher", systemImage: controller.state.systemImage) {
            Text(controller.state.title)
            Toggle("Enable Automatic Correction", isOn: Binding(
                get: { controller.isEnabled },
                set: { controller.setEnabled($0) }
            ))
            if controller.state == .permissionsRequired {
                Button("Request Required Permissions") { controller.requestPermissions() }
                Button("Open Privacy Settings") { controller.openPrivacySettings() }
            }
            Divider()
            Button("Quit LayoutSwitcher") { NSApplication.shared.terminate(nil) }
        }
    }
}
