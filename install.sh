#!/bin/zsh
# Installs the built app into /Applications and re-registers it with Launch
# Services so it shows up in Launchpad straight away.
#
# The copy in build/ picks up Finder metadata again the moment it lands, because
# this project lives in an iCloud-synced folder. /Applications is not synced, so
# the attributes are cleared at the destination and stay cleared.
set -euo pipefail
cd "$(dirname "$0")"

APP="build/PuraMac.app"
DEST="/Applications/PuraMac.app"
[[ -d "$APP" ]] || { echo "No build found. Run ./build.sh --release first." >&2; exit 1; }

echo "==> Installing to $DEST"
rm -rf "$DEST"
ditto --norsrc --noextattr --noacl "$APP" "$DEST"
xattr -cr "$DEST"

if ! codesign --verify --strict "$DEST" 2>/dev/null; then
    echo "==> Re-signing at the destination"
    codesign --force --options runtime \
        --entitlements Resources/PuraMac.entitlements --sign - "$DEST"
    codesign --verify --strict "$DEST"
fi
echo "    signature verifies"

/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
    -f "$DEST"

echo "Installed. Open it from Launchpad, or: open $DEST"
