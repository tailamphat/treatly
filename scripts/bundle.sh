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

# Built-in Google sign-in: the OAuth client JSON downloaded from Google Cloud
# Console (gitignored), or GOOGLE_CLIENT_ID / GOOGLE_CLIENT_SECRET.
CLIENT_JSON=Config/google-oauth-client.json
CLIENT_ID="${GOOGLE_CLIENT_ID:-}"
CLIENT_SECRET="${GOOGLE_CLIENT_SECRET:-}"
if [[ -z "$CLIENT_ID" && -f "$CLIENT_JSON" ]]; then
  CLIENT_ID=$(plutil -extract installed.client_id raw -o - "$CLIENT_JSON")
  CLIENT_SECRET=$(plutil -extract installed.client_secret raw -o - "$CLIENT_JSON")
fi
if [[ -n "$CLIENT_ID" && -n "$CLIENT_SECRET" ]]; then
  plutil -insert TreatlyGoogleClientID -string "$CLIENT_ID" "$APP/Contents/Info.plist"
  plutil -insert TreatlyGoogleClientSecret -string "$CLIENT_SECRET" "$APP/Contents/Info.plist"
  echo "Google sign-in: built in"
else
  echo "Google sign-in: not built in (users bring their own client, see docs/google-tasks.md)"
fi
cp -R Pets "$APP/Contents/Resources/Pets"
cp -R Resources/Art "$APP/Contents/Resources/Art"
codesign --force --sign - "$APP"

echo "Built $APP"
if [[ "${1:-}" == "--open" ]]; then
  pkill -x Treatly 2>/dev/null || true
  open "$APP"
fi
