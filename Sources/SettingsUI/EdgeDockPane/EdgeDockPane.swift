import AppKit
import DedockCore
import DesignSystem
import SettingsStore
import SwiftUI
import UniformTypeIdentifiers

/// Settings ▸ Edge Dock (plan T17, T19; design §5.3). Writes only to `SettingsModel`; the
/// running dock observes the model and reconfigures live.
struct EdgeDockPane: View {
    let settings: SettingsModel
    let environment: SettingsEnvironment

    private var dock: DockConfig? { settings.document.docks.first }

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsTokens.sectionSpacing) {
            Text("Edge Dock").font(.title2.weight(.semibold))
            if let dock {
                ScenarioCards(dock: dock, recommended: Scenario.recommended(nativeDockEdge: environment.nativeDockEdge())) { card in
                    updateDock { card.apply(to: $0, nativeDockEdge: environment.nativeDockEdge()) }
                }
                edgeSection(dock)
                timingSection
                triggerSection(dock)
                placementSection
                TileListSection(settings: settings, profileID: dock.profileID)
            } else {
                Text("No dock is configured.").foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Sections

    private func edgeSection(_ dock: DockConfig) -> some View {
        SettingsSection(title: "Edge") {
            HStack(alignment: .center, spacing: 24) {
                EdgePicker(edge: dockBinding(\.edge, custom: true), nativeDockEdge: environment.nativeDockEdge())
                VStack(alignment: .leading, spacing: 10) {
                    SettingsRow(label: "Mode") {
                        Picker("Mode", selection: dockBinding(\.mode, custom: true)) {
                            Text("Reveal").tag(DockConfig.Mode.reveal)
                            Text("Pinned").tag(DockConfig.Mode.pinned)
                        }
                        .labelsHidden().pickerStyle(.segmented).frame(width: 180)
                    }
                    if dock.edge == .bottom || dock.edge == .top {
                        Text("\(dock.edge == .top ? "Top" : "Bottom") edge is in beta.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if dock.edge == environment.nativeDockEdge() {
                        Text("The native Dock is on this edge; the trigger avoids its span.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var timingSection: some View {
        SettingsSection(title: "Timing") {
            ValueSlider(label: "Show delay", value: msBinding(\.reveal.showDwellMs), range: 0...5000, step: 10, unit: "ms",
                        help: "How long to rest at the edge before the dock appears.")
            ValueSlider(label: "Hide delay", value: msBinding(\.reveal.hideDelayMs), range: 0...5000, step: 10, unit: "ms",
                        help: "Grace period before the dock hides when you move away.")
            ValueSlider(label: "Full-screen show delay", value: msBinding(\.reveal.fullscreenDwellMs), range: 0...5000, step: 10,
                        unit: "ms", help: "Used while a full-screen app is in front.")
            SettingsRow(label: "Hide in full screen") {
                Toggle("Hide in full screen", isOn: dockBinding(\.reveal.hideInFullscreen, custom: true)).labelsHidden()
            }
        }
    }

    private func triggerSection(_ dock: DockConfig) -> some View {
        SettingsSection(title: "Trigger") {
            ValueSlider(label: "Trigger thickness", value: dockBinding(\.reveal.triggerThicknessPt, custom: true),
                        range: 1...20, unit: "pt", help: "The invisible strip at the edge that reveals the dock.")
            SettingsRow(label: "Trigger span") {
                Picker("Trigger span", selection: dockBinding(\.reveal.spanMode, custom: true)) {
                    Text("Dock length").tag(RevealSettings.SpanMode.content)
                    Text("Whole edge").tag(RevealSettings.SpanMode.wholeEdge)
                }
                .labelsHidden().pickerStyle(.segmented).frame(width: 220)
            }
            ValueSlider(label: "Corner exclusion", value: dockBinding(\.reveal.cornerExclusionPt, custom: true),
                        range: 0...96, unit: "pt", help: "Keeps Hot Corners and the corners free.")
            SettingsRow(label: "Push through to reveal", help: "Pushing into the edge reveals before the delay ends.") {
                Toggle("Push through to reveal", isOn: pushThroughBinding).labelsHidden()
            }
            if environment.hasSharedEdge(dock.edge) {
                SettingsRow(label: "Shared display edge", help: "This edge borders another display.") {
                    Picker("Shared display edge", selection: dockBinding(\.reveal.sharedEdgePolicy, custom: true)) {
                        Text("Slow dwell").tag(RevealSettings.SharedEdgePolicy.slowDwell)
                        Text("With ⌥").tag(RevealSettings.SharedEdgePolicy.modifier)
                        Text("Off").tag(RevealSettings.SharedEdgePolicy.wallOnly)
                    }
                    .labelsHidden().pickerStyle(.segmented).frame(width: 240)
                }
            }
        }
    }

    private var placementSection: some View {
        SettingsSection(title: "Placement and size") {
            SettingsRow(label: "Alignment") {
                Picker("Alignment", selection: dockBinding(\.placement.alignment, custom: false)) {
                    Text("Start").tag(PlacementSettings.Alignment.start)
                    Text("Center").tag(PlacementSettings.Alignment.center)
                    Text("End").tag(PlacementSettings.Alignment.end)
                }
                .labelsHidden().pickerStyle(.segmented).frame(width: 220)
            }
            ValueSlider(label: "Distance from edge", value: dockBinding(\.placement.edgeGapPt, custom: false),
                        range: 0...48, unit: "pt")
            SettingsRow(label: "Dock size") {
                Picker("Dock size", selection: dockBinding(\.appearance.size, custom: false)) {
                    Text("S").tag(AppearanceSettings.Size.s)
                    Text("M").tag(AppearanceSettings.Size.m)
                    Text("L").tag(AppearanceSettings.Size.l)
                    Text("XL").tag(AppearanceSettings.Size.xl)
                }
                .labelsHidden().pickerStyle(.segmented).frame(width: 200)
            }
            SettingsRow(label: "Style") {
                Picker("Style", selection: dockBinding(\.appearance.style, custom: false)) {
                    Text("Dark Glass").tag(AppearanceSettings.Style.darkGlass)
                    Text("Black").tag(AppearanceSettings.Style.black)
                    Text("Light Glass").tag(AppearanceSettings.Style.lightGlass)
                }
                .labelsHidden().pickerStyle(.segmented).frame(width: 260)
            }
            SettingsRow(label: "Drag to rearrange", help: "⌘-drag always rearranges.") {
                Toggle("Drag to rearrange", isOn: dockBinding(\.appearance.dragToRearrange, custom: false)).labelsHidden()
            }
        }
    }

    // MARK: Bindings

    private func updateDock(_ change: (DockConfig) -> DockConfig) {
        settings.update { doc in
            guard !doc.docks.isEmpty else { return }
            doc.docks[0] = change(doc.docks[0])
        }
    }

    /// A binding into the first dock. `custom` marks the scenario card Custom (DD-910 item 4):
    /// scenario cards cover edge, mode, timing and trigger, not placement or size.
    private func dockBinding<T: Equatable>(_ path: WritableKeyPath<DockConfig, T>, custom: Bool) -> Binding<T> {
        Binding(
            // Safe on a document with no docks: the defaults stand in until one exists.
            get: { (settings.document.docks.first ?? DockConfig(id: "dock-0"))[keyPath: path] },
            set: { value in
                updateDock { d in
                    guard d[keyPath: path] != value else { return d }
                    var next = d
                    next[keyPath: path] = value
                    if custom { next.markCustom() }
                    return next
                }
            })
    }

    private func msBinding(_ path: WritableKeyPath<DockConfig, Int>) -> Binding<Double> {
        let int = dockBinding(path, custom: true)
        return Binding(get: { Double(int.wrappedValue) }, set: { int.wrappedValue = Int($0.rounded()) })
    }

    private var pushThroughBinding: Binding<Bool> {
        let value = dockBinding(\.reveal.pushThroughPt, custom: true)
        return Binding(get: { value.wrappedValue != nil }, set: { value.wrappedValue = $0 ? 40 : nil })
    }
}

// MARK: - Scenario cards

struct ScenarioCards: View {
    let dock: DockConfig
    let recommended: Scenario
    let apply: (Scenario) -> Void

    private let columns = [GridItem(.adaptive(minimum: 170), spacing: 12)]

    var body: some View {
        SettingsSection(title: "Scenario") {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                ForEach(Scenario.allCases) { card in
                    ScenarioCard(card: card, selected: Scenario.current(dock) == card, recommended: card == recommended) {
                        apply(card)
                    }
                }
            }
            if Scenario.current(dock) == nil {
                Label("Custom: you changed settings after choosing a card.", systemImage: "slider.horizontal.3")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

struct ScenarioCard: View {
    let card: Scenario
    let selected: Bool
    let recommended: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                // Tags sit on their own row so a narrow card never wraps them mid-word.
                if card.isBeta || recommended {
                    HStack(spacing: 4) {
                        if recommended { Tag(text: "Recommended", tint: .accentColor) }
                        if card.isBeta { Tag(text: "Beta", tint: .orange) }
                    }
                }
                Text(card.title).font(.system(size: 13, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.85)
                Text(card.subtitle).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: SettingsTokens.scenarioCardHeight, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: SettingsTokens.scenarioCardRadius)
                .fill(selected ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.04)))
            .overlay(RoundedRectangle(cornerRadius: SettingsTokens.scenarioCardRadius)
                .strokeBorder(selected ? Color.accentColor : Color.primary.opacity(0.1), lineWidth: selected ? 2 : 1))
            .contentShape(RoundedRectangle(cornerRadius: SettingsTokens.scenarioCardRadius))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(card.title)\(recommended ? ", recommended" : "")\(selected ? ", selected" : "")")
    }
}

struct Tag: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold))
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Capsule().fill(tint.opacity(0.18)))
            .foregroundStyle(tint)
    }
}

// MARK: - Edge picker

/// A screen diagram with clickable left / right / bottom / top bars (design §5.3).
struct EdgePicker: View {
    @Binding var edge: ScreenEdge
    let nativeDockEdge: ScreenEdge

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.06))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.15)))
            // Menu bar and native Dock hints.
            VStack(spacing: 0) {
                Rectangle().fill(Color.primary.opacity(0.12)).frame(height: 8)
                Spacer()
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            nativeDockHint
            bar(.left).frame(width: 10, height: 64).frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 4)
            bar(.right).frame(width: 10, height: 64).frame(maxWidth: .infinity, alignment: .trailing).padding(.trailing, 4)
            bar(.bottom).frame(width: 80, height: 10).frame(maxHeight: .infinity, alignment: .bottom).padding(.bottom, 4)
            bar(.top).frame(width: 80, height: 10).frame(maxHeight: .infinity, alignment: .top).padding(.top, 12)
        }
        .frame(width: 200, height: 128)
    }

    private func bar(_ e: ScreenEdge) -> some View {
        Button { edge = e } label: {
            RoundedRectangle(cornerRadius: 4)
                .fill(edge == e ? Color.accentColor : Color.primary.opacity(0.2))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(e.rawValue.capitalized) edge\(edge == e ? ", selected" : "")")
    }

    @ViewBuilder private var nativeDockHint: some View {
        let hint = RoundedRectangle(cornerRadius: 2).fill(Color.primary.opacity(0.1))
        switch nativeDockEdge {
        case .bottom: hint.frame(width: 110, height: 6).frame(maxHeight: .infinity, alignment: .bottom).padding(.bottom, 16)
        case .left: hint.frame(width: 6, height: 70).frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 16)
        case .right: hint.frame(width: 6, height: 70).frame(maxWidth: .infinity, alignment: .trailing).padding(.trailing, 16)
        case .top: EmptyView()
        }
    }
}

// MARK: - Tiles

struct TileListSection: View {
    let settings: SettingsModel
    let profileID: ProfileID

    private var items: [TileItem] { settings.document.profile(profileID)?.items ?? [] }

    var body: some View {
        SettingsSection(title: "Tiles") {
            if items.isEmpty {
                Text("No tiles yet. Add apps or folders, or drop them onto the dock.").foregroundStyle(.secondary)
            }
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                HStack(spacing: 10) {
                    icon(item).frame(width: 22, height: 22)
                    Text(name(item)).lineLimit(1)
                    Spacer()
                    Button { move(index, by: -1) } label: { Image(systemName: "chevron.up") }
                        .buttonStyle(.borderless).disabled(index == 0).accessibilityLabel("Move \(name(item)) up")
                    Button { move(index, by: 1) } label: { Image(systemName: "chevron.down") }
                        .buttonStyle(.borderless).disabled(index == items.count - 1).accessibilityLabel("Move \(name(item)) down")
                    Button { remove(item.id) } label: { Image(systemName: "minus.circle") }
                        .buttonStyle(.borderless).accessibilityLabel("Remove \(name(item))")
                }
                if index < items.count - 1 { Divider() }
            }
            HStack {
                Button("Add App…") { add(apps: true) }
                Button("Add Folder…") { add(apps: false) }
                Button("Add Separator") { append(TileItem(id: newID(), kind: .separator)) }
            }
            .padding(.top, 4)
        }
    }

    private func name(_ item: TileItem) -> String {
        if item.kind == .separator { return "Separator" }
        if let n = item.displayName { return n }
        if let p = item.path { return URL(fileURLWithPath: p).deletingPathExtension().lastPathComponent }
        return item.bundleID ?? "Tile"
    }

    @ViewBuilder private func icon(_ item: TileItem) -> some View {
        if item.kind == .separator {
            Image(systemName: "minus")
        } else if let p = item.path {
            Image(nsImage: NSWorkspace.shared.icon(forFile: p)).resizable()
        } else {
            Image(systemName: "app")
        }
    }

    private func newID() -> TileID { TileItem.newID() }

    private func edit(_ change: (inout [TileItem]) -> Void) {
        settings.update { doc in
            guard let i = doc.profiles.firstIndex(where: { $0.id == profileID }) else { return }
            change(&doc.profiles[i].items)
        }
    }

    private func move(_ index: Int, by delta: Int) {
        edit { items in
            let target = index + delta
            guard items.indices.contains(index), items.indices.contains(target) else { return }
            items.swapAt(index, target)
        }
    }

    private func remove(_ id: TileID) { edit { $0.removeAll { $0.id == id } } }
    private func append(_ item: TileItem) { edit { $0.append(item) } }

    private func add(apps: Bool) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = !apps
        panel.canChooseFiles = apps
        if apps {
            panel.allowedContentTypes = [.application]
            panel.directoryURL = URL(fileURLWithPath: "/Applications")
        }
        // A sheet, never runModal: a modal session would stall the pointer monitors and the dock
        // the Settings window is holding open (as REG-057 showed for the launch notice).
        let add = { (response: NSApplication.ModalResponse) in
            guard response == .OK else { return }
            for url in panel.urls {
                append(apps ? .app(at: url, id: newID()) : .folder(at: url, id: newID()))
            }
        }
        if let window = NSApp.keyWindow {
            panel.beginSheetModal(for: window, completionHandler: add)
        } else {
            panel.begin(completionHandler: add)
        }
    }
}
