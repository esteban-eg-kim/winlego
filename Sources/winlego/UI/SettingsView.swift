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
            Section("My layouts") {
                ForEach(model.config.customLayouts) { layout in
                    HStack(spacing: 16) {
                        LayoutPreview(layout: layout, portrait: false).frame(width: 64, height: 36)
                        Text(L(layout.name))
                        Spacer()
                        Button("Edit…") { model.openEditor(layout) }
                        Button(role: .destructive) { model.deleteCustomLayout(layout.id) } label: { Image(systemName: "trash") }
                            .buttonStyle(.borderless)
                    }
                }
                HStack {
                    Button("New Layout…") {
                        model.openEditor(WinlegoCore.Layout(id: "custom-\(UUID().uuidString.prefix(8).lowercased())", name: L("My Layout"), root: .zone(name: nil)))
                    }
                    Spacer()
                    Text("Or drag the boundary between two placed windows on the real screen, then save when asked.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
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
                            ForEach(model.allLayouts) { layout in Text(L(layout.name)).tag(layout.id) }
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
        .sheet(item: Binding(get: { model.editingLayout }, set: { model.editingLayout = $0 })) { _ in
            LayoutEditorView(model: model, editor: model.editor) { model.editingLayout = nil }
        }
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
                Text("Once the drag has started, hold ⌃ Control as well to merge the zones you pass over into one.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Boundary drag") {
                Toggle("Dismiss the “Save this layout?” prompt automatically", isOn: Binding(
                    get: { model.config.savePromptAutoDismiss },
                    set: { model.setSavePrompt(autoDismiss: $0, seconds: model.config.savePromptSeconds) }
                ))
                Stepper(value: Binding(
                    get: { model.config.savePromptSeconds },
                    set: { model.setSavePrompt(autoDismiss: model.config.savePromptAutoDismiss, seconds: $0) }
                ), in: 3...120, step: 1) {
                    LabeledContent("After") { Text(String(format: L("%lld s"), model.config.savePromptSeconds)).monospacedDigit() }
                }
                .disabled(!model.config.savePromptAutoDismiss)
                Text("Dismissing counts as “Not Now”: the windows keep their new sizes, the layout is not changed.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Shortcuts") {
                ForEach(HotKeyCenter.Key.allCases) { key in
                    ShortcutRow(model: model, key: key)
                }
                Text("Click a shortcut, then press the new keys. Esc cancels. Function keys work alone; other keys need ⌃, ⌥ or ⌘.")
                    .font(.caption).foregroundStyle(.secondary)
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

/// One shortcut: title, the combo as a button that records, reset and clear.
struct ShortcutRow: View {
    @ObservedObject var model: AppModel
    var key: HotKeyCenter.Key

    var body: some View {
        let recording = model.recordingShortcut == key
        let combo = model.shortcut(for: key)
        HStack {
            Text(key.title)
            Spacer()
            if model.shortcutFailed(key) {
                Label("In use by another app", systemImage: "exclamationmark.triangle.fill")
                    .labelStyle(.iconOnly).foregroundStyle(.orange)
                    .help("Another app holds this combination; pick a different one.")
            }
            Button {
                recording ? model.endRecording() : model.beginRecording(key)
            } label: {
                Text(recording ? "Press keys…" : KeyCombo.label(combo))
                    .monospaced()
                    .frame(minWidth: 90)
            }
            .buttonStyle(.bordered)
            .tint(recording ? .accentColor : nil)
            Button {
                model.setShortcut(key.defaultCombo, for: key)
            } label: { Image(systemName: "arrow.uturn.backward") }
                .buttonStyle(.borderless)
                .help("Reset to default")
                .disabled(combo == key.defaultCombo)
            Button {
                model.setShortcut(.none, for: key)
            } label: { Image(systemName: "xmark.circle") }
                .buttonStyle(.borderless)
                .help("No shortcut")
                .disabled(combo.isNone)
        }
    }
}
