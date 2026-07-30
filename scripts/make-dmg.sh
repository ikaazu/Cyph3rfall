#!/usr/bin/env bash
# Usage: scripts/make-dmg.sh <version> <path-to-notarized.app>
# Example: scripts/make-dmg.sh 1.5 /tmp/Cyph3rfall.app
# Output: Cyph3rfall-v<version>.dmg in the repo root
set -euo pipefail

VERSION="${1:?Usage: make-dmg.sh <version> <path-to-app>}"
APP_PATH="${2:?Usage: make-dmg.sh <version> <path-to-app>}"
SCRIPT_DIR="$(cd "$(/usr/bin/dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
OUTPUT="$REPO_ROOT/Cyph3rfall-v${VERSION}.dmg"
EXPECTED_BUNDLE_ID="com.cyph3rfall.Cyph3rfall"
EXPECTED_TEAM_ID="GHXKLLWQPM"

if [[ ! "$VERSION" =~ ^[0-9]+(\.[0-9]+){1,3}$ ]]; then
    echo "Error: version must contain 2–4 numeric components (for example, 2.0 or 2.0.1)" >&2
    exit 1
fi

if [[ ! -d "$APP_PATH" || -L "$APP_PATH" ]]; then
    echo "Error: app not found at $APP_PATH" >&2
    exit 1
fi

CREATE_DMG_BIN="$(command -v create-dmg || true)"
if [[ -z "$CREATE_DMG_BIN" || ! -x "$CREATE_DMG_BIN" ]]; then
    echo "Error: create-dmg is not installed or executable" >&2
    exit 1
fi
case "$CREATE_DMG_BIN" in
    /opt/homebrew/bin/create-dmg|/usr/local/bin/create-dmg) ;;
    *)
        echo "Error: refusing unexpected create-dmg path: $CREATE_DMG_BIN" >&2
        exit 1
        ;;
esac

validate_app() {
    local app="$1"
    local info_plist="$app/Contents/Info.plist"
    local bundle_id
    local signing_details

    if [[ ! -f "$info_plist" ]]; then
        echo "Error: missing Info.plist in $app" >&2
        return 1
    fi

    bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$info_plist" 2>/dev/null || true)"
    if [[ "$bundle_id" != "$EXPECTED_BUNDLE_ID" ]]; then
        echo "Error: unexpected bundle identifier: $bundle_id" >&2
        return 1
    fi

    /usr/bin/codesign --verify --deep --strict --verbose=2 "$app"
    signing_details="$(/usr/bin/codesign -d --verbose=4 "$app" 2>&1)"
    if ! /usr/bin/grep -q "^TeamIdentifier=${EXPECTED_TEAM_ID}$" <<<"$signing_details"; then
        echo "Error: app is not signed by expected team $EXPECTED_TEAM_ID" >&2
        return 1
    fi
    if ! /usr/bin/grep -q 'flags=.*(runtime)' <<<"$signing_details"; then
        echo "Error: app signature does not enable hardened runtime" >&2
        return 1
    fi

    /usr/sbin/spctl --assess --type execute --verbose=2 "$app"
}

echo "Building branded DMG for v${VERSION}..."

# Use a newly created owner-only directory so another local account cannot
# pre-create or substitute the application that is packaged.
STAGE_DIR="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/Cyph3rfall-dmg-stage.XXXXXX")"
/bin/chmod 700 "$STAGE_DIR"
STAGED_APP="$STAGE_DIR/Cyph3rfall.app"
VERIFY_MOUNT="$STAGE_DIR/verify-mount"
VERIFY_MOUNTED=false

cleanup() {
    if [[ "$VERIFY_MOUNTED" == true ]]; then
        /usr/bin/hdiutil detach "$VERIFY_MOUNT" -quiet >/dev/null 2>&1 || true
    fi
    if [[ -n "$STAGE_DIR" && -d "$STAGE_DIR" ]]; then
        /bin/rm -rf -- "$STAGE_DIR"
    fi
}
trap cleanup EXIT INT TERM HUP

# Validate both the operator-provided app and the exact staged copy.
validate_app "$APP_PATH"
/usr/bin/ditto "$APP_PATH" "$STAGED_APP"
validate_app "$STAGED_APP"

"$CREATE_DMG_BIN" \
    --volname "Cyph3rfall" \
    --volicon "$REPO_ROOT/TestApp/Assets.xcassets/AppIcon.appiconset/icon_1024x1024.png" \
    --background "$REPO_ROOT/dmg-assets/background.png" \
    --window-pos 200 120 \
    --window-size 660 400 \
    --icon-size 96 \
    --icon "Cyph3rfall.app" 160 185 \
    --app-drop-link 500 185 \
    --hide-extension "Cyph3rfall.app" \
    --no-internet-enable \
    "$OUTPUT" \
    "$STAGED_APP"

/usr/bin/hdiutil verify "$OUTPUT"
/bin/mkdir "$VERIFY_MOUNT"
/usr/bin/hdiutil attach "$OUTPUT" \
    -mountpoint "$VERIFY_MOUNT" \
    -readonly \
    -nobrowse \
    -quiet
VERIFY_MOUNTED=true

DMG_APPS=("$VERIFY_MOUNT"/*.app)
if [[ ${#DMG_APPS[@]} -ne 1 || "$(/usr/bin/basename "${DMG_APPS[0]}")" != "Cyph3rfall.app" ]]; then
    echo "Error: finished DMG does not contain exactly one Cyph3rfall.app" >&2
    exit 1
fi
validate_app "${DMG_APPS[0]}"

/usr/bin/hdiutil detach "$VERIFY_MOUNT" -quiet
VERIFY_MOUNTED=false

echo "Done: $OUTPUT"
