#!/usr/bin/env bash
#
# Produces a distributable, notarized DMG:
#   build (Developer ID + hardened runtime) -> DMG -> sign -> notarize -> staple
#
# Usage:
#   ./distribute.sh              Full pipeline
#   ./distribute.sh --no-notary  Build and package only (skip Apple submission)
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/build"
DIST_DIR="$SCRIPT_DIR/dist"
APP_NAME="FL2601 Cipher Tool.app"
VOLUME_NAME="FL2601 Cipher Tool"
SIGNING_IDENTITY="Developer ID Application: Seven Morris (T9RLNAXPWU)"

NOTARIZE=true
for arg in "$@"; do
    case "$arg" in
        --no-notary) NOTARIZE=false ;;
        -h|--help)
            sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *)
            echo "Unknown option: $arg" >&2
            exit 1
            ;;
    esac
done

"$SCRIPT_DIR/build.sh"

APP_PATH="$BUILD_DIR/Build/Products/Release/$APP_NAME"
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" \
    "$APP_PATH/Contents/Info.plist" 2>/dev/null || echo "1.0")

mkdir -p "$DIST_DIR"
DMG_PATH="$DIST_DIR/FL2601-Cipher-Tool-$VERSION.dmg"

if [ "$NOTARIZE" = true ]; then
    echo
    echo "=== Notarizing the app ==="
    # Staple the app *before* it goes into the image. Stapling only the DMG
    # leaves the copy the user drags to /Applications without a ticket, which
    # forces Gatekeeper to check with Apple over the network on first launch
    # and fails when that machine is offline.
    "$SCRIPT_DIR/notarize.sh" "$APP_PATH"
fi

echo
echo "=== Packaging DMG ==="
STAGING=$(mktemp -d)
trap 'rm -rf "$STAGING"' EXIT

cp -R "$APP_PATH" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

rm -f "$DMG_PATH"
hdiutil create \
    -volname "$VOLUME_NAME" \
    -srcfolder "$STAGING" \
    -ov -format UDZO \
    "$DMG_PATH"

echo
echo "Signing the disk image..."
codesign --force --sign "$SIGNING_IDENTITY" --timestamp "$DMG_PATH"
codesign --verify --verbose=2 "$DMG_PATH"

if [ "$NOTARIZE" = true ]; then
    echo
    echo "=== Notarizing the disk image ==="
    # Second submission: the image itself, so the download is stapled too.
    "$SCRIPT_DIR/notarize.sh" "$DMG_PATH"
else
    echo
    echo "Skipped notarization (--no-notary). The DMG will trigger a Gatekeeper"
    echo "warning on other Macs until it is notarized."
fi

echo
echo "=== Done ==="
echo "DMG:  $DMG_PATH"
echo "Size: $(du -h "$DMG_PATH" | cut -f1)"
