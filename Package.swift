// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TwigaSwitcher",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "TwigaSwitcherCore", targets: ["TwigaSwitcherCore"]),
        .executable(name: "TwigaSwitcherApp", targets: ["TwigaSwitcherApp"]),
        .executable(name: "LexiconCompiler", targets: ["LexiconCompiler"]),
        .executable(name: "LexiconBenchmark", targets: ["LexiconBenchmark"]),
    ],
    targets: [
        .target(name: "TwigaSwitcherCore"),
        .target(
            name: "TwigaSwitcherLexicon",
            dependencies: ["TwigaSwitcherCore"],
            resources: [
                .copy("Resources/Lexicons"),
                .copy("Resources/Licenses"),
            ]
        ),
        .executableTarget(name: "LexiconCompiler", dependencies: ["TwigaSwitcherLexicon", "TwigaSwitcherCore"]),
        .executableTarget(name: "LexiconBenchmark", dependencies: ["TwigaSwitcherLexicon", "TwigaSwitcherCore"]),
        .executableTarget(
            name: "TwigaSwitcherApp",
            dependencies: ["TwigaSwitcherCore", "TwigaSwitcherLexicon"],
            resources: [
                .copy("Resources/Configuration"),
                .process("Resources/en.lproj"),
                .process("Resources/ru.lproj"),
            ]
        ),
        .testTarget(name: "TwigaSwitcherCoreTests", dependencies: ["TwigaSwitcherCore"]),
        .testTarget(name: "TwigaSwitcherLexiconTests", dependencies: ["TwigaSwitcherLexicon", "TwigaSwitcherCore"]),
        .testTarget(name: "TwigaSwitcherAppTests", dependencies: ["TwigaSwitcherApp", "TwigaSwitcherCore", "TwigaSwitcherLexicon"]),
    ],
    swiftLanguageModes: [.v6]
)
