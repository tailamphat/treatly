cask "treatly" do
  version "0.1.0"
  sha256 "86dc3b83f0d28827a8188b0aadccf4606a8e556cc4cac195d3a3504a2ebae635"

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
