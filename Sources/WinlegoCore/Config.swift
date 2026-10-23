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

    public init() {}

    private enum CodingKeys: String, CodingKey {
        case layoutByDisplay, rules, dragTrigger, gap, excludedBundleIDs
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        layoutByDisplay = try c.decodeIfPresent([String: String].self, forKey: .layoutByDisplay) ?? [:]
        rules = try c.decodeIfPresent([Rule].self, forKey: .rules) ?? []
        dragTrigger = try c.decodeIfPresent(DragTrigger.self, forKey: .dragTrigger) ?? .shift
        gap = try c.decodeIfPresent(Double.self, forKey: .gap) ?? 0
        excludedBundleIDs = try c.decodeIfPresent([String].self, forKey: .excludedBundleIDs) ?? []
    }

    /// The layout a display uses: the chosen one, else the default for its orientation.
    public func layout(for displayID: String, portrait: Bool) -> Layout {
        if let id = layoutByDisplay[displayID], let layout = Presets.layout(id: id) { return layout }
        return Presets.layout(id: Presets.defaultID(portrait: portrait))!
    }
}
