#!/usr/bin/env bash
# Checks the String Catalog before anything ships (§54, M10).
#
#   ./scripts/strings-check.sh
#
# Runs on the catalogue itself rather than on a built app, so it needs no
# simulator and can gate a pull request.
set -euo pipefail
cd "$(dirname "$0")/.."

python3 - "$@" <<'PY'
import json, re, sys, pathlib

CATALOGUE = pathlib.Path("App/Keezly/Localizable.xcstrings")
LANGUAGES = ("en", "de", "nl")
# %@ %lld %d %f, and their positional forms %1$@ %2$lld …
SPECIFIER = re.compile(r"%(?:(\d+)\$)?([@a-zA-Z]+)")

catalogue = json.loads(CATALOGUE.read_text())
problems = []

def arguments(text):
    """Which arguments a string consumes, and of what type.

    Keyed by argument position rather than by where it appears, because a
    translation is *expected* to reorder them — German and Dutch put the
    colour after the piece, which is the whole point of %1$@. A string may
    also use one argument twice (\"%1$lld. %1$lld squares forward\"), which is
    only legal with positions: written as two bare %lld it would read past the
    end of the argument list."""
    found = {}
    position = 0
    for index, kind in SPECIFIER.findall(text):
        if not kind:
            continue
        if index:
            slot = int(index)
        else:
            position += 1
            slot = position
        found[slot] = kind
    return found

for key, entry in sorted(catalogue["strings"].items()):
    localisations = entry.get("localizations", {})
    for language in LANGUAGES:
        unit = localisations.get(language, {}).get("stringUnit")
        if unit is None:
            problems.append(f"{key}: missing {language}")
            continue
        state = unit.get("state")
        if state != "translated":
            problems.append(f"{key}: {language} is '{state}', not translated")
        value = unit.get("value", "")
        if not value.strip():
            problems.append(f"{key}: {language} is empty")
        if value == key:
            problems.append(f"{key}: {language} is the key itself")

    # A translation that drops or invents a placeholder does not merely read
    # badly: it formats the wrong value, or crashes.
    reference = localisations.get("en", {}).get("stringUnit", {}).get("value", "")
    expected = arguments(reference)
    for language in ("de", "nl"):
        value = localisations.get(language, {}).get("stringUnit", {}).get("value", "")
        if arguments(value) != expected:
            problems.append(
                f"{key}: {language} takes {arguments(value)}, en takes {expected}"
            )

    # The key carries the call site's arguments, so it says how many the
    # code actually passes. A text that consumes more than that reads past the
    # end of the argument list.
    from_key = arguments(key)
    if from_key and len(expected) > len(from_key):
        problems.append(
            f"{key}: the text uses {len(expected)} arguments, the call site passes {len(from_key)}"
        )

# --- terminology -------------------------------------------------------------
#
# One word per thing, per language. Keezen vocabulary is settled here so that
# drift is a failing check rather than a proofreading job: the Dutch text had
# been saying both "huis" and "doelvakje" for the home lane, which is the
# sound of a translation rather than of somebody who plays the game (§55, M10.5).
VOCABULARY = {
    "de": [
        (r"\bSpielstein\w*\b", "Figur", "a piece is a Figur"),
        (r"\bHaus\b", "Ziel", "the home lane is das Ziel; Hausregel is a different word"),
    ],
    "nl": [
        (r"\bdoel\w*\b", "huis", "the home lane is het huis, not het doel"),
        (r"\bstuk(ken)?\b", "pion", "a piece is a pion"),
        (r"\bthuis\b", "binnen", "a piece that has arrived is binnen"),
    ],
}

for key, entry in sorted(catalogue["strings"].items()):
    for language, rules in VOCABULARY.items():
        value = entry.get("localizations", {}).get(language, {}).get("stringUnit", {}).get("value", "")
        for pattern, preferred, why in rules:
            if re.search(pattern, value, re.IGNORECASE):
                problems.append(f"{key}: {language} should say '{preferred}' — {why}")

# --- the code and the catalogue agree ---------------------------------------
#
# A key the code asks for and the catalogue does not have is shown to the
# player as the key itself — the exact failure the rulebook shipped with for
# one build. This catches it without running anything.
KEY = re.compile(r'"([a-z][A-Za-z0-9]*(?:\.[A-Za-z0-9]+)+)(?:(\s+%[^"]*)?"|\s+\\\()')
# Keys assembled entirely at runtime, where the source shows only a prefix.
BUILT_AT_RUNTIME = ("rank.", "rules.", "seat.", "achievement.", "lesson.", "replay.speed.")

def is_noise(text, match, line):
    """Dotted lowercase strings that are not text anybody reads."""
    # An SF Symbol name, read from the argument it is passed to rather than
    # from the whole line — a Label carries a key *and* a symbol.
    before = text[max(0, match.start() - 200):match.start()]
    # Up to the end of that argument: a symbol name may be picked by a
    # ternary, so the quote before it is not the boundary — the bracket is.
    #
    # `icon:` is here because Keezly's own row views take a symbol under that
    # name, and a ternary choosing between two symbols pushed the argument
    # label further back than the old 80-character window could see. The five
    # it was missing were all real symbols and identifiers, never missing
    # translations: inventing catalogue entries for them would have been the
    # wrong repair entirely.
    if re.search(r"(systemImage:|systemName:|\bicon:)[^)\n]*$", before):
        return True
    # An identifier argument, whatever it is spelled: `accessibilityIdentifier`
    # as a modifier, or `identifier:` on one of the app's own views.
    if re.search(r"\bidentifier:\s*$", before):
        return True
    if any(marker in line for marker in ("accessibilityIdentifier", "forResource", "forKey")):
        return True
    # Inside a property or function that returns a symbol name. A `switch`
    # picking an SF Symbol has no argument label to key off, so the enclosing
    # declaration is what identifies it:
    #
    #     private var icon: String {
    #         switch group { case .finished: "flag.checkered" ... }
    #
    # Matching on the declaration rather than listing symbol names, because a
    # list of symbols would need extending every time a view gains an icon —
    # and forgetting to extend it fails the build for a non-problem.
    enclosing = re.findall(r"\b(?:var|func)\s+([A-Za-z_][A-Za-z0-9_]*)", before)
    if enclosing and re.search(r"icon|symbol|image", enclosing[-1], re.IGNORECASE):
        return True
    # UserDefaults keys, which share the shape and are never shown.
    return match.group(1).startswith("keezly.")

# Files whose dotted strings are never shown to anybody. `OnlineDiagnostics`
# is the log channel: its step names (`match.received`, `start.tapped`) have
# exactly the shape of a localisation key and are read only by a developer
# looking at a device log.
NOT_USER_FACING = {"OnlineDiagnostics.swift"}

# A dotted string is only a candidate key if its first segment is a namespace
# the catalogue already uses. SF Symbols share the shape of a key exactly —
# `flag.checkered`, `person.badge.clock`, `envelope.badge` — and no amount of
# looking at the call site distinguishes them reliably.
#
# The trade-off is deliberate and narrow: a typo *within* a known namespace is
# still caught, which is the mistake that actually happens
# (`online.wonBaner`), while a whole new namespace shows up in the
# "not referenced" list below rather than as a hard failure.
NAMESPACES = {key.split(".")[0] for key in catalogue["strings"]}

used = set()
for source in pathlib.Path("App/Keezly").rglob("*.swift"):
    if source.name in NOT_USER_FACING:
        continue
    text = source.read_text()
    for match in KEY.finditer(text):
        line_start = text.rfind("\n", 0, match.start()) + 1
        line = text[line_start:text.find("\n", match.start())]
        if is_noise(text, match, line):
            continue
        # A key written with its format specifiers keeps them; one written
        # with an interpolation is matched by its stem, and the catalogue's
        # full key is found below.
        if match.group(1).split(".")[0] not in NAMESPACES:
            continue
        used.add(match.group(1) + (match.group(2) or ""))

known = set(catalogue["strings"])
# A catalogue key carries its specifiers ("a11y.leg %@ %lld"); an interpolated
# call site shows only the stem. Match on the stem so the two meet.
stems = {key.split(" %")[0]: key for key in known}
resolved = {stems.get(key.split(" %")[0], key) for key in used}

for key in sorted(resolved - known):
    problems.append(f"{key}: asked for in code, missing from the catalogue")

unused = {
    key for key in known - resolved
    if not any(key.startswith(prefix) for prefix in BUILT_AT_RUNTIME)
}

if problems:
    print(f"{len(problems)} problem(s) in {CATALOGUE}:")
    for problem in problems:
        print(f"  {problem}")
    sys.exit(1)

print(f"{len(catalogue['strings'])} keys, {len(LANGUAGES)} languages, all translated and consistent.")
if unused:
    # Not a failure: a key may be reached only from a runtime-built name this
    # scan cannot see. Worth printing so dead text does not accumulate.
    print(f"{len(unused)} key(s) not referenced directly in the source:")
    for key in sorted(unused):
        print(f"  {key}")
PY
