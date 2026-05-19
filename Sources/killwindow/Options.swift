import Foundation

struct Options {
    var dryRun = false
    var debug = false
    var anyLayer = false
    var signal: Int32 = SIGTERM  // graceful by default; ⌘+click upgrades to SIGKILL
    var closeWindow = false      // -c/--close-window: always AX-close
    var forceKillSystem = false  // --force-kill-system: bypass protected-from-SIGKILL list
}

func signalName(_ s: Int32) -> String {
    switch s {
    case SIGTERM: return "SIGTERM"
    case SIGKILL: return "SIGKILL"
    default:      return "signal \(s)"
    }
}

func printHelp() {
    print("""
    killwindow — click a window to kill its owning process

    usage: killwindow [options]
           killwindow daemon              run as a background hotkey daemon
           killwindow setup [options]     grant Accessibility, configure hotkey

    default signal is SIGTERM (graceful). Hold ⌘ while clicking to force SIGKILL.
    Hold ⌥ while clicking to AX-close the window only (app stays running).

    options:
      -n, --dry-run          print target and action, exit without executing
      -k, --kill             send SIGKILL on every click (default is SIGTERM; ⌘+click
                             still upgrades when this flag is off)
      -c, --close-window     AX-close the window rather than killing the process
                             (equivalent to ⌥+click; if AX close fails, reports
                             closeFailed with exit code 1 — no silent SIGTERM fallback)
      -a, --any-layer        match windows on any layer (default: only layer 0 and
                             known popover owners); useful for debugging unknown panels
      --force-kill-system    bypass the protected-from-SIGKILL list (allows SIGKILL
                             on Dock, Control Center, Spotlight, etc.)
      -d, --debug            verbose: dump click location and window list
      -v, --version          show version
      -h, --help             show this help

    window classification and default actions:
      normal window          SIGTERM (graceful quit)
      AX dialog / sheet      AX close (dialog dismissed, app stays alive)
      known popover service  SIGKILL (service respawns; SIGTERM is ignored
                             by AutoFillPanelService and similar daemons)
      system popover         Escape key (dismisses without killing the process)
      unknown popover        Escape key (best-effort)

    auto-discovered popover owners (matched on layers > 0 without -a):
      Spotlight, Control Center, NotificationCenter, SystemUIServer,
      TextInputMenuAgent, AutoFillPanelService

    protected-from-SIGKILL owners (SIGKILL refused unless --force-kill-system):
      the above + Dock (Dock's input-capture surface spans the screen, so
      it's not auto-discovered, but is still gated from accidental SIGKILL
      when reached via -a).

    Accessibility permission is required so killwindow can capture your next
    click. Grant it in System Settings → Privacy & Security → Accessibility.
    Run `killwindow setup` to open that pane directly.
    """)
}

func parseArgs() -> Options {
    var opts = Options()
    for arg in CommandLine.arguments.dropFirst() {
        switch arg {
        case "-n", "--dry-run":        opts.dryRun = true
        case "-k", "--kill":           opts.signal = SIGKILL
        case "-c", "--close-window":   opts.closeWindow = true
        case "-a", "--any-layer":      opts.anyLayer = true
        case "--force-kill-system":    opts.forceKillSystem = true
        case "-d", "--debug":          opts.debug = true
        case "-v", "--version":        print("killwindow \(killwindowVersion)"); exit(0)
        case "-h", "--help":           printHelp(); exit(0)
        default:
            // Finder-launched .apps sometimes receive a legacy
            // `-psn_0_1234` argument (Process Serial Number). Ignore it.
            if arg.hasPrefix("-psn_") { continue }
            FileHandle.standardError.write(Data("unknown option: \(arg)\n".utf8))
            exit(2)
        }
    }
    return opts
}
