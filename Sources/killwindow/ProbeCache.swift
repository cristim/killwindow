import CoreGraphics
import Foundation

// Caches AX subrole probe results keyed by (pid, CGWindowID). Lets the live
// preview tooltip pick up the dialog/sheet upgrade without running the
// ~5–10ms AX query on every mouseMoved event.
//
// Reads use a concurrent queue (lock-free for hits); writes go through a
// barrier. Entries expire after `ttl` so a window state change (dialog
// dismissed, normal window now) self-heals on the next hover.
final class ProbeCache {
    private struct Entry {
        let kind: WindowKind
        let expiry: Date
    }
    private struct Key: Hashable {
        let pid: pid_t
        let windowID: CGWindowID
    }

    private var entries: [Key: Entry] = [:]
    private let queue = DispatchQueue(label: "killwindow.probecache", attributes: .concurrent)
    private let ttl: TimeInterval

    init(ttl: TimeInterval = 5.0) {
        self.ttl = ttl
    }

    // Returns cached kind if present and unexpired; nil if absent or expired.
    func get(pid: pid_t, windowID: CGWindowID) -> WindowKind? {
        let key = Key(pid: pid, windowID: windowID)
        return queue.sync {
            guard let entry = entries[key], entry.expiry > Date() else { return nil }
            return entry.kind
        }
    }

    func set(pid: pid_t, windowID: CGWindowID, kind: WindowKind) {
        let key = Key(pid: pid, windowID: windowID)
        let entry = Entry(kind: kind, expiry: Date().addingTimeInterval(ttl))
        queue.async(flags: .barrier) { [self] in
            entries[key] = entry
        }
    }
}
