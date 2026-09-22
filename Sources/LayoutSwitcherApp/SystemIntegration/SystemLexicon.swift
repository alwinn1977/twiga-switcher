import AppKit
import LayoutSwitcherCore

public final class SystemLexicon: @unchecked Sendable, WordLexicon {
    private struct CacheKey: Hashable {
        let word: String
        let languageCode: String
    }

    private let words: [Language: Set<String>]
    private let spellingTimeout: DispatchTimeInterval
    private let spellingCheck: @Sendable (String, Language) -> Bool
    private let queue = DispatchQueue(label: "dev.layoutswitcher.spelling", qos: .userInitiated)
    private let lock = NSLock()
    private var cachedResults: [CacheKey: Bool] = [:]
    private var pending: Set<CacheKey> = []

    public convenience init() {
        self.init(bundle: .module)
    }

    public convenience init(bundle: Bundle) {
        self.init(
            words: [
                .english: Self.load("en", from: bundle),
                .russian: Self.load("ru", from: bundle),
            ],
            spellingTimeout: .milliseconds(8)
        ) { word, language in
            let languageCode = language == .english ? "en_US" : "ru"
            return NSSpellChecker.shared.checkSpelling(
                of: word,
                startingAt: 0,
                language: languageCode,
                wrap: false,
                inSpellDocumentWithTag: 0,
                wordCount: nil
            ).location == NSNotFound
        }
    }

    init(
        words: [Language: Set<String>],
        spellingTimeout: DispatchTimeInterval,
        spellingCheck: @escaping @Sendable (String, Language) -> Bool
    ) {
        self.words = words
        self.spellingTimeout = spellingTimeout
        self.spellingCheck = spellingCheck
    }

    public func contains(_ word: String, language: Language) -> Bool {
        let normalized = word.lowercased()
        if words[language]?.contains(normalized) == true { return true }

        let key = CacheKey(
            word: normalized,
            languageCode: language == .english ? "en_US" : "ru"
        )
        if let cached = cachedResult(for: key) { return cached }
        guard beginLookup(for: key) else { return false }

        let completed = DispatchSemaphore(value: 0)
        queue.async { [self] in
            let result = spellingCheck(normalized, language)
            finishLookup(result, for: key)
            completed.signal()
        }

        guard completed.wait(timeout: .now() + spellingTimeout) == .success else {
            return false
        }
        return cachedResult(for: key) ?? false
    }

    private static func load(_ name: String, from bundle: Bundle) -> Set<String> {
        guard let url = bundle.url(forResource: name, withExtension: "txt"),
              let contents = try? String(contentsOf: url, encoding: .utf8) else {
            return []
        }
        return Set(contents
            .split(separator: "\n")
            .map(String.init)
            .filter { !$0.hasPrefix("#") })
    }

    private func cachedResult(for key: CacheKey) -> Bool? {
        lock.lock()
        defer { lock.unlock() }
        return cachedResults[key]
    }

    private func beginLookup(for key: CacheKey) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !pending.contains(key) else { return false }
        pending.insert(key)
        return true
    }

    private func finishLookup(_ result: Bool, for key: CacheKey) {
        lock.lock()
        cachedResults[key] = result
        pending.remove(key)
        lock.unlock()
    }
}
