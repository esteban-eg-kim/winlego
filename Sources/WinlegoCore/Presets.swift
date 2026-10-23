/// Built-in layouts. Ratios are expressed as fractions of the display's usable area.
public enum Presets {
    public static let halves = Layout(id: "halves", name: "Halves", zones: [
        Zone("Left", NormRect(x: 0, y: 0, width: 0.5, height: 1)),
        Zone("Right", NormRect(x: 0.5, y: 0, width: 0.5, height: 1)),
    ])
    public static let wideLeft = Layout(id: "wide-left", name: "Wide Left (⅔ + ⅓)", zones: [
        Zone("Left ⅔", NormRect(x: 0, y: 0, width: 2 / 3, height: 1)),
        Zone("Right ⅓", NormRect(x: 2 / 3, y: 0, width: 1 / 3, height: 1)),
    ])
    public static let wideRight = Layout(id: "wide-right", name: "Wide Right (⅓ + ⅔)", zones: [
        Zone("Left ⅓", NormRect(x: 0, y: 0, width: 1 / 3, height: 1)),
        Zone("Right ⅔", NormRect(x: 1 / 3, y: 0, width: 2 / 3, height: 1)),
    ])
    public static let thirds = Layout(id: "thirds", name: "Thirds", zones: [
        Zone("Left", NormRect(x: 0, y: 0, width: 1 / 3, height: 1)),
        Zone("Center", NormRect(x: 1 / 3, y: 0, width: 1 / 3, height: 1)),
        Zone("Right", NormRect(x: 2 / 3, y: 0, width: 1 / 3, height: 1)),
    ])
    public static let grid = Layout(id: "grid-2x2", name: "Grid 2×2", zones: [
        Zone("Top Left", NormRect(x: 0, y: 0, width: 0.5, height: 0.5)),
        Zone("Top Right", NormRect(x: 0.5, y: 0, width: 0.5, height: 0.5)),
        Zone("Bottom Left", NormRect(x: 0, y: 0.5, width: 0.5, height: 0.5)),
        Zone("Bottom Right", NormRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5)),
    ])
    public static let leftStack = Layout(id: "left-stack", name: "Left + Right Stack", zones: [
        Zone("Left", NormRect(x: 0, y: 0, width: 0.6, height: 1)),
        Zone("Top Right", NormRect(x: 0.6, y: 0, width: 0.4, height: 0.5)),
        Zone("Bottom Right", NormRect(x: 0.6, y: 0.5, width: 0.4, height: 0.5)),
    ])
    public static let center = Layout(id: "center", name: "Center Column", zones: [
        Zone("Center", NormRect(x: 0.125, y: 0, width: 0.75, height: 1)),
    ])
    public static let rows = Layout(id: "rows-2", name: "Top + Bottom", zones: [
        Zone("Top", NormRect(x: 0, y: 0, width: 1, height: 0.5)),
        Zone("Bottom", NormRect(x: 0, y: 0.5, width: 1, height: 0.5)),
    ])
    public static let rows3 = Layout(id: "rows-3", name: "Three Rows", zones: [
        Zone("Top", NormRect(x: 0, y: 0, width: 1, height: 1 / 3)),
        Zone("Middle", NormRect(x: 0, y: 1 / 3, width: 1, height: 1 / 3)),
        Zone("Bottom", NormRect(x: 0, y: 2 / 3, width: 1, height: 1 / 3)),
    ])
    public static let tallTop = Layout(id: "tall-top", name: "Tall Top (⅔ + ⅓)", zones: [
        Zone("Top ⅔", NormRect(x: 0, y: 0, width: 1, height: 2 / 3)),
        Zone("Bottom ⅓", NormRect(x: 0, y: 2 / 3, width: 1, height: 1 / 3)),
    ])

    public static let all: [Layout] = [
        halves, wideLeft, wideRight, thirds, grid, leftStack, center, rows, rows3, tallTop,
    ]

    public static func layout(id: String) -> Layout? {
        all.first { $0.id == id }
    }

    /// What a display gets before the user picks anything.
    public static func defaultID(portrait: Bool) -> String {
        portrait ? rows.id : wideLeft.id
    }
}
