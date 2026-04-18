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

    // Under launchd the "responsible process" is this binary (not the
    // terminal that ran `brew services start`). Calling AX with prompt
    // here is what actually registers /opt/homebrew/bin/killwindow with
    // System Settings → Accessibility so the user can toggle it on.
    let trusted = requestAccessibilityTrust(prompt: true)
    if !trusted {
        FileHandle.standardError.write(Data("""
        daemon: Accessibility permission not yet granted.
        killwindow has been added to System Settings → Privacy & Security →
        Accessibility. Toggle it on, then: brew services restart killwindow

        """.utf8))
        exit(1)
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
