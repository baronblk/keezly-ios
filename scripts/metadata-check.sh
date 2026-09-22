#!/usr/bin/env bash
# Checks the App Store metadata before anybody tries to upload it (M12).
#
#   ./scripts/metadata-check.sh
#
# Three things go wrong with store metadata, and all three are cheap to catch
# here and expensive to catch later:
#
#   1. A field one character over its limit. App Store Connect refuses the
#      upload and does not say which field.
#   2. A locale that quietly has fewer files than the others, so one language
#      ships with an English description.
#   3. A claim the software cannot keep. Keezly has no server, so nothing about
#      anti-cheat, server-authorised play, leaderboards or online results may
#      appear in any language (DEC-025).
#
# It also fails while a genuinely external field is missing — the support and
# privacy URLs and the copyright holder — because those are facts about a
# person and a domain, not decisions about the app, and a half-filled set must
# not be uploadable by accident. See fastlane/metadata/BLOCKED.md.
set -uo pipefail

cd "$(dirname "$0")/.."
ROOT="fastlane/metadata"
LOCALES=(de-DE nl-NL en-US)
failures=0

fail() { echo "  ✘ $1"; failures=$((failures + 1)); }

# `wc -m` counts characters, which is what App Store Connect counts. `wc -c`
# would count bytes and pass a German description that is actually too long.
length() { LC_ALL=en_US.UTF-8 wc -m < "$1" | tr -d ' '; }

echo "Limits:"
for locale in "${LOCALES[@]}"; do
  for pair in "name.txt:30" "subtitle.txt:30" "promotional_text.txt:170" \
              "keywords.txt:100" "description.txt:4000" "release_notes.txt:4000"; do
    file="$ROOT/$locale/${pair%%:*}"
    limit="${pair##*:}"
    if [ ! -f "$file" ]; then
      fail "$locale/${pair%%:*} is missing"
      continue
    fi
    # The trailing newline is not part of the field.
    count=$(( $(length "$file") - 1 ))
    if [ "$count" -gt "$limit" ]; then
      fail "$locale/${pair%%:*} is $count characters, limit $limit"
    fi
  done
done

echo "Keywords:"
for locale in "${LOCALES[@]}"; do
  file="$ROOT/$locale/keywords.txt"
  [ -f "$file" ] || continue
  # A space after a comma is counted against the limit and buys nothing.
  if grep -q ', ' "$file"; then
    fail "$locale/keywords.txt has a space after a comma — every one costs a character"
  fi
done

echo "Claims the app cannot keep:"
# Matched case-insensitively across all three languages. Each term is here
# because saying it would be untrue, not because it is a bad word.
FORBIDDEN='anti-?cheat|cheat.?proof|server.?authorit|serverautoris|leaderboard|bestenliste|ranglijst|ranglist|game ?center|online.?(multiplayer|match|spiel|partij)|cloud ?(sync|save)'
for locale in "${LOCALES[@]}"; do
  for file in "$ROOT/$locale"/*.txt; do
    [ -f "$file" ] || continue
    if hits=$(grep -inE "$FORBIDDEN" "$file"); then
      fail "$(basename "$(dirname "$file")")/$(basename "$file") claims something untrue:"
      echo "$hits" | sed 's/^/        /'
    fi
  done
done

echo "Fields that are somebody else's to supply:"
for file in "$ROOT/copyright.txt"; do
  [ -f "$file" ] || fail "$(basename "$file") is missing — see $ROOT/BLOCKED.md (MAN-04)"
done
for locale in "${LOCALES[@]}"; do
  for name in support_url privacy_url; do
    [ -f "$ROOT/$locale/$name.txt" ] || fail "$locale/$name.txt is missing — see $ROOT/BLOCKED.md (MAN-04)"
  done
done

echo
if [ "$failures" -eq 0 ]; then
  echo "Metadata is complete and within every limit."
  exit 0
fi
echo "$failures problem(s). The upload would be refused or would say something untrue."
exit 1
