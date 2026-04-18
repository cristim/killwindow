import CoreGraphics
import Foundation

struct Target {
    let pid: pid_t
    let app: String
    let title: String
    let windowID: CGWindowID
    let bounds: CGRect  // Quartz coords, top-left origin
}

enum Outcome {
    case killed(Target, Int32)
    case dryRun(Target, Int32)
    case noWindow
    case cancelled
    case killFailed(Target, String)
}

func describe(_ t: Target) -> String {
    let titlePart = t.title.isEmpty ? "" : " title=\"\(t.title)\""
    return "pid=\(t.pid) app=\(t.app)\(titlePart)"
}
