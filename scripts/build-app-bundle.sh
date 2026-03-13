#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

BUILD_CONFIG="release"
OUTPUT_DIR="$ROOT_DIR/dist"
APP_NAME="NotesBridge"
BUNDLE_ID="dev.notesbridge.app"
VERSION="1.0.0"
BUILD_NUMBER="1"
SIGN_IDENTITY="-"
TEAM_ID=""
LAUNCH_AFTER_BUILD=0

usage() {
    cat <<EOF
Usage: $0 [options]

Options:
  --debug                 Build a debug bundle instead of release
  --output-dir PATH       Output directory for the bundle (default: ./dist)
  --app-name NAME         App bundle name (default: NotesBridge)
  --bundle-id ID          CFBundleIdentifier (default: dev.notesbridge.app)
  --version VERSION       CFBundleShortVersionString (default: 1.0.0)
  --build-number NUMBER   CFBundleVersion (default: 1)
  --sign-identity NAME    codesign identity (default: ad-hoc "-")
  --team-id TEAM          Optional TeamIdentifier for Info.plist
  --launch                Open the built app after packaging
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --debug)
            BUILD_CONFIG="debug"
            ;;
        --output-dir)
            OUTPUT_DIR="$2"
            shift
            ;;
        --app-name)
            APP_NAME="$2"
            shift
            ;;
        --bundle-id)
            BUNDLE_ID="$2"
            shift
            ;;
        --version)
            VERSION="$2"
            shift
            ;;
        --build-number)
            BUILD_NUMBER="$2"
            shift
            ;;
        --sign-identity)
            SIGN_IDENTITY="$2"
            shift
            ;;
        --team-id)
            TEAM_ID="$2"
            shift
            ;;
        --launch)
            LAUNCH_AFTER_BUILD=1
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage >&2
            exit 1
            ;;
    esac
    shift
done

EXECUTABLE_PATH="$ROOT_DIR/.build/$BUILD_CONFIG/NotesBridge"
APP_BUNDLE_PATH="$OUTPUT_DIR/$APP_NAME.app"
CONTENTS_PATH="$APP_BUNDLE_PATH/Contents"
MACOS_PATH="$CONTENTS_PATH/MacOS"
INFO_PLIST_PATH="$CONTENTS_PATH/Info.plist"
DESIGNATED_REQUIREMENT="=designated => identifier \"$BUNDLE_ID\""

echo "Building NotesBridge ($BUILD_CONFIG)..."
swift build --package-path "$ROOT_DIR" -c "$BUILD_CONFIG"

if [[ ! -x "$EXECUTABLE_PATH" ]]; then
    echo "Expected executable was not produced at $EXECUTABLE_PATH" >&2
    exit 1
fi

echo "Packaging app bundle at $APP_BUNDLE_PATH..."
rm -rf "$APP_BUNDLE_PATH"
mkdir -p "$MACOS_PATH"
cp "$EXECUTABLE_PATH" "$MACOS_PATH/$APP_NAME"

cat > "$INFO_PLIST_PATH" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>$BUILD_NUMBER</string>
    <key>LSUIElement</key>
    <true/>
$(if [[ -n "$TEAM_ID" ]]; then cat <<TEAM
    <key>TeamIdentifier</key>
    <string>$TEAM_ID</string>
TEAM
fi)
</dict>
</plist>
PLIST

codesign \
    --force \
    --sign "$SIGN_IDENTITY" \
    --identifier "$BUNDLE_ID" \
    --requirements "$DESIGNATED_REQUIREMENT" \
    --deep \
    "$APP_BUNDLE_PATH" >/dev/null

echo "App bundle ready:"
echo "  $APP_BUNDLE_PATH"
echo "  version=$VERSION"
echo "  build=$BUILD_NUMBER"
echo "  bundle_id=$BUNDLE_ID"
echo "  codesign_identity=$SIGN_IDENTITY"

if [[ "$LAUNCH_AFTER_BUILD" -eq 1 ]]; then
    open -n "$APP_BUNDLE_PATH"
fi
