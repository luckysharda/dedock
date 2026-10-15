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

    /// When true the model never writes: used when layout.json exists but cannot be read, so
    /// in-memory defaults never overwrite the user's file (REG-036).
    public let isReadOnly: Bool

    public init(file: LayoutFile, clock: any Clock<Duration>, document: DedockDocument,
                saveDelay: Duration = .milliseconds(500), readOnly: Bool = false) {
        self.file = file
        self.clock = clock
        self.document = document
        self.saveDelay = saveDelay
        self.isReadOnly = readOnly
    }

    /// Loads the document from `file` (with corruption recovery) and builds the model.
    public static func load(file: LayoutFile, clock: any Clock<Duration>,
                            nativeDockEdge: ScreenEdge? = .bottom) async throws
        -> (model: SettingsModel, result: LayoutFile.LoadResult) {
        let result = try await file.load(nativeDockEdge: nativeDockEdge)
        let model = SettingsModel(file: file, clock: clock, document: result.document)
        // First launch: write the seeded default at once, so the file exists from now on.
        // (`update` would not save it: an unchanged document is a no-op.)
        if result.source == .defaultSeed {
            do { try await file.save(result.document) } catch { model.lastSaveError = "\(error)" }
        }
        return (model, result)
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

    /// The save currently writing, if any. Saves are serialized through it.
    private var writing: Task<Void, Never>?
    /// True while a save is writing to disk.
    public var isWriting: Bool { writing != nil }

    /// Saves now if anything is pending, after waiting for a save already writing (on quit).
    /// Returning early while the debounced save was mid-write let the app quit before the file
    /// was complete (REG-037).
    public func flush() async {
        pendingSave?.cancel()
        pendingSave = nil
        await waitForWrite()
        guard isDirty else { return }
        await saveNow()
    }

    /// Waits until no save is writing. Whoever resumes first clears the finished task.
    private func waitForWrite() async {
        while let w = writing {
            await w.value
            if writing == w { writing = nil }
        }
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
        guard !isReadOnly else { return }
        await waitForWrite()
        let snapshot = document
        isDirty = false
        let file = self.file
        let task = Task { @MainActor [weak self] in
            do {
                try await file.save(snapshot)
                self?.lastSaveError = nil
            } catch {
                self?.isDirty = true
                self?.lastSaveError = String(describing: error)
            }
        }
        writing = task
        await task.value
        if writing == task { writing = nil }
    }
}
