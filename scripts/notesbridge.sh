#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NOTESBRIDGE_ROOT_DIR="$ROOT_DIR"

notesbridge_version_file_path() {
    printf '%s\n' "$NOTESBRIDGE_ROOT_DIR/VERSION"
}

notesbridge_resolve_version() {
    local explicit_version="${1:-}"
    local version="${NOTESBRIDGE_VERSION:-$explicit_version}"

    if [[ -z "${version:-}" ]]; then
        local version_file
        version_file="$(notesbridge_version_file_path)"
        if [[ -f "$version_file" ]]; then
            version="$(tr -d '[:space:]' < "$version_file")"
        fi
    fi

    if [[ -z "${version:-}" ]]; then
        version="$(git -C "$NOTESBRIDGE_ROOT_DIR" describe --tags --abbrev=0 2>/dev/null || echo 1.0.0)"
    fi

    printf '%s\n' "${version#v}"
}

notesbridge_resolve_build_number() {
    local explicit_build_number="${1:-}"
    local build_number="${NOTESBRIDGE_BUILD_NUMBER:-$explicit_build_number}"

    if [[ -z "${build_number:-}" ]]; then
        build_number="$(git -C "$NOTESBRIDGE_ROOT_DIR" rev-list --count HEAD 2>/dev/null || echo 1)"
    fi

    printf '%s\n' "$build_number"
}

usage() {
    cat <<EOF
Usage: $0 <command> [options]

Commands:
  dev            Build the local bundled app in Application Support and launch it
  bundle         Build a .app bundle
  release        Build release app + zip, optionally notarize
  package-zip    Package an existing .app into a zip
  notarize       Submit an archive for notarization and staple the app
  appcast        Generate Sparkle appcast content
  release-notes  Extract a release section from CHANGELOG.md

Examples:
  $0 dev
  $0 dev --build-only
  $0 bundle --debug --output-dir ~/Library/Application\\ Support/NotesBridge
  $0 release --version 0.2.5
  $0 release-notes 0.2.5
EOF
}

dev_usage() {
    cat <<EOF
Usage: $0 dev [--release] [--build-only]
EOF
}

release_usage() {
    cat <<EOF
Usage: $0 release [--version VERSION] [--build-number NUMBER] [--output-dir PATH] [--bundle-id ID] [--sign-identity NAME] [--team-id TEAM] [--notarize]
EOF
}

bundle_usage() {
    cat <<EOF
Usage: $0 bundle [options]

Options:
  --debug                 Build a debug bundle instead of release
  --output-dir PATH       Output directory for the bundle (default: ./dist)
  --app-name NAME         App bundle name (default: NotesBridge)
  --bundle-id ID          CFBundleIdentifier (default: dev.notesbridge.app)
  --version VERSION       CFBundleShortVersionString (default: VERSION file or latest git tag)
  --build-number NUMBER   CFBundleVersion (default: git commit count)
  --sign-identity NAME    codesign identity (default: ad-hoc "-")
  --team-id TEAM          Optional TeamIdentifier for Info.plist
  --launch                Open the built app after packaging
EOF
}

package_zip_usage() {
    cat <<EOF
Usage: $0 package-zip --app PATH [--output-dir PATH] [--archive-name NAME]
EOF
}

notarize_usage() {
    cat <<EOF
Usage: $0 notarize --archive PATH --app PATH [--bundle-id ID]

Required environment variables:
  APPLE_ID
  APPLE_TEAM_ID
  APPLE_APP_SPECIFIC_PASSWORD
EOF
}

appcast_usage() {
    cat <<EOF
Usage: $0 appcast --version VERSION --archive PATH --release-notes PATH --site-dir PATH
EOF
}

release_notes_usage() {
    cat <<EOF
Usage: $0 release-notes VERSION
EOF
}

run_dev_command() {
    local build_config="debug"
    local build_only=0

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --release)
                build_config="release"
                ;;
            --build-only)
                build_only=1
                ;;
            -h|--help)
                dev_usage
                exit 0
                ;;
            *)
                echo "Unknown option for dev: $1" >&2
                dev_usage >&2
                exit 1
                ;;
        esac
        shift
    done

    local app_support_dir="$HOME/Library/Application Support/NotesBridge"
    local app_bundle_path="$app_support_dir/NotesBridge.app"
    local build_args=(
        --output-dir "$app_support_dir"
        --app-name "NotesBridge"
        --bundle-id "dev.notesbridge.app"
    )

    if [[ "$build_config" == "debug" ]]; then
        build_args=(--debug "${build_args[@]}")
    fi

    run_bundle_command "${build_args[@]}"

    echo "Bundled app ready:"
    echo "  $app_bundle_path"
    echo "Note: bundled builds now use a stable designated requirement for TCC. If you previously granted an older build, remove and re-add NotesBridge once in Accessibility."

    if [[ "$build_only" -eq 1 ]]; then
        return
    fi

    echo "Launching bundled app..."
    open -n "$app_bundle_path"
}

run_bundle_command() {
    local build_config="release"
    local output_dir="$ROOT_DIR/dist"
    local app_name="NotesBridge"
    local bundle_id="dev.notesbridge.app"
    local version=""
    local build_number=""
    local sign_identity="-"
    local team_id=""
    local launch_after_build=0
    local sparkle_feed_url="${NOTESBRIDGE_SPARKLE_FEED_URL:-https://peizh.github.io/NoteBridge/updates/appcast.xml}"
    local sparkle_public_ed_key="${NOTESBRIDGE_SPARKLE_PUBLIC_ED_KEY:-bN0AdWyNntmdvuNQNXa2pDP8peMGNfsbBcrXIBf60ys=}"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --debug)
                build_config="debug"
                ;;
            --output-dir)
                output_dir="$2"
                shift
                ;;
            --app-name)
                app_name="$2"
                shift
                ;;
            --bundle-id)
                bundle_id="$2"
                shift
                ;;
            --version)
                version="$2"
                shift
                ;;
            --build-number)
                build_number="$2"
                shift
                ;;
            --sign-identity)
                sign_identity="$2"
                shift
                ;;
            --team-id)
                team_id="$2"
                shift
                ;;
            --launch)
                launch_after_build=1
                ;;
            -h|--help)
                bundle_usage
                exit 0
                ;;
            *)
                echo "Unknown option for bundle: $1" >&2
                bundle_usage >&2
                exit 1
                ;;
        esac
        shift
    done

    version="$(notesbridge_resolve_version "$version")"
    build_number="$(notesbridge_resolve_build_number "$build_number")"

    local build_bin_path=""
    local executable_path=""
    local sparkle_framework_source=""
    local app_bundle_path="$output_dir/$app_name.app"
    local contents_path="$app_bundle_path/Contents"
    local macos_path="$contents_path/MacOS"
    local resources_path="$contents_path/Resources"
    local frameworks_path="$contents_path/Frameworks"
    local info_plist_path="$contents_path/Info.plist"
    local designated_requirement="=designated => identifier \"$bundle_id\""
    local icon_source_path="$ROOT_DIR/images/notesbridge-app-icon.svg"
    local iconset_path="$output_dir/$app_name.iconset"
    local icon_name="$app_name"

    build_app_icon() {
        if [[ ! -f "$icon_source_path" ]]; then
            echo "App icon source not found at $icon_source_path" >&2
            exit 1
        fi

        rm -rf "$iconset_path"
        mkdir -p "$iconset_path"

        local rendered_dir
        rendered_dir="$(mktemp -d)"
        qlmanage -t -s 1024 -o "$rendered_dir" "$icon_source_path" >/dev/null 2>&1

        local base_png="$rendered_dir/$(basename "$icon_source_path").png"
        if [[ ! -f "$base_png" ]]; then
            echo "Failed to render app icon preview from $icon_source_path" >&2
            rm -rf "$rendered_dir"
            exit 1
        fi

        cp "$base_png" "$iconset_path/icon_512x512@2x.png"
        sips -z 512 512 "$base_png" --out "$iconset_path/icon_512x512.png" >/dev/null
        sips -z 256 256 "$base_png" --out "$iconset_path/icon_256x256.png" >/dev/null
        cp "$iconset_path/icon_512x512.png" "$iconset_path/icon_256x256@2x.png"
        sips -z 128 128 "$base_png" --out "$iconset_path/icon_128x128.png" >/dev/null
        cp "$iconset_path/icon_256x256.png" "$iconset_path/icon_128x128@2x.png"
        sips -z 64 64 "$base_png" --out "$iconset_path/icon_64x64.png" >/dev/null
        sips -z 32 32 "$base_png" --out "$iconset_path/icon_32x32.png" >/dev/null
        cp "$iconset_path/icon_64x64.png" "$iconset_path/icon_32x32@2x.png"
        sips -z 16 16 "$base_png" --out "$iconset_path/icon_16x16.png" >/dev/null
        sips -z 32 32 "$base_png" --out "$iconset_path/icon_16x16@2x.png" >/dev/null

        iconutil -c icns "$iconset_path" -o "$resources_path/$icon_name.icns"
        rm -rf "$iconset_path" "$rendered_dir"
    }

    add_app_framework_rpath() {
        install_name_tool -add_rpath "@executable_path/../Frameworks" "$macos_path/$app_name"
    }

    resolve_sparkle_framework_source() {
        local build_output_framework="$build_bin_path/Sparkle.framework"
        local artifact_framework="$ROOT_DIR/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"

        if [[ -d "$build_output_framework" ]]; then
            sparkle_framework_source="$build_output_framework"
            return
        fi

        if [[ -d "$artifact_framework" ]]; then
            sparkle_framework_source="$artifact_framework"
            return
        fi

        echo "Sparkle.framework not found in build output or SwiftPM artifacts" >&2
        echo "  tried: $build_output_framework" >&2
        echo "  tried: $artifact_framework" >&2
        exit 1
    }

    copy_support_frameworks() {
        if [[ ! -d "$sparkle_framework_source" ]]; then
            echo "Sparkle.framework not found at $sparkle_framework_source" >&2
            exit 1
        fi

        ditto "$sparkle_framework_source" "$frameworks_path/Sparkle.framework"
    }

    codesign_nested_item() {
        local path="$1"
        if [[ ! -e "$path" ]]; then
            return
        fi

        codesign --force --sign "$sign_identity" "$path" >/dev/null
    }

    codesign_support_frameworks() {
        local sparkle_framework="$frameworks_path/Sparkle.framework"
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

    echo "Building NotesBridge ($build_config)..."
    swift build --package-path "$ROOT_DIR" -c "$build_config"
    build_bin_path="$(swift build --package-path "$ROOT_DIR" -c "$build_config" --show-bin-path)"
    executable_path="$build_bin_path/NotesBridge"
    resolve_sparkle_framework_source

    if [[ ! -x "$executable_path" ]]; then
        echo "Expected executable was not produced at $executable_path" >&2
        exit 1
    fi

    echo "Packaging app bundle at $app_bundle_path..."
    rm -rf "$app_bundle_path"
    mkdir -p "$macos_path" "$resources_path" "$frameworks_path"
    cp "$executable_path" "$macos_path/$app_name"
    add_app_framework_rpath
    build_app_icon
    copy_support_frameworks

    cat >"$info_plist_path" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>$app_name</string>
    <key>CFBundleIconFile</key>
    <string>$icon_name</string>
    <key>CFBundleIdentifier</key>
    <string>$bundle_id</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>$app_name</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$version</string>
    <key>CFBundleVersion</key>
    <string>$build_number</string>
    <key>LSUIElement</key>
    <true/>
    <key>SUAutomaticallyUpdate</key>
    <false/>
    <key>SUEnableAutomaticChecks</key>
    <true/>
    <key>SUFeedURL</key>
    <string>$sparkle_feed_url</string>
    <key>SUPublicEDKey</key>
    <string>$sparkle_public_ed_key</string>
    <key>SURequireSignedFeed</key>
    <true/>
    <key>SUVerifyUpdateBeforeExtraction</key>
    <true/>
$(if [[ -n "$team_id" ]]; then
  cat <<TEAM
    <key>TeamIdentifier</key>
    <string>$team_id</string>
TEAM
fi)
</dict>
</plist>
PLIST

    codesign_support_frameworks

    codesign \
      --force \
      --sign "$sign_identity" \
      --identifier "$bundle_id" \
      --requirements "$designated_requirement" \
      "$app_bundle_path" >/dev/null

    echo "App bundle ready:"
    echo "  $app_bundle_path"
    echo "  version=$version"
    echo "  build=$build_number"
    echo "  bundle_id=$bundle_id"
    echo "  codesign_identity=$sign_identity"
    echo "  sparkle_feed_url=$sparkle_feed_url"

    if [[ "$launch_after_build" -eq 1 ]]; then
        open -n "$app_bundle_path"
    fi
}

run_package_zip_command() {
    local app_path=""
    local output_dir="$ROOT_DIR/dist"
    local archive_name=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --app)
                app_path="$2"
                shift
                ;;
            --output-dir)
                output_dir="$2"
                shift
                ;;
            --archive-name)
                archive_name="$2"
                shift
                ;;
            -h|--help)
                package_zip_usage
                exit 0
                ;;
            *)
                echo "Unknown option for package-zip: $1" >&2
                package_zip_usage >&2
                exit 1
                ;;
        esac
        shift
    done

    if [[ -z "$app_path" ]]; then
        package_zip_usage >&2
        exit 1
    fi

    if [[ ! -d "$app_path" ]]; then
        echo "App bundle not found: $app_path" >&2
        exit 1
    fi

    mkdir -p "$output_dir"

    local app_basename archive_path
    app_basename="$(basename "$app_path" .app)"
    if [[ -z "$archive_name" ]]; then
        archive_name="$app_basename.zip"
    fi

    archive_path="$output_dir/$archive_name"
    rm -f "$archive_path"

    ditto -c -k --keepParent "$app_path" "$archive_path"

    echo "ZIP archive ready:"
    echo "  $archive_path"
}

run_notarize_command() {
    local archive_path=""
    local app_path=""
    local primary_bundle_id="dev.notesbridge.app"
    local apple_id="${APPLE_ID:-}"
    local apple_team_id="${APPLE_TEAM_ID:-}"
    local apple_app_specific_password="${APPLE_APP_SPECIFIC_PASSWORD:-}"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --archive)
                archive_path="$2"
                shift
                ;;
            --app)
                app_path="$2"
                shift
                ;;
            --bundle-id)
                primary_bundle_id="$2"
                shift
                ;;
            -h|--help)
                notarize_usage
                exit 0
                ;;
            *)
                echo "Unknown option for notarize: $1" >&2
                notarize_usage >&2
                exit 1
                ;;
        esac
        shift
    done

    if [[ -z "$archive_path" || -z "$app_path" ]]; then
        notarize_usage >&2
        exit 1
    fi

    if [[ ! -f "$archive_path" ]]; then
        echo "Archive not found: $archive_path" >&2
        exit 1
    fi

    if [[ ! -d "$app_path" ]]; then
        echo "App bundle not found: $app_path" >&2
        exit 1
    fi

    if [[ -z "$apple_id" || -z "$apple_team_id" || -z "$apple_app_specific_password" ]]; then
        echo "Missing notarization credentials in environment." >&2
        notarize_usage >&2
        exit 1
    fi

    echo "Submitting archive for notarization..."
    xcrun notarytool submit "$archive_path" \
        --apple-id "$apple_id" \
        --team-id "$apple_team_id" \
        --password "$apple_app_specific_password" \
        --wait

    echo "Stapling notarization ticket..."
    xcrun stapler staple "$app_path"

    echo "Notarization complete for:"
    echo "  $app_path"
}

run_appcast_command() {
    local generate_appcast="${NOTESBRIDGE_GENERATE_APPCAST:-$ROOT_DIR/.build/artifacts/sparkle/Sparkle/bin/generate_appcast}"
    local github_repository_slug="${NOTESBRIDGE_GITHUB_REPOSITORY:-peizh/NoteBridge}"
    local pages_base_url="${NOTESBRIDGE_PAGES_BASE_URL:-https://peizh.github.io/NoteBridge}"
    local sparkle_private_ed_key="${SPARKLE_PRIVATE_ED_KEY:-${NOTESBRIDGE_SPARKLE_PRIVATE_ED_KEY:-}}"
    local version=""
    local archive_path=""
    local release_notes_path=""
    local site_dir=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --version)
                version="$2"
                shift
                ;;
            --archive)
                archive_path="$2"
                shift
                ;;
            --release-notes)
                release_notes_path="$2"
                shift
                ;;
            --site-dir)
                site_dir="$2"
                shift
                ;;
            -h|--help)
                appcast_usage
                exit 0
                ;;
            *)
                echo "Unknown option for appcast: $1" >&2
                appcast_usage >&2
                exit 1
                ;;
        esac
        shift
    done

    if [[ -z "$version" || -z "$archive_path" || -z "$release_notes_path" || -z "$site_dir" ]]; then
        appcast_usage >&2
        exit 1
    fi

    if [[ -z "$sparkle_private_ed_key" ]]; then
        echo "SPARKLE_PRIVATE_ED_KEY is required." >&2
        exit 1
    fi

    if [[ ! -x "$generate_appcast" ]]; then
        echo "generate_appcast not found at $generate_appcast" >&2
        exit 1
    fi

    local release_tag updates_dir archive_name release_notes_name
    release_tag="$version"
    version="${version#v}"
    updates_dir="$site_dir/updates"
    archive_name="$(basename "$archive_path")"
    release_notes_name="$(basename "$release_notes_path")"

    mkdir -p "$updates_dir"
    cp "$release_notes_path" "$updates_dir/$release_notes_name"
    cp "$archive_path" "$updates_dir/$archive_name"

    pushd "$updates_dir" >/dev/null
    printf '%s' "$sparkle_private_ed_key" | "$generate_appcast" \
        --ed-key-file - \
        --download-url-prefix "https://github.com/$github_repository_slug/releases/download/$release_tag/" \
        --release-notes-url-prefix "$pages_base_url/updates/" \
        --link "https://github.com/$github_repository_slug/releases" \
        --maximum-deltas 0 \
        -o appcast.xml \
        .
    rm -f "$archive_name"
    popd >/dev/null

    echo "Sparkle appcast updated:"
    echo "  site_dir=$site_dir"
    echo "  appcast=$updates_dir/appcast.xml"
}

run_release_notes_command() {
    local changelog_path="$ROOT_DIR/CHANGELOG.md"
    local version="${1:-}"

    if [[ -z "$version" ]]; then
        release_notes_usage >&2
        exit 1
    fi
    version="${version#v}"

    local section
    section="$(
        awk -v version="$version" '
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
        ' "$changelog_path"
    )"

    if [[ -z "$section" ]]; then
        echo "Could not find changelog section for version $version" >&2
        exit 1
    fi

    echo "$section"
}

run_release_command() {
    local version=""
    local build_number=""
    local output_dir="${NOTESBRIDGE_OUTPUT_DIR:-$ROOT_DIR/dist}"
    local bundle_id="${NOTESBRIDGE_BUNDLE_ID:-dev.notesbridge.app}"
    local sign_identity="${NOTESBRIDGE_SIGN_IDENTITY:--}"
    local team_id="${NOTESBRIDGE_TEAM_ID:-}"
    local notarize="${NOTESBRIDGE_NOTARIZE:-0}"
    local app_name="NotesBridge"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --version)
                version="$2"
                shift
                ;;
            --build-number)
                build_number="$2"
                shift
                ;;
            --output-dir)
                output_dir="$2"
                shift
                ;;
            --bundle-id)
                bundle_id="$2"
                shift
                ;;
            --sign-identity)
                sign_identity="$2"
                shift
                ;;
            --team-id)
                team_id="$2"
                shift
                ;;
            --notarize)
                notarize="1"
                ;;
            -h|--help)
                release_usage
                exit 0
                ;;
            *)
                echo "Unknown option for release: $1" >&2
                release_usage >&2
                exit 1
                ;;
        esac
        shift
    done

    version="$(notesbridge_resolve_version "$version")"
    build_number="$(notesbridge_resolve_build_number "$build_number")"

    local app_path zip_name zip_path build_args=()
    app_path="$output_dir/$app_name.app"
    zip_name="$app_name-$version-macOS.zip"
    zip_path="$output_dir/$zip_name"

    build_args=(
        --output-dir "$output_dir"
        --app-name "$app_name"
        --bundle-id "$bundle_id"
        --version "$version"
        --build-number "$build_number"
        --sign-identity "$sign_identity"
    )

    if [[ -n "$team_id" ]]; then
        build_args+=(--team-id "$team_id")
    fi

    run_bundle_command "${build_args[@]}"
    run_package_zip_command \
        --app "$app_path" \
        --output-dir "$output_dir" \
        --archive-name "$zip_name"

    if [[ "$notarize" == "1" ]]; then
        run_notarize_command \
            --archive "$zip_path" \
            --app "$app_path" \
            --bundle-id "$bundle_id"

        run_package_zip_command \
            --app "$app_path" \
            --output-dir "$output_dir" \
            --archive-name "$zip_name"
    fi

    echo
    echo "Release artifacts ready:"
    echo "  App: $app_path"
    echo "  ZIP: $zip_path"
}

command_name="${1:-}"
if [[ -z "$command_name" ]]; then
    usage >&2
    exit 1
fi
shift || true

case "$command_name" in
    dev)
        run_dev_command "$@"
        ;;
    bundle)
        run_bundle_command "$@"
        ;;
    release)
        run_release_command "$@"
        ;;
    package-zip)
        run_package_zip_command "$@"
        ;;
    notarize)
        run_notarize_command "$@"
        ;;
    appcast)
        run_appcast_command "$@"
        ;;
    release-notes)
        run_release_notes_command "$@"
        ;;
    -h|--help|help)
        usage
        ;;
    *)
        echo "Unknown command: $command_name" >&2
        usage >&2
        exit 1
        ;;
esac
