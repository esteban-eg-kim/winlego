import SwiftUI
import WinlegoCore

/// Edit app rules: which zone of which display an app's windows go to.
struct RulesView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            if model.config.rules.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "square.grid.2x2").font(.system(size: 36)).foregroundStyle(.secondary)
                    Text("No rules yet").font(.headline)
                    Text("Add one here, or put a window where you want it and choose\n“Remember This Window Here” from the menu bar.")
                        .multilineTextAlignment(.center).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(model.config.rules) { rule in
                        RuleRow(model: model, rule: rule)
                    }
                }
            }
            Divider()
            HStack {
                Menu("Add Rule for App…") {
                    ForEach(model.runningApps(), id: \.bundleID) { app in
                        Button(app.name) { model.addRule(bundleID: app.bundleID, appName: app.name) }
                    }
                }
                .frame(width: 180)
                Spacer()
                Text("Rules apply when a window opens, and to every window with “Arrange All”.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Arrange All Now") { model.arrangeAll() }
            }
            .padding(12)
        }
    }
}

private struct RuleRow: View {
    @ObservedObject var model: AppModel
    var rule: Rule

    var body: some View {
        HStack(spacing: 12) {
            AppLabel(bundleID: rule.bundleID)
                .frame(width: 220, alignment: .leading)
                .lineLimit(1)
            TextField("Any title", text: Binding(
                get: { rule.titleContains ?? "" },
                set: { text in model.updateRule(rule.id) { $0.titleContains = text.isEmpty ? nil : text } }
            ))
            .textFieldStyle(.roundedBorder)
            .frame(width: 150)
            .help("Only windows whose title contains this text")
            Picker("", selection: Binding(
                get: { rule.displayID ?? "" },
                set: { id in model.updateRule(rule.id) { $0.displayID = id.isEmpty ? nil : id; $0.zone = 0 } }
            )) {
                Text("Main display").tag("")
                ForEach(model.screens) { screen in Text(screen.name).tag(screen.id) }
            }
            .labelsHidden()
            .frame(width: 160)
            Picker("", selection: Binding(
                get: { rule.zone },
                set: { zone in model.updateRule(rule.id) { $0.zone = zone } }
            )) {
                ForEach(Array(model.zones(forRuleDisplay: rule.displayID).enumerated()), id: \.offset) { index, zone in
                    Text("\(index + 1)  \(zone.name)").tag(index)
                }
            }
            .labelsHidden()
            .frame(width: 150)
            Button(role: .destructive) { model.removeRule(rule) } label: { Image(systemName: "trash") }
                .buttonStyle(.borderless)
                .help("Remove rule")
        }
        .padding(.vertical, 2)
    }
}
