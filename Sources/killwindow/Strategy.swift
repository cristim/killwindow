import Darwin
import Foundation

// Imperative strategy dispatched for each click. One action per click.
enum Strategy {
    case signal(Int32)     // send a POSIX signal to the owning process
    case axClose           // close the window via AX (AXFocusedWindow)
    case escapeKey         // post a global Escape key event
    case refusedProtected  // SIGKILL refused for protected owner
}

// Owner lists. Exact strings match kCGWindowOwnerName values.

// Services that are safe to SIGKILL — launchd respawns them on demand.
// SIGTERM is not used because some of these (notably AutoFillPanelService)
// silently ignore it. AX-close is not viable either — these processes expose
// zero AXWindows. SIGKILL is the only reliable dismissal.
let sacrificialOwners: Set<String> = [
    "AutoFillPanelService"
]

// Persistent UI services where killing disrupts menubar state. Escape key
// dismisses their popovers without side effects.
//
// NOTE: `Dock` deliberately excluded — its on-screen "window" is a single
// full-screen input-capture surface (layer 20, bounds spanning all displays),
// not a popover. Including it here would make the Dock intercept every click
// on screen, hijacking layer-0 app windows. Dock stays in
// `protectedFromSigkill` below so accidental ⌘+click via `-a` is still gated.
let escapeOwners: Set<String> = [
    "Spotlight",
    "Control Center",
    "NotificationCenter",
    "SystemUIServer",
    "TextInputMenuAgent"
]

// Discovery filter used by WindowFinder: layer-1+ windows owned by one of
// these are matched without `-a`. Limited to popovers we KNOW how to handle
// AND that don't span the whole screen.
let popoverOwners: Set<String> = sacrificialOwners.union(escapeOwners)

// SIGKILL gate used by chooseStrategy: refused for these owners unless
// --force-kill-system is passed. Includes escape-owners (whose SIGKILL would
// disrupt persistent menubar/notification UI) and the Dock. Sacrificial
// owners are deliberately NOT here — SIGKILL is their *correct* strategy
// (they're respawned by launchd, and SIGTERM doesn't reliably work on them).
let protectedFromSigkill: Set<String> = escapeOwners.union(["Dock"])

// Pure strategy selection — no side effects.
// Precedence (highest first):
//   1. forceKill + protected + !forceKillSystem  -> .refusedProtected
//   2. forceKill                                 -> .signal(SIGKILL)
//   3. closeWindow                               -> .axClose
//   4. by target.kind                            -> kind-specific default
func chooseStrategy(
    target: Target,
    forceKill: Bool,
    closeWindow: Bool,
    forceKillSystem: Bool
) -> Strategy {
    if forceKill && protectedFromSigkill.contains(target.app) && !forceKillSystem {
        return .refusedProtected
    }
    if forceKill {
        return .signal(SIGKILL)
    }
    if closeWindow {
        return .axClose
    }
    switch target.kind {
    case .normal:
        return .signal(SIGTERM)
    case .dialog:
        return .axClose
    case .popoverSacrificial:
        // SIGKILL, not SIGTERM — AutoFillPanelService and similar daemons
        // ignore SIGTERM. launchd respawns them on demand, so SIGKILL is safe.
        return .signal(SIGKILL)
    case .popoverEscape, .popoverUnknown:
        return .escapeKey
    }
}
