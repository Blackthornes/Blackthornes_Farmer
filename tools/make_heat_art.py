"""Draw Media/Frame/HeatDot.tga, the soft dot the kill heat map is made of
(UI/Heat.lua): white, round, brightest at the middle and fading smoothly to
nothing at the edge, so overlapping dots run together into a glow. The game
tints it.

    python tools/make_heat_art.py

Uncompressed 32-bit TGA, 64 x 64, like tools/make_sparkle_art.py. Rerun it
rather than editing the TGA.
"""

import math
import os
import struct

SIZE = 64

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "Media", "Frame", "HeatDot.tga")


def light(r):
    """0 to 1 at a distance r from the middle (0 at the middle, 1 at the edge)."""
    if r >= 1:
        return 0.0
    return (1 - r * r) ** 2.2


def main():
    pixels = []
    # TGA rows run bottom to top; the dot is round, so the order does not matter.
    for row in range(SIZE):
        for col in range(SIZE):
            x = (col + 0.5) / SIZE * 2 - 1
            y = (row + 0.5) / SIZE * 2 - 1
            alpha = int(round(255 * light(math.hypot(x, y))))
            pixels.append(struct.pack("<BBBB", 255, 255, 255, alpha))
    header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, SIZE, SIZE, 32, 8)
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "wb") as handle:
        handle.write(header)
        handle.write(b"".join(pixels))
    print("wrote", OUT)


if __name__ == "__main__":
    main()
