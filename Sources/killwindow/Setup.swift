import AppKit
import Foundation

func printSetupHelp() {
    print("""
    killwindow setup — grant Accessibility and configure the hotkey

    usage: killwindow setup [options]

    options:
      --hotkey <spec>   set the daemon hotkey (e.g. 'ctrl+opt+cmd+k')
                        modifiers: ctrl, opt, cmd, shift
                        keys: a-z, 0-9, f1-f12, space, return, tab,
                              delete, escape, left, right, up, down, ...
      -h, --help        show this help

    with no options, prints the current hotkey and opens
    System Settings → Privacy & Security → Accessibility so you can
    grant killwindow permission to capture your clicks.
    """)
}

func runSetup(args: [String]) -> Never {
    var hotkeyStr: String?
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
        default:
            FileHandle.standardError.write(
                Data("setup: unknown option: \(args[i])\n".utf8))
            exit(2)
        }
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

    change the hotkey:
      killwindow setup --hotkey 'ctrl+opt+cmd+k'
      brew services restart killwindow

    start the background hotkey daemon:
      brew services start killwindow

    Accessibility permission: killwindow needs this to capture your click.
    Opening System Settings → Privacy & Security → Accessibility for you now.
    Add this binary to the list and toggle it on:
      \(Bundle.main.executablePath ?? "/opt/homebrew/bin/killwindow")
    """)

    let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
    NSWorkspace.shared.open(url)
    exit(0)
}
