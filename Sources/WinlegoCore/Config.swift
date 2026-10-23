import Foundation

/// When dragging a window shows the zone overlay.
public enum DragTrigger: String, Codable, Sendable, CaseIterable {
    case shift, option, always
}

/// Everything the user chose. Stored as JSON; unknown keys are ignored and missing keys
/// take their defaults, so older files keep loading.
public struct Config: Codable, Equatable, Sendable {
    public var layoutByDisplay: [String: String] = [:]
    public var rules: [Rule] = []
    public var dragTrigger: DragTrigger = .shift
    /// Points between neighbouring zones.
    public var gap: Double = 0
    public var excludedBundleIDs: [String] = []
    /// Layouts the user drew or adjusted. They shadow a preset with the same id.
    public var customLayouts: [Layout] = []
    /// Shortcut overrides by action name; a missing action keeps its default.
    public var shortcuts: [String: KeyCombo] = [:]
    /// The "save this layout?" prompt after a boundary drag goes away on its own…
    public var savePromptAutoDismiss = true
    /// …after this many seconds.
    public var savePromptSeconds = 12

    public init() {}

    private enum CodingKeys: String, CodingKey {
        case layoutByDisplay, rules, dragTrigger, gap, excludedBundleIDs, customLayouts, shortcuts
        case savePromptAutoDismiss, savePromptSeconds
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        layoutByDisplay = try c.decodeIfPresent([String: String].self, forKey: .layoutByDisplay) ?? [:]
        rules = try c.decodeIfPresent([Rule].self, forKey: .rules) ?? []
        dragTrigger = try c.decodeIfPresent(DragTrigger.self, forKey: .dragTrigger) ?? .shift
        gap = try c.decodeIfPresent(Double.self, forKey: .gap) ?? 0
        excludedBundleIDs = try c.decodeIfPresent([String].self, forKey: .excludedBundleIDs) ?? []
        customLayouts = try c.decodeIfPresent([Layout].self, forKey: .customLayouts) ?? []
        shortcuts = try c.decodeIfPresent([String: KeyCombo].self, forKey: .shortcuts) ?? [:]
        savePromptAutoDismiss = try c.decodeIfPresent(Bool.self, forKey: .savePromptAutoDismiss) ?? true
        savePromptSeconds = try c.decodeIfPresent(Int.self, forKey: .savePromptSeconds) ?? 12
    }

    /// Custom layouts first, then the presets.
    public var allLayouts: [Layout] { customLayouts + Presets.all.filter { preset in !customLayouts.contains { $0.id == preset.id } } }

    public func layout(id: String) -> Layout? {
        customLayouts.first { $0.id == id } ?? Presets.layout(id: id)
    }

    /// The layout a display uses: the chosen one, else the default for its orientation.
    public func layout(for displayID: String, portrait: Bool) -> Layout {
        if let id = layoutByDisplay[displayID], let layout = layout(id: id) { return layout }
        return Presets.layout(id: Presets.defaultID(portrait: portrait))!
    }

    /// Adds or replaces a custom layout.
    public mutating func upsert(_ layout: Layout) {
        customLayouts.removeAll { $0.id == layout.id }
        customLayouts.append(layout)
    }
}
