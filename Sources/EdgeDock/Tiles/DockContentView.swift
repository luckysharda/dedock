import AppKit
import DedockCore
import DesignSystem
import SwiftUI

/// The dock's SwiftUI content: E1 Capsule in Dark Glass (docs/design.md §7.1). Geometry comes
/// from `LayoutEngine`; every visual value comes from `DockTokens`.
struct DockContentView: View {
    let model: DockViewModel

    var body: some View {
        let t = model.tokens
        let h = model.panelSize.height
        ZStack(alignment: .topLeading) {
            // The capsule itself is `CapsuleView` (AppKit), drawn under this view.
            ForEach(model.tiles) { tile in
                if let f = model.tileFrames[tile.id] {
                    let centre = tile.id == model.draggedTile ? model.dragCentre : CGPoint(x: f.midX, y: f.midY)
                    TileView(tile: tile, model: model, size: f.size)
                        .position(x: centre.x, y: h - centre.y)
                        .zIndex(tile.id == model.draggedTile ? 1 : 0)
                }
            }

            if let id = model.hoveredTile, let tile = model.tiles.first(where: { $0.id == id }),
               !tile.isFiller, let f = model.tileFrames[id] {
                let lane = labelLane(for: f)
                LabelView(content: TileLabelContent(tile), tokens: t)
                    .frame(width: lane.width, height: lane.height, alignment: labelAlignment)
                    .position(x: lane.midX, y: h - lane.midY)
            }
        }
        .frame(width: model.panelSize.width, height: h, alignment: .topLeading)
        .transaction { $0.animation = nil } // the label is instant (motion.tile.label)
    }

    private func labelLane(for f: CGRect) -> CGRect {
        DockViewModel.labelLane(for: f, capsule: model.capsule, edge: model.edge, tokens: model.tokens)
    }

    private var labelAlignment: Alignment {
        switch model.edge {
        case .left: .leading
        case .right: .trailing
        case .bottom: .bottom
        case .top: .top
        }
    }
}

struct TileView: View {
    let tile: TileModel
    let model: DockViewModel
    let size: CGSize

    var body: some View {
        let t = model.tokens
        ZStack {
            switch tile.kind {
            case .separator, .spacer:
                // SP3 Islands: a separator is the clear gap between two capsules and a spacer is
                // empty glass; neither draws anything of its own.
                EmptyView()
            case .app, .folder:
                // Bare icon, no plate and no hover highlight (E1).
                if let icon = model.icon(for: tile) {
                    Image(nsImage: icon)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: t.appIcon, height: t.appIcon)
                        .opacity(tile.isMissing ? t.missingAppOpacity : 1)
                }
            }
        }
        .frame(width: size.width, height: size.height)
        .overlay(alignment: indicatorAlignment) { indicator }
        .modifier(accessibility)
    }

    /// The tile's accessibility element: the whole cell `size` (REG-061).
    var accessibility: DockTileAccessibility {
        DockTileAccessibility(tile: tile, cell: size) { [weak model] id in model?.activate?(id) }
    }

    /// Running dot on the inner side, `indicatorOffset` outside the tile edge (DD-903 item 4).
    @ViewBuilder private var indicator: some View {
        let t = model.tokens
        if tile.kind == .app, tile.running != .none {
            let shift = t.indicatorOffset + t.indicatorDiameter / 2
            Circle()
                .fill(Color(nsColor: tile.running == .hidden ? t.indicatorHidden : t.indicatorRunning))
                .frame(width: t.indicatorDiameter, height: t.indicatorDiameter)
                .offset(x: offset.dx * shift, y: offset.dy * shift)
        }
    }

    /// Unit direction toward the screen centre, in SwiftUI's y-down space.
    private var offset: CGVector {
        switch model.edge {
        case .left: CGVector(dx: 1, dy: 0)
        case .right: CGVector(dx: -1, dy: 0)
        case .bottom: CGVector(dx: 0, dy: -1)
        case .top: CGVector(dx: 0, dy: 1)
        }
    }

    private var indicatorAlignment: Alignment {
        switch model.edge {
        case .left: .trailing
        case .right: .leading
        case .bottom: .top
        case .top: .bottom
        }
    }
}

/// H4 "Name and state" (design.md §7.2a): the name in 13 pt semibold, the state in 11 pt with a
/// green dot while running; dark rounded fill, 1 px inner edge.
struct LabelView: View {
    let content: TileLabelContent
    let tokens: DockTokens

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: tokens.labelRadius, style: .continuous)
        VStack(alignment: .leading, spacing: 2) {
            Text(content.name)
                .font(.system(size: tokens.labelFontSize, weight: .semibold))
                .foregroundStyle(Color(nsColor: tokens.labelText))
            if let state = content.state {
                HStack(spacing: 4) {
                    if content.running {
                        Circle().fill(Color(nsColor: tokens.labelRunningDot)).frame(width: 6, height: 6)
                    }
                    Text(state)
                        .font(.system(size: tokens.labelStateFontSize))
                        .foregroundStyle(Color(nsColor: tokens.labelStateText))
                }
            }
        }
        .lineLimit(1)
        .padding(.horizontal, tokens.labelPaddingH)
        .padding(.vertical, tokens.labelPaddingV)
        .background(shape.fill(Color(nsColor: tokens.labelFill)))
        .overlay(shape.strokeBorder(Color(nsColor: tokens.labelEdge), lineWidth: 1))
        .fixedSize()
        .accessibilityHidden(true)    // the tile's AX element already carries name and state
    }
}
