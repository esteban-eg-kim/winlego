import CoreGraphics

/// Which way a split divides its space.
public enum Axis: String, Codable, Hashable, Sendable {
    /// Side by side: `first` on the left, `second` on the right. The divider is vertical.
    case horizontal
    /// Stacked: `first` on top, `second` below. The divider is horizontal.
    case vertical
}

/// A layout is a tree of splits whose leaves are zones. Dragging a divider changes one
/// split's ratio; the editor splits and removes leaves. Zones are numbered in leaf order.
public indirect enum SplitNode: Codable, Hashable, Sendable {
    case zone(name: String?)
    case split(axis: Axis, ratio: Double, first: SplitNode, second: SplitNode)
}

/// Path from the root: 0 steps into `first`, 1 into `second`. Empty is the root.
public typealias NodePath = [Int]

/// One leaf, resolved.
public struct Zone: Hashable, Sendable {
    public var name: String
    public var rect: NormRect
    public var path: NodePath
}

/// One split's boundary, resolved. `line` has zero width (horizontal split) or zero height.
public struct Divider: Hashable, Sendable {
    public var path: NodePath
    public var axis: Axis
    public var ratio: Double
    public var line: NormRect
    /// The split node's own area; a drag maps the cursor into this to get the new ratio.
    public var region: NormRect
}

public struct Layout: Codable, Hashable, Identifiable, Sendable {
    public static let minRatio = 0.1
    public static let maxRatio = 0.9

    public var id: String
    public var name: String
    public var root: SplitNode

    public init(id: String, name: String, root: SplitNode) {
        self.id = id
        self.name = name
        self.root = root
    }

    /// Leaves in order, with unnamed ones called "Zone n".
    public var zones: [Zone] {
        var zones: [Zone] = [], dividers: [Divider] = []
        root.walk(rect: .full, path: [], zones: &zones, dividers: &dividers)
        return zones.enumerated().map { index, zone in
            var zone = zone
            if zone.name.isEmpty { zone.name = "Zone \(index + 1)" }
            return zone
        }
    }

    public var dividers: [Divider] {
        var zones: [Zone] = [], dividers: [Divider] = []
        root.walk(rect: .full, path: [], zones: &zones, dividers: &dividers)
        return dividers
    }

    /// Absolute zone rectangles inside a display's usable area.
    public func frames(in visibleFrame: CGRect, gap: CGFloat = 0) -> [CGRect] {
        zones.map { $0.rect.resolved(in: visibleFrame, gap: gap) }
    }

    // MARK: - Editing (all return a changed copy)

    public func settingRatio(_ ratio: Double, at path: NodePath) -> Layout {
        let clamped = min(max(ratio, Layout.minRatio), Layout.maxRatio)
        return with(root.replacing(at: path) { node in
            guard case let .split(axis, _, first, second) = node else { return node }
            return .split(axis: axis, ratio: clamped, first: first, second: second)
        })
    }

    /// Divides a zone in two equal halves.
    public func splitting(_ path: NodePath, axis: Axis) -> Layout {
        with(root.replacing(at: path) { node in
            guard case let .zone(name) = node else { return node }
            return .split(axis: axis, ratio: 0.5, first: .zone(name: name), second: .zone(name: nil))
        })
    }

    /// Removes a zone; its sibling takes the whole space. The last zone stays.
    public func removing(_ path: NodePath) -> Layout {
        guard let last = path.last else { return self }
        let parentPath = Array(path.dropLast())
        return with(root.replacing(at: parentPath) { node in
            guard case let .split(_, _, first, second) = node else { return node }
            return last == 0 ? second : first
        })
    }

    public func renaming(_ path: NodePath, to name: String?) -> Layout {
        with(root.replacing(at: path) { node in
            guard case .zone = node else { return node }
            let trimmed = name?.trimmingCharacters(in: .whitespaces)
            return .zone(name: trimmed?.isEmpty == false ? trimmed : nil)
        })
    }

    private func with(_ root: SplitNode) -> Layout {
        Layout(id: id, name: name, root: root)
    }
}

public extension SplitNode {
    /// Resolves rectangles depth-first, collecting zones in reading order and dividers.
    func walk(rect: NormRect, path: NodePath, zones: inout [Zone], dividers: inout [Divider]) {
        switch self {
        case let .zone(name):
            zones.append(Zone(name: name ?? "", rect: rect, path: path))
        case let .split(axis, ratio, first, second):
            let (a, b, line) = rect.divided(axis: axis, ratio: ratio)
            dividers.append(Divider(path: path, axis: axis, ratio: ratio, line: line, region: rect))
            first.walk(rect: a, path: path + [0], zones: &zones, dividers: &dividers)
            second.walk(rect: b, path: path + [1], zones: &zones, dividers: &dividers)
        }
    }

    func node(at path: NodePath) -> SplitNode? {
        guard let step = path.first else { return self }
        guard case let .split(_, _, first, second) = self else { return nil }
        return (step == 0 ? first : second).node(at: Array(path.dropFirst()))
    }

    func replacing(at path: NodePath, with change: (SplitNode) -> SplitNode) -> SplitNode {
        guard let step = path.first else { return change(self) }
        guard case let .split(axis, ratio, first, second) = self else { return self }
        let rest = Array(path.dropFirst())
        return step == 0
            ? .split(axis: axis, ratio: ratio, first: first.replacing(at: rest, with: change), second: second)
            : .split(axis: axis, ratio: ratio, first: first, second: second.replacing(at: rest, with: change))
    }
}

public extension NormRect {
    /// Splits into two parts and returns the boundary line between them.
    func divided(axis: Axis, ratio: Double) -> (first: NormRect, second: NormRect, line: NormRect) {
        switch axis {
        case .horizontal:
            let cut = width * ratio
            return (NormRect(x: x, y: y, width: cut, height: height),
                    NormRect(x: x + cut, y: y, width: width - cut, height: height),
                    NormRect(x: x + cut, y: y, width: 0, height: height))
        case .vertical:
            let cut = height * ratio
            return (NormRect(x: x, y: y, width: width, height: cut),
                    NormRect(x: x, y: y + cut, width: width, height: height - cut),
                    NormRect(x: x, y: y + cut, width: width, height: 0))
        }
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
