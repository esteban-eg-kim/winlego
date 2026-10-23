/// Built-in layouts, written as split trees.
public enum Presets {
    private static func z(_ name: String) -> SplitNode { .zone(name: name) }
    private static func h(_ ratio: Double, _ a: SplitNode, _ b: SplitNode) -> SplitNode {
        .split(axis: .horizontal, ratio: ratio, first: a, second: b)
    }
    private static func v(_ ratio: Double, _ a: SplitNode, _ b: SplitNode) -> SplitNode {
        .split(axis: .vertical, ratio: ratio, first: a, second: b)
    }

    public static let fullScreen = Layout(id: "full", name: "Full Screen", root: z("Full"))
    public static let halves = Layout(id: "halves", name: "Halves", root: h(0.5, z("Left"), z("Right")))
    public static let wideLeft = Layout(id: "wide-left", name: "Wide Left (⅔ + ⅓)", root: h(2 / 3, z("Left ⅔"), z("Right ⅓")))
    public static let wideRight = Layout(id: "wide-right", name: "Wide Right (⅓ + ⅔)", root: h(1 / 3, z("Left ⅓"), z("Right ⅔")))
    public static let thirds = Layout(id: "thirds", name: "Thirds", root: h(1 / 3, z("Left"), h(0.5, z("Center"), z("Right"))))
    public static let grid = Layout(id: "grid-2x2", name: "Grid 2×2",
                                    root: v(0.5, h(0.5, z("Top Left"), z("Top Right")), h(0.5, z("Bottom Left"), z("Bottom Right"))))
    public static let leftStack = Layout(id: "left-stack", name: "Left + Right Stack",
                                         root: h(0.6, z("Left"), v(0.5, z("Top Right"), z("Bottom Right"))))
    public static let center = Layout(id: "center", name: "Center Column",
                                      root: h(0.15, z("Left"), h(0.7 / 0.85, z("Center"), z("Right"))))
    public static let rows = Layout(id: "rows-2", name: "Top + Bottom", root: v(0.5, z("Top"), z("Bottom")))
    public static let rows3 = Layout(id: "rows-3", name: "Three Rows", root: v(1 / 3, z("Top"), v(0.5, z("Middle"), z("Bottom"))))
    public static let tallTop = Layout(id: "tall-top", name: "Tall Top (⅔ + ⅓)", root: v(2 / 3, z("Top ⅔"), z("Bottom ⅓")))

    public static let all: [Layout] = [
        fullScreen, halves, wideLeft, wideRight, thirds, grid, leftStack, center, rows, rows3, tallTop,
    ]

    public static func layout(id: String) -> Layout? {
        all.first { $0.id == id }
    }

    /// What a display gets before the user picks anything.
    public static func defaultID(portrait: Bool) -> String {
        portrait ? rows.id : wideLeft.id
    }
}
