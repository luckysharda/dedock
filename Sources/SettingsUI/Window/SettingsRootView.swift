import DesignSystem
import Observation
import SettingsStore
import SwiftUI

enum SettingsPane: String, CaseIterable, Identifiable {
    case edgeDock, general, about
    var id: String { rawValue }

    var title: String {
        switch self {
        case .edgeDock: "Edge Dock"
        case .general: "General"
        case .about: "About"
        }
    }

    var symbol: String {
        switch self {
        case .edgeDock: "sidebar.left"
        case .general: "gearshape"
        case .about: "info.circle"
        }
    }

    /// Sidebar group labels (DockDoor settings grammar: Features / Customization / System).
    var group: String {
        switch self {
        case .edgeDock: "Features"
        case .general, .about: "System"
        }
    }
}

/// Window-local navigation state. (`@State` is a macro in this SDK and the Command Line Tools
/// ship no SwiftUI macro plugin, so view state lives in an `@Observable` object instead.)
@MainActor @Observable final class SettingsNavigation {
    var pane: SettingsPane = .edgeDock
}

/// Full-height sidebar with group labels and an accent selection row, beside a content column.
struct SettingsRootView: View {
    let settings: SettingsModel
    let environment: SettingsEnvironment
    let navigation: SettingsNavigation

    private var pane: SettingsPane { navigation.pane }
    private var selection: Binding<SettingsPane?> {
        Binding(get: { navigation.pane }, set: { if let p = $0 { navigation.pane = p } })
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: SettingsTokens.sidebarWidth)
                .background(.thinMaterial)
            Divider()
            ScrollView {
                content
                    .padding(SettingsTokens.contentPadding)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .background(SettingsTokens.contentBackground)
        }
        .frame(minWidth: 760, minHeight: 520)
    }

    private var sidebar: some View {
        let groups = Dictionary(grouping: SettingsPane.allCases, by: \.group)
        return List(selection: selection) {
            ForEach(["Features", "System"], id: \.self) { group in
                Section(group) {
                    ForEach(groups[group] ?? []) { p in
                        Label(p.title, systemImage: p.symbol).tag(p)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .padding(.top, 28)
    }

    @ViewBuilder private var content: some View {
        switch pane {
        case .edgeDock: EdgeDockPane(settings: settings, environment: environment)
        case .general: GeneralPane(settings: settings)
        case .about: AboutPane()
        }
    }
}

struct GeneralPane: View {
    let settings: SettingsModel

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsTokens.sectionSpacing) {
            Text("General").font(.title2.weight(.semibold))
            SettingsSection(title: "Motion") {
                SettingsRow(label: "Reduce motion", help: "Slides become a short fade in place.") {
                    Picker("Reduce motion", selection: reduceMotion) {
                        Text("Follow System").tag(Bool?.none)
                        Text("On").tag(Bool?.some(true))
                        Text("Off").tag(Bool?.some(false))
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 260)
                }
            }
        }
    }

    private var reduceMotion: Binding<Bool?> {
        Binding(get: { settings.document.app.reduceMotionOverride },
                set: { v in settings.update { $0.app.reduceMotionOverride = v } })
    }
}

struct AboutPane: View {
    var body: some View {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
        VStack(alignment: .leading, spacing: 8) {
            Text("dedock").font(.title2.weight(.semibold))
            Text("Version \(version)").foregroundStyle(.secondary)
            Text("A second dock on the edge of your screen.").foregroundStyle(.secondary)
        }
    }
}
