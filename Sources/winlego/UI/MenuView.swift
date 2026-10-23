import SwiftUI

struct MenuView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Toggle("Keep Windows in Zones", isOn: $model.enabled)

        Divider()

        Section("Displays") {
            ForEach(model.screens) { screen in
                Text(screen.title)
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
