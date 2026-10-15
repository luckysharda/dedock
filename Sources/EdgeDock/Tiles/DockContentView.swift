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
               tile.kind != .separator, let f = model.tileFrames[id] {
                let lane = labelLane(for: f)
                LabelView(text: tile.name, tokens: t)
                    .frame(width: lane.width, height: lane.height, alignment: labelAlignment)
                    .position(x: lane.midX, y: h - lane.midY)
            }
        }
        .frame(width: model.panelSize.width, height: h, alignment: .topLeading)
        .transaction { $0.animation = nil } // the label is instant (motion.tile.label)
    }

    /// The label lane toward the screen centre, `labelGap` from the capsule, beside the hovered
    /// tile (DD-903 item 3), panel-local. The label sits at the lane's capsule-side end.
    private func labelLane(for f: CGRect) -> CGRect {
        let t = model.tokens
        let c = model.capsule
        let laneLength = t.labelLane - t.labelGap
        let across = t.labelFontSize * 3
        switch model.edge {
        case .left: return CGRect(x: c.maxX + t.labelGap, y: f.midY - across / 2, width: laneLength, height: across)
        case .right: return CGRect(x: c.minX - t.labelGap - laneLength, y: f.midY - across / 2, width: laneLength, height: across)
        case .bottom: return CGRect(x: f.midX - laneLength / 2, y: c.maxY + t.labelGap, width: laneLength, height: across)
        case .top: return CGRect(x: f.midX - laneLength / 2, y: c.minY - t.labelGap - across, width: laneLength, height: across)
        }
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
            case .separator:
                // 1 px divider across the cross axis, 60 % of t.
                Rectangle()
                    .fill(Color(nsColor: t.dividerColor))
                    .frame(width: model.edge.isVertical ? t.tileThickness * t.dividerFraction : 1,
                           height: model.edge.isVertical ? 1 : t.tileThickness * t.dividerFraction)
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
        .dockTileAccessibility(tile, model: model)
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

/// Native-Dock-style tooltip: dark rounded fill, 12 pt Medium, 1 px inner edge.
struct LabelView: View {
    let text: String
    let tokens: DockTokens

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: tokens.labelRadius, style: .continuous)
        Text(text)
            .font(.system(size: tokens.labelFontSize, weight: .medium))
            .foregroundStyle(Color(nsColor: tokens.labelText))
            .lineLimit(1)
            .padding(.horizontal, tokens.labelPaddingH)
            .padding(.vertical, tokens.labelPaddingV)
            .background(shape.fill(Color(nsColor: tokens.labelFill)))
            .overlay(shape.strokeBorder(Color(nsColor: tokens.labelEdge), lineWidth: 1))
            .fixedSize()
    }
}
