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

It works whether or not this client reads SavedVariables back at login, which
is the open question about Forever -- reading the file from outside only needs
the client to have written it.

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
"""

import argparse
import glob
import hashlib
import os
import sys

from lupa import lua51 as luamod

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

SAVED_VARIABLE = "BlackthornesFarmerDB"
DEFAULT_OUTPUT = os.path.join(ROOT, "Data", "Data_Harvested.lua")

# Everything ever harvested, merged. The generated data file is derived from
# this, not from whatever one session happened to hold.
#
# It exists because the addon cannot accumulate on its own: this client is
# reported to write saved variables without reading them back, so the addon
# starts empty every login and its file only ever describes the last session
# that looted anything. Keeping the running total here, where both sides can
# be read, is the only place it can safely live.
STORE = os.path.join(ROOT, "Data", "Harvest_Store.lua")
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


def read_store(lua):
    """The accumulated records from a previous import, and what fed them.

    Returns (records, digest). The digest identifies the SavedVariables file
    the last import read; see `digest_of` for what it is for.
    """
    if not os.path.isfile(STORE):
        return None, None

    chunk = lua.eval("loadfile([[%s]])" % lua_path(STORE))
    if chunk is None:
        raise SystemExit(
            "%s will not parse. Delete it and re-import to start it over."
            % STORE)

    chunk()

    return (lua.globals()["BlackthornesFarmerHarvestStore"],
            lua.globals()["BlackthornesFarmerHarvestSource"])


def digest_of(path):
    """A fingerprint of the SavedVariables file this import is reading.

    Each run adds the session to a running total, so running it twice over the
    same file would count those corpses twice. The client only rewrites the
    file at logout or reload, so an unchanged file means there is nothing new
    in it -- and double-clicking the desktop shortcut a second time should
    say so rather than quietly inflating every number in the repository.
    """
    with open(path, "rb") as handle:
        return hashlib.sha256(handle.read()).hexdigest()


def merge_records(lua, into, extra):
    """Add `extra`'s records to `into`, in place.

    Two records are the same spot when they carry the same key -- mob, zone
    and subzone. Corpse counts add up, item counts add up, the level band
    widens to cover both, and coordinates are kept from whichever saw them
    first, because one set of coordinates for a camp is enough.

    Fields are read with ["name"] rather than .name throughout. A lupa table
    is also a Python mapping, so record.items is the mapping's own items()
    method and never the Lua field called "items" -- which is exactly the
    field every record here carries. Attribute access reads whichever of the
    two Python happens to find first, so it is not used at all.
    """
    if extra is None:
        return into

    for key in list(extra.keys()):
        incoming = extra[key]

        if into[key] is None:
            into[key] = incoming
            continue

        existing = into[key]
        existing["corpses"] = (existing["corpses"] or 0) + (incoming["corpses"] or 0)

        if incoming["coords"] is not None and existing["coords"] is None:
            existing["coords"] = incoming["coords"]

        for field, pick in (("minLevel", min), ("maxLevel", max)):
            mine, theirs = existing[field], incoming[field]
            if theirs is not None:
                existing[field] = theirs if mine is None else pick(mine, theirs)

        arrivals = incoming["items"]
        held_items = existing["items"]

        if arrivals is None:
            continue

        if held_items is None:
            existing["items"] = arrivals
            continue

        for name in list(arrivals.keys()):
            arriving = arrivals[name]
            held = held_items[name]

            if held is None:
                held_items[name] = arriving
                continue

            held["count"] = (held["count"] or 0) + (arriving["count"] or 0)
            held["corpses"] = (held["corpses"] or 0) + (arriving["corpses"] or 0)

            if held["id"] is None:
                held["id"] = arriving["id"]

    return into


def lua_value(value, indent=""):
    """One Lua literal for `value`, which may be a lupa table.

    Written in Python rather than Lua because the escaping of a Lua string
    inside a Python string inside generated Lua is exactly the kind of thing
    that goes quietly wrong. Keys are sorted so an unchanged import produces an
    unchanged file.
    """
    if value is None:
        return "nil"

    if isinstance(value, bool):
        return "true" if value else "false"

    if isinstance(value, (int, float)):
        # Whole numbers should not come back as 3.0.
        if float(value).is_integer():
            return str(int(value))
        return "%.4f" % value

    if isinstance(value, str):
        return '"%s"' % value.replace("\\", "\\\\").replace('"', '\\"')

    keys = list(value.keys())

    # An array, such as a coordinate pair, stays on one line.
    if keys and all(isinstance(k, int) for k in keys):
        return "{ %s }" % ", ".join(
            lua_value(value[k], indent) for k in sorted(keys))

    if not keys:
        return "{}"

    pad = indent + "    "
    lines = ["{"]

    for key in sorted(keys, key=str):
        lines.append("%s[%s] = %s," % (
            pad, lua_value(str(key)), lua_value(value[key], pad)))

    lines.append(indent + "}")
    return "\n".join(lines)


def write_store(lua, records, digest=None):
    """Save the merged records as a Lua table the next run can read back."""
    with open(STORE, "w", encoding="utf-8") as handle:
        handle.write(
            "-- Everything Blackthornes Farmer has ever harvested, merged.\n"
            "--\n"
            "-- Written by tools/harvest_import.py. The addon never loads this\n"
            "-- file -- it is deliberately not in the .toc -- and it is not\n"
            "-- edited by hand. Data/Data_Harvested.lua is generated from it,\n"
            "-- so this is the file that must not be lost.\n"
            "\n"
            "BlackthornesFarmerHarvestStore = " + lua_value(records) + "\n"
            "\n"
            "-- The SavedVariables file the last import read, so running it\n"
            "-- again over the same logout adds nothing a second time.\n"
            "BlackthornesFarmerHarvestSource = " + lua_value(digest) + "\n")


def load_addon(lua, records):
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

    ns.db.harvest = records
    restored = ns.Harvest.Restore(ns.Harvest)

    return ns, restored


def describe(ns):
    harvest = ns.Harvest
    items = harvest.Items(harvest)

    lines = ["%d corpses looted across %d mobs" % (
        harvest.CountCorpses(harvest), harvest.CountMobs(harvest))]

    # A Lua table indexes from 1 and lupa keeps that.
    for index in range(1, len(items) + 1):
        item = items[index]
        lines.append("  %-24s %4d from %d corpses" % (
            item.name, item.count, item.corpses))

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

    # This session's records, merged onto everything kept from before.
    #
    # Either side may be empty and that is fine: a login where nothing was
    # looted contributes nothing, and the first ever run has no store. What
    # must never happen is a thin session replacing a full history, which is
    # exactly what used to occur.
    store, last_source = read_store(lua)
    session = saved.harvest
    source = digest_of(path)

    # Adding each logout to a running total is only correct while the addon
    # starts every login empty. If it ever restores records at login, the file
    # already contains what the store contains and adding it would count the
    # same corpses twice. The addon stamps the save with what it restored, so
    # this is the client answering the question rather than a guess about it.
    restored_in_game = saved["harvestRestored"]

    if restored_in_game is not None and restored_in_game > 0:
        raise SystemExit(
            "this client read %d spot(s) back out of SavedVariables at login.\n"
            "\n"
            "That is good news -- the addon can accumulate on its own now -- but\n"
            "it means the file already holds what %s holds, and adding one to\n"
            "the other would count the same corpses twice. Nothing has been\n"
            "changed. Send this message to Claude.\n"
            % (int(restored_in_game), os.path.basename(STORE)))

    # A login that looted nothing still leaves an empty table behind, which is
    # not the same as no table at all but contributes exactly as much.
    if session is not None and not list(session.keys()):
        session = None

    # The same logout, read a second time. The client only rewrites this file
    # when you log out or reload, so identical bytes mean identical records --
    # already in the store, and not to be added again.
    already_merged = session is not None and source == last_source

    if already_merged:
        session = None

    if session is None and store is None:
        raise SystemExit(
            "nothing harvested in that file yet.\n"
            "Loot some corpses, log out, and run this again.")

    if store is None:
        merged = session
        print("starting a new harvest store")
    else:
        before = len(list(store.keys()))
        merged = merge_records(lua, store, session)
        after = len(list(merged.keys()))

        if already_merged:
            added = "already imported, nothing added"
        elif session is None:
            added = "nothing new"
        else:
            added = "%d spot(s) added" % (after - before)

        print("merged into %d spot(s) already recorded (%s)" % (before, added))

    ns, restored = load_addon(lua, merged)

    if restored == 0:
        raise SystemExit("the saved harvest holds no usable records.")

    print(describe(ns))

    harvest = ns.Harvest

    # Written back after the prune, so coins recorded by an older version are
    # gone from the store too rather than being re-dropped on every import.
    if not args.list:
        write_store(lua, ns.Harvest.records, source)

    text = harvest.ExportAll(harvest, lua.table(generated=True))

    if args.list:
        return 0

    if args.stdout:
        print()
        print(text)
        return 0

    output = os.path.abspath(args.output)
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
