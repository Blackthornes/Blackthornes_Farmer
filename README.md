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
| `/farm settings` | open the settings window (`options` and `config` work too) |
| `/farm minimap` | show or hide the minimap button |
| `/farm tracker [on\|off]` | show or hide the kills and loot panel (`reset confirm` clears the tallies) |
| `/farm tracker group [on\|off]` | move the panel aside from the party and raid frames when grouped (on by default) |
| `/farm kills [mob]` | a mob's kill tally and drop rates in chat |
| `/farm fishing [all]` | what you have caught in this zone, or everywhere (`reset confirm` clears it) |
| `/farm gathering [all\|check]` | herbs and ore you have gathered in this zone, or everywhere; `check` lists herbs or ore credited to a mob (`reset confirm` clears it) |
| `/farm markers [on\|off]` | markers where you gathered herbs and ore, on the world map and minimap (on by default; `map on\|off` or `minimap on\|off` for one, `clear confirm` removes them) |
| `/farm announce [on\|off]` | whether players near you see an emote when a mob reaches 20 kills, a fishing spot 20 casts or a node 20 gathers (on by default) |
| `/farm celebrate [on\|off]` | the fanfare when a mob reaches 20 kills, a fishing spot 20 casts or a node 20 gathers, and its rates unlock (on by default) |
| `/farm effects [full\|subtle\|off]` | how much the addon moves: in the kill panel, glows, the value counting up and loot floating off the panel; in the windows, fading up as they open, results coming in row by row and bars growing (full by default; subtle drops the floats and the row-by-row; off stops it all) |
| `/farm raresound [on\|off]` | a chime when something green or better drops (on by default) |
| `/farm goal <item> <amount>` | set a gathering goal, e.g. `/farm goal Copper Ore 40`; on its own, lists your goals (`remove <item>`, `clear` for finished ones, `bank on\|off` to count your bank) |
| `/farm where <item>` | the best places near you to farm it, nearest first |
| `/farm goals [dock]` | show or hide the goals panel; `dock` puts it back under the kills panel |
| `/farm loot [mob]` | open a mob's full loot table in its own window |
| `/farm value <mob>` | what a kill of that mob is worth, priced by Blackthornes Tradeskills |
| `/farm rankings` | open the Rankings tab: mobs by what a kill is worth (`rank` works too) |
| `/farm report` | report every kill's tally in chat, on or off (off to start) |
| `/farm chat <text>` | print the results to chat instead |
| `/farm data` | where the loaded data came from |
| `/farm stats` | how many items and spots are loaded |
| `/farm list` | list every item in the database |
| `/farm harvest` | everything the addon has recorded from your loot, across sessions |
| `/farm export [item]` | hand that back as a data file, ready to paste |
| `/farm help` | the command list |

`/farmer` is the same command if `/farm` is taken.

Open the window with nothing typed and it suggests a cloth, a leather, an ore
and a herb that suit your level; click one to search for it.

There is also a **minimap button** — the mining-pick icon on the ring. Click it
to open the window, drag it to move it round the minimap, and it stays where
you put it. `/farm minimap` hides it if you would rather not have it, and
brings it back.

### Settings

Every switch the addon has is on one page: `/farm settings`, **right-click**
the minimap button, the **Settings** button in the search window, or
Options > AddOns > Blackthornes Farmer in the game menu. It covers the minimap
button, the size of the search window and of the kill tally, putting windows
back if one ends up off screen, the kill tally and its chat report, pausing
loot recording (remembered between sessions) with an Export button, and debug
output. Changes save as you make them. Nothing on the page deletes data:
clearing tallies or recorded loot stays a typed `reset confirm` command.

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

### Kills and loot panel

A panel down the left side of the screen, under the player and party frames,
fills in as you farm. It has two tabs. **Farm** has a card for every mob you
have killed this session. The one you are on leads, open: its all-time kill
count, where you killed it, a bar toward the 20 kills it takes for drop
rates, what a kill is worth, and everything it has dropped as bag icons.
Until a mob has 20 kills, each icon shows a count; from 20 on, its drop rate,
which is corpses that held the item over kills. The other cards fold to one
line with their loot as small icons. Click a card's name to open or fold it,
and **Sort** to change their order. **Loot** lists everything you looted,
fished and gathered this session, best earners first, with where each came
from. The tallies are kept between sessions.

**Gathered value.** The title bar's second line adds up what the session has
brought in: the coin off your kills plus every item looted, fished up or
gathered, each at the same price "Worth per kill" uses (the Tradeskills
auction value, or the vendor price when that is higher). Items with no price
at all are left out, and a note under the top heading says how many. Once the
session has run five minutes, the bar under the tabs says what that comes to
per hour.

`/farm tracker` (or the panel's **X**) turns it off and on, and it stays the
way you left it. Drag it by the panel if the left edge is busy, and drag the
grip in its bottom-right corner to resize it. The width is what you drag it
to, or wider when a line needs it, so no text is cut off; the height is the
tallest it grows, so a short session still gets a
short panel. Settings > Window positions puts both back.

In a party or raid the panel moves to the right of the party and raid frames,
and back when you leave the group. Drag it while grouped and it goes to that
spot in every group from then on. Turn this off with **Move aside** in
Settings or `/farm tracker group off`.

**Fishing.** Once you have fished this session the panel grows a Fishing
section, on top whenever fishing is what you did last. Each spot you fished is
its own band: open water, or the school you cast into, with the zone and
subzone under it. Catches show as counts until a spot has 20 casts, then as
catch rates (casts that brought the item up, over casts), with what a cast is
worth once there are rates and prices. A fish that gets away opens no loot
window, so it is not counted.

The game does not tell an addon whether the bobber landed in a school, so a
cast counts as a school's only if you moused over the school just before
casting, or you are recasting from the same spot, facing the same way, as a
cast that did. Everything else is open water. So mouse over a school once
before you fish it, or its catch goes down as open water.

**Gathering.** Herbs you pick and veins you mine are recorded the same way,
against the node, zone and subzone, and the panel grows a Gathering section
once you have gathered this session. Each loot window is one gather, so a vein
mined three times counts three. Yields show as counts until a node has 20
gathers, then as rates. A gather is recognised from its Herb Gathering or
Mining cast, so herbs never count as a mob's drop, even with a looted corpse
still targeted. Skinned leather stays the mob's drop. `/farm gathering check`
lists any herb or ore an older version credited to a mob, and changes nothing.

**A mob's full loot table.** Click a loot icon on a mob's open card and a
window opens with everything that mob has ever dropped for you: how many
corpses held each item, how many you took in all, and from 20 kills its drop
rate and what it adds to a kill. Coin per kill shows from the first kill,
averaged over the kills that recorded coin. It updates as you loot. Click an
icon again, press Escape or its **X** to close it. `/farm loot <mob>` opens it
too.

**What a kill is worth.** With Blackthornes Tradeskills loaded too, each mob
in the panel gets a "Worth per kill" line, and hovering a mob in the search
window shows the same. It is the coin a kill drops plus, for each item, how
many dropped per kill times its price. The price is Tradeskills' auction
market value, or what a vendor pays if that is more. Grey items only ever use
the vendor price. Farmer only reads those
prices and never changes them. Once a mob has 20 kills in your tally, the
value comes from your own kills. Before that, it is an estimate from the
database's drop rates, which leaves out coin, and it says "(est.)". Without
Tradeskills, vendor prices are used. `/farm value <mob>` breaks it down.

**Rankings.** The main window has two tabs, **Search** and **Rankings**.
Rankings lists every mob it can value, best per kill first, on two separate
boards: **Your kills** (20 kills or more, measured from your own loot, coin
included) and **Estimates** (the database's drop rates, one of each drop and
no coin, so they run low, shown with a "~"). The two are never ranked against
each other. Below them, mobs you have started on show how many kills each
still needs, or that nothing they drop has a price yet. Hover a mob for what
makes up its worth, click it for its loot
table. `/farm rankings` (or `/farm rank`) opens it, and the window reopens on
whichever tab you left it on.

The kill that unlocks a mob's drop rates, its 20th, plays a fanfare and
prints "Blackthornes Farmer: Drop rates unlocked for ..." with its best drop
in your own chat window. Players near you also see an emote: "Name unlocked
drop rates for Mangy Wolf after 20 kills! (Blackthornes Farmer)". A fishing
spot's 20th cast gets the same: "Catch rates unlocked for open water in Crystal
Lake, Elwynn Forest!" in your chat, and the matching emote. So does a node's
20th gather: "Gather rates unlocked for Copper Vein in Jasperlode Mine, Elwynn
Forest!" in your chat, and the matching emote. That emote, once per mob,
fishing spot or node, is the only thing the addon ever says in public.
`/farm announce off` (or Settings > Share milestones) keeps it to yourself;
`/farm celebrate off` turns the whole thing off.

The panel moves when loot lands. Gathered value counts up to its new total with
a green "+38s" beside it for a few seconds, each item looted floats off the
panel's right edge in its quality colour, any count that went up glows, and the
mob you just killed glows gold with its kill count popping and its bar sliding
toward 20. Something green or better also plays a chime, pulses in its quality
colour and floats as "Nice!", "Rare!" or "Epic!". Kills no more than a minute
apart build a kill streak, shown from the third kill with the session's best
beside it, and every fifth cheers. A mob's 20th kill drops a gold "Drop rates
unlocked" banner over the top of the panel, with a shine across its title. The fanfare and the
chime are the addon's own sounds, in `Media/Sounds` (made by
`tools/make_sounds.py`); until the game has been fully restarted once they
cannot be found, and the fanfare falls back to the game's own. `/farm effects
subtle` keeps the glows and the count-up and drops the floats and pops,
`/farm effects off` stops it all, and `/farm raresound off` silences the
chime. Both are in Settings too.

A kill is a corpse you open. Skinning a corpse you already looted, or coming
back for what you left, is still one kill. A corpse you only skin (someone
else's kill) is not a kill, since you never saw what it dropped, but its
leather still counts in the session's loot. With area loot, only the corpse
you opened is the kill and gets the drops in its tally; everything else in
the window still counts in the session's loot and coin. An item being rolled
for, or left to the master looter, counts toward the mob's drops but not in
your session's loot, whoever wins it. `/farm report on` also prints a line in
your own chat window on every kill; nobody else sees it.

### Gathering goals

Pick a material and a number and the Goals panel counts you toward it. Press
**Goal** beside an item in the search results, choose 20, 40, 60, 100 or
type your own, and **Set goal**; or type `/farm goal Copper Ore 40`. Up to six
goals run at once on each character.

A goal is how many you have, so what is already in your bags counts. Tick
**Include bank** on the picker (or `/farm goal bank on`) to count the bank
as well. Only loot counts toward your pace: items from the bank, mail, a
vendor, the auction house, a trade or your own crafting move the count but
float nothing.

Goals belong to the character that set them: a goal counts that character's
bags and shows only on that character's panel, so logging in on an alt leaves
your main's goals alone. A goal set before goals had owners shows on every
character until one of them loots toward it or changes it, and then it is
that character's.

The panel sits under the kills panel, or above or beside it when there is no
room below, until you drag it elsewhere. Each goal
shows its count, the best spot for it, a bar marked at a quarter, half and
three quarters, how many are left and, once you have gathered a few, how long
the rest should take at your pace. As you loot, the count ticks
up, the bar slides with a shine along it and "+3 Copper Ore" floats off the
side. Passing 25%, halfway and 75% pulses the card gold and tags it. In the
last stretch the bar turns green and counts down "3 more!". The last one drops
a GOAL COMPLETE banner with sparkles and the drop-rates-unlocked sound, and
the card shows how many loots it took and what the pile is worth. Click a
finished card to clear it. Click any other card to search for that item, or
right-click to remove it. The effects follow `/farm effects`.

**Where?** Each goal card has a **Where?** button, and the line under the
goal's name already names the top pick. It lists up to six places to farm the
item, best first, from where you are standing. Near means how many zones
you would cross: your own zone, then the zones next to it, with the other
continent last. A place well above your level drops down the list, a better
drop rate moves one up, and places you have killed or gathered it yourself
come first and say what you got there. Click a place to print it to chat;
when it is in the zone you are in and has coordinates, it is also pinned on
your map. `/farm where copper ore` opens the same list without a goal.

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
Catches come out in the same file as `kind = "fishing"` rows named for the
school or open water, with the same 20-cast floor for a `chance`.
A mob with fewer than 20 corpses behind it exports without a `chance` and says
how thin the sample was instead, since a rate off six kills is a number
pretending to be evidence.

These are deliberately **not** recorded, because a sample attributed to
the wrong mob is worse than no sample at all: fishing (kept separately, see
the panel's Fishing section), herbs and ore (see Gathering), containers, player corpses, anything looted while your target is not the corpse, and
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

## Releasing

Releases are cut by pushing a tag like `v0.2.0`.
`.github/workflows/release.yml` then:

1. refuses the tag unless `CHANGELOG.md` opens with a `## 0.2.0` section
   (`tools/check_release.py`);
2. runs the tests;
3. builds the player-facing zip with the
   [BigWigs packager](https://github.com/BigWigsMods/packager), uploading
   nothing;
4. checks that zip is clear to post (`tools/check_package.py`): only the
   addon's own files, and nothing that looks private, such as a Windows path,
   an email address, a saved-variables dump or a token;
5. only then uploads that same zip to each site with a token, and attaches it
   to a GitHub release.

To release from GitHub Desktop: add the new version's section to the top of
`CHANGELOG.md` and merge it to `main`, pull `main`, then **History**, right-click
the newest commit, **Create Tag...**, name it `v0.2.0`, and **Push origin**.

The version is never typed by hand. The TOC says
`## Version: @project-version@` and the packager fills in the tag. Running
straight from a clone there is no packager, and the addon calls itself a
"dev build". The middle number moves for new behaviour, the last for fixes
alone; a tag like `v0.3.0-beta1` is uploaded as a beta.

`.pkgmeta` decides what reaches a player. `tools/`, `deploy.ps1`,
`Import Harvest.bat` and this README are excluded, and so is
`Data/Harvest_Carryover.lua`: that is Trent's own harvest from before saved
variables worked, and in a player's install it would add his kills to theirs.
Its TOC line is fenced with `#@do-not-package@` to match.

Uploads are opt-in per site. The workflow reads these repository secrets, and
skips any site whose secret is missing:

| Secret | Site |
|---|---|
| `CF_API_KEY` | CurseForge |
| `WAGO_API_TOKEN` | Wago Addons |
| `WOWI_API_TOKEN` | WoWInterface |

Each site also needs its project ID in the TOC (`X-Curse-Project-ID`,
`X-Wago-ID`, `X-WoWI-ID`). CurseForge's is 1710618, the existing Farmer
project; the other two stay commented out until those projects exist.
