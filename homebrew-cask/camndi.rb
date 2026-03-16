# Homebrew Cask formula for CamNDI
#
# To use this, create a GitHub repo named "homebrew-camndi" with this file
# at Casks/camndi.rb, then users can install with:
#
#   brew tap manuelvegadev/camndi
#   brew install --cask camndi
#
# Update the url and sha256 each time you create a new release.

cask "camndi" do
  version "1.0.0"
  sha256 "REPLACE_WITH_ACTUAL_SHA256"

  url "https://github.com/manuelvegadev/CamNDI/releases/download/v#{version}/CamNDI.dmg"
  name "CamNDI"
  desc "Menu bar app that broadcasts a USB webcam as an NDI source"
  homepage "https://github.com/manuelvegadev/CamNDI"

  depends_on macos: ">= :sequoia"

  app "CamNDI.app"

  zap trash: [
    "~/Library/Preferences/manuelvegadev.CamNDI.plist",
  ]
end
