"""Rebuild Data/Harvest_Store.lua from Data/Data_Harvested.lua.

    python tools/harvest_recover.py

The store is the running total of everything ever harvested, and the generated
data file is derived from it. This goes the other way, which is what you want
when the store is missing but the generated file is not -- because it was lost,
because you are on a fresh checkout, or because the store did not exist yet
when the data was first imported.

That direction only works because the export is unusually complete: every
source row carries the mob, zone, subzone, coordinates and level band, and the
comment under it carries "N of M corpses" -- N the corpses that held the item,
M the corpses looted at that spot. Those are the two numbers a drop rate is
made of, so a store rebuilt from the export produces the same rates.

One field does not survive the round trip: `count`, the total quantity looted
as opposed to the number of corpses that held something. The export never
writes it because no published number depends on it -- it is the quantity
column in `/farm harvest` and the order that list sorts in, nothing more. It
comes back as N, which is the least it can possibly have been: you cannot get
an item off N corpses fewer than N times. Where it matters the store says so,
with a `recovered = true` marker on the entry.

Running this over a store that already exists refuses rather than overwrites.
Delete the store first if replacing it is genuinely what you want.
"""

import argparse
import os
import re
import sys

from lupa import lua51 as luamod

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

HARVESTED = os.path.join(ROOT, "Data", "Data_Harvested.lua")
STORE = os.path.join(ROOT, "Data", "Harvest_Store.lua")

# "-- 3 of 14 corpses" and "-- 3 of 14 corpses: too few for a rate" alike.
COMMENT = re.compile(r"^\s*--\s*(\d+) of (\d+) corpses\b")

# The line a comment belongs to: a source entry inside a sources = { } block.
SOURCE = re.compile(r'^\s*\{\s*name\s*=\s*"')


def lua_path(path):
    return path.replace("\\", "/")


def read_export(lua, path):
    """Every DB:RegisterItem call in the generated file, in order.

    Loaded rather than pattern-matched: the fields are Lua, and Lua is the only
    thing that reads Lua correctly. The stub collects the calls instead of
    building a database, so none of the addon needs to be present.
    """
    lua.execute("""
        collected = {}

        function make_ns()
            local ns = { DB = {} }
            function ns.DB:RegisterItem(item)
                collected[#collected + 1] = item
            end
            return ns
        end
    """)

    chunk = lua.eval("loadfile([[%s]])" % lua_path(path))
    if chunk is None:
        raise SystemExit("could not parse %s" % path)

    chunk(None, lua.eval("make_ns()"))

    return lua.globals()["collected"]


def read_corpse_counts(path):
    """The (held, looted) pair under each source row, in file order.

    The numbers live in comments, so the loaded file cannot carry them. They
    are read separately and zipped back onto the sources, which is safe only
    because both sequences come from the same file in the same order -- and
    that is checked rather than assumed, in `pair_up`.
    """
    counts = []
    pending = False

    with open(path, encoding="utf-8") as handle:
        for line in handle:
            match = COMMENT.match(line)

            if match:
                if not pending:
                    raise SystemExit(
                        "a corpse-count comment with no source above it:\n  %s"
                        % line.strip())
                counts.append((int(match.group(1)), int(match.group(2))))
                pending = False
                continue

            if SOURCE.match(line):
                if pending:
                    raise SystemExit(
                        "a source row with no corpse-count comment under it:\n  %s"
                        % line.strip())
                pending = True

    if pending:
        raise SystemExit("the last source row has no corpse-count comment")

    return counts


def pair_up(items, counts):
    """Walk the loaded items and the comment numbers together.

    Both are in file order, so the nth source row overall matches the nth
    comment. If the totals disagree the file is not the shape this expects and
    guessing which row lost its number would be worse than stopping.
    """
    rows = []
    index = 0

    for position in range(1, len(items) + 1):
        item = items[position]
        sources = item["sources"]

        for slot in range(1, len(sources) + 1):
            if index >= len(counts):
                raise SystemExit(
                    "%d source rows but only %d corpse counts -- is the file "
                    "hand-edited?" % (len(counts) + 1, len(counts)))

            rows.append((item, sources[slot], counts[index]))
            index += 1

    if index != len(counts):
        raise SystemExit(
            "%d source rows but %d corpse counts -- is the file hand-edited?"
            % (index, len(counts)))

    return rows


def build_records(rows):
    """Plain Python records, keyed the way the addon keys them."""
    records = {}

    for item, source, (held, looted) in rows:
        mob = source["name"]
        zone = source["zone"]
        location = source["location"]

        key = "%s|%s|%s" % (mob, zone, location or "")
        record = records.get(key)

        if record is None:
            record = {
                "mob": mob,
                "zone": zone,
                "corpses": looted,
                "items": {},
            }

            if location:
                record["location"] = location

            if source["coords"] is not None:
                coords = source["coords"]
                record["coords"] = [coords[1], coords[2]]

            if source["minLevel"] is not None:
                record["minLevel"] = int(source["minLevel"])
                record["maxLevel"] = int(
                    source["maxLevel"] if source["maxLevel"] is not None
                    else source["minLevel"])

            records[key] = record

        elif record["corpses"] != looted:
            # Every item found at one spot was found across the same corpses,
            # so the second number is the same on every row for that spot. If
            # it is not, the pairing above has slipped and the rates built
            # from it would be quietly wrong.
            raise SystemExit(
                "%s reports %d corpses on one row and %d on another"
                % (key, record["corpses"], looted))

        record["items"][item["name"]] = {
            "name": item["name"],
            "corpses": held,
            # The real quantity is gone; this is its floor. See the note at
            # the top about what `count` is and is not used for.
            "count": held,
            "recovered": True,
            "id": int(item["id"]) if item["id"] is not None else None,
        }

    return records


def lua_value(value, indent=""):
    """One Lua literal for `value`.

    A near-twin of the one in harvest_import, which serialises lupa tables
    read back out of Lua. This one takes the plain dicts and lists built
    above, so the two are deliberately not shared: merging them would mean a
    type switch in the middle of the only code that writes the store.
    """
    if value is None:
        return "nil"

    if isinstance(value, bool):
        return "true" if value else "false"

    if isinstance(value, (int, float)):
        if float(value).is_integer():
            return str(int(value))
        return "%.4f" % value

    if isinstance(value, str):
        return '"%s"' % value.replace("\\", "\\\\").replace('"', '\\"')

    if isinstance(value, list):
        return "{ %s }" % ", ".join(lua_value(entry, indent) for entry in value)

    pad = indent + "    "
    lines = ["{"]

    for key in sorted(value, key=str):
        if value[key] is None:
            continue
        lines.append("%s[%s] = %s," % (
            pad, lua_value(str(key)), lua_value(value[key], pad)))

    lines.append(indent + "}")
    return "\n".join(lines)


def write_store(records, path):
    with open(path, "w", encoding="utf-8") as handle:
        handle.write(
            "-- Everything Blackthornes Farmer has ever harvested, merged.\n"
            "--\n"
            "-- Written by tools/harvest_import.py. The addon never loads this\n"
            "-- file -- it is deliberately not in the .toc -- and it is not\n"
            "-- edited by hand. Data/Data_Harvested.lua is generated from it,\n"
            "-- so this is the file that must not be lost.\n"
            "\n"
            "BlackthornesFarmerHarvestStore = " + lua_value(records) + "\n")


def main():
    parser = argparse.ArgumentParser(
        description="Rebuild the harvest store from the generated data file.")
    parser.add_argument("--from", dest="source", default=HARVESTED,
                        help="the generated data file to read")
    parser.add_argument("-o", "--output", default=STORE,
                        help="where to write the store")
    parser.add_argument("--force", action="store_true",
                        help="overwrite an existing store")
    args = parser.parse_args()

    if not os.path.isfile(args.source):
        raise SystemExit("no such file: %s" % args.source)

    if os.path.isfile(args.output) and not args.force:
        raise SystemExit(
            "%s already exists.\n"
            "It is the running total, so this will not overwrite it. Delete it\n"
            "first, or pass --force, if starting it over is really what you want."
            % args.output)

    lua = luamod.LuaRuntime(unpack_returned_tuples=True)

    items = read_export(lua, args.source)
    counts = read_corpse_counts(args.source)
    records = build_records(pair_up(items, counts))

    if not records:
        raise SystemExit("%s holds no source rows to recover" % args.source)

    write_store(records, args.output)

    corpses = sum(record["corpses"] for record in records.values())
    print("recovered %d spot(s), %d corpses into %s"
          % (len(records), corpses, args.output))

    # A recovered store carries no record of which logout fed it, so the next
    # import cannot tell whether it is looking at one it has already counted.
    print("\nThe next import adds whatever your SavedVariables file holds on\n"
          "top of this. If that file still holds harvest this recovered, log\n"
          "in and out once first so the client writes a fresh one.")

    return 0


if __name__ == "__main__":
    sys.exit(main())
