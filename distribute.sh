#!/usr/bin/env bash
#
# Produces a distributable, notarized DMG:
#   build (Developer ID + hardened runtime) -> DMG -> sign -> notarize -> staple
#
# Usage:
#   ./distribute.sh              Full pipeline
#   ./distribute.sh --no-notary  Build and package only (skip Apple submission)
#   ./distribute.sh --bump-cask  ...and push the new version to the Homebrew tap
#
# --bump-cask writes to a second repository, so it is opt-in rather than part
# of the default run. It refuses to push anything that was not notarized.
#
set -euo pipefail

TAP_REPO="sevmorris/homebrew-tap"
TAP_CASK_PATH="Casks/fl2601.rb"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/build"
DIST_DIR="$SCRIPT_DIR/dist"
APP_NAME="FL2601 Cipher Tool.app"
VOLUME_NAME="FL2601 Cipher Tool"
SIGNING_IDENTITY="Developer ID Application: Seven Morris (T9RLNAXPWU)"

NOTARIZE=true
BUMP_CASK=false
for arg in "$@"; do
    case "$arg" in
        --no-notary) NOTARIZE=false ;;
        --bump-cask) BUMP_CASK=true ;;
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

if [ "$BUMP_CASK" = true ]; then
    echo
    echo "=== Bumping the Homebrew cask ==="
    if [ "$NOTARIZE" != true ]; then
        echo "Refusing to publish a cask for an un-notarized build." >&2
        exit 1
    fi

    DMG_SHA256=$(shasum -a 256 "$DMG_PATH" | awk '{print $1}')
    [ -n "$DMG_SHA256" ] || { echo "Could not hash $DMG_PATH" >&2; exit 1; }

    TAP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/homebrew-tap.XXXXXX")
    # SSH rather than the gh CLI's HTTPS default, so the push uses the same key
    # as everything else here instead of prompting for credentials.
    git clone --quiet "git@github.com:${TAP_REPO}.git" "$TAP_DIR"
    CASK_FILE="$TAP_DIR/$TAP_CASK_PATH"
    [ -f "$CASK_FILE" ] || { echo "Tap is missing $TAP_CASK_PATH" >&2; exit 1; }

    # Anchored to the whole line so a version like 1.1 can never match part of
    # a longer one like 1.1.1 and leave a half-rewritten file behind.
    sed -i '' "s|^  version \".*\"\$|  version \"${VERSION}\"|" "$CASK_FILE"
    sed -i '' "s|^  sha256 \".*\"\$|  sha256 \"${DMG_SHA256}\"|" "$CASK_FILE"

    # sed -i silently no-ops on a pattern that never matched, so confirm.
    grep -q "^  version \"${VERSION}\"\$" "$CASK_FILE" \
        || { echo "Cask version rewrite did not land" >&2; exit 1; }
    grep -q "^  sha256 \"${DMG_SHA256}\"\$" "$CASK_FILE" \
        || { echo "Cask sha256 rewrite did not land" >&2; exit 1; }

    (
        cd "$TAP_DIR"
        if [ -z "$(git status --porcelain)" ]; then
            echo "Cask already at $VERSION"
        else
            git add "$TAP_CASK_PATH"
            git commit --quiet -m "Bump fl2601 to ${VERSION}"
            git push --quiet origin HEAD
            echo "Cask bumped to ${VERSION} (sha256 ${DMG_SHA256:0:12}...)"
        fi
    )
    rm -rf "$TAP_DIR"
fi

echo
echo "=== Done ==="
echo "DMG:  $DMG_PATH"
echo "Size: $(du -h "$DMG_PATH" | cut -f1)"
if [ "$BUMP_CASK" != true ]; then
    echo
    echo "The Homebrew cask still points at the previous release."
    echo "Run with --bump-cask to publish this one to the tap."
fi
