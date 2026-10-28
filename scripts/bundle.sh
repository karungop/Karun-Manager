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
codesign --force --sign - "$app" >/dev/null

echo "Built $app"
