import AppKit
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

    /// One stop up or down (VoiceOver increment/decrement, arrow keys).
    static func stepped(_ size: AppearanceSettings.Size, up: Bool) -> AppearanceSettings.Size {
        let all = AppearanceSettings.Size.allCases
        let i = all.firstIndex(of: size) ?? 1
        return all[min(all.count - 1, max(0, i + (up ? 1 : -1)))]
    }

    /// A value change that arrives while no drag is in progress (no live value) is a discrete
    /// step, e.g. Full Keyboard Access arrows: it moves one stop in its direction and saves,
    /// never leaving a live preview behind.
    static func discrete(_ size: AppearanceSettings.Size, to value: Double) -> AppearanceSettings.Size {
        value == tile(size) ? size : stepped(size, up: value > tile(size))
    }

    /// The release snap's path: ease-out (close to the snappy spring) from where the drag
    /// stopped to the stop, about 0.25 s at 60 Hz. The last value is the stop exactly.
    static func snapCurve(from a: Double, to b: Double, steps: Int = 15) -> [Double] {
        guard steps > 0, a != b else { return [b] }
        return (1...steps).map { i in
            let t = Double(i) / Double(steps)
            return a + (b - a) * (1 - pow(1 - t, 3))
        }
    }

    /// Eases `live` to the stop (the dock follows each step, as while dragging), then saves the
    /// stop. Instant under Reduce Motion.
    private func release() {
        let target = Self.snapped(live: live, size: size)
        guard let from = live, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            size = target
            live = nil
            return
        }
        let setLive = $live, setSize = $size
        SnapRunner.shared.run(path: Self.snapCurve(from: from, to: Self.tile(target)),
                              step: { setLive.wrappedValue = $0 },
                              finish: { setSize.wrappedValue = target; setLive.wrappedValue = nil })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Slider(value: Binding(get: { live ?? Self.tile(size) }, set: { value in
                if live == nil { size = Self.discrete(size, to: value) } else { live = value }
            }), in: Self.range) { editing in
                if editing {
                    // A new grab during the release snap stops it and continues from where it is
                    // (e9's #42 review): the old snap must not write `live` under the new drag.
                    SnapRunner.shared.cancel()
                    live = live ?? Self.tile(size)   // a drag begins: preview from here
                } else {
                    release()
                }
            }
            .frame(width: 220)
            .accessibilityLabel("Dock size")
            .accessibilityValue(size.rawValue.uppercased())
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: size = Self.stepped(size, up: true)
                case .decrement: size = Self.stepped(size, up: false)
                @unknown default: break
                }
                live = nil
            }
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
        .onDisappear { SnapRunner.shared.finishNow() }   // never leave a live value behind
    }
}

/// Owns the one release snap in flight (the size slider exists once). Cancelling stops further
/// writes; `finishNow` completes it at once (the Settings window closed mid-snap).
@MainActor final class SnapRunner {
    static let shared = SnapRunner()
    private var task: Task<Void, Never>?
    private var pendingFinish: (() -> Void)?

    func run(path: [Double], frame: Duration = .milliseconds(16), step: @escaping (Double) -> Void,
             finish: @escaping () -> Void) {
        cancel()
        pendingFinish = finish
        task = Task { @MainActor [weak self] in
            for value in path {
                guard !Task.isCancelled else { return }
                step(value)
                try? await Task.sleep(for: frame)
            }
            guard !Task.isCancelled else { return }
            self?.finishNow()
        }
    }

    /// Stops the snap without finishing it (a new drag takes over).
    func cancel() {
        task?.cancel()
        task = nil
        pendingFinish = nil
    }

    /// Completes a pending snap immediately.
    func finishNow() {
        task?.cancel()
        task = nil
        let finish = pendingFinish
        pendingFinish = nil
        finish?()
    }

    var isRunning: Bool { task != nil }
}
