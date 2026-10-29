#!/bin/bash
# Builds build/Treatly.app. Pass --open to launch it afterwards.
# The app needs a real bundle (Info.plist) for the Reminders permission prompt.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release --product Treatly

APP=build/Treatly.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$(swift build -c release --show-bin-path)/Treatly" "$APP/Contents/MacOS/Treatly"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp -R Pets "$APP/Contents/Resources/Pets"
cp -R Resources/Art "$APP/Contents/Resources/Art"
codesign --force --sign - "$APP"

echo "Built $APP"
if [[ "${1:-}" == "--open" ]]; then
  pkill -x Treatly 2>/dev/null || true
  open "$APP"
fi
