// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TwigaSwitcher",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "LayoutSwitcherCore", targets: ["LayoutSwitcherCore"]),
        .executable(name: "LayoutSwitcherApp", targets: ["LayoutSwitcherApp"]),
        .executable(name: "LexiconCompiler", targets: ["LexiconCompiler"]),
        .executable(name: "LexiconBenchmark", targets: ["LexiconBenchmark"]),
    ],
    targets: [
        .target(name: "LayoutSwitcherCore"),
        .target(
            name: "LayoutSwitcherLexicon",
            dependencies: ["LayoutSwitcherCore"],
            resources: [
                .copy("Resources/Lexicons"),
                .copy("Resources/Licenses"),
            ]
        ),
        .executableTarget(name: "LexiconCompiler", dependencies: ["LayoutSwitcherLexicon", "LayoutSwitcherCore"]),
        .executableTarget(name: "LexiconBenchmark", dependencies: ["LayoutSwitcherLexicon", "LayoutSwitcherCore"]),
        .executableTarget(name: "LayoutSwitcherApp", dependencies: ["LayoutSwitcherCore", "LayoutSwitcherLexicon"]),
        .testTarget(name: "LayoutSwitcherCoreTests", dependencies: ["LayoutSwitcherCore"]),
        .testTarget(name: "LayoutSwitcherLexiconTests", dependencies: ["LayoutSwitcherLexicon", "LayoutSwitcherCore"]),
        .testTarget(name: "LayoutSwitcherAppTests", dependencies: ["LayoutSwitcherApp", "LayoutSwitcherCore", "LayoutSwitcherLexicon"]),
    ],
    swiftLanguageModes: [.v6]
)
