# killwindow

A macOS [`xkill`](https://linux.die.net/man/1/xkill) equivalent: click a window on your screen to terminate the process that drew it.

- Default: **SIGTERM** (graceful).
- Hold **⌘** while clicking: **SIGKILL** (force).
- Live preview: orange highlight + tooltip for SIGTERM, red for SIGKILL.
- **Right-click** (or press Esc) to cancel.

## Install

```sh
brew tap cristim/tap
brew install killwindow
killwindow setup          # opens Accessibility pane, shows/sets hotkey
```

## Requirements

- macOS 11+
- **Accessibility permission** for the `killwindow` binary (and for the terminal that launches it, if you run it from a shell). Without it, the event tap cannot capture your click.

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

`killwindow daemon` registers a global hotkey (default **⌃⌥⌘K**) that fires a click-to-kill session from anywhere. Manage it with `brew services`:

```sh
brew services start killwindow            # start at login, running now
brew services stop killwindow
brew services restart killwindow          # after changing the hotkey
```

### Configure the hotkey

```sh
killwindow setup                          # print current hotkey + open Accessibility
killwindow setup --hotkey 'ctrl+opt+cmd+k'
killwindow setup --hotkey 'shift+cmd+f13'
brew services restart killwindow          # apply
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
