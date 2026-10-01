import AppKit
import SwiftUI

public struct DictionaryManagerView: View {
    @ObservedObject private var controller: AppController
    @StateObject private var model: DictionaryManagerModel
    @State private var showingImporter = false
    @State private var pendingRemoval: DictionaryManagerRow?

    @MainActor
    public init(controller: AppController) {
        self.controller = controller
        _model = StateObject(wrappedValue: DictionaryManagerModel(
            reloadCatalog: { await controller.reloadDictionaries() }
        ))
    }

    public var body: some View {
        let language = controller.displayLanguage
        VStack(alignment: .leading, spacing: 12) {
            List(model.rows) { row in
                HStack {
                    VStack(alignment: .leading) {
                        Text(row.displayName(in: language)).font(.headline)
                        Text("\(row.version) · \(row.displayDetail(in: language))").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { row.isEnabled },
                        set: { value in Task { await model.setEnabled(value, row: row) } }
                    ))
                    .labelsHidden()
                    .disabled(row.isBase)
                    if row.canRemove {
                        Button(InterfaceText.remove.localized(language)) { pendingRemoval = row }
                    }
                    if let notice = row.noticeURL {
                        Button(InterfaceText.notice.localized(language)) { NSWorkspace.shared.open(notice) }
                    }
                }
            }
            HStack {
                Button(InterfaceText.importDictionary.localized(language)) { showingImporter = true }
                if model.isWorking { ProgressView().controlSize(.small) }
                if let message = model.statusMessage(in: language) { Text(message).font(.caption) }
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
            InterfaceText.removeDictionaryPrompt.localized(
                language,
                pendingRemoval?.displayName(in: language) ?? InterfaceText.dictionary.localized(language)
            ),
            isPresented: Binding(
                get: { pendingRemoval != nil },
                set: { if !$0 { pendingRemoval = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(InterfaceText.remove.localized(language), role: .destructive) {
                guard let row = pendingRemoval else { return }
                pendingRemoval = nil
                Task { await model.remove(row) }
            }
            Button(InterfaceText.cancel.localized(language), role: .cancel) { pendingRemoval = nil }
        }
    }
}
