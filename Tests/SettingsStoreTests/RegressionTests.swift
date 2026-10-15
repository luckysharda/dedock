import DedockCore
import Foundation
import Testing
@testable import SettingsStore

@Suite("Regression", .tags(.regression)) struct SettingsRegressionTests {
    /// REG-026: the first launch never wrote layout.json (the save was a no-op update), and the
    /// decoder's edge-inset default (6) disagreed with the model's (8).
    @Test("REG-026: first launch writes layout.json with the model's edge inset")
    @MainActor func reg026() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("dedock-reg-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = LayoutFile(directory: dir)
        let (_, result) = try await SettingsModel.load(file: file, clock: ContinuousClock())
        #expect(result.source == .defaultSeed)
        let data = try Data(contentsOf: dir.appendingPathComponent("layout.json"))
        let saved = try LayoutFile.decode(data)
        #expect(saved.docks.first?.placement.edgeGapPt == PlacementSettings().edgeGapPt)
        #expect(PlacementSettings(object: [:]).edgeGapPt == PlacementSettings().edgeGapPt)
    }
}
