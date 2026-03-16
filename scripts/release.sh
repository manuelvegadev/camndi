#!/bin/bash
set -euo pipefail

# Creates a GitHub release with the DMG and prints the Homebrew Cask update.
#
# Usage:
#   ./scripts/release.sh 1.0.0
#
# Prerequisites:
#   - gh CLI authenticated (brew install gh && gh auth login)
#   - DMG built (./scripts/build-dmg.sh)

VERSION="${1:?Usage: $0 <version>}"
TAG="v$VERSION"
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DMG_PATH="$PROJECT_DIR/build/CamNDI.dmg"

if [ ! -f "$DMG_PATH" ]; then
    echo "DMG not found. Building..."
    "$PROJECT_DIR/scripts/build-dmg.sh"
fi

echo "==> Creating release $TAG..."

# Create git tag
git tag -a "$TAG" -m "CamNDI $VERSION"
git push origin "$TAG"

# Create GitHub release with DMG
gh release create "$TAG" "$DMG_PATH" \
    --title "CamNDI $VERSION" \
    --generate-notes

# Calculate SHA256 for Homebrew
SHA=$(shasum -a 256 "$DMG_PATH" | awk '{print $1}')

echo ""
echo "==> Release created: $TAG"
echo ""
echo "==> Update your Homebrew tap (homebrew-camndi/Casks/camndi.rb):"
echo "    version \"$VERSION\""
echo "    sha256 \"$SHA\""
echo ""
echo "==> Users can then install with:"
echo "    brew tap manuelvegadev/camndi"
echo "    brew install --cask camndi"
