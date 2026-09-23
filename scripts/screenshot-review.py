#!/usr/bin/env python3
"""Builds SCREENSHOT_REVIEW.html — the sheet a person signs off before upload.

Deliberately not a gallery. Every image carries the ten checks that decide
whether it may ship, all unticked, because a review that starts at PASS is not
a review. There is also a contact sheet per series, so ten images can be judged
as a sequence rather than one at a time.
"""

import base64
import json
import subprocess
import sys
import tempfile
from pathlib import Path

CHECKS = [
    "Language is right for this locale",
    "Status bar correct (9:41, full signal)",
    "No raw string keys",
    "No debug or test-only interface",
    "Nothing clipped or cut off",
    "No personal data",
    "Board composition is worth showing",
    "Cards legible and correct",
    "The feature shown genuinely exists in this build",
    "Good enough to sell the app",
]

TITLES = {"de": "Deutsch", "nl": "Nederlands", "en": "English"}
DEVICES = {"iphone": "iPhone 6.9″ (1320 × 2868)", "ipad": "iPad 13″ (2064 × 2752)"}


# The review page embeds every image so it can be opened from anywhere — no
# folder beside it, no broken links, nothing to lose. Full-resolution PNGs make
# that 177 MB and unopenable, so each is scaled to a height a reviewer can
# actually judge on screen. The originals are untouched: these are for looking
# at, the files in the folder are what get uploaded.
_CACHE: dict[tuple[str, int], str] = {}


def data_uri(path: Path, height: int = 900) -> str:
    key = (str(path), height)
    if key in _CACHE:
        return _CACHE[key]
    with tempfile.NamedTemporaryFile(suffix=".png", delete=False) as tmp:
        scaled = Path(tmp.name)
    subprocess.run(
        ["sips", "--resampleHeight", str(height), str(path), "--out", str(scaled)],
        check=True, capture_output=True,
    )
    uri = "data:image/png;base64," + base64.b64encode(scaled.read_bytes()).decode("ascii")
    scaled.unlink(missing_ok=True)
    _CACHE[key] = uri
    return uri


def main(folder: Path, out: Path) -> int:
    manifest = json.loads((folder / "selection.json").read_text(encoding="utf-8"))

    parts = ["""<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Keezly — screenshot review</title>
<style>
 :root { color-scheme: light dark; --line: #8883; }
 body { font: 16px/1.5 -apple-system, system-ui, sans-serif; margin: 0 auto; padding: 24px; max-width: 1100px; }
 h1 { font-size: 1.6rem; } h2 { margin-top: 2.5rem; border-bottom: 2px solid var(--line); padding-bottom: .3rem; }
 .lede { opacity: .75; }
 .contact { display: flex; gap: 10px; overflow-x: auto; padding: 12px 0; border-bottom: 1px solid var(--line); }
 .contact figure { margin: 0; flex: 0 0 auto; width: 110px; text-align: center; }
 .contact img { width: 110px; border: 1px solid var(--line); border-radius: 6px; }
 .contact figcaption { font-size: .7rem; opacity: .7; }
 .shot { display: grid; grid-template-columns: 260px 1fr; gap: 22px; padding: 22px 0; border-bottom: 1px solid var(--line); }
 .shot img { width: 100%; border: 1px solid var(--line); border-radius: 10px; }
 .meta { font-size: .85rem; opacity: .8; margin: .2rem 0 .8rem; }
 .why { font-style: italic; opacity: .85; margin-bottom: .8rem; }
 ul.checks { list-style: none; padding: 0; margin: 0; columns: 2; }
 ul.checks li { break-inside: avoid; margin: .25rem 0; }
 .verdict { margin-top: .8rem; font-weight: 600; }
 @media (max-width: 720px) { .shot { grid-template-columns: 1fr; } ul.checks { columns: 1; } }
</style></head><body>
<h1>Keezly 1.0.0 — screenshot review</h1>
<p class="lede">Six series, ten images each, in the order the App Store will show them.
Nothing here is ticked. A review that starts at PASS is not a review — and no
check below can be answered by a script, which is why they are here and not in
<code>screenshots-verify.py</code>.</p>
"""]

    for series in ["iphone-de", "ipad-de", "iphone-nl", "ipad-nl", "iphone-en", "ipad-en"]:
        entries = manifest.get(series)
        if not entries:
            continue
        device, locale = series.split("-")
        parts.append(f"<h2>{TITLES[locale]} — {DEVICES[device]}</h2>")

        parts.append('<div class="contact">')
        for e in entries:
            path = folder / series / e["file"]
            parts.append(
                f'<figure><img src="{data_uri(path, 220)}" alt="{e["scene"]}">'
                f'<figcaption>{e["position"]}. {e["scene"]}</figcaption></figure>'
            )
        parts.append("</div>")

        for e in entries:
            path = folder / series / e["file"]
            checks = "".join(f"<li>☐ {c}</li>" for c in CHECKS)
            parts.append(f"""<div class="shot">
 <img src="{data_uri(path)}" alt="{e['scene']} in {locale}">
 <div>
  <h3>{e['position']}. {e['scene']}</h3>
  <p class="meta">{e['file']} · {DEVICES[device]} · {TITLES[locale]} · position {e['position']} of 10</p>
  <p class="why">Why it is in the series: {e['reason']}</p>
  <ul class="checks">{checks}</ul>
  <p class="verdict">☐ APPROVE &nbsp;&nbsp; ☐ REPLACE &nbsp;&nbsp; ☐ REORDER</p>
 </div></div>""")

    parts.append("""<h2>Sign-off</h2>
<p>☐ All six series approved &nbsp;&nbsp; ☐ Changes needed (listed below)</p>
<p>Date: ______________  Reviewed by: ______________</p>
<p class="lede">Until this is signed, the screenshots are SELECTED, not APP STORE VERIFIED.</p>
</body></html>""")

    out.write_text("\n".join(parts), encoding="utf-8")
    size = out.stat().st_size / 1_000_000
    print(f"{out} written ({size:.1f} MB, images embedded)")
    return 0


if __name__ == "__main__":
    folder = Path(sys.argv[1] if len(sys.argv) > 1 else "artifacts/store-screenshots")
    out = Path(sys.argv[2] if len(sys.argv) > 2 else "SCREENSHOT_REVIEW.html")
    sys.exit(main(folder, out))
