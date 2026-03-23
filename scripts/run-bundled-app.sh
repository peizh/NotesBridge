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

APP_SUPPORT_DIR="$HOME/Library/Application Support/NotesBridge"
APP_BUNDLE_PATH="$APP_SUPPORT_DIR/NotesBridge.app"
"$ROOT_DIR/scripts/build-app-bundle.sh" \
    $( [[ "$BUILD_CONFIG" == "debug" ]] && printf '%s' "--debug" ) \
    --output-dir "$APP_SUPPORT_DIR" \
    --app-name "NotesBridge" \
    --bundle-id "dev.notesbridge.app" \
    --version "0.2.2" \
    --build-number "1"

echo "Bundled app ready:"
echo "  $APP_BUNDLE_PATH"
echo "Note: bundled builds now use a stable designated requirement for TCC. If you previously granted an older build, remove and re-add NotesBridge once in Accessibility."

if [[ "$BUILD_ONLY" -eq 1 ]]; then
    exit 0
fi

echo "Launching bundled app..."
open -n "$APP_BUNDLE_PATH"
