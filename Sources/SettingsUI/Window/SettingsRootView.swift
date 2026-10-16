import DesignSystem
import Observation
import SettingsStore
import SwiftUI

enum SettingsPane: String, CaseIterable, Identifiable {
    case edgeDock, appearance, general, about
    var id: String { rawValue }

    var title: String {
        switch self {
        case .edgeDock: "Edge Dock"
        case .appearance: "Appearance"
        case .general: "General"
        case .about: "About"
        }
    }

    var symbol: String {
        switch self {
        case .edgeDock: "sidebar.left"
        case .appearance: "paintpalette"
        case .general: "gearshape"
        case .about: "info.circle"
        }
    }

    /// Sidebar group labels (DockDoor settings grammar: Features / Customization / System).
    var group: String {
        switch self {
        case .edgeDock: "Features"
        case .appearance: "Customization"
        case .general, .about: "System"
        }
    }
}

/// Window-local navigation state. (`@State` is a macro in this SDK and the Command Line Tools
/// ship no SwiftUI macro plugin, so view state lives in an `@Observable` object instead.)
@MainActor @Observable final class SettingsNavigation {
    var pane: SettingsPane = .edgeDock
}

/// The window's backdrop, so the content is clear over Frosted and Liquid Glass and keeps its
/// solid background on Solid.
@MainActor @Observable final class SettingsChrome {
    var backdrop: WindowLook.Backdrop = .solid
}

/// Full-height sidebar with group labels and an accent selection row, beside a content column.
struct SettingsRootView: View {
    let settings: SettingsModel
    let environment: SettingsEnvironment
    let navigation: SettingsNavigation
    let chrome: SettingsChrome

    private var pane: SettingsPane { navigation.pane }
    private var selection: Binding<SettingsPane?> {
        Binding(get: { navigation.pane }, set: { if let p = $0 { navigation.pane = p } })
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: SettingsTokens.sidebarWidth)
                .background(SettingsTokens.sidebarFill(chrome.backdrop))
            Divider()
            ScrollView {
                content
                    .padding(SettingsTokens.contentPadding)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .background(SettingsTokens.contentFill(chrome.backdrop))
        }
        .frame(minWidth: 760, minHeight: 520)
    }

    private var sidebar: some View {
        let groups = Dictionary(grouping: SettingsPane.allCases, by: \.group)
        return List(selection: selection) {
            ForEach(["Features", "Customization", "System"], id: \.self) { group in
                Section(group) {
                    ForEach(groups[group] ?? []) { p in
                        Label(p.title, systemImage: p.symbol).tag(p)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)      // the material is the window's choice, not the List's
        .padding(.top, 28)
    }

    @ViewBuilder private var content: some View {
        switch pane {
        case .edgeDock: EdgeDockPane(settings: settings, environment: environment)
        case .appearance: AppearancePane(settings: settings)
        case .general: GeneralPane(settings: settings)
        case .about: AboutPane()
        }
    }
}

/// Window appearance and material (T37b, design.md §7.2): Settings, onboarding, notices and
/// permission screens. The dock's own style is in the Edge Dock pane.
struct AppearancePane: View {
    let settings: SettingsModel

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsTokens.sectionSpacing) {
            Text("Appearance").font(.title2.weight(.semibold))
            SettingsSection(title: "Windows") {
                SettingsRow(label: "Appearance", help: "Settings and Dedock's other windows. The dock's style is in Edge Dock.") {
                    Picker("Appearance", selection: binding(\.windowAppearance)) {
                        Text("System").tag(AppPreferences.WindowAppearance.system)
                        Text("Light").tag(AppPreferences.WindowAppearance.light)
                        Text("Dark").tag(AppPreferences.WindowAppearance.dark)
                    }
                    .labelsHidden().pickerStyle(.segmented).frame(width: 260)
                }
                SettingsRow(label: "Material", help: Self.materialHelp) {
                    Picker("Material", selection: binding(\.windowMaterial)) {
                        Text("Frosted").tag(AppPreferences.WindowMaterial.frosted)
                        Text("Liquid Glass").tag(AppPreferences.WindowMaterial.liquidGlass)
                        Text("Solid").tag(AppPreferences.WindowMaterial.solid)
                    }
                    .labelsHidden().pickerStyle(.segmented).frame(width: 260)
                    .disabled(NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency)
                }
            }
        }
    }

    static var materialHelp: String? {
        if NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency { return "Reduce Transparency is on, so windows are solid." }
        return DockTokens.systemGlassAvailable ? nil : "Liquid Glass needs macOS 26; until then it is Frosted."
    }

    private func binding<V>(_ key: WritableKeyPath<AppPreferences, V>) -> Binding<V> {
        Binding(get: { settings.document.app[keyPath: key] }, set: { v in settings.update { $0.app[keyPath: key] = v } })
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
            Text("Dedock").font(.title2.weight(.semibold))
            Text("Version \(version)").foregroundStyle(.secondary)
            Text("A second dock on the edge of your screen.").foregroundStyle(.secondary)
        }
    }
}
