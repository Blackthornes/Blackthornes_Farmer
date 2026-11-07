"""Turn what you harvested in game into a data file, with no copying.

    python tools/harvest_import.py

A WoW addon cannot write a file. There is no `io` and no `os` inside the
client's Lua sandbox, so `/farm export` opening a window you copy out of is not
a shortcut -- it is the only thing an addon can do on its own.

What the client *can* do is write SavedVariables, which it does at every logout
and reload. Logic/Harvest.lua already persists there, so the moment you log out
your harvest is sitting in a real file on disk:

    WTF/Account/<ACCOUNT>/SavedVariables/Blackthornes_Farmer.lua

This script reads that file and writes Data/Data_Harvested.lua. Your loop
becomes: play, log out, run this, commit. Nothing to copy.

Since the Forever patch of 2026-09-24 the client reads SavedVariables back at
login, so that file holds everything you have ever harvested, not one session
of it. There is nothing to merge: this reads the total and writes it out. Run
it whenever you want the repository to catch up -- after every session, once a
week, whenever.

The export itself is not reimplemented here. This loads the addon under a real
Lua 5.1 runtime, hands it your saved records and calls the same
Harvest:ExportAll the in-game window calls, so the file on disk and the window
can never disagree about a drop rate.

Options:

    --sv PATH        read this SavedVariables file instead of searching
    --client PATH    search under this WoW install
    -o PATH          write somewhere other than Data/Data_Harvested.lua
    --stdout         print it instead of writing
    --list           show what was found and write nothing
    --allow-smaller  write even if it has fewer corpses than the file it replaces
    --shared         also fold in the drops players sent (sharedDrops,
                     Logic/Contribute.lua); the save itself is never changed
    --keep-published also keep what the file being replaced knows: each spot
                     keeps whichever side saw more corpses, so nothing shrinks
                     and nothing counts twice
"""

import argparse
import glob
import re
import os
import sys

from lupa import lua51 as luamod

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

SAVED_VARIABLE = "BlackthornesFarmerDB"
DEFAULT_OUTPUT = os.path.join(ROOT, "Data", "Data_Harvested.lua")

# What the addon adds to the saved harvest at the first login after the
# SavedVariables fix. A saved file without its stamp predates that login and
# holds only part of the total.
CARRYOVER = os.path.join(ROOT, "Data", "Harvest_Carryover.lua")
TOC = os.path.join(ROOT, "Blackthornes_Farmer.toc")
TOC_LINE = "Data\\Data_Harvested.lua"

# Where a Windows install usually lives. The owner's is the first one; the rest are
# ordinary defaults, so this works on someone else's machine too.
CLIENT_GUESSES = [
    r"D:\Blizzard\World of Warcraft",
    r"C:\Program Files (x86)\World of Warcraft",
    r"C:\Program Files\World of Warcraft",
    os.path.expanduser("~/Applications/World of Warcraft"),
    "/Applications/World of Warcraft",
]


def lua_path(path):
    """A path Lua can read, on any platform."""
    return path.replace("\\", "/")


def find_saved_variables(client=None):
    """Every Blackthornes_Farmer.lua under a WoW install, newest first.

    An install has one folder per game flavour and one per account, and a
    person can have several of each. Rather than guess which is the live one,
    take them all and let recency decide -- the file you just wrote by logging
    out is the one you meant.
    """
    roots = [client] if client else CLIENT_GUESSES
    found = []

    for root in roots:
        if not root or not os.path.isdir(root):
            continue

        pattern = os.path.join(
            root, "**", "WTF", "Account", "*", "SavedVariables",
            "Blackthornes_Farmer.lua")
        found.extend(glob.glob(pattern, recursive=True))

    # Deduplicate while keeping the newest first.
    unique = sorted(set(found), key=os.path.getmtime, reverse=True)
    return unique


def read_saved_variables(lua, path):
    """The saved BlackthornesFarmerDB table, or None if it holds no harvest.

    A SavedVariables file is plain Lua that assigns a global, so running it is
    how you read it. It is your own file, written by your own client.
    """
    chunk = lua.eval("loadfile([[%s]])" % lua_path(path))
    if chunk is None:
        raise SystemExit("could not parse %s -- is it a SavedVariables file?" % path)

    chunk()

    saved = lua.globals()[SAVED_VARIABLE]
    if saved is None:
        raise SystemExit(
            "%s holds no %s -- has the addon ever been loaded?"
            % (path, SAVED_VARIABLE))

    return saved


def carryover_id(lua):
    """The id the addon stamps the save with once the carryover is in, or None."""
    if not os.path.isfile(CARRYOVER):
        return None

    chunk = lua.eval("loadfile([[%s]])" % lua_path(CARRYOVER))
    if chunk is None:
        raise SystemExit("%s will not parse." % CARRYOVER)

    namespace = lua.table()
    chunk("Blackthornes_Farmer", namespace)

    carryover = namespace["HarvestCarryover"]
    return carryover["id"] if carryover is not None else None


def published_corpses(path):
    """How many corpses the data file about to be replaced was built from.

    Read off the header ExportAll writes, so it is None for a file this script
    did not write.
    """
    if not os.path.isfile(path):
        return None

    with open(path, encoding="utf-8") as handle:
        match = re.search(r"^-- \d+ mobs, (\d+) corpses looted\.",
                          handle.read(), re.M)

    return int(match.group(1)) if match else None


def published_casts(path):
    """How many fishing casts the data file about to be replaced was built from.

    0 for a file with no fishing line (written before fishing was recorded, or
    with nothing caught), None for a file that is not there.
    """
    if not os.path.isfile(path):
        return None

    with open(path, encoding="utf-8") as handle:
        match = re.search(r"^-- (\d+) fishing casts\.", handle.read(), re.M)

    return int(match.group(1)) if match else 0


def load_addon(lua, records, fishing=None, creature_types=None, tracker=None):
    """Load the addon against the stub client and hand it `records`.

    Restore also prunes coin entries that older versions of the addon wrote
    into the data as if they were drops, so importing an old file cleans it.
    """
    lua.execute("package.path = [[%s/?.lua;]] .. package.path" % lua_path(ROOT))
    lua.execute("lfs_cwd = [[%s]]" % lua_path(ROOT))

    env = lua.eval("dofile([[%s/tools/testenv.lua]])" % lua_path(ROOT))

    # InstallClient resets BlackthornesFarmerDB, so the saved table goes in
    # after the addon has loaded rather than before.
    ns = env.Load()

    # The saved file already holds the carryover -- main() checks its stamp --
    # so adding it again here would count those corpses twice.
    ns.HarvestCarryover = None
    ns.db.harvest = records

    # Catches are kept apart from the harvest (Logic/Fishing.lua) and written
    # into the same file.
    if fishing is not None:
        ns.db.fishing = fishing

    # Creature types read off mobs in game (Logic/Grinding.lua), written into
    # the same file for the Grind tab.
    if creature_types is not None:
        ns.db.creatureTypes = creature_types

    # The kills panel keeps each item's loot link colour, which is how the
    # world drop counts know green from blue (Logic/WorldDrops.lua). Only
    # read; nothing from it is written but those counts.
    if tracker is not None:
        ns.db.tracker = tracker

    restored = ns.Harvest.Restore(ns.Harvest)

    return ns, restored


# Adds one record's counts onto another, the way Logic/Share.lua merges a
# drop record: corpses and each item's count and corpses add up, levels
# widen, and empty names and places are filled. Only the copy in memory
# changes; the save on disk is never written.
FOLD_LUA = r"""
return function(records, shared)
    local added = 0
    if type(shared) ~= "table" then return 0 end
    for key, record in pairs(shared) do
        if type(key) == "string" and type(record) == "table"
            and type(record.corpses) == "number" and type(record.items) == "table" then
            local own = records[key]
            if type(own) ~= "table" then
                own = { mob = record.mob, zone = record.zone, location = record.location,
                        npc = record.npc, corpses = 0, items = {} }
                records[key] = own
            end
            own.corpses = (own.corpses or 0) + record.corpses
            if type(record.minLevel) == "number" then
                own.minLevel = math.min(own.minLevel or record.minLevel, record.minLevel)
            end
            if type(record.maxLevel) == "number" then
                own.maxLevel = math.max(own.maxLevel or record.maxLevel, record.maxLevel)
            end
            if own.coords == nil and type(record.coords) == "table" then
                own.coords = { record.coords[1], record.coords[2] }
            end
            if type(own.items) ~= "table" then own.items = {} end
            for name, item in pairs(record.items) do
                if type(name) == "string" and type(item) == "table" then
                    local mine = own.items[name]
                    if type(mine) ~= "table" then
                        mine = { name = item.name or name, id = item.id, count = 0, corpses = 0 }
                        own.items[name] = mine
                    end
                    mine.count = (mine.count or 0) + (tonumber(item.count) or 0)
                    mine.corpses = (mine.corpses or 0) + (tonumber(item.corpses) or 0)
                    if mine.id == nil then mine.id = item.id end
                end
            end
            added = added + 1
        end
    end
    return added
end
"""


def fold_shared(lua, records, shared):
    """Add the drops players sent onto the harvest about to be written.

    They are kept apart in the save (sharedDrops) so they never touch the
    player's own counts in game; here, only for the shipped data, they join
    in. Senders' names live only in the ledgers (sharedIn), never read here.
    """
    if shared is None:
        return 0
    return int(lua.execute(FOLD_LUA)(records, shared))


# Reading the file this tool wrote, so --keep-published can keep what it knows.
# The live save can hold less than the shipped file: it began at Forever's
# launch, and the file also holds older drops. Each mob at each spot keeps
# whichever side saw more corpses. Adding them instead would count twice every
# corpse both sides saw, and the shipped file does not say which those are.
SOURCE_FIELD = r'%s = "((?:[^"\\]|\\.)*)"'
SOURCE_LINE = re.compile(r'^\s+\{ ' + SOURCE_FIELD % "name")
CORPSES_LINE = re.compile(r"^\s+-- (\d+) of (\d+) corpses")


def lua_unescape(text):
    return text.replace('\\"', '"').replace("\\\\", "\\")


def read_published(path):
    """What the data file at `path` knows, or None if there is no such file."""
    if not os.path.isfile(path):
        return None

    with open(path, encoding="utf-8") as handle:
        lines = handle.read().split("\n")

    records, types, qualities = {}, {}, {}
    item, item_id, source, section = None, None, None, "items"

    for line in lines:
        if line.startswith("if DB.CreatureTypes"):
            section = "types"
        elif line.startswith("if DB.WorldDrops"):
            section = "world"
        elif line.startswith("}) end"):
            section = "items"
        elif section == "types":
            match = re.match(r'\s+\["(.*)"\] = "(.*)",$', line)
            if match:
                types[lua_unescape(match.group(1))] = lua_unescape(match.group(2))
        elif section == "world":
            match = re.match(r"\s+\{ \d+, (\d+), (\d+), \d+, ", line)
            if match:
                qualities[int(match.group(1))] = int(match.group(2))
        elif line.startswith("DB:RegisterItem"):
            item, item_id, source = None, None, None
        elif line.startswith('    name = "'):
            item = lua_unescape(re.match(r'    ' + SOURCE_FIELD % "name", line).group(1))
        elif line.startswith("    id = "):
            item_id = int(re.search(r"\d+", line).group())
        elif SOURCE_LINE.match(line):
            # Fishing rows count casts, not corpses, and are kept whole below.
            source = None
            if 'kind = "fishing"' not in line:
                source = {"mob": lua_unescape(SOURCE_LINE.match(line).group(1))}
                for field in ("zone", "location"):
                    match = re.search(SOURCE_FIELD % field, line)
                    if match:
                        source[field] = lua_unescape(match.group(1))
                match = re.search(r"coords = \{ ([\d.]+), ([\d.]+) \}", line)
                if match:
                    source["coords"] = [float(match.group(1)), float(match.group(2))]
                for field in ("minLevel", "maxLevel"):
                    match = re.search(field + r" = (\d+)", line)
                    if match:
                        source[field] = int(match.group(1))
        elif source is not None and CORPSES_LINE.match(line):
            held, corpses = (int(n) for n in CORPSES_LINE.match(line).groups())
            key = "%s|%s|%s" % (source["mob"], source.get("zone", "?"),
                                source.get("location", ""))
            record = records.setdefault(key, dict(source, corpses=corpses, items={}))
            record["corpses"] = max(record["corpses"], corpses)
            entry = {"name": item, "count": held, "corpses": held}
            if item_id:
                entry["id"] = item_id
            record["items"][item] = entry
            source = None

    return {"records": records, "types": types, "qualities": qualities}


def to_lua(lua, value):
    if isinstance(value, dict):
        return lua.table_from({key: to_lua(lua, inner) for key, inner in value.items()})
    if isinstance(value, list):
        return lua.table_from(value)
    return value


def keep_published(lua, saved, records, published):
    """Keep each spot's larger side. Only the copy in memory changes."""
    kept = 0
    for key, record in published["records"].items():
        own = records[key]
        if own is None or (own["corpses"] or 0) < record["corpses"]:
            records[key] = to_lua(lua, record)
            kept += 1

    if published["types"]:
        types = saved["creatureTypes"]
        if types is None:
            types = lua.table()
            saved["creatureTypes"] = types
        for name, kind in published["types"].items():
            if types[name] is None:
                types[name] = kind

    return kept


def know_qualities(lua, qualities):
    """Let the world drop counts know the colour of what the file already had.

    In game the client knows an item's quality. Here only the save's loot
    links do, and a spot kept from the file may have no link in this save.
    """
    if not qualities:
        return
    lua.eval(r"""function(known)
        local before = C_Item and C_Item.GetItemQualityByID
        C_Item = C_Item or {}
        C_Item.GetItemQualityByID = function(id)
            if known[id] then return known[id] end
            if before then return before(id) end
        end
    end""")(lua.table_from(qualities))


FISHING_SECTION = re.compile(r"-- Fishing\n.*?(?=\n-- Creature types|\n-- World drops|\Z)", re.S)
CASTS_LINE = re.compile(r"^-- \d+ fishing casts\.$", re.M)


def keep_fishing(text, path, casts_now, casts_before):
    """Fishing keeps whole, from whichever side made more casts."""
    if casts_before is None or casts_now >= casts_before:
        return text

    with open(path, encoding="utf-8") as handle:
        old = FISHING_SECTION.search(handle.read())

    if old is None:
        return text

    line = "-- %d fishing casts." % casts_before
    if FISHING_SECTION.search(text):
        text = FISHING_SECTION.sub(lambda _: old.group(0), text, count=1)
        return CASTS_LINE.sub(line, text, count=1)

    text = text.replace("\n--\n", "\n%s\n--\n" % line, 1)
    match = re.search(r"\n-- Creature types|\n-- World drops", text)
    at = match.start() if match else len(text)
    return text[:at].rstrip("\n") + "\n\n" + old.group(0) + "\n" + text[at:]


def describe(ns):
    harvest = ns.Harvest
    items = harvest.Items(harvest)

    lines = ["everything harvested so far: %d corpses across %d mobs" % (
        harvest.CountCorpses(harvest), harvest.CountMobs(harvest))]

    # A Lua table indexes from 1 and lupa keeps that.
    for index in range(1, len(items) + 1):
        item = items[index]
        lines.append("  %-24s %4d from %d corpses" % (
            item.name, item.count, item.corpses))

    casts = int(ns.Fishing.CountCasts(ns.Fishing))
    if casts:
        lines.append("and %d fishing casts" % casts)

    return "\n".join(lines)


def ensure_toc_line():
    """Add the generated file to the TOC if it is not already there.

    A file missing from the TOC never loads and the client says nothing about
    it, which is the single easiest way to lose an afternoon on this project.
    """
    with open(TOC, encoding="utf-8") as handle:
        content = handle.read()

    if TOC_LINE in content:
        return False

    # Last in load order: it registers items the seed files may also register,
    # and merging onto an existing item is what DB:RegisterItem does.
    content = content.rstrip("\n") + "\n" + TOC_LINE + "\n"

    with open(TOC, "w", encoding="utf-8") as handle:
        handle.write(content)

    return True


def main():
    parser = argparse.ArgumentParser(
        description="Write Data/Data_Harvested.lua from your in-game harvest.")
    parser.add_argument("--sv", help="path to Blackthornes_Farmer.lua")
    parser.add_argument("--client", help="path to the WoW install to search")
    parser.add_argument("-o", "--output", default=DEFAULT_OUTPUT)
    parser.add_argument("--stdout", action="store_true",
                        help="print the data file instead of writing it")
    parser.add_argument("--list", action="store_true",
                        help="report what was found and write nothing")
    parser.add_argument("--shared", action="store_true",
                        help="also fold in the drops players sent (sharedDrops)")
    parser.add_argument("--keep-published", action="store_true",
                        help="each spot keeps the larger of the save and the file")
    parser.add_argument("--allow-smaller", action="store_true",
                        help="write even if it has fewer corpses than before")
    args = parser.parse_args()

    if args.sv:
        if not os.path.isfile(args.sv):
            raise SystemExit("no such file: %s" % args.sv)
        path = args.sv
    else:
        candidates = find_saved_variables(args.client)

        if not candidates:
            raise SystemExit(
                "could not find Blackthornes_Farmer.lua.\n"
                "Log out of WoW once so the client writes it, then either run\n"
                "this again or point at it directly:\n"
                "    python tools/harvest_import.py --sv <path>")

        path = candidates[0]

        if len(candidates) > 1:
            print("found %d saved files; using the most recent:" % len(candidates))
            for candidate in candidates:
                print("  %s" % candidate)

    print("reading %s" % path)

    lua = luamod.LuaRuntime(unpack_returned_tuples=True)
    saved = read_saved_variables(lua, path)

    # Before the addon's first login on a client that reads saved variables
    # back, this file holds whatever the last session left and none of the
    # history kept in Data/Harvest_Carryover.lua. Writing the data file from it
    # would throw that history out of the repository.
    expected = carryover_id(lua)

    if expected is not None and saved["harvestCarryover"] != expected:
        raise SystemExit(
            "this saved file is from before the addon added your older harvest.\n"
            "Log in to WoW once with the latest version, then log out and run\n"
            "this again. Nothing has been changed.")

    records = saved["harvest"]

    if records is None or not list(records.keys()):
        raise SystemExit(
            "nothing harvested in that file yet.\n"
            "Loot some corpses, log out, and run this again.")

    if args.shared:
        added = fold_shared(lua, records, saved["sharedDrops"])
        print("folded in %d records players sent" % added)

    published = read_published(os.path.abspath(args.output)) if args.keep_published else None

    if published:
        print("kept %d spots from the file being replaced"
              % keep_published(lua, saved, records, published))

    ns, restored = load_addon(lua, records, saved["fishing"], saved["creatureTypes"],
                              saved["tracker"])

    if published:
        know_qualities(lua, published["qualities"])

    if restored == 0:
        raise SystemExit("the saved harvest holds no usable records.")

    print(describe(ns))

    harvest = ns.Harvest
    output = os.path.abspath(args.output)

    # The saved harvest only ever grows, so a smaller one means something went
    # wrong in game -- a reset, or a client that has stopped reading saved
    # variables back again. Either way the repository keeps what it has until
    # someone says otherwise.
    before = published_corpses(output)
    now = int(harvest.CountCorpses(harvest))

    if (before is not None and now < before and not args.allow_smaller
            and not args.keep_published and not (args.list or args.stdout)):
        raise SystemExit(
            "\nthe saved harvest has %d corpses but %s was built from %d.\n"
            "Nothing has been changed. To keep what that file knows too, run this\n"
            "again with --keep-published. If you cleared the harvest on purpose,\n"
            "use --allow-smaller. If not, send this to Claude."
            % (now, os.path.basename(output), before))

    # The same for fishing casts.
    casts_before = published_casts(output)
    casts_now = int(ns.Fishing.CountCasts(ns.Fishing))

    if (casts_before is not None and casts_now < casts_before and not args.allow_smaller
            and not args.keep_published and not (args.list or args.stdout)):
        raise SystemExit(
            "\nthe saved fishing record has %d casts but %s was built from %d.\n"
            "Nothing has been changed. If you cleared it on purpose,\n"
            "run this again with --allow-smaller. If not, send this to Claude."
            % (casts_now, os.path.basename(output), casts_before))

    text = harvest.ExportAll(harvest, lua.table(generated=True))

    if published:
        text = keep_fishing(text, output, casts_now, casts_before)

    if args.list:
        return 0

    if args.stdout:
        print()
        print(text)
        return 0

    os.makedirs(os.path.dirname(output), exist_ok=True)

    with open(output, "w", encoding="utf-8") as handle:
        handle.write(text.rstrip("\n") + "\n")

    print("\nwrote %s" % output)

    if output == os.path.abspath(DEFAULT_OUTPUT) and ensure_toc_line():
        print("added %s to Blackthornes_Farmer.toc" % TOC_LINE)
        print("that is a TOC change, so restart WoW rather than /reload.")

    return 0


if __name__ == "__main__":
    sys.exit(main())
