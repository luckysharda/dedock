import AppKit
import DedockCore
import EdgeDock
import SettingsStore

/// The menu-bar item (T18 subset): show the dock, keep it open, pick edge and mode, quit.
@MainActor final class StatusItemController: NSObject, NSMenuDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let settings: SettingsModel
    private let docks: EdgeDockManager
    private let openSettings: () -> Void

    init(settings: SettingsModel, docks: EdgeDockManager, openSettings: @escaping () -> Void) {
        self.settings = settings
        self.docks = docks
        self.openSettings = openSettings
        super.init()
        item.button?.image = NSImage(systemSymbolName: "rectangle.lefthalf.inset.filled", accessibilityDescription: "Dedock")
        item.button?.image?.isTemplate = true
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
    }

    private var firstDock: DockConfig? { settings.document.docks.first }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
        menu.addItem(withTitle: "Dedock \(version)", action: nil, keyEquivalent: "").isEnabled = false
        menu.addItem(.separator())
        add(menu, "Show Edge Dock", #selector(showDock))
        let keep = add(menu, "Keep Edge Dock Open", #selector(toggleKeepOpen))
        keep.state = docks.isHeldOpen ? .on : .off

        let edgeMenu = NSMenu()
        for edge in ScreenEdge.allCases {
            let i = add(edgeMenu, edge.title, #selector(pickEdge(_:)))
            i.representedObject = edge.rawValue
            i.state = firstDock?.edge == edge ? .on : .off
        }
        menu.addItem(withTitle: "Edge", action: nil, keyEquivalent: "").submenu = edgeMenu

        let modeMenu = NSMenu()
        for mode in DockConfig.Mode.allCases {
            let i = add(modeMenu, mode == .reveal ? "Reveal" : "Pinned", #selector(pickMode(_:)))
            i.representedObject = mode.rawValue
            i.state = firstDock?.mode == mode ? .on : .off
        }
        menu.addItem(withTitle: "Mode", action: nil, keyEquivalent: "").submenu = modeMenu

        menu.addItem(.separator())
        add(menu, "Settings…", #selector(showSettings), key: ",")
        add(menu, "Quit Dedock", #selector(NSApplication.terminate(_:)), key: "q", target: NSApp)
    }

    // The dock stays put while this menu is open (the hub swaps to its timer fallback).
    func menuWillOpen(_ menu: NSMenu) { docks.setHold(.menuOpen, true, dock: nil) }
    func menuDidClose(_ menu: NSMenu) { docks.setHold(.menuOpen, false, dock: nil) }

    @discardableResult
    private func add(_ menu: NSMenu, _ title: String, _ action: Selector, key: String = "", target: AnyObject? = nil) -> NSMenuItem {
        let i = menu.addItem(withTitle: title, action: action, keyEquivalent: key)
        i.target = target ?? self
        return i
    }

    @objc private func showDock() { docks.reveal(dock: nil) }
    @objc private func showSettings() { openSettings() }

    @objc private func toggleKeepOpen() {
        let on = !docks.isHeldOpen
        docks.setHold(.pinnedByUser, on, dock: nil)
        if on { docks.reveal(dock: nil) }
    }

    @objc private func pickEdge(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let edge = ScreenEdge(rawValue: raw) else { return }
        settings.update { doc in
            guard !doc.docks.isEmpty else { return }
            doc.docks[0].edge = edge
            doc.docks[0].markCustom()
        }
    }

    @objc private func pickMode(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let mode = DockConfig.Mode(rawValue: raw) else { return }
        settings.update { doc in
            guard !doc.docks.isEmpty else { return }
            doc.docks[0].mode = mode
            doc.docks[0].markCustom()
        }
    }
}

private extension ScreenEdge {
    var title: String {
        switch self {
        case .left: "Left"
        case .right: "Right"
        case .bottom: "Bottom (beta)"
        case .top: "Top (beta)"
        }
    }
}
