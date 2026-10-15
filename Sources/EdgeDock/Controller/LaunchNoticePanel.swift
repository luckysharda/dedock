import AppKit

/// The one-time launch notice (a damaged or unreadable layout), as a small floating panel. It is
/// never modal: `NSAlert.runModal` ran a modal session on the main thread, and the pointer
/// monitors and reveal timers stalled until OK was clicked, so the dock could not reveal while
/// the alert was up (REG-057). The panel neither activates Dedock nor becomes key on its own, so
/// the user's app keeps both focus and keystrokes (typing at login never lands here, and a stray
/// Return cannot dismiss it unread). OK works by click; Return works once the user clicks in.
@MainActor public final class LaunchNoticePanel: NSObject {
    public let panel: NSPanel
    private let onClose: (LaunchNoticePanel) -> Void

    public static func text(for notice: LaunchNotices.Notice) -> (title: String, body: String) {
        switch notice {
        case let .recovered(movedTo, fromBackup):
            ("Your Edge Dock layout was damaged",
             fromBackup
                 ? "Dedock restored the most recent backup. The damaged file was kept as \(movedTo)."
                 : "Dedock started with a fresh layout. The damaged file was kept as \(movedTo).")
        case .readOnly:
            ("Dedock can't read its layout file",
             "The Edge Dock is using the default layout. Changes you make won't be saved until the file can be read again.")
        }
    }

    /// - Parameter onClose: called with this notice after OK closes it (no capture needed).
    public init(_ notice: LaunchNotices.Notice, onClose: @escaping (LaunchNoticePanel) -> Void = { _ in }) {
        self.onClose = onClose
        panel = NSPanel(contentRect: CGRect(x: 0, y: 0, width: 380, height: 140),
                        styleMask: [.titled, .nonactivatingPanel, .utilityWindow], backing: .buffered, defer: false)
        super.init()
        let text = Self.text(for: notice)
        panel.title = text.title          // read as AXTitle; the bold label shows it once
        panel.titleVisibility = .hidden
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let title = NSTextField(labelWithString: text.title)
        title.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
        let body = NSTextField(wrappingLabelWithString: text.body)
        body.preferredMaxLayoutWidth = 340
        let ok = NSButton(title: "OK", target: self, action: #selector(LaunchNoticePanel.dismiss))
        ok.keyEquivalent = "\r"
        let buttons = NSStackView(views: [NSView(), ok])
        let stack = NSStackView(views: [title, body, buttons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 20, bottom: 16, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false
        let content = NSView()
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            buttons.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -40),
            body.widthAnchor.constraint(equalToConstant: 340),
        ])
        panel.contentView = content
    }

    /// Shows the notice and returns at once; no modal session is started.
    public func show() {
        panel.layoutIfNeeded()
        panel.center()
        panel.orderFrontRegardless()
    }

    @objc func dismiss() {
        panel.close()
        onClose(self)
    }
}
