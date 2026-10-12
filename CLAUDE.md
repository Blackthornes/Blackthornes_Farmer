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
Tradeskills itself fills gaps from TradeSkillMaster, then Auctionator
(2026-10-12; the owner allowed naming both in public). Without Tradeskills,
Farmer reads them itself (`Value:OtherPrice`: `TSM_API.GetCustomPriceValue
("DBMarket", "i:<id>")`, then `Auctionator.API.v1.GetAuctionPriceByItemID
("Blackthornes_Farmer", id)`, in a pcall, kept 60 s), "TSM and Auctionator"
on the Loot page (`otherPriceAddons`, on unless unticked, never rename it;
`tools/test_otherprices.lua`); with none of them, the vendor price. Tradeskills'
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
_G.BlackthornesFarmer.Goals:Remove(name)          -- true when there was one
```

Since 2026-10-11 a goal Set goal made follows Tradeskills' queue: when the
queue changes, Tradeskills calls `Goals:Set` again with the new amount, or
`Goals:Remove` when nothing queued needs it, but only while the goal's
`target` is still the one it set (a goal the player changed here is left
alone). Keep the `_G.BlackthornesFarmer` global, `Goals:Find`, `Goals:Set`
(returning the goal with `item`, `target`, `have` and `done`, or nil and a
reason), `Goals:Remove` and `GoalsUI:Show` stable.
If one has to change, change Tradeskills' `Logic/FarmerGoals.lua` too.

Goals belong to the character that set them (`goal.owner`, its GUID since
2026-10-11; "Name-Realm" before, still read as that character's by
`Goals:IsOwner` and given the GUID when it gathers toward it or changes
it), since a goal counts one character's bags, so `Find` and `Set` act on
the character playing. A goal saved before owners existed shows on every
character until one gathers toward it or changes it.

## What Butler calls here

Blackthornes Butler (`Blackthornes/Blackthornes_Butler`, 2026-10-10) tells
the player what to do with each bag item, and asks whether a goal here
needs it. It calls, inside a pcall, read only, with no TOC dependency:

```lua
_G.BlackthornesFarmer.Butler:Advise(itemID)   -- a table, or nil; never raises
```

`Logic/Butler.lua` answers for the goals of the character playing (a goal
saved before owners counts, as `Goals:Find` has it), or nil when none is
for that item:

- `goal`: the goal's item name.
- `have`: how many the character has toward it (`Goals:Have`, bank
  included when goals count it; the saved `have` if the client will not say).
- `target`: the goal's number.
- `need`: `target - have`, never below 0 (0 once the goal is reached).

Goals are kept by name, so an item ID is matched by the ID the database
gives the goal's name, else by the name the client gives the ID (kept per
ID once given). Butler asks once per bag item in a burst, so the goals are
laid out as a lookup once and built again only when `Goals.version` moves
(`Set`, `Remove`, `ClearDone`) or the character's name comes in; only an
item with a goal reads its count. Keep the global, `Butler:Advise(itemID)`
and these four fields stable; if one has to change, change Butler's
`Logic/Sisters.lua` too.

## Sharing with the player's other account

The owner agreed (2026-10-11, a viewer's question on stream: can Farmer track
across characters and accounts?). Farmer's saved data was already shared by
every character on one account (`BlackthornesFarmerDB`; only goals are per
character, by `owner`), but WoW keeps accounts apart, so `Logic/Share.lua`
passes it over addon whispers the way Tradeskills' account link does
(`Logic/AccountLink.lua`, setting `linkNames`, both sides name each other).
Farmer has its own pairing, `shareNames`, rather than reading Tradeskills',
since neither addon depends on the other.

`Core/Comm.lua` and `Core/Serialize.lua` are Tradeskills' files brought over
(the prefix is `BFRshare`, so the two never read each other's messages; the
test command is gone and `Comm:Start`/`Stop` listen only while sharing is on,
since every addon's messages come through in a raid). A fix to the wire or
the serializer belongs in both repos.

What is shared is counts only: the loot harvest (`ns.Harvest.records`), the
kill tally (`tracker.mobs`), `gathering.nodes` and `fishing.spots`. Never
goals, settings or positions. How it never counts one twice: a side sends
only its own (its totals less what it has taken, `Share.Export`), and the
other adds only the rise over the most it has ever taken from that partner
(`Share.Merge`, kept in `shareIn[partner].credit`; a partner whose counts
fell, a reset, adds nothing until they pass it). So nothing goes round a
loop and nothing is relayed to a third account. Saved, never renamed:
`shareData` (off by default), `shareNames` (full names, comma apart) and
`shareIn` (`[partner] = { name, hashes, credit }`). Taken counts are merged
into the ordinary tables and cannot be taken back out; nothing is deleted. A
kill tally is made through `Tracker:GetMob`, which sets a pre-coin tally
aside first. Records are whitelisted and type-checked (`Share.CleanRecord`),
and a record whose key is not what its own fields make is refused. Lists are
built a slice a frame (`Share.SLICE`), never in combat, and sent a batch at a
time as the pacing frees up. Tested in `tools/test_share.lua`, which plays two
accounts over a pretend chat. Not yet seen in game; the owner has one account,
so only Tradeskills' one-account whisper test (full names, 2026-10-07) backs
the wire.

Naming several characters (2026-10-11): a partner is the account, not the
name. The manifest carries `i`, the sender's Farmer id (`Transfer:SourceId`,
`exportId`), and `Share:Identify` keeps it in `shareIn[partner].account`; a
second character with an id already held, or this account's own, is a
duplicate (`state.duplicate`) and nothing is taken from it. First heard
holds the ledger. Tested in `tools/test_share.lua`.

## Giving data to another player

A player asked (2026-10-11, the owner agreed) to export Farmer's data and
have someone else merge it into theirs. `Logic/Transfer.lua`, `UI/Import.lua`
(`/farm give`, `/farm take`, both with Settings buttons on the Sharing page).
It is account sharing by text: `Transfer:Make` builds
`BFR1:<id>:<part>/<parts>:<checksum>:<base 64 of Serialize.Encode>`, one line,
in parts of about 200,000 characters (`PART_RAW`), each complete in itself, and
the Export window hands it out with a Next part button. Nothing in it but
counts (the same sections and `Share.Export` as sharing, so it leaves out
everything taken from anyone: nothing is relayed). `id` is this Farmer's
`exportId`, made once and kept (never rename it). `Transfer:Parse` checks the
line, checksum and `Serialize.Decode` (data only, never run), then every
record through `Share.CleanRecord` and the key check, and refuses a count
over `MAX_COUNT`, a drop record with far more items than corpses
(`MAX_PER_CORPSE`) and more than `MAX_RECORDS` records a section. Nothing
changes before Apply. `Transfer:Apply` merges with `Share.Merge` into the
ledger `shareIn["import:<id>"]` (`kind = "import"`; never rename it), so the
same text twice adds nothing and a newer one adds the rise; `Transfer:Remove`
subtracts exactly the ledger from the records (dropping one that is left
empty) and deletes it. Everything is worked a few records a frame. Tested in
`tools/test_transfer.lua` and `tools/test_importwindow.lua`. Not yet seen in
game. A fix to `Core/Serialize.lua` still belongs in Tradeskills' too.

## The panel kept between sessions

The owner asked (2026-10-11) for the kills and loot panel to stop starting
empty after every /reload or relog, per character, with a way to clear it.
`Logic/Session.lua`: at `PLAYER_LOGOUT` (a reload too) Tracker's, Fishing's
and Gathering's session counts, the order last done, coin, best streak,
`ns.lastLoot` and the per-hour clock's play time go in the account save as
`panelSessions[guid]` (never rename it; the GUID from `Goals:Owner`), and
are added back at login, or on the first `PLAYER_ENTERING_WORLD` that reads
the GUID. Nothing is written while playing. A character whose GUID is never
read keeps and gets nothing. Corpses opened (by guid) and the running streak
are not kept. **Clear panel** (`Session:Clear`; the panel's Clear button
beside Sort and Settings > Kill tally, both `TrackerUI.ClearButton`, a
second click within `CLEAR_ARMED` seconds; `/farm tracker clear`) empties
the view only: every tally stays, so it is allowed on the Settings page.
Tested in `tools/test_panelkeep.lua`. Not yet seen in game.

## Drops only

A player asked (2026-10-11, the owner agreed) for Farmer to leave skinning
out and show only drops, on by default (the owner, 2026-10-11). "Hide
skinning" on the Loot page of Settings (`hideSkinning`, account wide, on
unless unticked; never rename it) and `/farm skinning [on|off]` (on shows
skinning). Ticked, `DB:HidesItem` and `DB:HidesSource`
leave out every `kind = "skinning"` source and every item the data names a
skinning spot for (`item.fromSkinning`: leather, hides, scales), since a
skin opens a loot window and recorded loot has the leather as a drop. The
search, `DB:ByName` (Rankings, worth estimates), `Value:FromTally`,
`Tracker:Summary` (panel, loot table), the Grind tab and the tooltip line
follow it, and so does the session (the Loot tab, its looted count, a
mob's loot worth, the session's worth and gold per hour, `Value:Session`,
`Tracker.Counts`); recorded data is never changed, and goals and their
arrow still follow a goal for leather. Every item a skinning window gives
is noted account wide in `skinnedItems` (`DB:NoteSkinned`,
`DB:WasSkinned`; never rename it), so a skin the data lists only as a drop,
or one Forever added, counts as skinning too. `DB:SetShowSkinning` moves `DB.hiddenVersion`
and calls `DB.hideWatchers`, so only the lists that show it redraw.
Tested in `tools/test_showskinning.lua`.

The hide list (the owner asked the same day for a blacklist): a mob, node
or item the player never wants to see, kept account wide in `hiddenItems`
and `hiddenSources` (`[lower case name] = name`; never rename either; an
item is keyed by the data's English name). `DB:Hide`, `DB:Unhide`,
`DB:IsHiddenItem`, `DB:IsHiddenSource`; `DB:HidesItem` and
`DB:HidesSource` answer for both rules, and the same `hiddenVersion` and
watchers redraw. A right-click on a row in the search, Rankings, Grind,
the loot table or the kills panel opens `UI/HideMenu.lua` ("Hide NAME",
nothing hidden until a line is clicked); `UI/HiddenWindow.lua` (`/farm
hidden`, Settings > Loot, `hiddenScale`) lists them with Show again;
`/farm hide <name>` and `/farm unhide <name>`. Rankings, the panel's
mobs (`Tracker:SessionMobs`) and the Loot tab (`TrackerUI:SessionItems`)
leave hidden ones out; recorded data is never changed. Tested in
`tools/test_hidelist.lua`.

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
keep their own frame, though their lines are dark glass too (2026-10-12:
`TrackerUI.Stripe` shades each line once a redraw, the open mob is
`glassActive` with a bright gold edge, an open card's lines sit on its
`glassAlt` card; the goal cards and spot rows alternate by index). Anything placed inside a dressed window stays 6 pixels
in from its edge, or it covers the rim.

Every window wears the house size grip (the owner, 2026-10-11, as in
Tradeskills, Equipment's quest panel and Butler): `Widgets.CreateSizeGrip`,
a gold-edged square with six dots outside the bottom right corner. Dragging
changes only the window's scale, from its top left corner, 50% to 150%, so
nothing is laid out again mid-drag and no text is cut; right-click is
normal size. Saved in percent, account wide, never renamed: `windowScale`
(search window, Rankings and Grind), `trackerScale` (kills panel, its own
grip), `settingsScale`, `lootTableScale`, `exportScale`, `goalsScale`,
`goalSpotsScale`, `goalPickerScale`. A new window gets one too
(`tools/test_windowgrips.lua`). The goal arrow is the shared dial, left
as it is.

List rows are dark glass (the owner picked it 2026-10-10 over a gold glow
that lit every row; Tradeskills and Equipment have the same):
`Widgets.CreateRowList` rows alternate `glass`/`glassAlt` with a fine line
under each, and the gold wash lights only the row under the mouse. A
gradient that fades goes through `Theme.LightGradient`, which hides it at
0; faded with SetAlpha alone it stayed lit on Forever.

## The Blizzard window style

The owner asked (2026-10-10) for a choice of the game's own look beside
Titanforged, in all four addons. "Window style" in Settings (`windowStyle`,
`titanforged` or `blizzard`, Titanforged by default; read once at login,
so a change waits for /reload, as Text size does; a stepper on the Windows
page, since Farmer has no dropdown). `UI/BlizzardLook.lua`
is the same file in all four (a fix to it belongs in all four): picked, it
lays the game's colours over `Theme.colors` (grey metal, the game's gold,
plain rows with a blue bar for the one picked) and puts out the halos;
`Titanforged:Dress` hands the window to `BlizzardLook.Dress` (silver rim,
a title tab where the plate sits, a silver-ringed portrait and the game's
`UIPanelCloseButton`, with the same trim fields); and the widgets call
`BlizzardLook.Button`, `.Checkbox`, `.Tab`/`.SelectTab` (hanging tabs) and
`.Thumb`/`.LightThumb` (Farmer's list scrollbars and the export box) to
wear the game's own texture files. It never touches a Blizzard frame. Each
file is checked once (`BlizzardLook.HasArt`); a client without one keeps
that widget in the house look. Farmer has no probe; Tradeskills',
Equipment's and Pets' probes list what is missing. Not yet seen in game.
New widgets should look right in both styles.

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

## Reading the probe

The owner asked (2026-10-10) for check results without screenshots, in all
four addons. `ns.KeepCheck(name, fn)` in `Core/Init.lua` runs a check that
prints to chat, keeps every line it prints (colours and links taken out, a
secret value kept as "(secret)") and saves them in the account save as
`lastProbe = { check, at, version, lines }`, replacing the last one; chat
adds "Saved for Claude, /reload to write it." It wraps `/bts probe`
(Tradeskills, saved under `BlackthornesTSDB.global`), `/beq probe` and
`/beq arrow check` (Equipment), `/bpet probe` and `/bpet arrow check`
(Pets), and `/farm arrow check`, `/farm gathering check` and `/farm harvest
check` (Farmer, which has no probe; the harvest check readies itself and
runs on the next loot window, to see what a dungeon lets it read). Each has a Settings button. Never rename `lastProbe`; a new
check that players run for a report goes through `ns.KeepCheck` too, and a
fix to it belongs in all four.

When the owner says "read the probe": he has run the check and typed
`/reload` (or logged out). In the thread, connect to his device, ask for
his game's WTF folder (already approved; the path is in the project's
memory) and stage the addon's account save from
`WTF\Account\<account>\SavedVariables\` (`Blackthornes_TS.lua`,
`Blackthornes_Farmer.lua`, `Blackthornes_Equipment.lua` or
`Blackthornes_Pets.lua`), read only. Read its `lastProbe`: `check` says
which one ran and `at` when; one older than his message means the save was
not written yet, so ask him to `/reload`. Use only the probe lines; never
commit the save or copy anything else out of it.

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
Changes to the Discord bots, the digest or the release posting tools
(like this one) never go in a CHANGELOG, #announcements or #general
section (the owner, 2026-10-10): they are not changes to the addon.

The language is "Deutsch" in every post (the owner, 2026-10-11): a
CHANGELOG.md or NEWS.md section about the German translation or German
clients says "Deutsch", or "Deutsch (German)" where English readers need
the hint, never "German" alone. `tools/check_release.py` warns (it does
not refuse) when this version's CHANGELOG.md or NEWS.md section says
German without Deutsch. This rule is in every addon's notes; keep them
the same.

## Loot inside dungeons

Inside a dungeon the client hides the corpse's name and guid from addons,
so until 2026-10-11 nothing looted there was recorded. The loot window
still names its source by guid (`GetLootSourceInfo`, readable in Ragefire
Chasm), and that guid carries the mob's ID, so `Harvest:Corpse` falls back
to the first creature the window names (`Harvest.NpcID`). Its name comes
from the game's unit link (`Harvest.NameFromLink`), kept account wide in
`npcNames[id]` (never rename it). Inside a dungeon the game gives none
(Ragefire Chasm, 2026-10-11), so Classic's name from `Data/NpcNames.lua`
stands in (`ns.NPC_NAMES`, generated by `tools/make_npc_names.py` from
pfQuest; never edit it by hand). A mob neither knows (one Forever added)
is kept as "Creature #ID" with `record.npc`, never exported
(`Harvest.Unnamed`), and renamed on load once a name is known
(`Harvest:NameUnnamed`, harvest and kill tally both). This works the same in every dungeon and raid.
`/farm harvest check` reports what a dungeon lets the addon read.

## What's New

The owner asked (2026-10-12) for the Discord #general post to show in game,
the first time it loads after an update, in one window for every addon.
`UI/WhatsNew.lua` is the same file in all five (a fix to it belongs in all
five), and so are `tools/test_whatsnew.lua`, `tools/make_whatsnew.py` and
`tools/test_make_whatsnew.py`. There is no shared core addon: every copy
signs up in `_G.BlackthornesWhatsNew` as it loads, the first to reach
PLAYER_LOGIN starts the only timer (`WhatsNew.DELAY`, 5 s, never in a
fight), and that one check gathers what is new in all of them. The copy
with the highest `FILE_VERSION` draws the window (first in
`WhatsNew.ADDONS` on a tie); raise it when a change needs the newer copy.

The words are NEWS.md's: it never ships, so `tools/make_whatsnew.py` writes
its newest three sections, bullets only (the thanks line names players and
never ships), into `Core/WhatsNewText.lua` (`ns.WHATS_NEW`; never edit it by
hand). **Every release PR that writes a NEWS.md section runs
`python tools/make_whatsnew.py` too**; `check_release.py` refuses a tag
while the file is behind, and `tools/test_make_whatsnew.py` fails on every
push. The bullets stay in English, also on a German client.

Shown once a version: each addon keeps the newest version shown in its own
account save (`whatsNewSeen`); after an update the sections newer than that
(at most three) show, and an addon that never kept one shows its newest.
"After an update" (`whatsNewPopup`) and "What's New motion"
(`whatsNewMotion`) are on unless unticked, off in all when off in any;
`whatsNewScale` is the size grip's, where the addon has one. Never rename
them. The `whatsnew` command and a Settings button open it any time, with
each addon's newest. It rises in, its divider draws out, each addon's card
slides up with its icon popping and a light crossing it, and the Got it
button glows (one looping animation the game plays, only while it shows);
Motion off lands it all at once. Not yet seen in game.

## The sister note

The owner asked (2026-10-11) for the addons to say, once, which of the
others a player does not have. `Core/SisterNote.lua` is the same file in
all five (a fix to it belongs in all five), and so is
`tools/test_sisternote.lua`. Every copy signs up in `_G.BlackthornesSisterNote`
as it loads; the first to reach PLAYER_LOGIN starts the only timer
(`SisterNote.DELAY`, 8 s, no ticker), and that one check prints one line for
all of them: the sisters not installed (`C_AddOns.DoesAddOnExist`, else
`GetAddOnInfo`'s "MISSING"), each with what it adds. One installed but
turned off is never named. Once per account: what it named is kept in every
loaded addon's account save as `sisterNoteTold[folder] = true`, so only a
sister never named before (one released later) brings it back. "Sister
addons" in Settings (`sisterNote`, on unless unticked) and the `sisters`
command on each addon: off in any is off in all, and changing it writes all.
Never rename `sisterNote` or `sisterNoteTold`. A new addon goes in
`SisterNote.ADDONS` in all the copies. It names only our own addons.

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

## German and other language clients

The data names items, zones, skills and creature types in English; a
German client names them in German. Nothing is translated: each check
also knows the client's own word, by ID, and only when
`Util.EnglishClient()` (`GetLocale`) says the client is not English, so
an English client runs exactly as before. Items: `DB:GetItem` falls back
to the name the client gives each ID (`DB:ByClientName`, read a few items
a frame and on `GET_ITEM_INFO_RECEIVED`), the search matches it too, and a
goal set by the client's name keeps that name (`Goals:ResolveItem`;
`Goals:Find` matches either name). Skills: `Gathering.ClientNames` and
`SkillOf` (spell names by ID, skill line names through
`C_TradeSkillUI.GetProfessionInfoBySkillLineID`). Zones: see "Zone names from
the client" below. Creature types are kept in English (`Grinding.EnglishType`,
`C_CreatureInfo.GetCreatureTypeInfo`), and coin words come from
`COPPER_AMOUNT` and the like (`Harvest.CoinValue`). Loot records stay keyed
by the client's mob name, and fishing schools are still told by English
name endings. Tested in `tools/test_german.lua`. Not yet seen in game.

The translation (the owner said yes, 2026-10-11, after Pets' pilot):
Farmer's own words are in German on a German client. Players are told
the language as "Deutsch"; the code names stay `deDE` and
`Locale/deDE.lua`.

- **English is the key and the fallback.** `Locale/Locale.lua` (first in
  the TOC, Pets' file) makes `ns.L`, whose missing keys answer the key
  itself. `L.Format(key, ...)` is `string.format` on the translation and
  puts values named by place (`%2$s ... %1$d`) in order.
- **Adding a string:** write it as `L["English text"]` or
  `L.Format("English %s", value)`, a literal where it is written, one
  whole sentence a key (never pieces joined with `..`), both forms for a
  plural (`Util.Plural(n, L["kill"], L["kills"])`); add its line to
  `Locale/deDE.lua` (informal "du" and the game's words: Beute, Ziel,
  Gegner, Vorkommen, Fundort, Kürschnerei, Fischschwarm, Stufe, Gebiet,
  Meter) and run `python tools/check_locale.py` (warns only; keep it at 0
  missing). `tools/test_locale.lua` loads the addon as a German client.
- **Left in English on purpose:** slash command words, saved and internal
  keys, anything compared against data or the client (zone names, coin
  words, skill names, creature types: `Grinding.TypeLabel` only shows
  one), data names (items, mobs; zones are kept English and only shown
  in German, `Spots.Show`), "Creature #ID", the harvest and
  fishing export text, debug lines, and the checks players run for a
  report (`/farm arrow check`, `gathering check`, `harvest check`).
  `Spots.Hops`' `travel` stays English; only `Spots.DistanceText` says it.
- German runs about 30% longer: buttons grow to fit, settings rows wrap,
  and a new fixed width must wrap or grow, never end in "...".
- `Locale/Locale.lua` and `tools/check_locale.py` are the same as Pets';
  a fix to either belongs in every addon that has them.

## Zone names from the client

The owner said "do it all" (2026-10-12) to using the Forever client's game
tables in every addon. Farmer's part is `Data/Zones.lua`, written by
`tools/make_zones.py` from the tables' AreaTable, Map and UiMap (English
and deDE exports, build named in the file; never edit it by hand, and never
commit the tables or name where they came from: "the Forever client's game
tables"). It holds names and map IDs only, no drop rates or spawns.

- `ns.ZONE_DATA.maps`: each zone's map ID, Forever's own (they match
  Classic's, and Forever's new zones are there). `Spots.ZONE_MAPS` is
  built from it; `Spots:Player` names the zone by the map when the name
  alone does not say.
- `ns.ZONE_DATA.english.deDE`: the English name of every German zone,
  dungeon and raid name the client gives. `Spots.English` reads it on a
  German client (after the names seen this session), so a record kept
  under "Wald von Elwynn" counts as Elwynn Forest anywhere.
- `ns.ZONE_DATA.names.deDE`: the German name of each, for showing.
  `Spots.Show(zone)` gives it on a German client (`Spots.ZoneLocale`, read
  once) and the zone as it is otherwise. The search rows and zone
  headings, Where to farm, the Grind tab and its pins, the item tooltip,
  Rankings, fishing and gathering places and the arrow show zones through
  it, and the search matches the German name too. Everything kept or
  compared stays English. A new place that shows a zone calls it too.

Tested in `tools/test_zones.lua`. Not yet seen in game.

## The owner's standing rules (both addons)

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
