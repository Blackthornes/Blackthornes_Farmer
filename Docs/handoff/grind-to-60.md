# Grind to 60: handoff

Branch: `claude/project-thread-gjeteb` (Blackthornes_Farmer). No PR yet.

The owner said build it (2026-11-22) from the mockup
`Docs/mockups/farmer-grind-to-60.html` in the project files. Its words are
approved, including the amber EXPERIMENTAL tag beside the GRIND TO 60 chip
and "Experimental." at the start of the footer. Six languages, deDE in "du".

## Done

- `Logic/GrindTo60.lua` (in the TOC and `tools/testenv.lua`): settings
  (`grindTo60`, `grindTo60View`, `grindTo60Pick`), who is playing
  (`Who`, race start zones), zone sides and towns tables, elites learned in
  `Harvest:NoteUnit` while on (`grindElites`), hides (`HideArea` to
  `grindTo60Areas`; `HideMob` to `grindTo60Mobs` plus `DB:Hide("source")`;
  `HiddenCount`, `ShowAgain` only undoes what was hidden from here), Skip
  (session only), camps from `Grinding:Mobs()`, scoring (`Look`, `Choose`:
  Classic kill XP by level or own session XP on the current step,
  `Value:ForMob`, skins and herbs only with the skill, real Forever camps
  beat estimates), the plan from 1 to 60 kept by a stamp (`Plan`), dots,
  reasons, good drops, `Seconds` for the pace line.
- `Logic/Harvest.lua`: one line calling `GrindTo60:Learn`.
- `tools/test_grindto60.lua`: written, not yet run. Its logic checks
  (parts 1 to 6 and 8) only need the logic file; the view parts need the UI.

## Left

- `UI/GrindTo60.lua` (add back to the TOC after `UI\GatherRoute.lua` and to
  testenv's UI list): the view over the Grind tab's list, modelled on
  `UI/GatherRoute.lua` (`Build(panel)`, `Toggle(grinding, on)`, `Update()`
  returning the footer). Header line, Pick By chip, LEVELS/WHERE/XP/GOLD
  rows in dark glass, the open step card (Mobs:, Good Drops:, Also Here:,
  Why Here:, Show the Way via `Arrow:Grind(step.camp)`, Skip Step, pace),
  tags (estimate with hollow dots, HERBS, SKINS, BOTH SIDES, ELITES NEAR),
  hover, footer ("Experimental." first, "Level N", "Step X of Y",
  "N hidden." + Show Again), empty and "You made it to 60." states.
- `UI/Grinding.lua`: the GRIND TO 60 chip plus amber tag (Theme `warn`) at
  the end of the gives chips, only while on; `Layout()` returns a new view
  while `GrindTo60.Shown()`; other chips clear `grindTo60View`;
  `Render` toggles the view like `ShowRoute`.
- `UI/HideMenu.lua`: `MOST` is 4; the step menu needs up to 6 lines (Show
  the Way, Hide This Area, a Hide line per mob, Cancel). Let `Open` take a
  larger count without changing other menus.
- Settings: there is no Experimental page yet. Add an EXPERIMENTAL page
  after GOALS in `PAGES` (`UI/Settings.lua`) with "Grind to 60:" and its
  description, and paint it in `SettingsUI:Refresh`. Check tests that count
  pages.
- Locale lines in all six files for every new key; run
  `python tools/check_locale.py`.
- Notes in `Docs/claude-notes.md`, the verify skill steps, then the PR.

## Gotchas

- `Spots.Hops` says "other continent" as its second return (8 hops); the
  code reads that.
- Hiding a mob uses the global hide list, so it also leaves search and the
  Grind tab. The approved chat line still says "hidden from Grind to 60."
- Herbs come from `GrindGather:DataRows("herbs")` by zone only.
- The plan stamp ignores price changes on purpose (no rebuild on a timer).
