# Release checklist

Tick these off in order for every release. [releasing.md](releasing.md) explains the commands.

## Before building

- [ ] All work for this release is committed. Anything unfinished stays out of the commit.
- [ ] `swift run TreatlyChecks` passes.
- [ ] Try the dev build (`scripts/bundle.sh && open build/Treatly.app`): the new things work, and settings open without glitches.
- [ ] README and `docs/` describe the new features.
- [ ] **Website updated** (`site/`) for the new features. Preview it locally (`scripts/site.sh && cd build/site && python3 -m http.server 8765`, then open http://localhost:8765).
- [ ] **Owner approves the website and the release notes before anything is published.**

## Build

- [ ] Bump `CFBundleShortVersionString` and `CFBundleVersion` in `Resources/Info.plist` and commit.
- [ ] Build from a clean checkout so uncommitted work stays out of the zip:

  ```sh
  git worktree add ../treatly-release HEAD
  cd ../treatly-release && scripts/release.sh
  ```

- [ ] The zip has the new version, both architectures (`lipo -archs`), every pet and `Sparkle.framework`.
- [ ] `appcast.xml` got the new version (copy it back from the release checkout, don't commit it yet).
- [ ] Copy `packaging/homebrew/treatly.rb` back and commit it ("Release x.y.z: cask checksum").
- [ ] Tag the commit the zip was built from: `git tag vX.Y.Z <commit>`.

## Publish

- [ ] Push `main` and the tag: `git push origin main vX.Y.Z`.
- [ ] Create the GitHub release with the zip and the release notes:

  ```sh
  gh release create vX.Y.Z build/Treatly-X.Y.Z.zip --title "Treatly X.Y.Z" --notes-file build/release-notes-X.Y.Z.md
  ```

- [ ] Only after the zip is downloadable: commit and push `appcast.xml` to `main`, so installed apps find the update.
- [ ] Copy the cask to `Casks/treatly.rb` in **tailamphat/homebrew-tap**, commit and push.
- [ ] The website deploy (Actions > "Deploy site") finished green.

## Verify

- [ ] The download link works and its sha256 matches the cask.
- [ ] `brew update && brew upgrade --cask treatly` installs the new version (`brew info --cask treatly`).
- [ ] The installed app launches and shows the new version in About.
- [ ] https://raw.githubusercontent.com/tailamphat/treatly/main/appcast.xml lists the new version, and "Check for Updates…" in an older install finds it.
- [ ] The live website shows the new content: https://tailamphat.github.io/treatly/
