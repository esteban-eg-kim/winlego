import SwiftUI

@main
struct WinlegoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            MenuView(model: delegate.model)
        } label: {
            MenuBarIcon(model: delegate.model)
        }
        .menuBarExtraStyle(.menu)
    }
}

private struct MenuBarIcon: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Image(systemName: model.isActive ? "square.grid.2x2.fill" : "square.grid.2x2")
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    private var onboarding: NSWindow?
    private var settings: NSWindow?
    private lazy var dev = DevCommands(model: model)

    func applicationDidFinishLaunching(_ notification: Notification) {
        dev.start()
        model.openSettings = { [weak self] tab in self?.showSettings(tab: tab) }
        if !model.trusted { showOnboarding() }
    }

    func showSettings(tab: SettingsTab) {
        model.settingsTab = tab
        if settings == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 760, height: 480),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = L("winlego Settings")
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: SettingsView(model: model))
            window.center()
            settings = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settings?.makeKeyAndOrderFront(nil)
    }

    private func showOnboarding() {
        let window = NSWindow(
            contentRect: .zero,
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = L("Welcome to winlego")
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: OnboardingView(model: model) { [weak window] in
            window?.close()
        })
        window.center()
        onboarding = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}
