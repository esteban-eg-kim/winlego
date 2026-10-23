# Homebrew cask for winlego. Lives in esteban-eg-kim/homebrew-tap as Casks/winlego.rb
# once the project is public. scripts/release.sh prints the version and sha256.
cask "winlego" do
  version "0.1.0"
  sha256 "REPLACE_WITH_SHA256"

  url "https://github.com/esteban-eg-kim/winlego/releases/download/v#{version}/winlego-#{version}.zip"
  name "winlego"
  desc "Snap windows into zones on every display, and keep them there"
  homepage "https://github.com/esteban-eg-kim/winlego"

  depends_on macos: ">= :ventura"

  app "winlego.app"

  # Signed with a local certificate, not notarized: clear the quarantine flag.
  postflight do
    system_command "/usr/bin/xattr",
                   args: ["-dr", "com.apple.quarantine", "#{appdir}/winlego.app"],
                   sudo: false
  end

  uninstall quit: "io.github.esteban-eg-kim.winlego"

  zap trash: [
    "~/Library/Application Support/winlego",
    "~/Library/Preferences/io.github.esteban-eg-kim.winlego.plist",
  ]
end
