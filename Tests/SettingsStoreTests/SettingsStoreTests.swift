import DedockCore
import Foundation
import Testing
@testable import SettingsStore

// MARK: - Helpers

func tempDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("dedock-settings-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

func decode(_ json: String) throws -> DedockDocument {
    try LayoutFile.decode(Data(json.utf8))
}

func object(_ data: Data) throws -> [String: JSONValue] {
    try #require(try JSONDecoder().decode(JSONValue.self, from: data).objectValue)
}

/// A clock whose `sleep` resumes only when the test advances time.
final class TestClock: Clock, @unchecked Sendable {
    struct Instant: InstantProtocol {
        var offset: Duration
        func advanced(by d: Duration) -> Instant { Instant(offset: offset + d) }
        func duration(to other: Instant) -> Duration { other.offset - offset }
        static func < (a: Instant, b: Instant) -> Bool { a.offset < b.offset }
    }

    private let lock = NSLock()
    private var current = Instant(offset: .zero)
    private var sleepers: [(deadline: Instant, continuation: CheckedContinuation<Void, any Error>)] = []

    var now: Instant { lock.withLock { current } }
    var minimumResolution: Duration { .nanoseconds(1) }
    var sleeperCount: Int { lock.withLock { sleepers.count } }

    func sleep(until deadline: Instant, tolerance: Duration?) async throws {
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, any Error>) in
            lock.lock()
            if deadline <= current {
                lock.unlock()
                c.resume()
            } else {
                sleepers.append((deadline, c))
                lock.unlock()
            }
        }
    }

    func advance(by d: Duration) {
        lock.lock()
        current = current.advanced(by: d)
        let due = sleepers.filter { $0.deadline <= current }
        sleepers.removeAll { $0.deadline <= current }
        lock.unlock()
        for s in due { s.continuation.resume() }
    }

    /// Waits until `count` tasks are sleeping on this clock.
    func waitForSleepers(_ count: Int) async {
        for _ in 0..<10_000 where sleeperCount < count { await Task.yield() }
    }
}

// MARK: - Coding

@Suite struct DocumentCodingTests {
    @Test func defaultDocumentRoundTrips() throws {
        let doc = DedockDocument.makeDefault()
        let data = try LayoutFile.encode(doc)
        #expect(try LayoutFile.decode(data) == doc)
    }

    @Test func encodedKeysMatchArchitectureSchema() throws {
        let data = try LayoutFile.encode(.makeDefault())
        let root = try object(data)
        #expect(Set(root.keys) == ["schemaVersion", "app", "profiles", "docks", "displays"])
        let dock = try #require(root["docks"]?.arrayValue?.first?.objectValue)
        #expect(Set(dock.keys) == ["id", "enabled", "edge", "mode", "scenario", "display", "profileID",
                                   "reveal", "placement", "appearance"])
        let reveal = try #require(dock["reveal"]?.objectValue)
        #expect(Set(reveal.keys) == ["showDwellMs", "fullscreenDwellMs", "hideDelayMs", "triggerThicknessPt",
                                     "spanMode", "cornerExclusionPt", "pushThroughPt", "hysteresisPt",
                                     "sharedEdgePolicy", "hideInFullscreen"])
        #expect(reveal["showDwellMs"] == .number(120))
        // Whole numbers are written without a fraction.
        #expect(String(decoding: data, as: UTF8.self).contains("\"showDwellMs\" : 120,"))
        #expect(root["app"]?.objectValue?["reduceMotionOverride"] == .null)
    }

    @Test func unknownKeysSurviveAtEveryLevel() throws {
        let json = """
        {
          "schemaVersion": 1,
          "futureTop": {"a": [1, 2, "x"]},
          "app": {"showStatusItem": false, "futureApp": true},
          "profiles": [{"id": "p", "name": "P", "futureProfile": 3,
                        "items": [{"id": "t1", "kind": "app", "bundleID": "com.apple.calculator", "futureTile": "keep"},
                                  {"id": "t2", "kind": "hologram", "gizmo": 7}]}],
          "docks": [{"id": "D1", "edge": "right", "futureDock": null,
                     "reveal": {"showDwellMs": 250, "futureReveal": 1.5},
                     "placement": {"futurePlacement": "y"}}],
          "displays": [{"identity": "UUID-1", "futureDisplay": false}]
        }
        """
        let doc = try decode(json)
        #expect(doc.unknown["futureTop"] == .object(["a": .array([.number(1), .number(2), .string("x")])]))
        #expect(doc.app.unknown["futureApp"] == .bool(true))
        #expect(doc.app.showStatusItem == false)
        #expect(doc.profiles[0].unknown["futureProfile"] == .number(3))
        #expect(doc.profiles[0].items[0].unknown["futureTile"] == .string("keep"))
        #expect(doc.profiles[0].items[1].kind.rawValue == "hologram")
        #expect(doc.docks[0].unknown["futureDock"] == .null)
        #expect(doc.docks[0].reveal.unknown["futureReveal"] == .number(1.5))
        #expect(doc.docks[0].reveal.showDwellMs == 250)
        #expect(doc.docks[0].placement.unknown["futurePlacement"] == .string("y"))
        #expect(doc.displays[0].unknown["futureDisplay"] == .bool(false))

        // Round-trip keeps all of it.
        let again = try LayoutFile.decode(LayoutFile.encode(doc))
        #expect(again == doc)
        let root = try object(LayoutFile.encode(doc))
        let tile = try #require(root["profiles"]?.arrayValue?[0].objectValue?["items"]?.arrayValue?[1].objectValue)
        #expect(tile["kind"] == .string("hologram"))
        #expect(tile["gizmo"] == .number(7))
    }

    @Test func minimalSeedDecodesWithDefaults() throws {
        let doc = try decode("""
        {"profiles": [{"items": [{"bundleID": "com.apple.calculator"}, {"path": "~/Downloads"},
                                 {"path": "/System/Applications/Notes.app"}]}],
         "docks": [{"edge": "right"}]}
        """)
        #expect(doc.schemaVersion == 1)
        let items = doc.profiles[0].items
        #expect(items.map(\.id) == ["t1", "t2", "t3"])
        #expect(items[0].kind == .app)
        #expect(items[0].bookmark == nil)
        #expect(items[1].kind == .folder)
        #expect(items[1].path == FileManager.default.homeDirectoryForCurrentUser.path + "/Downloads")
        #expect(items[2].kind == .app)
        let dock = try #require(doc.docks.first)
        #expect(dock.edge == .right)
        #expect(dock.mode == .reveal)
        #expect(dock.enabled)
        #expect(dock.reveal == RevealSettings())
        #expect(dock.placement == PlacementSettings())
        #expect(dock.appearance == AppearanceSettings())
        #expect(dock.display == DisplayBinding())
    }

    @Test func mistypedFieldsFallBackToDefaults() throws {
        let doc = try decode("""
        {"docks": [{"id": "D1", "edge": "diagonal", "mode": 3, "enabled": "yes",
                    "reveal": {"showDwellMs": "fast", "hideDelayMs": 250.6, "spanMode": "everywhere"}}]}
        """)
        let dock = try #require(doc.docks.first)
        #expect(dock.edge == .left)
        #expect(dock.mode == .reveal)
        #expect(dock.enabled)
        #expect(dock.reveal.showDwellMs == 120)
        #expect(dock.reveal.hideDelayMs == 251)
        #expect(dock.reveal.spanMode == .content)
    }

    @Test func pushThroughNullMeansOffAndMissingMeansDefault() throws {
        let off = try decode(#"{"docks": [{"reveal": {"pushThroughPt": null}}]}"#)
        #expect(off.docks[0].reveal.pushThroughPt == nil)
        let missing = try decode(#"{"docks": [{"reveal": {}}]}"#)
        #expect(missing.docks[0].reveal.pushThroughPt == 40)
        // `null` is written back explicitly, so "off" survives a round-trip.
        #expect(try LayoutFile.decode(LayoutFile.encode(off)).docks[0].reveal.pushThroughPt == nil)
    }

    @Test func bookmarkRoundTripsAsBase64() throws {
        let bytes = Data([0, 1, 2, 250, 255])
        var doc = DedockDocument.makeDefault()
        doc.profiles[0].items.append(TileItem(id: "f", kind: .folder, bookmark: bytes, displayName: "Docs"))
        let data = try LayoutFile.encode(doc)
        #expect(String(decoding: data, as: UTF8.self).contains(bytes.base64EncodedString()))
        #expect(try LayoutFile.decode(data).profiles[0].items.last?.bookmark == bytes)
    }

    @Test func topEdgeIsAccepted() throws {
        #expect(try decode(#"{"docks": [{"edge": "top"}]}"#).docks[0].edge == .top)
    }

    @Test func notAnObjectFails() {
        #expect(throws: (any Error).self) { try decode("[1, 2]") }
        #expect(throws: (any Error).self) { try decode("{ nope") }
    }

    @Test func e2eSeedFixtureDecodes() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("E2E/fixtures/layout-seed.json")
        let doc = try LayoutFile.decode(Data(contentsOf: url))
        let dock = try #require(doc.docks.first)
        #expect(dock.id == "dock-0")
        #expect(dock.edge == .left)
        #expect(dock.mode == .reveal)
        #expect(dock.display.role == .main)
        let profile = try #require(doc.profile(dock.profileID))
        #expect(profile.items.compactMap(\.bundleID) == ["com.apple.calculator", "com.apple.TextEdit", "com.apple.Notes"])
        let downloads = try #require(profile.items.last)
        #expect(downloads.kind == .folder)
        #expect(downloads.path == FileManager.default.homeDirectoryForCurrentUser.path + "/Downloads")
        #expect(dock.reveal == RevealSettings())
    }
}

// MARK: - Default seed

@Suite struct DefaultSeedTests {
    @Test(arguments: [
        (ScreenEdge?.some(.bottom), ScreenEdge.left, "revealLeft"),
        (.some(.right), .left, "revealLeft"),
        (.some(.left), .right, "revealRight"),
        (nil, .left, "revealLeft"),
    ])
    func recommendedEdgeFollowsNativeDock(native: ScreenEdge?, expected: ScreenEdge, scenario: String) {
        let doc = DedockDocument.makeDefault(nativeDockEdge: native)
        #expect(doc.docks.count == 1)
        #expect(doc.docks[0].edge == expected)
        #expect(doc.docks[0].mode == .reveal)
        #expect(doc.docks[0].scenario == scenario)
    }

    @Test func defaultProfileHasFinderSafariSystemSettings() throws {
        let doc = DedockDocument.makeDefault()
        let profile = try #require(doc.profile(doc.docks[0].profileID))
        #expect(profile.name == "Default")
        #expect(profile.items.compactMap(\.bundleID) == ["com.apple.finder", "com.apple.Safari", "com.apple.systempreferences"])
        #expect(profile.items.allSatisfy { $0.kind == .app && $0.path != nil })
    }
}

// MARK: - LayoutFile

@Suite struct LayoutFileTests {
    @Test func missingFileSeedsDefault() async throws {
        let dir = try tempDirectory()
        let file = LayoutFile(directory: dir)
        let result = try await file.load(nativeDockEdge: .left)
        #expect(result.source == .defaultSeed)
        #expect(result.document.docks[0].edge == .right)
        #expect(result.corruptFileMovedTo == nil)
        // Loading does not write.
        #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("layout.json").path))
    }

    @Test func saveThenLoadRoundTrips() async throws {
        let dir = try tempDirectory()
        let file = LayoutFile(directory: dir.appendingPathComponent("nested", isDirectory: true))
        var doc = DedockDocument.makeDefault()
        doc.docks[0].reveal.hideDelayMs = 900
        try await file.save(doc)
        let result = try await file.load()
        #expect(result.source == .file)
        #expect(result.document == doc)
    }

    @Test func corruptFileIsMovedAsideAndNewestBackupUsed() async throws {
        let dir = try tempDirectory()
        let file = LayoutFile(directory: dir)
        var first = DedockDocument.makeDefault()
        first.docks[0].reveal.showDwellMs = 111
        var second = first
        second.docks[0].reveal.showDwellMs = 222
        try await file.save(first)
        try await file.save(second)  // first → layout.json.1
        try Data("{ not json".utf8).write(to: dir.appendingPathComponent("layout.json"))

        let result = try await file.load()
        #expect(result.source == .backup(1))
        #expect(result.document.docks[0].reveal.showDwellMs == 111)
        let moved = try #require(result.corruptFileMovedTo)
        #expect(moved.lastPathComponent.hasPrefix("layout.corrupt-"))
        #expect(moved.pathExtension == "json")
        #expect(try String(contentsOf: moved, encoding: .utf8) == "{ not json")
        #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("layout.json").path))
    }

    @Test func corruptFileWithoutBackupsSeedsDefault() async throws {
        let dir = try tempDirectory()
        try Data("[]".utf8).write(to: dir.appendingPathComponent("layout.json"))
        let result = try await LayoutFile(directory: dir).load()
        #expect(result.source == .defaultSeed)
        #expect(result.corruptFileMovedTo != nil)
    }

    @Test func savesKeepFiveRollingBackups() async throws {
        let dir = try tempDirectory()
        let file = LayoutFile(directory: dir)
        for n in 1...8 {
            var doc = DedockDocument.makeDefault()
            doc.docks[0].reveal.hideDelayMs = n
            try await file.save(doc)
        }
        func hideDelay(_ name: String) throws -> Int {
            try LayoutFile.decode(Data(contentsOf: dir.appendingPathComponent(name))).docks[0].reveal.hideDelayMs
        }
        #expect(try hideDelay("layout.json") == 8)
        for n in 1...5 { #expect(try hideDelay("layout.json.\(n)") == 8 - n) }
        #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("layout.json.6").path))
    }

    @Test func fileIsPrettyPrintedWithSortedKeys() async throws {
        let dir = try tempDirectory()
        try await LayoutFile(directory: dir).save(.makeDefault())
        let text = try String(contentsOf: dir.appendingPathComponent("layout.json"), encoding: .utf8)
        #expect(text.contains("\n  \"app\" : {"))
        let topKeys = ["\"app\"", "\"displays\"", "\"docks\"", "\"profiles\"", "\"schemaVersion\""]
        let positions = topKeys.compactMap { text.range(of: "\n  \($0)")?.lowerBound }
        #expect(positions.count == topKeys.count)
        #expect(positions == positions.sorted())
    }
}

// MARK: - Migration

@Suite struct MigrationTests {
    @Test func currentSchemaIsUnchanged() throws {
        let o: [String: JSONValue] = ["schemaVersion": .number(1), "x": .bool(true)]
        #expect(try Migration.migrate(o) == o)
    }

    @Test func stepsRunInOrderAndBumpVersion() throws {
        let steps: [Int: Migration.Step] = [
            1: { var o = $0; o["trail"] = .string((o["trail"]?.stringValue ?? "") + "1"); return o },
            2: { var o = $0; o["trail"] = .string((o["trail"]?.stringValue ?? "") + "2"); return o },
        ]
        let out = try Migration.migrate(["schemaVersion": .number(1)], steps: steps, to: 3)
        #expect(out["trail"] == .string("12"))
        #expect(out["schemaVersion"] == .number(3))
    }

    @Test func missingStepThrows() {
        #expect(throws: MigrationError.missingStep(from: 1)) {
            try Migration.migrate(["schemaVersion": .number(1)], steps: [:], to: 2)
        }
    }

    @Test func newerSchemaIsLoadedAsIs() throws {
        let doc = try decode(#"{"schemaVersion": 7, "docks": [{"edge": "right"}]}"#)
        #expect(doc.schemaVersion == 7)
        #expect(doc.docks[0].edge == .right)
    }
}

// MARK: - SettingsModel

@MainActor @Suite struct SettingsModelTests {
    @Test func updateNotifiesObserversAndDebouncesSave() async throws {
        let dir = try tempDirectory()
        let file = LayoutFile(directory: dir)
        let clock = TestClock()
        let model = SettingsModel(file: file, clock: clock, document: .makeDefault())
        var seen: [Int] = []
        model.addObserver { seen.append($0.docks[0].reveal.hideDelayMs) }
        let layout = dir.appendingPathComponent("layout.json")

        model.update { $0.docks[0].reveal.hideDelayMs = 100 }
        await clock.waitForSleepers(1)
        clock.advance(by: .milliseconds(300))
        model.update { $0.docks[0].reveal.hideDelayMs = 200 }   // restarts the debounce
        await clock.waitForSleepers(2)
        clock.advance(by: .milliseconds(400))                   // 400 ms after the last change
        for _ in 0..<50 { await Task.yield() }
        #expect(!FileManager.default.fileExists(atPath: layout.path))

        clock.advance(by: .milliseconds(100))                   // 500 ms after the last change
        await model.pendingSave?.value
        #expect(seen == [100, 200])
        #expect(try LayoutFile.decode(Data(contentsOf: layout)).docks[0].reveal.hideDelayMs == 200)
        // One save only: no backup was rotated.
        #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("layout.json.1").path))
    }

    @Test func noOpUpdateDoesNothing() async throws {
        let dir = try tempDirectory()
        let clock = TestClock()
        let model = SettingsModel(file: LayoutFile(directory: dir), clock: clock, document: .makeDefault())
        var calls = 0
        model.addObserver { _ in calls += 1 }
        model.update { _ in }
        #expect(calls == 0)
        #expect(model.pendingSave == nil)
    }

    @Test func flushSavesImmediately() async throws {
        let dir = try tempDirectory()
        let model = SettingsModel(file: LayoutFile(directory: dir), clock: TestClock(), document: .makeDefault())
        model.update { $0.app.showStatusItem = false }
        await model.flush()
        let saved = try LayoutFile.decode(Data(contentsOf: dir.appendingPathComponent("layout.json")))
        #expect(saved.app.showStatusItem == false)
    }

    @Test func flushWithoutChangesWritesNothing() async throws {
        let dir = try tempDirectory()
        let model = SettingsModel(file: LayoutFile(directory: dir), clock: TestClock(), document: .makeDefault())
        await model.flush()
        #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("layout.json").path))
    }

    @Test func removedObserverIsNotCalled() async throws {
        let model = SettingsModel(file: LayoutFile(directory: try tempDirectory()), clock: TestClock(),
                                  document: .makeDefault())
        var calls = 0
        let token = model.addObserver { _ in calls += 1 }
        model.removeObserver(token)
        model.update { $0.app.showStatusItem = false }
        #expect(calls == 0)
    }

    @Test func loadBuildsModelFromFile() async throws {
        let dir = try tempDirectory()
        let file = LayoutFile(directory: dir)
        var doc = DedockDocument.makeDefault()
        doc.docks[0].edge = .bottom
        try await file.save(doc)
        let (model, result) = try await SettingsModel.load(file: file, clock: TestClock())
        #expect(result.source == .file)
        #expect(model.document.docks[0].edge == .bottom)
    }
}
