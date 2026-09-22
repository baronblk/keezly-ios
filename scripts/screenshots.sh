#!/usr/bin/env bash
# Produces the App Store screenshot set, as files on disk (M11, ISS-012).
#
#   ./scripts/screenshots.sh [destination]
#
# The captures themselves are taken by `DesignReviewScreenshots`, which already
# settled the hard part: `XCUIScreen.main.screenshot()` rather than
# `app.screenshot()`, because the application element's capture on a rotated
# device comes back on its side with the remainder filled in black. There is no
# crop constant here and there must never be one — the black band was the wrong
# capture source, not a margin to trim (ISS-009, ISS-012).
#
# What this adds is the half that was missing: the images come out of the result
# bundle and land in a directory, one per device and locale, where
# `screenshots-verify.py` can check them as files rather than as attachments
# nobody opens.
set -euo pipefail

DESTINATION="${1:-build/screenshots}"
IPAD="${KEEZLY_IPAD:-iPad Pro 13-inch (M5)}"
# A Pro Max, not a Pro. App Store Connect wants the 6.9-inch set at 1290 points
# across or better; an iPhone 17 Pro captures at 1206 and the upload is refused.
# `screenshots-verify.py` caught exactly that, which is the whole reason it
# measures the short edge rather than the long one.
IPHONE="${KEEZLY_IPHONE:-iPhone 17 Pro Max}"
SUITE="KeezlyUITests/DesignReviewScreenshots"

# App Store Connect wants de-DE, nl-NL and en. The language and region are
# given to xcodebuild rather than to the app, so the whole process — including
# anything the system draws — comes up in that locale.
LOCALES=("de:DE" "nl:NL" "en:US")

cd "$(dirname "$0")/.."
rm -rf "$DESTINATION"
mkdir -p "$DESTINATION"

# Several simulators share a name across runtimes, so a name is never enough.
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

capture() {
  local label="$1" udid="$2" language="$3" region="$4"
  local bundle="build/xcresult/${label}.xcresult"
  local out="$DESTINATION/${label}"

  rm -rf "$bundle"
  mkdir -p "$(dirname "$bundle")" "$out"

  echo "  $label"
  xcodebuild test \
    -project Keezly.xcodeproj -scheme Keezly \
    -destination "id=$udid" \
    -only-testing:"$SUITE" \
    -resultBundlePath "$bundle" \
    -testLanguage "$language" -testRegion "$region" \
    >"build/xcresult/${label}.log" 2>&1 \
    || { echo "    FAILED — see build/xcresult/${label}.log" >&2; return 1; }

  xcrun xcresulttool export attachments \
    --path "$bundle" --output-path "$out" >/dev/null

  # The exporter names files by attachment id and records the real names in a
  # manifest. Rename them, because a directory of UUIDs is not a screenshot set
  # anybody can review or upload.
  python3 scripts/screenshots-name.py "$out"
}

IPAD_UDID=$(udid_for "$IPAD")
IPHONE_UDID=$(udid_for "$IPHONE")

echo "Writing to $DESTINATION:"
failed=0
for pair in "${LOCALES[@]}"; do
  language="${pair%%:*}"
  region="${pair##*:}"
  capture "ipad-${language}" "$IPAD_UDID" "$language" "$region" || failed=1
  capture "iphone-${language}" "$IPHONE_UDID" "$language" "$region" || failed=1
done

echo
python3 scripts/screenshots-verify.py "$DESTINATION" || failed=1
exit "$failed"
