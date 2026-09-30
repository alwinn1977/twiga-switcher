import AppKit
import SwiftUI
import LayoutSwitcherCore

@MainActor
enum SuggestionDialogs {
    static func rule(pair: CorrectionPair, language: DisplayLanguage,
                     completion: @escaping (UserCorrectionDisposition?) -> Void) -> NSPanel {
        let dialog = panel(title: InterfaceText.addRulePrompt.localized(language), content:
            VStack(alignment: .leading, spacing: 16) {
                Text(InterfaceText.addRulePrompt.localized(language)).font(.headline)
                Text("«\(pair.source)» → «\(pair.candidate)»").textSelection(.enabled)
                    .lineLimit(5)
                Text(InterfaceText.addRuleHelp.localized(language)).foregroundStyle(.secondary)
                HStack {
                    Button(InterfaceText.cancel.localized(language)) { completion(nil) }
                    Spacer()
                    Button(InterfaceText.never.localized(language)) { completion(.never) }
                    Button(InterfaceText.always.localized(language)) { completion(.always) }
                }
            }.padding(24).frame(width: 460)
        )
        dialog.onClose = { completion(nil) }
        return dialog
    }

    static func missingLayouts(message: String, language: DisplayLanguage) -> NSPanel {
        panel(title: InterfaceText.inputSources.localized(language), content:
            VStack(alignment: .leading, spacing: 16) {
                Text(message).font(.headline)
                Text(InterfaceText.addInputSourcesHelp.localized(language))
                Button(InterfaceText.openSystemSettings.localized(language)) { openKeyboardSettings() }
            }.padding(24).frame(width: 460)
        )
    }

    static func openKeyboardSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    private static func panel<Content: View>(title: String, content: Content) -> SuggestionPanel {
        let panel = SuggestionPanel(contentRect: .zero, styleMask: [.titled, .closable, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.title = title
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        let view = NSHostingView(rootView: content)
        panel.contentView = view
        panel.setContentSize(view.fittingSize)
        panel.center()
        // A suggestion should not steal keystrokes from the editor.
        panel.orderFrontRegardless()
        return panel
    }
}

@MainActor
private final class SuggestionPanel: NSPanel {
    var onClose: (() -> Void)?

    override func close() {
        let action = onClose
        onClose = nil
        super.close()
        action?()
    }
}
