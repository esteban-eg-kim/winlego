import AppKit

/// A connected display as the menu shows it.
struct ScreenInfo: Identifiable, Equatable {
    var id: String          // CGDisplay UUID: survives reconnects and ID reshuffles
    var name: String
    var frame: CGRect       // Quartz global coordinates (origin top-left of the main display)
    var visibleFrame: CGRect // Same coordinates, minus menu bar and Dock
    var pixelSize: CGSize

    var title: String {
        "\(name) (\(Int(pixelSize.width))×\(Int(pixelSize.height)))"
    }

    var isPortrait: Bool { frame.height > frame.width }
}

enum Screens {
    static func current() -> [ScreenInfo] {
        // AppKit frames have their origin at the bottom-left of the primary display;
        // Quartz (and the Accessibility API) at its top-left. Flip around the primary height.
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return NSScreen.screens.compactMap { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
            else { return nil }
            let displayID = CGDirectDisplayID(number.uint32Value)
            guard let uuid = uuidString(for: displayID) else { return nil }
            let mode = CGDisplayCopyDisplayMode(displayID)
            return ScreenInfo(
                id: uuid,
                name: screen.localizedName,
                frame: CGDisplayBounds(displayID),
                visibleFrame: flipped(screen.visibleFrame, primaryHeight: primaryHeight),
                pixelSize: CGSize(width: mode?.pixelWidth ?? 0, height: mode?.pixelHeight ?? 0)
            )
        }
    }

    static func mainScreenID() -> String? {
        uuidString(for: CGMainDisplayID())
    }

    private static func flipped(_ rect: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    private static func uuidString(for displayID: CGDirectDisplayID) -> String? {
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue() else { return nil }
        return CFUUIDCreateString(nil, uuid) as String
    }
}
