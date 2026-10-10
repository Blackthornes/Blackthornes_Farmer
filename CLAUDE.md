# Notes for Claude

Read this before working in this repo. The owner runs two Claude projects, one per
addon: this one (**Blackthornes_Farmer**) and **Blackthornes_Tradeskills**
(`Blackthornes/Blackthornes_Tradeskills`). They cannot read each other's
memory, so what one needs to know about the other lives in the repos, in this
file and in Tradeskills' `CLAUDE.md`. Keep both current: when a change here
leans on something new in Tradeskills, or a standing rule from the owner applies to
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

## The settings pages (from Tradeskills)

The owner asked (2026-10-09) for Tradeskills' Settings upgrade in Pets,
Equipment and Farmer. `UI/SettingsPages.lua` is the same file in all three
(a fix to it belongs in all three): category pages along the top
(`settingsPage`, the one left on), two columns a page, what a setting does
as the row's tooltip ("Show descriptions", `settingsDescriptions`, off by
default, puts it back under the rows), "Find a setting", and Text size
(`textSize` normal/large/larger adds 0/1/2 to `Theme.sizes`, now a lookup
over `Theme.BASE_SIZES`; read once, so it waits for /reload). The window
fits its fullest page, so no page scrolls. Farmer's pages are Windows, Kill
tally, Loot, Map & goals and Advanced. Add a setting with
`pages:Row(page, column, label, description)` and
`pages:Section(page, column, "HEADING")` in `UI/Settings.lua`; every
`/farm` command has a button or control there (`tools/test_settings.lua`
checks `ns.commandOrder` against them), but never one that deletes data:
resets stay typed `reset confirm` commands.

## The house frame (Titanforged)

The owner picked this look for all four addons on 2026-10-04 (Tradeskills had it
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

List rows are dark glass (the owner picked it 2026-10-10 over a gold glow
that lit every row; Tradeskills and Equipment have the same):
`Widgets.CreateRowList` rows alternate `glass`/`glassAlt` with a fine line
under each, and the gold wash lights only the row under the mouse. A
gradient that fades goes through `Theme.LightGradient`, which hides it at
0; faded with SetAlpha alone it stayed lit on Forever.

## The goal arrow, copied to Equipment and Pets

Equipment's upgrade quest and Pets' compendium have the same dial (asked
2026-10-08): Equipment's `Logic/QuestArrow.lua` and `UI/QuestArrow.lua`
and Pets' `Logic/BeastArrow.lua` and `UI/BeastArrow.lua` copy
`Logic/Arrow.lua` and `UI/Arrow.lua` here, and their
`tools/make_arrow_art.py` is this repo's, drawing the same
`Media/Arrow/*.tga`. None of them calls another for it. A fix to the dial
or its art in one belongs in all three.

TomTom (a player asked, the owner agreed 2026-10-09, then asked for it in
every addon with an arrow): with TomTom installed, each arrow hands its
place to TomTom (`Logic/TomTom.lua` in Farmer, Equipment and Pets, read
through `_G.TomTom:AddWaypoint`/`RemoveWaypoint` inside a pcall, waypoints
never persistent). "Use TomTom" (`useTomTom`, account wide, on unless
unticked; `arrow tomtom` on each addon's command) hides the dial while
TomTom shows the way, and the waypoint goes whenever the dial would hide,
so the one-arrow rule holds. The files are the same apart from names
(Farmer's reads the goal arrow's `x`/`y`, the others `mx`/`my`); a fix to
one belongs in all three.

Farmer's arrow can also follow a camp from the Grind tab (a player asked,
the owner agreed 2026-10-09; `Arrow:Grind`, `Logic/Grinding.lua`). That is
Farmer's own feature, not part of the shared dial. The harvest file now ends
with the creature types seen in game, as `if DB.CreatureTypes then ... end`
so Equipment's and Pets' readers of `Data/Data_Harvested.lua`, whose `DB`
has only `RegisterItem`, keep working.

Only one Blackthornes arrow is on screen at a time (the owner asked
2026-10-08): Farmer's goal arrow, Equipment's quest arrow and Pets' beast
arrow agree through one global table, `_G.BlackthornesArrows`
(`wants[addon]` while that arrow has something to show, `claims[addon]` the
`GetTime()` it was last turned on or aimed). The one wanting to show with
the latest claim is drawn; the others wait hidden. The lines are the same
in each dial's file (`ArrowUI:Claim`, `ArrowUI.Wins`); a change to them
belongs in all three.

## Discord

The addons share a Discord server, Blackthornes AddOns (public invite
https://discord.gg/f2geDecrw2, set up 2026-10-05). After a release uploads,
`release.yml` runs `tools/announce_discord.py`, which posts the version's
CHANGELOG section to the server's #announcements through a channel webhook
kept in the `DISCORD_WEBHOOK_URL` repository secret. The owner sets that secret
himself; never ask him to paste the webhook address anywhere. Without it the
step does nothing, and a failed post never undoes the upload. The tool is the
same in all four repos; a fix to it belongs in all four.

The owner asked (2026-10-09) for one post in #general per release too,
and (2026-10-10) for it to be short: a few bullets in plain words, a
sixth-grade reading level, warm, in his voice (short, contractions, no
jargon, no file or setting names, never his name), saying what players will
notice. Each release PR writes the new version's section in `NEWS.md`
(`## X.Y.Z`, like CHANGELOG.md; it never ships) next to the CHANGELOG
section: the bullets, then one line of thanks. After the upload
`tools/post_general.py` scans it with `check_package.py`'s PRIVATE list and
posts it through the `DISCORD_GENERAL_WEBHOOK_URL` secret, which the owner
sets himself, under a line with the addon's name and version (so each
addon's bullets are their own group) and "(full list of changes in
#announcements)", so the thanks comes last. It carries no CurseForge link and no card (link previews
are turned off). No section or no secret means no post.
A player's name never goes in a report (the owner, 2026-10-09): no
CHANGELOG, #announcements post, commit or PR text names a player, and
`check_release.py` refuses a CHANGELOG section that credits one
(`names_a_player` in `post_general.py`). The #general post is the one
exception: its last line thanks, by their Discord name, everyone who asked
for or reported the changes, each name once ("Thanks Ana and Bob for the
ideas and reports!"); leave it out when nobody asked. Find who asked from
the project's threads. This tool is also the same in all four repos.

## The owner's standing rules (both addons)

- **"Always check that it's clear to post."** Anything public is checked for
  private or unexpected content first, and nothing is published or uploaded
  without the owner's go-ahead. He tags releases himself.
- **Changelogs come from git history,** never from asking the owner. Claude drafts
  the CHANGELOG section in a PR; the owner merges, pulls `main`, tags and pushes.
- **Every reply that ships code ends with the GitHub Desktop steps,** naming
  the branch: merge the PR on github.com, switch **Current branch** to
  **main**, **Pull origin**, then `/reload` or a full restart (a full restart
  when a file is added, removed or renamed, or the TOC changes).
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
  rule is in all four addons' notes; keep them the same.
- **The client is WoW: Forever, a retail engine** (`## Interface: 16001`,
  modern Lua), not 1.12. Read client values inside a pcall; instances hand out
  secret values that raise when touched.
