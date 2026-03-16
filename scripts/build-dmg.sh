#!/bin/bash
set -euo pipefail

# ─── Config ───────────────────────────────────────────────────────────
APP_NAME="CamNDI"
SCHEME="CamNDI"
CONFIG="Release"
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="$PROJECT_DIR/CamNDI.xcodeproj"
BUILD_DIR="$PROJECT_DIR/build"
DMG_DIR="$BUILD_DIR/dmg"
APP_PATH="$BUILD_DIR/$APP_NAME.app"
DMG_PATH="$BUILD_DIR/$APP_NAME.dmg"
VERSION=$(/usr/libexec/PlistBuddy -c "Print :MARKETING_VERSION" "$PROJECT/project.pbxproj" 2>/dev/null || echo "1.0")

# ─── Preflight ────────────────────────────────────────────────────────
if [ ! -f "$PROJECT_DIR/NDI/libndi.dylib" ]; then
    echo "ERROR: NDI SDK not found at NDI/libndi.dylib"
    echo "Install the NDI SDK from https://ndi.video/for-developers/ndi-sdk/"
    echo "then run: cp /Library/NDI\\ SDK\\ for\\ Apple/lib/macOS/libndi.dylib NDI/"
    exit 1
fi

echo "==> Building $APP_NAME $VERSION (Release)..."

# ─── Clean & Build ────────────────────────────────────────────────────
rm -rf "$BUILD_DIR"

xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration "$CONFIG" \
    -derivedDataPath "$BUILD_DIR/DerivedData" \
    SYMROOT="$BUILD_DIR/sym" \
    build \
    2>&1 | tail -5

# Find the built .app
BUILT_APP=$(find "$BUILD_DIR" -name "$APP_NAME.app" -type d | head -1)

if [ -z "$BUILT_APP" ]; then
    echo "ERROR: Build succeeded but $APP_NAME.app not found"
    exit 1
fi

cp -R "$BUILT_APP" "$APP_PATH"
echo "==> App built at $APP_PATH"

# ─── Verify dylib is embedded ────────────────────────────────────────
if [ ! -f "$APP_PATH/Contents/Frameworks/libndi.dylib" ]; then
    echo "ERROR: libndi.dylib not found in app bundle Frameworks/"
    exit 1
fi

echo "==> libndi.dylib embedded OK"

# ─── Create DMG ──────────────────────────────────────────────────────
echo "==> Creating DMG..."

rm -rf "$DMG_DIR"
mkdir -p "$DMG_DIR"
cp -R "$APP_PATH" "$DMG_DIR/"
ln -s /Applications "$DMG_DIR/Applications"

hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$DMG_DIR" \
    -ov \
    -format UDZO \
    "$DMG_PATH"

rm -rf "$DMG_DIR"

DMG_SIZE=$(du -h "$DMG_PATH" | cut -f1 | xargs)
echo ""
echo "==> Done! $DMG_PATH ($DMG_SIZE)"
echo "    Drag CamNDI.app to Applications to install."
