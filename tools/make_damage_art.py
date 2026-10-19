"""Draw the art for Farmer's damage numbers (UI/DamageNumbers.lua):

    Media/Frame/HitRing.tga   a thin bright ring with a soft edge, white
                              (the game tints it), for a crit or a kill
    Media/Frame/HitSpark.tga  a short streak, bright in the middle and
                              fading to both ends, white (tinted)
    Media/Frame/HitCoin.tga   a small gold coin with a rim and a shine,
                              in its own colours
    Media/Frame/HitEmber.tga  a soft round ember (fire)
    Media/Frame/HitShard.tga  a thin ice diamond with a bright edge (frost)
    Media/Frame/HitLeaf.tga   a leaf with a vein (nature)
    Media/Frame/HitSmoke.tga  a soft cloudy puff (shadow)
    Media/Frame/HitStar.tga   a four-point twinkle (arcane)

All but the coin are white, so the game tints them.

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


def ember(x, y):
    r = math.hypot(x, y)
    core = math.exp(-(r / 0.28) ** 2)
    halo = 0.55 * math.exp(-(r / 0.45) ** 2)
    return 1, 1, 1, min(1.0, core + halo)


def shard(x, y):
    # A diamond, tall along y.
    d = abs(x) / 0.45 + abs(y) / 0.95
    if d >= 1:
        return 1, 1, 1, 0.0
    edge = 0.55 + 0.45 * (d ** 3)
    soft = min(1.0, (1 - d) / 0.12)
    return 1, 1, 1, edge * soft


def leaf(x, y):
    # Pointed at both ends along x, a vein down the middle.
    half = 0.55 * max(0.0, 1 - x * x) ** 0.8
    if abs(y) >= half or abs(x) >= 1:
        return 1, 1, 1, 0.0
    body = 0.85
    vein = 0.35 * math.exp(-(y / 0.05) ** 2)
    soft = min(1.0, (half - abs(y)) / 0.08)
    return 1, 1, 1, min(1.0, body + vein) * soft


def smoke(x, y):
    # A lumpy soft puff.
    r = math.hypot(x, y)
    a = math.atan2(y, x)
    lump = 0.75 + 0.12 * math.sin(a * 3) + 0.08 * math.sin(a * 5 + 1)
    alpha = max(0.0, 1 - (r / lump) ** 2) ** 1.5
    return 1, 1, 1, alpha


def star(x, y):
    # Four thin points and a soft middle.
    arms = math.exp(-(abs(x) / 0.06)) * max(0.0, 1 - abs(y)) + math.exp(-(abs(y) / 0.06)) * max(0.0, 1 - abs(x))
    core = math.exp(-((x * x + y * y) / 0.04))
    return 1, 1, 1, min(1.0, arms + core)


def main():
    write("HitRing.tga", 128, 128, ring)
    write("HitSpark.tga", 64, 16, spark)
    write("HitCoin.tga", 32, 32, coin)
    write("HitEmber.tga", 32, 32, ember)
    write("HitShard.tga", 32, 32, shard)
    write("HitLeaf.tga", 32, 32, leaf)
    write("HitSmoke.tga", 64, 64, smoke)
    write("HitStar.tga", 32, 32, star)


if __name__ == "__main__":
    main()
