# Blackthorne's Farmer

A World of Warcraft addon that answers one question: **where do I farm this?**

Type a material and it gives you back every source it knows about — the mob or
node, the zone, and the level range you will be fighting in — sorted lowest
level first.

Built for the 1.12 client (Turtle WoW and other vanilla-era servers).

```
/farm copper ore

Copper Ore (Mining, 8 spots)
  [1-10]  Dun Morogh      Copper Vein (mining node, needs Mining 1)
  [1-10]  Elwynn Forest   Copper Vein (mining node, needs Mining 1)
  [10-20] Westfall        Copper Vein (mining node, needs Mining 1)  dense circuit along the coast
  [10-25] The Barrens     Copper Vein (mining node, needs Mining 1)  best single-zone route for a new miner
```

## Install

Copy the `BlackthornesFarmer` folder into your client's addon folder:

```
<WoW folder>/Interface/AddOns/BlackthornesFarmer/
```

The folder name has to stay `BlackthornesFarmer` — it must match the `.toc`
file inside it. Restart the client (or `/reload`) and you're set.

## Use

| Command | What it does |
| --- | --- |
| `/farm` | open or close the window |
| `/farm <text>` | search, and show the results in the window |
| `/farm chat <text>` | print the same results to the chat frame instead |
| `/farm list` | list every item in the database |
| `/farm stats` | how many items and spots are loaded |
| `/farm help` | the command list |

`/farmer` and `/bfarm` do the same thing if `/farm` is taken by another addon.

Searching is deliberately loose. It matches, best match first:

1. an **item name** or alias — `copper ore`, `copper`, `mageweave`
2. a **category** — `mining`, `herbalism`, `cloth`, `leather`, `fishing`
3. a **zone** or a **mob name** — `westfall`, `un'goro`, `defias`

So the same box answers both "where do I get this?" and "what's worth farming
in this zone?".

The window is draggable, scrolls with the mouse wheel, and remembers where you
put it and what you last searched for.

## The data

The addon ships with a seed database of 35 common materials and 144 farming
spots: ore, herbs, cloth, leather, and a handful of elemental and fishing
examples. It covers the materials people farm most, not everything in the
game — the point of the data model is that it's easy to grow.

Levels mean different things depending on the kind of source, and that's
deliberate:

- **mob / skinning** — the mob's own level range, so you know if you can kill it
- **node / herb** — the surrounding zone's level band, so you know if the zone
  will kill you while you mine

### Adding to it

Every data file is plain Lua that calls one function. Add an item like this:

```lua
BlackthornesFarmer:RegisterItem({
    name     = "Thorium Ore",
    id       = 10620,             -- optional, for item links later
    category = "Mining",
    aliases  = { "thorium" },     -- optional extra search terms
    note     = "optional one-liner shown under the item",
    sources  = {
        {
            kind     = "node",    -- mob | node | herb | skinning | fishing |
                                  -- container | vendor | quest
            name     = "Rich Thorium Vein",   -- optional; omit for plain herb nodes
            zone     = "Winterspring",        -- required
            minLevel = 53,                    -- required
            maxLevel = 60,
            requires = "Mining 275",          -- optional gate
            chance   = 12,                    -- optional drop rate, in percent
            note     = "optional one-liner shown after the source",
        },
    },
})
```

`zone` and `minLevel` are the only required fields on a source; everything else
is optional and simply isn't printed when it's missing.

Registering a name that already exists **merges** the new sources into the
existing item instead of replacing it. That means:

- the database can be split across as many files as you like
- a later file can extend an earlier one
- a separate data pack — a server-specific one, say — can bolt extra spots onto
  items that already ship here

To add a file, drop it in `BlackthornesFarmer/Data/` and add a line for it in
`BlackthornesFarmer.toc`. Order doesn't matter as long as it's after
`Core.lua`.

## Tests

There's a smoke test that loads the whole addon against a stubbed-out client
and checks the search, the ranking, the formatting and the window. It needs a
Lua interpreter (5.1 or newer), not the game:

```
lua tests/smoke_test.lua
```

It also validates the seed data — every item needs a source, every source
needs a zone and a level — so it's worth running after editing a data file.

## Notes and caveats

- The seed data is a starting point drawn from vanilla-era common knowledge.
  Private servers tweak spawn rates and drop tables, so treat anything here as
  a lead rather than gospel, and correct the file when you find better.
- Levels on node entries are zone bands, not node requirements. The `requires`
  field is what your profession skill has to be.
