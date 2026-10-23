import CoreGraphics

/// One slot of a layout.
public struct Zone: Codable, Hashable, Sendable {
    public var name: String
    public var rect: NormRect

    public init(_ name: String, _ rect: NormRect) {
        self.name = name
        self.rect = rect
    }
}

/// How one display is divided. Zones are addressed by index.
public struct Layout: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var zones: [Zone]

    public init(id: String, name: String, zones: [Zone]) {
        self.id = id
        self.name = name
        self.zones = zones
    }

    /// Absolute zone rectangles inside a display's usable area.
    public func frames(in visibleFrame: CGRect, gap: CGFloat = 0) -> [CGRect] {
        zones.map { $0.rect.resolved(in: visibleFrame, gap: gap) }
    }
}

/// Where a window lives: a zone of a display.
public struct Placement: Codable, Hashable, Sendable {
    public var displayID: String
    public var zone: Int

    public init(displayID: String, zone: Int) {
        self.displayID = displayID
        self.zone = zone
    }
}
