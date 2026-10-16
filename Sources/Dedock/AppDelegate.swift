import AppKit
import DedockCore
import Diagnostics
import DisplayTopology
import EdgeDock
import EventTapKit
import SettingsStore
import SettingsUI

/// Composition root and lifecycle (architecture §8). The only place that sees every module.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var settings: SettingsModel?
    private var topology: DisplayTopology?
    private var hub: PointerHub?
    private var manager: EdgeDockManager?
    private var statusItem: StatusItemController?
    private var settingsWindow: SettingsWindowController?

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
            if let newer = result.newerSchema {
                // A newer build wrote this file: loaded as far as we understand it, not migrated
                // down, not written until the user changes something (architecture §7).
                DedockLog.event(.settings, "settings.newerSchema", ["version": newer])
            }
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
        let settingsWindow = SettingsWindowController(settings: settings, environment: SettingsEnvironment(
            nativeDockEdge: { DockPreferencesReader.readOrientation() },
            hasSharedEdge: { [weak topology] edge in
                guard let layout = topology?.layout, let main = layout.main else { return false }
                return !EdgeGeometry.sharedSegments(of: main, edge: edge, in: layout).isEmpty
            },
            triggerHint: { [weak manager] in manager?.triggerHint }))
        // While Settings is open the dock stays revealed, so every change shows live.
        settingsWindow.onVisibilityChange = { [weak manager] open in
            manager?.setHold(.editing, open, dock: nil)
            if open { manager?.reveal(dock: nil) }
        }
        self.settingsWindow = settingsWindow
        // Debug command `openSettings` (E2E): opens the same window as Settings… ⌘,.
        manager.onOpenSettings = { [weak settingsWindow] in settingsWindow?.show() }
        statusItem = StatusItemController(settings: settings, docks: manager) { [weak settingsWindow] in settingsWindow?.show() }
    }

    /// Notices on screen; each is released when its OK is clicked.
    private var noticePanels: [LaunchNoticePanel] = []

    /// Tells the user once about a layout problem found at launch (architecture §7). Runs after
    /// the docks are live (`LaunchNotices`), in a non-modal panel so the dock keeps working
    /// behind it (REG-057).
    private func show(_ notice: LaunchNotices.Notice) {
        switch notice {
        case .recovered: DedockLog.event(.settings, "settings.notice", ["kind": "recovered"])
        case .readOnly: DedockLog.event(.settings, "settings.notice", ["kind": "readOnly"])
        }
        let panel = LaunchNoticePanel(notice) { [weak self] closed in
            self?.noticePanels.removeAll { $0 === closed }
        }
        noticePanels.append(panel)
        panel.show()
    }

    /// Launching dedock again while it runs opens Settings (plan T18 item 3).
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        settingsWindow?.show()
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
