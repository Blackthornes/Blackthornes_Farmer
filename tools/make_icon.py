"""Draw tools/farmer.ico, the icon on the desktop shortcut.

    python tools/make_icon.py

The icon is committed, so this only needs running if the artwork changes. It is
here so the .ico is not an unexplained binary somebody has to reverse-engineer
or redraw from scratch.

Written without Pillow on purpose: this repository's only dependency is lupa,
for the Lua tests, and a build-time image library for one small icon is not
worth adding to that. PNG and ICO are both simple enough to emit directly.

The drawing is supersampled 4x and box-filtered down, which is what keeps the
diagonals of the arrow smooth at 16 pixels.
"""

import os
import struct
import zlib

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUTPUT = os.path.join(ROOT, "tools", "farmer.ico")

# The addon's own palette, so the shortcut matches the window it feeds.
PANEL = (0x16, 0x18, 0x1D)
BORDER = (0x4D, 0x55, 0x63)
GOLD = (0xC8, 0xA4, 0x4D)

SIZES = [16, 24, 32, 48, 64, 128, 256]
SUPERSAMPLE = 4


# -----------------------------------------------------------------------------
# Drawing
# -----------------------------------------------------------------------------

def rounded_rect(x, y, left, top, right, bottom, radius):
    """Is (x, y) inside this rounded rectangle?"""
    if x < left or x > right or y < top or y > bottom:
        return False

    # Only the corners need the distance test.
    cx = left + radius if x < left + radius else (
        right - radius if x > right - radius else x)
    cy = top + radius if y < top + radius else (
        bottom - radius if y > bottom - radius else y)

    if cx == x and cy == y:
        return True

    return (x - cx) ** 2 + (y - cy) ** 2 <= radius ** 2


def arrow_down(x, y, size):
    """A downward arrow: shaft, then head. Coordinates are 0..1 of `size`."""
    u, v = x / size, y / size

    # Shaft.
    if 0.43 <= u <= 0.57 and 0.18 <= v <= 0.52:
        return True

    # Head: a triangle narrowing to a point at the bottom.
    if 0.50 <= v <= 0.70:
        # How far through the head we are, 0 at the top and 1 at the tip.
        t = (v - 0.50) / 0.20
        half = 0.22 * (1.0 - t)
        return abs(u - 0.50) <= half

    return False


def tray(x, y, size):
    """The bar the arrow points into."""
    u, v = x / size, y / size
    return 0.22 <= u <= 0.78 and 0.76 <= v <= 0.86


def render(size):
    """One RGBA image, as a flat list of (r, g, b, a) tuples, row-major."""
    big = size * SUPERSAMPLE
    radius = big * 0.20
    inset = big * 0.02

    # Supersampled coverage: for each big pixel, which layer is on top.
    layers = []

    for y in range(big):
        row = []
        for x in range(big):
            px, py = x + 0.5, y + 0.5

            if arrow_down(px, py, big) or tray(px, py, big):
                row.append(GOLD)
            elif rounded_rect(px, py, inset, inset, big - inset, big - inset,
                              radius):
                # A thin lighter edge so the tile has a defined shape against a
                # dark wallpaper as well as a light one.
                edge = big * 0.055
                if not rounded_rect(px, py, inset + edge, inset + edge,
                                    big - inset - edge, big - inset - edge,
                                    radius * 0.82):
                    row.append(BORDER)
                else:
                    row.append(PANEL)
            else:
                row.append(None)          # transparent
        layers.append(row)

    # Box-filter down to the requested size.
    pixels = []
    area = SUPERSAMPLE * SUPERSAMPLE

    for y in range(size):
        for x in range(size):
            r = g = b = a = 0

            for dy in range(SUPERSAMPLE):
                for dx in range(SUPERSAMPLE):
                    sample = layers[y * SUPERSAMPLE + dy][x * SUPERSAMPLE + dx]
                    if sample is not None:
                        r += sample[0]
                        g += sample[1]
                        b += sample[2]
                        a += 255

            if a == 0:
                pixels.append((0, 0, 0, 0))
                continue

            # Average the colour over the covered samples only, so a partly
            # covered edge keeps its colour and loses alpha instead of
            # darkening towards black.
            covered = a // 255
            pixels.append((r // covered, g // covered, b // covered, a // area))

    return pixels


# -----------------------------------------------------------------------------
# PNG
# -----------------------------------------------------------------------------

def png_chunk(tag, payload):
    return (struct.pack(">I", len(payload)) + tag + payload
            + struct.pack(">I", zlib.crc32(tag + payload) & 0xFFFFFFFF))


def to_png(pixels, size):
    raw = bytearray()

    for y in range(size):
        raw.append(0)                     # filter: none
        for x in range(size):
            raw.extend(pixels[y * size + x])

    header = struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0)

    return (b"\x89PNG\r\n\x1a\n"
            + png_chunk(b"IHDR", header)
            + png_chunk(b"IDAT", zlib.compress(bytes(raw), 9))
            + png_chunk(b"IEND", b""))


# -----------------------------------------------------------------------------
# BMP, for the sizes the shell still prefers it at
# -----------------------------------------------------------------------------

def to_bmp(pixels, size):
    """A BITMAPINFOHEADER image: BGRA bottom-up, then the AND mask.

    The header claims twice the real height, which is how an icon says it
    carries a mask after the colour data. The mask is redundant for a 32-bit
    image but the format still wants it, padded to four-byte rows.
    """
    header = struct.pack("<IiiHHIIiiII",
                         40,              # header size
                         size, size * 2,  # width, doubled height
                         1, 32,           # planes, bits per pixel
                         0, 0,            # compression, image size
                         0, 0, 0, 0)      # resolution and palette

    body = bytearray()

    for y in range(size - 1, -1, -1):     # bottom-up
        for x in range(size):
            r, g, b, a = pixels[y * size + x]
            body.extend((b, g, r, a))

    # AND mask: one bit per pixel, rows padded to four bytes.
    mask_row_bytes = ((size + 31) // 32) * 4
    mask = bytearray()

    for y in range(size - 1, -1, -1):
        row = bytearray(mask_row_bytes)
        for x in range(size):
            if pixels[y * size + x][3] == 0:
                row[x // 8] |= 0x80 >> (x % 8)
        mask.extend(row)

    return header + bytes(body) + bytes(mask)


# -----------------------------------------------------------------------------

def main():
    images = []

    for size in SIZES:
        pixels = render(size)
        # PNG only for 256: it is the size that needs the compression, and
        # older shell code paths are happiest with BMP below it.
        data = to_png(pixels, size) if size == 256 else to_bmp(pixels, size)
        images.append((size, data))

    out = bytearray(struct.pack("<HHH", 0, 1, len(images)))

    offset = 6 + 16 * len(images)
    entries = bytearray()
    blobs = bytearray()

    for size, data in images:
        entries.extend(struct.pack(
            "<BBBBHHII",
            size if size < 256 else 0,
            size if size < 256 else 0,
            0, 0, 1, 32,
            len(data), offset))
        blobs.extend(data)
        offset += len(data)

    out.extend(entries)
    out.extend(blobs)

    with open(OUTPUT, "wb") as handle:
        handle.write(bytes(out))

    print("wrote %s (%d bytes, %s)" % (
        OUTPUT, len(out), ", ".join(str(s) for s in SIZES)))


if __name__ == "__main__":
    main()
