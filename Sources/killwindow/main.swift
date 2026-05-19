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
        let target = findWindow(at: loc, myPid: myPid, anyLayer: options.anyLayer, debug: false)
        let flags = event.flags
        ui?.update(
            at: loc,
            target: target,
            forceKill: forceKillNow(flags: flags, options: options),
            closeWindow: closeWindowNow(flags: flags, options: options),
            forceKillSystem: options.forceKillSystem
        )
        return Unmanaged.passUnretained(event)
    case .flagsChanged:
        // ⌘/⌥ pressed/released — re-paint UI without the user moving the mouse.
        let loc = CGEvent(source: nil)?.location ?? event.location
        let target = findWindow(at: loc, myPid: myPid, anyLayer: options.anyLayer, debug: false)
        let flags = event.flags
        ui?.update(
            at: loc,
            target: target,
            forceKill: forceKillNow(flags: flags, options: options),
            closeWindow: closeWindowNow(flags: flags, options: options),
            forceKillSystem: options.forceKillSystem
        )
        return Unmanaged.passUnretained(event)
    case .leftMouseDown:
        let loc = event.location
        let flags = event.flags
        let fk = forceKillNow(flags: flags, options: options)
        let cw = closeWindowNow(flags: flags, options: options)

        if var target = findWindow(at: loc, myPid: myPid,
                                   anyLayer: options.anyLayer, debug: options.debug) {
            // AX subrole probe: upgrade .normal -> .dialog if the focused window
            // has a dialog/sheet subrole (or is an AXSheet by role). Only runs on
            // .normal targets (layer 0) since popovers are already classified by
            // owner. AX probe failure falls back to .normal — never crashes.
            if target.kind == .normal {
                if let (role, subrole) = probeDialogSubrole(pid: target.pid, targetBounds: target.bounds) {
                    // AXDialog and AXSystemDialog are subroles of AXWindow.
                    // AXSheet is a top-level role (not a subrole), so probe both.
                    let isDialog =
                        subrole == (kAXDialogSubrole as String) ||
                        subrole == (kAXSystemDialogSubrole as String) ||
                        role    == (kAXSheetRole as String)
                    if isDialog {
                        target = Target(
                            pid: target.pid,
                            app: target.app,
                            title: target.title,
                            windowID: target.windowID,
                            bounds: target.bounds,
                            kind: .dialog
                        )
                    }
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
    let t = findWindow(at: startLoc, myPid: myPid, anyLayer: options.anyLayer, debug: false)
    let flags = CGEvent(source: nil)?.flags ?? []
    ui.update(
        at: startLoc,
        target: t,
        forceKill: forceKillNow(flags: flags, options: options),
        closeWindow: closeWindowNow(flags: flags, options: options),
        forceKillSystem: options.forceKillSystem
    )
}

print("click to terminate (SIGTERM) — hold ⌘ to force-kill (SIGKILL) — hold ⌥ to close window (AX) — right-click or Esc to cancel")
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
