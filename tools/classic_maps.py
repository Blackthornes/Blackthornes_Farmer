"""Moves Classic's map spots onto Forever's own maps.

Classic's drop spots (Data/Data_ClassicDrops.lua) are numbers on a zone's
map. Most of Forever's zone maps cover the same ground as Classic's, so the
numbers point at the same place. Mulgore's does not: Forever's map reaches
further on every side, so a Classic spot read on it lands north and west of
where the mob stands. Tradeskills found it first, when Show the way sent
players just north of Thunder Bluff (2026-11-17); its tools/classic_maps.py
holds the same bounds.

The bounds below are where each map starts and ends in the world, as
{ left, right, top, bottom } in world Y (east to west) and world X (north to
south). Forever's come from its client's UiMapAssignment table. Classic's
are the ones its numbers were measured on. Every other zone already
matched, so only Mulgore is listed.

make_classic_drops.py calls forever_spot() on every spot it writes. To move
the spots in a file written before that:

    python tools/classic_maps.py

It changes only Mulgore's numbers, and only once: a moved file says so in
its header and is left alone after that.
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

# zone: (Classic's bounds, Forever's bounds)
MOVED = {
    "Mulgore": (
        (2047.917, -3089.583, -272.917, -3697.917),
        (2479.167, -3675.0, 266.666, -3835.416),
    ),
}

MARK = "-- Mulgore's spots are on Forever's Mulgore map (tools/classic_maps.py)."


def forever_spot(zone, x, y):
    """(x, y) on Forever's map of the zone, from Classic's x, y on it."""
    if zone not in MOVED:
        return x, y
    (cl, cr, ct, cb), (fl, fr, ft, fb) = MOVED[zone]
    world_y = cl - x / 100 * (cl - cr)
    world_x = ct - y / 100 * (ct - cb)
    return (fl - world_y) / (fl - fr) * 100, (ft - world_x) / (ft - fb) * 100


NUM = r"(-?\d+(?:\.\d+)?)"
PATTERNS = {
    "Data/Data_ClassicDrops.lua": re.compile(
        r'(zone = "Mulgore", coords = \{ )' + NUM + ", " + NUM),
}


def move_file(rel):
    path = ROOT / rel
    text = path.read_text(encoding="utf-8")
    if MARK in text:
        return 0
    count = 0

    def swap(m):
        nonlocal count
        count += 1
        x, y = forever_spot("Mulgore", float(m.group(2)), float(m.group(3)))
        return "%s%.1f, %.1f" % (m.group(1), x, y)

    text = PATTERNS[rel].sub(swap, text)
    text = text.replace("\nlocal _, ns = ...", "\n" + MARK + "\n\nlocal _, ns = ...", 1)
    path.write_text(text, encoding="utf-8", newline="\n")
    return count


def main():
    for rel in PATTERNS:
        print(f"{rel}: {move_file(rel)} Mulgore spot(s) moved")
    return 0


if __name__ == "__main__":
    sys.exit(main())
