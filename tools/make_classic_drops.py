"""Writes Data/Data_ClassicDrops.lua: where Classic's mobs drop trade goods.

Run from the repository root:

    python tools/make_classic_drops.py <Classic data> <Forever tables folder>

  Classic data            Classic 1.12's drops, spawns and names, the same
                          folder tools/make_npc_names.py reads
  Forever tables folder   the Forever client's game tables as CSV: Item.csv
                          (what kind of item each is) and ItemSparse.csv
                          (its English name and quality)

So the search has something to show for a trade good before anyone has
looted it on Forever. Only trade goods (the client's item class 7: cloth,
leather, meat, herbs, metal, elemental, enchanting and the rest) and quest
items (class 12) that the Forever client still has, dropped by a mob that stands somewhere, at
MIN_CHANCE or better, the MAX_SPOTS likeliest mobs an item, each in the zone
it stands in most. No drop rates are written: these are Classic's, nobody
measured them here, and a spot is shown as one from Classic until it is
looted on Forever, when the player's own row takes its place
(DB:AddSource). Every row is `searchOnly`, so the Grind tab keeps to the
camps it had.

A mob name the clear-to-post scan would refuse (tools/check_package.py's
PRIVATE list) is left out, so the package always passes it.

Never edit the output by hand; rerun this.
"""

import csv
import re
import sys
from collections import Counter, defaultdict
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from check_package import PRIVATE  # noqa: E402

OUT = Path("Data/Data_ClassicDrops.lua")
ZONES = Path("Data/Zones.lua")

TRADE_GOODS, QUEST_ITEMS = "7", "12"
MIN_CHANCE = 1.0
MAX_SPOTS = 8
MIN_SPAWNS = 3

# The search's category for a new item, by the client's trade goods
# subclass, as the hand-typed files name them; anything else a mob drops.
CATEGORIES = {"4": "Gem", "5": "Cloth", "6": "Leatherworking", "7": "Mining",
              "8": "Cooking", "9": "Herbalism", "10": "Elemental", "12": "Enchanting"}
# Gathered, not looted: a vein or a herb is where to get these, and the odd
# one a mob carries is no place to send anyone.
GATHERED = {"Mining", "Herbalism", "Fishing"}
HAND_TYPED = ["Data_Mining.lua", "Data_Herbalism.lua", "Data_Cloth.lua",
              "Data_Leather.lua", "Data_Misc.lua", "Data_MobDrops.lua"]
ITEM_BLOCK = re.compile(r"\n  \[(\d+)\] = \{\n(.*?)\n  \},", re.S)
UNIT_DROPS = re.compile(r'\["U"\] = \{\n(.*?)\n    \},', re.S)
PAIR = re.compile(r"\[(\d+)\] = (-?[\d.]+),")
COORD = re.compile(r"\{ ([\d.]+), ([\d.]+), (\d+), \d+ \}")
LEVEL = re.compile(r'\["lvl"\] = "(\d+)(?:-(\d+))?"')
RANK = re.compile(r'\["rnk"\] = "(\d)"')
NAME = re.compile(r'\[(\d+)\] = "((?:[^"\\]|\\.)*)"')


def lua_string(text):
    """`text` as a Lua string; the names come in with their quotes escaped."""
    text = text.replace("\\'", "'").replace('\\"', '"')
    return '"%s"' % text.replace("\\", "\\\\").replace('"', '\\"')


def known_zones():
    """The English zone names the Forever client has (Data/Zones.lua)."""
    text = ZONES.read_text(encoding="utf-8")
    return set(re.findall(r'\["([^"]+)"\] = \d+,', text))


def hand_typed():
    """{ item ID: (name, category) } the hand-typed data files register.
    Those items keep their own name and category, so one item is never two."""
    names = {}
    for name in HAND_TYPED:
        text = (Path("Data") / name).read_text(encoding="utf-8")
        for item, item_id, kind in re.findall(
                r'name = "((?:[^"\\]|\\.)*)",\s*id = (\d+),\s*(?:category = "([^"]*)")?', text):
            names[int(item_id)] = (item, kind)
    return names


def category(kind, subclass):
    if kind == QUEST_ITEMS:
        return "Quest item"
    return CATEGORIES.get(subclass, "Mob drop")


def trade_goods(tables):
    """{ item ID: (English name, category) } for trade goods and quest items."""
    kinds = {}
    with open(tables / "Item.csv", encoding="utf-8", newline="") as f:
        for row in csv.DictReader(f):
            kinds[int(row["ID"])] = (row["ClassID"], row["SubclassID"])
    goods = {}
    with open(tables / "ItemSparse.csv", encoding="utf-8", newline="") as f:
        for row in csv.DictReader(f):
            item = int(row["ID"])
            name = (row.get("Display_lang") or "").strip()
            kind, subclass = kinds.get(item, (None, None))
            if kind not in (TRADE_GOODS, QUEST_ITEMS) or not name:
                continue
            # "[PH]", "Deprecated", "Test" and the like were never handed out.
            if name.startswith("[") or re.search(r"\b(test|deprecated|unused|old)\b", name, re.I):
                continue
            goods[item] = (name, category(kind, subclass))
    return goods


def units(db):
    text = (db / "units.lua").read_text(encoding="utf-8")
    out = {}
    for unit, body in ITEM_BLOCK.findall(text):
        points = [(float(x), float(y), int(z)) for x, y, z in COORD.findall(body)]
        level = LEVEL.search(body)
        rank = RANK.search(body)
        rank = int(rank.group(1)) if rank else 0
        # Rares and bosses (ranks 2 to 4) stand alone and are no camp.
        if points and level and rank < 2:
            low = int(level.group(1))
            out[int(unit)] = (points, low, int(level.group(2) or low), rank)
    return out


def spot(points, zone_names, zones):
    """The zone a mob stands in most, and one of its spawn points there
    nearest the middle of them (a real spot, never an average). None when
    it stands in fewer than MIN_SPAWNS places there: one named mob is no
    camp to farm."""
    counts = Counter(z for _, _, z in points if zone_names.get(z) in zones)
    if not counts:
        return None
    zone, many = counts.most_common(1)[0]
    if many < MIN_SPAWNS:
        return None
    here = [(x, y) for x, y, z in points if z == zone]
    xs, ys = sorted(x for x, _ in here), sorted(y for _, y in here)
    mx, my = xs[len(xs) // 2], ys[len(ys) // 2]
    x, y = min(here, key=lambda p: (p[0] - mx) ** 2 + (p[1] - my) ** 2)
    return zone_names[zone], x, y


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    db, tables = Path(sys.argv[1]) / "db", Path(sys.argv[2])

    goods = trade_goods(tables)
    typed = hand_typed()
    zones = known_zones()
    zone_names = dict((int(z), n) for z, n in NAME.findall(
        (db / "enUS" / "zones.lua").read_text(encoding="utf-8")))
    unit_names = dict((int(u), n) for u, n in NAME.findall(
        (db / "enUS" / "units.lua").read_text(encoding="utf-8")))
    stands = units(db)

    rows = defaultdict(list)
    for item, body in ITEM_BLOCK.findall((db / "items.lua").read_text(encoding="utf-8")):
        item = int(item)
        if item not in goods or typed.get(item, ("", ""))[1] in GATHERED:
            continue
        drops = UNIT_DROPS.search(body)
        for unit, chance in PAIR.findall(drops.group(1) if drops else ""):
            unit, chance = int(unit), float(chance)
            name = unit_names.get(unit)
            if chance < MIN_CHANCE or unit not in stands or not name or name.startswith("["):
                continue
            if any(pattern.search(name) for _, pattern in PRIVATE):
                continue
            points, low, high, rank = stands[unit]
            where = spot(points, zone_names, zones)
            if where:
                rows[item].append((rank, chance, name, where, low, high))

    out = [
        "-- Blackthornes Farmer -- Data/Data_ClassicDrops.lua",
        "-- Generated by tools/make_classic_drops.py from Classic 1.12 data and the",
        "-- Forever client's game tables; never edit by hand. Where Classic's mobs",
        "-- drop trade goods, with no drop rates: leads for the search until looted",
        "-- on Forever.",
        "",
        "local _, ns = ...",
        "",
        "local DB = ns.DB",
        "",
    ]
    items = spots = 0
    for item in sorted(rows, key=lambda i: goods[i][0]):
        best, seen = [], set()
        # Ordinary mobs before elites, then the likeliest.
        for _, _, name, (zone, x, y), low, high in sorted(rows[item], key=lambda r: (r[0], -r[1], r[4], r[2])):
            if (name, zone) in seen:
                continue
            seen.add((name, zone))
            best.append((name, zone, x, y, low, high))
            if len(best) == MAX_SPOTS:
                break
        name, kind = goods[item]
        # A hand-typed item keeps its own name and category.
        if item in typed:
            name, kind = typed[item][0], ""
        else:
            kind = "category = %s, " % lua_string(kind)
        out.append("DB:RegisterItem({ name = %s, id = %d, %ssources = {" % (lua_string(name), item, kind))
        for name, zone, x, y, low, high in sorted(best, key=lambda r: (r[4], r[5], r[1])):
            out.append("    { name = %s, zone = %s, coords = { %.1f, %.1f }, minLevel = %d, maxLevel = %d, searchOnly = true },"
                       % (lua_string(name), lua_string(zone), x, y, low, high))
        out.append("} })")
        items += 1
        spots += len(best)
    out.append("")
    OUT.write_text("\n".join(out), encoding="utf-8", newline="\n")
    print("%s: %d items, %d spots" % (OUT, items, spots))


if __name__ == "__main__":
    main()
