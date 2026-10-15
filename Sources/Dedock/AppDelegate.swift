import AppKit
import DedockCore
import Diagnostics
import DisplayTopology
import EdgeDock
import EventTapKit
import SettingsStore

/// Composition root and lifecycle (architecture §8). The only place that sees every module.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var settings: SettingsModel?
    private var topology: DisplayTopology?
    private var hub: PointerHub?
    private var manager: EdgeDockManager?
    private var statusItem: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let env = DedockEnvironment.current
        DedockLog.event(.app, "app.launch", ["dataDir": env.dataDirectory.lastPathComponent, "e2e": env.e2e])
        Task { await start(env) }
    }

    private func start(_ env: DedockEnvironment) async {
        let clock = ContinuousClock()
        let file = LayoutFile(directory: env.dataDirectory)
        let nativeEdge = DockPreferencesReader.readOrientation()
        let settings: SettingsModel
        do {
            let (model, result) = try await SettingsModel.load(file: file, clock: clock, nativeDockEdge: nativeEdge)
            settings = model
            DedockLog.event(.settings, "settings.loaded", ["source": "\(result.source)", "docks": model.document.docks.count])
            if let error = model.lastSaveError {
                DedockLog.error(.settings, "saving the default layout failed: \(error)")
            }
            if let moved = result.corruptFileMovedTo {
                // One-time notice: the file is moved aside, so the next launch does not repeat it.
                let source = result.source == .defaultSeed ? "default" : "backup"
                DedockLog.event(.settings, "settings.recovered", ["source": source, "moved": moved.lastPathComponent])
                showRecoveryNotice(movedTo: moved, fromBackup: source == "backup")
            }
        } catch {
            // Unreadable (not corrupt): leave the file alone and run on defaults without saving.
            DedockLog.event(.settings, "settings.readFailed", ["readOnly": true])
            DedockLog.error(.settings, "layout.json could not be read: \(error)")
            settings = SettingsModel(file: file, clock: clock, document: .makeDefault(nativeDockEdge: nativeEdge), readOnly: true)
        }
        let topology = DisplayTopology(clock: clock)
        let hub = PointerHub(source: NSEventPointerSource(), clock: clock)
        let manager = EdgeDockManager(settings: settings, topology: topology, hub: hub, clock: clock,
                                      dataDirectory: env.dataDirectory)
        self.settings = settings
        self.topology = topology
        self.hub = hub
        self.manager = manager
        statusItem = StatusItemController(settings: settings, docks: manager)
    }

    /// Tells the user once that an unreadable layout was set aside (architecture §7).
    private func showRecoveryNotice(movedTo: URL, fromBackup: Bool) {
        DedockLog.event(.settings, "settings.notice", ["kind": "recovered"])
        let alert = NSAlert()
        alert.messageText = "Your Edge Dock layout was damaged"
        alert.informativeText = fromBackup
            ? "dedock restored the most recent backup. The damaged file was kept as \(movedTo.lastPathComponent)."
            : "dedock started with a fresh layout. The damaged file was kept as \(movedTo.lastPathComponent)."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        manager?.reveal(dock: nil)
        return false
    }

    /// Flush the debounced layout save before quitting.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let settings else { return .terminateNow }
        Task { @MainActor in
            await settings.flush()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
