#!/bin/zsh
# Builds d4vAgentBar.app (release, ad-hoc signed) in ./build.
# Usage: ./build-app.sh [--install|--release]
#   --install  copies it to /Applications and launches it
#   --release  universal build (Apple Silicon + Intel) zipped as build/d4vAgentBar-<version>.zip
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="d4vAgentBar"
BUNDLE_ID="com.github.dcourtin.d4vagentbar"
VERSION="0.1.0"

MODE="${1:-}"
BUILD_ARGS=(-c release)
[[ "$MODE" == "--release" ]] && BUILD_ARGS+=(--arch arm64 --arch x86_64)

swift build "${BUILD_ARGS[@]}"
BIN="$(swift build "${BUILD_ARGS[@]}" --show-bin-path)/D4vAgentBar"

APP="build/$APP_NAME.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/$APP_NAME"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>$APP_NAME</string>
    <key>CFBundleDisplayName</key><string>$APP_NAME</string>
    <key>CFBundleExecutable</key><string>$APP_NAME</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP"
echo "Built $APP"

if [[ "$MODE" == "--release" ]]; then
    ZIP="build/$APP_NAME-$VERSION.zip"
    rm -f "$ZIP"
    ditto -c -k --keepParent "$APP" "$ZIP"
    echo "Packaged $ZIP"
fi

if [[ "$MODE" == "--install" ]]; then
    pkill -x "$APP_NAME" 2>/dev/null || true
    rm -rf "/Applications/$APP_NAME.app"
    cp -R "$APP" /Applications/
    open "/Applications/$APP_NAME.app"
    echo "Installed to /Applications and launched"
fi
