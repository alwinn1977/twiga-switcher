import LayoutSwitcherCore
import LayoutSwitcherLexicon
import XCTest

final class ComputerTermsResourceTests: XCTestCase {
    func testComputerTermsPackCoversRequiredWordsPhrasesAndPunctuation() throws {
        let pack = try BundledLexiconResources.loadComputerTerms()

        for term in ["kubernetes", "typescript", "node.js", ".net", "c++", "postgresql"] {
            XCTAssertTrue(pack.lookup(term, language: .english).isSubjectTerm, term)
        }
        for term in ["машинное обучение", "база данных"] {
            XCTAssertTrue(pack.lookup(term, language: .russian).isSubjectTerm, term)
        }
        XCTAssertGreaterThanOrEqual(pack.maximumPhraseWords, 2)
    }

    func testBundledFrequencyDecisionCorrectsComputerFromPhysicalKeys() throws {
        let base = try BundledLexiconResources.loadBase()
        let terms = try BundledLexiconResources.loadComputerTerms()
        let lexicon = LexiconCatalogSnapshot(
            baseLexicons: [base.english, base.russian],
            subjectLexicons: [terms]
        )
        let conversion = try XCTUnwrap(LayoutConverter().convert("rjvgm.nth"))
        XCTAssertEqual(conversion.text, "компьютер")
        XCTAssertEqual(
            LanguageDetector(lexicon: lexicon, rules: NoUserCorrectionRules())
                .decision(original: "rjvgm.nth", conversion: conversion),
            .correct(text: "компьютер", targetLayout: .russian),
            "base=\(String(describing: base.russian.lookup("компьютер", language: .russian).score)), subject=\(String(describing: terms.lookup("компьютер", language: .russian).score))"
        )
    }

    func testBundledPipelineSwitchesComputerBeforePhysicalPeriodKey() throws {
        let base = try BundledLexiconResources.loadBase()
        let terms = try BundledLexiconResources.loadComputerTerms()
        let lexicon = LexiconCatalogSnapshot(
            baseLexicons: [base.english, base.russian],
            subjectLexicons: [terms]
        )
        var pipeline = InputPipeline(
            converter: LayoutConverter(),
            detector: LanguageDetector(lexicon: lexicon, rules: NoUserCorrectionRules())
        )
        for key in "rjv" { _ = pipeline.handle(.character(key), focusIsSafe: true) }
        XCTAssertEqual(pipeline.handle(.character("g"), focusIsSafe: true), .replace(.init(
            deleteKeyCount: 3, replacement: "комп", delimiter: "", targetLayout: .russian
        )))
        for key in "ьютер" { XCTAssertEqual(pipeline.handle(.character(key), focusIsSafe: true), .passThrough) }
        XCTAssertEqual(pipeline.handle(.boundary(" "), focusIsSafe: true), .passThrough)
    }

    func testBundledFrequencyDecisionCorrectsCommonInflectedVerb() throws {
        let base = try BundledLexiconResources.loadBase()
        let terms = try BundledLexiconResources.loadComputerTerms()
        let lexicon = LexiconCatalogSnapshot(
            baseLexicons: [base.english, base.russian],
            subjectLexicons: [terms]
        )
        let conversion = try XCTUnwrap(LayoutConverter().convert("cj[hfyztn"))
        XCTAssertEqual(conversion.text, "сохраняет")
        XCTAssertEqual(
            LanguageDetector(lexicon: lexicon, rules: NoUserCorrectionRules())
                .decision(original: "cj[hfyztn", conversion: conversion),
            .correct(text: "сохраняет", targetLayout: .russian),
            "base=\(String(describing: base.russian.lookup("сохраняет", language: .russian).score)), subject=\(String(describing: terms.lookup("сохраняет", language: .russian).score))"
        )
    }

    func testBundledFrequencyDecisionCorrectsBudgetWithLeadingPunctuationKeys() throws {
        let base = try BundledLexiconResources.loadBase()
        let terms = try BundledLexiconResources.loadComputerTerms()
        let lexicon = LexiconCatalogSnapshot(
            baseLexicons: [base.english, base.russian],
            subjectLexicons: [terms]
        )
        let conversion = try XCTUnwrap(LayoutConverter().convert(",.l;tn"))
        XCTAssertEqual(conversion.text, "бюджет")
        XCTAssertEqual(
            LanguageDetector(lexicon: lexicon, rules: NoUserCorrectionRules())
                .decision(original: ",.l;tn", conversion: conversion),
            .correct(text: "бюджет", targetLayout: .russian),
            "base=\(String(describing: base.russian.lookup("бюджет", language: .russian).score)), subject=\(String(describing: terms.lookup("бюджет", language: .russian).score))"
        )
    }

    func testBundledPipelineRetainsBudgetAcrossLeadingCommaDotAndSemicolon() throws {
        let base = try BundledLexiconResources.loadBase()
        let terms = try BundledLexiconResources.loadComputerTerms()
        let lexicon = LexiconCatalogSnapshot(
            baseLexicons: [base.english, base.russian],
            subjectLexicons: [terms]
        )
        var pipeline = InputPipeline(
            converter: LayoutConverter(),
            detector: LanguageDetector(lexicon: lexicon, rules: NoUserCorrectionRules())
        )
        for key in ",.l;" {
            let input: InputEvent = ",.;".contains(key) ? .boundary(String(key)) : .character(key)
            XCTAssertEqual(pipeline.handle(input, focusIsSafe: true), .passThrough)
        }
        XCTAssertEqual(pipeline.handle(.character("t"), focusIsSafe: true), .replace(.init(
            deleteKeyCount: 4, replacement: "бюдже", delimiter: "", targetLayout: .russian
        )))
        XCTAssertEqual(pipeline.handle(.character("т"), focusIsSafe: true), .passThrough)
        XCTAssertEqual(pipeline.handle(.boundary(" "), focusIsSafe: true), .passThrough)
    }

    func testBundledComputerTermsRecognizesMutexAndCorrectsPhysicalKeys() throws {
        let base = try BundledLexiconResources.loadBase()
        let terms = try BundledLexiconResources.loadComputerTerms()
        let lexicon = LexiconCatalogSnapshot(
            baseLexicons: [base.english, base.russian],
            subjectLexicons: [terms]
        )
        XCTAssertTrue(terms.lookup("мьютекс", language: .russian).isSubjectTerm)
        let conversion = try XCTUnwrap(LayoutConverter().convert("vm.ntrc"))
        XCTAssertEqual(conversion.text, "мьютекс")
        XCTAssertEqual(
            LanguageDetector(lexicon: lexicon, rules: NoUserCorrectionRules())
                .decision(original: "vm.ntrc", conversion: conversion),
            .correct(text: "мьютекс", targetLayout: .russian),
            "base=\(String(describing: base.russian.lookup("мьютекс", language: .russian).score)), subject=\(String(describing: terms.lookup("мьютекс", language: .russian).score))"
        )
    }

    func testBundledComputerTermsRecognizesStandaloneCI() throws {
        let base = try BundledLexiconResources.loadBase()
        let terms = try BundledLexiconResources.loadComputerTerms()
        let lexicon = LexiconCatalogSnapshot(
            baseLexicons: [base.english, base.russian],
            subjectLexicons: [terms]
        )
        XCTAssertTrue(terms.lookup("CI", language: .english).isSubjectTerm)
        let conversion = try XCTUnwrap(LayoutConverter().convert("СШ"))
        XCTAssertEqual(conversion.text, "CI")
        XCTAssertEqual(
            LanguageDetector(lexicon: lexicon, rules: NoUserCorrectionRules())
                .decision(original: "СШ", conversion: conversion),
            .correct(text: "CI", targetLayout: .english)
        )
    }

    func testBundledComputerTermsCoverCorpusSoftwareVocabulary() throws {
        let terms = try BundledLexiconResources.loadComputerTerms()
        for term in [
            "README", "setup", "build", "dashboard", "timeout", "request",
            "update", "config", "cache", "lookup", "terminal", "error",
            "report", "commit", "diff", "tests", "editor", "logs",
            "layout", "pod", "TextEdit", "localhost"
        ] {
            XCTAssertTrue(terms.lookup(term, language: .english).isSubjectTerm, term)
        }
    }
}
