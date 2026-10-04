# Notes for Claude

Read this before working in this repo. Trent runs two Claude projects, one per
addon: this one (**Blackthornes_Farmer**) and **Blackthornes_Tradeskills**
(`Blackthornes/Blackthornes_Tradeskills`). They cannot read each other's
memory, so what one needs to know about the other lives in the repos, in this
file and in Tradeskills' `CLAUDE.md`. Keep both current: when a change here
leans on something new in Tradeskills, or a standing rule from Trent applies to
both addons, add it to both files.

Nothing private goes in this file (no local paths, emails or account names).
It never ships: `.pkgmeta` leaves it out of the zip and
`tools/check_package.py` refuses it.

## What Tradeskills provides

Tradeskills is the house standard for layout (`Core/ Data/ Logic/ UI/
tools/`), palette, module registry and tooling; check it before inventing a
convention. Its `docs/FOREVER_API_FINDINGS.md` records what the Forever client
actually does.

At runtime it is Farmer's source of auction prices. `Logic/Value.lua` reads,
inside a pcall and read only:

```lua
_G.BlackthornesTS.Prices:GetValue(itemID)   -- Tradeskills' smoothed market value, in copper
```

Nothing is copied, nothing is written back, and there is no TOC dependency.
Without Tradeskills, Farmer falls back to the vendor price. Tradeskills'
`CLAUDE.md` asks its side to keep that global, `Prices` and `GetValue(itemID)`
stable; if Farmer needs more from it, change both repos together.

CurseForge project IDs: Farmer **1710618**, Tradeskills **1710638**. Both
release the same way (a `vX.Y.Z` tag on `main`, checked clear to post before
upload; see the README under Releasing). v0.2.0 of both is on CurseForge.

## What Tradeskills calls here

Tradeskills' Gather tab has a **Set goal** button that makes a goal here for a
material its craft queue needs. It shows only when Farmer is loaded and
calls, inside a pcall:

```lua
_G.BlackthornesFarmer.Goals:Find(name)            -- optional
_G.BlackthornesFarmer.Goals:Set(name, amount)     -- goal table, or nil and why
_G.BlackthornesFarmer.GoalsUI:Show()
```

Keep the `_G.BlackthornesFarmer` global, `Goals:Set` (returning the goal with
`item`, `target` and `have`, or nil and a reason) and `GoalsUI:Show` stable.
If one has to change, change Tradeskills' `Logic/FarmerGoals.lua` too.

Goals belong to the character that set them (`goal.owner`, "Name-Realm"),
since a goal counts one character's bags, so `Find` and `Set` act on the
character playing. A goal saved before owners existed shows on every
character until one gathers toward it or changes it.

## The house frame (Titanforged)

Trent picked this look for all four addons on 2026-10-04 (Tradeskills had it
first). It's the game's own window shape with the light turned up: a gold
metal rim with corner gems, a round portrait with the addon's emblem, the
name on a plate across the top edge, a red close gem, and tabs hanging below
the window. Buttons are raised metal with gold labels; the main action is
solid gold with dark "ink" lettering, and only a gold face gets ink (a
button given its own dark `baseColor` keeps a gold label).

`UI/Titanforged.lua` (`Titanforged:Dress(frame, opts)`, `:Opened(frame)`)
is Tradeskills' file with the plate measuring by size, since Farmer's
`Theme.TextWidth(size, text)` differs. The art is `Media/Frame/*.tga`, drawn
by `tools/make_frame_art.py` with `EMBLEM = "pick"`; rerun it, never edit the
TGAs. Hanging tabs are `Widgets.CreateTabStrip(..., { hanging = true })`,
ported from Tradeskills. Glows and glints follow the Window effects setting
(`Motion.Level()`). The search window wears the whole frame; settings,
export and the loot table the plate and close gem; the goal picker and
Where to farm the rim and close gem (their own titles stay inside). The
kills panel, the goals panel, banners and toasts stay up while playing and
keep their own look. Anything placed inside a dressed window stays 6 pixels
in from its edge, or it covers the rim.

## Trent's standing rules (both addons)

- **"Always check that it's clear to post."** Anything public is checked for
  private or unexpected content first, and nothing is published or uploaded
  without Trent's go-ahead. He tags releases himself.
- **Changelogs come from git history,** never from asking Trent. Claude drafts
  the CHANGELOG section in a PR; Trent merges, pulls `main`, tags and pushes.
- **Every reply that ships code ends with the GitHub Desktop steps,** naming
  the branch: merge the PR on github.com, switch **Current branch** to
  **main**, **Pull origin**, then `/reload` or a full restart (a full restart
  when a file is added, removed or renamed, or the TOC changes).
- **Grey (poor quality) items are priced at vendor only;** everything else is
  max(auction, vendor).
- **CurseForge descriptions are features only:** no privacy notes and no
  explanation of public emotes or their switches.
- **The client is WoW: Forever, a retail engine** (`## Interface: 16001`,
  modern Lua), not 1.12. Read client values inside a pcall; instances hand out
  secret values that raise when touched.
