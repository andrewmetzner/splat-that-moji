#!/bin/bash
# Builds "build/Splat That Moji.app".
#
#   scripts/build_app.sh            # release build, signed
#   scripts/build_app.sh --install  # ...and copy it to /Applications
#
# Signs with your first "Apple Development" / "Developer ID Application" identity when there is
# one (so macOS keeps the Accessibility permission across rebuilds), otherwise ad hoc.
# Override with SIGN_IDENTITY="..." (use "-" for ad hoc).
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/Splat That Moji.app"

swift build -c release --product SplatThatMoji
BIN="$(swift build -c release --show-bin-path)/SplatThatMoji"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/SplatThatMoji"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/kaomoji.tsv Resources/kaomoji-meta.json Resources/AppIcon.icns "$APP/Contents/Resources/"

IDENTITY="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null \
    | awk -F'"' '/Apple Development|Developer ID Application/ { print $2; exit }')}"
IDENTITY="${IDENTITY:--}"
codesign --force --options runtime --timestamp=none --sign "$IDENTITY" "$APP"
echo "Built $APP (signed: $IDENTITY)"

if [[ "${1:-}" == "--install" ]]; then
    pkill -x SplatThatMoji 2>/dev/null || true
    rm -rf "/Applications/Splat That Moji.app"
    cp -R "$APP" /Applications/
    echo "Installed to /Applications/Splat That Moji.app"
    open "/Applications/Splat That Moji.app"
fi
