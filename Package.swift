// swift-tools-version: 6.2
import PackageDescription

// SwiftPM-first build: the machine has only the Command Line Tools (no Xcode),
// so the app bundle is assembled by Scripts/make-app.sh from the `Dedock` product.
let package = Package(
    name: "Dedock",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Dedock", targets: ["Dedock"]),
        .library(name: "DedockCore", targets: ["DedockCore"]),
        .library(name: "EdgeDock", targets: ["EdgeDock"]),
    ],
    targets: [
        // L0: value types and geometry. Foundation + CoreGraphics only (architecture rule D4).
        .target(name: "DedockCore"),
        // L3: Edge Dock. Trigger/ and Reveal/ are pure logic; AppKit surfaces land later.
        .target(name: "EdgeDock", dependencies: ["DedockCore"]),
        // Composition root: agent app with a status item.
        .executableTarget(name: "Dedock", dependencies: ["DedockCore", "EdgeDock"]),

        .testTarget(name: "DedockCoreTests", dependencies: ["DedockCore"]),
        .testTarget(name: "EdgeDockTests", dependencies: ["EdgeDock", "DedockCore"]),
    ],
    swiftLanguageModes: [.v6]
)
