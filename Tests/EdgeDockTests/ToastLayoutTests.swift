import DedockCore
import Foundation
import Testing
@testable import EdgeDock

/// P2 Capsule toast geometry (T37c, design.md §7.2a).
@Suite struct ToastLayoutTests {
    let visible = CGRect(x: 0, y: 0, width: 1920, height: 1056)

    @Test func confirmSitsTenPointsOffTheInnerSideCentredOnTheSlotAndGrowsAway() {
        let w: CGFloat = 300
        let left = ToastLayout.confirm(width: w, capsule: CGRect(x: 8, y: 300, width: 78, height: 300),
                                       slot: CGPoint(x: 47, y: 450), edge: .left, visible: visible)
        #expect(left.frame == CGRect(x: 96, y: 424, width: 300, height: 52) && left.growth == .right)
        let right = ToastLayout.confirm(width: w, capsule: CGRect(x: 1834, y: 300, width: 78, height: 300),
                                        slot: CGPoint(x: 1873, y: 450), edge: .right, visible: visible)
        #expect(right.frame.maxX == 1824 && right.growth == .left)
        let bottom = ToastLayout.confirm(width: w, capsule: CGRect(x: 800, y: 8, width: 300, height: 78),
                                         slot: CGPoint(x: 950, y: 47), edge: .bottom, visible: visible)
        #expect(bottom.frame == CGRect(x: 800, y: 96, width: 300, height: 52) && bottom.growth == .up)
        let top = ToastLayout.confirm(width: w, capsule: CGRect(x: 800, y: 970, width: 300, height: 78),
                                      slot: CGPoint(x: 950, y: 1009), edge: .top, visible: visible)
        #expect(top.frame.maxY == 960 && top.frame.midX == 950 && top.growth == .down)
    }

    @Test func confirmIsClampedEightPointsInside() {
        // A slot at the very top of a left dock: the pill would cross the top of the visible frame.
        let p = ToastLayout.confirm(width: 300, capsule: CGRect(x: 8, y: 700, width: 78, height: 356),
                                    slot: CGPoint(x: 47, y: 1050), edge: .left, visible: visible)
        #expect(p.frame.maxY == visible.maxY - 8)
    }

    @Test func noticeDropsSixPointsUnderTheMenuBarCentredOnTheStatusItem() {
        let item = CGRect(x: 1500, y: 1056, width: 30, height: 24)
        let n = ToastLayout.notice(width: 400, statusItem: item, visible: visible)
        #expect(n.frame.maxY == 1050 && n.frame.midX == 1515 && n.growth == .down)
        // Hidden status item: top centre of the menu-bar display.
        #expect(ToastLayout.notice(width: 400, statusItem: nil, visible: visible).frame.midX == 960)
        // An item near the right edge: clamped 8 pt inside.
        let edge = ToastLayout.notice(width: 400, statusItem: CGRect(x: 1890, y: 1056, width: 24, height: 24), visible: visible)
        #expect(edge.frame.maxX == visible.maxX - 8)
    }

    @Test func widthFitsBetween240And520() {
        #expect(ToastLayout.width(fitting: 100) == 240)
        #expect(ToastLayout.width(fitting: 333) == 333)
        #expect(ToastLayout.width(fitting: 900) == 520)
    }

    @Test func longNamesAreShortenedInTheMiddle() {
        let measure: (String) -> CGFloat = { CGFloat($0.count * 7) }      // 7 pt per character
        let name = "An Application With A Very Long Name Indeed"
        let short = ToastLayout.middleTruncated(name, prefix: "Remove \u{201C}", suffix: "\u{201D}?", maxWidth: 200, measure: measure)
        #expect(short.contains("\u{2026}") && short.hasPrefix("An") && short.hasSuffix("ed"))
        #expect(measure("Remove \u{201C}" + short + "\u{201D}?") <= 200)
        #expect(ToastLayout.middleTruncated("Mail", prefix: "Remove \u{201C}", suffix: "\u{201D}?", maxWidth: 200, measure: measure) == "Mail")
    }
}
