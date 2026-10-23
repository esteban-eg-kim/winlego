import AppKit
import Combine
import WinlegoCore

@MainActor
final class AppModel: ObservableObject {
    @Published var enabled: Bool {
        didSet {
            defaults.set(enabled, forKey: Keys.enabled)
            manager.enabled = enabled
            syncRunning()
        }
    }
    @Published private(set) var config: Config
    @Published var launchAtLogin: Bool = LoginItem.isEnabled
    @Published private(set) var trusted = Permissions.isTrusted
    @Published private(set) var screens: [ScreenInfo] = []
    @Published var settingsTab: SettingsTab = .rules
    /// Non-nil while the layout editor sheet is up.
    @Published var editingLayout: Layout?
    /// The shortcut row waiting for a key press, if any.
    @Published var recordingShortcut: HotKeyCenter.Key?
    private var recordMonitor: Any?
    let editor = LayoutEditorModel()

    /// Enabled, permitted, and watching windows.
    var isActive: Bool { enabled && trusted && manager.isRunning }

    let manager = ZoneManager()
    /// Installed by the app delegate, which owns the window.
    var openSettings: ((SettingsTab) -> Void)?
    private let hotKeys = HotKeyCenter()
    private let defaults = UserDefaults.standard
    private var accessPoll: Timer?
    private var observers: [NSObjectProtocol] = []

    private enum Keys {
        static let enabled = "enabled"
    }

    init() {
        defaults.register(defaults: [Keys.enabled: true])
        enabled = defaults.bool(forKey: Keys.enabled)
        config = ConfigStore.load()
        manager.config = config
        manager.enabled = enabled

        refreshScreens()
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refreshScreens()
                self?.manager.reapplyAllAfterSettling()
            }
        })

        hotKeys.handler = { [weak self] key in self?.hotKey(key) }
        manager.onLayoutEdited = { [weak self] screen, layout in
            guard let self else { return }
            config.upsert(layout)
            config.layoutByDisplay[screen.id] = layout.id
            ConfigStore.save(config)
        }
        if trusted { syncRunning() } else { pollAccess() }
    }

    // MARK: - Permissions

    func requestAccess() {
        Permissions.request()
        Permissions.openSettings()
        pollAccess()
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
                    self.syncRunning()
                }
            }
        }
    }

    private func syncRunning() {
        guard trusted else { return }
        registerHotKeys()
        if enabled { manager.start() }
        objectWillChange.send()
    }

    // MARK: - Shortcuts

    private func registerHotKeys() {
        var combos: [HotKeyCenter.Key: KeyCombo] = [:]
        for key in HotKeyCenter.Key.allCases { combos[key] = config.shortcuts[key.rawValue] }
        hotKeys.register(combos)
    }

    func shortcut(for key: HotKeyCenter.Key) -> KeyCombo {
        config.shortcuts[key.rawValue] ?? key.defaultCombo
    }

    func shortcutLabel(_ key: HotKeyCenter.Key) -> String { KeyCombo.label(shortcut(for: key)) }

    func shortcutFailed(_ key: HotKeyCenter.Key) -> Bool { hotKeys.failed.contains(key) }

    func setShortcut(_ combo: KeyCombo, for key: HotKeyCenter.Key) {
        config.shortcuts[key.rawValue] = combo == key.defaultCombo ? nil : combo
        configChanged()
        registerHotKeys()
    }

    /// Starts listening for the next key press in our own windows; Esc cancels.
    func beginRecording(_ key: HotKeyCenter.Key) {
        endRecording()
        recordingShortcut = key
        hotKeys.unregisterKeys()
        recordMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            let code = Int(event.keyCode)
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            var mods: KeyCombo.Modifiers = []
            if flags.contains(.control) { mods.insert(.control) }
            if flags.contains(.option) { mods.insert(.option) }
            if flags.contains(.shift) { mods.insert(.shift) }
            if flags.contains(.command) { mods.insert(.command) }
            MainActor.assumeIsolated {
                if code == 53 && mods.isEmpty {
                    self.endRecording()
                    return
                }
                let combo = KeyCombo(keyCode: code, modifiers: mods)
                guard combo.isUsable else { NSSound.beep(); return }
                self.endRecording()
                self.setShortcut(combo, for: key)
            }
            return nil
        }
    }

    func endRecording() {
        if let recordMonitor { NSEvent.removeMonitor(recordMonitor) }
        recordMonitor = nil
        if recordingShortcut != nil {
            recordingShortcut = nil
            registerHotKeys()
        }
    }

    // MARK: - Displays and layouts

    private func refreshScreens() {
        screens = Screens.current()
        manager.screens = screens
    }

    func layoutID(for screen: ScreenInfo) -> String {
        manager.layout(for: screen).id
    }

    func setLayout(_ layoutID: String, for screen: ScreenInfo) {
        config.layoutByDisplay[screen.id] = layoutID
        manager.discardSessionLayout(for: screen)
        configChanged()
        manager.reapplyAll()
    }

    func zones(on screen: ScreenInfo) -> [Zone] {
        manager.layout(for: screen).zones
    }

    // MARK: - Window commands

    func placeFocused(on screen: ScreenInfo, zone: Int) {
        manager.placeFocused(at: Placement(displayID: screen.id, zone: zone))
    }

    func releaseFocused() { manager.releaseFocused() }
    func arrangeAll() { manager.arrangeAll() }

    func rememberFocused() {
        guard let rule = manager.ruleForFocused() else { return }
        // One app-wide rule per app; a new one replaces the old.
        config.rules.removeAll { $0.bundleID == rule.bundleID && $0.titleContains == nil }
        config.rules.append(rule)
        configChanged()
    }

    func setDragTrigger(_ trigger: DragTrigger) {
        config.dragTrigger = trigger
        configChanged()
    }

    func setGap(_ gap: Double) {
        config.gap = gap
        configChanged()
    }

    func setExcluded(_ bundleID: String, _ excluded: Bool) {
        config.excludedBundleIDs.removeAll { $0 == bundleID }
        if excluded { config.excludedBundleIDs.append(bundleID) }
        configChanged()
    }

    func addRule(bundleID: String, appName: String) {
        config.rules.append(Rule(bundleID: bundleID, appName: appName, displayID: nil, zone: 0))
        configChanged()
    }

    func updateRule(_ id: UUID, _ change: (inout Rule) -> Void) {
        guard let index = config.rules.firstIndex(where: { $0.id == id }) else { return }
        change(&config.rules[index])
        configChanged()
    }

    func removeRule(_ rule: Rule) {
        config.rules.removeAll { $0.id == rule.id }
        configChanged()
    }

    func runningApps() -> [AppInfo.Running] { AppInfo.running() }

    var allLayouts: [Layout] { config.allLayouts }

    func saveCustomLayout(_ layout: Layout) {
        config.upsert(layout)
        configChanged()
        manager.reapplyAll()
    }

    func deleteCustomLayout(_ id: String) {
        config.customLayouts.removeAll { $0.id == id }
        for (display, layoutID) in config.layoutByDisplay where layoutID == id {
            config.layoutByDisplay[display] = nil
        }
        configChanged()
        manager.reapplyAll()
    }

    func openEditor(_ layout: Layout) {
        editor.load(layout)
        editingLayout = layout
    }

    /// The zones a rule can pick from: those of its display's layout (main display when unset).
    func zones(forRuleDisplay displayID: String?) -> [Zone] {
        let screen = displayID.flatMap { id in screens.first { $0.id == id } }
            ?? screens.first { $0.id == Screens.mainScreenID() }
            ?? screens.first
        return screen.map(zones(on:)) ?? []
    }

    /// How the menu describes where a rule sends windows.
    func describe(_ rule: Rule) -> String {
        let screen = rule.displayID.flatMap { id in screens.first { $0.id == id } }
            ?? screens.first { $0.id == Screens.mainScreenID() }
        let zoneName = screen.flatMap { s in zones(on: s).indices.contains(rule.zone) ? L(zones(on: s)[rule.zone].name) : nil }
            ?? String(format: L("Zone %lld"), rule.zone + 1)
        let title = rule.titleContains.map { " “\($0)”" } ?? ""
        return "\(rule.appName)\(title) → \(screen?.name ?? L("Main display")) · \(zoneName)"
    }

    private func configChanged() {
        manager.config = config
        ConfigStore.save(config)
    }

    private func hotKey(_ key: HotKeyCenter.Key) {
        guard enabled, trusted else { return }
        switch key {
        case .previousZone: manager.moveFocused(by: -1)
        case .nextZone: manager.moveFocused(by: 1)
        case .previousDisplay: manager.moveFocusedToDisplay(by: -1)
        case .nextDisplay: manager.moveFocusedToDisplay(by: 1)
        case .arrangeAll: manager.arrangeAll()
        case .release: manager.releaseFocused()
        }
    }

    // MARK: - Login item

    func setLaunchAtLogin(_ on: Bool) {
        do {
            try LoginItem.set(on)
        } catch {
            NSLog("winlego: login item change failed: \(error)")
        }
        launchAtLogin = LoginItem.isEnabled
    }
}
