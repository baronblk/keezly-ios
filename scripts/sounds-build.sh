#!/usr/bin/env bash
# Generates Keezly's sound set and installs it into the app (§77, M8.5).
#
#   ./scripts/sounds-build.sh
#
# The audio is synthesised by Tools/soundforge.py, so its provenance is the
# source code that made it: nothing sampled, nothing downloaded, no licence to
# wonder about. Tools/soundcheck.py then measures what a machine can measure
# about a sound, and refuses the build if anything clips, sustains or drifts.
set -euo pipefail

cd "$(dirname "$0")/.."
WORK="build/sounds"
TARGET="App/Keezly/Sounds"

python3 Tools/soundforge.py "$WORK"
echo
python3 Tools/soundcheck.py "$WORK"
echo

mkdir -p "$TARGET"
for wav in "$WORK"/*.wav; do
  name=$(basename "$wav" .wav)
  # CAF with little-endian 16-bit PCM: no decode cost on a cue that has to
  # land the instant a piece goes down.
  afconvert -f caff -d LEI16@44100 "$wav" "$TARGET/$name.caf"
done

echo "Installed $(ls -1 "$TARGET"/*.caf | wc -l | tr -d ' ') cues into $TARGET:"
ls -lh "$TARGET"/*.caf | awk '{printf "  %-28s %s\n", $9, $5}'
