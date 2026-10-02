import AppKit
import SwiftUI

struct AboutView: View {
    @ObservedObject var controller: AppController
    private var language: DisplayLanguage { controller.displayLanguage }
    private var licenseURL: URL {
        Bundle.main.url(forResource: "LICENSE", withExtension: "txt")
            ?? URL(string: "https://www.gnu.org/licenses/gpl-3.0.html")!
    }

    var body: some View {
        VStack(spacing: 16) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .scaledToFit()
                .frame(width: 96, height: 96)
                .accessibilityHidden(true)

            VStack(spacing: 6) {
                Text("Twiga Switcher")
                    .font(.title.bold())
                if let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String {
                    Text(InterfaceText.aboutVersion.localized(language, version))
                        .foregroundStyle(.secondary)
                }
                if let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String {
                    Text(InterfaceText.aboutBuild.localized(language, build))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Text(InterfaceText.aboutDescription.localized(language))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Link("GitHub", destination: URL(string: "https://github.com/alwinn1977/twiga-switcher")!)

            VStack(spacing: 8) {
                Text("© 2026 Алексей Винокуров (Alexey Vinokurov)")
                Button(InterfaceText.aboutLicense.localized(language)) {
                    // SwiftUI's default Link handler does not reliably open local files.
                    if !NSWorkspace.shared.open(licenseURL), licenseURL.isFileURL {
                        NSWorkspace.shared.open(URL(string: "https://www.gnu.org/licenses/gpl-3.0.html")!)
                    }
                }
                .buttonStyle(.link)
                Text(InterfaceText.aboutLicenseNotice.localized(language))
                    .foregroundStyle(.secondary)
            }
            .font(.caption)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(32)
        .frame(width: 360)
    }
}
