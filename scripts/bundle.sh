#!/bin/bash
# Builds build/Treatly.app.
#
#   scripts/bundle.sh             # this Mac's architecture, ad-hoc signed
#   scripts/bundle.sh --open      # ...and launch it
#   scripts/bundle.sh --universal # Apple Silicon + Intel (used for releases)
#
# Set DEVELOPER_ID (e.g. "Developer ID Application: Name (TEAMID)") to sign
# with hardened runtime for notarization; otherwise it is signed ad hoc.
# The app needs a real bundle (Info.plist) for the Reminders permission prompt.
set -euo pipefail
cd "$(dirname "$0")/.."

OPEN=0
ARCHS=()
for arg in "$@"; do
  case "$arg" in
    --open) OPEN=1 ;;
    --universal) ARCHS=(--arch arm64 --arch x86_64) ;;
    *) echo "unknown option: $arg" >&2; exit 1 ;;
  esac
done

swift build -c release --product Treatly ${ARCHS[@]+"${ARCHS[@]}"}
BIN="$(swift build -c release ${ARCHS[@]+"${ARCHS[@]}"} --show-bin-path)/Treatly"

APP=build/Treatly.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Treatly"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp -R Pets "$APP/Contents/Resources/Pets"
cp -R Resources/Art "$APP/Contents/Resources/Art"

if [[ -n "${DEVELOPER_ID:-}" ]]; then
  codesign --force --options runtime --timestamp --entitlements packaging/Treatly.entitlements --sign "$DEVELOPER_ID" "$APP"
else
  codesign --force --sign - "$APP"
fi

echo "Built $APP ($(lipo -archs "$APP/Contents/MacOS/Treatly"))"
if [[ $OPEN == 1 ]]; then
  pkill -x Treatly 2>/dev/null || true
  open "$APP"
fi
