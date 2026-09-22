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

# A simulator name is not enough for anything here. Xcode installs several
# devices with the same name across runtimes — this machine has two called
# "iPhone 17 Pro" and three called "iPad Pro 13-inch (M5)" — and both
# xcodebuild and simctl refuse or guess. Every command below therefore takes a
# UDID, resolved once.
udid_for() {
  local found
  found=$(xcrun simctl list devices available | grep -F "$1 (" \
    | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/' | head -1) || true
  if [ -z "$found" ]; then
    echo "No available simulator called '$1'." >&2
    exit 1
  fi
  printf '%s' "$found"
}

build_and_install() {
  local udid="$1"
  xcodebuild build -project Keezly.xcodeproj -scheme Keezly \
    -destination "id=$udid" >/dev/null
  local app
  app=$(find ~/Library/Developer/Xcode/DerivedData/Keezly-*/Build/Products/Debug-iphonesimulator \
    -name "Keezly.app" -maxdepth 1 | head -1)
  xcrun simctl boot "$udid" >/dev/null 2>&1 || true
  xcrun simctl bootstatus "$udid" -b >/dev/null 2>&1 || true
  xcrun simctl install "$udid" "$app"
}

shot() {
  local udid="$1" name="$2"; shift 2
  xcrun simctl terminate "$udid" "$BUNDLE_ID" >/dev/null 2>&1 || true
  xcrun simctl launch "$udid" "$BUNDLE_ID" -KEEZLY_UI_TESTING "$@" >/dev/null
  sleep 5
  xcrun simctl io "$udid" screenshot "$DESTINATION/$name.png" >/dev/null
  echo "  $name"
}

echo "Writing to $DESTINATION:"

IPAD_UDID=$(udid_for "$IPAD")
IPHONE_UDID=$(udid_for "$IPHONE")

build_and_install "$IPAD_UDID"
xcrun simctl status_bar "$IPAD_UDID" override --time "9:41" --batteryLevel 100 >/dev/null 2>&1 || true

# Portrait: the board is width-limited and has the most room to look wrong.
for seats in 2 4 6; do
  shot "$IPAD_UDID" "ipad-portrait-${seats}p" -KEEZLY_SEATS "$seats"
done

# Wide, where the seat panels flank the board and the width is shared.
#
# A *pane*, not a rotation. `simctl` cannot turn a simulator, and the pane the
# app draws into cannot be wider than the screen it is drawn on — the first
# version of this asked a portrait iPad for a 1376-point-wide pane and captured
# the part of it that fitted. So this is a landscape-shaped pane on a portrait
# device: it exercises `wideLayout` at a real size, and it does not exercise
# iPadOS's own rotation, which is what the UI tests are for. The file names say
# which of the two this is.
for seats in 2 4 6; do
  shot "$IPAD_UDID" "ipad-wide-${seats}p" -KEEZLY_SEATS "$seats" -KEEZLY_PANE "1032x774"
done

build_and_install "$IPHONE_UDID"
xcrun simctl status_bar "$IPHONE_UDID" override --time "9:41" --batteryLevel 100 >/dev/null 2>&1 || true
for seats in 2 4 6; do
  shot "$IPHONE_UDID" "iphone-${seats}p" -KEEZLY_SEATS "$seats"
done

echo
echo "For each: are all four corners free, is the border complete, is the"
echo "shadow whole, does the board stand rather than fill?"
