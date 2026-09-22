import AppKit
import LayoutSwitcherCore

public struct SystemLexicon: @unchecked Sendable, WordLexicon {
    private let words: [Language:Set<String>]
    public init() { self.init(bundle: .module) }
    public init(bundle: Bundle) { func load(_ n:String)->Set<String>{ guard let u=bundle.url(forResource:n,withExtension:"txt"), let s=try? String(contentsOf:u,encoding:.utf8) else{return []}; return Set(s.split(separator:"\n").map(String.init).filter{!$0.hasPrefix("#")}) }; words=[.english:load("en"),.russian:load("ru")] }
    public func contains(_ word: String, language: Language) -> Bool { let w=word.lowercased(); if words[language]?.contains(w)==true{return true}; let lang=language == .english ? "en_US":"ru"; return NSSpellChecker.shared.checkSpelling(of:w, startingAt:0, language:lang, wrap:false, inSpellDocumentWithTag:0, wordCount:nil).location == NSNotFound }
}
