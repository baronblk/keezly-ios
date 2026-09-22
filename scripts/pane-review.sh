#!/usr/bin/env bash
# Draws the app at every pane size an iPad can hand it, and captures each
# (§4, M4.3).
#
#   ./scripts/pane-review.sh [destination]
#
# Split View gives a third, a half or two thirds of the width; Stage Manager
# gives whatever the window has been dragged to. None of those sizes can be
# reached from simctl, and driving the dock by gesture is not reliable enough
# to base a check on — so the app is drawn into a pane of exactly that size.
#
# This verifies **the app's layout at those sizes**, which is where the risk
# is. It does not exercise iPadOS's own multitasking machinery.
set -euo pipefail

DESTINATION="${1:-build/pane-review}"
DEVICE="${KEEZLY_PANE_DEVICE:-iPad Pro 13-inch (M5)}"
BUNDLE_ID="de.gcng.keezly"

cd "$(dirname "$0")/.."
mkdir -p "$DESTINATION"

xcodebuild build -project Keezly.xcodeproj -scheme Keezly \
  -destination "platform=iOS Simulator,name=$DEVICE" >/dev/null
APP=$(find ~/Library/Developer/Xcode/DerivedData/Keezly-*/Build/Products/Debug-iphonesimulator \
  -name "Keezly.app" -maxdepth 1 | head -1)
xcrun simctl boot "$DEVICE" >/dev/null 2>&1 || true
xcrun simctl install "$DEVICE" "$APP"

pane() {
  local name="$1" size="$2"; shift 2
  xcrun simctl terminate "$DEVICE" "$BUNDLE_ID" >/dev/null 2>&1 || true
  xcrun simctl launch "$DEVICE" "$BUNDLE_ID" \
    -KEEZLY_UI_TESTING -KEEZLY_PANE "$size" "$@" >/dev/null
  sleep 5
  xcrun simctl io "$DEVICE" screenshot "$DESTINATION/$name.png" >/dev/null 2>&1
  echo "  $name ($size)"
}

echo "Writing to $DESTINATION:"
# Split View, portrait: a third, a half, two thirds, and the whole thing.
pane "split-third"       "375x1376"  -KEEZLY_SEATS 6
pane "split-half"        "507x1376"  -KEEZLY_SEATS 6
pane "split-two-thirds"  "639x1376"  -KEEZLY_SEATS 6
pane "full-portrait"     "1032x1376" -KEEZLY_SEATS 6

# Split View, landscape.
pane "split-third-land"  "507x1032"  -KEEZLY_SEATS 6
pane "split-half-land"   "678x1032"  -KEEZLY_SEATS 6
pane "full-landscape"    "1376x1032" -KEEZLY_SEATS 6

# Stage Manager: a window dragged to something nobody designed for.
pane "stage-small"       "620x520"   -KEEZLY_SEATS 4
pane "stage-tall"        "540x900"   -KEEZLY_SEATS 4
pane "stage-wide"        "980x620"   -KEEZLY_SEATS 4

# The menu, which has to survive the same widths.
pane "menu-third"        "375x1376"
pane "menu-stage-small"  "620x520"
