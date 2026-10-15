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
        // Notices wait until the docks are live, so an alert never blocks setup (REG-057).
        let notices = LaunchNotices { [weak self] in self?.show($0) }
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
                notices.post(.recovered(movedTo: moved.lastPathComponent, fromBackup: source == "backup"))
            }
        } catch {
            // Unreadable (not corrupt): leave the file alone and run on defaults without saving.
            DedockLog.event(.settings, "settings.readFailed", ["readOnly": true])
            DedockLog.error(.settings, "layout.json could not be read: \(error)")
            settings = SettingsModel(file: file, clock: clock, document: .makeDefault(nativeDockEdge: nativeEdge), readOnly: true)
            notices.post(.readOnly)
        }
        let topology = DisplayTopology(clock: clock)
        let hub = PointerHub(source: NSEventPointerSource(), clock: clock)
        let manager = EdgeDockManager(settings: settings, topology: topology, hub: hub, clock: clock,
                                      dataDirectory: env.dataDirectory, notices: notices)
        self.settings = settings
        self.topology = topology
        self.hub = hub
        self.manager = manager
        statusItem = StatusItemController(settings: settings, docks: manager)
    }

    /// Tells the user once about a layout problem found at launch (architecture §7). Runs after
    /// the docks are live (`LaunchNotices`).
    private func show(_ notice: LaunchNotices.Notice) {
        let alert = NSAlert()
        switch notice {
        case let .recovered(movedTo, fromBackup):
            DedockLog.event(.settings, "settings.notice", ["kind": "recovered"])
            alert.messageText = "Your Edge Dock layout was damaged"
            alert.informativeText = fromBackup
                ? "dedock restored the most recent backup. The damaged file was kept as \(movedTo)."
                : "dedock started with a fresh layout. The damaged file was kept as \(movedTo)."
        case .readOnly:
            DedockLog.event(.settings, "settings.notice", ["kind": "readOnly"])
            alert.messageText = "dedock can't read its layout file"
            alert.informativeText = "The Edge Dock is using the default layout. Changes you make won't be saved until the file can be read again."
        }
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
