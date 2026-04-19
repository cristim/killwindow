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

    // CGEventTap needs TWO permissions on modern macOS:
    //   - Accessibility: to consume/modify events (e.g. swallow the click
    //     before it reaches the target app)
    //   - Input Monitoring: to *listen* to key/mouse events globally
    // Both prompt calls are idempotent; they register this binary with
    // their respective TCC lists the first time. Under launchd the
    // "responsible process" is killwindow itself, so this is where the
    // registration actually sticks (from an iTerm-spawned invocation the
    // responsible process is iTerm, which already has its own grants).
    let axOK = requestAccessibilityTrust(prompt: true)
    let imOK = requestInputMonitoring()

    let binary = Bundle.main.executablePath ?? "/opt/homebrew/bin/killwindow"
    if !axOK || !imOK {
        FileHandle.standardError.write(Data("""
        daemon: waiting for permissions. grant killwindow in BOTH:
          System Settings → Privacy & Security → Accessibility       \(axOK ? "✓" : "✗")
          System Settings → Privacy & Security → Input Monitoring    \(imOK ? "✓" : "✗")
        if killwindow isn't listed, click + and add: \(binary)

        """.utf8))
        while !requestAccessibilityTrust(prompt: false) || !inputMonitoringGranted() {
            Thread.sleep(forTimeInterval: 3)
        }
        FileHandle.standardError.write(Data(
            "daemon: permissions granted — registering hotkey\n".utf8))
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
