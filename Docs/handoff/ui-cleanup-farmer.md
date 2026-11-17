# Farmer UI cleanup (2026-11-16)

What a pass over Farmer's UI found, what was fixed, and what is recommended
but not built. Nothing under "Recommended" is built: each needs the owner's
yes on its mockup first, and any new player word needs his OK.

Mockups live in the project files, not in this repo:
`previews/farmer-ui-cleanup/` (`mockup.html` and one PNG per number below).

## Fixed in this pass

- **The Kills & Loot panel worked the session's value out four times in one
  redraw** (the title, the per-hour line, the note, the clock), each time
  walking every item looted. `Value:BeginPass` / `EndPass` now share the
  first answer inside `TrackerUI:Refresh`. Measured in the test harness on a
  session of 60 mob kinds and 120 items: 7.5 ms a redraw down to 5.4 ms.
  Tested in `tools/test_perf.lua`.
- **CLAUDE.md is much smaller.** "One key per
  character", "Mute All Sounds", "Fold in fresh data" and "Window spots"
  moved word for word into `Docs/claude-notes.md`, with a short pointer left.
  The standing rules and "Writing for players" are short forms now, their
  full wording under "Standing rules in full" there. 16 KB to 9.5 KB in all.
- **Quiet test tools,** as in Butler: `python tools/runtests.py -q` prints
  only failures and the total, `-q perf tracker` runs only suites whose
  name holds a word given, and `python tools/syntaxcheck.py -q` prints only
  failures. `tools/testenv.lua` now gives the client's `time`, so the
  Settings suites pass when run on their own.

## Checked and found fine

- Every always-on OnUpdate driver is throttled and leaves early when nothing
  changed (map markers, heat, route map, travel map, grind pins, arrow
  waker). The effect drivers (`Motion`, `TrackerFX`, `GoalsUI`) hide when
  idle. Measured idle: about 2 KB of garbage a second in all, from
  `MapMarkers:Step`.
- Bag work listens to `BAG_UPDATE_DELAYED`, not `BAG_UPDATE`.
- Saved lists have caps (`Stats.KEEP_DAYS`, `Heat.MAX_CELLS`,
  `Pace.KEEP`, `CampWorth.KEEP`, `Gathering.MAX_SPOTS` and the like).
- All 146 test suites pass, the fit suites among them (`test_textfit`,
  `test_panelfit`, `test_wrapfit`).

## Engineering follow-ups (no change a player sees, not built)

1. **The panel redraw still makes about 1.4 MB of garbage in a long
   session** (60 mob kinds). `Tracker:SessionMobs` builds a fresh
   `Tracker:Summary` for every mob on every kill, though one mob changed,
   and `TrackerUI:Lines`, `Arrange` and `TrackerFX:Prepare` build new tables
   for every line. Keeping each mob's summary until its tally changes needs
   a version number bumped wherever the tally, the hide list, "Hide
   skinning", `rollLooks` or an item's look changes. Worth its own PR with
   its own tests; it is the biggest hitch left at kill time.
2. **`NodeSparkle:SafeRefresh` runs once per nameplate added.** A pack of
   mobs coming into view runs it many times in one frame. One run on the
   next frame would do.
3. **`MapMarkers:MinimapKey` builds a nine-part string ten times a second.**
   Comparing the numbers kept from last time would make none.

## Recommended, each with a mockup

Built since (the owner said "build all", 2026-11-16): 2 and 3 and the BAGS
heading of 5; then 4 and the rest of 5 as ten Settings pages (see "Ten
Settings pages and the Windows table" in `Docs/claude-notes.md`; the joined
rows of 5 were not built, they did not fit a row). 1 is built in the shared
files in all five addons.

### 1. One lane for the notes at the top of the screen (`1-notice-lane.png`)

Found: these all place themselves at the top middle with no knowledge of
each other. The goal arrow (`UI/Arrow.lua`, TOP -140), the Bags Full notice
(`UI/BagsFull.lua`, TOP -150), the note cards (`UI/Notice.lua`, TOP -150
and down), the Opening note (`UI/OpenNote.lua`, TOP -210), and the Run
Recap and Rank-Up pop-ups when Kills & Loot is hidden (TOP -140). With the
arrow on they land on each other.

Recommend: one lane. `Notice.Layout` already stacks the cards; let it also
own the arrow's bottom edge as its start, and have Bags Full, the Opening
note and the two pop-up fallbacks take a place in the same stack. No new
words, no new settings. A dragged arrow or pop-up keeps its dragged spot.

### 2. Play panels sit under the game's windows (`2-layers.png`)

Found: the Fishing Panel (`UI/FishingPanel.lua:467`), the Kill Goal windows
(`UI/KillGoal.lua:64`) and Where to Farm (`UI/Goals.lua:1500`) are on the
DIALOG layer, so they cover the bags, the map and the character window.
Kills & Loot, Goals and the XP bar are on LOW; the arrow, loot feed, route
window and travel card on MEDIUM.

Recommend: one ladder. Panels that stay up while you play: LOW. Things
that pop up on their own (arrow, loot feed, pop-ups, notes): MEDIUM.
Windows the player opens on purpose (the main window, Settings, the loot
table, the name box, Export, Import): DIALOG. Menus and tooltips above.
A few lines of code, no new words.

### 3. Where to Farm opens beside the world map (`3-map-drawer.png`)

Found: floating panels and the world map know nothing of each other, so a
panel can cover the part of the map being read.

Recommend: while the world map is open, Where to Farm hangs on its right
edge, and goes back to its own spot when the map closes. The game's map is
never hidden, moved or changed; our frame only anchors to its edge and
follows it (the way the map gem already does). Off by default. The same
drawer could later hold the Grind list and the gather route. New words to
approve: "Dock to the Map:" and its hover.

### 4. One Windows page in Settings (`4-windows-page.png`)

Found: each floating window has its Show tick on one page, its Transparent
row on General and its place row on a third. About 24 rows on 4 pages.

Recommend: a WINDOWS page with one table, a line a window: Show,
Transparent, Reset Spot. Snap Panels and Window Spots sit under it. Every
saved key stays as it is; only the rows move. New words to approve: the
page name, the column names and "Reset Spot".

### 5. Settings rows that belong together (`5-settings-rows.png`)

Found, 121 rows on 5 pages:

- Sounds are on three pages (Kills, Map and General).
- MAP & GOALS holds 39 rows, 10 of them tooltips and nameplates.
- "My Professions Only:" is on the Map page twice, once for markers and
  once for sparkles, with nothing on the label to tell them apart.
- Trash Can, Opening Note, Bags Full Notice, Open Button and Open
  Automatically sit under the SKINNING heading.
- Several pairs are two halves of one choice: World Map and Minimap
  markers, Heat on World Map and Minimap, Beacon Height and Width, Quest
  Count and its position, Nameplate Kills and its position, Open Button
  and Open Automatically.

Recommend: a SOUNDS page; MAP & GOALS split into MAP, GOALS and TOOLTIPS;
a BAGS heading; each pair on one row; and the second "My Professions
Only:" renamed for what it does. About 121 rows become about 95, and no
page holds more than about 20. Every saved key stays. New words to approve
are marked NEW on the mockup.

## For every addon

- The notes of all seven repos load into every session,
  about 103 KB before any work starts. The same five sections ("One key per
  character", "Mute All Sounds", "Window spots", "Fold in fresh data",
  "Smooth play") are word for word in six of them. Moving them to each
  repo's `Docs/claude-notes.md`, as done here, saves about 4 to 5 KB a repo.
- `Blackthornes_Farmer_Retail` (24 KB of notes) and
  `blackthornes_addons_data` load in every session though neither is being
  worked on. Taking them out of the project's repositories saves about a
  quarter of that load. That is the owner's choice.
- `UI/TravelMap.lua` (the same file in every addon) keeps its OnUpdate
  running with no trip set. Measured here it costs one add and one compare
  a frame and makes no garbage, and it looks twice a second. Stopping it
  when idle needs a wake call where a trip starts, and the change has to
  land in every copy together, so it was left alone here.
- The notice lane (1) and the layer ladder (2) belong in the shared files
  (`UI/Notice.lua` is shared), so the other four addons would join the same
  lane.
