import ApplicationServices
import CoreGraphics
import Foundation

// Finds the AXUIElement window in `pid` whose bounds match `bounds` within
// a few-pixel tolerance. Tries AXFocusedWindow first (cheap, usually correct
// for dialogs/sheets which are modal/focused), then falls back to enumerating
// all top-level AXWindows of the app.
//
// Why bounds-matching instead of trusting AXFocusedWindow: an app with both
// a normal window and a focused dialog/sheet elsewhere would otherwise have
// the user clicking the normal window but our AX query returning the
// dialog — leading to AX-close acting on a window the user never touched.
//
// Used at click time only — never in the mouseMoved hot path.
func findMatchingAXWindow(pid: pid_t, bounds: CGRect) -> AXUIElement? {
    let app = AXUIElementCreateApplication(pid)

    // Fast path: focused window. Modal dialogs/sheets land here.
    var focusedRef: CFTypeRef?
    if AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &focusedRef) == .success,
       let focusedRef {
        let focused = focusedRef as! AXUIElement
        if axBoundsMatch(focused, bounds) {
            return focused
        }
    }

    // Slow path: enumerate all top-level windows of the app, match by bounds.
    var windowsRef: CFTypeRef?
    guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &windowsRef) == .success,
          let windowsRef,
          let windows = windowsRef as? [AXUIElement]
    else { return nil }

    for window in windows where axBoundsMatch(window, bounds) {
        return window
    }
    return nil
}

// Convenience wrapper around `probeDialogSubrole`: returns the WindowKind
// that the CGWindowList-classified `.normal` target should be upgraded to.
// Returns `.dialog` when AX reports an AXDialog/AXSystemDialog subrole or an
// AXSheet role; returns `.normal` otherwise (including probe failure). Shared
// by both the live-preview path (via ProbeCache) and the click-dispatch path
// so the rendered action always matches the executed one.
func classifyForDialogUpgrade(pid: pid_t, bounds: CGRect) -> WindowKind {
    guard let (role, subrole) = probeDialogSubrole(pid: pid, targetBounds: bounds) else {
        return .normal
    }
    let isDialog =
        subrole == (kAXDialogSubrole as String) ||
        subrole == (kAXSystemDialogSubrole as String) ||
        role    == (kAXSheetRole as String)
    return isDialog ? .dialog : .normal
}

// Probes the AX role and subrole of the window matching `targetBounds`. Used
// to upgrade `.normal` (CGWindowList classification) to `.dialog` at click
// time when the window is actually an AXDialog/AXSystemDialog or has role
// AXSheet. Returns nil if no matching AX window is found or both role and
// subrole are empty (probe failed).
//
//   - subrole == kAXDialogSubrole / kAXSystemDialogSubrole for modal dialogs
//   - role == kAXSheetRole for attached sheets (AXSheet is a top-level role,
//     not a subrole)
func probeDialogSubrole(pid: pid_t, targetBounds: CGRect) -> (role: String, subrole: String)? {
    guard let window = findMatchingAXWindow(pid: pid, bounds: targetBounds) else { return nil }

    var roleRef: CFTypeRef?
    let roleErr = AXUIElementCopyAttributeValue(
        window, kAXRoleAttribute as CFString, &roleRef)
    let role = (roleErr == .success ? roleRef as? String : nil) ?? ""

    var subroleRef: CFTypeRef?
    let subroleErr = AXUIElementCopyAttributeValue(
        window, kAXSubroleAttribute as CFString, &subroleRef)
    let subrole = (subroleErr == .success ? subroleRef as? String : nil) ?? ""

    if role.isEmpty && subrole.isEmpty { return nil }
    return (role: role, subrole: subrole)
}

// True if `element`'s AX position+size match `bounds` within a few-pixel tolerance.
// Returns false if either AX attribute is missing or the values diverge.
private func axBoundsMatch(_ element: AXUIElement, _ bounds: CGRect) -> Bool {
    var posRef: CFTypeRef?
    var sizeRef: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posRef) == .success,
          AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef) == .success,
          let posValue = posRef, let sizeValue = sizeRef
    else { return false }

    var pos = CGPoint.zero
    var size = CGSize.zero
    let gotPos  = AXValueGetValue(posValue  as! AXValue, .cgPoint, &pos)
    let gotSize = AXValueGetValue(sizeValue as! AXValue, .cgSize,  &size)
    guard gotPos, gotSize else { return false }

    let tol: CGFloat = 4
    return abs(pos.x - bounds.origin.x) <= tol
        && abs(pos.y - bounds.origin.y) <= tol
        && abs(size.width  - bounds.width)  <= tol
        && abs(size.height - bounds.height) <= tol
}

// Attempts to AX-close the window matching `target.bounds` (NOT the focused
// window, unless they happen to match — see findMatchingAXWindow). Strategy:
//   1. Try kAXCancelAction (relevant for AXDialog with a Cancel button).
//   2. Read the standard kAXCloseButtonAttribute on the window and press it
//      (Apple's documented way to obtain the close button).
//   3. Fall back to scanning kAXChildrenAttribute for an AXCloseButton subrole.
// Returns true on first success, false on all-fail or no-match.
// AX failures are silent — caller decides the fallback.
func performAxClose(target: Target) -> Bool {
    guard let window = findMatchingAXWindow(pid: target.pid, bounds: target.bounds) else { return false }

    // 1. Try kAXCancelAction — works on AXDialogs that have a Cancel button.
    let cancelResult = AXUIElementPerformAction(window, kAXCancelAction as CFString)
    if cancelResult == .success { return true }

    // 2. Standard close-button attribute on the window. Apple's documented
    // approach. There is no public kAXCloseAction constant for windows;
    // press the AXCloseButton element via kAXPressAction.
    var closeButtonRef: CFTypeRef?
    if AXUIElementCopyAttributeValue(window, kAXCloseButtonAttribute as CFString, &closeButtonRef) == .success,
       let closeButtonRef {
        let closeButton = closeButtonRef as! AXUIElement
        if AXUIElementPerformAction(closeButton, kAXPressAction as CFString) == .success {
            return true
        }
    }

    // 3. Fall back to scanning immediate children for an AXCloseButton subrole.
    // Some dialogs/sheets expose the close button as a child element rather
    // than through kAXCloseButtonAttribute.
    var childrenRef: CFTypeRef?
    let childrenErr = AXUIElementCopyAttributeValue(
        window, kAXChildrenAttribute as CFString, &childrenRef)
    guard childrenErr == .success, let childrenRef,
          let children = childrenRef as? [AXUIElement]
    else { return false }

    for child in children {
        var subroleRef: CFTypeRef?
        let subroleErr = AXUIElementCopyAttributeValue(
            child, kAXSubroleAttribute as CFString, &subroleRef)
        guard subroleErr == .success, let subroleRef else { continue }
        if (subroleRef as? String) == (kAXCloseButtonSubrole as String) {
            let pressResult = AXUIElementPerformAction(child, kAXPressAction as CFString)
            if pressResult == .success { return true }
        }
    }

    return false
}

// Posts a global Escape key event (virtualKey 53) to the HID event tap.
// Fire-and-forget: from our perspective it always "succeeds" (we don't poll
// whether a popover actually disappeared).
func postEscape() {
    guard let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: 53, keyDown: true),
          let keyUp   = CGEvent(keyboardEventSource: nil, virtualKey: 53, keyDown: false)
    else { return }
    keyDown.post(tap: .cghidEventTap)
    keyUp.post(tap: .cghidEventTap)
}
