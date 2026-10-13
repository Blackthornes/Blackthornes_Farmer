"""Draw Media/Frame/Sparkle.tga, the sparkle Farmer puts over the node you
face: a four-pointed star of light with a smaller, fainter cross turned 45
degrees and a soft glow at its heart.

    python tools/make_sparkle_art.py

White on transparent, so the game tints it (UI/NodeSparkle.lua tints it
gold). Uncompressed 32-bit TGA, 64 x 64, supersampled 4x4 per pixel, like
tools/make_frame_art.py. Rerun it rather than editing the TGA.
"""

import math
import os
import struct

SIZE = 64
SAMPLES = 4

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "Media", "Frame", "Sparkle.tga")

# The long rays reach the edge; the short ones reach this far of it.
SHORT = 0.55
# How fast a ray thins toward its tip; bigger is thinner.
SHARP = 2.4


def ray(u, v, length, width):
    """Light of a ray along u, thinning to a point at `length`."""
    along = abs(u) / length
    if along >= 1:
        return 0.0
    half = width * (1 - along) ** SHARP
    if half <= 0:
        return 0.0
    across = abs(v) / half
    if across >= 1:
        return 0.0
    return (1 - across) ** 1.5 * (1 - along) ** 0.6


def light(x, y):
    """0 to 1 at a point, x and y from -1 to 1."""
    value = max(ray(x, y, 1.0, 0.16), ray(y, x, 1.0, 0.16))
    d1, d2 = (x + y) / math.sqrt(2), (x - y) / math.sqrt(2)
    value = max(value, 0.6 * max(ray(d1, d2, SHORT, 0.12), ray(d2, d1, SHORT, 0.12)))
    r = math.hypot(x, y)
    value = max(value, math.exp(-(r / 0.16) ** 2))
    value += 0.25 * math.exp(-(r / 0.42) ** 2)
    return min(1.0, value)


def main():
    pixels = []
    # TGA rows run bottom up; the star is symmetric, so order does not matter.
    for row in range(SIZE):
        for column in range(SIZE):
            total = 0.0
            for sy in range(SAMPLES):
                for sx in range(SAMPLES):
                    x = (column + (sx + 0.5) / SAMPLES) / SIZE * 2 - 1
                    y = (row + (sy + 0.5) / SAMPLES) / SIZE * 2 - 1
                    total += light(x, y)
            alpha = int(round(total / (SAMPLES * SAMPLES) * 255))
            pixels.append(bytes((255, 255, 255, alpha)))

    header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, SIZE, SIZE, 32, 8)
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "wb") as handle:
        handle.write(header)
        handle.write(b"".join(pixels))
    print("wrote %s (%d bytes)" % (os.path.relpath(OUT, ROOT), os.path.getsize(OUT)))


if __name__ == "__main__":
    main()
