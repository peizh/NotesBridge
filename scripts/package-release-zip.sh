#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

APP_PATH=""
OUTPUT_DIR="$ROOT_DIR/dist"
ARCHIVE_NAME=""

usage() {
    cat <<EOF
Usage: $0 --app PATH [--output-dir PATH] [--archive-name NAME]
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --app)
            APP_PATH="$2"
            shift
            ;;
        --output-dir)
            OUTPUT_DIR="$2"
            shift
            ;;
        --archive-name)
            ARCHIVE_NAME="$2"
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

if [[ -z "$APP_PATH" ]]; then
    usage >&2
    exit 1
fi

if [[ ! -d "$APP_PATH" ]]; then
    echo "App bundle not found: $APP_PATH" >&2
    exit 1
fi

mkdir -p "$OUTPUT_DIR"

APP_BASENAME="$(basename "$APP_PATH" .app)"
if [[ -z "$ARCHIVE_NAME" ]]; then
    ARCHIVE_NAME="$APP_BASENAME.zip"
fi

ARCHIVE_PATH="$OUTPUT_DIR/$ARCHIVE_NAME"
rm -f "$ARCHIVE_PATH"

ditto -c -k --keepParent "$APP_PATH" "$ARCHIVE_PATH"

echo "ZIP archive ready:"
echo "  $ARCHIVE_PATH"
