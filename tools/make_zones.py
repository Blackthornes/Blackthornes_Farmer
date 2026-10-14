"""Writes Data/Zones.lua: Forever's zones by map ID, and their German names.

Run from the repository root with the Forever client's game tables exported
as CSV, one file per table, the English ones in one folder and the German
(deDE) ones in another:

    python tools/make_zones.py <tables> <tables-deDE> <build>

It reads AreaTable (each zone and dungeon as GetRealZoneText names it),
Map (each instance) and UiMap (each zone's map ID, as C_Map numbers it).
What it writes:

- ns.ZONE_DATA.maps: each zone's map ID by its English name, so a client in
  another language is told its zone by the map it stands on (Spots.ZONE_MAPS).
- ns.ZONE_DATA.names.deDE: each zone, dungeon and raid's German name by its
  English one, for showing (Spots.Show).
- ns.ZONE_DATA.english.deDE: the English name of every German name the
  client can give, so a record kept under a German name finds its zone without the
  player standing in it first (Spots.English).
- ns.ZONE_DATA.instances: "dungeon" or "raid" by each instance's English
  name, as the map and GetRealZoneText inside it give it, for Rankings'
  "Outside dungeons only" (Spots.IsInstance). A name that is also an open
  world zone ("Deadwind Pass") is left out.

Only names: the client's tables carry no drop rates or spawn spots. Rows the
client keeps for tests and cut content are left out, and so is any name the
clear-to-post scan (tools/check_package.py's PRIVATE list) would refuse.

Never edit the output by hand; rerun this when the client's tables change.
"""

import csv
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from check_package import PRIVATE  # noqa: E402

OUT = Path("Data/Zones.lua")

# The world: Eastern Kingdoms (0) and Kalimdor (1).
CONTINENTS = {"0", "1"}

# Instance types worth naming: dungeons (1), raids (2), battlegrounds (3).
INSTANCES = {"1", "2", "3"}

# Instance types that are dungeons or raids, and what the data calls them.
DUNGEON_KINDS = {"1": "dungeon", "2": "raid"}

# Rows the client keeps for tests, cut content and its own lists.
JUNK = re.compile(
    r"unused|delete me|test|\*\*\*|prototype|^nine$|^city$|^crafting$|"
    r"programmer|designer|gm island|nothing to see|barracks|preserved|"
    r"scarlet raid phase|\(winter\)",
    re.I)


def read(folder, table):
    path = Path(folder) / f"{table}.csv"
    with path.open(encoding="utf-8", newline="") as handle:
        return list(csv.DictReader(handle))


def usable(name):
    return (bool(name) and not JUNK.search(name)
            and not any(pattern.search(name) for _, pattern in PRIVATE))


def lua_string(text):
    return '"' + text.replace("\\", "\\\\").replace('"', '\\"') + '"'


def build(english, german):
    """Return (maps, deDE, fromDeDE, instances) from the two folders' tables."""
    areas = read(english, "AreaTable")
    areas_de = {row["ID"]: row["AreaName_lang"] for row in read(german, "AreaTable")}
    instances = {row["ID"]: row for row in read(english, "Map")}
    instances_de = {row["ID"]: row["MapName_lang"] for row in read(german, "Map")}
    ui_maps = read(english, "UiMap")
    ui_maps_de = {row["ID"]: row["Name_lang"] for row in read(german, "UiMap")}

    # (English, German, rank): a lower rank wins when an English name has
    # more than one German one. The zone's own area beats the world map's
    # name, and the open world beats an instance's copy of it.
    pairs = []

    for row in areas:
        if row["ParentAreaID"] != "0":
            continue
        continent = row["ContinentID"]
        if continent in CONTINENTS:
            rank = 0
        elif instances.get(continent, {}).get("InstanceType") in INSTANCES:
            rank = 2
        else:
            continue
        pairs.append((row["AreaName_lang"], areas_de.get(row["ID"], ""), rank))

    for row in instances.values():
        if row["InstanceType"] in INSTANCES:
            pairs.append((row["MapName_lang"], instances_de.get(row["ID"], ""), 3))

    maps = {}
    for row in ui_maps:
        # Zones (3) and battlegrounds (6), on a continent or the world map.
        if row["Type"] not in ("3", "6") or row["ParentUiMapID"] == "0":
            continue
        name = row["Name_lang"]
        if row["Type"] == "3" and usable(name):
            maps.setdefault(name, int(row["ID"]))
        pairs.append((name, ui_maps_de.get(row["ID"], ""), 1))

    show, back = {}, {}
    for name, local, rank in sorted(pairs, key=lambda pair: pair[2]):
        if not (usable(name) and usable(local)) or name == local:
            continue
        show.setdefault(name, local)
        back.setdefault(local, name)

    return maps, show, back, dungeons(areas, instances, maps)


# AreaTable's flag for an area that is a zone of the open world. Blackrock
# Depths and Onyxia's Lair have a top level area on the continent too, but
# without it.
ZONE_FLAG = 64


def dungeons(areas, instances, maps):
    """Each dungeon and raid by its English name: "dungeon" or "raid"."""
    world_zones = set(maps)
    for row in areas:
        if (row["ContinentID"] in CONTINENTS and row["ParentAreaID"] == "0"
                and int(row.get("Flags_0") or 0) & ZONE_FLAG):
            world_zones.add(row["AreaName_lang"])

    found = {}

    def add(name, kind):
        # A name the open world has as a zone ("Deadwind Pass") is never
        # taken for an instance.
        if usable(name) and name not in world_zones:
            found.setdefault(name, kind)

    for row in instances.values():
        kind = DUNGEON_KINDS.get(row["InstanceType"])
        if kind:
            add(row["MapName_lang"], kind)
    for row in areas:
        kind = DUNGEON_KINDS.get(instances.get(row["ContinentID"], {}).get("InstanceType"))
        if kind and row["ParentAreaID"] == "0":
            add(row["AreaName_lang"], kind)

    return found


def write(maps, show, back, instances, build_name):
    out = [
        "-- Blackthornes Farmer -- Data/Zones.lua",
        f"-- Generated by tools/make_zones.py from the Forever client's game tables",
        f"-- (build {build_name}); never edit by hand. Zone names and map IDs only.",
        "",
        "local _, ns = ...",
        "",
        "ns.ZONE_DATA = {",
        f"    build = {lua_string(build_name)},",
        "",
        "    -- Each zone's map ID (C_Map), by its English name.",
        "    maps = {",
    ]
    for name, map_id in sorted(maps.items(), key=lambda item: item[1]):
        out.append(f"        [{lua_string(name)}] = {map_id},")
    out += ["    },", "", "    -- Each zone, dungeon and raid's name in a client's language, by its",
            "    -- English one.", "    names = {", "        deDE = {"]
    for name in sorted(show):
        out.append(f"            [{lua_string(name)}] = {lua_string(show[name])},")
    out += ["        },", "    },", "",
            "    -- The English name of each name a client in that language gives.",
            "    english = {", "        deDE = {"]
    for local in sorted(back):
        out.append(f"            [{lua_string(local)}] = {lua_string(back[local])},")
    out += ["        },", "    },", "",
            "    -- Each dungeon and raid, by its English name: \"dungeon\" or \"raid\".",
            "    instances = {"]
    for name in sorted(instances):
        out.append(f"        [{lua_string(name)}] = {lua_string(instances[name])},")
    out += ["    },", "}", ""]
    OUT.write_text("\n".join(out), encoding="utf-8", newline="\n")


def main():
    if len(sys.argv) != 4:
        sys.exit(__doc__)
    maps, show, back, instances = build(sys.argv[1], sys.argv[2])
    write(maps, show, back, instances, sys.argv[3])
    print(f"{OUT}: {len(maps)} zone maps, {len(show)} German names, "
          f"{len(back)} German names read back, {len(instances)} dungeons and raids")


if __name__ == "__main__":
    main()
