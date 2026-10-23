import AppKit

/// Name and icon for a bundle identifier, running or not.
enum AppInfo {
    struct Running: Hashable {
        var bundleID: String
        var name: String
    }

    static func lookup(_ bundleID: String) -> (name: String, icon: NSImage?) {
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first {
            return (app.localizedName ?? bundleID, app.icon)
        }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            let name = (try? url.resourceValues(forKeys: [.localizedNameKey]).localizedName)?
                .replacingOccurrences(of: ".app", with: "") ?? url.deletingPathExtension().lastPathComponent
            return (name, NSWorkspace.shared.icon(forFile: url.path))
        }
        return (bundleID, nil)
    }

    /// Regular apps running now, by name.
    static func running() -> [Running] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil && $0.bundleIdentifier != Bundle.main.bundleIdentifier }
            .map { Running(bundleID: $0.bundleIdentifier!, name: $0.localizedName ?? $0.bundleIdentifier!) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
