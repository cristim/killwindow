import CoreGraphics
import Foundation

// Classification of the window under the cursor, derived from CGWindowList
// info (layer + owner). Dialogs are initially classified as .normal at
// mouseMoved time; the AX subrole probe in leftMouseDown upgrades them.
enum WindowKind {
    case normal            // layer 0, AX subrole = AXStandardWindow (or unknown)
    case dialog            // layer 0, AX subrole in {AXDialog, AXSheet, AXSystemDialog}
    case popoverSacrificial // layer > 0, owner in sacrificialOwners
    case popoverEscape     // layer > 0, owner in escapeOwners
    case popoverUnknown    // layer > 0, owner not in either list
}

struct Target {
    let pid: pid_t
    let app: String
    let title: String
    let windowID: CGWindowID
    let bounds: CGRect  // Quartz coords, top-left origin
    let kind: WindowKind
}

enum Outcome {
    case killed(Target, Int32)
    case closed(Target)          // AX close succeeded
    case dismissed(Target)       // Escape key posted
    case closeFailed(Target, String) // AX close failed; no silent fallback
    case noWindow
    case cancelled
    case dryRunDone              // dry-run printed its message inline; no final print needed
    case killFailed(Target, String)
}

func describe(_ t: Target) -> String {
    let titlePart = t.title.isEmpty ? "" : " title=\"\(t.title)\""
    return "pid=\(t.pid) app=\(t.app)\(titlePart)"
}
