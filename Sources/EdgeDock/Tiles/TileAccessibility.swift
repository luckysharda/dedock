import DedockCore
import SwiftUI

/// What assistive technology sees for a dock tile (NFR-10, design.md §5.1, §6). Tiles were
/// exposed as `AXUnknown` with no action (REG-040); now each is an actionable button whose press
/// takes the same path as a click.
struct TileAccessibilitySpec: Equatable {
    var hidden: Bool
    var isButton: Bool
    var label: String
    var value: String
    var hint: String

    init(_ tile: TileModel) {
        hidden = tile.kind == .separator
        isButton = !hidden
        label = tile.name
        hint = switch tile.kind {
        case .folder: "Opens the folder"
        case .app: "Opens the app"
        case .separator: ""
        }
        value = if tile.isMissing {
            "missing"
        } else {
            switch tile.kind {
            case .folder: "folder"
            case .separator: ""
            case .app:
                switch tile.running {
                case .none: "not running"
                case .running: "running"
                case .frontmost: "running, frontmost"
                case .hidden: "running, hidden"
                }
            }
        }
    }
}

struct DockTileAccessibility: ViewModifier {
    let tile: TileModel
    let activate: (TileID) -> Void

    var spec: TileAccessibilitySpec { TileAccessibilitySpec(tile) }

    /// The AXPress action: the click path.
    func press() { activate(tile.id) }

    func body(content: Content) -> some View {
        let spec = spec
        if spec.hidden {
            content.accessibilityHidden(true)
        } else {
            content
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(spec.label)
                .accessibilityAddTraits(spec.isButton ? .isButton : [])
                .accessibilityValue(spec.value)
                .accessibilityHint(spec.hint)
                .accessibilityAction { press() }
        }
    }
}

extension View {
    func dockTileAccessibility(_ tile: TileModel, model: DockViewModel) -> some View {
        modifier(DockTileAccessibility(tile: tile) { [weak model] id in model?.activate?(id) })
    }
}
