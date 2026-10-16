import AppKit
import DedockCore
import Diagnostics

/// The pending question after a tile was dragged out of the dock (evaluation row 43, design
/// §2.3a). It answers exactly once: Remove, Keep, or Keep after `timeout` without an answer.
@MainActor final class RemovalConfirmation {
    enum Result: String { case remove, keep, timeout }

    let tile: TileID
    private let onResult: (Result) -> Void
    private let clock: any Clock<Duration>
    private let timeout: Duration
    private var timer: Task<Void, Never>?
    private(set) var result: Result?

    init(tile: TileID, clock: any Clock<Duration>, timeout: Duration = .seconds(8), onResult: @escaping (Result) -> Void) {
        self.tile = tile
        self.clock = clock
        self.timeout = timeout
        self.onResult = onResult
    }

    /// Starts the no-answer timeout (Keep).
    func start() {
        let clock = clock, timeout = timeout
        timer = Task { @MainActor [weak self] in
            do { try await clock.sleep(for: timeout, tolerance: .milliseconds(100)) } catch { return }
            self?.answer(.timeout)
        }
    }

    func answer(_ r: Result) {
        guard result == nil else { return }
        result = r
        timer?.cancel()
        onResult(r)
    }
}

/// "Remove “<name>” from the Edge Dock?" beside the dock at the drop point. A floating,
/// non-activating panel that never becomes key on its own (a sheet would need key focus on the
/// dock panel, and a modal alert would stall the pointer monitors, REG-057). Keep is the
/// default; Esc, a click elsewhere, or the timeout keep the tile.
@MainActor final class RemoveConfirmPanel: NSObject {
    let panel: NSPanel
    private let confirmation: RemovalConfirmation
    private var monitors: [Any] = []

    static func title(for name: String) -> String { "Remove \u{201C}\(name)\u{201D} from the Edge Dock?" }

    init(name: String, confirmation: RemovalConfirmation) {
        self.confirmation = confirmation
        panel = NSPanel(contentRect: CGRect(x: 0, y: 0, width: 300, height: 92),
                        styleMask: [.titled, .nonactivatingPanel, .utilityWindow], backing: .buffered, defer: false)
        super.init()
        panel.title = Self.title(for: name)          // the AXTitle; the label shows it once
        panel.titleVisibility = .hidden
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let label = NSTextField(wrappingLabelWithString: Self.title(for: name))
        label.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
        label.preferredMaxLayoutWidth = 260
        let keep = NSButton(title: "Keep", target: self, action: #selector(RemoveConfirmPanel.keep))
        keep.keyEquivalent = "\r"
        let remove = NSButton(title: "Remove", target: self, action: #selector(RemoveConfirmPanel.remove))
        remove.hasDestructiveAction = true
        let buttons = NSStackView(views: [NSView(), remove, keep])
        let stack = NSStackView(views: [label, buttons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 14, left: 16, bottom: 14, right: 16)
        stack.translatesAutoresizingMaskIntoConstraints = false
        let content = NSView()
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            buttons.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -32),
            label.widthAnchor.constraint(equalToConstant: 268),
        ])
        panel.contentView = content
    }

    /// Where the panel sits: beside the capsule at the drop point, on the screen-centre side,
    /// kept on `visible` (AppKit global).
    static func origin(size: CGSize, capsule: CGRect, drop: CGPoint, edge: ScreenEdge, gap: CGFloat = 10,
                       visible: CGRect) -> CGPoint {
        var o: CGPoint = switch edge {
        case .left: CGPoint(x: capsule.maxX + gap, y: drop.y - size.height / 2)
        case .right: CGPoint(x: capsule.minX - gap - size.width, y: drop.y - size.height / 2)
        case .bottom: CGPoint(x: drop.x - size.width / 2, y: capsule.maxY + gap)
        case .top: CGPoint(x: drop.x - size.width / 2, y: capsule.minY - gap - size.height)
        }
        o.x = min(max(o.x, visible.minX + 8), visible.maxX - 8 - size.width)
        o.y = min(max(o.y, visible.minY + 8), visible.maxY - 8 - size.height)
        return o
    }

    /// Shows the panel without making it key, and starts the timeout. A click anywhere outside
    /// it keeps the tile. Esc and Return reach the panel only when it has focus through
    /// VoiceOver or Full Keyboard Access: it never takes key focus itself (typing stays with the
    /// user's app), so for everyone else the click elsewhere and the timeout are the Keep paths.
    /// A global Esc needs the Accessibility grant (T28).
    func show(capsule: CGRect, drop: CGPoint, edge: ScreenEdge, visible: CGRect) {
        panel.layoutIfNeeded()
        panel.setFrameOrigin(Self.origin(size: panel.frame.size, capsule: capsule, drop: drop, edge: edge, visible: visible))
        panel.orderFrontRegardless()
        // VoiceOver users hear the question without moving focus.
        NSAccessibility.post(element: panel, notification: .announcementRequested, userInfo: [
            .announcement: panel.title, .priority: NSAccessibilityPriorityLevel.high.rawValue,
        ])
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        if let m = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.keep() }
        }) { monitors.append(m) }
        if let m = NSEvent.addLocalMonitorForEvents(matching: mask.union(.keyDown), handler: { [weak self] event in
            let esc = event.type == .keyDown && event.keyCode == 53
            let click = event.type != .keyDown
            let window = event.windowNumber
            let consumed = MainActor.assumeIsolated { () -> Bool in
                guard let self else { return false }
                if esc { self.keep(); return true }      // Esc keeps (only when focused, see above)
                if click, window != self.panel.windowNumber { self.keep() }           // a click elsewhere keeps
                return false
            }
            return consumed ? nil : event
        }) { monitors.append(m) }
        confirmation.start()
    }

    @objc func keep() { confirmation.answer(.keep) }
    @objc func remove() { confirmation.answer(.remove) }

    /// Called once the confirmation has an answer.
    func close() {
        for m in monitors { NSEvent.removeMonitor(m) }
        monitors.removeAll()
        panel.close()
    }
}
