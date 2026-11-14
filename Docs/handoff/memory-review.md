# Farmer memory review (2026-11-14)

Research only. No code was changed. Every idea below keeps every feature
working the same and touches no saved data.

How the numbers were worked out: there is no game client or Lua here, so
nothing was measured live. They are estimates from the file sizes, row
counts and how Lua 5.1 stores tables (a hash slot is about 40 bytes, a
table's header about 56 bytes, and a table's hash part grows to the next
power of two). Treat them as "about this big". Check with
`collectgarbage("count")` in game before and after each change.

## Where the memory goes

| What | Size on disk | Guess in game | Notes |
|---|---|---|---|
| `Data/Data_Harvested.lua` | 2.4 MB | 4 to 6 MB | 10,501 rows, 9,372 coords tables. Half the file is `-- N of M corpses` comments (no cost in game). |
| `Data/Data_ClassicDrops.lua` | 470 KB | about 1 MB | 846 items, search only. |
| `NpcNames` + `ForeverNpcNames` | 205 KB | about 0.4 MB | id to name. Small. |
| Hand data files, Zones, Travel | about 190 KB | under 0.5 MB | Small. |
| `DB:ByName()` index | none | about 2 MB | One `{ item, source }` table for every row, made again whenever data or the hide list changes. |
| Saved data (the player's) | grows | grows | Records, kill tally, stats. Not touched by any idea here. |
| Locale files | | none | Each one already returns at its top on other clients. Nothing to gain. |

Already fine: map markers reuse a pool, Stats keeps 100 days and 30
sessions, kill heat, gathered spots (2,000) and guildmates (20) all have
caps.

## Ideas, best first (savings against risk)

### 1. Stop the ninth field doubling 3,678 rows (about 1.2 MB, low risk)

`DB:AddSource` writes `source.kind = source.kind or "mob"` onto every row.
3,678 harvested rows already have exactly 8 fields (name, zone, location,
coords, minLevel, maxLevel, chance, provenance). The ninth key makes Lua
double the row's hash part from 8 slots to 16: about 320 bytes more on
each of those rows.

Fix: leave `kind` nil for mob rows and read it through one helper,
`DB.KindOf(source)` (returns `source.kind or "mob"`). There are about 135
reads of `.kind` in Logic and UI. Most compare with "skinning", "node" or
"fish", where nil acts the same as "mob". Only 5 compare with "mob"
directly and need the helper. A test should load the data and check
every row's kind reads the same before and after.

### 2. Lighter `DB:ByName()` index (about 1.5 MB less, and less garbage, low to medium risk)

`ByName` makes a little `{ item = item, source = source }` table for every
row, about 14,000 of them, and throws them all away whenever
`DB.changes` or `DB.hiddenVersion` moves (guild rows coming in, hiding a
mob, the skinning box). Each rebuild leaves about 2 MB for the garbage
collector.

Fix, same answers: keep one table per mob name holding pairs side by side
(`list[2i-1] = item, list[2i] = source`), or keep the source alone and
look its item up in a `sourceItem[source] = item` map made once as rows
are added (a row never moves to another item). Six callers to change.
Also worth checking: only the hide version should force a full rebuild;
a guild row added could be slotted in without one.

### 3. Forget old corpses during long sessions (a few hundred KB after a long grind, low to medium risk)

`Harvest.opened` and `Tracker.corpses` keep an entry for every corpse
looted this session and are only emptied on reload or reset. After
thousands of kills that adds up. A corpse can't be looted again once it
is gone, so entries older than, say, 30 minutes can be let go a few at a
time. Check first that nothing needs an old one (the kill goal's
`corpse[3]`, skinning a corpse later, the Open button). Nothing saved.

### 4. Fewer string compares while the data loads (login time, not memory, low risk)

`SameSpot` and `SameMob` lowercase both sides of every compare, and a
busy item like Linen Cloth has 379 rows, so loading it does tens of
thousands of `:lower()` calls. Keeping each row's lowered name and zone in
a lookup made once per item (by `name|zone|location`) makes the check one
table read. Same rows kept, just faster at login with less garbage.

### 5. Guild sharing ledgers (unknown, only for players who turned it on; measure first)

With guild sharing on, Farmer keeps each guildmate's ledger (`guildIn`):
a count for every record that guildmate sent, so the same drop is never
counted twice. With 20 guildmates that can be close to 20 copies of the
record list. The ledger is how double counting is stopped, so it can't
just be dropped. Worth measuring a real save before thinking about a
smaller shape, and any new shape must keep the old values.

### 6. Smaller shipped file (download size and load time, no memory, no risk)

About half of `Data_Harvested.lua` is `-- 50 of 333 corpses` comment
lines. They cost nothing in game memory, but they double the download
and the time the game spends reading the file. The tool could write them
to a side file in `tools/` instead. Only if the owner wants the smaller
zip; the data itself stays exactly the same.

## Looked at and left alone

- **Coords as two plain numbers** instead of a small table: would save
  about 0.8 MB, but adding two fields pushes many rows past 8 slots again,
  and 69 reads in 15 files use `.coords`. Not worth the risk.
- **Loading Classic drops or NPC names only when needed**: WoW loads every
  file in the TOC at login, and the search, tooltips and dungeon names use
  them at once. No gain without losing something.
- **Trimming saved data** (records, kill tally, `npcNames`, stats): the
  owner's rule is never to delete or reset player data, so nothing here
  prunes it.
- **Locale files**: all five non-English files stop at their first lines
  on other clients.
