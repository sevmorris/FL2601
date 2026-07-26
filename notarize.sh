#!/usr/bin/env bash
#
# Submits a .app or .dmg to Apple for notarization, waits for the result,
# and staples the ticket so the app opens offline without a Gatekeeper prompt.
#
# Usage:
#   ./notarize.sh "build/Build/Products/Release/FL2601 Cipher Tool.app"
#   ./notarize.sh dist/FL2601-Cipher-Tool-1.0.dmg
#
# One-time setup (this stores an app-specific password in your keychain, so
# run it yourself - it prompts for the password interactively):
#
#   xcrun notarytool store-credentials "FL2601" \
#       --apple-id "$APPLE_ID" \
#       --team-id "$TEAM_ID"
#
# Create the app-specific password at https://account.apple.com -> Sign-In and
# Security -> App-Specific Passwords. It is not your Apple ID password.
#
# Once stored, this script authenticates with the keychain profile alone - it
# never needs your Apple ID again. APPLE_ID below is only used to print an
# accurate setup command if the profile is missing.
#
set -euo pipefail

NOTARY_PROFILE="${NOTARY_PROFILE:-FL2601}"
APPLE_ID="${APPLE_ID:-your-apple-id@example.com}"
TEAM_ID="${TEAM_ID:-T9RLNAXPWU}"

TARGET="${1:-}"
if [ -z "$TARGET" ]; then
    echo "Usage: $0 <path-to-.app-or-.dmg>" >&2
    exit 1
fi
if [ ! -e "$TARGET" ]; then
    echo "Not found: $TARGET" >&2
    exit 1
fi

if ! xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
    cat >&2 <<EOF
No notarytool credentials found for profile "$NOTARY_PROFILE".

Run this once (it will prompt for an app-specific password):

  xcrun notarytool store-credentials "$NOTARY_PROFILE" \\
      --apple-id "$APPLE_ID" \\
      --team-id "$TEAM_ID"

Generate the app-specific password at https://account.apple.com under
Sign-In and Security -> App-Specific Passwords.
EOF
    exit 1
fi

# notarytool only accepts .zip, .dmg, and .pkg. A .app has to be zipped first,
# but the ticket is stapled to the .app itself, not to the zip.
CLEANUP=""
# Single-quoted so $CLEANUP is read when the trap fires, not when it is set.
trap 'test -n "$CLEANUP" && rm -f "$CLEANUP"' EXIT

case "$TARGET" in
    *.app)
        UPLOAD="$(mktemp -d)/$(basename "$TARGET" .app).zip"
        CLEANUP="$UPLOAD"
        echo "Zipping for upload..."
        ditto -c -k --keepParent "$TARGET" "$UPLOAD"
        ;;
    *.dmg|*.pkg|*.zip)
        UPLOAD="$TARGET"
        ;;
    *)
        echo "Unsupported file type: $TARGET" >&2
        exit 1
        ;;
esac

echo "Submitting to Apple (this usually takes 1-5 minutes)..."
set +e
SUBMIT_OUTPUT=$(xcrun notarytool submit "$UPLOAD" \
    --keychain-profile "$NOTARY_PROFILE" \
    --wait 2>&1)
SUBMIT_STATUS=$?
set -e

echo "$SUBMIT_OUTPUT"

REQUEST_ID=$(echo "$SUBMIT_OUTPUT" | awk '/^ *id:/ { print $2; exit }')

if [ $SUBMIT_STATUS -ne 0 ] || ! echo "$SUBMIT_OUTPUT" | grep -q 'status: Accepted'; then
    echo >&2
    echo "Notarization did not succeed." >&2
    if [ -n "$REQUEST_ID" ]; then
        echo "Fetching the rejection log:" >&2
        xcrun notarytool log "$REQUEST_ID" --keychain-profile "$NOTARY_PROFILE" >&2 || true
    fi
    exit 1
fi

echo
echo "Stapling ticket to $TARGET..."
xcrun stapler staple "$TARGET"
xcrun stapler validate "$TARGET"

echo
echo "=== Gatekeeper assessment ==="
case "$TARGET" in
    *.app)
        spctl --assess --type execute --verbose=4 "$TARGET"
        ;;
    *.dmg)
        # A disk image is assessed as "open", not as an executable.
        spctl --assess --type open --context context:primary-signature --verbose=4 "$TARGET"
        ;;
esac

echo
echo "Notarized and stapled: $TARGET"
