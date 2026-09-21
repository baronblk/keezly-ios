#!/usr/bin/env bash
# Renders every app-icon concept at every size an icon is drawn at, and copies
# the result out of the simulator for a decision to be made from (§79).
#
#   ./scripts/icon-sheet.sh [destination]
#
# The pictures come from the same code that ships, so there is no drawing-
# program original that can drift away from the app.
set -euo pipefail

DESTINATION="${1:-build/icon-sheet}"
DEVICE="${KEEZLY_ICON_DEVICE:-iPad Pro 13-inch (M5)}"
BUNDLE_ID="de.gcng.keezly"

cd "$(dirname "$0")/.."

xcodebuild test \
  -project Keezly.xcodeproj \
  -scheme Keezly \
  -destination "platform=iOS Simulator,name=$DEVICE" \
  -only-testing:KeezlyTests/AppIconTests \
  >/dev/null

CONTAINER=$(xcrun simctl get_app_container "$DEVICE" "$BUNDLE_ID" data)
mkdir -p "$DESTINATION"
cp "$CONTAINER"/Documents/icons/*.png "$DESTINATION"/
echo "Wrote $(ls -1 "$DESTINATION" | wc -l | tr -d ' ') renders to $DESTINATION"
