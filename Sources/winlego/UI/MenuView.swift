import SwiftUI
import WinlegoCore

struct MenuView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Toggle("Keep Windows in Zones", isOn: $model.enabled)

        Divider()

        Menu("Move Window to") {
            ForEach(model.screens) { screen in
                Menu(screen.name) {
                    ForEach(Array(model.zones(on: screen).enumerated()), id: \.offset) { index, zone in
                        Button("\(index + 1)  \(zone.name)") { model.placeFocused(on: screen, zone: index) }
                    }
                }
            }
            Divider()
            Text("Previous / Next Zone  \(HotKeyCenter.Key.previousZone.label) \(HotKeyCenter.Key.nextZone.label)")
            Text("Previous / Next Display  \(HotKeyCenter.Key.previousDisplay.label) \(HotKeyCenter.Key.nextDisplay.label)")
        }
        Button("Remember This Window Here") { model.rememberFocused() }
        Button("Release This Window  \(HotKeyCenter.Key.release.label)") { model.releaseFocused() }
        Button("Arrange All by Rules  \(HotKeyCenter.Key.arrangeAll.label)") { model.arrangeAll() }

        Divider()

        Menu("Layouts") {
            ForEach(model.screens) { screen in
                Menu(screen.title) {
                    Picker("Layout", selection: Binding(
                        get: { model.layoutID(for: screen) },
                        set: { model.setLayout($0, for: screen) }
                    )) {
                        ForEach(Presets.all) { layout in
                            Text(layout.name).tag(layout.id)
                        }
                    }
                    .pickerStyle(.inline)
                }
            }
        }
        Menu("Rules") {
            if model.config.rules.isEmpty {
                Text("No rules yet. Place a window, then “Remember This Window Here”.")
            }
            ForEach(model.config.rules) { rule in
                Menu(model.describe(rule)) {
                    Button("Remove Rule") { model.removeRule(rule) }
                }
            }
        }

        Divider()

        Toggle("Open at Login", isOn: Binding(
            get: { model.launchAtLogin },
            set: { model.setLaunchAtLogin($0) }
        ))

        Divider()

        if !model.trusted {
            Button("⚠️ Allow Accessibility Access…") { model.requestAccess() }
        }
        Button("About winlego") {
            NSApp.activate(ignoringOtherApps: true)
            NSApp.orderFrontStandardAboutPanel(nil)
        }
        Button("Quit winlego") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
