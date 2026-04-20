import AppKit
import ApplicationServices
import Foundation

// Ask macOS for Accessibility permission — the only permission
// killwindow needs. CGEventTap with .defaultTap is allowed to observe
// and modify events with this grant alone (the Carbon hotkey path
// needs no TCC permission at all). prompt=true registers the current
// binary in the Accessibility list and triggers the system dialog.
@discardableResult
func requestAccessibilityTrust(prompt: Bool) -> Bool {
    let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
    let opts = [key: prompt] as CFDictionary
    return AXIsProcessTrustedWithOptions(opts)
}

func printSetupHelp() {
    print("""
    killwindow setup — grant Accessibility, manage the hotkey daemon

    usage: killwindow setup [options]

    options:
      --hotkey <spec>    set the daemon hotkey (e.g. 'ctrl+opt+cmd+k')
                         modifiers: ctrl, opt, cmd, shift
                         keys: a-z, 0-9, f1-f12, space, return, tab,
                               delete, escape, left, right, up, down, ...
      --enable-daemon    install and start the background LaunchAgent
                         (auto-launches on login; runs the hotkey daemon)
      --disable-daemon   stop and remove the LaunchAgent
      -h, --help         show this help

    with no options, prints the current hotkey and opens
    System Settings → Privacy & Security → Accessibility so you can
    grant killwindow permission to capture your clicks.
    """)
}

func runSetup(args: [String]) -> Never {
    var hotkeyStr: String?
    var enable = false
    var disable = false
    var i = 0
    while i < args.count {
        switch args[i] {
        case "-h", "--help":
            printSetupHelp()
            exit(0)
        case "--hotkey":
            guard i + 1 < args.count else {
                FileHandle.standardError.write(Data("setup: --hotkey requires a value\n".utf8))
                exit(2)
            }
            hotkeyStr = args[i + 1]
            i += 2
            continue
        case "--enable-daemon":
            enable = true
            i += 1
            continue
        case "--disable-daemon":
            disable = true
            i += 1
            continue
        default:
            FileHandle.standardError.write(
                Data("setup: unknown option: \(args[i])\n".utf8))
            exit(2)
        }
    }

    if disable {
        disableDaemon()
        exit(0)
    }
    if enable {
        do { try enableDaemon() } catch {
            FileHandle.standardError.write(Data("setup: \(error)\n".utf8))
            exit(1)
        }
        exit(0)
    }

    if let s = hotkeyStr {
        guard let spec = parseHotkey(s) else {
            FileHandle.standardError.write(
                Data("setup: invalid hotkey: '\(s)'\n".utf8))
            exit(2)
        }
        var cfg = loadConfig()
        cfg.hotkey = formatHotkey(spec)
        do {
            try saveConfig(cfg)
        } catch {
            FileHandle.standardError.write(
                Data("setup: failed to save config: \(error)\n".utf8))
            exit(1)
        }
        print("hotkey saved: \(cfg.hotkey!)")
        print("apply by restarting the daemon: brew services restart killwindow")
        exit(0)
    }

    let current = currentHotkey()

    print("""

    current hotkey: \(formatHotkey(current))
    config file:    \(configPath().path)
    binary:         \(Bundle.main.executablePath ?? "/opt/homebrew/bin/killwindow")

    To enable the background hotkey (\(formatHotkey(current))):

      1. killwindow setup --enable-daemon

         Installs and bootstraps a LaunchAgent at
         ~/Library/LaunchAgents/com.cristim.killwindow.plist.

      2. Open Settings → Privacy & Security → Accessibility and toggle
         killwindow on. That's the only permission we need.

      3. killwindow setup --enable-daemon

         Re-run to re-bootstrap so the daemon picks up the grant, or
         (equivalently) sign out / sign in.

    Disable the daemon:
      killwindow setup --disable-daemon

    Change the hotkey:
      killwindow setup --hotkey 'ctrl+opt+cmd+k'
      brew services restart killwindow
    """)

    let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
    NSWorkspace.shared.open(url)
    exit(0)
}
