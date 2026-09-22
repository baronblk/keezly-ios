#!/usr/bin/env bash
# Renders the board in a handful of real states and writes each one twice:
# in colour, and with the colour taken out (§42, §53, ISS-016).
#
#   ./scripts/grayscale-review.sh [destination]
#
# The question this answers is not "does the board look nice in grey" but
# "does it still say the same things". Anything that is only a hue disappears
# in the right-hand column.
#
# The measurable half of the same question lives in `GrayscaleTests`, which
# compares two renders numerically instead of by eye.
set -euo pipefail

DESTINATION="${1:-build/grayscale-review}"
DEVICE="${KEEZLY_GRAYSCALE_DEVICE:-iPad Pro 13-inch (M5)}"
BUNDLE_ID="de.gcng.keezly"

cd "$(dirname "$0")/.."
mkdir -p "$DESTINATION"

xcodebuild build -project Keezly.xcodeproj -scheme Keezly \
  -destination "platform=iOS Simulator,name=$DEVICE" >/dev/null
APP=$(find ~/Library/Developer/Xcode/DerivedData/Keezly-*/Build/Products/Debug-iphonesimulator \
  -name "Keezly.app" -maxdepth 1 | head -1)

xcrun simctl boot "$DEVICE" >/dev/null 2>&1 || true
xcrun simctl install "$DEVICE" "$APP"

# Each state is a name and the launch arguments that reach it.
capture() {
  local name="$1"; shift
  xcrun simctl terminate "$DEVICE" "$BUNDLE_ID" >/dev/null 2>&1 || true
  xcrun simctl launch "$DEVICE" "$BUNDLE_ID" -KEEZLY_UI_TESTING "$@" >/dev/null
  sleep 5
  xcrun simctl io "$DEVICE" screenshot "$DESTINATION/$name.png" >/dev/null 2>&1
  python3 - "$DESTINATION/$name.png" <<'PY'
import sys
from PIL import Image, ImageOps
source = sys.argv[1]
image = Image.open(source).convert("RGB")
grey = ImageOps.grayscale(image).convert("RGB")
pair = Image.new("RGB", (image.width, image.height * 2 + 24), (245, 245, 247))
pair.paste(image, (0, 0))
pair.paste(grey, (0, image.height + 24))
pair.save(source.replace(".png", "-pair.png"))
grey.save(source.replace(".png", "-grey.png"))
PY
  echo "  $name"
}

echo "Writing to $DESTINATION:"
capture "four-players"
capture "six-players" -KEEZLY_SEATS 6
capture "two-players" -KEEZLY_SEATS 2
capture "jack-selectable" -KEEZLY_OPENING jack -KEEZLY_FOCUS first
capture "seven-split" -KEEZLY_OPENING seven -KEEZLY_FOCUS first
capture "free-for-all" -KEEZLY_TEAMS free -KEEZLY_SEATS 6

echo
echo "Each state is written three ways: colour, greyscale, and the two stacked."
echo "Look for anything in the colour image that is not also a shape in the grey one."
