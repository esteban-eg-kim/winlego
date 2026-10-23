/// A keyboard shortcut: a virtual key code plus modifier bits, independent of AppKit.
public struct KeyCombo: Codable, Hashable, Sendable {
    public struct Modifiers: OptionSet, Codable, Hashable, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
        public static let control = Modifiers(rawValue: 1)
        public static let option = Modifiers(rawValue: 2)
        public static let shift = Modifiers(rawValue: 4)
        public static let command = Modifiers(rawValue: 8)
    }

    /// macOS virtual key code (kVK_*). -1 means "no shortcut".
    public var keyCode: Int
    public var modifiers: Modifiers

    public init(keyCode: Int, modifiers: Modifiers) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    public static let none = KeyCombo(keyCode: -1, modifiers: [])
    public var isNone: Bool { keyCode < 0 }

    /// Function keys work alone; anything else needs ⌃, ⌥ or ⌘ so typing stays possible.
    public var isUsable: Bool {
        if isNone { return true }
        if KeyCombo.functionKeyCodes.contains(keyCode) { return true }
        return !modifiers.intersection([.control, .option, .command]).isEmpty
    }

    static let functionKeyCodes: Set<Int> = [122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111, 105, 107, 113, 106, 64, 79, 80, 90]
}
