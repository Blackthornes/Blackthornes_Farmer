# Notes for Claude

Read this before working in this repo. It is one of five Blackthornes addons
(Farmer, Tradeskills, Equipment, Pets, Butler), each in its own repo. What one
needs to know about another lives in the repos, in this file and in theirs.
Keep them current: when a change here leans on something new in a sister, or a
standing rule from the owner applies to all of them, add it to each file.

Nothing private goes in this file (no local paths, emails or account names).
It never ships: `.pkgmeta` leaves it out of the zip and
`tools/check_package.py` refuses it.

## Long notes live in Docs/claude-notes.md

CLAUDE.md is kept short on purpose (a 130 to 170 KB one ran every session out of room). Every feature history, call list and sister note was moved word for word, nothing deleted, into `Docs/claude-notes.md`. Grep a heading there and read about 150 lines at a time; never read it whole. Add new feature notes to that file, not here. **Before you change any saved key, global, call between addons or shared file named in a section below, read that section first**: the cross-addon calls (`What ... calls here`, `Sending ...`, `The goal arrow`, `The one window` and the like) must stay stable and are changed in both repos together.

Sections there:

- Checking a change
- What Tradeskills provides
- What Tradeskills calls here
- Craft or farm (Tradeskills' Your time view)
- Find a material (Tradeskills' Disenchanting tab)
- Farmed (Tradeskills' Profit by method)
- Goblin Gold (Tradeskills' gold bar)
- Kill goal
- What Butler calls here
- Sharing with the player's other account
- Sharing with the guild
- Sending drops to Blackthornes
- Giving data to another player
- Grind: Leather, Ore and Herbs
- Camp worth on the Grind tab
- Grind: Fish
- Schools told by the game
- The Fishing window
- One key fishing
- The fishing panel
- The gold plaque
- Legacy perks (read only)
- Gather to cap
- Gather Route
- The session timer
- The panel kept between sessions
- Search finds your own loot
- Quest items in the loot lists
- Classic drops in the search
- Random suffixes count as their item
- Same name, another zone
- Drops only
- The one window
- The shared minimap button
- The settings pages (from Tradeskills)
- The house frame (Titanforged)
- The fold gem
- The Blizzard window style
- The goal arrow, copied to Equipment and Pets
- Our own map marker
- The way there (arrows across zones and the sea)
- Reading the probe
- Discord
- The rank-up pop-up
- Rankings outside dungeons only
- Rankings without Uncommon and better
- Rankings at vendor prices
- Near my level on Rankings
- Your top 15 after an auction scan
- The trash can when bags are full
- Bags full notice
- The loot feed
- Clams and sacks worth what's inside
- The Open button
- The see-through panel
- Kill heat map (a test feature)
- Kills on the mob tooltip
- Off, Shift or Always on tooltip lines
- Rates are the player's to find
- World drops
- Sparkles on the node you face
- The map gem
- Gathered spots on the maps
- Quest count over quest mobs
- Kill count beside mobs' nameplates
- Damage numbers (taken out)
- The XP bar
- The Stats tab
- Loot inside dungeons
- Loot icons
- Party loot
- What's New
- The About page and the note
- The sister note
- German and other language clients
- Simplified Chinese, French, Spanish and Russian
- Zone names from the client
- One look across the addons (the house kit)
- One key per character
- Mute All Sounds
- Fold in fresh data at each release
- Window spots
- Standing rules in full
- Where to Farm on the map's edge
- Shelves, dock places and the All Addons page
- Ten Settings pages and the Windows table
- Saved Farms
- The Zone Board
- The swap gem (One Window toggle, 2026-11-19)
- The tooltip block (shared item tooltip lines)
- Panel Style (Like Quest List)
- Grind to 60 (taken out)
- The Farm HUD
- Restore Defaults (Farmer Settings: Set Default)
- Smoother kills and the hand-drawn scroll bar
- Slim Bar for Kills & Loot (2026-11-26)
- The run graph and a Run Recap that stays (2026-11-26)
- Move Windows (2026-11-26)
- The Home tab (taken out)
- Names as you type (2026-11-26)
- The Rankings board over a few frames (2026-11-26)

## Checking a change

Before every PR, follow `.claude/skills/verify/SKILL.md`: a bug fix starts
with a test that fails the way the game failed; act the steps out in the
fake game; run `python tools/check_house_rules.py` (player words and dark
glass, lines this change adds) and `python tools/checklist_for_change.py`
(the items in `Docs/change-checklist.md` this change touches). Every PR
body ends with `Checked:` and `Not checked:` lines. After three failed
rounds, stop and ask the owner. A miss a diff could have shown gets a
checklist item in the fix's PR. Details under "Checking a change" in
`Docs/claude-notes.md`.

## One key per character

A character is its GUID (`UnitGUID("player")`) in saved data and in every
call between the addons, never a name. A GUID the client won't read means
"not sure who's playing": write nothing, offer nothing for an alt. Old
"Name-Realm" records stay readable, nothing is deleted. Ask Farmer's one
test, `Goals:IsOwner`, never compare keys or names by hand, and refuse an
errand aimed at the character playing. Tested in `tools/test_goals.lua`.
The whole rule (the same in every addon) is under "One key per character"
in `Docs/claude-notes.md`; read it before touching character keys.

## Mute All Sounds

Every `PlaySound` and `PlaySoundFile` asks `ns.Muted()` first, fallbacks
too; a new sound must as well. Saved as `muteSounds` and `muteSoundsAt`
(never rename them). Details under "Mute All Sounds" in
`Docs/claude-notes.md`.

## Writing for players

Every word a player reads is plain, warm and human, at a sixth grade
reading level: short sentences, everyday words, what the player sees or
does. No hype, no filler, no em-dashes, no questions to the reader. deDE
changes with the English, in the "du" voice. Farmer's play cheers keep
their "!", and `About.NOTE` is the owner's own wording. Full wording under
"Standing rules in full" in `Docs/claude-notes.md`.

Plain prose everywhere (the owner, 2026-11-21): notes, commits, PRs and
replies too. Say plainly what you mean, no stock figures of speech. Short
words. Cut every word you can, keeping the context the reader needs.
Active voice. Everyday words or the reader's own term, not jargon or words
made up during the work. Defaults, not hard limits. Check all prose against
them before handing it over. Full wording under "Standing rules in full".

## The owner's standing rules (all the addons)

Short forms. The full wording of each, with dates and reasons, is under
"Standing rules in full" in `Docs/claude-notes.md`; read a rule there
before work that leans on it.

- **Every list is dark glass:** rows take `glass` and `glassAlt` in turn
  with a 1 px `border` line under each, `glassHover` and a gold edge under
  the mouse, `glassActive` and a gold left edge when picked. Never
  `row`/`rowAlt`. Gradients fade through `Theme.LightGradient` or are
  hidden, never SetAlpha alone.
- **No red gems on a rim's ends** (the owner, 2026-11-22): never put red
  circles on the left and right of a window, plaque or pop-up, in any
  addon. The red close gem (the X) and the corner gems stay.
- **"Always check that it's clear to post."** Nothing is published or
  uploaded without the owner's go-ahead. He tags releases himself.
- **Changelogs come from git history,** never from asking the owner.
- **A checkout shows the real version number:** `ns.RELEASED_VERSION` in
  `Core/Init.lua` matches the newest `## X.Y.Z` in CHANGELOG.md; the
  release PR changes both.
- **Every reply that ships code says the PR is ready and whether the game
  needs `/reload` or a full restart** (a full restart when a file is added,
  removed or renamed, or the TOC changes). Never merge or pull by hand on
  github.com or in GitHub Desktop.
- **Grey items are priced at vendor only;** everything else is
  max(auction, vendor).
- **CurseForge descriptions are features only.**
- **Smooth play comes first, but never at the cost of looks:** nothing on
  a timer or OnUpdate rebuilds a whole list, map or set of markers when one
  thing moved; coalesce event bursts; skip work for hidden windows; spread
  work over hundreds of items across frames.
- **The client is WoW: Forever, a retail engine** (`## Interface: 16001`),
  not 1.12. Read client values inside a pcall; instances hand out secret
  values that raise when touched.

## Fold in fresh data at each release

Every release starts with a fold-in of fresh data from the live game, as
its own step, committed as "Refresh shipped data" and never announced.
Farmer goes first. The steps and tools are under "Fold in fresh data at
each release" in `Docs/claude-notes.md`; read them before a release.

## Big files (read these in pieces)

Reading a huge file whole runs the session out of room. Sizes are
from 2026-11-03 and only grow. Find more with `find . -name '*.lua' | xargs wc -lc | sort -n`.

Keep command output short too: `python tools/runtests.py -q` prints only
failures and the total, `-q perf tracker` runs only the suites whose name
holds a word given, and `python tools/syntaxcheck.py -q` prints only failures.

- Never read a file below whole. Use `grep -n` to find the spot, then read
  about 150 lines at a time (Read with `offset` and `limit`).
- Never read data tables or locale files whole. Grep them for one key.
- CLAUDE.md is big too. Grep it for a heading, then read that part only.
- Generated files (`Data/`) are written by their `tools/` script. Never edit
  them by hand, and never open them to see what they hold.

Data tables (generated, grep only):
- `Data/Data_Harvested.lua` 8214 lines, 475 KB: shipped drop records.
- `Data/Data_ClassicDrops.lua` 4611 lines, 470 KB: Classic drops for the search.
- `Data/NpcNames.lua` 3365 lines, 115 KB and `Data/ForeverNpcNames.lua` 1215 lines, 39 KB: mob names by ID.

Locale (grep one key, never read): `Locale/ruRU.lua` 1785 lines, 150 KB; `frFR`, `esES`, `deDE`, `zhCN` are each about 1780 lines, 115 to 120 KB.

Code over 1500 lines:
- `UI/Tracker.lua` 3557 lines, 137 KB: the Kills & Loot panel.
- `UI/Widgets.lua` 2496 lines, 94 KB: shared widgets.
- `Logic/Harvest.lua` 2345 lines, 92 KB: drop records.
- `UI/Main.lua` 2119 lines, 79 KB: main window and its tabs.
- `UI/Goals.lua` 2100 lines, 79 KB: goals panel.
- `UI/Settings.lua` 1944 lines, 86 KB: Settings pages.
- `Logic/Tracker.lua` 1824 lines, 72 KB: kill tally.
- `UI/TrackerFX.lua` 1830 lines, 68 KB: panel effects.
- `UI/Grinding.lua` 1743 lines, 71 KB: Grind tab.

Over 800 lines or 30 KB, same rule: `UI/Rankings.lua`, `UI/Stats.lua`, `UI/XPBar.lua`, `UI/NodeSparkle.lua`, `UI/WhatsNew.lua`, `UI/MapMarkers.lua`, `UI/SharedWindow.lua`, `UI/LootTable.lua`, `UI/Heat.lua`, `UI/SettingsPages.lua`, `UI/FishingBar.lua`, `Logic/Share.lua`, `Logic/Arrow.lua`, `Logic/Search.lua`, `Logic/Gathering.lua`, `Logic/Stats.lua`, `Logic/Travel.lua`, `Logic/Value.lua`, `Logic/Fishing.lua`, `CHANGELOG.md` (1169 lines).

The same file lives in several addons: `UI/SharedWindow.lua`, `UI/WhatsNew.lua`, `UI/SettingsPages.lua`, `Logic/Travel.lua`, `UI/TooltipBlock.lua` (not Pets). A fix to one belongs in all.

## Window spots

Windows remember where they were dragged: `oneWindowDockSpots[place]` and
`windowSpots[key]` (never rename either), small windows through
`SharedWindow.KeepSpot(frame, key)`. A window folded into its round button
is kept as `foldedWindows[key]`, its button's spot as
`windowSpots["fold:" .. key]` (never rename; see "The fold gem"). Details under "Window spots" in
`Docs/claude-notes.md`.
