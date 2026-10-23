import Foundation

/// "Windows of this app (with this in the title) go to that zone of that display."
public struct Rule: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var bundleID: String
    public var appName: String
    /// Case-insensitive substring of the window title; nil matches every window of the app.
    public var titleContains: String?
    /// Display UUID; nil means the main display.
    public var displayID: String?
    public var zone: Int

    public init(id: UUID = UUID(), bundleID: String, appName: String, titleContains: String? = nil,
                displayID: String?, zone: Int) {
        self.id = id
        self.bundleID = bundleID
        self.appName = appName
        self.titleContains = titleContains
        self.displayID = displayID
        self.zone = zone
    }
}

public enum Rules {
    /// The rule for a window. A title match beats an app-wide rule; among equals, the first wins.
    public static func match(_ rules: [Rule], bundleID: String, title: String?) -> Rule? {
        let candidates = rules.filter { $0.bundleID == bundleID }
        if let title, let titled = candidates.first(where: { rule in
            guard let needle = rule.titleContains, !needle.isEmpty else { return false }
            return title.localizedCaseInsensitiveContains(needle)
        }) {
            return titled
        }
        return candidates.first { $0.titleContains == nil || $0.titleContains?.isEmpty == true }
    }
}
