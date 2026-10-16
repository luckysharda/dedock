import Foundation
import Testing

/// T24: Scripts/make-signing-identity.sh is run by the user only; tests exercise its dry run and
/// argument checks, which change nothing.
@Suite struct SigningScriptTests {
    static let script = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent("Scripts/make-signing-identity.sh")

    func run(_ args: [String]) throws -> (status: Int32, output: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/bash")
        p.arguments = [Self.script.path] + args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        try p.run()
        p.waitUntilExit()
        return (p.terminationStatus, String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self))
    }

    @Test func dryRunChangesNothingAndMasksThePassword() throws {
        let r = try run(["--dry-run", "--name", "Dedock Test", "--keychain", "/tmp/none.keychain-db"])
        #expect(r.status == 0)
        #expect(r.output.contains("would run: /usr/bin/openssl req -x509"))
        #expect(r.output.contains("extendedKeyUsage=critical,codeSigning"))
        #expect(r.output.contains("/usr/bin/security import"))
        #expect(r.output.contains("dry run: nothing changed"))
        #expect(r.output.contains("-passout env:DEDOCK_P12_PASS"))          // not on the command line
        #expect(!r.output.contains("pass:") || r.output.contains("pass:***"))
    }

    @Test func rejectsBadArguments() throws {
        #expect(try run(["--bogus"]).status == 2)
        #expect(try run(["--days", "abc"]).status == 2)
        #expect(try run(["--name", "a\"b"]).status == 2)
        #expect(try run(["--name", "a+b"]).status == 2)
        #expect(try run(["--name", "a=b"]).status == 2)
        #expect(try run(["--name"]).status != 0)
    }
}
