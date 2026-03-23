#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GENERATE_APPCAST="${NOTESBRIDGE_GENERATE_APPCAST:-$ROOT_DIR/.build/artifacts/sparkle/Sparkle/bin/generate_appcast}"
GITHUB_REPOSITORY_SLUG="${NOTESBRIDGE_GITHUB_REPOSITORY:-peizh/NoteBridge}"
PAGES_BASE_URL="${NOTESBRIDGE_PAGES_BASE_URL:-https://peizh.github.io/NoteBridge}"
SPARKLE_PRIVATE_ED_KEY="${SPARKLE_PRIVATE_ED_KEY:-${NOTESBRIDGE_SPARKLE_PRIVATE_ED_KEY:-}}"

VERSION=""
ARCHIVE_PATH=""
RELEASE_NOTES_PATH=""
SITE_DIR=""

usage() {
    cat <<EOF
Usage: $0 --version VERSION --archive PATH --release-notes PATH --site-dir PATH
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --version)
            VERSION="$2"
            shift
            ;;
        --archive)
            ARCHIVE_PATH="$2"
            shift
            ;;
        --release-notes)
            RELEASE_NOTES_PATH="$2"
            shift
            ;;
        --site-dir)
            SITE_DIR="$2"
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

if [[ -z "$VERSION" || -z "$ARCHIVE_PATH" || -z "$RELEASE_NOTES_PATH" || -z "$SITE_DIR" ]]; then
    usage >&2
    exit 1
fi

if [[ -z "$SPARKLE_PRIVATE_ED_KEY" ]]; then
    echo "SPARKLE_PRIVATE_ED_KEY is required." >&2
    exit 1
fi

if [[ ! -x "$GENERATE_APPCAST" ]]; then
    echo "generate_appcast not found at $GENERATE_APPCAST" >&2
    exit 1
fi

RELEASE_TAG="$VERSION"
VERSION="${VERSION#v}"
UPDATES_DIR="$SITE_DIR/updates"
ARCHIVE_NAME="$(basename "$ARCHIVE_PATH")"
RELEASE_NOTES_NAME="$(basename "$RELEASE_NOTES_PATH")"

mkdir -p "$UPDATES_DIR"
cp "$RELEASE_NOTES_PATH" "$UPDATES_DIR/$RELEASE_NOTES_NAME"
cp "$ARCHIVE_PATH" "$UPDATES_DIR/$ARCHIVE_NAME"

pushd "$UPDATES_DIR" >/dev/null
printf '%s' "$SPARKLE_PRIVATE_ED_KEY" | "$GENERATE_APPCAST" \
    --ed-key-file - \
    --download-url-prefix "https://github.com/$GITHUB_REPOSITORY_SLUG/releases/download/$RELEASE_TAG/" \
    --release-notes-url-prefix "$PAGES_BASE_URL/updates/" \
    --link "https://github.com/$GITHUB_REPOSITORY_SLUG/releases" \
    --maximum-deltas 0 \
    -o appcast.xml \
    .
rm -f "$ARCHIVE_NAME"
popd >/dev/null

echo "Sparkle appcast updated:"
echo "  site_dir=$SITE_DIR"
echo "  appcast=$UPDATES_DIR/appcast.xml"
