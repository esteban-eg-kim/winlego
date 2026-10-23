import AppKit
import Combine
import WinlegoCore

@MainActor
final class AppModel: ObservableObject {
    @Published var enabled: Bool { didSet { defaults.set(enabled, forKey: Keys.enabled) } }
    @Published var launchAtLogin: Bool = LoginItem.isEnabled
    @Published private(set) var trusted = Permissions.isTrusted
    @Published private(set) var screens: [ScreenInfo] = []

    /// Enabled and permitted.
    var isActive: Bool { enabled && trusted }

    private let defaults = UserDefaults.standard
    private var accessPoll: Timer?
    private var observers: [NSObjectProtocol] = []

    private enum Keys {
        static let enabled = "enabled"
    }

    init() {
        defaults.register(defaults: [Keys.enabled: true])
        enabled = defaults.bool(forKey: Keys.enabled)

        refreshScreens()
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshScreens() }
        })
        if !trusted { pollAccess() }
    }

    func requestAccess() {
        Permissions.request()
        Permissions.openSettings()
        pollAccess()
    }

    func setLaunchAtLogin(_ on: Bool) {
        do {
            try LoginItem.set(on)
            launchAtLogin = LoginItem.isEnabled
        } catch {
            launchAtLogin = LoginItem.isEnabled
            NSLog("winlego: login item change failed: \(error)")
        }
    }

    private func refreshScreens() {
        screens = Screens.current()
    }

    /// The system never tells us when the user flips the switch; ask once a second until granted.
    private func pollAccess() {
        guard accessPoll == nil else { return }
        accessPoll = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            MainActor.assumeIsolated {
                if Permissions.isTrusted {
                    self.trusted = true
                    self.accessPoll?.invalidate()
                    self.accessPoll = nil
                }
            }
        }
    }
}
