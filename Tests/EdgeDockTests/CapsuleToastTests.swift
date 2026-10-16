import AppKit
import DedockCore
import DedockTestSupport
import DesignSystem
import Testing
@testable import EdgeDock

/// T37c: the P2 Capsule toast (design.md §7.2a) for the drag-out confirm and the launch notice.
@MainActor @Suite("Capsule toast", .serialized)
struct CapsuleToastTests {
    func rgba(_ c: NSColor?) -> [Int] {
        guard let s = c?.usingColorSpace(.sRGB) else { return [] }
        return [s.redComponent, s.greenComponent, s.blueComponent, s.alphaComponent].map { Int(($0 * 255).rounded()) }
    }

    func confirm(_ name: String, tokens: DockTokens = .capsule()) -> RemoveConfirmPanel {
        RemoveConfirmPanel(name: name, icon: NSImage(size: CGSize(width: 32, height: 32)), tokens: tokens,
                           confirmation: RemovalConfirmation(tile: "t", clock: ManualClock()) { _ in })
    }

    @Test func confirmReadsRemoveNameWithRemoveThenKeepAndKeepIsTheDefault() {
        let p = confirm("Calculator")
        #expect(p.toast.content.text == "Remove \u{201C}Calculator\u{201D}?")
        #expect(p.panel.title == "Remove \u{201C}Calculator\u{201D} from the Edge Dock?")          // AXTitle, announcement
        let b = p.toast.buttons
        #expect(b.map(\.title) == ["Remove", "Keep"])
        #expect(b[0].frame.maxX < b[1].frame.minX)                                               // Keep trails
        #expect(b[1].keyEquivalent == "\r" && b[0].keyEquivalent.isEmpty)
        #expect(b[0].role == .destructive && b[1].role == .plain)                                // no accent fill on Keep
        #expect(b.allSatisfy { $0.frame.height == 26 })
        #expect(p.toast.iconFrame?.size == CGSize(width: 32, height: 32))
    }

    @Test func removeIsRedTextNotARedFill() throws {
        let remove = try #require(confirm("Mail").toast.buttons.first)
        let title = remove.attributedTitle.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
        #expect(title == .systemRed)
        #expect(rgba(remove.layer?.backgroundColor.flatMap(NSColor.init(cgColor:))) == [255, 255, 255, 31])  // white @ 0.12
    }

    @Test func thePillIs52PointsAndFitsBetween240And520() {
        let short = confirm("Mail").toast, long = confirm(String(repeating: "Very Long Application Name ", count: 6)).toast
        #expect(short.width >= 240 && short.width <= 520)
        #expect(long.width > 480 && long.width <= 520)                                            // as wide as it may be
        #expect(long.content.text.contains("\u{2026}"))                                          // the name, middle-truncated
        #expect(long.content.text.hasPrefix("Remove \u{201C}Very") && long.content.text.hasSuffix("\u{201D}?"))
        #expect(short.panel.frame.height == CGFloat(52 + 2 * 24))                                         // the dock look's shadow room
    }

    @Test func confirmWearsTheDockStyleIncludingALightTint() {
        let light = confirm("Mail", tokens: .capsule(.m, style: .lightGlass)).toast
        #expect(light.pill is CapsuleView)
        #expect(rgba(light.buttons[1].attributedTitle.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor)
                == [0x11, 0x11, 0x11, 255])
        #expect(rgba(light.buttons[1].layer?.backgroundColor.flatMap(NSColor.init(cgColor:))) == [0, 0, 0, 20])  // black @ 0.08
        #expect(light.panel.appearance?.name == .aqua)
    }

    @Test func noticeIsOneLineWithAnAccentOKAndTheDetailInAccessibility() {
        let n = LaunchNoticePanel(.recovered(movedTo: "layout.corrupt-1.json", fromBackup: false))
        #expect(n.toast.content.text == "Your Edge Dock layout was damaged. Dedock started fresh.")
        #expect(n.toast.buttons.map(\.title) == ["OK"] && n.toast.buttons[0].role == .accent)
        #expect(n.panel.accessibilityHelp() == "The damaged file was kept as layout.corrupt-1.json.")
        #expect(n.toast.iconFrame == nil)
        #expect(n.toast.width <= 520)
        for notice in [LaunchNotices.Notice.recovered(movedTo: "x", fromBackup: true), .readOnly] {
            let t = LaunchNoticePanel(notice).toast
            #expect(CapsuleToast.measure(t.content.text) <= t.labelFrame.width + 2)                // one line, not cut
        }
    }

    @Test func theNoticeHasNoShadowAndNoMargin() {
        let n = LaunchNoticePanel(.readOnly).toast
        #expect(n.margin == 0 && n.panel.frame.height == 52)
        #expect((n.pill.layer?.shadowOpacity ?? 0) == 0)
        #expect(confirm("Mail").toast.margin == 24)                                              // the confirm keeps the dock's
    }

    /// A click in the confirm's transparent shadow margin is elsewhere (it keeps), not swallowed.
    @Test func aClickInTheShadowMarginIsElsewhere() {
        let t = confirm("Mail").toast
        let pill = t.pillRect
        func elsewhere(_ p: CGPoint, window: Int? = nil) -> Bool {
            CapsuleToast.clickIsElsewhere(eventWindow: window ?? t.panel.windowNumber, panelWindow: t.panel.windowNumber,
                                          location: p, pill: pill)
        }
        #expect(!elsewhere(CGPoint(x: pill.midX, y: pill.midY)))                                 // on the pill
        #expect(elsewhere(CGPoint(x: pill.minX - 10, y: pill.midY)))                             // in the margin
        #expect(elsewhere(CGPoint(x: pill.midX, y: pill.maxY + 5)))
        #expect(elsewhere(CGPoint(x: pill.midX, y: pill.midY), window: t.panel.windowNumber + 1)) // another window
        // The margin does not hit-test either: only the pill takes the mouse.
        let root = t.panel.contentView
        #expect(root?.hitTest(CGPoint(x: pill.minX - 10, y: pill.midY)) == nil)
        #expect(root?.hitTest(CGPoint(x: t.buttons[1].frame.midX, y: t.buttons[1].frame.midY)) === t.buttons[1])
    }

    @Test func noticeWearsTheWindowLook() {
        for (material, backdrop) in [(WindowLook.Material.frosted, WindowLook.Backdrop.frosted), (.solid, .solid)] {
            let look = WindowLook(appearance: .light, material: material, reduceTransparency: false)
            let t = LaunchNoticePanel(.readOnly, look: look).toast
            let pill = t.pill as? WindowPillView
            #expect(pill?.backdropKind == backdrop)
            #expect(t.panel.appearance?.name == .aqua)
        }
        let rt = WindowLook(appearance: .dark, material: .liquidGlass, reduceTransparency: true)
        #expect((LaunchNoticePanel(.readOnly, look: rt).toast.pill as? WindowPillView)?.backdropKind == .solid)
    }

    @Test(.enabled(if: NSScreen.main != nil)) func neverKeyNeverModalAndFadesOut() async throws {
        let n = LaunchNoticePanel(.readOnly)
        n.show(statusItem: nil, visible: CGRect(x: 0, y: 0, width: 1920, height: 1056), reduceMotion: false)
        #expect(n.panel.isVisible && !n.panel.isKeyWindow)
        #expect(NSApplication.shared.modalWindow == nil)
        #expect(n.panel.styleMask.contains(.nonactivatingPanel))
        #expect(n.panel.frame.maxY == 1050)                                                     // 6 pt under the menu bar, no margin
        n.dismiss()
        #expect(n.panel.title.isEmpty && n.panel.ignoresMouseEvents && !n.panel.isAccessibilityElement())  // no longer a question
        try await Task.sleep(for: .milliseconds(600))
        #expect(!n.panel.isVisible)
    }
}
