"""Draw the Farm HUD's art (UI/FarmHUD.lua) into Media/Frame/:

- HudDisc.tga: a soft filled disc, the ring's see-through floor.
- HudRing.tga: a thin round line at the disc's edge, the ring's rim.
- HudDash.tga: a dotted round line, the inner distance rings.
- HudDot.tga: a filled dot, a spot that should be back.
- HudHollow.tga: a round line, a spot still growing back.
- HudArrow.tga: the arrowhead in the middle that turns with you.

All are white so the game tints them. Uncompressed 32-bit TGA, like
tools/make_heat_art.py. Rerun it rather than editing the TGAs.

    python tools/make_hud_art.py
"""

import math
import os
import struct

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "Media", "Frame")
SAMPLES = 4


def write(name, size, alpha_at):
    """Write a white square TGA whose alpha is alpha_at(x, y), x and y from
    -1 to 1 with y up, averaged over SAMPLES x SAMPLES points per pixel."""
    pixels = []
    for row in range(size):  # TGA rows run bottom to top, so y runs up
        for col in range(size):
            total = 0.0
            for sy in range(SAMPLES):
                for sx in range(SAMPLES):
                    x = (col + (sx + 0.5) / SAMPLES) / size * 2 - 1
                    y = (row + (sy + 0.5) / SAMPLES) / size * 2 - 1
                    total += alpha_at(x, y)
            alpha = int(round(255 * max(0.0, min(1.0, total / SAMPLES ** 2))))
            pixels.append(struct.pack("<BBBB", 255, 255, 255, alpha))
    header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, size, size, 32, 8)
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, name + ".tga")
    with open(path, "wb") as handle:
        handle.write(header)
        handle.write(b"".join(pixels))
    print("wrote", path)


def disc(x, y):
    r = math.hypot(x, y)
    return 1.0 if r <= 0.98 else 0.0


def band(inner, outer):
    def at(x, y):
        r = math.hypot(x, y)
        return 1.0 if inner <= r <= outer else 0.0
    return at


def dashed(inner, outer, dashes):
    line = band(inner, outer)

    def at(x, y):
        if not line(x, y):
            return 0.0
        turn = (math.atan2(y, x) / (2 * math.pi)) % 1.0
        return 1.0 if (turn * dashes) % 1.0 < 0.35 else 0.0
    return at


def arrow(x, y):
    """An arrowhead pointing up: tip at the top, notched at the bottom."""
    tip, left, notch, right = (0.0, 0.9), (-0.62, -0.75), (0.0, -0.4), (0.62, -0.75)

    def inside(poly):
        hit = False
        for i in range(len(poly)):
            (ax, ay), (bx, by) = poly[i], poly[i - 1]
            if (ay > y) != (by > y) and x < (bx - ax) * (y - ay) / (by - ay) + ax:
                hit = not hit
        return hit
    return 1.0 if inside([tip, right, notch, left]) else 0.0


def main():
    write("HudDisc", 256, disc)
    write("HudRing", 256, band(0.978, 0.996))
    write("HudDash", 256, dashed(0.975, 0.995, 72))
    write("HudDot", 32, disc)
    write("HudHollow", 32, band(0.6, 0.98))
    write("HudArrow", 64, arrow)


if __name__ == "__main__":
    main()
