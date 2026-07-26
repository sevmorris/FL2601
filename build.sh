#!/usr/bin/env bash
#
# Builds FL2601 Cipher Tool, signed with Developer ID + hardened runtime,
# and verifies the signature.
#
# Usage:
#   ./build.sh              Build and verify
#   ./build.sh --install    Also copy to /Applications
#   ./build.sh --debug      Ad-hoc signed Debug build (fast, local only)
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$SCRIPT_DIR/FL2601"
BUILD_DIR="$SCRIPT_DIR/build"
APP_NAME="FL2601 Cipher Tool.app"
INSTALL_DIR="/Applications"

CONFIGURATION="Release"
INSTALL=false

for arg in "$@"; do
    case "$arg" in
        --install) INSTALL=true ;;
        --debug)   CONFIGURATION="Debug" ;;
        -h|--help)
            sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *)
            echo "Unknown option: $arg" >&2
            exit 1
            ;;
    esac
done

echo "Building $APP_NAME ($CONFIGURATION)..."
xcodebuild \
    -project "$PROJECT_DIR/FL2601.xcodeproj" \
    -scheme FL2601 \
    -configuration "$CONFIGURATION" \
    -derivedDataPath "$BUILD_DIR" \
    build

APP_PATH="$BUILD_DIR/Build/Products/$CONFIGURATION/$APP_NAME"

if [ ! -d "$APP_PATH" ]; then
    echo "Build failed: $APP_PATH not found." >&2
    exit 1
fi

echo
echo "Build successful: $APP_PATH"
echo

echo "=== Signature ==="
codesign --display --verbose=2 "$APP_PATH" 2>&1 | grep -E 'Authority|TeamIdentifier|Identifier|Timestamp|flags' || true
echo

echo "=== Verifying ==="
codesign --verify --deep --strict --verbose=2 "$APP_PATH"
echo "codesign: OK"

if [ "$CONFIGURATION" = "Release" ]; then
    # Fails until the app has been notarized and stapled; that is expected on a
    # fresh build, so report it without treating it as a build failure.
    if spctl --assess --type execute --verbose=4 "$APP_PATH" 2>&1 | grep -q 'accepted'; then
        echo "spctl:    accepted (notarized)"
    else
        echo "spctl:    rejected - not notarized yet. Run ./distribute.sh to notarize."
    fi

    # Confirm the security posture actually made it into the binary.
    FLAGS=$(codesign --display --verbose=2 "$APP_PATH" 2>&1 | grep -o 'flags=.*' || echo "")
    case "$FLAGS" in
        *runtime*) echo "hardened: yes" ;;
        *)         echo "hardened: NO - hardened runtime missing, notarization will fail" >&2 ;;
    esac

    ENTITLEMENTS=$(codesign --display --entitlements - --xml "$APP_PATH" 2>/dev/null)

    if echo "$ENTITLEMENTS" | grep -q 'app-sandbox'; then
        echo "sandbox:  yes"
    else
        echo "sandbox:  NO" >&2
    fi

    # Xcode injects get-task-allow (the "a debugger may attach" entitlement)
    # unless CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO. Apple rejects notarization
    # outright when it is present, so fail here rather than after a round trip
    # to their servers.
    if echo "$ENTITLEMENTS" | grep -q 'get-task-allow'; then
        echo "debug:    FAIL - com.apple.security.get-task-allow is present" >&2
        echo >&2
        echo "Apple will reject this build. Ensure the Release configuration" >&2
        echo "sets CODE_SIGN_INJECT_BASE_ENTITLEMENTS = NO." >&2
        exit 1
    fi
    echo "debug:    no get-task-allow"
fi

if [ "$INSTALL" = true ]; then
    echo
    echo "Installing to $INSTALL_DIR/$APP_NAME..."
    rm -rf "${INSTALL_DIR:?}/${APP_NAME:?}"
    cp -R "$APP_PATH" "$INSTALL_DIR/$APP_NAME"
    echo "Installed to $INSTALL_DIR/$APP_NAME"
fi
