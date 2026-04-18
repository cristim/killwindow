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
    default:       break  // fall through to one-shot kill mode
    }
}

let options = parseArgs()
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
    case .mouseMoved:
        let loc = event.location
        let target = findWindow(at: loc, myPid: myPid, anyLayer: options.anyLayer, debug: false)
        ui?.update(at: loc, target: target,
                   forceKill: forceKillNow(flags: event.flags, options: options))
        return Unmanaged.passUnretained(event)
    case .flagsChanged:
        // ⌘ pressed/released — re-paint UI without the user moving the mouse.
        let loc = CGEvent(source: nil)?.location ?? event.location
        let target = findWindow(at: loc, myPid: myPid, anyLayer: options.anyLayer, debug: false)
        ui?.update(at: loc, target: target,
                   forceKill: forceKillNow(flags: event.flags, options: options))
        return Unmanaged.passUnretained(event)
    case .leftMouseDown:
        let loc = event.location
        let sig: Int32 = forceKillNow(flags: event.flags, options: options) ? SIGKILL : SIGTERM
        if let target = findWindow(at: loc, myPid: myPid,
                                   anyLayer: options.anyLayer, debug: options.debug) {
            if options.dryRun {
                outcome = .dryRun(target, sig)
            } else if target.pid > 0 {
                let rc = kill(target.pid, sig)
                if rc == 0 {
                    outcome = .killed(target, sig)
                } else {
                    outcome = .killFailed(target, String(cString: strerror(errno)))
                }
            } else {
                outcome = .killFailed(target, "no pid on window")
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
    ui.update(at: startLoc, target: t, forceKill: forceKillNow(flags: flags, options: options))
}

print("click to terminate (SIGTERM) — hold ⌘ to force-kill (SIGKILL) — Esc to cancel")
NSApp.run()

ui.hide()

switch outcome {
case .killed(let t, let sig):
    print("sent \(signalName(sig)) to \(describe(t))")
case .dryRun(let t, let sig):
    print("would send \(signalName(sig)) to \(describe(t))")
case .noWindow:
    FileHandle.standardError.write(Data("no window at click location\n".utf8))
    exit(1)
case .cancelled:
    print("cancelled")
case .killFailed(let t, let msg):
    FileHandle.standardError.write(Data("kill failed for \(describe(t)): \(msg)\n".utf8))
    exit(1)
}
