#!/usr/bin/env python3
"""Chooses the ten App Store screenshots per device and locale, and says why.

Apple allows ten; the capture matrix produces fifteen. Which five to leave out
is a judgement, so it is written down as an ordered list with a reason against
each entry rather than made by a rule nobody can inspect.

The order is the order the App Store shows them, and it is meant to read as a
sequence: what the game is, then how it scales, then what is interesting about
it, then what surrounds it.

iPhone and iPad are deliberately different. A phone is held in one hand and its
story is the hand of cards and the reachable board; an iPad's story is the full
table with room to breathe, so it leads with the larger tables and keeps the
landscape compositions a phone cannot show as well.
"""

import json
import shutil
import sys
from pathlib import Path

# (file stem, why it is here). Order is the store order.
# Every one of these is portrait. A phone is held upright, and a store series
# that flips between portrait and landscape looks like a mistake even when each
# image in it is right. The landscape captures of the same screens exist and are
# used for the iPad series.
IPHONE = [
    ("phone-four-players-portrait", "Hero. A four-player table in the hand, the way most people will first see it."),
    ("phone-menu-portrait", "What the app is, and that it offers online play."),
    ("two-players-portrait", "The smallest table, and proof the board reshapes rather than leaving gaps."),
    ("phone-six-players-portrait", "The largest table on a phone — the claim '2 to 6' made visible."),
    ("phone-mid-match-portrait", "A real position mid-match: a full hand, pieces out, something to decide."),
    ("phone-seven-split-portrait", "The Seven split across two pieces — the rule that makes Keezen Keezen."),
    ("phone-jack-swap-portrait", "The Jack's swap, with its targets showing. The second distinctive card."),
    ("phone-online-menu-portrait", "Online play through Game Center, which is a 1.0 feature and should be seen."),
    ("phone-free-for-all-portrait", "Free-for-all rather than teams — the house rules are configurable."),
    ("phone-rulebook-portrait", "The rulebook — the answer to \"but how do you actually play it\", which sells a folk game."),
]

IPAD = [
    ("four-players-landscape", "Hero. The full table on a large display, which is what an iPad is for."),
    ("six-players-landscape", "Six seats with room to breathe — the composition a phone cannot show."),
    ("menu", "What the app is, and that it offers online play."),
    ("two-players-landscape", "The smallest table, and the board reshaping for it."),
    ("seven-mid-split", "The Seven split across two pieces."),
    ("jack-swap-targets", "The Jack's swap and its targets."),
    ("five-players-landscape", "An odd table, which the geometry handles rather than refusing."),
    ("online-menu", "Online play through Game Center."),
    ("four-players-free-for-all", "Free-for-all rather than teams."),
    ("four-players-portrait", "Portrait on a tablet, which people genuinely use."),
]

LOCALES = ["de", "nl", "en"]


def main(root: Path, out: Path) -> int:
    problems = []
    manifest = {}

    for locale in LOCALES:
        for device, wanted in (("iphone", IPHONE), ("ipad", IPAD)):
            source = root / f"{device}-{locale}"
            if not source.is_dir():
                problems.append(f"{source} does not exist")
                continue

            available = {p.stem: p for p in source.glob("*.png")}
            chosen = []
            for position, (stem, reason) in enumerate(wanted, start=1):
                path = available.get(stem)
                if path is None:
                    problems.append(f"{device}-{locale}: no capture called {stem}.png")
                    continue
                chosen.append({
                    "position": position,
                    "scene": stem,
                    "reason": reason,
                    "source": str(path),
                })

            if len(chosen) != 10:
                problems.append(f"{device}-{locale}: {len(chosen)} chosen, Apple takes exactly 10")

            destination = out / f"{device}-{locale}"
            destination.mkdir(parents=True, exist_ok=True)
            for entry in chosen:
                # Numbered, because App Store Connect orders by upload and a
                # name that sorts is the only order a person can check.
                target = destination / f"{entry['position']:02d}-{entry['scene']}.png"
                shutil.copy2(entry["source"], target)
                entry["file"] = target.name
                del entry["source"]
            manifest[f"{device}-{locale}"] = chosen

    (out / "selection.json").write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")

    total = sum(len(v) for v in manifest.values())
    print(f"{total} screenshots selected into {out}")
    for series, entries in sorted(manifest.items()):
        print(f"  {series}: {len(entries)}")
    if problems:
        print("\nPROBLEMS:")
        for p in problems:
            print(f"  ✘ {p}")
        return 1
    print("\n6 series x 10 = 60. Selection recorded in selection.json.")
    print("SELECTED — not reviewed by a person, and not uploaded.")
    return 0


if __name__ == "__main__":
    root = Path(sys.argv[1] if len(sys.argv) > 1 else "artifacts/screenshots")
    out = Path(sys.argv[2] if len(sys.argv) > 2 else "artifacts/store-screenshots")
    sys.exit(main(root, out))
