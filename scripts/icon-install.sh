#!/usr/bin/env bash
# Renders the chosen app-icon concept and installs the three 1024 masters into
# the asset catalogue (§79).
#
#   ./scripts/icon-install.sh
#
# The icon is code, not an exported file: this regenerates it, so the shipped
# artwork can never drift away from the source it was drawn from.
set -euo pipefail

DEVICE="${KEEZLY_ICON_DEVICE:-iPad Pro 13-inch (M5)}"
BUNDLE_ID="de.gcng.keezly"

cd "$(dirname "$0")/.."
TARGET="App/Keezly/Assets.xcassets/AppIcon.appiconset"

xcodebuild test \
  -project Keezly.xcodeproj \
  -scheme Keezly \
  -destination "platform=iOS Simulator,name=$DEVICE" \
  -only-testing:KeezlyTests/AppIconTests \
  >/dev/null

CONTAINER=$(xcrun simctl get_app_container "$DEVICE" "$BUNDLE_ID" data)
for name in AppIcon-1024 AppIcon-dark-1024 AppIcon-tinted-1024; do
  cp "$CONTAINER/Documents/icons/$name.png" "$TARGET/$name.png"
done
echo "Installed three 1024 masters into $TARGET"
