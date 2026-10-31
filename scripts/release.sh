#!/bin/bash
# Builds a release zip for GitHub Releases and fills in the Homebrew cask.
#
#   scripts/release.sh
#
# The version comes from Resources/Info.plist (CFBundleShortVersionString).
# Optional, for a notarized build that opens without Gatekeeper warnings:
#   DEVELOPER_ID   "Developer ID Application: Name (TEAMID)"
#   NOTARY_PROFILE a keychain profile from `xcrun notarytool store-credentials`
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=$(plutil -extract CFBundleShortVersionString raw Resources/Info.plist)
ZIP="build/Treatly-$VERSION.zip"

swift run TreatlyChecks
scripts/bundle.sh --universal

rm -f "$ZIP"
ditto -c -k --keepParent build/Treatly.app "$ZIP"

if [[ -n "${NOTARY_PROFILE:-}" ]]; then
  [[ -n "${DEVELOPER_ID:-}" ]] || { echo "NOTARY_PROFILE needs DEVELOPER_ID" >&2; exit 1; }
  xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple build/Treatly.app
  rm -f "$ZIP"
  ditto -c -k --keepParent build/Treatly.app "$ZIP"
  NOTARIZED=yes
else
  NOTARIZED=no
fi

# Sparkle appcast: signs the zip with the EdDSA key in the login Keychain
# (from generate_keys) and adds this version to appcast.xml, keeping older ones.
STAGE=build/appcast
rm -rf "$STAGE" && mkdir -p "$STAGE"
cp "$ZIP" "$STAGE/"
[[ -f appcast.xml ]] && cp appcast.xml "$STAGE/appcast.xml"
.build/artifacts/sparkle/Sparkle/bin/generate_appcast \
  --download-url-prefix "https://github.com/tailamphat/treatly/releases/download/v$VERSION/" \
  --link https://github.com/tailamphat/treatly "$STAGE"
cp "$STAGE/appcast.xml" appcast.xml

SHA=$(shasum -a 256 "$ZIP" | cut -d' ' -f1)
sed -e "s/^  version \".*\"/  version \"$VERSION\"/" -e "s/^  sha256 \".*\"/  sha256 \"$SHA\"/" \
  packaging/homebrew/treatly.rb > build/treatly.rb
mv build/treatly.rb packaging/homebrew/treatly.rb

cat <<DONE

Release $VERSION
  zip:        $ZIP
  sha256:     $SHA
  notarized:  $NOTARIZED
  cask:       packaging/homebrew/treatly.rb (version and sha256 updated)
  appcast:    appcast.xml (new version added)

Next (see docs/releasing.md):
  git tag v$VERSION && git push origin v$VERSION
  upload $ZIP to the v$VERSION GitHub release
  commit and push appcast.xml to main (installed apps update from it)
  copy packaging/homebrew/treatly.rb to Casks/treatly.rb in tailamphat/homebrew-tap
DONE
