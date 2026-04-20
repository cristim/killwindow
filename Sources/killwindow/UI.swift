import AppKit

// Background view that uses its layer so borderless/transparent windows
// actually rasterize. WindowServer culls window-backgroundColor-only
// borderless windows in some cases — a layer-backed NSView forces a real
// surface and reliable rendering.
final class RoundedBGView: NSView {
    init(fill: NSColor, radius: CGFloat) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = fill.cgColor
        layer?.cornerRadius = radius
    }
    required init?(coder: NSCoder) { fatalError() }
}

// Two floating windows: a tint that hugs the target's bounds (orange for
// SIGTERM, red for SIGKILL), and a tooltip near the cursor naming the target.
final class KillwindowUI {
    static let sigtermColor = NSColor(calibratedRed: 1.00, green: 0.55, blue: 0.00, alpha: 0.30)
    static let sigkillColor = NSColor(calibratedRed: 1.00, green: 0.00, blue: 0.00, alpha: 0.30)

    private let highlight: NSWindow
    private let tooltip: NSWindow
    private let label: NSTextField
    private let bg: RoundedBGView
    private let tooltipPadding: CGFloat = 10

    init() {
        let highlightView = RoundedBGView(fill: KillwindowUI.sigtermColor, radius: 0)
        highlight = NSWindow(contentRect: .zero, styleMask: .borderless,
                             backing: .buffered, defer: false)
        highlight.level = .popUpMenu
        highlight.isOpaque = false
        highlight.hasShadow = false
        highlight.ignoresMouseEvents = true
        highlight.backgroundColor = .clear
        highlight.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        highlight.contentView = highlightView

        label = NSTextField(labelWithString: "")
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .white
        label.backgroundColor = .clear
        label.drawsBackground = false
        label.isBordered = false
        label.isEditable = false
        label.isSelectable = false

        bg = RoundedBGView(fill: NSColor(white: 0, alpha: 0.85), radius: 6)
        bg.addSubview(label)

        tooltip = NSWindow(contentRect: .zero, styleMask: .borderless,
                           backing: .buffered, defer: false)
        tooltip.level = .popUpMenu
        tooltip.isOpaque = false
        tooltip.hasShadow = true
        tooltip.ignoresMouseEvents = true
        tooltip.backgroundColor = .clear
        tooltip.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        tooltip.contentView = bg
    }

    func update(at quartzCursor: CGPoint, target: Target?, forceKill: Bool) {
        guard let target = target else {
            highlight.orderOut(nil)
            tooltip.orderOut(nil)
            return
        }

        let hiFrame = quartzRectToNS(target.bounds)
        highlight.setFrame(hiFrame, display: true)
        let tint = forceKill ? KillwindowUI.sigkillColor : KillwindowUI.sigtermColor
        (highlight.contentView as? RoundedBGView)?.layer?.backgroundColor = tint.cgColor
        if !highlight.isVisible { highlight.orderFrontRegardless() }

        let text: String
        if forceKill {
            text = "Force-kill \"\(target.app)\" (SIGKILL) — right-click to cancel"
        } else {
            text = "Terminate \"\(target.app)\" (SIGTERM) — hold ⌘ to force kill — right-click to cancel"
        }
        label.stringValue = text
        label.sizeToFit()
        let ls = label.frame.size
        let winSize = NSSize(width: ls.width + 2 * tooltipPadding,
                             height: ls.height + 2 * tooltipPadding)

        let nsCursor = quartzPointToNS(quartzCursor)
        let screen = NSScreen.screens.first { $0.frame.contains(nsCursor) } ?? primaryScreen()
        let sf = screen.frame
        let margin: CGFloat = 8
        let cursorOffset: CGFloat = 18

        var origin = NSPoint(x: nsCursor.x + cursorOffset,
                             y: nsCursor.y - winSize.height - cursorOffset)

        if origin.x + winSize.width + margin > sf.maxX {
            origin.x = nsCursor.x - winSize.width - cursorOffset
        }
        origin.x = max(sf.minX + margin,
                       min(origin.x, sf.maxX - winSize.width - margin))

        if origin.y < sf.minY + margin {
            origin.y = nsCursor.y + cursorOffset
        }
        origin.y = max(sf.minY + margin,
                       min(origin.y, sf.maxY - winSize.height - margin))

        tooltip.setFrame(NSRect(origin: origin, size: winSize), display: true)
        bg.frame = NSRect(origin: .zero, size: winSize)
        label.frame = NSRect(x: tooltipPadding, y: tooltipPadding,
                             width: ls.width, height: ls.height)
        if !tooltip.isVisible { tooltip.orderFrontRegardless() }
    }

    func hide() {
        highlight.orderOut(nil)
        tooltip.orderOut(nil)
    }
}

func activateApp() {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
    NSApp.finishLaunching()
}
