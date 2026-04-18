import Foundation

struct Options {
    var dryRun = false
    var debug = false
    var anyLayer = false
    var signal: Int32 = SIGTERM  // graceful by default; ⌘+click upgrades to SIGKILL
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

    options:
      -n, --dry-run    print target and exit without killing
      -k, --kill       send SIGKILL on every click (default is SIGTERM; ⌘+click
                       still upgrades when this flag is off)
      -a, --any-layer  match windows on any layer (default: only layer 0,
                       i.e. normal app windows); useful for stray panels
                       like AutoFillPanelService. Window Server is always
                       excluded.
      -d, --debug      verbose: dump click location and window list
      -v, --version    show version
      -h, --help       show this help

    Accessibility permission is required so killwindow can capture your next
    click. Grant it in System Settings → Privacy & Security → Accessibility.
    Run `killwindow setup` to open that pane directly.
    """)
}

func parseArgs() -> Options {
    var opts = Options()
    for arg in CommandLine.arguments.dropFirst() {
        switch arg {
        case "-n", "--dry-run":   opts.dryRun = true
        case "-k", "--kill":      opts.signal = SIGKILL
        case "-a", "--any-layer": opts.anyLayer = true
        case "-d", "--debug":     opts.debug = true
        case "-v", "--version":   print("killwindow \(killwindowVersion)"); exit(0)
        case "-h", "--help":      printHelp(); exit(0)
        default:
            FileHandle.standardError.write(Data("unknown option: \(arg)\n".utf8))
            exit(2)
        }
    }
    return opts
}
