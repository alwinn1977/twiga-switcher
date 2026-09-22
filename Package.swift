// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LayoutSwitcher",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "LayoutSwitcherCore", targets: ["LayoutSwitcherCore"]),
    ],
    targets: [
        .target(name: "LayoutSwitcherCore"),
        .target(name: "LayoutSwitcherApp", dependencies: ["LayoutSwitcherCore"], resources: [.process("Resources")]),
        .testTarget(name: "LayoutSwitcherCoreTests", dependencies: ["LayoutSwitcherCore"]),
        .testTarget(name: "LayoutSwitcherAppTests", dependencies: ["LayoutSwitcherApp", "LayoutSwitcherCore"]),
    ],
    swiftLanguageModes: [.v6]
)
