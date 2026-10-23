import Carbon.HIToolbox
import os

/// Global shortcuts through Carbon's hot key API: no extra permission, works while any
/// app is frontmost.
@MainActor
final class HotKeyCenter {
    enum Key: UInt32, CaseIterable {
        case previousZone = 1, nextZone, previousDisplay, nextDisplay, arrangeAll, release

        var keyCode: UInt32 {
            switch self {
            case .previousZone: UInt32(kVK_LeftArrow)
            case .nextZone: UInt32(kVK_RightArrow)
            case .previousDisplay: UInt32(kVK_UpArrow)
            case .nextDisplay: UInt32(kVK_DownArrow)
            case .arrangeAll: UInt32(kVK_Return)
            case .release: UInt32(kVK_Delete)
            }
        }

        /// How the menu shows it.
        var label: String {
            switch self {
            case .previousZone: "⌃⌥←"
            case .nextZone: "⌃⌥→"
            case .previousDisplay: "⌃⌥↑"
            case .nextDisplay: "⌃⌥↓"
            case .arrangeAll: "⌃⌥↩"
            case .release: "⌃⌥⌫"
            }
        }
    }

    var handler: ((Key) -> Void)?
    private var hotKeys: [EventHotKeyRef] = []
    private var eventHandler: EventHandlerRef?
    private static let signature: OSType = "wlgo".utf8.reduce(0) { $0 << 8 | OSType($1) }

    func register() {
        guard eventHandler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), HotKeyCenter.callback, 1, &spec, refcon, &eventHandler)
        let log = Logger(subsystem: "io.github.esteban-eg-kim.winlego", category: "hotkeys")
        for key in Key.allCases {
            var ref: EventHotKeyRef?
            let id = EventHotKeyID(signature: HotKeyCenter.signature, id: key.rawValue)
            let status = RegisterEventHotKey(key.keyCode, UInt32(controlKey | optionKey), id, GetApplicationEventTarget(), 0, &ref)
            if status == noErr, let ref {
                hotKeys.append(ref)
            } else {
                // -9878 (eventHotKeyExistsErr): another app holds this combination.
                log.error("could not register \(key.label, privacy: .public): \(status)")
            }
        }
        log.info("registered \(self.hotKeys.count) of \(Key.allCases.count) hot keys")
    }

    func unregister() {
        hotKeys.forEach { UnregisterEventHotKey($0) }
        hotKeys.removeAll()
        if let eventHandler { RemoveEventHandler(eventHandler) }
        eventHandler = nil
    }

    private static let callback: EventHandlerUPP = { _, event, refcon in
        guard let refcon, let event else { return OSStatus(eventNotHandledErr) }
        var id = EventHotKeyID()
        GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                          MemoryLayout<EventHotKeyID>.size, nil, &id)
        guard id.signature == signature, let key = Key(rawValue: id.id) else { return OSStatus(eventNotHandledErr) }
        let center = Unmanaged<HotKeyCenter>.fromOpaque(refcon).takeUnretainedValue()
        Logger(subsystem: "io.github.esteban-eg-kim.winlego", category: "hotkeys").info("pressed \(key.label, privacy: .public)")
        MainActor.assumeIsolated { center.handler?(key) }
        return noErr
    }
}
