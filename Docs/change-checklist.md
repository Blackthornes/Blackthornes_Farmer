# Change checklist

Things we got wrong before, each with what sets it off. Before a PR, run
`python tools/checklist_for_change.py` and it prints only the items this
change touches (usually a handful). Make sure of each one, or say in the PR
why it does not apply.

When something slips through anyway (a fix that passed the tests but not the
game, a reviewer's catch), add an item here in the same PR as the fix, if the
miss can be spotted from a diff. Take an item out when the code it guards is
gone. Keep each item short: the full story lives in Docs/claude-notes.md.

Fields: `Files` is matched against each changed path, `Lines` against each
added or removed line (both are regular expressions; either one matching is
enough). `Check` is what to make sure of. `Why` is the miss behind it.

## A file shared by all five addons
Files: ^(UI/(SharedWindow|WhatsNew|SettingsPages|SharedMinimap|About|HouseKit|TooltipShift|FoldWindow|BlizzardLook|SharedChoices|TravelMap)|Logic/(Travel|ClassTraining)|Core/SisterNote)\.lua$
Check: Make the same change in each sister addon that has this file, and bump
  FILE_VERSION when the file has one (then update the FILE_VERSION line in
  every addon's CLAUDE.md).
Why: Fixes landed in one addon only, and the newest copy loaded first won.

## Dragging or placing a window
Lines: StartMoving|StopMovingOrSizing|ClearAllPoints|KeepSpot|SetUserPlaced|OnDragStart|OnDragStop
Check: Nothing places the window while it is dragged, a spot is saved only
  on the drop, and it stays on screen. The fake game cannot show a drag, so
  the PR says "Not checked: dragging in game".
Why: The one window snapped back under the cursor mid-drag (2026-11-16),
  with every test green.

## A saved key
Lines: muteSounds|muteSoundsAt|windowSpots|oneWindowDockSpots|formerCharacters|retiredInto|SavedVariables
Check: Never rename or drop a saved key. Old saves must still load: read the
  old shape, write the new one, delete nothing.
Why: Renamed keys lost players' data; old records are kept on purpose.

## Who is playing
Lines: UnitName\(\s*"player"|GetUnitName|GetRealmName|UnitGUID
Check: A character is its GUID, never a name. A GUID that will not read
  means write nothing and offer nothing for an alt. Use the one test for
  "same character" in this addon, and refuse an errand aimed at the one
  playing.
Why: Errands were sent to the character playing, and a reload wiped alts'
  saved gear (2026-10-11).

## A sound
Lines: PlaySound
Check: Every PlaySound and PlaySoundFile asks ns.Muted() first, fallbacks too.
Why: Mute All Sounds must quiet every sound in all five addons.

## Reading the client
Lines: \bC_[A-Za-z]+\.[A-Za-z]+\(|\bGet[A-Z][A-Za-z]+Info\(
Check: Client values are read inside a pcall. Inside an instance some come
  back as secret values that raise when touched. Never assume an API exists
  on Forever: note what the probe shows in docs/FOREVER_API_FINDINGS.md.
Why: Forever is a retail engine with classic rules; several calls are
  missing or locked in dungeons.

## Events, timers and redraws
Lines: RegisterEvent|OnUpdate|C_Timer\.(After|NewTicker|NewTimer)
Check: Register through ns.RegisterEvent, the owner first:
  `ns.RegisterEvent(self, "EVENT", fn)`. Without the owner nothing is heard
  and nothing says so. Coalesce bag, loot, cast and skill bursts. Nothing on a timer rebuilds a whole list when one thing moved, and
  hidden windows skip the work.
Why: Hitches while crafting and a once-a-second minimap redraw (2026-10-09).
  A window that waited for a fight to end and never heard it (2026-11-20).

## Walking a table that may change
Lines: \bpairs\(
Check: If anything inside the loop can add to or clear the table being
  walked, walk a copy instead.
Why: "invalid key to next" when a worker started another worker (2026-11).

## Player words
Lines: L\[\s*"|L\.Format\(
Check: Plain, warm, sixth grade, no em-dashes, hype or questions
  (`python tools/check_house_rules.py`). New words need the owner's yes. deDE and
  the other locales change with the English.
Why: The writing rule holds for every word a player reads.

## A call between the addons
Lines: _G\.Blackthornes|BlackthornesTS_API
Check: Calls between addons stay stable and run inside a pcall. A change to
  one is made in both repos together, after reading its section in
  Docs/claude-notes.md.
Why: A sister addon reading an old name breaks silently.

## The TOC, or a file added, removed or renamed
Files: \.toc$
Check: The reply says the game needs a full restart, not /reload. A new
  file is listed in the TOC in the right load order.
Why: A /reload does not pick up new files.

## A release version
Lines: RELEASED_VERSION|^## \d+\.\d+\.\d+
Check: ns.RELEASED_VERSION in Core/Init.lua matches the newest version in
  CHANGELOG.md (`python tools/check_release.py`).
Why: A checkout must show the real version number.

## Generated data
Files: ^Data/
Check: Data files are written by their tools/ script, never by hand.
Why: Hand edits were lost at the next fold-in.

## Defaults and settings
Lines: [Dd]efaults?\s*=|DEFAULTS
Check: Big new features start off. Never change a setting the player
  already chose.
Why: Standing rule from the owner.

## Sharing code (Farmer)
Files: ^Core/(Comm|Serialize)\.lua$|^Logic/Contribute\.lua$
Check: Core/Comm.lua and Core/Serialize.lua match Tradeskills' copies. The
  recipient lists in Logic/Contribute.lua match Tradeskills' and Equipment's.
Why: The two copies drifted and shared data stopped reading.

## Drop records (Farmer)
Files: ^Data/Data_Harvested\.lua$|^tools/Data_Harvested_corpses\.txt$
Check: Commit Data_Harvested.lua and Data_Harvested_corpses.txt together,
  made by tools/harvest_import.py with --keep-published, from the live save only.
Why: A release must never lose drops, and the corpse notes live beside the data.

## Goals and their owner (Farmer)
Lines: IsOwner|goal\.owner|\.owner\s*=
Check: Ask Goals:IsOwner, never compare keys by hand (tools/test_goals.lua).
Why: One key per character.

## Two values from one call
Lines: local \w+, \w+ = [^,]+ and [\w.:]+\(
Check: `local x, y = thing and Call()` keeps only the first value, so `y` is
  always nil. Declare the locals, then `if thing then x, y = Call() end`.
Why: The trip line never drew on the world map: y was nil and the draw
  raised inside its pcall, in all five addons (2026-11-20).
