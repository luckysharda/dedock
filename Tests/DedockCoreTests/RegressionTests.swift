import DedockCore
import Foundation
import Testing

/// Unit-level regression guards (Tests/E2E/regressions.md). Runs on macOS and Linux.
@Suite("Regression", .tags(.regression)) struct CoreRegressionTests {
    /// REG-022: CGVector is missing from swift-corelibs-foundation; DedockCore provides it on
    /// Linux so PointerSample keeps its Equatable conformance. This test compiles on both.
    @Test("REG-022: CGVector and PointerSample equality on every platform")
    func reg022() {
        let v = CGVector(dx: 3, dy: -4)
        #expect(v == CGVector(dx: 3, dy: -4))
        #expect(CGVector.zero == CGVector(dx: 0, dy: 0))
        let a = PointerSample(location: .zero, delta: v, timestamp: .milliseconds(1))
        #expect(a == PointerSample(location: .zero, delta: v, timestamp: .milliseconds(1)))
        #expect(a.push(toward: .right) == 3)
    }

    /// REG-060: Scripts/check-deps.sh passed when a checked directory was missing (renamed), and
    /// read `import struct Foundation.URL` as an import of module `struct`.
    @Test("REG-060: check-deps fails closed on a missing directory and parses import kinds")
    func reg060() throws {
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let script = repo.appendingPathComponent("Scripts/check-deps.sh")
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("dedock-reg060-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: root) }
        func write(_ path: String, _ text: String) throws {
            let url = root.appendingPathComponent(path)
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(text.utf8).write(to: url)
        }
        func run() throws -> (status: Int32, output: String) {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/bin/bash")
            p.arguments = [script.path]
            p.environment = ["CHECK_DEPS_ROOT": root.path, "PATH": "/usr/bin:/bin"]
            let pipe = Pipe()
            p.standardOutput = pipe
            p.standardError = pipe
            try p.run()
            p.waitUntilExit()
            return (p.terminationStatus, String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self))
        }

        try write("Sources/DedockCore/A.swift", "import struct Foundation.URL\n")
        let missing = try run()                          // Sources/EdgeDock/Logic does not exist
        #expect(missing.status != 0)
        #expect(missing.output.contains("D5: Sources/EdgeDock/Logic missing"))

        try write("Sources/EdgeDock/Logic/B.swift", "import DedockCore\n")
        let clean = try run()
        #expect(clean.status == 0, "\(clean.output)")    // `struct Foundation.URL` is module Foundation

        try write("Sources/DedockCore/C.swift", "import class AppKit.NSView\n")
        let violation = try run()
        #expect(violation.status != 0)
        #expect(violation.output.contains("imports AppKit"))
    }
}
