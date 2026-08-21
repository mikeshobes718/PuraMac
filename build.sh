#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")"

if [[ ! -f AppIcon.icns ]]; then
    swiftc -o /tmp/pm-make-icon make-icon.swift -framework AppKit
    /tmp/pm-make-icon AppIcon.iconset
    iconutil -c icns AppIcon.iconset -o AppIcon.icns
    rm -rf AppIcon.iconset /tmp/pm-make-icon
fi

mkdir -p build/PuraMac.app/Contents/MacOS build/PuraMac.app/Contents/Resources
swiftc -O -o build/PuraMac.app/Contents/MacOS/PuraMac \
    main.swift AppDelegate.swift SystemStats.swift ScanEngine.swift OpenRouterClient.swift \
    Views.swift SmartCleanViews.swift LargeFilesViews.swift AssistantViews.swift SettingsAndLoginViews.swift \
    -framework AppKit -framework ServiceManagement -framework UserNotifications
cp Info.plist build/PuraMac.app/Contents/Info.plist
cp AppIcon.icns build/PuraMac.app/Contents/Resources/AppIcon.icns
xattr -cr build/PuraMac.app
codesign --force --sign - build/PuraMac.app
xattr -cr build/PuraMac.app

echo "Built: $(pwd)/build/PuraMac.app"
