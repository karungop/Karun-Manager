#!/usr/bin/env bash
# Builds the SwiftPM executable and wraps it in build/KarunManager.app (LSUIElement menu bar app).
# Usage: scripts/bundle.sh [debug|release]
set -euo pipefail
cd "$(dirname "$0")/.."

config="${1:-release}"
swift build -c "$config"
bin_path="$(swift build -c "$config" --show-bin-path)"

app="build/KarunManager.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
cp "$bin_path/KarunManager" "$app/Contents/MacOS/KarunManager"
cp Resources/Info.plist "$app/Contents/Info.plist"
[ -f Resources/AppIcon.icns ] || swift scripts/make-icon.swift Resources
mkdir -p "$app/Contents/Resources"
cp Resources/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
# Prefer a real signing identity: macOS only grants system notifications to properly signed apps.
# (Free: sign in to Xcode with an Apple ID to get an "Apple Development" certificate.)
identity="$(security find-identity -v -p codesigning 2>/dev/null \
  | awk -F'"' '/Apple Development|Developer ID Application/ { print $2; exit }')"
codesign --force --sign "${identity:--}" "$app" >/dev/null
echo "Signed with: ${identity:-ad-hoc (no developer certificate; notifications fall back to in-app banners)}"

echo "Built $app"
