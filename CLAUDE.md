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

## One key per character

The owner asked (2026-10-11) that a character can never be mistaken for
another again. Old records had sent errands to the character playing:
Butler filled a mail to itself and told a player to mail Medium Leather to,
and log out for, the character they were on (an old "Name-Realm" record of
Tradeskills' beside the GUID one), and a reload wiped alts' saved gear in
Equipment. The rule, in every addon:

- **A character is its GUID** (`UnitGUID("player")`) in saved data and in
  every call between the addons. Never a first name, "Name-Realm" or a
  short name: Forever lets characters share a first name. Names are for
  showing and for a mail's To line only, always first and last.
- **A GUID the client won't read (a dungeon) means "not sure who's
  playing":** write nothing under another key, and offer nothing for an
  alt. Tradeskills remembers each character's GUID in its own file
  (`BlackthornesTSCharDB.guid`) for that case.
- **Old records stay readable and count as the same character; nothing is
  deleted.** Tradeskills folds an old "Name-Realm" record into the GUID one
  at login, once (`Config:AdoptLegacyCharacter`): it is kept whole in
  `formerCharacters[old key]` with `retiredInto` (never rename either), what
  the GUID record lacks is filled from it when it carries that GUID, and
  the queue's references to the old key follow. Farmer reads a goal tagged
  "Name-Realm" as the character's and tags it with the GUID once the
  character gathers toward it or changes it.
- **One test per addon answers "the same character?" and "the one
  playing?"; never compare keys or names by hand.** Tradeskills:
  `Characters:Same`, `:IsPlaying` and `:Canonical` (`Core/Characters.lua`),
  and `playing` on each `Butler:Holdings()` entry. Butler:
  `Errands:IsMe(name)` (full name, first name alone, any old record's name,
  any case, with or without a realm). Farmer: `Goals:IsOwner`. Equipment:
  `Alts.PlayerGUID()`.
- **Every errand that targets a character asks that test right before it
  acts and refuses the character playing:** a mail, a gold top-up, a Log
  out, an alt's upgrade, a learned habit, the disenchanter.
- Tested in Tradeskills' `tools/test_onecharacter.lua`, Butler's
  `tools/test_notme.lua`, Farmer's `tools/test_goals.lua` and Equipment's
  `tools/test_alts.lua`. This rule is in every addon's notes; keep them the
  same.

## Mute All Sounds

A player asked, the owner said build it (2026-11-12), in all five addons:
one box quiets every sound every Blackthornes addon plays. "Mute All
Sounds:" on the General page under Effects and `/farm mute [on|off]`; off unless ticked. It lives on
the shared choices board (`UI/SharedChoices.lua`, the same file in all
five): `SharedChoices:SetMute(on)` sets it and tells the others,
`ns.Muted()` answers every play call, and each addon keeps it in its own
account save as `muteSounds` and `muteSoundsAt` (never rename them). Each
joins with a reader of those two (`Join(name, write, readMute)`), read at
the first sound after its save loads, the newest winning, so an addon that
was off when the box was ticked still goes quiet. Every `PlaySound` and
`PlaySoundFile` asks `ns.Muted()` first, fallbacks too; a new sound must
as well. Warnings still show on screen and in chat. Tested in
`tools/test_housekit.lua`.

## Writing for players

Every word a player reads (labels, buttons, tooltips, Settings rows and
their descriptions, empty lists, chat lines, slash command help) reads the
way a friend who plays would say it: plain, warm and human. Write it at a sixth grade reading level. Short
sentences in everyday words, contractions welcome. Say what the player
sees or does, not how the addon works inside. No hype or sales words
("seamlessly", "effortlessly", "now you can", "powerful"), no filler, no
em-dashes, and no questions to the reader. The German in
`Locale/deDE.lua` changes with the English, in the same informal "du"
voice. Farmer's play cheers keep their "!" (drop-quality cheers, goal
marks, streaks, "Up to #N!", "Goal done: X!"), and `About.NOTE` is the
owner's own wording. This rule is in every addon's notes; keep them the
same.

## The owner's standing rules (all the addons)

- **Every list is dark glass** (the owner, 2026-10-12: "keep this as the
  standard across all Blackthornes addons", after Farmer's Kills & Loot
  panel was given the look of Tradeskills' queue). Rows or lines take
  `glass` and `glassAlt` in turn, by place, with a 1 px `border` line
  (alpha 0.6) under each; under the mouse `glassHover` and a gold edge,
  only on that row; the row picked or open is `glassActive` with a bright
  gold edge down its left. Never the older `row`/`rowAlt` bands for a
  list, a panel's lines or cards. A gradient fades through
  `Theme.LightGradient` or is hidden, never with SetAlpha alone (it stayed
  lit on Forever). This rule is in every addon's notes; keep them the same.
- **"Always check that it's clear to post."** Anything public is checked for
  private or unexpected content first, and nothing is published or uploaded
  without the owner's go-ahead. He tags releases himself.
- **Changelogs come from git history,** never from asking the owner. Claude drafts
  the CHANGELOG section in a PR; the owner merges, pulls `main`, tags and pushes.
- **A checkout shows the real version number** (the owner,
  2026-10-12). `ns.RELEASED_VERSION` in `Core/Init.lua` is the newest
  `## X.Y.Z` in CHANGELOG.md, shown when the packager has not filled in the
  TOC's `@project-version@` (he plays from a clone). The release PR that
  writes the CHANGELOG section changes it too; `tools/check_release.py`
  refuses a tag it does not match, and `tools/test_check_release.py` fails
  while the two disagree. This rule is in every addon's notes.
- **Every reply that ships code says the PR is ready and whether the game
  needs `/reload` or a full restart** (a full restart when a file is added,
  removed or renamed, or the TOC changes). Merging, pulling and tagging go
  through the project's own steps, never by hand on github.com or in
  GitHub Desktop.
- **Grey (poor quality) items are priced at vendor only;** everything else is
  max(auction, vendor).
- **CurseForge descriptions are features only:** no privacy notes and no
  explanation of public emotes or their switches.
- **Smooth play comes first, but never at the cost of looks** (the owner,
  2026-10-09, after a hitch while crafting). Nothing on a timer or
  OnUpdate rebuilds or re-places a whole list, map or set of markers when
  only one thing moved: keep what is drawn, and redo only rows or pins
  whose inputs changed (a per-row key, a version number). Bag, loot,
  cast, skill and profession-list events arrive in bursts, several per
  craft or loot: coalesce them, read only what they changed, and skip
  work for windows that are hidden. Work over hundreds of items (recipes,
  sources, saved spots) is spread over frames (a worker with a small
  per-frame budget) rather than done in one frame, and shown when done.
  Clicks and typing still answer at once. The two causes found: Farmer's
  minimap markers gathered, sorted and re-placed every saved spot once a
  second because the clock second was in their redraw key (now only the
  fade moves, `MapMarkers:FadeMinimap`); and on every craft Tradeskills
  re-read every recipe in the profession window and repriced the whole
  craft pane in one frame (now `Recipes:NothingNewMidCraft` skips the
  re-read mid-run and `CraftPanel:RefreshInSlices` spreads the pane over
  frames). Visuals and usability are never traded away for speed. This
  rule is in every addon's notes; keep them the same.
- **The client is WoW: Forever, a retail engine** (`## Interface: 16001`,
  modern Lua), not 1.12. Read client values inside a pcall; instances hand out
  secret values that raise when touched.

## Fold in fresh data at each release

Every release of this addon starts with a fold-in of fresh data from the
live game (the owner, 2026-11-07), even when nothing else about the data
changed: the release thread stages the owner's account save and the game's
English caches, read only, from his live Forever folder (the path is in the
project's release steps), runs the tools below, runs the tests and commits
the data in the release PR as "Refresh shipped data". Never announced (no
CHANGELOG, NEWS, What's New or post), never the save or caches committed,
nothing else copied out of them. A release whose only change is new data
does not ship on its own. If his PC can't be reached, the thread asks him
once (Try again or Skip it); it never skips without saying. If the game
patched since the client tables were last pulled, those are refreshed
first.

Farmer goes first, before Equipment or Pets ship, since their boss drops
and beasts read `Data/Data_Harvested.lua`:

- `tools/harvest_import.py --shared --keep-published --sv <Blackthornes_Farmer.lua>`
  (`Data/Data_Harvested.lua`, with the drops players sent in). Read only the
  Forever release save, never the beta backup (the owner, 2026-11-07: the beta
  drops were merged in once and that is not repeated). The shipped file still
  holds them, so it is bigger than the save; `--keep-published` lets each mob
  at each spot keep the larger of the two, so a release never loses drops.
  The "-- N of M corpses" notes under each row live beside the data in
  `tools/Data_Harvested_corpses.txt` (written by the import, never shipped,
  2026-11-14), so the game reads a smaller file; `--keep-published` reads
  them from there, or inline from an older file. Commit both together.
  `tools/harvest_notes.py` moves inline notes out of an older file.
- `tools/forever_npc_names.py <save> <creaturecache.wdb>`
  (`Data/ForeverNpcNames.lua`).

## Big files (read these in pieces)

Reading a huge file whole fills the context and the thread dies. Sizes are
from 2026-11-03 and only grow. Find more with `find . -name '*.lua' | xargs wc -lc | sort -n`.

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

The same file lives in several addons: `UI/SharedWindow.lua`, `UI/WhatsNew.lua`, `UI/SettingsPages.lua`, `Logic/Travel.lua`. A fix to one belongs in all.

## Window spots

A player asked, the owner said build it (2026-11-12), in all five
addons: windows remember where they were dragged. `UI/SharedWindow.lua`
(FILE_VERSION 7; `UI/WhatsNew.lua` FILE_VERSION 7 too) keeps the one
window's spot beside each game window it docks to, once the player drags
it there (`SharedWindow.Dropped`, account wide in every save as
`oneWindowDockSpots[place]`), and small windows signed up with
`SharedWindow.KeepSpot(frame, key)` keep their top left in
`windowSpots[key] = { x, y }`, kept on screen when placed again. Never
rename either. Tradeskills' sell list drawer can be dragged too
(`PostPanel:MakeDraggable`, `SaveSpot`, `ns.db.postPanelSpot`). "Window
Spots:" Set Default on the General page (Tradeskills: its look page) and
`windows reset` on each addon's command run `SharedWindow.ResetAllSpots`,
which clears both keys and calls each addon's own reset
(`SharedWindow.AddSpotReset(name, fn)`); sizes, settings and data stay.
Chat says "Every window is back in its first spot." Tested in
`tools/test_sharedwindow.lua` and each addon's settings test
(Tradeskills: `tools/test_resetwindows.lua`).
