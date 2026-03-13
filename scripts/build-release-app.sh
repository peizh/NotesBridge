#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_DIR="$ROOT_DIR/dist"

VERSION="${NOTESBRIDGE_VERSION:-${1:-}}"
if [[ -z "${VERSION:-}" ]]; then
    VERSION="$(git describe --tags --abbrev=0 2>/dev/null || echo 1.0.0)"
fi
VERSION="${VERSION#v}"

BUILD_NUMBER="${NOTESBRIDGE_BUILD_NUMBER:-$(git rev-list --count HEAD)}"
BUNDLE_ID="${NOTESBRIDGE_BUNDLE_ID:-dev.notesbridge.app}"
SIGN_IDENTITY="${NOTESBRIDGE_SIGN_IDENTITY:--}"
TEAM_ID="${NOTESBRIDGE_TEAM_ID:-}"
APP_NAME="NotesBridge"
APP_PATH="$OUTPUT_DIR/$APP_NAME.app"
ZIP_NAME="$APP_NAME-$VERSION-macOS.zip"
ZIP_PATH="$OUTPUT_DIR/$ZIP_NAME"

build_args=(
    --output-dir "$OUTPUT_DIR"
    --app-name "$APP_NAME"
    --bundle-id "$BUNDLE_ID"
    --version "$VERSION"
    --build-number "$BUILD_NUMBER"
    --sign-identity "$SIGN_IDENTITY"
)

if [[ -n "$TEAM_ID" ]]; then
    build_args+=(--team-id "$TEAM_ID")
fi

"$ROOT_DIR/scripts/build-app-bundle.sh" "${build_args[@]}"

"$ROOT_DIR/scripts/package-release-zip.sh" \
    --app "$APP_PATH" \
    --output-dir "$OUTPUT_DIR" \
    --archive-name "$ZIP_NAME"

if [[ "${NOTESBRIDGE_NOTARIZE:-0}" == "1" ]]; then
    "$ROOT_DIR/scripts/notarize-release.sh" \
        --archive "$ZIP_PATH" \
        --app "$APP_PATH" \
        --bundle-id "$BUNDLE_ID"

    "$ROOT_DIR/scripts/package-release-zip.sh" \
        --app "$APP_PATH" \
        --output-dir "$OUTPUT_DIR" \
        --archive-name "$ZIP_NAME"
fi

echo
echo "Release artifacts ready:"
echo "  App: $APP_PATH"
echo "  ZIP: $ZIP_PATH"
