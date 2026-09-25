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

# Where a Windows install usually lives. Trent's is the first one; the rest are
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


def load_addon(lua, records, fishing=None):
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

    restored = ns.Harvest.Restore(ns.Harvest)

    return ns, restored


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

    ns, restored = load_addon(lua, records, saved["fishing"])

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
            and not (args.list or args.stdout)):
        raise SystemExit(
            "\nthe saved harvest has %d corpses but %s was built from %d.\n"
            "Nothing has been changed. If you cleared the harvest on purpose,\n"
            "run this again with --allow-smaller. If not, send this to Claude."
            % (now, os.path.basename(output), before))

    # The same for fishing casts.
    casts_before = published_casts(output)
    casts_now = int(ns.Fishing.CountCasts(ns.Fishing))

    if (casts_before is not None and casts_now < casts_before and not args.allow_smaller
            and not (args.list or args.stdout)):
        raise SystemExit(
            "\nthe saved fishing record has %d casts but %s was built from %d.\n"
            "Nothing has been changed. If you cleared it on purpose,\n"
            "run this again with --allow-smaller. If not, send this to Claude."
            % (casts_now, os.path.basename(output), casts_before))

    text = harvest.ExportAll(harvest, lua.table(generated=True))

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
