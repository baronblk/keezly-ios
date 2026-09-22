#!/usr/bin/env bash
# Captures the board in every configuration and orientation that matters, so
# its placement in the frame can be judged rather than assumed (§43, §87).
#
#   ./scripts/board-review.sh [destination]
#
# Written after the board was found pressed into its container: its rounded
# corners, its border ornament and its shadow were all being scaled past the
# edge of the view, because the bounds a view fits were the *playing squares*
# rather than the panel that is actually drawn.
set -euo pipefail

DESTINATION="${1:-build/board-review}"
IPAD="${KEEZLY_IPAD:-iPad Pro 13-inch (M5)}"
IPHONE="${KEEZLY_IPHONE:-iPhone 17 Pro}"
BUNDLE_ID="de.gcng.keezly"

cd "$(dirname "$0")/.."
mkdir -p "$DESTINATION"

# A simulator name is not always enough for xcodebuild — several runtimes can
# carry the same one — so it is resolved to a UDID first.
udid_for() {
  xcrun simctl list devices available \
    | grep -F "$1 (" | head -1 | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/'
}

build_and_install() {
  local device="$1"
  local udid
  udid=$(udid_for "$device")
  xcodebuild build -project Keezly.xcodeproj -scheme Keezly \
    -destination "id=$udid" >/dev/null
  local app
  app=$(find ~/Library/Developer/Xcode/DerivedData/Keezly-*/Build/Products/Debug-iphonesimulator \
    -name "Keezly.app" -maxdepth 1 | head -1)
  xcrun simctl boot "$device" >/dev/null 2>&1 || true
  xcrun simctl install "$device" "$app"
}

shot() {
  local device="$1" name="$2"; shift 2
  xcrun simctl terminate "$device" "$BUNDLE_ID" >/dev/null 2>&1 || true
  xcrun simctl launch "$device" "$BUNDLE_ID" -KEEZLY_UI_TESTING "$@" >/dev/null
  sleep 5
  xcrun simctl io "$device" screenshot "$DESTINATION/$name.png" >/dev/null 2>&1
  echo "  $name"
}

echo "Writing to $DESTINATION:"

build_and_install "$IPAD"
xcrun simctl status_bar "$IPAD" override --time "9:41" --batteryLevel 100 >/dev/null 2>&1 || true

# Portrait: the board is width-limited and has the most room to look wrong.
for seats in 2 4 6; do
  shot "$IPAD" "ipad-portrait-${seats}p" -KEEZLY_SEATS "$seats"
done

# Landscape, where the seat panels flank the board and the width is shared.
xcrun simctl io "$IPAD" enumerate >/dev/null 2>&1 || true
for seats in 2 4 6; do
  shot "$IPAD" "ipad-landscape-${seats}p" -KEEZLY_SEATS "$seats" -KEEZLY_PANE "1376x1032"
done

build_and_install "$IPHONE"
xcrun simctl status_bar "$IPHONE" override --time "9:41" --batteryLevel 100 >/dev/null 2>&1 || true
for seats in 2 4 6; do
  shot "$IPHONE" "iphone-${seats}p" -KEEZLY_SEATS "$seats"
done

echo
echo "For each: are all four corners free, is the border complete, is the"
echo "shadow whole, does the board stand rather than fill?"
