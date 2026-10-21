import TwigaSwitcherCore
import TwigaSwitcherLexicon
import XCTest

final class ComputerTermsResourceTests: XCTestCase {
    func testExpandedPackCoversServicesDeveloperToolsAndRussianWorkVocabulary() throws {
        let terms = try BundledLexiconResources.loadComputerTerms()
        for term in [
            "GitLab", "Jira", "Confluence", "Figma", "FFmpeg", "Fornex", "Bitrix", "RuStore",
            "Yandex", "Ozon", "Ostrovok", "ChatGPT", "Claude", "Cursor", "Rider", "DataGrip",
            "Grafana", "Prometheus", "Elasticsearch", "ClickHouse", "RabbitMQ", "Terraform",
            "DWH", "PWA", "GPON", "SNI", "XSLT", "MKV", "MSDOS", "QA", "RC", "AFK", "H2"
        ] {
            XCTAssertTrue(terms.lookup(term, language: .english).isSubjectTerm, term)
        }
        for term in [
            "апрув", "заапрувь", "заапрувить", "заапрувили", "юзай", "юзаешь", "юзать",
            "дефолтную", "опенсорсным", "эпик", "эпика", "гитхаб", "нейропомощник",
            "задеплой", "закоммить", "запушь", "заревьюй", "смёржи", "хардкодом",
            "пайплайн", "эндпоинт", "бэкенд", "фронтенд", "рефакторинг", "чекаут"
        ] {
            XCTAssertTrue(terms.lookup(term, language: .russian).isSubjectTerm, term)
        }
    }

    func testDictionaryReplacesGeneralTermsWithoutPersonalAlwaysRules() throws {
        let base = try BundledLexiconResources.loadBase()
        let terms = try BundledLexiconResources.loadComputerTerms()
        let detector = LanguageDetector(lexicon: LexiconCatalogSnapshot(
            baseLexicons: [base.english, base.russian], subjectLexicons: [terms]
        ), rules: NoUserCorrectionRules())
        let pairs = [
            ("pffghedm", "заапрувь"), ("fghed", "апрув"), (".pfq", "юзай"),
            (".pftim", "юзаешь"), ("jgtycjhcysv", "опенсорсным"), ("ltajknye.", "дефолтную"),
            ("ubn[f,", "гитхаб"), ("ytqhjgjvjoybr", "нейропомощник"),
            ("ааьзуп", "ffmpeg"), ("ашпьф", "figma"), ("ащктуч", "fornex"),
            ("вцр", "dwh"), ("зцф", "pwa"), ("ишекшч", "bitrix"),
            ("кгыещку", "rustore"), ("нфтвуч", "yandex"), ("пзщт", "gpon"),
            ("чыде", "xslt"), ("щфь", "oam"), ("щыекщмщл", "ostrovok"),
            ("щящт", "ozon"), ("ытш", "sni"), ("ьлм", "mkv"), ("ьывщы", "msdos")
        ]
        for (source, target) in pairs {
            let conversion = try XCTUnwrap(LayoutConverter().convert(source))
            XCTAssertEqual(conversion.text, target)
            XCTAssertEqual(detector.decision(original: source, conversion: conversion), .correct(
                text: target, targetLayout: conversion.targetLayout
            ), source)
            let reverse = try XCTUnwrap(LayoutConverter().convert(target))
            XCTAssertNotEqual(detector.decision(original: target, conversion: reverse), .correct(
                text: reverse.text, targetLayout: reverse.targetLayout
            ), target)
        }
    }

    func testExpandedVocabularyWorksWithPhysicalTypingAndPunctuation() throws {
        let expected = "Заапрувь деплой в GitLab и проверь Figma, FFmpeg, nginx, h2. и nalog.ru, юзай дефолтную ветку.\n"
        for mode in [TypingMode.automatic, .manualAtScriptChanges] {
            let session = try TypingSessionDriver(initialLayout: .english)
            let trace = try session.type(expected, mode: mode)
            XCTAssertEqual(trace.editorText, expected, trace.firstDivergence)
        }
    }

    func testComputerVocabularyPreservesCommonWordsAndAbbreviations() throws {
        let base = try BundledLexiconResources.loadBase()
        let terms = try BundledLexiconResources.loadComputerTerms()
        let detector = LanguageDetector(lexicon: LexiconCatalogSnapshot(
            baseLexicons: [base.english, base.russian], subjectLexicons: [terms]
        ), rules: NoUserCorrectionRules())
        for word in ["а", "и", "в", "на", "по", "за", "до", "из", "не", "он", "она", "мы", "ты", "вы", "да", "нет", "это", "для", "уже", "тут", "мл", "МГУ", "LTD", "гм", "СВТ", "КС", "ЕД", "Vue", "uv", "CDN", "RC", "TL", "VK", "дев"] {
            let conversion = try XCTUnwrap(LayoutConverter().convert(word))
            XCTAssertNotEqual(detector.decision(original: word, conversion: conversion), .correct(
                text: conversion.text, targetLayout: conversion.targetLayout
            ), word)
        }
    }

    func testComputerTermsPackCoversRequiredWordsPhrasesAndPunctuation() throws {
        let pack = try BundledLexiconResources.loadComputerTerms()

        for term in ["kubernetes", "typescript", "node.js", ".net", "c++", "postgresql"] {
            XCTAssertTrue(pack.lookup(term, language: .english).isSubjectTerm, term)
        }
        for term in ["машинное обучение", "база данных"] {
            XCTAssertTrue(pack.lookup(term, language: .russian).isSubjectTerm, term)
        }
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
