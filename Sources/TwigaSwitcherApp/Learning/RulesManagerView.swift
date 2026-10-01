import SwiftUI

public struct RulesManagerView: View {
    @ObservedObject private var controller: AppController
    @StateObject private var model = RulesManagerModel()
    @State private var confirmingDeleteAll = false

    public init(controller: AppController) { self.controller = controller }

    public var body: some View {
        let language = controller.displayLanguage
        VStack(alignment: .leading, spacing: 12) {
            List(model.rules) { rule in
                HStack {
                    Text(rule.source)
                    Image(systemName: "arrow.right")
                    Text(rule.candidate)
                    Spacer()
                    Text((rule.disposition == .always ? InterfaceText.always : .never).localized(language))
                        .foregroundStyle(.secondary)
                    Button(InterfaceText.delete.localized(language)) { model.remove(rule) }
                }
            }
            HStack {
                Button(InterfaceText.forgetAllRules.localized(language), role: .destructive) { confirmingDeleteAll = true }
                    .disabled(model.rules.isEmpty)
                if let message = model.statusMessage(in: language) { Text(message).font(.caption) }
            }
        }
        .padding()
        .frame(minWidth: 560, minHeight: 320)
        .confirmationDialog(
            InterfaceText.forgetAllPrompt.localized(language),
            isPresented: $confirmingDeleteAll,
            titleVisibility: .visible
        ) {
            Button(InterfaceText.forgetAll.localized(language), role: .destructive) { model.removeAll() }
            Button(InterfaceText.cancel.localized(language), role: .cancel) {}
        }
    }
}
