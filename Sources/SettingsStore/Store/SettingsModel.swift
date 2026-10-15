import DedockCore
import Foundation
import Observation

/// The observable settings document the UI and the Edge Dock bind to (architecture §7).
///
/// Changes go through `update(_:)`, which notifies observers at once and schedules a debounced
/// save (500 ms by default) on the injected clock. Never call `update` from a SwiftUI `body`.
@MainActor @Observable public final class SettingsModel {
    public private(set) var document: DedockDocument
    /// The last save error, if any (cleared by a successful save).
    public private(set) var lastSaveError: String?

    @ObservationIgnored public let file: LayoutFile
    @ObservationIgnored private let clock: any Clock<Duration>
    @ObservationIgnored private let saveDelay: Duration
    @ObservationIgnored private var observers: [UUID: @MainActor (DedockDocument) -> Void] = [:]
    @ObservationIgnored private(set) var pendingSave: Task<Void, Never>?
    @ObservationIgnored private var isDirty = false

    public init(file: LayoutFile, clock: any Clock<Duration>, document: DedockDocument,
                saveDelay: Duration = .milliseconds(500)) {
        self.file = file
        self.clock = clock
        self.document = document
        self.saveDelay = saveDelay
    }

    /// Loads the document from `file` (with corruption recovery) and builds the model.
    public static func load(file: LayoutFile, clock: any Clock<Duration>,
                            nativeDockEdge: ScreenEdge? = .bottom) async throws
        -> (model: SettingsModel, result: LayoutFile.LoadResult) {
        let result = try await file.load(nativeDockEdge: nativeDockEdge)
        return (SettingsModel(file: file, clock: clock, document: result.document), result)
    }

    /// Mutates the document, notifies observers and schedules the debounced save.
    /// A change that leaves the document equal does nothing.
    public func update(_ change: (inout DedockDocument) -> Void) {
        var next = document
        change(&next)
        guard next != document else { return }
        document = next
        isDirty = true
        for observer in observers.values { observer(next) }
        scheduleSave()
    }

    /// Registers a change handler; returns a token for `removeObserver`.
    @discardableResult
    public func addObserver(_ handler: @escaping @MainActor (DedockDocument) -> Void) -> UUID {
        let id = UUID()
        observers[id] = handler
        return id
    }

    public func removeObserver(_ id: UUID) { observers[id] = nil }

    /// Saves now if anything is pending (on quit).
    public func flush() async {
        pendingSave?.cancel()
        pendingSave = nil
        guard isDirty else { return }
        await saveNow()
    }

    private func scheduleSave() {
        pendingSave?.cancel()
        let clock = self.clock
        let delay = saveDelay
        pendingSave = Task { [weak self] in
            do { try await clock.sleep(for: delay) } catch { return }
            guard let self, !Task.isCancelled else { return }
            await self.saveNow()
        }
    }

    private func saveNow() async {
        let snapshot = document
        isDirty = false
        do {
            try await file.save(snapshot)
            lastSaveError = nil
        } catch {
            isDirty = true
            lastSaveError = String(describing: error)
        }
    }
}
