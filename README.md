# killwindow

A macOS [`xkill`](https://linux.die.net/man/1/xkill) equivalent: click a window on your screen to terminate the process that drew it.

- Default: **SIGTERM** (graceful).
- Hold **⌘** while clicking: **SIGKILL** (force).
- Live preview: orange highlight + tooltip for SIGTERM, red for SIGKILL.
- Press **Esc** to cancel.

## Install

```sh
brew tap cristim/tap
brew install killwindow
```

## Requirements

- macOS 11+
- **Accessibility permission** for the terminal or launcher that starts `killwindow`
  (System Settings → Privacy & Security → Accessibility). Without it, the event tap cannot capture your click.

## Usage

```sh
killwindow                 # click to SIGTERM; ⌘+click to SIGKILL
killwindow -n              # dry-run: identify target, don't kill
killwindow -k              # always SIGKILL (no polite SIGTERM)
killwindow -a              # match any window layer (panels, HUDs, etc.)
killwindow -d              # verbose debug output
killwindow -h              # help
```

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
