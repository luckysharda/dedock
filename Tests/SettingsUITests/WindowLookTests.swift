import AppKit
import DesignSystem
import SettingsStore
import Testing
@testable import SettingsUI

/// T37b: the windows' look after the fallbacks (design.md §7.2).
@Suite @MainActor struct WindowLookTests {
    @Test func materialResolvesWithItsFallbacks() {
        func backdrop(_ m: WindowLook.Material, rt: Bool = false, glass: Bool = true) -> WindowLook.Backdrop {
            WindowLook(appearance: .system, material: m, reduceTransparency: rt, systemGlass: glass).backdrop
        }
        #expect(backdrop(.frosted) == .frosted)
        #expect(backdrop(.liquidGlass) == .glass)
        #expect(backdrop(.liquidGlass, glass: false) == .frosted)      // before macOS 26
        #expect(backdrop(.solid) == .solid)
        for m in WindowLook.Material.allCases { #expect(backdrop(m, rt: true) == .solid) }   // Reduce Transparency
    }

    @Test func appearanceMapsToTheWindowAppearance() {
        #expect(WindowLook(appearance: .system, material: .frosted, reduceTransparency: false).nsAppearance == nil)
        #expect(WindowLook(appearance: .light, material: .frosted, reduceTransparency: false).nsAppearance?.name == .aqua)
        #expect(WindowLook(appearance: .dark, material: .frosted, reduceTransparency: false).nsAppearance?.name == .darkAqua)
    }

    /// The settings enums and the DesignSystem ones stay in step (the controller maps by raw value).
    @Test func settingsValuesMapOneToOne() {
        #expect(AppPreferences.WindowAppearance.allCases.map(\.rawValue) == WindowLook.Appearance.allCases.map(\.rawValue))
        #expect(AppPreferences.WindowMaterial.allCases.map(\.rawValue) == WindowLook.Material.allCases.map(\.rawValue))
    }

    @Test func backdropShowsOneLayerPerMaterial() {
        let v = WindowBackdropView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        v.apply(.solid)
        #expect(v.backdrop == .solid && v.layer?.backgroundColor != NSColor.clear.cgColor)
        v.apply(.frosted)
        #expect(v.layer?.backgroundColor == NSColor.clear.cgColor)
        #expect(v.subviews.contains { $0 is NSVisualEffectView && !$0.isHidden })
        v.apply(.solid)
        #expect(!v.subviews.contains { $0 is NSVisualEffectView && !$0.isHidden })
    }
}
