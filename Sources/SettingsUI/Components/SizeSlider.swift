import DesignSystem
import SettingsStore
import SwiftUI

/// Dock size, Z1 "Slider with stops" (design.md §7.2a): S, M, L, XL stops (tiles 48, 62, 76,
/// 92 pt). The slider moves freely while dragged and the dock follows every frame through
/// `live`; on release it snaps to the nearest stop, which is what is saved.
struct SizeSlider: View {
    @Binding var size: AppearanceSettings.Size
    @Binding var live: Double?

    static func tile(_ s: AppearanceSettings.Size) -> Double { Double(DockTokens.Size(rawValue: s.rawValue)?.tile ?? 62) }
    static func nearest(_ t: Double) -> AppearanceSettings.Size {
        AppearanceSettings.Size(rawValue: DockTokens.Size.nearest(toTile: CGFloat(t)).rawValue) ?? .m
    }
    static let range = Double(DockTokens.tileRange.lowerBound)...Double(DockTokens.tileRange.upperBound)

    /// The release: snap to the nearest stop and end the live preview.
    static func snapped(live: Double?, size: AppearanceSettings.Size) -> AppearanceSettings.Size {
        live.map(nearest) ?? size
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Slider(value: Binding(get: { live ?? Self.tile(size) }, set: { live = $0 }), in: Self.range) { editing in
                guard !editing else { return }
                size = Self.snapped(live: live, size: size)
                live = nil
            }
            .frame(width: 220)
            .accessibilityLabel("Dock size")
            .accessibilityValue(size.rawValue.uppercased())
            HStack {
                ForEach(AppearanceSettings.Size.allCases, id: \.self) { s in
                    Text(s.rawValue.uppercased())
                        .font(.caption2)
                        .foregroundStyle(s == size ? .primary : .secondary)
                    if s != AppearanceSettings.Size.allCases.last { Spacer() }
                }
            }
            .frame(width: 220)
            .accessibilityHidden(true)
        }
    }
}
