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
BIN_DIR="$(swift build -c release ${ARCHS[@]+"${ARCHS[@]}"} --show-bin-path)"
BIN="$BIN_DIR/Treatly"

APP=build/Treatly.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$BIN" "$APP/Contents/MacOS/Treatly"
# Sparkle (in-app updates) is a framework the app loads from Contents/Frameworks.
ditto "$BIN_DIR/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"
install_name_tool -add_rpath @executable_path/../Frameworks "$APP/Contents/MacOS/Treatly"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp -R Pets "$APP/Contents/Resources/Pets"
cp -R Resources/Art "$APP/Contents/Resources/Art"

# Sign inside out: Sparkle's helpers, then the framework, then the app.
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"
if [[ -n "${DEVELOPER_ID:-}" ]]; then
  SIGN=(codesign --force --options runtime --timestamp --sign "$DEVELOPER_ID")
else
  SIGN=(codesign --force --sign -)
fi
"${SIGN[@]}" "$SPARKLE/XPCServices/Installer.xpc"
"${SIGN[@]}" --preserve-metadata=entitlements "$SPARKLE/XPCServices/Downloader.xpc"
"${SIGN[@]}" "$SPARKLE/Autoupdate"
"${SIGN[@]}" "$SPARKLE/Updater.app"
"${SIGN[@]}" "$APP/Contents/Frameworks/Sparkle.framework"
if [[ -n "${DEVELOPER_ID:-}" ]]; then
  "${SIGN[@]}" --entitlements packaging/Treatly.entitlements "$APP"
else
  "${SIGN[@]}" "$APP"
fi

echo "Built $APP ($(lipo -archs "$APP/Contents/MacOS/Treatly"))"
if [[ $OPEN == 1 ]]; then
  pkill -x Treatly 2>/dev/null || true
  open "$APP"
fi
