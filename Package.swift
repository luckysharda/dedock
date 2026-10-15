// swift-tools-version: 6.2
import PackageDescription

// SwiftPM-first build (architecture.md §1, §4.1): the machine has only the Command Line Tools,
// so Scripts/make-app.sh assembles build/Dedock.app from the `Dedock` product.
let strict: [SwiftSetting] = [
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .enableUpcomingFeature("InferIsolatedConformances"),
    .enableUpcomingFeature("ExistentialAny"),
]
// `NonisolatedNonsendingByDefault` on a test target breaks swift-testing's macro plugin with the
// Command Line Tools toolchain ("plugin for module 'TestingMacros' not found"), so test targets
// use the other two flags only.
let testStrict: [SwiftSetting] = [
    .enableUpcomingFeature("InferIsolatedConformances"),
    .enableUpcomingFeature("ExistentialAny"),
]

#if os(macOS)
let package = Package(
    name: "Dedock",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Dedock", targets: ["Dedock"])],
    targets: [
        // L0
        .target(name: "DedockCore", swiftSettings: strict),
        // L1
        .target(name: "Diagnostics", dependencies: ["DedockCore"], swiftSettings: strict),
        .target(name: "DesignSystem", dependencies: ["DedockCore"], swiftSettings: strict),
        .target(name: "DisplayTopology", dependencies: ["DedockCore", "Diagnostics"], swiftSettings: strict),
        // L2
        .target(name: "EventTapKit", dependencies: ["DedockCore", "Diagnostics"], swiftSettings: strict),
        .target(name: "SettingsStore", dependencies: ["DedockCore"], swiftSettings: strict),
        // L3
        .target(name: "EdgeDock", dependencies: ["DedockCore", "Diagnostics", "DesignSystem",
                                                 "DisplayTopology", "EventTapKit", "SettingsStore"],
                swiftSettings: strict),
        // L4
        .target(name: "SettingsUI", dependencies: ["DedockCore", "DesignSystem", "SettingsStore"],
                swiftSettings: strict),
        // App
        .executableTarget(name: "Dedock", dependencies: ["DedockCore", "Diagnostics", "DesignSystem", "DisplayTopology",
                                                         "EventTapKit", "SettingsStore", "EdgeDock", "SettingsUI"],
                          swiftSettings: strict),
        // Tests
        .target(name: "DedockTestSupport", dependencies: ["DedockCore", "EventTapKit", "EdgeDock"],
                path: "Tests/DedockTestSupport", swiftSettings: testStrict),
    ] + ["DedockCore", "EventTapKit", "SettingsStore", "EdgeDock", "DisplayTopology", "Diagnostics"].map {
        .testTarget(name: "\($0)Tests", dependencies: ($0 == "DedockCore" ? [] : ["DedockCore"]) + [.target(name: $0), "DedockTestSupport"],
                    swiftSettings: testStrict)
    },
    swiftLanguageModes: [.v6]
)
#else
// Linux CI (swift:6.2): only the Foundation-only pure logic builds and tests. AppKit modules,
// the app and the AppKit-backed EdgeDock files are macOS-only.
let package = Package(
    name: "Dedock",
    targets: [
        .target(name: "DedockCore", swiftSettings: strict),
        .target(name: "SettingsStore", dependencies: ["DedockCore"], swiftSettings: strict),
        .target(name: "EdgeDock", dependencies: ["DedockCore"],
                exclude: ["Controller", "Panel", "Tiles", "NativeDock", "Displays", "E2E"],
                sources: ["Logic"], swiftSettings: strict),
        .testTarget(name: "DedockCoreTests", dependencies: ["DedockCore"], swiftSettings: testStrict),
        .testTarget(name: "SettingsStoreTests", dependencies: ["SettingsStore", "DedockCore"], swiftSettings: testStrict),
        .testTarget(name: "EdgeDockTests", dependencies: ["EdgeDock", "DedockCore"],
                    exclude: ["NativeDockTests.swift", "AnimatorRegressionTests.swift", "AccessibilityRegressionTests.swift", "ReorderTests.swift", "AppRegressionTests.swift", "MappingRegressionTests.swift", "EdgeRevealControllerTests.swift"], swiftSettings: testStrict),
    ],
    swiftLanguageModes: [.v6]
)
#endif
