cask "treatly" do
  version "0.1.4"
  sha256 "52bba99ab7d7318cb742092a49b21d9b51060d0ca9af35f62caf9cd115a1d6b9"

  url "https://github.com/tailamphat/treatly/releases/download/v#{version}/Treatly-#{version}.zip"
  name "Treatly"
  desc "Desktop pet that turns your reminders into treats and nags you to finish them"
  homepage "https://github.com/tailamphat/treatly"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: :sonoma

  app "Treatly.app"

  # `brew upgrade` backs up the old app first and stops if it's gone (moved to
  # the Trash, or removed by security software). An empty stand-in lets the
  # upgrade or uninstall carry on and put the new app in its place.
  uninstall_preflight do
    app = "#{appdir}/Treatly.app"
    FileUtils.mkdir_p(app) unless File.exist?(app)
  end

  zap trash: [
    "~/Library/Application Support/Treatly",
    "~/Library/Preferences/io.github.treatly.Treatly.plist",
  ]

  # Until releases are signed with a Developer ID and notarized.
  caveats <<~EOS
    Treatly is not notarized yet. The first time you open it, macOS may say
    it can't verify the app. Open System Settings > Privacy & Security and
    click "Open Anyway" next to Treatly.
  EOS
end
