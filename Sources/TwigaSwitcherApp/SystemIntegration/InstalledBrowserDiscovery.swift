import AppKit

struct InstalledBrowser: Equatable, Sendable {
    let bundleID: String
    let name: String
}

enum InstalledBrowserDiscovery {
    static func discover(urlSchemes: [String]) -> [InstalledBrowser] {
        urlSchemes.flatMap { scheme -> [InstalledBrowser] in
            // Query registered handlers only; this does not open the URL or access the network.
            guard let url = URL(string: "\(scheme)://example.invalid") else { return [] }
            return NSWorkspace.shared.urlsForApplications(toOpen: url).compactMap { appURL in
                guard let bundle = Bundle(url: appURL), let id = bundle.bundleIdentifier else { return nil }
                let name = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                    ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
                    ?? appURL.deletingPathExtension().lastPathComponent
                return InstalledBrowser(bundleID: id, name: name)
            }
        }
    }
}
