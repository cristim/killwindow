import AppKit
import CoreGraphics

let eventMask: CGEventMask =
    (1 << CGEventType.leftMouseDown.rawValue) |
    (1 << CGEventType.rightMouseDown.rawValue) |
    (1 << CGEventType.mouseMoved.rawValue) |
    (1 << CGEventType.flagsChanged.rawValue) |
    (1 << CGEventType.keyDown.rawValue)

// True if a click right now should SIGKILL rather than SIGTERM.
func forceKillNow(flags: CGEventFlags, options: Options) -> Bool {
    options.signal == SIGKILL || flags.contains(.maskCommand)
}

// True if a click right now should AX-close the window rather than kill.
func closeWindowNow(flags: CGEventFlags, options: Options) -> Bool {
    options.closeWindow || flags.contains(.maskAlternate)
}

func stopApp() {
    NSApp.stop(nil)
    // Post a dummy event to wake the NSApp run loop so it notices the stop flag.
    if let e = NSEvent.otherEvent(
        with: .applicationDefined, location: .zero, modifierFlags: [],
        timestamp: 0, windowNumber: 0, context: nil,
        subtype: 0, data1: 0, data2: 0)
    {
        NSApp.postEvent(e, atStart: true)
    }
}
