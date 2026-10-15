import AppKit
import DedockCore
import DesignSystem
import SwiftUI

/// The dock's SwiftUI content. PLACEHOLDER skin: neutral capsule and tiles drawn only from
/// `DockTokens`. The design gate replaces this view's skin, not its geometry.
struct DockContentView: View {
    let model: DockViewModel

    var body: some View {
        let t = model.tokens
        let h = model.panelSize.height
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: t.capsuleRadius, style: .continuous)
                .fill(Color(nsColor: t.capsuleFill))
                .overlay(RoundedRectangle(cornerRadius: t.capsuleRadius, style: .continuous)
                    .strokeBorder(Color(nsColor: t.capsuleStroke), lineWidth: 1))
                .shadow(color: Color(nsColor: t.shadowColor).opacity(Double(t.shadowOpacity)), radius: t.shadowRadius)
                .frame(width: model.capsule.width, height: model.capsule.height)
                .position(x: model.capsule.midX, y: h - model.capsule.midY)

            ForEach(model.tiles) { tile in
                if let f = model.tileFrames[tile.id] {
                    TileView(tile: tile, model: model, size: f.size)
                        .position(x: f.midX, y: h - f.midY)
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
        .transaction { $0.animation = nil } // labels and hover are instant (motion.tile.label)
    }

    /// The label lane toward the screen centre, beside the hovered tile (DD-903 item 3),
    /// panel-local. The label sits at the lane's capsule-side end.
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
        let hovered = model.hoveredTile == tile.id
        ZStack {
            if tile.kind == .separator {
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color(nsColor: t.capsuleStroke))
                    .frame(width: model.edge.isVertical ? size.width * 0.6 : 2,
                           height: model.edge.isVertical ? 2 : size.height * 0.6)
            } else {
                RoundedRectangle(cornerRadius: t.tileRadius, style: .continuous)
                    .fill(Color(nsColor: hovered ? t.tileHoverFill : t.tileFill))
                if let icon = model.icon(for: tile) {
                    Image(nsImage: icon)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .padding(size.width * 0.08)
                        .opacity(tile.isMissing ? t.missingAppOpacity : (tile.running == .hidden ? t.hiddenAppOpacity : 1))
                }
                if tile.running != .none {
                    Circle()
                        .fill(Color(nsColor: tile.running == .frontmost ? t.indicatorFrontmost : t.indicatorRunning))
                        .frame(width: t.indicatorDiameter, height: t.indicatorDiameter)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: indicatorAlignment)
                        .padding(-t.indicatorInset - t.indicatorDiameter)
                }
            }
        }
        .frame(width: size.width, height: size.height)
        .accessibilityElement()
        .accessibilityLabel(tile.name)
    }

    /// Indicators sit on the inner side, toward the screen centre (DD-903 item 4).
    private var indicatorAlignment: Alignment {
        switch model.edge {
        case .left: .trailing
        case .right: .leading
        case .bottom: .top
        case .top: .bottom
        }
    }
}

struct LabelView: View {
    let text: String
    let tokens: DockTokens

    var body: some View {
        Text(text)
            .font(.system(size: tokens.labelFontSize, weight: .medium))
            .foregroundStyle(Color(nsColor: tokens.labelText))
            .padding(.horizontal, tokens.labelPadding)
            .padding(.vertical, tokens.labelPadding / 2)
            .background(RoundedRectangle(cornerRadius: tokens.labelRadius).fill(Color(nsColor: tokens.labelFill)))
            .lineLimit(1)
    }
}
