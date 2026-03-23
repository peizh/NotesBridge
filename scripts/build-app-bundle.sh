#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

BUILD_CONFIG="release"
OUTPUT_DIR="$ROOT_DIR/dist"
APP_NAME="NotesBridge"
BUNDLE_ID="dev.notesbridge.app"
VERSION="0.2.3"
BUILD_NUMBER="1"
SIGN_IDENTITY="-"
TEAM_ID=""
LAUNCH_AFTER_BUILD=0
SPARKLE_FEED_URL="${NOTESBRIDGE_SPARKLE_FEED_URL:-https://peizh.github.io/NoteBridge/updates/appcast.xml}"
SPARKLE_PUBLIC_ED_KEY="${NOTESBRIDGE_SPARKLE_PUBLIC_ED_KEY:-0Gcbr/JsQLrUXt36na4JMUNt7S9/+GIVr3fNSE8q1F4=}"

usage() {
    cat <<EOF
Usage: $0 [options]

Options:
  --debug                 Build a debug bundle instead of release
  --output-dir PATH       Output directory for the bundle (default: ./dist)
  --app-name NAME         App bundle name (default: NotesBridge)
  --bundle-id ID          CFBundleIdentifier (default: dev.notesbridge.app)
  --version VERSION       CFBundleShortVersionString (default: 0.2.3)
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

BUILD_BIN_PATH=""
EXECUTABLE_PATH=""
SPARKLE_FRAMEWORK_SOURCE=""
APP_BUNDLE_PATH="$OUTPUT_DIR/$APP_NAME.app"
CONTENTS_PATH="$APP_BUNDLE_PATH/Contents"
MACOS_PATH="$CONTENTS_PATH/MacOS"
RESOURCES_PATH="$CONTENTS_PATH/Resources"
FRAMEWORKS_PATH="$CONTENTS_PATH/Frameworks"
INFO_PLIST_PATH="$CONTENTS_PATH/Info.plist"
DESIGNATED_REQUIREMENT="=designated => identifier \"$BUNDLE_ID\""
ICON_SOURCE_PATH="$ROOT_DIR/images/notesbridge-app-icon.svg"
ICONSET_PATH="$OUTPUT_DIR/$APP_NAME.iconset"
ICON_NAME="$APP_NAME"

build_app_icon() {
    if [[ ! -f "$ICON_SOURCE_PATH" ]]; then
        echo "App icon source not found at $ICON_SOURCE_PATH" >&2
        exit 1
    fi

    rm -rf "$ICONSET_PATH"
    mkdir -p "$ICONSET_PATH"

    local rendered_dir
    rendered_dir="$(mktemp -d)"
    qlmanage -t -s 1024 -o "$rendered_dir" "$ICON_SOURCE_PATH" >/dev/null 2>&1

    local base_png="$rendered_dir/$(basename "$ICON_SOURCE_PATH").png"
    if [[ ! -f "$base_png" ]]; then
        echo "Failed to render app icon preview from $ICON_SOURCE_PATH" >&2
        rm -rf "$rendered_dir"
        exit 1
    fi

    cp "$base_png" "$ICONSET_PATH/icon_512x512@2x.png"
    sips -z 512 512 "$base_png" --out "$ICONSET_PATH/icon_512x512.png" >/dev/null
    sips -z 256 256 "$base_png" --out "$ICONSET_PATH/icon_256x256.png" >/dev/null
    cp "$ICONSET_PATH/icon_512x512.png" "$ICONSET_PATH/icon_256x256@2x.png"
    sips -z 128 128 "$base_png" --out "$ICONSET_PATH/icon_128x128.png" >/dev/null
    cp "$ICONSET_PATH/icon_256x256.png" "$ICONSET_PATH/icon_128x128@2x.png"
    sips -z 64 64 "$base_png" --out "$ICONSET_PATH/icon_64x64.png" >/dev/null
    sips -z 32 32 "$base_png" --out "$ICONSET_PATH/icon_32x32.png" >/dev/null
    cp "$ICONSET_PATH/icon_64x64.png" "$ICONSET_PATH/icon_32x32@2x.png"
    sips -z 16 16 "$base_png" --out "$ICONSET_PATH/icon_16x16.png" >/dev/null
    sips -z 32 32 "$base_png" --out "$ICONSET_PATH/icon_16x16@2x.png" >/dev/null

    iconutil -c icns "$ICONSET_PATH" -o "$RESOURCES_PATH/$ICON_NAME.icns"
    rm -rf "$ICONSET_PATH" "$rendered_dir"
}

add_app_framework_rpath() {
    install_name_tool -add_rpath "@executable_path/../Frameworks" "$MACOS_PATH/$APP_NAME"
}

resolve_sparkle_framework_source() {
    local build_output_framework="$BUILD_BIN_PATH/Sparkle.framework"
    local artifact_framework="$ROOT_DIR/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"

    if [[ -d "$build_output_framework" ]]; then
        SPARKLE_FRAMEWORK_SOURCE="$build_output_framework"
        return
    fi

    if [[ -d "$artifact_framework" ]]; then
        SPARKLE_FRAMEWORK_SOURCE="$artifact_framework"
        return
    fi

    echo "Sparkle.framework not found in build output or SwiftPM artifacts" >&2
    echo "  tried: $build_output_framework" >&2
    echo "  tried: $artifact_framework" >&2
    exit 1
}

copy_support_frameworks() {
    if [[ ! -d "$SPARKLE_FRAMEWORK_SOURCE" ]]; then
        echo "Sparkle.framework not found at $SPARKLE_FRAMEWORK_SOURCE" >&2
        exit 1
    fi

    ditto "$SPARKLE_FRAMEWORK_SOURCE" "$FRAMEWORKS_PATH/Sparkle.framework"
}

codesign_nested_item() {
    local path="$1"
    if [[ ! -e "$path" ]]; then
        return
    fi

    codesign \
        --force \
        --sign "$SIGN_IDENTITY" \
        "$path" >/dev/null
}

codesign_support_frameworks() {
    local sparkle_framework="$FRAMEWORKS_PATH/Sparkle.framework"
    local sparkle_current="$sparkle_framework/Versions/Current"

    if [[ ! -d "$sparkle_framework" ]]; then
        return
    fi

    codesign_nested_item "$sparkle_current/Autoupdate"
    codesign_nested_item "$sparkle_current/Updater.app"

    if compgen -G "$sparkle_current/XPCServices/*.xpc" >/dev/null; then
        for xpc_service in "$sparkle_current"/XPCServices/*.xpc; do
            codesign_nested_item "$xpc_service"
        done
    fi

    codesign_nested_item "$sparkle_framework"
}

echo "Building NotesBridge ($BUILD_CONFIG)..."
BUILD_BIN_PATH="$(swift build --package-path "$ROOT_DIR" -c "$BUILD_CONFIG" --show-bin-path)"
EXECUTABLE_PATH="$BUILD_BIN_PATH/NotesBridge"
resolve_sparkle_framework_source

if [[ ! -x "$EXECUTABLE_PATH" ]]; then
    echo "Expected executable was not produced at $EXECUTABLE_PATH" >&2
    exit 1
fi

echo "Packaging app bundle at $APP_BUNDLE_PATH..."
rm -rf "$APP_BUNDLE_PATH"
mkdir -p "$MACOS_PATH"
mkdir -p "$RESOURCES_PATH"
mkdir -p "$FRAMEWORKS_PATH"
cp "$EXECUTABLE_PATH" "$MACOS_PATH/$APP_NAME"
add_app_framework_rpath
build_app_icon
copy_support_frameworks

cat > "$INFO_PLIST_PATH" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIconFile</key>
    <string>$ICON_NAME</string>
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
    <key>SUAutomaticallyUpdate</key>
    <false/>
    <key>SUEnableAutomaticChecks</key>
    <true/>
    <key>SUFeedURL</key>
    <string>$SPARKLE_FEED_URL</string>
    <key>SUPublicEDKey</key>
    <string>$SPARKLE_PUBLIC_ED_KEY</string>
    <key>SURequireSignedFeed</key>
    <true/>
    <key>SUVerifyUpdateBeforeExtraction</key>
    <true/>
$(if [[ -n "$TEAM_ID" ]]; then cat <<TEAM
    <key>TeamIdentifier</key>
    <string>$TEAM_ID</string>
TEAM
fi)
</dict>
</plist>
PLIST

codesign_support_frameworks

codesign \
    --force \
    --sign "$SIGN_IDENTITY" \
    --identifier "$BUNDLE_ID" \
    --requirements "$DESIGNATED_REQUIREMENT" \
    "$APP_BUNDLE_PATH" >/dev/null

echo "App bundle ready:"
echo "  $APP_BUNDLE_PATH"
echo "  version=$VERSION"
echo "  build=$BUILD_NUMBER"
echo "  bundle_id=$BUNDLE_ID"
echo "  codesign_identity=$SIGN_IDENTITY"
echo "  sparkle_feed_url=$SPARKLE_FEED_URL"

if [[ "$LAUNCH_AFTER_BUILD" -eq 1 ]]; then
    open -n "$APP_BUNDLE_PATH"
fi
