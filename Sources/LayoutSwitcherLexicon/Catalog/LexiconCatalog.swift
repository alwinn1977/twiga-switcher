import Foundation
import LayoutSwitcherCore

public final class LexiconCatalog: @unchecked Sendable, FrequencyLexicon {
    private let lock = NSLock()
    private var currentSnapshot: LexiconCatalogSnapshot

    public init(initialSnapshot: LexiconCatalogSnapshot) {
        self.currentSnapshot = initialSnapshot
    }

    public var maximumPhraseWords: Int {
        snapshot().maximumPhraseWords
    }

    public func snapshot() -> LexiconCatalogSnapshot {
        lock.withLock { currentSnapshot }
    }

    public func replaceSnapshot(_ snapshot: LexiconCatalogSnapshot) {
        lock.withLock { currentSnapshot = snapshot }
    }

    public func lookup(_ text: String, language: Language) -> LexiconMatch {
        snapshot().lookup(text, language: language)
    }

    public func hasCompletion(for prefix: String, language: Language, minimumScore: Int) -> Bool {
        snapshot().hasCompletion(for: prefix, language: language, minimumScore: minimumScore)
    }
}
