import AppKit
import ApplicationServices
import os

private typealias GetWindowFn = @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError

/// `_AXUIElementGetWindow` is not in the headers, but every window manager leans on it:
/// it is the only way to learn a window's Quartz number from its accessibility element.
private let getWindowNumber: GetWindowFn? = {
    guard let symbol = dlsym(dlopen(nil, RTLD_NOW), "_AXUIElementGetWindow") else { return nil }
    return unsafeBitCast(symbol, to: GetWindowFn.self)
}()

/// Identity of a window that survives re-listing.
struct WindowKey: Hashable, CustomStringConvertible {
    let pid: pid_t
    let number: CGWindowID
    var description: String { "\(pid)/\(number)" }
}

/// One window of another app, seen through the Accessibility API.
@MainActor
final class AXWindow {
    let element: AXUIElement
    let pid: pid_t
    let key: WindowKey?

    init(element: AXUIElement, pid: pid_t) {
        self.element = element
        self.pid = pid
        var number: CGWindowID = 0
        if let fn = getWindowNumber, fn(element, &number) == .success, number != 0 {
            key = WindowKey(pid: pid, number: number)
        } else {
            key = nil
        }
    }

    var title: String? { attribute(kAXTitleAttribute) as? String }
    var role: String? { attribute(kAXRoleAttribute) as? String }
    var subrole: String? { attribute(kAXSubroleAttribute) as? String }
    var isMinimized: Bool { (attribute(kAXMinimizedAttribute) as? Bool) ?? false }
    var isFullscreen: Bool { (attribute("AXFullScreen") as? Bool) ?? false }

    /// A normal, movable document or app window: not a sheet, popover, panel or dialog.
    var isStandard: Bool {
        role == kAXWindowRole && subrole == kAXStandardWindowSubrole
    }

    /// Something we would place: standard, visible, not in its own fullscreen Space.
    var isPlaceable: Bool {
        isStandard && !isMinimized && !isFullscreen
    }

    /// Quartz coordinates: origin top-left of the main display.
    var frame: CGRect? {
        guard let posValue = attribute(kAXPositionAttribute), let sizeValue = attribute(kAXSizeAttribute) else { return nil }
        var position = CGPoint.zero, size = CGSize.zero
        guard AXValueGetValue(posValue as! AXValue, .cgPoint, &position),
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &size) else { return nil }
        return CGRect(origin: position, size: size)
    }

    /// Sets size, then position, then size again: apps with a minimum size otherwise end
    /// up with the right origin but the wrong extent, or the other way round.
    @discardableResult
    func setFrame(_ target: CGRect) -> Bool {
        var size = target.size
        var position = target.origin
        guard let sizeValue = AXValueCreate(.cgSize, &size), let posValue = AXValueCreate(.cgPoint, &position) else { return false }
        let app = AXUIElementCreateApplication(pid)
        return AXWindow.withEnhancedUserInterfaceDisabled(app) {
            AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, sizeValue)
            let moved = AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, posValue)
            let sized = AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, sizeValue)
            return moved == .success && sized == .success
        }
    }

    func raise() {
        AXUIElementPerformAction(element, kAXRaiseAction as CFString)
    }

    private func attribute(_ name: String) -> AnyObject? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    /// Chromium and Electron apps resize wrongly while "enhanced user interface" is on
    /// (VoiceOver turns it on, and so do some apps on their own). Turn it off for the call.
    static func withEnhancedUserInterfaceDisabled<T>(_ app: AXUIElement, _ body: () -> T) -> T {
        let key = "AXEnhancedUserInterface" as CFString
        var value: CFTypeRef?
        let wasOn = AXUIElementCopyAttributeValue(app, key, &value) == .success && (value as? Bool) == true
        if wasOn { AXUIElementSetAttributeValue(app, key, kCFBooleanFalse) }
        defer { if wasOn { AXUIElementSetAttributeValue(app, key, kCFBooleanTrue) } }
        return body()
    }

    /// The windows of an app, in the order the app reports them (front to back).
    static func windows(of pid: pid_t) -> [AXWindow] {
        let app = AXUIElementCreateApplication(pid)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
              let elements = value as? [AXUIElement] else { return [] }
        return elements.map { AXWindow(element: $0, pid: pid) }
    }

    /// The window with keyboard focus anywhere on the system.
    static func focused() -> AXWindow? {
        let system = AXUIElementCreateSystemWide()
        var appValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedApplicationAttribute as CFString, &appValue) == .success,
              let appValue else { return nil }
        let app = appValue as! AXUIElement
        var pid: pid_t = 0
        AXUIElementGetPid(app, &pid)
        var windowValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &windowValue) == .success,
              let windowValue else { return nil }
        return AXWindow(element: windowValue as! AXUIElement, pid: pid)
    }
}
