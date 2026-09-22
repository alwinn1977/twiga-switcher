import AppKit
import SwiftUI

public struct DictionaryManagerView: View {
    @StateObject private var model: DictionaryManagerModel
    @State private var showingImporter = false
    @State private var pendingRemoval: DictionaryManagerRow?

    @MainActor
    public init(controller: AppController) {
        _model = StateObject(wrappedValue: DictionaryManagerModel(
            reloadCatalog: { await controller.reloadDictionaries() }
        ))
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            List(model.rows) { row in
                HStack {
                    VStack(alignment: .leading) {
                        Text(row.name).font(.headline)
                        Text("\(row.version) · \(row.detail)").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { row.isEnabled },
                        set: { value in Task { await model.setEnabled(value, row: row) } }
                    ))
                    .labelsHidden()
                    .disabled(row.isBase || row.isBuiltIn)
                    if row.canRemove {
                        Button("Remove") { pendingRemoval = row }
                    }
                    if let notice = row.noticeURL {
                        Button("Notice") { NSWorkspace.shared.open(notice) }
                    }
                }
            }
            HStack {
                Button("Import…") { showingImporter = true }
                if model.isWorking { ProgressView().controlSize(.small) }
                if let message = model.statusMessage { Text(message).font(.caption) }
            }
        }
        .padding()
        .frame(minWidth: 680, minHeight: 380)
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [.layoutDictionary],
            allowsMultipleSelection: false
        ) { result in
            guard case let .success(urls) = result, let url = urls.first else { return }
            Task {
                let hasSecurityScope = url.startAccessingSecurityScopedResource()
                defer {
                    if hasSecurityScope { url.stopAccessingSecurityScopedResource() }
                }
                await model.importPackage(at: url)
            }
        }
        .confirmationDialog(
            "Remove \(pendingRemoval?.name ?? "dictionary")?",
            isPresented: Binding(
                get: { pendingRemoval != nil },
                set: { if !$0 { pendingRemoval = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                guard let row = pendingRemoval else { return }
                pendingRemoval = nil
                Task { await model.remove(row) }
            }
            Button("Cancel", role: .cancel) { pendingRemoval = nil }
        }
    }
}
