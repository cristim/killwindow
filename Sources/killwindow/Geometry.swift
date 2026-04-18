import AppKit

// Primary screen (menu-bar screen) — origin is (0, 0) in NSScreen coords.
// Its height drives the Quartz⇄NSScreen y-flip for all rect conversions.
func primaryScreen() -> NSScreen {
    NSScreen.screens.first { $0.frame.origin == .zero } ?? NSScreen.screens[0]
}

// Quartz rects (top-left origin) → NSScreen rects (bottom-left origin).
func quartzRectToNS(_ q: CGRect) -> NSRect {
    let h = primaryScreen().frame.height
    return NSRect(x: q.origin.x,
                  y: h - (q.origin.y + q.height),
                  width: q.width,
                  height: q.height)
}

func quartzPointToNS(_ p: CGPoint) -> NSPoint {
    NSPoint(x: p.x, y: primaryScreen().frame.height - p.y)
}
