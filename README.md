# killwindow

A macOS [`xkill`](https://linux.die.net/man/1/xkill) equivalent: click a window on your screen to terminate the process that drew it.

- Default: **SIGTERM** (graceful).
- Hold **⌘** while clicking: **SIGKILL** (force).
- Live preview: orange highlight + tooltip for SIGTERM, red for SIGKILL.
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
killwindow                 # click to SIGTERM; ⌘+click to SIGKILL
killwindow -n              # dry-run: identify target, don't kill
killwindow -k              # always SIGKILL (no polite SIGTERM)
killwindow -a              # match any window layer (panels, HUDs, etc.)
killwindow -d              # verbose debug output
killwindow -h              # help
```

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

- Creates a session-level [`CGEventTap`](https://developer.apple.com/documentation/coregraphics/cgeventtap) that intercepts the next left-click, Esc, and ⌘ flag changes.
- Uses [`CGWindowListCopyWindowInfo`](https://developer.apple.com/documentation/coregraphics/1454595-cgwindowlistcopywindowinfo) to find the frontmost window whose bounds contain the click.
- Floating AppKit tooltip + tint window provide live feedback as the cursor moves.
- `kill(pid, SIGTERM)` or `kill(pid, SIGKILL)` ends the process.

## License

MIT — see [`LICENSE`](./LICENSE).
