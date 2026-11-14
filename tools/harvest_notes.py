"""The "-- N of M corpses" notes under each row of Data/Data_Harvested.lua.

They are comments, so the game skips them, but the client still reads every
line of a file it loads. They live here in tools/ instead, beside the rows
they belong to, so `harvest_import.py --keep-published` can still rebuild a
record from the shipped file. The data the game reads does not change.

    python tools/harvest_notes.py [Data/Data_Harvested.lua]

moves the notes out of an older data file that still has them inline. It
needs nothing but Python and never touches a saved variables file.
"""

import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEFAULT_DATA = os.path.join(ROOT, "Data", "Data_Harvested.lua")

NOTE_LINE = re.compile(r"^\s+-- \d+ of \d+ corpses")
ITEM_LINE = re.compile(r'^    name = "')
SOURCE_LINE = re.compile(r'^\s+\{ name = "')
HEADER = ("# The corpse counts under each row of %s, one a line:\n"
          "# item line, row, note. Written by tools/harvest_import.py. Not shipped.\n")


def notes_path(data_path):
    """Where the notes for the data file at `data_path` are kept."""
    data_path = os.path.abspath(data_path)
    root = os.path.dirname(os.path.dirname(data_path))
    name = os.path.splitext(os.path.basename(data_path))[0]
    return os.path.join(root, "tools", name + "_corpses.txt")


def split_notes(text):
    """The data text without its notes, and the notes as (item, row, note)."""
    kept, notes = [], []
    item, row = None, None

    for line in text.split("\n"):
        if NOTE_LINE.match(line) and row is not None:
            notes.append((item or "", row, line.strip()))
            continue
        if line.startswith("DB:RegisterItem"):
            item, row = None, None
        elif ITEM_LINE.match(line):
            item = line.strip()
        elif SOURCE_LINE.match(line):
            row = line.strip()
        kept.append(line)

    return "\n".join(kept), notes


def write_notes(path, notes, data_name="Data/Data_Harvested.lua"):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as handle:
        handle.write(HEADER % data_name)
        for item, row, note in notes:
            handle.write("%s\t%s\t%s\n" % (item, row, note))


def read_notes(path):
    """{ (item line, row): [note, ...] } from the notes file, or {} with none."""
    found = {}
    if not os.path.isfile(path):
        return found
    with open(path, encoding="utf-8") as handle:
        for line in handle:
            line = line.rstrip("\n")
            if not line or line.startswith("#"):
                continue
            parts = line.split("\t")
            if len(parts) != 3:
                continue
            found.setdefault((parts[0], parts[1]), []).append(parts[2])
    return found


def main(argv):
    data = os.path.abspath(argv[1]) if len(argv) > 1 else DEFAULT_DATA
    if not os.path.isfile(data):
        raise SystemExit("no such file: %s" % data)

    with open(data, encoding="utf-8") as handle:
        text = handle.read()

    clean, notes = split_notes(text)
    if not notes:
        print("%s has no notes inline; nothing to move." % data)
        return 0

    write_notes(notes_path(data), notes)
    with open(data, "w", encoding="utf-8") as handle:
        handle.write(clean)

    print("moved %d notes to %s" % (len(notes), notes_path(data)))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
