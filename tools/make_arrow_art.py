"""Draw Media/Arrow/*.tga, the goal arrow's dial: the gold ring with its four
gems and the arrow that turns inside it.

    python tools/make_arrow_art.py

Made with tools/make_frame_art.py's helpers, so the metal and the gems match
the house frame. The arrow is drawn pale and tinted in the game (gold while
it points the way, green once you are there), with a dark edge that stays
dark under any tint. Rerun this rather than editing the TGAs.
"""

import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import make_frame_art as art  # noqa: E402

art.OUT = os.path.join(art.ROOT, "Media", "Arrow")

GEM = art.hexrgb("#4fc8ff")
GEM_HI = art.hexrgb("#e6f8ff")
GEM_LO = art.hexrgb("#0b3a66")
FACE = art.hexrgb("#14161c")
FACE_HI = art.hexrgb("#2a2e38")


def ring():
    """The dial: a dark face in a bevelled gold ring, a gem at each corner."""
    size = 128
    c = size / 2.0
    outer, inner = 60.0, 48.0
    gem_radius = 8.0
    gem_at = (outer + inner) / 2.0
    gems = [(c + gem_at * math.cos(math.radians(a)), c + gem_at * math.sin(math.radians(a)))
            for a in (45, 135, 225, 315)]

    def shade(x, y):
        color = None
        r = math.hypot(x - c, y - c)

        if r <= inner:
            # The face, lit a little from the top.
            t = (y - (c - inner)) / (2 * inner)
            color = art.mix(FACE_HI, FACE, t) + (0.92,)
        elif r <= outer:
            # Metal, bright on the top-left of the band, dark on the bottom-right.
            across = (r - inner) / (outer - inner)
            light = 0.5 - 0.5 * ((x - c) + (y - c)) / (r * 1.414)
            band = 1 - abs(across - 0.5) * 2
            base = art.ramp([(0, art.METAL_LO), (0.45, art.METAL_MID), (0.8, art.METAL), (1, art.METAL_HI)],
                            light * 0.7 + band * 0.3)
            color = base + (1.0,)
            # A thin dark line either side of the band.
            if r - inner < 1.2 or outer - r < 1.2:
                color = art.EDGE + (1.0,)
            # A gold line just inside the band.
            elif abs(r - (inner + 2.5)) < 0.8:
                color = art.GOLD_HI + (1.0,)

        for gx, gy in gems:
            d = math.hypot(x - gx, y - gy)
            if d <= gem_radius:
                if d > gem_radius - 1.4:
                    gem = art.METAL_HI + (1.0,)
                else:
                    t = math.hypot(x - (gx - 2.5), y - (gy - 2.5)) / gem_radius
                    gem = art.ramp([(0, GEM_HI), (0.35, GEM), (1, GEM_LO)], t) + (1.0,)
                color = art.over(gem, color)

        return color

    art.render("Ring", size, size, shade)


def arrow():
    """A broad arrowhead pointing up, pale so the game can tint it."""
    size = 64
    c = size / 2.0
    # The shape: a tip, two wings and a notch in the tail.
    head = [(c, 5.0), (c + 21.0, 55.0), (c, 43.0), (c - 21.0, 55.0)]
    left_half = [(c, 5.0), (c, 43.0), (c - 21.0, 55.0)]

    def shade(x, y):
        if not art.inside(head, x, y):
            return None
        edge = art.edge_distance(head, x, y)
        if edge < 1.6:
            return art.EDGE + (1.0,)
        # The left wing lit, the right in shade, so it reads as a solid shape.
        lit = 1.0 if art.inside(left_half, x, y) else 0.72
        t = min(1.0, (edge - 1.6) / 6.0)
        tone = (0.80 + 0.20 * t) * lit
        return (tone, tone, tone, 1.0)

    art.render("Arrow", size, size, shade)


def main():
    ring()
    arrow()


if __name__ == "__main__":
    main()
