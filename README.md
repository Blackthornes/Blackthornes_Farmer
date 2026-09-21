# Blackthornes Farmer

A WoW: Forever addon that answers one question: **where do I farm this?**

Type a material and it gives you back every source it knows about — the mob or
the node, the zone, and the level range you will be fighting in — sorted lowest
level first.

```
/farm copper ore

Copper Ore (Mining, 8 spots)
  [1-10]  Dun Morogh      Copper Vein (mining node, needs Mining 1)
  [1-10]  Elwynn Forest   Copper Vein (mining node, needs Mining 1)
  [10-20] Westfall        Copper Vein (mining node, needs Mining 1)  dense circuit along the coast
  [10-25] The Barrens     Copper Vein (mining node, needs Mining 1)  best single-zone route for a new miner
```

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
| `/farm help` | the command list |

`/farmer` is the same command if `/farm` is taken.

There is also a **minimap button** — the mining-pick icon on the ring. Click it
to open the window, drag it to move it round the minimap, and it stays where
you put it. `/farm minimap` hides it if you would rather not have it, and
brings it back.

Searching is deliberately loose. It matches, best match first:

1. an **item name** or alias — `copper ore`, `copper`, `mageweave`
2. a **category** — `mining`, `herbalism`, `cloth`, `mob drop`
3. a **zone** or a **mob name** — `westfall`, `un'goro`, `defias`

A name match always outranks a zone match, so looking up an item never buries
it under everything that happens to drop in a zone you named. Results follow
typing rather than waiting for Enter.

## The data

The addon ships with a seed database covering ore, herbs, cloth, leather, mob
drops and elementals. It is the materials people actually farm, not a full dump
of the game.

Levels mean different things depending on the kind of source, deliberately:

- **mob / skinning** — the mob's own level range, so you know if you can kill it
- **node / herb** — the surrounding zone's level band, so you know if the zone
  will kill you while you mine

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
            minLevel   = 53,                    -- required
            maxLevel   = 60,
            requires   = "Mining 275",          -- optional gate
            chance     = 12,                    -- optional drop rate, percent
            note       = "optional one-liner shown after the source",
            provenance = "forever",             -- omit unless you checked it
        },
    },
})
```

`zone` and `minLevel` are the only required fields on a source. Everything else
is simply not printed when it is missing.

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
| `Logic/` | Ranked search and the display lines it produces |
| `UI/` | Theme, widgets and the window |
| `tools/` | Checks and tests. Not shipped to the client |

## Development

```bash
python tools/syntaxcheck.py   # parse every Lua file with a real 5.1 parser
python tools/lintcalls.py     # find calls to methods, and constants, never defined
python tools/runtests.py      # run the logic and window tests outside WoW
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
