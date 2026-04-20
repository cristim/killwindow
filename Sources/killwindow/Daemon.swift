import AppKit
import ApplicationServices
import Carbon.HIToolbox
import Foundation

// Spawn the current binary with no arguments — which runs a one-shot
// kill-mode instance (overlay + event tap + tooltip).
private func spawnKillwindow() {
    let exePath = Bundle.main.executablePath ?? CommandLine.arguments[0]
    let task = Process()
    task.executableURL = URL(fileURLWithPath: exePath)
    task.arguments = []
    do {
        try task.run()
    } catch {
        FileHandle.standardError.write(
            Data("daemon: failed to launch killwindow: \(error)\n".utf8))
    }
}

private var hotKeyRef: EventHotKeyRef?
private var handlerRef: EventHandlerRef?

// C-compatible event handler — no Swift capture, just delegates to a
// file-scope function.
private let hotKeyHandler: EventHandlerUPP = { _, _, _ -> OSStatus in
    spawnKillwindow()
    return noErr
}

func runDaemon() -> Never {
    // When stdout is piped (launchd, CI, backgrounded shell) it defaults to
    // block-buffered — status messages get lost if we're killed before flush.
    setbuf(stdout, nil)
    setbuf(stderr, nil)

    let spec = currentHotkey()

    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
    NSApp.finishLaunching()

    // CGEventTap in the spawned click-mode needs Accessibility only —
    // the Carbon hotkey runs at the window-server level and doesn't
    // require Input Monitoring, so we don't ask for it.
    let binary = Bundle.main.executablePath ?? "/opt/homebrew/bin/killwindow"
    if !requestAccessibilityTrust(prompt: true) {
        FileHandle.standardError.write(Data("""
        daemon: waiting for Accessibility permission.
          System Settings → Privacy & Security → Accessibility → killwindow
        if killwindow isn't listed, click + and add: \(binary)

        """.utf8))
        // Poll via a child `killwindow ax-probe` — TCC results cache
        // per-process, so this running daemon would never notice a new
        // grant if it checked in-process. When the child reports
        // granted, exit(0); launchd's KeepAlive respawns us with a
        // fresh process that'll see the grant on its first check.
        while true {
            Thread.sleep(forTimeInterval: 3)
            let probe = Process()
            probe.executableURL = URL(fileURLWithPath: binary)
            probe.arguments = ["ax-probe"]
            do {
                try probe.run()
                probe.waitUntilExit()
            } catch {
                continue
            }
            if probe.terminationStatus == 0 {
                FileHandle.standardError.write(Data(
                    "daemon: Accessibility granted — exiting for a clean restart\n".utf8))
                exit(0)
            }
        }
    }

    // Signature "KWHK" (killwindow hotkey) — any stable 4-byte id is fine.
    let signature: OSType = 0x4B57484B  // 'KWHK'
    let hotKeyID = EventHotKeyID(signature: signature, id: 1)

    let regStatus = RegisterEventHotKey(
        spec.keyCode, spec.modifiers,
        hotKeyID, GetApplicationEventTarget(),
        0, &hotKeyRef)

    if regStatus != noErr {
        FileHandle.standardError.write(Data("""
        daemon: RegisterEventHotKey failed (status=\(regStatus)) for \(formatHotkey(spec)).
        another app may already own this combination. pick a different hotkey:
          killwindow setup --hotkey 'ctrl+opt+cmd+k'

        """.utf8))
        exit(1)
    }

    var evSpec = EventTypeSpec(
        eventClass: OSType(kEventClassKeyboard),
        eventKind: UInt32(kEventHotKeyPressed))

    let handlerStatus = InstallEventHandler(
        GetApplicationEventTarget(),
        hotKeyHandler,
        1, &evSpec,
        nil,
        &handlerRef)

    if handlerStatus != noErr {
        FileHandle.standardError.write(
            Data("daemon: InstallEventHandler failed (status=\(handlerStatus))\n".utf8))
        exit(1)
    }

    FileHandle.standardError.write(Data(
        "killwindow daemon: hotkey \(formatHotkey(spec)) registered — waiting\n".utf8))
    NSApp.run()
    exit(0)
}
