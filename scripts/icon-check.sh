#!/usr/bin/env bash
# Fails if the committed app icon no longer matches the code it is drawn from
# (§79).
#
#   ./scripts/icon-check.sh
#
# The icon is code. That is only true as long as the PNGs in the asset
# catalogue are what that code renders — otherwise the "editable source" is a
# file nobody re-runs. This re-renders and compares.
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
STATUS=0
for name in AppIcon-1024 AppIcon-dark-1024 AppIcon-tinted-1024; do
  if ! cmp -s "$CONTAINER/Documents/icons/$name.png" "$TARGET/$name.png"; then
    echo "DRIFT: $name.png in the asset catalogue is not what AppIconArtwork renders."
    STATUS=1
  fi
done

if [ "$STATUS" -eq 0 ]; then
  echo "The app icon matches its source."
else
  echo "Run ./scripts/icon-install.sh to bring them back into line."
fi
exit "$STATUS"
