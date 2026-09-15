#!/bin/zsh
# Builds PuraMac.app from the SwiftPM package.
#
#   ./build.sh                 debug-ish local build, ad-hoc signed
#   ./build.sh --release       optimised build, ad-hoc signed
#   ./build.sh --sign "Developer ID Application: Name (TEAMID)"
#   ./build.sh --sign "..." --notarize "keychain-profile"
set -euo pipefail
cd "$(dirname "$0")"

VERSION="2.0.0"
BUILD="$(date +%Y%m%d%H%M)"
CONFIG="release"
IDENTITY="-"
NOTARY_PROFILE=""

# The package lives inside an iCloud-synced folder, whose Finder metadata makes
# codesign refuse the bundle. Building outside it avoids that entirely.
SCRATCH="${TMPDIR:-/tmp}/puramac-build"
APP="build/PuraMac.app"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --release) CONFIG="release"; shift ;;
        --debug) CONFIG="debug"; shift ;;
        --sign) IDENTITY="$2"; shift 2 ;;
        --notarize) NOTARY_PROFILE="$2"; shift 2 ;;
        *) echo "Unknown option: $1" >&2; exit 2 ;;
    esac
done

echo "==> Building ($CONFIG)"
swift build -c "$CONFIG" --scratch-path "$SCRATCH" --product PuraMac

echo "==> Running tests"
swift test --scratch-path "$SCRATCH"

# Assembled and signed inside the scratch path, never in the repo directory:
# this folder is iCloud-synced, and Finder re-attaches com.apple.FinderInfo
# between an xattr clear and codesign, which makes signing fail at random.
STAGE="$SCRATCH/stage/PuraMac.app"

echo "==> Assembling $STAGE"
rm -rf "$STAGE"
mkdir -p "$STAGE/Contents/MacOS" "$STAGE/Contents/Resources"
cp "$SCRATCH/$CONFIG/PuraMac" "$STAGE/Contents/MacOS/PuraMac"

sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD/" \
    Resources/Info.plist > "$STAGE/Contents/Info.plist"

if [[ ! -f Resources/AppIcon.icns ]]; then
    echo "==> Generating app icon"
    swiftc -O -o "$SCRATCH/make-icon" Resources/make-icon.swift -framework AppKit -framework CoreImage
    "$SCRATCH/make-icon" "$SCRATCH/AppIcon.iconset"
    iconutil -c icns "$SCRATCH/AppIcon.iconset" -o Resources/AppIcon.icns
fi
cp Resources/AppIcon.icns "$STAGE/Contents/Resources/AppIcon.icns"

printf 'APPL????' > "$STAGE/Contents/PkgInfo"
xattr -cr "$STAGE"

echo "==> Signing with identity: $IDENTITY"
if [[ "$IDENTITY" == "-" ]]; then
    # An ad-hoc signature cannot carry a secure timestamp.
    SIGN_ARGS=(--force --options runtime
               --entitlements Resources/PuraMac.entitlements
               --sign "-")
    echo "    (ad-hoc: fine for local use, not distributable)"
else
    SIGN_ARGS=(--force --timestamp --options runtime
               --entitlements Resources/PuraMac.entitlements
               --sign "$IDENTITY")
fi
codesign "${SIGN_ARGS[@]}" "$STAGE"
codesign --verify --strict --verbose=2 "$STAGE"

# ditto without xattrs keeps the copy clean, so the signature still verifies
# even though the destination lives in the synced folder.
echo "==> Copying to $APP"
rm -rf "$APP"
mkdir -p build
ditto --norsrc --noextattr --noacl "$STAGE" "$APP"
# Only advisory: iCloud re-attaches metadata here immediately. install.sh
# clears it at /Applications, which is not synced.
codesign --verify --strict "$APP" 2>/dev/null \
    && echo "    signature verifies in build/" \
    || echo "    (build/ copy carries Finder metadata; install.sh handles it)"

if [[ -n "$NOTARY_PROFILE" ]]; then
    echo "==> Notarizing"
    ZIP="build/PuraMac-$VERSION.zip"
    ditto -c -k --keepParent "$STAGE" "$ZIP"
    xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$STAGE"
    ditto --norsrc --noextattr --noacl "$STAGE" "$APP"
    xcrun stapler validate "$STAGE"
    echo "    Notarized and stapled."
fi

echo
echo "Built $(pwd)/$APP  (version $VERSION build $BUILD)"
echo "Install:  ./install.sh"
