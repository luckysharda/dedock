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
        .target(name: "SettingsStore", dependencies: ["DedockCore", "Diagnostics"], swiftSettings: strict),
        // L3
        .target(name: "EdgeDock", dependencies: ["DedockCore", "Diagnostics", "DesignSystem",
                                                 "DisplayTopology", "EventTapKit", "SettingsStore"],
                swiftSettings: strict),
        // App
        .executableTarget(name: "Dedock", dependencies: ["DedockCore", "Diagnostics", "DesignSystem", "DisplayTopology",
                                                         "EventTapKit", "SettingsStore", "EdgeDock"],
                          swiftSettings: strict),
        // Tests
        .target(name: "DedockTestSupport", dependencies: ["DedockCore", "EventTapKit", "EdgeDock"],
                path: "Tests/DedockTestSupport", swiftSettings: testStrict),
    ] + ["DedockCore", "EventTapKit", "SettingsStore", "EdgeDock", "DisplayTopology"].map {
        .testTarget(name: "\($0)Tests", dependencies: ($0 == "DedockCore" ? [] : ["DedockCore"]) + [.target(name: $0), "DedockTestSupport"],
                    swiftSettings: testStrict)
    },
    swiftLanguageModes: [.v6]
)
