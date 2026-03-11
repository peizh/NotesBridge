#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_CONFIG="debug"
BUILD_ONLY=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --release)
            BUILD_CONFIG="release"
            ;;
        --build-only)
            BUILD_ONLY=1
            ;;
        *)
            echo "Unknown option: $1" >&2
            echo "Usage: $0 [--release] [--build-only]" >&2
            exit 1
            ;;
    esac
    shift
done

EXECUTABLE_PATH="$ROOT_DIR/.build/$BUILD_CONFIG/NotesBridge"
APP_SUPPORT_DIR="$HOME/Library/Application Support/NotesBridge"
APP_BUNDLE_PATH="$APP_SUPPORT_DIR/NotesBridge.app"
CONTENTS_PATH="$APP_BUNDLE_PATH/Contents"
MACOS_PATH="$CONTENTS_PATH/MacOS"
INFO_PLIST_PATH="$CONTENTS_PATH/Info.plist"
BUNDLE_IDENTIFIER="dev.notesbridge.app"
DESIGNATED_REQUIREMENT='=designated => identifier "dev.notesbridge.app"'

echo "Building NotesBridge ($BUILD_CONFIG)..."
swift build --package-path "$ROOT_DIR" -c "$BUILD_CONFIG"

if [[ ! -x "$EXECUTABLE_PATH" ]]; then
    echo "Expected executable was not produced at $EXECUTABLE_PATH" >&2
    exit 1
fi

echo "Packaging app bundle at $APP_BUNDLE_PATH..."
rm -rf "$APP_BUNDLE_PATH"
mkdir -p "$MACOS_PATH"
cp "$EXECUTABLE_PATH" "$MACOS_PATH/NotesBridge"

cat > "$INFO_PLIST_PATH" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>NotesBridge</string>
    <key>CFBundleIdentifier</key>
    <string>dev.notesbridge.app</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>NotesBridge</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
PLIST

codesign \
    --force \
    --sign - \
    --identifier "$BUNDLE_IDENTIFIER" \
    --requirements "$DESIGNATED_REQUIREMENT" \
    --deep \
    "$APP_BUNDLE_PATH" >/dev/null

echo "Bundled app ready:"
echo "  $APP_BUNDLE_PATH"
echo "Note: bundled builds now use a stable designated requirement for TCC. If you previously granted an older build, remove and re-add NotesBridge once in Accessibility."

if [[ "$BUILD_ONLY" -eq 1 ]]; then
    exit 0
fi

echo "Launching bundled app..."
open -n "$APP_BUNDLE_PATH"
