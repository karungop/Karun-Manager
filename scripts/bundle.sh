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
# iCloud sync needs a provisioning profile that grants the iCloud entitlements (README → iCloud sync).
# Without one the app is signed without them and keeps tasks on this Mac only.
entitlements=()
if [ -n "${KARUNMANAGER_PROFILE:-}" ]; then
  [ -n "$identity" ] || { echo "KARUNMANAGER_PROFILE needs an Apple Development or Developer ID certificate" >&2; exit 1; }
  profile_plist="$(mktemp)"
  security cms -D -i "$KARUNMANAGER_PROFILE" > "$profile_plist"
  team_id="$(plutil -extract TeamIdentifier.0 raw "$profile_plist")"
  aps="$(plutil -extract Entitlements.com\\.apple\\.developer\\.aps-environment raw "$profile_plist" 2>/dev/null || echo development)"
  rm -f "$profile_plist"
  cp "$KARUNMANAGER_PROFILE" "$app/Contents/embedded.provisionprofile"
  sed -e "s/TEAM_ID/$team_id/g" -e "s/APS_ENVIRONMENT/$aps/g" Resources/KarunManager.entitlements > "build/KarunManager.entitlements"
  entitlements=(--entitlements build/KarunManager.entitlements --options runtime)
fi
codesign --force --sign "${identity:--}" ${entitlements[@]+"${entitlements[@]}"} "$app" >/dev/null
echo "Signed with: ${identity:-ad-hoc (no developer certificate; notifications fall back to in-app banners)}"
if [ -n "${KARUNMANAGER_PROFILE:-}" ]; then
  echo "iCloud sync: on (team $team_id, push environment $aps)"
else
  echo "iCloud sync: off (set KARUNMANAGER_PROFILE to a provisioning profile to enable it)"
fi

echo "Built $app"
