// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LayoutSwitcher",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "LayoutSwitcherCore", targets: ["LayoutSwitcherCore"]),
        .executable(name: "LayoutSwitcherApp", targets: ["LayoutSwitcherApp"]),
    ],
    targets: [
        .target(name: "LayoutSwitcherCore"),
        .target(name: "LayoutSwitcherLexicon", dependencies: ["LayoutSwitcherCore"]),
        .executableTarget(name: "LayoutSwitcherApp", dependencies: ["LayoutSwitcherCore", "LayoutSwitcherLexicon"], resources: [.process("Resources")]),
        .testTarget(name: "LayoutSwitcherCoreTests", dependencies: ["LayoutSwitcherCore"]),
        .testTarget(name: "LayoutSwitcherLexiconTests", dependencies: ["LayoutSwitcherLexicon", "LayoutSwitcherCore"]),
        .testTarget(name: "LayoutSwitcherAppTests", dependencies: ["LayoutSwitcherApp", "LayoutSwitcherCore"]),
    ],
    swiftLanguageModes: [.v6]
)
