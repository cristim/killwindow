#!/usr/bin/env bash
# Wrap the release binary in a signed .app bundle so macOS TCC tracks
# Accessibility / Input Monitoring grants by CFBundleIdentifier instead
# of by binary path (the latter changes on every brew upgrade).
#
# Requires a prior `swift build -c release`.

set -euo pipefail

OUT_DIR="${1:-build}"
APP_NAME="killwindow"
APP="${OUT_DIR}/${APP_NAME}.app"
BIN=".build/release/${APP_NAME}"
PLIST_TEMPLATE="Resources/Info.plist.template"

if [ ! -f "$BIN" ]; then
    echo "error: $BIN missing — run 'swift build -c release' first" >&2
    exit 1
fi
if [ ! -f "$PLIST_TEMPLATE" ]; then
    echo "error: $PLIST_TEMPLATE missing" >&2
    exit 1
fi

VERSION=$(
    sed -nE 's/.*killwindowVersion = "([^"]+)".*/\1/p' \
        Sources/killwindow/Version.swift
)
if [ -z "$VERSION" ]; then
    echo "error: could not read version from Sources/killwindow/Version.swift" >&2
    exit 1
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN" "$APP/Contents/MacOS/$APP_NAME"
sed "s/__VERSION__/${VERSION}/g" "$PLIST_TEMPLATE" > "$APP/Contents/Info.plist"

# Ad-hoc signature — TCC tracks by bundle ID on signed bundles regardless
# of disk location, so the Accessibility grant survives upgrades.
codesign --force --deep --sign - "$APP" >/dev/null

echo "built $APP (version $VERSION)"
