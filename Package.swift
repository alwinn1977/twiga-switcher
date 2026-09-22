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
        .testTarget(name: "LayoutSwitcherCoreTests", dependencies: ["LayoutSwitcherCore"]),
    ],
    swiftLanguageModes: [.v6]
)
