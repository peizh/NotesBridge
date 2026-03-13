#!/bin/bash
set -euo pipefail

ARCHIVE_PATH=""
PRIMARY_BUNDLE_ID="dev.notesbridge.app"
APPLE_ID="${APPLE_ID:-}"
APPLE_TEAM_ID="${APPLE_TEAM_ID:-}"
APPLE_APP_SPECIFIC_PASSWORD="${APPLE_APP_SPECIFIC_PASSWORD:-}"
APP_PATH=""

usage() {
    cat <<EOF
Usage: $0 --archive PATH --app PATH [--bundle-id ID]

Required environment variables:
  APPLE_ID
  APPLE_TEAM_ID
  APPLE_APP_SPECIFIC_PASSWORD
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --archive)
            ARCHIVE_PATH="$2"
            shift
            ;;
        --app)
            APP_PATH="$2"
            shift
            ;;
        --bundle-id)
            PRIMARY_BUNDLE_ID="$2"
            shift
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

if [[ -z "$ARCHIVE_PATH" || -z "$APP_PATH" ]]; then
    usage >&2
    exit 1
fi

if [[ ! -f "$ARCHIVE_PATH" ]]; then
    echo "Archive not found: $ARCHIVE_PATH" >&2
    exit 1
fi

if [[ ! -d "$APP_PATH" ]]; then
    echo "App bundle not found: $APP_PATH" >&2
    exit 1
fi

if [[ -z "$APPLE_ID" || -z "$APPLE_TEAM_ID" || -z "$APPLE_APP_SPECIFIC_PASSWORD" ]]; then
    echo "Missing notarization credentials in environment." >&2
    usage >&2
    exit 1
fi

echo "Submitting archive for notarization..."
xcrun notarytool submit "$ARCHIVE_PATH" \
    --apple-id "$APPLE_ID" \
    --team-id "$APPLE_TEAM_ID" \
    --password "$APPLE_APP_SPECIFIC_PASSWORD" \
    --wait

echo "Stapling notarization ticket..."
xcrun stapler staple "$APP_PATH"

echo "Notarization complete for:"
echo "  $APP_PATH"
