# killwindow

A macOS [`xkill`](https://linux.die.net/man/1/xkill) equivalent: click a window on your screen to terminate the process that drew it — or, for dialogs and popovers, close just that window without touching the app.

- Default: **SIGTERM** (graceful).
- Hold **⌘** while clicking: **SIGKILL** (force).
- Hold **⌥** while clicking: **AX close** (close just the window, app stays running).
- Live preview: orange highlight + tooltip for SIGTERM/AX-close/Escape, red for SIGKILL, grey for protected owners.
- **Right-click** (or press Esc) to cancel.

## Install

```sh
brew install --cask cristim/tap/killwindow
killwindow setup                     # opens Accessibility pane
killwindow setup --enable-daemon     # optional: global hotkey ⌃⌥⌘K
```

The cask installs `killwindow.app` to `/Applications` (Spotlight-searchable), symlinks the CLI at `/opt/homebrew/bin/killwindow`, and keeps the Accessibility grant stable across upgrades via the bundle ID `com.cristim.killwindow`.

## Requirements

- macOS 11+
- **Accessibility permission** for `killwindow.app`. Grant it in System Settings → Privacy & Security → Accessibility.

## Usage

```sh
killwindow                 # click to terminate; smart action by window type
killwindow -n              # dry-run: print what would happen, don't execute
killwindow -k              # always SIGKILL
killwindow -c              # always AX-close (equivalent to ⌥+click)
killwindow -a              # match any window layer (panels, HUDs, etc.)
killwindow --force-kill-system  # allow SIGKILL on protected system services
killwindow -d              # verbose debug output
killwindow -h              # help
```

## Window classification and default actions

killwindow classifies each window and picks the right action automatically:

| Window type | How detected | Default action |
|---|---|---|
| Normal app window | layer 0, AX subrole = AXStandardWindow | SIGTERM |
| Dialog / sheet | layer 0, AX subrole = AXDialog / AXSystemDialog / role AXSheet | AX close (app stays alive) |
| Known popover service | layer > 0, owner in sacrificial list | SIGKILL (service respawns; SIGTERM is ignored by these daemons) |
| System popover | layer > 0, owner in escape-friendly list | Escape key (dismisses cleanly) |
| Unknown popover | layer > 0, other owner | Escape key (best-effort) |

### Modifier overrides (highest precedence first)

| Modifier | Action |
|---|---|
| ⌘ (or `-k`) | SIGKILL — force kill |
| ⌥ (or `-c`) | AX close — close window only, app stays running |
| none | smart default from classification table |

### Protected-from-SIGKILL owners

The following system services are **refused** when you ⌘+click (or use `-k`), unless you also pass `--force-kill-system`:

- Spotlight, Control Center, NotificationCenter, SystemUIServer
- TextInputMenuAgent, AutoFillPanelService
- Dock (only reachable via `-a` — see below)

These services manage persistent UI state. `--force-kill-system` bypasses the protection:

```sh
killwindow --force-kill-system   # then ⌘+click Control Center to SIGKILL it
```

> **Breaking change from older versions**: ⌘+click on Dock, Control Center, Spotlight, and similar services is now refused by default. Pass `--force-kill-system` to restore the old behaviour.

### Popovers discovered by default

killwindow now discovers popovers from known services (e.g. the Passwords widget from `AutoFillPanelService`, or Control Center panels) without requiring `-a`. The `-a` flag remains available to match every layer regardless of owner.

The Dock is deliberately excluded from auto-discovery: its on-screen surface is a single full-screen input-capture window (not a popover), and including it would make the Dock intercept every click. Use `-a` to reach the Dock window explicitly.

### AX close for dialogs

When you click on a dialog or sheet, killwindow uses the Accessibility API to close just that window. The parent application is unaffected. If AX close fails (e.g. Accessibility permission not granted or the dialog has no close button), the error is reported with exit code 1 — there is no silent fallback to SIGTERM.

Re-click without `-c` / ⌥ to use the default strategy (SIGTERM) if AX close fails.

### Background hotkey daemon

`killwindow daemon` registers a global hotkey (default **⌃⌥⌘K**) that fires a click-to-kill session from anywhere. Manage it via the LaunchAgent helpers:

```sh
killwindow setup --enable-daemon          # install + start LaunchAgent
killwindow setup --disable-daemon         # remove it
```

Log: `/tmp/killwindow.log`.

### Configure the hotkey

```sh
killwindow setup                          # print current hotkey + open Accessibility
killwindow setup --hotkey 'ctrl+opt+cmd+k'
killwindow setup --hotkey 'shift+cmd+f13'
killwindow setup --enable-daemon          # re-bootstrap the agent to apply
```

Config is stored at `~/Library/Application Support/killwindow/config.json`. Modifiers: `ctrl`, `opt`, `cmd`, `shift`. Keys: `a–z`, `0–9`, `f1–f12`, `space`, `return`, `tab`, `delete`, `escape`, arrows.

## Build from source

```sh
git clone https://github.com/cristim/killwindow
cd killwindow
make build            # or: swift build -c release
make install          # copies binary to /usr/local/bin
```

## How it works

- Creates a session-level [`CGEventTap`](https://developer.apple.com/documentation/coregraphics/cgeventtap) that intercepts the next left-click, Esc, and modifier flag changes.
- Uses [`CGWindowListCopyWindowInfo`](https://developer.apple.com/documentation/coregraphics/1454595-cgwindowlistcopywindowinfo) to find the frontmost window whose bounds contain the click, and classifies it by layer and owner.
- At click time, probes the target app's `AXFocusedWindow` subrole to detect dialogs/sheets and upgrade the strategy to AX-close if needed.
- Dispatches one action per click: `kill(pid, SIGTERM/SIGKILL)`, `AXUIElementPerformAction` (close/cancel), or a synthetic Escape key event.
- Floating AppKit tooltip + tint window provide live feedback as the cursor moves, reflecting the action that would fire on click.

## License

MIT — see [`LICENSE`](./LICENSE).
