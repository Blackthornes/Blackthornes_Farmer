"""Draw Media/Trash/TrashCan.tga, the small gold can Farmer puts on the
cheapest item in full bags (UI/Trash.lua).

    python tools/make_trash_art.py

Drawn here, never shipped from the game: a lid with its handle, a tapered
body with three ribs, in the house gold with a dark edge and a soft glow
round it, so it reads on any item icon at 16 pixels. Uncompressed 32-bit
TGA, 64 by 64, supersampled 4x4 per pixel, like tools/make_frame_art.py.

It also draws Media/Trash/PickGlow.tga, the red glow round the slot the can
sits on: a bright red line on the slot's edge with a soft glow either side.
The slot fills the middle of the art, GLOW_MARGIN pixels in from each side,
so UI/Trash.lua lays it GLOW_MARGIN / (SIZE - 2 * GLOW_MARGIN) of the slot's
side past each edge (Trash.GLOW_REACH).
"""

import math
import os
import struct

SAMPLES = 4
SIZE = 64

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "Media", "Trash")


def hexrgb(value):
    value = value.lstrip("#")
    return tuple(int(value[i:i + 2], 16) / 255.0 for i in (0, 2, 4))


GOLD_HI = hexrgb("#FFF4CF")
GOLD = hexrgb("#E8C873")
METAL = hexrgb("#c8a44d")
METAL_LO = hexrgb("#7a5a1c")
EDGE = hexrgb("#050608")
GLOW = hexrgb("#FFD86A")


def mix(a, b, t):
    t = min(1.0, max(0.0, t))
    return tuple(a[i] + (b[i] - a[i]) * t for i in range(3))


def inside(polygon, x, y):
    result = False
    count = len(polygon)
    for i in range(count):
        ax, ay = polygon[i]
        bx, by = polygon[(i + 1) % count]
        if (ay > y) != (by > y):
            if x < ax + (y - ay) / (by - ay) * (bx - ax):
                result = not result
    return result


def edge_distance(polygon, x, y):
    best = 1e9
    count = len(polygon)
    for i in range(count):
        ax, ay = polygon[i]
        bx, by = polygon[(i + 1) % count]
        dx, dy = bx - ax, by - ay
        length = dx * dx + dy * dy
        t = 0.0 if length == 0 else max(0.0, min(1.0, ((x - ax) * dx + (y - ay) * dy) / length))
        best = min(best, math.hypot(x - (ax + t * dx), y - (ay + t * dy)))
    return best


def rect(x0, y0, x1, y1):
    return [(x0, y0), (x1, y0), (x1, y1), (x0, y1)]


# y grows downward, as the rows are written.
LID = rect(13, 16, 51, 23)
HANDLE = rect(25, 9, 39, 16)
HANDLE_HOLE = rect(29, 12.5, 35, 16)
BODY = [(17, 25), (47, 25), (43.5, 55), (20.5, 55)]
RIBS = [((26, 29), (27.2, 51)), ((32, 29), (32, 51)), ((38, 29), (36.8, 51))]
OUTLINE = 2.2


def segment_distance(a, b, x, y):
    return edge_distance([a, b], x, y)


def shapes(x, y):
    """The can's own colour at (x, y), or None outside it."""
    in_handle = inside(HANDLE, x, y) and not inside(HANDLE_HOLE, x, y)
    if inside(LID, x, y) or in_handle:
        t = (y - 9) / 14.0
        color = mix(GOLD_HI, METAL, t)
        # A bright line along the lid's top edge.
        if inside(LID, x, y) and y < 17.5:
            color = GOLD_HI
        return color
    if inside(BODY, x, y):
        across = (x - 17) / 30.0
        color = mix(GOLD, METAL_LO, abs(across - 0.38) * 1.6)
        for a, b in RIBS:
            if segment_distance(a, b, x, y) < 1.3:
                color = mix(color, METAL_LO, 0.75)
        return color
    return None


def near_shape(x, y):
    """How far (x, y) is from the nearest part of the can."""
    best = 1e9
    for polygon in (LID, BODY, HANDLE):
        if inside(polygon, x, y) and not (polygon is HANDLE and inside(HANDLE_HOLE, x, y)):
            return 0.0
        best = min(best, edge_distance(polygon, x, y))
    if inside(HANDLE_HOLE, x, y):
        best = min(best, edge_distance(HANDLE_HOLE, x, y))
    return best


def shade(x, y):
    color = shapes(x, y)
    if color:
        return color + (1.0,)
    distance = near_shape(x, y)
    if distance <= OUTLINE:
        return EDGE + (1.0,)
    # The soft gold glow round the edge, fading out.
    glow = max(0.0, 1.0 - (distance - OUTLINE) / 8.0)
    if glow <= 0:
        return None
    return GLOW + (0.55 * glow * glow,)


GLOW_RED = hexrgb("#FF3B30")
GLOW_HOT = hexrgb("#FFB0A8")
GLOW_MARGIN = SIZE / 7.0
GLOW_CORNER = 3.0


def slot_edge(x, y):
    """Signed distance to the slot's edge: below 0 inside, above 0 outside."""
    lo, hi = GLOW_MARGIN + GLOW_CORNER, SIZE - GLOW_MARGIN - GLOW_CORNER
    dx = max(lo - x, 0.0, x - hi)
    dy = max(lo - y, 0.0, y - hi)
    if dx > 0 or dy > 0:
        return math.hypot(dx, dy) - GLOW_CORNER
    return -min(x - GLOW_MARGIN, SIZE - GLOW_MARGIN - x, y - GLOW_MARGIN, SIZE - GLOW_MARGIN - y)


def glow(x, y):
    d = slot_edge(x, y)
    if abs(d) <= 0.9:
        return GLOW_HOT + (1.0,)
    if abs(d) <= 2.0:
        return GLOW_RED + (1.0,)
    if d > 0:
        reach = max(0.0, 1.0 - (d - 2.0) / (GLOW_MARGIN - 2.0))
        return GLOW_RED + (0.85 * reach * reach,)
    reach = max(0.0, 1.0 - (-d - 2.0) / 6.0)
    if reach <= 0:
        return None
    return GLOW_RED + (0.5 * reach * reach,)


def render(name, width, height, fn):
    pixels = []
    total = SAMPLES * SAMPLES
    # Bottom-up rows, the orientation a plain TGA declares.
    for row in range(height - 1, -1, -1):
        for column in range(width):
            r = g = b = a = 0.0
            for sy in range(SAMPLES):
                for sx in range(SAMPLES):
                    color = fn(column + (sx + 0.5) / SAMPLES, row + (sy + 0.5) / SAMPLES)
                    if color and color[3] > 0:
                        r += color[0] * color[3]
                        g += color[1] * color[3]
                        b += color[2] * color[3]
                        a += color[3]
            if a <= 0:
                pixels.append(b"\x00\x00\x00\x00")
                continue
            r, g, b = r / a, g / a, b / a
            pixels.append(bytes((
                int(round(min(1, b) * 255)), int(round(min(1, g) * 255)),
                int(round(min(1, r) * 255)), int(round(min(1, a / total) * 255)))))

    header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, width, height, 32, 8)
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, name + ".tga")
    with open(path, "wb") as handle:
        handle.write(header)
        handle.write(b"".join(pixels))
    print("wrote %s (%d bytes)" % (os.path.relpath(path, ROOT), os.path.getsize(path)))


def main():
    render("TrashCan", SIZE, SIZE, shade)
    render("PickGlow", SIZE, SIZE, glow)


if __name__ == "__main__":
    main()
