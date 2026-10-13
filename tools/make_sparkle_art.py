"""Draw Media/Frame/Sparkle.tga, the sparkle Farmer puts over the node you
face: a four-pointed star of light with a smaller, fainter cross turned 45
degrees and a soft glow at its heart; and Media/Frame/Beacon.tga, the
other look: a tall beam of light, brightest at its foot, fading upward.

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
BEACON = os.path.join(ROOT, "Media", "Frame", "Beacon.tga")
BEACON_W, BEACON_H = 32, 256

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


def beam(x, y):
    """0 to 1 at a point of the beam, x from -1 to 1 across, y 0 at its
    foot to 1 at its top."""
    core = math.exp(-(x / 0.14) ** 2)
    haze = 0.45 * math.exp(-(x / 0.5) ** 2)
    rise = (1 - y) ** 1.6
    foot = 1 if y > 0.03 else y / 0.03
    return min(1.0, (core + haze) * rise * foot)


def write(path, width, height, shade):
    pixels = []
    # TGA rows run bottom up (descriptor 8), so row 0 is the foot.
    for row in range(height):
        for column in range(width):
            total = 0.0
            for sy in range(SAMPLES):
                for sx in range(SAMPLES):
                    total += shade((column + (sx + 0.5) / SAMPLES) / width, (row + (sy + 0.5) / SAMPLES) / height)
            alpha = int(round(total / (SAMPLES * SAMPLES) * 255))
            pixels.append(bytes((255, 255, 255, alpha)))
    header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, width, height, 32, 8)
    with open(path, "wb") as handle:
        handle.write(header)
        handle.write(b"".join(pixels))
    print("wrote %s (%d bytes)" % (os.path.relpath(path, ROOT), os.path.getsize(path)))


def main():
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    write(OUT, SIZE, SIZE, lambda u, v: light(u * 2 - 1, v * 2 - 1))
    write(BEACON, BEACON_W, BEACON_H, lambda u, v: beam(u * 2 - 1, v))


if __name__ == "__main__":
    main()
