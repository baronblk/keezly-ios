#!/usr/bin/env python3
"""Keezly's achievement artwork, drawn from source.

Ten 1024×1024 images, one per achievement, generated rather than sourced — the
same argument as the app icon and the sound set: the provenance of the artwork
is the code that made it, and there is no licence to wonder about (§77).

The design language is the board's, because these appear next to it:

  * Classic Wood for the plate, with the same warm ramp as the panel.
  * A Delft-blue medallion, the colour the game's chrome already uses.
  * One restrained orange accent, and only where it means something.
  * A single glyph per achievement, built from the same shapes the board draws
    — pawns, a card, a ring, an arrow — so a player recognises them.

Drawn at 2048 and downsampled to 1024, which is the cheapest way to get clean
edges out of a library with no anti-aliasing worth the name.

    python3 Tools/achievementart.py build/achievements

Requires Pillow and nothing else.
"""

import math
import os
import sys

from PIL import Image, ImageDraw

SIZE = 1024
SUPER = 2

WOOD_LIGHT = (232, 213, 183)
WOOD_MID = (214, 186, 146)
WOOD_DEEP = (170, 138, 96)
WOOD_EDGE = (120, 94, 60)
DELFT = (31, 78, 121)
DELFT_LIGHT = (62, 116, 168)
ORANJE = (224, 122, 47)
IVORY = (250, 246, 238)
INK = (36, 29, 20)


def ramp(draw, box, top, bottom):
    """A soft vertical wood gradient, drawn as rows."""
    x0, y0, x1, y1 = box
    height = max(1, y1 - y0)
    for i in range(height):
        t = i / height
        colour = tuple(round(top[c] + (bottom[c] - top[c]) * t) for c in range(3))
        draw.rectangle([x0, y0 + i, x1, y0 + i + 1], fill=colour)


def plate(draw, s):
    """The wooden plate every achievement sits on."""
    margin = 40 * s
    box = (margin, margin, SIZE * s - margin, SIZE * s - margin)
    radius = 180 * s

    # Shadow first, so the plate reads as an object rather than a sticker.
    draw.rounded_rectangle(
        (box[0] + 6 * s, box[1] + 14 * s, box[2] + 6 * s, box[3] + 14 * s),
        radius=radius, fill=(210, 190, 165),
    )
    draw.rounded_rectangle(box, radius=radius, fill=WOOD_MID)

    # A lit top edge and a darker foot: the same modelling the board uses.
    inner = (box[0] + 10 * s, box[1] + 10 * s, box[2] - 10 * s, box[3] - 10 * s)
    mask = Image.new("L", (SIZE * s, SIZE * s), 0)
    ImageDraw.Draw(mask).rounded_rectangle(inner, radius=radius - 10 * s, fill=255)
    grad = Image.new("RGB", (SIZE * s, SIZE * s))
    ramp(ImageDraw.Draw(grad), (0, 0, SIZE * s, SIZE * s), WOOD_LIGHT, WOOD_DEEP)
    return mask, grad, box, radius


def medallion(draw, s, cx, cy, r):
    draw.ellipse((cx - r, cy - r, cx + r, cy + r), fill=DELFT)
    draw.ellipse((cx - r + 12 * s, cy - r + 12 * s, cx + r - 12 * s, cy + r - 12 * s),
                 outline=DELFT_LIGHT, width=5 * s)


def pawn(draw, s, cx, cy, h, colour):
    """The board's pawn silhouette: head, collar, body."""
    head_r = h * 0.20
    draw.ellipse((cx - head_r, cy - h * 0.50, cx + head_r, cy - h * 0.50 + head_r * 2),
                 fill=colour)
    draw.polygon([
        (cx - h * 0.09, cy - h * 0.18), (cx + h * 0.09, cy - h * 0.18),
        (cx + h * 0.15, cy + h * 0.10), (cx - h * 0.15, cy + h * 0.10),
    ], fill=colour)
    draw.rounded_rectangle((cx - h * 0.27, cy + h * 0.10, cx + h * 0.27, cy + h * 0.30),
                           radius=h * 0.08, fill=colour)


def card(draw, s, cx, cy, w, angle, face=IVORY):
    h = w * 1.42
    layer = Image.new("RGBA", (int(w * 2.2), int(h * 2.2)), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    ox, oy = layer.size[0] / 2 - w / 2, layer.size[1] / 2 - h / 2
    d.rounded_rectangle((ox, oy, ox + w, oy + h), radius=w * 0.10, fill=face,
                        outline=(198, 186, 166), width=max(1, int(3 * s)))
    return layer.rotate(angle, resample=Image.BICUBIC, expand=False), \
        (int(cx - layer.size[0] / 2), int(cy - layer.size[1] / 2))


def arrow(draw, s, cx, cy, length, angle_deg, colour, width):
    a = math.radians(angle_deg)
    hx, hy = cx + math.cos(a) * length / 2, cy + math.sin(a) * length / 2
    tx, ty = cx - math.cos(a) * length / 2, cy - math.sin(a) * length / 2
    draw.line([(tx, ty), (hx, hy)], fill=colour, width=width)
    head = length * 0.22
    left = (hx - math.cos(a - 0.5) * head, hy - math.sin(a - 0.5) * head)
    right = (hx - math.cos(a + 0.5) * head, hy - math.sin(a + 0.5) * head)
    draw.polygon([(hx, hy), left, right], fill=colour)


# ------------------------------------------------------------------ glyphs

def glyph_finished(d, s, cx, cy, r):
    medallion(d, s, cx, cy, r)
    for i, dx in enumerate((-1, 0, 1)):
        pawn(d, s, cx + dx * r * 0.42, cy + r * 0.10, r * 0.78, IVORY)


def glyph_won(d, s, cx, cy, r):
    medallion(d, s, cx, cy, r)
    pawn(d, s, cx, cy + r * 0.06, r * 1.05, IVORY)
    ring = r * 0.62
    d.arc((cx - ring, cy - ring * 1.5, cx + ring, cy + ring * 0.5),
          start=200, end=340, fill=ORANJE, width=int(14 * s))


def glyph_untouched(d, s, cx, cy, r):
    medallion(d, s, cx, cy, r)
    pawn(d, s, cx, cy + r * 0.06, r * 0.95, IVORY)
    d.ellipse((cx - r * 0.74, cy - r * 0.74, cx + r * 0.74, cy + r * 0.74),
              outline=ORANJE, width=int(13 * s))


def glyph_split(d, s, cx, cy, r):
    medallion(d, s, cx, cy, r)
    pawn(d, s, cx - r * 0.40, cy + r * 0.10, r * 0.70, IVORY)
    pawn(d, s, cx + r * 0.40, cy + r * 0.10, r * 0.70, IVORY)
    arrow(d, s, cx, cy - r * 0.52, r * 0.80, 0, ORANJE, int(12 * s))


def glyph_swapped(d, s, cx, cy, r):
    medallion(d, s, cx, cy, r)
    pawn(d, s, cx - r * 0.42, cy + r * 0.12, r * 0.70, IVORY)
    pawn(d, s, cx + r * 0.42, cy + r * 0.12, r * 0.70, IVORY)
    arrow(d, s, cx, cy - r * 0.40, r * 0.86, 0, ORANJE, int(11 * s))
    arrow(d, s, cx, cy - r * 0.62, r * 0.86, 180, ORANJE, int(11 * s))


def glyph_backwards(d, s, cx, cy, r):
    medallion(d, s, cx, cy, r)
    pawn(d, s, cx + r * 0.22, cy + r * 0.10, r * 0.92, IVORY)
    arrow(d, s, cx - r * 0.20, cy - r * 0.48, r * 0.95, 180, ORANJE, int(13 * s))


def glyph_knockout(d, s, cx, cy, r):
    medallion(d, s, cx, cy, r)
    pawn(d, s, cx - r * 0.34, cy + r * 0.10, r * 0.86, IVORY)
    pawn(d, s, cx + r * 0.46, cy + r * 0.22, r * 0.62, (196, 122, 104))
    arrow(d, s, cx + r * 0.06, cy - r * 0.44, r * 0.66, 0, ORANJE, int(12 * s))


def glyph_resilient(d, s, cx, cy, r):
    medallion(d, s, cx, cy, r)
    pawn(d, s, cx, cy + r * 0.10, r * 0.92, IVORY)
    for k in range(3):
        a0 = 150 + k * 60
        d.arc((cx - r * 0.80, cy - r * 0.80, cx + r * 0.80, cy + r * 0.80),
              start=a0, end=a0 + 38, fill=ORANJE, width=int(12 * s))


def glyph_full_table(d, s, cx, cy, r):
    medallion(d, s, cx, cy, r)
    for k in range(6):
        a = math.radians(-90 + k * 60)
        px = cx + math.cos(a) * r * 0.58
        py = cy + math.sin(a) * r * 0.58
        pawn(d, s, px, py, r * 0.46, IVORY if k % 2 == 0 else (232, 214, 188))


def glyph_partners(d, s, cx, cy, r):
    medallion(d, s, cx, cy, r)
    pawn(d, s, cx - r * 0.34, cy + r * 0.10, r * 0.88, IVORY)
    pawn(d, s, cx + r * 0.34, cy + r * 0.10, r * 0.88, IVORY)
    d.arc((cx - r * 0.66, cy - r * 0.70, cx + r * 0.66, cy + r * 0.20),
          start=190, end=350, fill=ORANJE, width=int(13 * s))


GLYPHS = {
    "finished": glyph_finished,
    "won": glyph_won,
    "untouched": glyph_untouched,
    "split": glyph_split,
    "swapped": glyph_swapped,
    "backwards": glyph_backwards,
    "knockout": glyph_knockout,
    "resilient": glyph_resilient,
    "fullTable": glyph_full_table,
    "partners": glyph_partners,
}


def render(name):
    s = SUPER
    img = Image.new("RGB", (SIZE * s, SIZE * s), WOOD_LIGHT)
    d = ImageDraw.Draw(img)

    mask, grad, box, radius = plate(d, s)
    img.paste(grad, (0, 0), mask)
    d = ImageDraw.Draw(img)
    d.rounded_rectangle(box, radius=radius, outline=WOOD_EDGE, width=int(7 * s))

    cx = cy = SIZE * s / 2
    GLYPHS[name](d, s, cx, cy, SIZE * s * 0.27)

    return img.resize((SIZE, SIZE), Image.LANCZOS)


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else "build/achievements"
    os.makedirs(out, exist_ok=True)
    for name in GLYPHS:
        path = os.path.join(out, f"{name}.png")
        render(name).save(path, "PNG", optimize=True)
        size = os.path.getsize(path)
        print(f"  {name:11} {size / 1024:6.0f} KiB")
    print(f"\n{len(GLYPHS)} images in {out}, 1024x1024, RGB, no alpha.")


if __name__ == "__main__":
    main()
