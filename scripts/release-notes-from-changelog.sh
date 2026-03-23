#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHANGELOG_PATH="$ROOT_DIR/CHANGELOG.md"

VERSION="${1:-}"
if [[ -z "$VERSION" ]]; then
    echo "Usage: $0 VERSION" >&2
    exit 1
fi
VERSION="${VERSION#v}"

section="$(
    awk -v version="$VERSION" '
        BEGIN {
            target = "## [" version "]"
        }
        index($0, target) == 1 {
            in_section = 1
        }
        in_section && index($0, "## [") == 1 && index($0, target) != 1 {
            exit
        }
        in_section {
            print
        }
    ' "$CHANGELOG_PATH"
)"

if [[ -z "$section" ]]; then
    echo "Could not find changelog section for version $VERSION" >&2
    exit 1
fi

echo "$section"
