import AppKit
import SwiftUI

/// Settings window tokens, A2 Frosted / DockDoor settings grammar (docs/design.md §7.2).
public enum SettingsTokens {
    public static let sidebarWidth: CGFloat = 270
    public static let windowSize = CGSize(width: 900, height: 640)
    public static let contentPadding: CGFloat = 24
    public static let sectionSpacing: CGFloat = 22
    public static let cardRadius: CGFloat = 10
    public static let cardPadding: CGFloat = 14
    public static let rowSpacing: CGFloat = 12
    public static let sectionHeaderSize: CGFloat = 11
    public static let groupLabelSize: CGFloat = 11
    public static let scenarioCardRadius: CGFloat = 12
    public static let scenarioCardHeight: CGFloat = 92

    /// The sidebar's fill for a window backdrop: opaque on Solid; on Frosted and Liquid Glass a
    /// faint overlay over the window's material, so the sidebar reads as its own column.
    public static func sidebarFill(_ backdrop: WindowLook.Backdrop) -> Color {
        switch backdrop {
        case .solid:
            Color(nsColor: NSColor(name: nil) { a in
                a.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                    ? NSColor(srgbRed: 0x1E / 255, green: 0x1D / 255, blue: 0x1B / 255, alpha: 1)
                    : NSColor(srgbRed: 0xEC / 255, green: 0xEC / 255, blue: 0xEE / 255, alpha: 1)
            })
        case .frosted, .glass:
            Color(nsColor: NSColor(name: nil) { a in
                a.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(white: 0, alpha: 0.18) : NSColor(white: 1, alpha: 0.30)
            })
        }
    }

    /// The content column's fill: opaque on Solid, clear over Frosted and Liquid Glass.
    public static func contentFill(_ backdrop: WindowLook.Backdrop) -> Color {
        backdrop == .solid ? contentBackground : .clear
    }

    /// Content background: dark `#252421`, light the window background.
    public static var contentBackground: Color {
        Color(nsColor: NSColor(name: nil) { a in
            a.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(srgbRed: 0x25 / 255, green: 0x24 / 255, blue: 0x21 / 255, alpha: 1) : .windowBackgroundColor
        })
    }

    /// Grouped card: dark `#1C1C1C`; light white with a hairline.
    public static var cardFill: Color {
        Color(nsColor: NSColor(name: nil) { a in
            a.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(srgbRed: 0x1C / 255, green: 0x1C / 255, blue: 0x1C / 255, alpha: 1) : .white
        })
    }

    public static var cardStroke: Color {
        Color(nsColor: NSColor(name: nil) { a in
            a.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(white: 1, alpha: 0.06) : NSColor(white: 0, alpha: 0.08)
        })
    }
}
