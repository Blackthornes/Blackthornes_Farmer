"""Draw the art for Farmer's damage numbers (UI/DamageNumbers.lua):

    Media/Frame/HitRing.tga   a thin bright ring with a soft edge, white
                              (the game tints it), for a crit or a kill
    Media/Frame/HitSpark.tga  a short streak, bright in the middle and
                              fading to both ends, white (tinted)
    Media/Frame/HitCoin.tga   a small gold coin with a rim and a shine,
                              in its own colours

    python tools/make_damage_art.py

Uncompressed 32-bit TGA, like tools/make_heat_art.py. Rerun it rather than
editing the TGAs.
"""

import math
import os
import struct

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FOLDER = os.path.join(ROOT, "Media", "Frame")


def clamp(value):
    return max(0, min(255, int(round(value))))


def write(name, width, height, pixel):
    """pixel(x, y) gives (r, g, b, a) in 0..1 for x, y in -1..1."""
    rows = []
    for row in range(height):
        for col in range(width):
            x = (col + 0.5) / width * 2 - 1
            # TGA rows run bottom to top.
            y = (row + 0.5) / height * 2 - 1
            r, g, b, a = pixel(x, y)
            rows.append(struct.pack("<BBBB", clamp(b * 255), clamp(g * 255), clamp(r * 255), clamp(a * 255)))
    header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, width, height, 32, 8)
    path = os.path.join(FOLDER, name)
    os.makedirs(FOLDER, exist_ok=True)
    with open(path, "wb") as handle:
        handle.write(header)
        handle.write(b"".join(rows))
    print("wrote", path)


def ring(x, y):
    r = math.hypot(x, y)
    # A bright band at 0.8 of the way out, with a faint glow either side.
    band = math.exp(-((r - 0.8) / 0.06) ** 2)
    glow = 0.35 * math.exp(-((r - 0.78) / 0.16) ** 2)
    alpha = min(1.0, band + glow) if r < 1 else 0.0
    return 1, 1, 1, alpha


def spark(x, y):
    # Long along x, thin along y.
    along = max(0.0, 1 - abs(x)) ** 1.6
    across = math.exp(-(y / 0.32) ** 2)
    return 1, 1, 1, along * across


def coin(x, y):
    r = math.hypot(x, y)
    if r >= 0.92:
        # A soft dark edge so the coin reads over a bright scene.
        edge = max(0.0, 1 - (r - 0.92) / 0.08)
        return 0.25, 0.16, 0.04, edge * 0.8
    # The face: deep gold, lighter toward the top left.
    light = 0.5 + 0.5 * (-x * 0.5 + y * 0.7)
    gold = (1.0 * (0.72 + 0.28 * light), 0.78 * (0.68 + 0.32 * light), 0.28 * (0.6 + 0.4 * light))
    # A raised rim.
    if r > 0.74:
        rim = 0.85 + 0.15 * light
        gold = (min(1, 1.0 * rim), min(1, 0.84 * rim), min(1, 0.38 * rim))
    # A shine near the top left.
    shine = math.exp(-(((x + 0.32) / 0.22) ** 2 + ((y - 0.36) / 0.14) ** 2))
    color = tuple(min(1.0, c + 0.6 * shine) for c in gold)
    return color[0], color[1], color[2], 1.0


def main():
    write("HitRing.tga", 128, 128, ring)
    write("HitSpark.tga", 64, 16, spark)
    write("HitCoin.tga", 32, 32, coin)


if __name__ == "__main__":
    main()
