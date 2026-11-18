"""Draw Media/Frame/Eye.tga, the eye on each Zone Board row that turns a
mob's kill heat on and off (UI/ZoneBoard.lua): a white almond outline with a
round middle, on clear. The game tints it gold when on, grey when off.

    python tools/make_eye_art.py

Uncompressed 32-bit TGA, 32 x 32, like tools/make_heat_art.py. Rerun it
rather than editing the TGA.
"""

import math
import os
import struct

SIZE = 32
SAMPLES = 4          # each pixel is SAMPLES x SAMPLES points, for soft edges
HALF_HEIGHT = 0.58   # how open the eye is, at its middle
STROKE = 0.13        # the outline's half width
PUPIL = 0.27         # the round middle's radius

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "Media", "Frame", "Eye.tga")


def lit(x, y):
    """True where a point (-1 to 1 both ways) is on the outline or the middle."""
    if math.hypot(x, y) <= PUPIL:
        return True
    edge = 0.92
    if abs(x) > edge + STROKE:
        return False
    u = max(-edge, min(edge, x)) / edge
    h = HALF_HEIGHT * (1 - u * u)
    slope = HALF_HEIGHT * 2 * abs(u) / edge
    distance = abs(abs(y) - h) / math.sqrt(1 + slope * slope)
    if abs(x) > edge:
        distance = math.hypot(abs(x) - edge, y)
    return distance <= STROKE


def main():
    pixels = []
    for row in range(SIZE):
        for col in range(SIZE):
            hits = 0
            for sy in range(SAMPLES):
                for sx in range(SAMPLES):
                    x = (col + (sx + 0.5) / SAMPLES) / SIZE * 2 - 1
                    y = (row + (sy + 0.5) / SAMPLES) / SIZE * 2 - 1
                    if lit(x * 1.08, y * 1.08):
                        hits += 1
            alpha = int(round(255 * hits / (SAMPLES * SAMPLES)))
            pixels.append(struct.pack("<BBBB", 255, 255, 255, alpha))
    header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, SIZE, SIZE, 32, 8)
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "wb") as handle:
        handle.write(header)
        handle.write(b"".join(pixels))


if __name__ == "__main__":
    main()
