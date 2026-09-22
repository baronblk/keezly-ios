#!/usr/bin/env python3
"""Checks the screenshot set as files, before anybody uploads it.

The captures used to be attachments in a result bundle, which meant the only
way to find out that every landscape one carried a black band down a quarter of
it was to open one and look (ISS-012). Files can be measured, so they are.

What is checked, and why each one is here rather than trusted:

  shape      A landscape capture must be wider than it is tall and a portrait
             one taller than it is wide. This is ISS-009 exactly, and it came
             back once already.
  borders    No black band on any edge. This is ISS-012 exactly. The check is
             for a band of *any* width — it must never be turned into a crop,
             because the band was the wrong capture source and not a margin.
  size       App Store Connect rejects anything under its minimums, and a
             rejection three weeks later is an expensive way to learn it. This
             one has already earned its keep: the capture device was an
             iPhone 17 Pro, whose screenshots are 1206 points across, and the
             store wants 1290.

What is **not** checked here, and is not pretended to be: whether the frame
carries a debug overlay, a test identifier, a raw localisation key or anybody's
name. Finding text in a PNG needs OCR this has no business carrying, and a
check that cannot see something must not imply that it looked. That gate is a
person with the set open, and it is written down as one in
`RELEASE_CHECKLIST.md`.

Reports every failure rather than stopping at the first, because a screenshot
run is slow and finding out about one fault at a time is how a morning goes.
"""

import sys
from pathlib import Path

try:
    from PIL import Image
except ImportError:  # pragma: no cover - the message is the whole point
    print("Pillow is needed: python3 -m pip install pillow", file=sys.stderr)
    sys.exit(2)

# The **short** edge App Store Connect expects. A 6.9" iPhone capture is
# 1290x2796 and a 13" iPad one is 2064x2752, so 1290 passes both and anything
# scaled down fails — which is the case worth catching, because a downscaled
# capture looks fine in a file browser and is refused at upload.
#
# Measured against the short edge rather than the long one on purpose: a long
# thin image has a long edge too, and would sail through.
MINIMUM_EDGE = 1290

# Dark, but not black. The table the board sits on is a very dark green; a
# capture's real background must not be mistaken for a dead band, so the
# threshold is well below it.
BLACK = 12


def is_black_row(pixels, width, y):
    return all(max(pixels[x, y][:3]) <= BLACK for x in range(0, width, 8))


def is_black_column(pixels, height, x):
    return all(max(pixels[x, y][:3]) <= BLACK for y in range(0, height, 8))


def black_border(image):
    """How many rows and columns of pure black sit on each edge."""
    pixels = image.load()
    width, height = image.size

    top = 0
    while top < height and is_black_row(pixels, width, top):
        top += 1
    bottom = 0
    while bottom < height - top and is_black_row(pixels, width, height - 1 - bottom):
        bottom += 1
    left = 0
    while left < width and is_black_column(pixels, height, left):
        left += 1
    right = 0
    while right < width - left and is_black_column(pixels, height, width - 1 - right):
        right += 1
    return top, bottom, left, right


def check(path):
    """Every fault in one capture, as a list of sentences."""
    faults = []
    name = path.stem.lower()
    image = Image.open(path).convert("RGB")
    width, height = image.size

    if "landscape" in name and width <= height:
        faults.append(f"landscape capture is {width}x{height} — it is not wider than it is tall (ISS-009)")
    if "portrait" in name and height <= width:
        faults.append(f"portrait capture is {width}x{height} — it is not taller than it is wide")

    if min(width, height) < MINIMUM_EDGE:
        faults.append(
            f"{width}x{height} — the short edge is below App Store Connect's {MINIMUM_EDGE}px minimum"
        )

    top, bottom, left, right = black_border(image)
    if max(top, bottom, left, right) > 2:
        share = max(top + bottom, left + right) / max(width, height)
        faults.append(
            f"black border t{top} b{bottom} l{left} r{right} — {share:.0%} of the frame (ISS-012). "
            "The capture source is wrong; do not crop it"
        )

    return faults


def main():
    root = Path(sys.argv[1] if len(sys.argv) > 1 else "build/screenshots")
    captures = sorted(root.rglob("*.png"))
    if not captures:
        print(f"No captures under {root}.", file=sys.stderr)
        return 1

    failures = 0
    for path in captures:
        faults = check(path)
        if faults:
            failures += 1
            print(f"✘ {path.relative_to(root)}")
            for fault in faults:
                print(f"    {fault}")

    print(f"\n{len(captures)} capture(s), {failures} with faults.")
    if failures:
        return 1
    print("Every capture is the right way up, the right size, and has no dead band.")
    print("What this cannot tell you is whether they sell the app. That needs eyes.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
