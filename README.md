# Blackthornes Farmer

A WoW: Forever addon that answers one question: **where do I farm this?**

Type a material and it gives you back every source it knows about — the mob or
the node, the zone, and the level range you will be fighting in — sorted lowest
level first.

```
/farm wool cloth

- Wool Cloth (Cloth, 20 spots)
  MOB   SOURCE                  WHERE                                  LEVEL   DROP
  MOB   Shadowfang Moonwalker   Silverpine Forest / Shadowfang Keep    22-23   ####------  45%
  MOB   Shadowfang Darksoul     Silverpine Forest / Shadowfang Keep    23-24   ####------  42%
  MOB   Syndicate Rogue         Hillsbrad Foothills / Durnholde Keep   25-26   ###-------  32%
  MOB   Blackrock Champion      Redridge Mountains / Stonewatch Keep   24-26   ###-------  30%
```

Levels are coloured the way the game colours a target, so you can see at a
glance what you can actually kill. Click any row to print it to chat with its
coordinates, which is how you paste a spot to someone.

The same box takes a zone or a mob name too, so it also answers "what is worth
farming here?":

```
/farm defias      ->  Linen Cloth, off Defias Trappers and Smugglers in Westfall, 12-18
/farm un'goro     ->  everything the database has in Un'Goro, by level
```

Built for the WoW: Forever beta client (`## Interface: 16001`), without Ace3 or
LibStub, matching [Blackthornes Tradeskills](https://github.com/Blackthornes/Blackthornes_Tradeskills).
The two share a palette on purpose — they are worn together.

## Install

### Linked to your working copy (recommended while developing)

Run this once, and from then on testing a branch is pulling it and typing
`/reload`:

```powershell
.\tools\link.ps1
```

It junctions `Interface\AddOns\Blackthornes_Farmer` to this folder, so the
client reads your checkout directly. Nothing is copied, so there is no deploy
step to forget.

Two things `/reload` will **not** pick up, because the client only reads them at
startup:

- a file that was **added, removed or renamed**
- any change to **`Blackthornes_Farmer.toc`**

After pulling a branch that did either, restart the client once. Everything
else — a changed Lua file, new data, a UI tweak — is live on `/reload`.

### Copied into the client

If you would rather keep the client's copy separate from the repo:

```powershell
.\deploy.ps1              # syntax check, lint, then mirror into Interface\AddOns
.\deploy.ps1 -SkipCheck   # skip the checks (not recommended)
```

Both scripts default to `D:\Blizzard\World of Warcraft\_classic_beta_`. Pass
`-GamePath` if the client lives somewhere else.

The addon folder name has to stay `Blackthornes_Farmer`, matching the `.toc`
inside it. If they differ, the client ignores the folder and says nothing.

## Use

| Command | What it does |
| --- | --- |
| `/farm <text>` | search, and show the results in the window |
| `/farm` | open or close the window |
| `/farm minimap` | show or hide the minimap button |
| `/farm chat <text>` | print the results to chat instead |
| `/farm data` | where the loaded data came from |
| `/farm stats` | how many items and spots are loaded |
| `/farm list` | list every item in the database |
| `/farm harvest` | everything the addon has recorded from your loot, across sessions |
| `/farm export [item]` | hand that back as a data file, ready to paste |
| `/farm help` | the command list |

`/farmer` is the same command if `/farm` is taken.

There is also a **minimap button** — the mining-pick icon on the ring. Click it
to open the window, drag it to move it round the minimap, and it stays where
you put it. `/farm minimap` hides it if you would rather not have it, and
brings it back.

Searching is deliberately loose. It matches, best match first:

1. an **item name** or alias — `copper ore`, `copper`, `mageweave`
2. a **category** — `mining`, `herbalism`, `cloth`, `mob drop`
3. a **zone**, a **landmark** or a **mob name** — `westfall`, `durnholde`,
   `shadowfang`, `defias`

A name match always outranks a zone match, so looking up an item never buries
it under everything that happens to drop in a zone you named. Results follow
typing rather than waiting for Enter.

When a search turns up more than one kind of source, filter chips appear above
the results — `ALL`, `MOB`, `ORE`, `HERB` and so on. Click an item heading to
collapse it.

## The data

The addon ships with a seed database covering ore, herbs, cloth, leather, mob
drops and elementals. It is the materials people actually farm, not a full dump
of the game.

Levels mean different things depending on the kind of source, deliberately:

- **mob / skinning** — the mob's own level range, so you know if you can kill it
- **node / herb** — the surrounding zone's level band, so you know if the zone
  will kill you while you mine

**`Wool Cloth` is the worked example of a fully researched item.** Every one of
its rows names the mob, its level band, where in the zone it stands and roughly
how often it drops. That is the shape to copy when filling in the rest, and
`tools/test_data.lua` keeps it complete.

Drop rates and coordinates are Classic-era figures. Coordinates are only given
where the landmark is unambiguous — everywhere else the location name is the
honest answer, because a coordinate that is wrong costs a flight while a
landmark name does not.

### Classic data versus Forever

**Everything that ships today is Classic data, and none of it is confirmed on
Forever.** Forever is classic content on a retail engine and its drop tables are
nobody's to assume, so the addon does not present a guess and a checked fact as
the same thing.

A source that has actually been confirmed in game carries a green `[Forever]`
marker in the results. Unmarked means Classic-sourced and unverified — the
window says so in its footer, and `/farm data` gives the running count.

When you farm a spot and it holds up, mark it:

```lua
{ kind = "mob", name = "Defias Trapper", zone = "Westfall",
  minLevel = 12, maxLevel = 18, provenance = "forever" },
```

That is the whole mechanism. `provenance` defaults to `"classic"`, so the
honest state is what you get for free and the claim is the thing you have to
type.

One test enforces this: `tools/test_data.lua` asserts the shipped data is all
Classic-sourced. When you mark a row confirmed that test fails, which is the
prompt to say in the commit message that you checked it in game. It is a
speed bump, not a wall.

`Data/Data_Harvested.lua` is the one exemption, for the reason the rule exists:
those rows were measured by counting corpses, not claimed by somebody editing a
number. The test checks them on their own terms instead — every measured row
has to name its mob and carry a level.

### Measuring it yourself

The addon watches your loot window and counts. Every time you loot a corpse it
records the mob, its level, the zone, the subzone and where you were standing,
and what was inside. Corpses looted is the denominator, corpses that held the
item is the numerator, and that is a real drop rate — measured on Forever
rather than copied from Classic.

It runs on its own from login, and what it records is kept in SavedVariables,
so every session adds to the last. `/farm harvest` shows the total:

```
/farm harvest
  41 corpses looted across 3 mobs:
  58 Wool Cloth  from 30 corpses
  12 Linen Cloth  from 9 corpses
```

`/farm export` opens a window holding the whole thing as a data file, already
selected — Ctrl+C, then paste it into a file under `Data/`. `/farm export wool`
gives you just that item.

#### Getting it out without copying anything

A WoW addon cannot write a file. There is no `io` and no `os` inside the
client's Lua sandbox, so the export window is not a shortcut — on its own it is
the only thing an addon can do.

What the client *can* do is write SavedVariables, which it does at every logout
and reload, and the harvester already persists there. So the moment you log out,
your harvest is sitting in a real file on disk:

```
WTF/Account/<ACCOUNT>/SavedVariables/Blackthornes_Farmer.lua
```

`tools/harvest_import.py` reads that file and writes `Data/Data_Harvested.lua`,
adding it to the `.toc` the first time:

```bash
python tools/harvest_import.py
```

Play, log out, run it, commit. Nothing to copy. The saved file already holds
everything you have ever harvested, so there is no rush: import after one
session or after ten. It finds the saved file under
the usual install paths on its own; `--sv <path>` points it somewhere else, and
`--list` shows what it found without writing anything.

##### A desktop icon for it

Run this once and a shortcut appears on your desktop:

```
powershell -ExecutionPolicy Bypass -File tools\make_shortcut.ps1
```

From then on the loop is: log out of WoW, double-click **Import WoW Harvest**,
then commit in GitHub Desktop. The window stays open so you can read what it
found. `-Remove` takes the shortcut away again.

The shortcut points at `Import Harvest.bat` inside the repository rather than a
copy, so it keeps working after a `git pull`. The batch file finds Python,
installs `lupa` the first time if it is missing, and says what to do if Python
is not on the machine at all.

The icon is `tools/farmer.ico`, drawn by `tools/make_icon.py` -- committed, so
that script only needs running if the artwork changes.

Two refusals keep the repository safe. The import will not write a data file
with fewer corpses than the one it replaces, since the harvest only ever grows
and a smaller one means something went wrong in game (`--allow-smaller` if you
cleared it on purpose). And it will not read a saved file from before the
addon's first login after the SavedVariables fix, which is still missing the
older harvest described below.

##### Harvest from before saved data worked

Until the Forever patch of 2026-09-24 the client wrote SavedVariables but never
read them back, so everything harvested before then lived in the repository
instead. `Data/Harvest_Carryover.lua` holds it: 84 corpses across 22 spots. The
first time you log in with this version the addon adds it to your saved harvest
and says so in chat, then stamps the save so it is never added twice.

The export is not reimplemented in Python. The script loads the addon under a
real Lua runtime and calls the same `Harvest:ExportAll` the in-game window
calls, so the file and the window can never disagree about a drop rate.

Rows come out marked `provenance = "forever"`, because they were measured here.
A mob with fewer than 20 corpses behind it exports without a `chance` and says
how thin the sample was instead, since a rate off six kills is a number
pretending to be evidence.

Four things are deliberately **not** recorded, because a sample attributed to
the wrong mob is worse than no sample at all: fishing pools and containers,
player corpses, anything looted while your target is not the corpse, and
coordinates the client will not give a straight answer for.

Nothing leaves your machine. It accumulates in SavedVariables and comes back out
through the export window or the import. `/farm harvest off` pauses it.
`/farm harvest reset confirm` clears it, for good; a plain `reset` only tells you
how much you are about to lose.

### Adding to it

Every data file is plain Lua that calls one function:

```lua
local _, ns = ...
local DB = ns.DB

DB:RegisterItem({
    name     = "Thorium Ore",
    id       = 10620,             -- optional, for item links later
    category = "Mining",
    aliases  = { "thorium" },     -- optional extra search terms
    note     = "optional one-liner shown under the item",
    sources  = {
        {
            kind       = "node",  -- mob | node | herb | skinning | fishing |
                                  -- container | vendor | quest
            name       = "Rich Thorium Vein",   -- omit for plain herb nodes
            zone       = "Winterspring",        -- required
            location   = "Frostsaber Rock",     -- where in the zone
            coords     = { 55.4, 42.1 },        -- map percentages
            minLevel   = 53,                    -- required
            maxLevel   = 60,
            requires   = "Mining 275",          -- optional gate
            chance     = 12,                    -- drop rate, percent
            note       = "optional one-liner shown after the source",
            provenance = "forever",             -- omit unless you checked it
        },
    },
})
```

`zone` and `minLevel` are the only required fields on a source. Everything else
is simply not drawn when it is missing, so a thin entry and a fully researched
one live in the same list without either looking broken.

Coordinates and drop rates are validated on load: a pair outside the map, or a
rate over 100, is dropped with a warning rather than stored. A row that points
somewhere wrong is worse than one that admits it does not know.

Registering a name that already exists **merges** the new sources into the
existing item instead of replacing it. So:

- the database can be split across as many files as you like
- a later file can extend an earlier one
- a Forever-specific data pack can bolt confirmed spots onto items that already
  ship here, without touching the Classic rows

`Data/Data_MobDrops.lua` does exactly that at the bottom of the file, adding
extra elemental spots to items first registered in `Data/Data_Misc.lua`.

To add a file, drop it in `Data/` and add a line for it in
`Blackthornes_Farmer.toc`. A file that is not in the `.toc` does not load, and
WoW says nothing about it.

## Layout

| Folder | What is in it |
|---|---|
| `Core/` | Namespace, module registry, event dispatch, slash commands, saved variables |
| `Data/` | The item database and the seed data files |
| `Logic/` | Ranked search, the display lines it produces, and the loot harvester |
| `UI/` | Theme, widgets, the main window and the export window |
| `tools/` | Checks, tests, the harvest importer and the desktop shortcut. Not shipped to the client |

## Development

```bash
python tools/syntaxcheck.py   # parse every Lua file with a real 5.1 parser
python tools/lintcalls.py     # find calls to methods, and constants, never defined
python tools/runtests.py      # run the logic and window tests outside WoW
python tools/test_harvest_import.py   # check the harvest importer end to end
```

`tools/` requires `lupa` (`python -m pip install --user lupa`).

The checks exist because WoW silently disables an addon whose first TOC file
fails to compile, and because a call to a method that no longer exists is valid
Lua that fails only when that line runs. `deploy.ps1` runs the first two before
it copies anything, and `.github/workflows/tests.yml` runs all three on every
push.

The tests load the addon against a stub client (`tools/testenv.lua`), so they
check the search, the ranking, the data and the window's wiring without the
game running.
