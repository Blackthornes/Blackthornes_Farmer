"""Writes Data/Data_KnownDrops.lua: mobs known to drop items the data lacks.

Run from the repository root:

    python tools/make_known_drops.py <drop list> <Classic data> <Forever tables folder>

  drop list               a folder with item.json and npc.json: Forever's
                          items, each with the IDs of the mobs that drop it
                          (`crs`) and the map spots it is found on
                          (`coords`, `in_map`), and mobs with their spots
  Classic data            Classic 1.12's spawns and names, the same folder
                          tools/make_classic_drops.py reads
  Forever tables folder   the Forever client's game tables as CSV: Item.csv
                          and ItemSparse.csv

So the search can say who drops an item nobody has looted yet. Only items no
other data file registers are written, so a looted row, a hand-typed one or
a Classic lead is never doubled. No drop rates are written: the list names
mobs, not how often they drop it, and a rate is the player's to find. Every
row is `searchOnly`, like Data/Data_ClassicDrops.lua, so it feeds the search,
the item tooltip and Spots, never worth, Rankings or the Grind tab.

Where each mob stands, first found wins:

  1. Our own looted rows (Data/Data_Harvested.lua) for that mob's name: the
     spot, its levels and its subzone as the game showed them.
  2. Classic's spawns for that mob, in a zone the item is found in when the
     list says so.
  3. The list's own spot for that mob, with Classic's levels.

A mob with no name, no zone or no levels is left out. A mob name the
clear-to-post scan would refuse (tools/check_package.py's PRIVATE list) is
left out, so the package always passes it.

Never edit the output by hand; rerun this.
"""

import csv
import json
import re
import sys
from collections import Counter, defaultdict
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from check_package import PRIVATE  # noqa: E402
from classic_maps import forever_spot  # noqa: E402
from make_classic_drops import (  # noqa: E402
    CATEGORIES, COORD, ITEM_BLOCK, LEVEL, NAME, QUEST_ITEMS, RECIPES, TRADE_GOODS, lua_string)

OUT = Path("Data/Data_KnownDrops.lua")
ZONES = Path("Data/Zones.lua")
HARVESTED = Path("Data/Data_Harvested.lua")
NAME_FILES = [Path("Data/ForeverNpcNames.lua"), Path("Data/NpcNames.lua")]
MAX_SPOTS = 8

ROW = re.compile(r'\{ name = "((?:[^"\\]|\\.)*)", zone = "((?:[^"\\]|\\.)*)"(.*?)\},?\n')
FIELD_TEXT = re.compile(r'(\w+) = "((?:[^"\\]|\\.)*)"')
FIELD_NUM = re.compile(r'(\w+) = (-?[\d.]+)')
FIELD_XY = re.compile(r'coords = \{ ([\d.]+), ([\d.]+) \}')


def unescape(text):
    return text.replace("\\'", "'").replace('\\"', '"').replace("\\\\", "\\")


def zone_tables():
    """({ map ID: zone }, { instance names }) from Data/Zones.lua."""
    text = ZONES.read_text(encoding="utf-8")
    maps = re.search(r"maps = \{(.*?)\n    \}", text, re.S).group(1)
    by_id = {int(i): n for n, i in re.findall(r'\["([^"]+)"\] = (\d+),', maps)}
    inside = re.search(r"instances = \{(.*?)\n    \}", text, re.S).group(1)
    return by_id, set(re.findall(r'\["([^"]+)"\] = "', inside))


def registered():
    """Item IDs and names the other data files already register."""
    ids, names = set(), set()
    for path in Path("Data").glob("Data_*.lua"):
        if path == OUT:
            continue
        text = path.read_text(encoding="utf-8")
        ids |= {int(x) for x in re.findall(r"\bid = (\d+)", text)}
        names |= {unescape(n).lower() for n in re.findall(
            r'RegisterItem\(\{\s*name = "((?:[^"\\]|\\.)*)"', text)}
    return ids, names


def looted_spots():
    """{ mob name: [spot, ...] } from our own looted rows, most kills first
    (the file lists a mob's best rows first, so file order is kept)."""
    spots = defaultdict(list)
    for name, zone, rest in ROW.findall(HARVESTED.read_text(encoding="utf-8")):
        if "provenance = \"forever\"" not in rest:
            continue
        nums = dict(FIELD_NUM.findall(rest))
        texts = dict(FIELD_TEXT.findall(rest))
        if "minLevel" not in nums or texts.get("kind"):
            continue
        xy = FIELD_XY.search(rest)
        spot = (unescape(zone), unescape(texts["location"]) if "location" in texts else None,
                (float(xy.group(1)), float(xy.group(2))) if xy else None,
                int(float(nums["minLevel"])), int(float(nums.get("maxLevel", nums["minLevel"]))))
        if spot not in spots[unescape(name)]:
            spots[unescape(name)].append(spot)
    return spots


def item_names(tables, classic):
    """{ item ID: (English name, category or None) }: the client's name first,
    else Classic's (the client's table holds only some items)."""
    kinds = {}
    with open(tables / "Item.csv", encoding="utf-8", newline="") as f:
        for row in csv.DictReader(f):
            kinds[int(row["ID"])] = (row["ClassID"], row["SubclassID"])
    names = {int(i): unescape(n) for i, n in NAME.findall(
        (classic / "enUS" / "items.lua").read_text(encoding="utf-8"))}
    with open(tables / "ItemSparse.csv", encoding="utf-8", newline="") as f:
        for row in csv.DictReader(f):
            name = (row.get("Display_lang") or "").strip()
            if name:
                names[int(row["ID"])] = name
    out = {}
    for item, name in names.items():
        if name.startswith("[") or re.search(r"\b(test|deprecated|unused)\b", name, re.I):
            continue
        kind, subclass = kinds.get(item, (None, None))
        if kind is None:
            continue
        category = None
        if kind == QUEST_ITEMS:
            category = "Quest item"
        elif kind == RECIPES:
            category = "Recipe"
        elif kind == TRADE_GOODS:
            category = CATEGORIES.get(subclass, "Mob drop")
        out[item] = (name, category)
    return out


def mob_names(classic, tables):
    """{ mob ID: name }: as the game showed it, else Classic's."""
    def read(path):
        return {int(i): unescape(n) for i, n in NAME.findall(path.read_text(encoding="utf-8"))}
    # Later ones win: the shipped Classic list, Classic's, then the game's.
    names = read(NAME_FILES[1])
    names.update(read(classic / "enUS" / "units.lua"))
    names.update(read(NAME_FILES[0]))
    with open(tables / "Creature.csv", encoding="utf-8", newline="") as f:
        for row in csv.DictReader(f):
            name = (row.get("Name_lang") or "").strip()
            if name:
                names.setdefault(int(row["ID"]), name)
    return names


def classic_units(classic):
    """{ mob ID: (points, low, high) } for every Classic mob with a level."""
    out = {}
    for unit, body in ITEM_BLOCK.findall((classic / "units.lua").read_text(encoding="utf-8")):
        level = LEVEL.search(body)
        if not level:
            continue
        low = int(level.group(1))
        points = [(float(x), float(y), int(z)) for x, y, z in COORD.findall(body)]
        out[int(unit)] = (points, low, int(level.group(2) or low))
    return out


def middle(points):
    """The point nearest the middle of `points` (a real one, never an average)."""
    xs, ys = sorted(x for x, _ in points), sorted(y for _, y in points)
    mx, my = xs[len(xs) // 2], ys[len(ys) // 2]
    return min(points, key=lambda p: (p[0] - mx) ** 2 + (p[1] - my) ** 2)


def classic_spot(points, zone_names, wanted, places):
    """The zone a mob stands in most (one the item is found in when there
    are any), with one of its spawn points there; no point inside."""
    named = [(x, y, zone_names[z]) for x, y, z in points if zone_names.get(z) in places]
    if not named:
        return None
    pick = [p for p in named if p[2] in wanted] or named
    zone = Counter(z for _, _, z in pick).most_common(1)[0][0]
    if zone in places.inside:
        return zone, None
    x, y = middle([(x, y) for x, y, z in pick if z == zone])
    return zone, forever_spot(zone, x, y)


class Places(set):
    inside = set()


def main():
    if len(sys.argv) != 4:
        sys.exit(__doc__)
    facts, classic, tables = Path(sys.argv[1]), Path(sys.argv[2]) / "db", Path(sys.argv[3])

    by_id, inside = zone_tables()
    places = Places(set(by_id.values()) | inside)
    places.inside = inside
    classic_zones = {int(z): n for z, n in NAME.findall(
        (classic / "enUS" / "zones.lua").read_text(encoding="utf-8"))}
    have_ids, have_names = registered()
    items = item_names(tables, classic)
    mobs = mob_names(classic, tables)
    units = classic_units(classic)
    looted = looted_spots()

    npc_spots = defaultdict(list)
    for row in json.loads((facts / "npc.json").read_text(encoding="utf-8")):
        for map_id, points in (row.get("coords") or {}).items():
            if int(map_id) in by_id and points:
                npc_spots[row["id"]].append((by_id[int(map_id)], points))

    droppers, found_in, item_spots = defaultdict(list), defaultdict(set), defaultdict(list)
    dungeon_of, dungeon_mobs = {}, defaultdict(set)
    for row in json.loads((facts / "item.json").read_text(encoding="utf-8")):
        if not row.get("crs"):
            continue
        for mob in row["crs"]:
            if mob not in droppers[row["id"]]:
                droppers[row["id"]].append(mob)
        for map_id in list((row.get("coords") or {}).keys()) + [row.get("in_map")]:
            if map_id is not None and int(map_id) in by_id:
                found_in[row["id"]].add(by_id[int(map_id)])
        for map_id, points in (row.get("coords") or {}).items():
            if int(map_id) in by_id:
                item_spots[row["id"]].append((by_id[int(map_id)], points))
        if row.get("in_inst"):
            dungeon_of[row["id"]] = row["in_inst"]
            dungeon_mobs[row["in_inst"]] |= set(row["crs"])

    # The list names a dungeon by its own number. Which dungeon that is
    # comes from our own looted rows: where its other mobs were looted.
    dungeon_names = {}
    for number, ids in dungeon_mobs.items():
        votes = Counter(zone for mob in ids for zone, *_ in looted.get(mobs.get(mob), [])
                        if zone in inside)
        if votes:
            dungeon_names[number] = votes.most_common(1)[0][0]

    rows = {}
    for item, ids in droppers.items():
        if item in have_ids or item not in items or items[item][0].lower() in have_names:
            continue
        wanted, best, seen = set(found_in[item]), [], set()
        dungeon = dungeon_names.get(dungeon_of.get(item))
        if dungeon:
            wanted.add(dungeon)
        for mob in ids:
            name = mobs.get(mob)
            if not name or name.startswith("[") or any(p.search(name) for _, p in PRIVATE):
                continue
            spot = None
            for zone, location, xy, low, high in looted.get(name, []):
                if not wanted or zone in wanted or zone in inside:
                    spot = (zone, location, xy, low, high)
                    break
            if not spot and mob in units:
                points, low, high = units[mob]
                where = classic_spot(points, classic_zones, wanted, places)
                if not where and npc_spots.get(mob):
                    zone, pts = npc_spots[mob][0]
                    where = (zone, tuple(middle([tuple(p) for p in pts])))
                # A dungeon's mob, or one mob in the item's one zone.
                if not where and dungeon:
                    where = (dungeon, None)
                if not where and len(ids) == 1 and len(found_in[item]) == 1:
                    zone = next(iter(found_in[item]))
                    pts = [tuple(p) for z, ps in item_spots[item] if z == zone for p in ps]
                    where = (zone, forever_spot(zone, *middle(pts)) if pts else None)
                if where:
                    spot = (where[0], None, where[1], low, high)
            if not spot or (name, spot[0]) in seen:
                continue
            seen.add((name, spot[0]))
            best.append((name,) + spot)
            if len(best) == MAX_SPOTS:
                break
        if best:
            rows[item] = best

    out = [
        "-- Blackthornes Farmer -- Data/Data_KnownDrops.lua",
        "-- Generated by tools/make_known_drops.py; never edit by hand. Mobs known",
        "-- to drop items no other data file has, with no drop rates: leads for",
        "-- the search until looted on Forever.",
        "",
        "local _, ns = ...",
        "",
        "local DB = ns.DB",
        "",
    ]
    # Items share a name now and then ("Draconic for Dummies" is three): the
    # search knows an item by its name, so they are one entry, the lowest ID.
    for item in sorted(rows):
        twin = next((i for i in rows if i < item and items[i][0] == items[item][0]), None)
        if twin:
            have = {(r[0], r[1]) for r in rows[twin]}
            rows[twin] += [r for r in rows.pop(item) if (r[0], r[1]) not in have][:MAX_SPOTS - len(rows[twin])]
    spots = 0
    for item in sorted(rows, key=lambda i: (items[i][0], i)):
        name, category = items[item]
        kind = "category = %s, " % lua_string(category) if category else ""
        out.append("DB:RegisterItem({ name = %s, id = %d, %ssources = {" % (lua_string(name), item, kind))
        for mob, zone, location, xy, low, high in sorted(rows[item], key=lambda r: (r[4], r[5], r[0])):
            parts = ["name = %s" % lua_string(mob), "zone = %s" % lua_string(zone)]
            if location:
                parts.append("location = %s" % lua_string(location))
            if xy:
                parts.append("coords = { %.1f, %.1f }" % xy)
            parts += ["minLevel = %d" % low, "maxLevel = %d" % high, "searchOnly = true"]
            out.append("    { %s }," % ", ".join(parts))
        out.append("} })")
        spots += len(rows[item])
    out.append("")
    OUT.write_text("\n".join(out), encoding="utf-8", newline="\n")
    print("%s: %d items, %d spots" % (OUT, len(rows), spots))


if __name__ == "__main__":
    main()
