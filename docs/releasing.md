# Releasing

Treatly ships as a zipped universal app on GitHub Releases, installed with a Homebrew cask from a tap.

## One-time setup

1. Create a public GitHub repo **tailamphat/homebrew-tap** with a `Casks/` folder.
2. Optional but recommended: a paid Apple Developer account. Create a "Developer ID Application" certificate in Xcode or the developer portal, then store notarization credentials once:

   ```sh
   xcrun notarytool store-credentials treatly-notary --apple-id you@example.com --team-id TEAMID
   ```

   Without this, releases are signed ad hoc and users click **Open Anyway** once (the cask says so).

## Each release

1. Bump `CFBundleShortVersionString` (and `CFBundleVersion`) in `Resources/Info.plist` and commit.
2. Build the release:

   ```sh
   scripts/release.sh
   # or, signed and notarized:
   DEVELOPER_ID="Developer ID Application: Your Name (TEAMID)" NOTARY_PROFILE=treatly-notary scripts/release.sh
   ```

   It runs the checks, builds a universal (Apple Silicon + Intel) app, writes `build/Treatly-<version>.zip`, and puts the version and sha256 into `packaging/homebrew/treatly.rb`.
3. Tag and publish:

   ```sh
   git tag v0.1.0 && git push origin main v0.1.0
   gh release create v0.1.0 build/Treatly-0.1.0.zip --title "Treatly 0.1.0" --notes "First release: Apple Reminders."
   ```

   (Or create the release on github.com and upload the zip.)
4. Copy `packaging/homebrew/treatly.rb` to `Casks/treatly.rb` in **tailamphat/homebrew-tap** and push. Once notarized, delete the `caveats` block.
5. Check it:

   ```sh
   brew update && brew install --cask tailamphat/tap/treatly
   brew audit --cask --strict tailamphat/tap/treatly
   ```

## The official homebrew/cask repo

Later, the cask can go to [Homebrew/homebrew-cask](https://github.com/Homebrew/homebrew-cask) instead of a tap. It requires a notarized app and a reasonably popular repo (stars, forks, watchers); unsigned apps are not accepted. Until then the tap works the same for users, with one extra word in the install command.
