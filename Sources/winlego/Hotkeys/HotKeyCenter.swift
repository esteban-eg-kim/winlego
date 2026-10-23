import Carbon.HIToolbox
import os
import WinlegoCore

/// Global shortcuts through Carbon's hot key API: no extra permission, works while any
/// app is frontmost. Registration refuses a combination another app already holds.
@MainActor
final class HotKeyCenter {
    enum Key: String, CaseIterable, Identifiable {
        case previousZone, nextZone, previousDisplay, nextDisplay, arrangeAll, release
        var id: String { rawValue }

        /// Stable number for the hot key id.
        var number: UInt32 { UInt32(Key.allCases.firstIndex(of: self)! + 1) }

        var defaultCombo: KeyCombo {
            switch self {
            case .previousZone: KeyCombo(keyCode: kVK_LeftArrow, modifiers: [.control, .option])
            case .nextZone: KeyCombo(keyCode: kVK_RightArrow, modifiers: [.control, .option])
            case .previousDisplay: KeyCombo(keyCode: kVK_UpArrow, modifiers: [.control, .option])
            case .nextDisplay: KeyCombo(keyCode: kVK_DownArrow, modifiers: [.control, .option])
            case .arrangeAll: KeyCombo(keyCode: kVK_Return, modifiers: [.control, .option])
            case .release: KeyCombo(keyCode: kVK_Delete, modifiers: [.control, .option])
            }
        }

        var title: String {
            switch self {
            case .previousZone: L("Previous zone")
            case .nextZone: L("Next zone")
            case .previousDisplay: L("Previous display")
            case .nextDisplay: L("Next display")
            case .arrangeAll: L("Arrange all by rules")
            case .release: L("Release window")
            }
        }
    }

    var handler: ((Key) -> Void)?
    /// Keys whose combination could not be registered (taken by another app).
    private(set) var failed: Set<Key> = []

    private var hotKeys: [EventHotKeyRef] = []
    private var eventHandler: EventHandlerRef?
    private let log = Logger(subsystem: Geometry.bundleID, category: "hotkeys")
    private static let signature: OSType = "wlgo".utf8.reduce(0) { $0 << 8 | OSType($1) }

    /// Registers every key with its combo (default unless overridden); re-callable.
    func register(_ combos: [Key: KeyCombo]) {
        unregisterKeys()
        if eventHandler == nil {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            let refcon = Unmanaged.passUnretained(self).toOpaque()
            InstallEventHandler(GetApplicationEventTarget(), HotKeyCenter.callback, 1, &spec, refcon, &eventHandler)
        }
        for key in Key.allCases {
            let combo = combos[key] ?? key.defaultCombo
            guard !combo.isNone else { continue }
            var ref: EventHotKeyRef?
            let id = EventHotKeyID(signature: HotKeyCenter.signature, id: key.number)
            let status = RegisterEventHotKey(UInt32(combo.keyCode), HotKeyCenter.carbonModifiers(combo.modifiers), id,
                                             GetApplicationEventTarget(), 0, &ref)
            if status == noErr, let ref {
                hotKeys.append(ref)
            } else {
                failed.insert(key)
                log.error("could not register \(key.rawValue, privacy: .public) \(KeyCombo.label(combo), privacy: .public): \(status)")
            }
        }
        log.info("registered \(self.hotKeys.count) hot keys, \(self.failed.count) failed")
    }

    /// Lets go of every hot key, e.g. while the user records a new one.
    func unregisterKeys() {
        hotKeys.forEach { UnregisterEventHotKey($0) }
        hotKeys.removeAll()
        failed.removeAll()
    }

    func unregister() {
        unregisterKeys()
        if let eventHandler { RemoveEventHandler(eventHandler) }
        eventHandler = nil
    }

    private static func carbonModifiers(_ m: KeyCombo.Modifiers) -> UInt32 {
        var flags: UInt32 = 0
        if m.contains(.control) { flags |= UInt32(controlKey) }
        if m.contains(.option) { flags |= UInt32(optionKey) }
        if m.contains(.shift) { flags |= UInt32(shiftKey) }
        if m.contains(.command) { flags |= UInt32(cmdKey) }
        return flags
    }

    private static let callback: EventHandlerUPP = { _, event, refcon in
        guard let refcon, let event else { return OSStatus(eventNotHandledErr) }
        var id = EventHotKeyID()
        GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                          MemoryLayout<EventHotKeyID>.size, nil, &id)
        guard id.signature == signature, let key = Key.allCases.first(where: { $0.number == id.id }) else {
            return OSStatus(eventNotHandledErr)
        }
        let center = Unmanaged<HotKeyCenter>.fromOpaque(refcon).takeUnretainedValue()
        MainActor.assumeIsolated { center.handler?(key) }
        return noErr
    }
}

extension KeyCombo {
    /// ⌃⌥→ and friends.
    static func label(_ combo: KeyCombo) -> String {
        if combo.isNone { return "–" }
        var text = ""
        if combo.modifiers.contains(.control) { text += "⌃" }
        if combo.modifiers.contains(.option) { text += "⌥" }
        if combo.modifiers.contains(.shift) { text += "⇧" }
        if combo.modifiers.contains(.command) { text += "⌘" }
        return text + keyName(combo.keyCode)
    }

    private static let specialNames: [Int: String] = [
        kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        kVK_Return: "↩", kVK_ANSI_KeypadEnter: "⌤", kVK_Delete: "⌫", kVK_ForwardDelete: "⌦",
        kVK_Space: "␣", kVK_Tab: "⇥", kVK_Escape: "⎋", kVK_Home: "↖", kVK_End: "↘",
        kVK_PageUp: "⇞", kVK_PageDown: "⇟",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
        kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
        kVK_F13: "F13", kVK_F14: "F14", kVK_F15: "F15", kVK_F16: "F16", kVK_F17: "F17", kVK_F18: "F18",
        kVK_F19: "F19", kVK_F20: "F20",
    ]

    /// The character the key produces on the current keyboard layout, or a symbol.
    static func keyName(_ keyCode: Int) -> String {
        if let name = specialNames[keyCode] { return name }
        guard let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
              let data = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return "key \(keyCode)" }
        let layout = unsafeBitCast(data, to: CFData.self)
        var deadKeys: UInt32 = 0
        var length = 0
        var chars = [UniChar](repeating: 0, count: 4)
        let status = CFDataGetBytePtr(layout).withMemoryRebound(to: UCKeyboardLayout.self, capacity: 1) { ptr in
            UCKeyTranslate(ptr, UInt16(keyCode), UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                           OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeys, chars.count, &length, &chars)
        }
        guard status == noErr, length > 0 else { return "key \(keyCode)" }
        return String(utf16CodeUnits: chars, count: length).uppercased()
    }
}
