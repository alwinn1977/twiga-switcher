import SwiftUI

public struct RulesManagerView: View {
    @StateObject private var model = RulesManagerModel()
    @State private var confirmingDeleteAll = false

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            List(model.rules) { rule in
                HStack {
                    Text(rule.source)
                    Image(systemName: "arrow.right")
                    Text(rule.candidate)
                    Spacer()
                    Text(rule.disposition == .always ? "Always" : "Never")
                        .foregroundStyle(.secondary)
                    Button("Delete") { model.remove(rule) }
                }
            }
            HStack {
                Button("Forget All Rules", role: .destructive) { confirmingDeleteAll = true }
                    .disabled(model.rules.isEmpty)
                if let message = model.statusMessage { Text(message).font(.caption) }
            }
        }
        .padding()
        .frame(minWidth: 560, minHeight: 320)
        .confirmationDialog(
            "Forget all learned rules?",
            isPresented: $confirmingDeleteAll,
            titleVisibility: .visible
        ) {
            Button("Forget All", role: .destructive) { model.removeAll() }
            Button("Cancel", role: .cancel) {}
        }
    }
}
