# PuraMac

PuraMac is a macOS cleanup and system care app. It shows what is eating your disk and memory, finds space you can reclaim, and moves it to the Trash when you say so. It never deletes anything outright and never touches anything outside your home folder.

## Features

- Dashboard: free, used and total disk on the boot volume, memory pressure, CPU usage, battery status, macOS version and uptime, with a refresh button.
- Smart Clean: scans user level caches, logs, the Trash, Xcode DerivedData, iOS DeviceSupport, the npm cache, hidden user caches, the Homebrew cache and Downloads files older than 30 days. Shows per category sizes, lets you pick categories, shows a review sheet with exactly what will move, then moves everything to the Trash with a summary and a notification when done.
- Large Files: finds the top 50 files over 100 MB in your user folders (Desktop, Documents, Downloads, Movies, Music, Pictures plus Library caches, logs and Developer). Select files and move them to the Trash after a confirmation.
- Login Items: read-only list of your login items with a shortcut to System Settings. PuraMac does not modify them.
- AI Assistant: chat about your Mac with system context included, plus an Analyze my scan button that sends only category names and sizes (never file paths or personal data) to OpenRouter for cleanup advice. Model picker with six models, default google/gemini-3.7-flash.
- Notifications: scan complete, cleanup complete with space freed, and a low disk warning when free space drops below 10 percent, rate limited to once per day.
- Settings: automatic disk checks, cleanup notifications, start at login, and the default AI model. All stored in UserDefaults.

## Safety model

- Scans only user level roots inside /Users/you. No system directories are ever touched.
- Removal always goes through the macOS Trash (FileManager trashItem) so every change is undoable.
- Nothing is removed without a review sheet showing counts, sizes and sample paths first.
- The Homebrew cache is measured only, brew cleanup is never run.
- The AI never receives file paths, file names or personal data, only category names and sizes when you ask for a scan analysis.
- The API key is read at runtime from /Users/mike/Documents/Keys/.env and is never stored in the app.

## Build

Requires macOS 13 or newer and Xcode command line tools.

```bash
cd PuraMac
./build.sh
```

The script generates AppIcon.icns if missing, compiles all Swift files with swiftc, assembles PuraMac.app under build/, and ad-hoc codesigns it.

## Install

```bash
rm -rf /Applications/PuraMac.app
cp -R build/PuraMac.app /Applications/PuraMac.app
open /Applications/PuraMac.app
```

On first launch the app asks for notification permission so it can tell you when scans and cleanups finish.

## License

MIT, Mike Shobes 2026.
