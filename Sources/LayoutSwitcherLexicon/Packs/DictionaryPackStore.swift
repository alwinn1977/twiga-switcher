import Foundation

public final class DictionaryPackStore: @unchecked Sendable {
    private struct State: Codable {
        let schemaVersion: Int
        let enabledIdentifiers: [String]
    }

    private let rootURL: URL
    private let stateURL: URL
    private let lock = NSLock()
    private var enabledIdentifiers: Set<String>

    public init(rootURL: URL) throws {
        self.rootURL = rootURL.standardizedFileURL
        self.stateURL = self.rootURL.appendingPathComponent("enabled-packs.json")
        try FileManager.default.createDirectory(at: self.rootURL, withIntermediateDirectories: true)

        let persisted: Set<String>
        if let data = try? Data(contentsOf: stateURL),
           let state = try? JSONDecoder().decode(State.self, from: data),
           state.schemaVersion == 1 {
            persisted = Set(state.enabledIdentifiers)
        } else {
            persisted = []
        }
        let installed = Set(try Self.installedIdentifiers(in: self.rootURL))
        self.enabledIdentifiers = persisted.intersection(installed)
        if self.enabledIdentifiers != persisted { try persist() }
    }

    public func isEnabled(_ identifier: String) -> Bool {
        lock.withLock { enabledIdentifiers.contains(identifier) }
    }

    public func enabledIdentifiersSnapshot() -> Set<String> {
        lock.withLock { enabledIdentifiers }
    }

    public func setEnabled(_ enabled: Bool, identifier: String) throws {
        guard DictionaryPackImporter.isValidIdentifier(identifier) else {
            throw DictionaryPackError.invalidIdentifier
        }
        try lock.withLock {
            if enabled {
                enabledIdentifiers.insert(identifier)
            } else {
                enabledIdentifiers.remove(identifier)
            }
            try persistLocked()
        }
    }

    public func installedPacks() throws -> [InstalledDictionaryPack] {
        try Self.installedIdentifiers(in: rootURL).compactMap { identifier in
            let directory = rootURL.appendingPathComponent(identifier, isDirectory: true)
            guard let manifestData = try? Data(contentsOf: directory.appendingPathComponent("pack.json")),
                  let manifest = try? JSONDecoder().decode(DictionaryPackManifest.self, from: manifestData),
                  let indexData = try? Data(contentsOf: directory.appendingPathComponent("indexes.json")),
                  let indexes = try? JSONDecoder().decode(LexiconResourceManifest.self, from: indexData) else {
                return nil
            }
            return InstalledDictionaryPack(manifest: manifest, indexManifest: indexes, directoryURL: directory)
        }.sorted { $0.manifest.name.localizedStandardCompare($1.manifest.name) == .orderedAscending }
    }

    public func removeConfirmed(identifier: String) throws {
        guard DictionaryPackImporter.isValidIdentifier(identifier) else {
            throw DictionaryPackError.invalidIdentifier
        }
        let directory = rootURL.appendingPathComponent(identifier, isDirectory: true).standardizedFileURL
        guard directory.deletingLastPathComponent() == rootURL else {
            throw DictionaryPackError.invalidIdentifier
        }
        if FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
        try setEnabled(false, identifier: identifier)
    }

    private static func installedIdentifiers(in root: URL) throws -> [String] {
        let urls = try FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        )
        return try urls.compactMap { url in
            let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard values.isDirectory == true,
                  values.isSymbolicLink != true,
                  DictionaryPackImporter.isValidIdentifier(url.lastPathComponent),
                  FileManager.default.fileExists(atPath: url.appendingPathComponent("pack.json").path) else {
                return nil
            }
            return url.lastPathComponent
        }
    }

    private func persist() throws {
        try lock.withLock { try persistLocked() }
    }

    private func persistLocked() throws {
        let state = State(schemaVersion: 1, enabledIdentifiers: enabledIdentifiers.sorted())
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        var data = try encoder.encode(state)
        data.append(0x0A)
        try data.write(to: stateURL, options: .atomic)
    }
}
