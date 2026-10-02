import Foundation

struct InterfaceStringResources: Sendable {
    static let bundled = Self(bundle: .module)

    private let english: Bundle
    private let russian: Bundle?

    init(bundle: Bundle) {
        guard let englishURL = bundle.url(forResource: "en", withExtension: "lproj"),
              let englishBundle = Bundle(url: englishURL) else {
            preconditionFailure("Missing bundled English localization")
        }
        english = englishBundle
        russian = bundle.url(forResource: "ru", withExtension: "lproj").flatMap(Bundle.init(url:))
    }

    func localizedString(forKey key: String, in language: DisplayLanguage) -> String {
        let fallback = english.localizedString(forKey: key, value: key, table: "Localizable")
        guard language == .russian, let russian else { return fallback }
        return russian.localizedString(forKey: key, value: fallback, table: "Localizable")
    }
}
