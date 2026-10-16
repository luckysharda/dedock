import AppKit
import DedockCore
import DesignSystem
import QuartzCore

/// A button inside a P2 Capsule toast (design.md §7.2a): a 26 pt capsule (radius 13), 12 pt
/// semibold, 12 pt side padding. Plain buttons sit on `white @ 0.12` (light styles
/// `black @ 0.08`); the destructive one has `systemRed` text, not a red fill; the accent one
/// (a notice's OK) is the only filled button.
@MainActor final class ToastButton: NSButton {
    enum Role { case plain, destructive, accent }

    static let height: CGFloat = 26
    static let padding: CGFloat = 12
    static let font = NSFont.systemFont(ofSize: 12, weight: .semibold)

    let role: Role
    private let handler: () -> Void

    init(title: String, role: Role, light: Bool, handler: @escaping () -> Void) {
        self.role = role
        self.handler = handler
        super.init(frame: .zero)
        self.title = title
        isBordered = false
        wantsLayer = true
        layer?.cornerRadius = Self.height / 2
        layer?.cornerCurve = .continuous
        let fill: NSColor = switch role {
        case .accent: .controlAccentColor
        case .plain, .destructive: light ? NSColor(white: 0, alpha: 0.08) : NSColor(white: 1, alpha: 0.12)
        }
        layer?.backgroundColor = fill.cgColor
        let text: NSColor = switch role {
        case .accent: .white
        case .destructive: .systemRed
        case .plain: light ? NSColor(srgbRed: 0x11 / 255, green: 0x11 / 255, blue: 0x11 / 255, alpha: 1) : .white
        }
        attributedTitle = NSAttributedString(string: title, attributes: [.font: Self.font, .foregroundColor: text])
        target = self
        action = #selector(ToastButton.fire)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    @objc private func fire() { handler() }

    override var intrinsicContentSize: NSSize {
        let w = (title as NSString).size(withAttributes: [.font: Self.font]).width
        return NSSize(width: ceil(w) + 2 * Self.padding, height: Self.height)
    }

    // The focus ring (Full Keyboard Access) follows the capsule.
    override func drawFocusRingMask() {
        NSBezierPath(roundedRect: bounds, xRadius: bounds.height / 2, yRadius: bounds.height / 2).fill()
    }

    override var focusRingMaskBounds: NSRect { bounds }
}

/// The toast's content: only the pill takes the mouse; the shadow margin around it is empty.
@MainActor final class PillHitView: NSView {
    var pill: CGRect = .zero
    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = superview.map { convert(point, from: $0) } ?? point
        return pill.contains(local) ? super.hitTest(point) : nil
    }
}

/// The toast's window: borderless and non-activating. It can become key only when VoiceOver
/// or Full Keyboard Access moves focus into it; it never takes focus on its own.
@MainActor final class ToastWindow: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    // ToastLayout places the pill exactly; only the transparent shadow margin may reach under
    // the menu bar, so AppKit must not push the window down.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

/// The pill of a P2 toast in the window look (the launch notice, design.md §7.2a): the Window
/// material (Frosted, Liquid Glass, Solid) clipped to the pill and a 1 px inner edge; no
/// shadow, like the window materials.
@MainActor final class WindowPillView: NSView {
    private let backdrop = WindowBackdropView(frame: .zero)
    private let edge = CALayer()

    init(frame: CGRect, look: WindowLook, dark: Bool, radius: CGFloat) {
        super.init(frame: frame)
        wantsLayer = true
        appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        backdrop.frame = bounds
        backdrop.wantsLayer = true
        backdrop.layer?.cornerRadius = radius
        backdrop.layer?.cornerCurve = .continuous
        backdrop.layer?.masksToBounds = true
        addSubview(backdrop)
        backdrop.apply(look.backdrop)
        edge.frame = bounds
        edge.cornerRadius = radius
        edge.cornerCurve = .continuous
        edge.borderWidth = 1
        edge.borderColor = (dark ? NSColor(white: 1, alpha: 0.08) : NSColor(white: 0, alpha: 0.06)).cgColor
        layer?.addSublayer(edge)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    var backdropKind: WindowLook.Backdrop { backdrop.backdrop }
}

/// P2 Capsule toast (design.md §7.2a): a 52 pt pill (radius 26) that unrolls from where it comes from (a clip reveal from its origin side, 0.22 s on the reveal
/// curve) and fades out over 0.30 s. One line of text, never key, never modal. Under Reduce
/// Motion it fades in place over 0.15 s. The drag-out confirm grows out of the dock and wears
/// the dock's style; the launch notice wears the window look.
@MainActor final class CapsuleToast {
    enum Look {
        /// The dock's style, LG4 tint and Reduce Transparency included.
        case dock(DockTokens)
        /// Window appearance × Window material; `dark` is the resolved appearance.
        case window(WindowLook, dark: Bool)
    }

    struct Button {
        var title: String
        var role: ToastButton.Role
        var isDefault = false
        var action: () -> Void
    }

    struct Content {
        var icon: NSImage?
        var text: String
        var truncation: NSLineBreakMode = .byTruncatingTail
        var buttons: [Button]
        /// The full question or message: the window's AXTitle and the announcement.
        var accessibilityTitle: String
        /// A longer explanation, read as the toast's accessibility help (not shown).
        var accessibilityHelp: String?
    }

    static let font = NSFont.systemFont(ofSize: 13, weight: .medium)
    static let iconSize: CGFloat = 32
    static let iconRadius: CGFloat = 9
    /// Room around the pill for its shadow: the dock look's 0 8 24; the window look has none.
    static func margin(for look: Look) -> CGFloat {
        switch look {
        case .dock: 24
        case .window: 0
        }
    }

    /// A mouse-down is "elsewhere" unless it lands on the pill itself: another window, or this
    /// window's transparent shadow margin (a click there must not be swallowed).
    static func clickIsElsewhere(eventWindow: Int, panelWindow: Int, location: CGPoint, pill: CGRect) -> Bool {
        eventWindow != panelWindow || !pill.contains(location)
    }
    static let revealDuration: CFTimeInterval = 0.22
    static let fadeOutDuration: TimeInterval = 0.30
    static let reducedFadeIn: TimeInterval = 0.15

    let panel: ToastWindow
    let content: Content
    /// The pill's width, fitted to the content (240–520 pt).
    let width: CGFloat
    let look: Look
    /// The shadow room around the pill, and the pill's rect in window coordinates.
    let margin: CGFloat
    let pillRect: CGRect
    private let clip = NSView()
    private let label: NSTextField
    private var iconView: NSImageView?
    private(set) var buttons: [ToastButton] = []
    private(set) var isClosing = false
    /// The pill's background view (a `CapsuleView` or a `WindowPillView`).
    private(set) var pill: NSView = NSView()

    /// Whether the look is light (dark ink).
    static func isLight(_ look: Look) -> Bool {
        switch look {
        case .dock(let t): isLight(t)
        case .window(_, let dark): !dark
        }
    }

    static func ink(_ look: Look) -> NSColor {
        switch look {
        case .dock(let t): t.textPrimary
        case .window(_, let dark): dark ? .white : NSColor(srgbRed: 0x11 / 255, green: 0x11 / 255, blue: 0x11 / 255, alpha: 1)
        }
    }

    /// Whether the style's ink is dark (a light style: Light Glass, Liquid Glass's light tint).
    static func isLight(_ t: DockTokens) -> Bool {
        (t.textPrimary.usingColorSpace(.sRGB)?.brightnessComponent ?? 1) < 0.5
    }

    static func measure(_ s: String) -> CGFloat {
        ceil((s as NSString).size(withAttributes: [.font: font]).width)
    }

    init(_ content: Content, look: Look) {
        self.content = content
        self.look = look
        let light = Self.isLight(look)
        label = NSTextField(labelWithString: content.text)
        label.font = Self.font
        label.textColor = Self.ink(look)
        label.lineBreakMode = content.truncation
        label.maximumNumberOfLines = 1
        label.cell?.truncatesLastVisibleLine = true
        buttons = content.buttons.map { b in
            let button = ToastButton(title: b.title, role: b.role, light: light, handler: b.action)
            if b.isDefault { button.keyEquivalent = "\r" }
            return button
        }

        // Fit: leading padding, icon, text, buttons, trailing padding, 12 pt between items.
        let L = ToastLayout.self
        let fixed = (content.icon != nil ? L.leadingWithIcon + Self.iconSize + L.spacing : L.leading)
            + buttons.reduce(0) { $0 + $1.intrinsicContentSize.width + L.spacing } + L.trailing
        let textWidth = min(Self.measure(content.text) + 2, L.maxWidth - fixed)
        width = L.width(fitting: fixed + textWidth)

        let m = Self.margin(for: look)
        margin = m
        pillRect = CGRect(x: m, y: m, width: width, height: L.height)
        let size = CGSize(width: width + 2 * m, height: L.height + 2 * m)
        panel = ToastWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false                  // the pill draws its own shadow
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.appearance = NSAppearance(named: light ? .aqua : .darkAqua)
        panel.title = content.accessibilityTitle
        panel.setAccessibilityLabel(content.accessibilityTitle)
        if let help = content.accessibilityHelp { panel.setAccessibilityHelp(help) }

        let root = PillHitView(frame: CGRect(origin: .zero, size: size))
        root.pill = pillRect
        clip.frame = root.bounds
        clip.wantsLayer = true
        root.addSubview(clip)
        let pillFrame = CGRect(x: m, y: m, width: width, height: L.height)
        switch look {
        case .dock(let tokens):
            let capsule = CapsuleView(frame: .zero)
            capsule.apply(frame: pillFrame, tokens: tokens, radius: L.radius)
            pill = capsule
        case let .window(windowLook, dark):
            pill = WindowPillView(frame: pillFrame, look: windowLook, dark: dark, radius: L.radius)
        }
        clip.addSubview(pill)

        var x = pillFrame.minX + (content.icon != nil ? L.leadingWithIcon : L.leading)
        if let icon = content.icon {
            let v = NSImageView(frame: CGRect(x: x, y: pillFrame.midY - Self.iconSize / 2, width: Self.iconSize, height: Self.iconSize))
            v.image = icon
            v.imageScaling = .scaleProportionallyUpOrDown
            v.wantsLayer = true
            v.layer?.cornerRadius = Self.iconRadius
            v.layer?.masksToBounds = true
            v.setAccessibilityElement(false)           // decorative: the text names the app
            clip.addSubview(v)
            iconView = v
            x += Self.iconSize + L.spacing
        }
        let buttonsWidth = buttons.reduce(0) { $0 + $1.intrinsicContentSize.width } + CGFloat(max(0, buttons.count - 1)) * L.spacing
        let textRoom = pillFrame.maxX - L.trailing - buttonsWidth - (buttons.isEmpty ? 0 : L.spacing) - x
        let textHeight = ceil(label.intrinsicContentSize.height)
        label.frame = CGRect(x: x, y: pillFrame.midY - textHeight / 2, width: max(0, textRoom), height: textHeight)
        clip.addSubview(label)
        var bx = pillFrame.maxX - L.trailing - buttonsWidth
        for b in buttons {
            let w = b.intrinsicContentSize.width
            b.frame = CGRect(x: bx, y: pillFrame.midY - ToastButton.height / 2, width: w, height: ToastButton.height)
            clip.addSubview(b)
            bx += w + L.spacing
        }
        panel.contentView = root
    }

    /// The label's frame inside the window (tests).
    var labelFrame: CGRect { label.frame }
    var iconFrame: CGRect? { iconView?.frame }

    /// Shows the pill at `frame` (AppKit global), unrolling from its `growth` origin side;
    /// never key.
    func show(at frame: CGRect, growth: ToastLayout.Growth, reduceMotion: Bool) {
        panel.setFrame(frame.insetBy(dx: -margin, dy: -margin), display: false)
        if reduceMotion {
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = Self.reducedFadeIn
                panel.animator().alphaValue = 1
            }
        } else {
            panel.alphaValue = 1
            unroll(growth)
            panel.orderFrontRegardless()
        }
        NSAccessibility.post(element: panel, notification: .announcementRequested, userInfo: [
            .announcement: content.accessibilityTitle, .priority: NSAccessibilityPriorityLevel.high.rawValue,
        ])
    }

    /// The clip reveal: a mask anchored on the origin side grows to the full window.
    private func unroll(_ growth: ToastLayout.Growth) {
        guard let layer = clip.layer else { return }
        let full = layer.bounds
        let mask = CALayer()
        mask.backgroundColor = NSColor.black.cgColor
        let (anchor, key): (CGPoint, String) = switch growth {
        case .right: (CGPoint(x: 0, y: 0), "bounds.size.width")
        case .left: (CGPoint(x: 1, y: 0), "bounds.size.width")
        case .up: (CGPoint(x: 0, y: 0), "bounds.size.height")
        case .down: (CGPoint(x: 0, y: 1), "bounds.size.height")
        }
        mask.anchorPoint = anchor
        mask.bounds = CGRect(origin: .zero, size: full.size)
        mask.position = CGPoint(x: full.minX + anchor.x * full.width, y: full.minY + anchor.y * full.height)
        layer.mask = mask
        let a = CABasicAnimation(keyPath: key)
        a.fromValue = 0
        a.toValue = key.hasSuffix("width") ? full.width : full.height
        a.duration = Self.revealDuration
        a.timingFunction = EdgeMotion.revealBezier
        a.isRemovedOnCompletion = true
        mask.add(a, forKey: "p2.unroll")
    }

    /// Fades out over 0.30 s, then orders out.
    func dismiss() {
        guard !isClosing else { return }
        isClosing = true
        // It stops being a question at once, though it still fades: no clicks, no title, out of
        // the accessibility tree, so a new question never meets a second one (§2.3a).
        panel.ignoresMouseEvents = true
        panel.title = ""
        panel.setAccessibilityLabel(nil)
        panel.setAccessibilityElement(false)
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = Self.fadeOutDuration
            panel.animator().alphaValue = 0
        }, completionHandler: { [panel] in
            MainActor.assumeIsolated {
                panel.orderOut(nil)
                panel.close()
            }
        })
    }
}
