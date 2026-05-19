import AppKit
import CoreGraphics
import Darwin

let myPid = getpid()

// Subcommand dispatch before any AppKit setup. Each handler is `-> Never`
// (it calls `exit`), so control returns here only when there is no match.
let rawArgs = Array(CommandLine.arguments.dropFirst())
if let sub = rawArgs.first {
    switch sub {
    case "daemon": runDaemon()
    case "setup":  runSetup(args: Array(rawArgs.dropFirst()))
    case "ax-probe":
        // Short-lived probe used by the daemon to check Accessibility
        // state from a fresh process (TCC results cache per-process,
        // so the daemon would never notice a mid-run grant otherwise).
        exit(requestAccessibilityTrust(prompt: false) ? 0 : 1)
    default:       break  // fall through to one-shot kill mode
    }
}

let options = parseArgs()

// Only one click-mode instance at a time — otherwise a rapid hotkey
// press could stack overlays + event taps on top of each other.
if tryAcquireLock(at: clickLockPath) < 0 {
    FileHandle.standardError.write(Data(
        "killwindow is already active — ignoring\n".utf8))
    exit(0)
}

var outcome: Outcome = .cancelled
var ui: KillwindowUI!

// Cache of AX dialog/sheet upgrade results so the live preview tooltip stays
// aligned with the click-time dispatch without re-probing on every event.
// Filled asynchronously on first hover; consulted synchronously on click.
let probeCache = ProbeCache()

// Latest cursor location seen by the tap. Read by the async-probe callback
// to re-render the tooltip when a probe completes while the cursor is still
// on the same window (otherwise a stationary cursor would never pick up the
// upgrade since mouseMoved wouldn't fire again).
var lastCursorLoc: CGPoint = .zero

// Resolve the kind the UI/dispatch should use, consulting the cache. A
// `.normal` target stays `.normal` until the AX probe upgrades it.
func resolvedKind(for target: Target) -> WindowKind {
    if target.kind != .normal { return target.kind }
    return probeCache.get(pid: target.pid, windowID: target.windowID) ?? .normal
}

// Returns a Target with `kind` replaced by the resolved kind.
func targetWithResolvedKind(_ target: Target) -> Target {
    let kind = resolvedKind(for: target)
    if kind == target.kind { return target }
    return Target(pid: target.pid, app: target.app, title: target.title,
                  windowID: target.windowID, bounds: target.bounds, kind: kind)
}

// Kick an asynchronous AX probe for `target` if its kind isn't cached yet.
// When the probe completes, the result is cached AND (if the probe upgraded
// the kind) a UI refresh is scheduled on the main run loop so a stationary
// cursor still picks up the new tooltip.
func kickProbeIfNeeded(target: Target) {
    guard target.kind == .normal else { return }
    if probeCache.get(pid: target.pid, windowID: target.windowID) != nil { return }
    let pid = target.pid
    let windowID = target.windowID
    let bounds = target.bounds
    DispatchQueue.global(qos: .userInteractive).async {
        let kind = classifyForDialogUpgrade(pid: pid, bounds: bounds)
        probeCache.set(pid: pid, windowID: windowID, kind: kind)
        guard kind == .dialog else { return }
        DispatchQueue.main.async { refreshTooltipAtCurrentCursor() }
    }
}

// Re-render the UI overlay using the current cursor location and the
// cache-resolved kind. Called from the async-probe completion handler.
func refreshTooltipAtCurrentCursor() {
    let loc = lastCursorLoc
    let flags = CGEvent(source: nil)?.flags ?? []
    let target = findWindow(at: loc, myPid: myPid, anyLayer: options.anyLayer, debug: false)
    let resolved = target.map(targetWithResolvedKind)
    ui?.update(
        at: loc,
        target: resolved,
        forceKill: forceKillNow(flags: flags, options: options),
        closeWindow: closeWindowNow(flags: flags, options: options),
        forceKillSystem: options.forceKillSystem
    )
}

let callback: CGEventTapCallBack = { _, type, event, _ in
    switch type {
    case .tapDisabledByTimeout, .tapDisabledByUserInput:
        return Unmanaged.passUnretained(event)
    case .keyDown:
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        if keyCode == 53 { // Esc
            outcome = .cancelled
            stopApp()
            return nil
        }
        return Unmanaged.passUnretained(event)
    case .rightMouseDown:
        // Right-click / two-finger trackpad tap cancels. We consume the
        // event so the target app doesn't receive a context-menu request.
        outcome = .cancelled
        stopApp()
        return nil
    case .mouseMoved:
        let loc = event.location
        lastCursorLoc = loc
        let target = findWindow(at: loc, myPid: myPid, anyLayer: options.anyLayer, debug: false)
        let resolved = target.map(targetWithResolvedKind)
        let flags = event.flags
        ui?.update(
            at: loc,
            target: resolved,
            forceKill: forceKillNow(flags: flags, options: options),
            closeWindow: closeWindowNow(flags: flags, options: options),
            forceKillSystem: options.forceKillSystem
        )
        if let target { kickProbeIfNeeded(target: target) }
        return Unmanaged.passUnretained(event)
    case .flagsChanged:
        // ⌘/⌥ pressed/released — re-paint UI without the user moving the mouse.
        let loc = CGEvent(source: nil)?.location ?? event.location
        lastCursorLoc = loc
        let target = findWindow(at: loc, myPid: myPid, anyLayer: options.anyLayer, debug: false)
        let resolved = target.map(targetWithResolvedKind)
        let flags = event.flags
        ui?.update(
            at: loc,
            target: resolved,
            forceKill: forceKillNow(flags: flags, options: options),
            closeWindow: closeWindowNow(flags: flags, options: options),
            forceKillSystem: options.forceKillSystem
        )
        if let target { kickProbeIfNeeded(target: target) }
        return Unmanaged.passUnretained(event)
    case .leftMouseDown:
        let loc = event.location
        let flags = event.flags
        let fk = forceKillNow(flags: flags, options: options)
        let cw = closeWindowNow(flags: flags, options: options)

        if var target = findWindow(at: loc, myPid: myPid,
                                   anyLayer: options.anyLayer, debug: options.debug) {
            // Resolve via cache first (filled asynchronously while the user
            // hovered), then fall back to a synchronous AX probe if the user
            // clicked before the cache warmed up. Either way the click-time
            // kind matches what the tooltip showed.
            if target.kind == .normal {
                let cached = probeCache.get(pid: target.pid, windowID: target.windowID)
                let kind = cached ?? classifyForDialogUpgrade(pid: target.pid, bounds: target.bounds)
                if cached == nil {
                    probeCache.set(pid: target.pid, windowID: target.windowID, kind: kind)
                }
                if kind != .normal {
                    target = Target(
                        pid: target.pid,
                        app: target.app,
                        title: target.title,
                        windowID: target.windowID,
                        bounds: target.bounds,
                        kind: kind
                    )
                }
            }

            let strategy = chooseStrategy(
                target: target,
                forceKill: fk,
                closeWindow: cw,
                forceKillSystem: options.forceKillSystem
            )

            if options.dryRun {
                // Dry-run: print what would happen, then exit cleanly.
                let description: String
                switch strategy {
                case .signal(let sig):
                    description = "would send \(signalName(sig)) to \(describe(target))"
                case .axClose:
                    description = "would close window (AX) of \(describe(target))"
                case .escapeKey:
                    description = "would dismiss popover of \(describe(target)) via Escape"
                case .refusedProtected:
                    description = "would refuse — \(target.app) is protected (pass --force-kill-system to override)"
                }
                print(description)
                outcome = .dryRunDone
            } else {
                // Live dispatch.
                switch strategy {
                case .signal(let sig):
                    if target.pid > 0 {
                        let rc = kill(target.pid, sig)
                        if rc == 0 {
                            outcome = .killed(target, sig)
                        } else {
                            outcome = .killFailed(target, String(cString: strerror(errno)))
                        }
                    } else {
                        outcome = .killFailed(target, "no pid on window")
                    }
                case .axClose:
                    if performAxClose(target: target) {
                        outcome = .closed(target)
                    } else {
                        outcome = .closeFailed(target, "AX close failed (check Accessibility permission)")
                    }
                case .escapeKey:
                    postEscape()
                    outcome = .dismissed(target)
                case .refusedProtected:
                    outcome = .killFailed(target,
                        "\(target.app) is protected from SIGKILL — pass --force-kill-system to override")
                }
            }
        } else {
            outcome = .noWindow
        }
        stopApp()
        return nil  // consume the click so the target app doesn't also receive it
    default:
        return Unmanaged.passUnretained(event)
    }
}

guard let tap = CGEvent.tapCreate(
    tap: .cgSessionEventTap,
    place: .headInsertEventTap,
    options: .defaultTap,
    eventsOfInterest: eventMask,
    callback: callback,
    userInfo: nil
) else {
    FileHandle.standardError.write(Data("""
    failed to create event tap.

    killwindow needs Accessibility permission to capture your next click.
    grant it for the terminal running this command:
      System Settings → Privacy & Security → Accessibility
    then re-run.

    """.utf8))
    exit(1)
}

let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
CFRunLoopAddSource(CFRunLoopGetCurrent(), src, .commonModes)
CGEvent.tapEnable(tap: tap, enable: true)

activateApp()
ui = KillwindowUI()

if let startLoc = CGEvent(source: nil)?.location {
    lastCursorLoc = startLoc
    let t = findWindow(at: startLoc, myPid: myPid, anyLayer: options.anyLayer, debug: false)
    let resolved = t.map(targetWithResolvedKind)
    let flags = CGEvent(source: nil)?.flags ?? []
    ui.update(
        at: startLoc,
        target: resolved,
        forceKill: forceKillNow(flags: flags, options: options),
        closeWindow: closeWindowNow(flags: flags, options: options),
        forceKillSystem: options.forceKillSystem
    )
    if let t { kickProbeIfNeeded(target: t) }
}

print(startupBanner(options: options))
NSApp.run()

ui.hide()

switch outcome {
case .killed(let t, let sig):
    print("sent \(signalName(sig)) to \(describe(t))")
case .closed(let t):
    print("closed window of \(describe(t))")
case .dismissed(let t):
    print("dismissed popover of \(describe(t))")
case .closeFailed(let t, let msg):
    FileHandle.standardError.write(Data("close failed for \(describe(t)): \(msg)\n".utf8))
    exit(1)
case .noWindow:
    FileHandle.standardError.write(Data("no window at click location\n".utf8))
    exit(1)
case .cancelled:
    print("cancelled")
case .dryRunDone:
    // dry-run message already printed inline at click time
    break
case .killFailed(let t, let msg):
    FileHandle.standardError.write(Data("kill failed for \(describe(t)): \(msg)\n".utf8))
    exit(1)
}
