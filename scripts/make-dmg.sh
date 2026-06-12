#!/usr/bin/env bash
# Usage: scripts/make-dmg.sh <version> <path-to-notarized.app>
# Example: scripts/make-dmg.sh 1.5 /tmp/Cyph3rfall.app
# Output: Cyph3rfall-v<version>.dmg in the repo root
set -euo pipefail

VERSION="${1:?Usage: make-dmg.sh <version> <path-to-app>}"
APP_PATH="${2:?Usage: make-dmg.sh <version> <path-to-app>}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
OUTPUT="$REPO_ROOT/Cyph3rfall-v${VERSION}.dmg"

if [[ ! -d "$APP_PATH" ]]; then
    echo "Error: app not found at $APP_PATH" >&2
    exit 1
fi

echo "Building branded DMG for v${VERSION}..."

# Normalise to Cyph3rfall.app so the DMG always shows the clean name.
STAGED_APP="/tmp/Cyph3rfall-dmg-stage-$$/Cyph3rfall.app"
mkdir -p "$(dirname "$STAGED_APP")"
cp -R "$APP_PATH" "$STAGED_APP"
trap "rm -rf /tmp/Cyph3rfall-dmg-stage-$$" EXIT

create-dmg \
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

echo "Done: $OUTPUT"
