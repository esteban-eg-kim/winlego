import CoreGraphics

/// A rectangle inside a display's usable area, as fractions of it (0…1).
/// Origin top-left, like Quartz and the Accessibility API.
public struct NormRect: Codable, Hashable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x; self.y = y; self.width = width; self.height = height
    }

    public static let full = NormRect(x: 0, y: 0, width: 1, height: 1)

    /// The absolute rectangle inside `frame`, shrunk by half the gap on every side so
    /// neighbouring zones end up `gap` apart. Edges are rounded to whole points, so two
    /// zones that share an edge meet exactly rather than overlapping by a pixel.
    public func resolved(in frame: CGRect, gap: CGFloat = 0) -> CGRect {
        let minX = (frame.minX + frame.width * x + gap / 2).rounded()
        let maxX = (frame.minX + frame.width * (x + width) - gap / 2).rounded()
        let minY = (frame.minY + frame.height * y + gap / 2).rounded()
        let maxY = (frame.minY + frame.height * (y + height) - gap / 2).rounded()
        return CGRect(x: minX, y: minY, width: max(maxX - minX, 0), height: max(maxY - minY, 0))
    }
}

public enum Geometry {
    /// Shared constants for the package.
    public static let bundleID = "io.github.esteban-eg-kim.winlego"

    /// Index of the zone under `point`, if any. The first match wins.
    public static func zoneIndex(containing point: CGPoint, in zones: [CGRect]) -> Int? {
        zones.firstIndex { $0.contains(point) }
    }

    /// The zone sharing the most area with `frame`; nil when they do not touch at all.
    public static func bestZone(for frame: CGRect, in zones: [CGRect]) -> Int? {
        var best: (index: Int, area: CGFloat)?
        for (index, zone) in zones.enumerated() {
            let area = frame.overlapArea(with: zone)
            if area > 0, area > (best?.area ?? 0) { best = (index, area) }
        }
        return best?.index
    }

    /// Converts between AppKit (origin bottom-left of the primary display) and Quartz
    /// (origin top-left) coordinates. Applying it twice gives the input back.
    public static func flip(_ rect: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    /// True when two rectangles share an edge (or overlap): the test for merging zones.
    public static func areAdjacent(_ a: CGRect, _ b: CGRect, tolerance: CGFloat = 1) -> Bool {
        a.insetBy(dx: -tolerance, dy: -tolerance).intersects(b)
    }

    /// Next zone index when stepping `delta` zones, wrapping around.
    public static func step(zone: Int, count: Int, by delta: Int) -> Int {
        guard count > 0 else { return 0 }
        let next = (zone + delta) % count
        return next < 0 ? next + count : next
    }
}

public extension CGRect {
    func overlapArea(with other: CGRect) -> CGFloat {
        let i = intersection(other)
        return i.isNull ? 0 : i.width * i.height
    }

    /// True when every edge is within `tolerance` points of `other`'s.
    func isClose(to other: CGRect, tolerance: CGFloat) -> Bool {
        abs(minX - other.minX) <= tolerance && abs(minY - other.minY) <= tolerance
            && abs(width - other.width) <= tolerance && abs(height - other.height) <= tolerance
    }
}
