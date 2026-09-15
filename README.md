# PuraMac

A native macOS cleanup and system-care app. PuraMac shows what is using your
disk and memory, finds space you can safely reclaim, and moves it to the
Trash only when you say so.

## Safety model

This is the part that actually matters in an app that deletes things:

- **Every removal is validated twice** — once when it is offered for
  selection, and again immediately before it is removed — by `PathGuard`,
  which refuses anything outside your home folder, your home folder itself,
  and a fixed list of folders holding irreplaceable data (Keychains, iCloud
  Drive, Mail, Messages, Photos, app containers, preferences, ...). Symlinks
  are resolved before the check, so a cache folder cannot be used to reach
  outside the sandbox PuraMac holds itself to.
- **Nothing is permanently deleted except the Trash itself.** Every other
  category is moved to `~/.Trash` via `FileManager.trashItem`, so it can be
  put back — PuraMac's History pane does exactly that.
- **What you see is what gets removed.** A scan records the exact paths it
  found; cleaning replays that list rather than re-reading the folder, so
  nothing created after the scan and before you click Clean is touched.
- **The review sheet lists real paths, not a count**, before every removal.
- **The uninstaller** is the one place PuraMac reaches into `~/Library`
  subfolders the general cleaner refuses — and only for a leftover whose own
  filename identifies the app being removed, in a folder on an explicit
  allowlist. The folders themselves (`~/Library/Preferences`, `.../Caches`,
  ...) can never be selected.
- **The AI assistant only ever sees system totals and, if you ask for an
  analysis, category names and sizes from your last scan.** No file name, no
  path, no file content is ever sent anywhere.

All of this is covered by an automated test suite (`swift test`), including
a symlink-escape attempt and a check that emptying the Trash cannot delete
anything outside `~/.Trash`.

## Features

- **Dashboard** — disk, memory (with real kernel pressure, not a guess),
  CPU, battery, thermal state, macOS version and uptime.
- **Smart Clean** — scans caches, logs, Xcode DerivedData and Simulator
  caches, npm and Homebrew caches, old Downloads, and the Trash. Each
  category is labelled Safe / Worth a look / Be careful, shows its largest
  items, and can be expanded before you decide.
- **Large Files** — the biggest files across your personal folders, with
  Quick Look, size, and age filters.
- **Duplicates** — finds byte-identical files (size, then a partial
  fingerprint, then a full hash — never a false positive), and always
  leaves at least one copy of every file.
- **Uninstaller** — removes an app together with the caches, preferences,
  containers and login items it leaves behind, all in one reviewed batch.
- **Login Items** — lists what starts automatically and lets you disable
  one, reversibly.
- **AI Assistant** — chat about this Mac over OpenRouter, with a live,
  fetched model catalogue rather than a hardcoded list. The API key lives in
  your macOS keychain, never on disk.
- **History** — every cleanup PuraMac has performed, with a Put Back button
  for anything still sitting in the Trash.
- **Menu bar extra** — disk and memory at a glance, with a one-click Smart
  Clean scan.

## Requirements

macOS 14 or later, Swift 6 toolchain (Xcode 16+).

## Build

```bash
./build.sh --release
```

This runs the full test suite, builds `build/PuraMac.app`, and ad-hoc signs
it. Building happens outside this repository's directory (it uses a scratch
path under `$TMPDIR`) because Finder metadata on files inside an
iCloud-synced folder makes `codesign` refuse the bundle otherwise.

To sign for distribution:

```bash
./build.sh --release --sign "Developer ID Application: Your Name (TEAMID)"
./build.sh --release --sign "Developer ID Application: Your Name (TEAMID)" \
           --notarize "your-keychain-profile"
```

## Install

```bash
rm -rf /Applications/PuraMac.app
cp -R build/PuraMac.app /Applications/PuraMac.app
open /Applications/PuraMac.app
```

## Project layout

```
Sources/PuraMacCore/     Pure-logic package: scanning, the safety guard,
                          removal, system stats, the AI client. No AppKit
                          imports — fully unit-testable in isolation.
Sources/PuraMacApp/       SwiftUI app: views, view models, the app shell.
Tests/PuraMacCoreTests/   Swift Testing suite for everything in Core.
Resources/                Info.plist, entitlements, app icon.
```

## Development

```bash
swift build            # debug build
swift test              # run the test suite
swift run PuraMac        # run without packaging an .app
```

## License

MIT, Mike Shobes 2026.
