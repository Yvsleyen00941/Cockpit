#!/bin/zsh
# Builds a signed Release copy of ControlCenter Helper and installs it in
# /Applications — the only place it registers itself to launch at login.
# A properly signed build keeps the same identity across updates, so macOS
# doesn't ask again for Keychain access or permissions after each rebuild.
#
#   Tools/install-helper.sh
set -euo pipefail
cd "$(dirname "$0")/.."

DERIVED=build/ReleaseDerivedData
APP_NAME="ControlCenter Helper.app"
LOG=$(mktemp -t cc-helper-build)

echo "Building ControlCenter Helper (Release)…"
if ! xcodebuild -project ControlCenter.xcodeproj -scheme ControlCenterHelper -configuration Release \
    -destination 'platform=macOS' -derivedDataPath "$DERIVED" build >"$LOG" 2>&1; then
    grep -E "error:" "$LOG" | head -20 || true
    echo "Build failed. Full log: $LOG"
    exit 1
fi

# Quit a running helper (it says goodbye to connected iPads first).
HELPER_PROCESS="ControlCenter Helper.app/Contents/MacOS/ControlCenter Helper"
if pgrep -fq "$HELPER_PROCESS"; then
    osascript -e 'quit app id "be.yorben.controlcenter.helper"' >/dev/null 2>&1 || true
    for _ in {1..20}; do
        pgrep -fq "$HELPER_PROCESS" || break
        sleep 0.25
    done
fi

rm -rf "/Applications/$APP_NAME"
cp -R "$DERIVED/Build/Products/Release/$APP_NAME" /Applications/
open "/Applications/$APP_NAME"
echo "Installed /Applications/$APP_NAME. It's in your menu bar and starts at login."
