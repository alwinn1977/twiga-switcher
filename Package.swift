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
        .executableTarget(name: "LayoutSwitcherApp", dependencies: ["LayoutSwitcherCore"], resources: [.process("Resources")]),
        .testTarget(name: "LayoutSwitcherCoreTests", dependencies: ["LayoutSwitcherCore"]),
        .testTarget(name: "LayoutSwitcherAppTests", dependencies: ["LayoutSwitcherApp", "LayoutSwitcherCore"]),
    ],
    swiftLanguageModes: [.v6]
)
