import SwiftUI

/// First-run window, shown only while the Accessibility permission is missing.
struct OnboardingView: View {
    @ObservedObject var model: AppModel
    var close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 2) {
                    Text("winlego").font(.title2.bold())
                    Text("Snap windows into zones, and keep them there.").foregroundStyle(.secondary)
                }
            }

            Text("To place other apps' windows into your zones and keep them there, winlego needs to see and move windows. Allow it under System Settings › Privacy & Security › Accessibility.")
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Label(
                    model.trusted ? "Access allowed" : "Waiting for access…",
                    systemImage: model.trusted ? "checkmark.circle.fill" : "hourglass"
                )
                .foregroundStyle(model.trusted ? .green : .secondary)
                Spacer()
                if model.trusted {
                    Button("Done", action: close).keyboardShortcut(.defaultAction)
                } else {
                    Button("Open System Settings") { model.requestAccess() }
                        .keyboardShortcut(.defaultAction)
                }
            }

            Text("winlego lives in the menu bar (\(Image(systemName: "square.grid.2x2.fill"))). Pick a layout for each display there.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(width: 440)
    }
}
