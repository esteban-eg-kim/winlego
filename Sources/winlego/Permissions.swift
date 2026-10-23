import AppKit
import ApplicationServices

/// One permission covers everything winlego does: Accessibility lets it read and move
/// other apps' windows and watch the mouse while a window is dragged.
/// Input Monitoring is not needed; that is for watching the keyboard.
enum Permissions {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Shows the system prompt that adds winlego to the Accessibility list.
    static func request() {
        // The value of kAXTrustedCheckOptionPrompt; the global itself is not concurrency-safe.
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    static func openSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }
}
