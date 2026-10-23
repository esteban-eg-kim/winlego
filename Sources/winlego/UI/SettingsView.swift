import SwiftUI
import WinlegoCore

enum SettingsTab: String, CaseIterable, Identifiable {
    case rules, layouts, general
    var id: String { rawValue }
}

/// The settings window: rules, per-display layouts, and general behaviour.
struct SettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        TabView(selection: $model.settingsTab) {
            RulesView(model: model)
                .tabItem { Label("Rules", systemImage: "list.bullet.rectangle") }
                .tag(SettingsTab.rules)
            LayoutsView(model: model)
                .tabItem { Label("Layouts", systemImage: "rectangle.split.2x1") }
                .tag(SettingsTab.layouts)
            GeneralView(model: model)
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(SettingsTab.general)
        }
        .frame(minWidth: 720, minHeight: 440)
        .padding()
    }
}

/// One row per display: which preset it uses, with a small preview.
struct LayoutsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Form {
            Section("Layout per display") {
                ForEach(model.screens) { screen in
                    HStack(spacing: 16) {
                        LayoutPreview(layout: model.manager.layout(for: screen), portrait: screen.isPortrait)
                            .frame(width: screen.isPortrait ? 36 : 64, height: screen.isPortrait ? 64 : 36)
                        VStack(alignment: .leading) {
                            Text(screen.name).font(.headline)
                            Text("\(Int(screen.pixelSize.width))×\(Int(screen.pixelSize.height))").foregroundStyle(.secondary).font(.caption)
                        }
                        Spacer()
                        Picker("", selection: Binding(
                            get: { model.layoutID(for: screen) },
                            set: { model.setLayout($0, for: screen) }
                        )) {
                            ForEach(Presets.all) { layout in Text(layout.name).tag(layout.id) }
                        }
                        .labelsHidden()
                        .frame(width: 220)
                    }
                    .padding(.vertical, 4)
                }
            }
            Section("Spacing") {
                HStack {
                    Slider(value: Binding(
                        get: { model.config.gap },
                        set: { model.setGap($0) }
                    ), in: 0...40, step: 2)
                    Text("\(Int(model.config.gap)) pt").monospacedDigit().frame(width: 48, alignment: .trailing)
                }
                Text("Gap between neighbouring zones. Takes effect the next time windows are placed.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

struct LayoutPreview: View {
    var layout: WinlegoCore.Layout
    var portrait: Bool

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 4).fill(Color.secondary.opacity(0.15))
                ForEach(Array(layout.zones.enumerated()), id: \.offset) { _, zone in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.accentColor.opacity(0.6))
                        .frame(width: geo.size.width * zone.rect.width - 2, height: geo.size.height * zone.rect.height - 2)
                        .offset(x: geo.size.width * zone.rect.x + 1, y: geo.size.height * zone.rect.y + 1)
                }
            }
        }
    }
}

struct GeneralView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Form {
            Section("Dragging") {
                Picker("Show zones while dragging", selection: Binding(
                    get: { model.config.dragTrigger },
                    set: { model.setDragTrigger($0) }
                )) {
                    Text("Holding ⇧ Shift").tag(DragTrigger.shift)
                    Text("Holding ⌥ Option").tag(DragTrigger.option)
                    Text("Always").tag(DragTrigger.always)
                }
                Text("Drop a window on a zone to put it there. Dropping an assigned window anywhere else lets it go.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Shortcuts") {
                ForEach(HotKeyCenter.Key.allCases, id: \.rawValue) { key in
                    LabeledContent(key.title) { Text(key.label).monospaced() }
                }
            }
            Section("Ignored apps") {
                if model.config.excludedBundleIDs.isEmpty {
                    Text("Windows of ignored apps are never placed by rules.").foregroundStyle(.secondary)
                }
                ForEach(model.config.excludedBundleIDs, id: \.self) { bundleID in
                    HStack {
                        AppLabel(bundleID: bundleID)
                        Spacer()
                        Button(role: .destructive) { model.setExcluded(bundleID, false) } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.borderless)
                    }
                }
                Menu("Ignore an App…") {
                    ForEach(model.runningApps(), id: \.bundleID) { app in
                        Button(app.name) { model.setExcluded(app.bundleID, true) }
                    }
                }
            }
            Section("Startup") {
                Toggle("Open at Login", isOn: Binding(
                    get: { model.launchAtLogin },
                    set: { model.setLaunchAtLogin($0) }
                ))
                LabeledContent("Accessibility access") {
                    if model.trusted {
                        Label("Allowed", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    } else {
                        Button("Allow…") { model.requestAccess() }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

/// Icon and name of an app, looked up by bundle identifier.
struct AppLabel: View {
    var bundleID: String

    var body: some View {
        let info = AppInfo.lookup(bundleID)
        HStack(spacing: 8) {
            if let icon = info.icon {
                Image(nsImage: icon).resizable().frame(width: 20, height: 20)
            }
            Text(info.name)
            Text(bundleID).font(.caption).foregroundStyle(.secondary)
        }
    }
}

extension HotKeyCenter.Key {
    var title: String {
        switch self {
        case .previousZone: "Previous zone"
        case .nextZone: "Next zone"
        case .previousDisplay: "Previous display"
        case .nextDisplay: "Next display"
        case .arrangeAll: "Arrange all by rules"
        case .release: "Release window"
        }
    }
}
