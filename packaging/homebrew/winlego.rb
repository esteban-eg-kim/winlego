# Homebrew cask. Put this in the tap repository esteban-eg-kim/homebrew-tap
# (Casks/winlego.rb), then:  brew install --cask esteban-eg-kim/tap/winlego
# scripts/release.sh prints the version and sha256 to paste here. Check with `brew style`.
cask "winlego" do
  version "0.2.1"
  sha256 "dceb336fc4997e2998b49fc663b2f7ea30d9cf03ba9b26b4eed06339a1f76842"

  url "https://github.com/esteban-eg-kim/winlego/releases/download/v#{version}/winlego-#{version}.zip"
  name "winlego"
  desc "Snap windows into zones on every display, and keep them there"
  homepage "https://github.com/esteban-eg-kim/winlego"

  depends_on macos: :ventura

  app "winlego.app"

  # Not notarized (no Apple Developer ID): drop the quarantine flag so Gatekeeper lets it open.
  postflight_steps do
    run "/usr/bin/xattr",
        args:           ["-dr", "com.apple.quarantine", "{{appdir}}/winlego.app"],
        writable_paths: ["{{appdir}}/winlego.app"]
  end

  uninstall quit:       "io.github.esteban-eg-kim.winlego",
            login_item: "winlego"

  zap trash: [
    "~/Library/Application Support/winlego",
    "~/Library/Preferences/io.github.esteban-eg-kim.winlego.plist",
  ]

  caveats <<~EOS
    winlego needs Accessibility access:
      System Settings › Privacy & Security › Accessibility › winlego
      (macOS 27: Privacy & Security › Device Control and Data Access)
    Open winlego once and it walks you through it. Upgrades keep the permission.
  EOS
end
