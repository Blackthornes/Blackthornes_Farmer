# Changelog

Versions follow [semantic versioning](https://semver.org): the middle number
moves for new behaviour, the last for fixes alone. The newest version goes at
the top; a release is refused if its version has no section here.

## 0.4.2

For WoW: Forever (interface 16001).

- Fixed: hovering a mob in a dungeon raised a Lua error, twice per hover.
- Fixed: loot could be mistaken for a herb or ore node when the client
  called it fishing loot.
- The 20-kill /emote is no longer sent inside dungeons and raids. The
  fanfare and chat line still play.

## 0.4.1

For WoW: Forever (interface 16001).

- Fixed: the search and settings windows took the keyboard to watch for
  Escape, which put "Interface action failed because of an AddOn" on screen
  when one was open during a fight. Escape still closes them, through the
  same list the game's own windows use.
- Fixed: the 20-kill fanfare fell silent on a client without the achievement
  sound, instead of falling back to the level-up chime.
- Fixed: a value past a gold with no silver still showed its copper ("1g 3c"),
  while one with silver did not. Copper is dropped past a gold either way.
- A mob or item under the mouse is told apart from a school or a node on the
  newer tooltip API too, so a mob named "... Swarm" cannot pass for a
  fishing school.
- Wording: the Gathering heading counts gathers, not nodes; a few chat lines
  and data notes read more plainly.

## 0.4.0

For WoW: Forever (interface 16001).

- Rankings: the main window now has Search and Rankings tabs. Rankings lists
  every mob by what a kill is worth, on two separate boards: Your kills
  (measured from 20 or more of your own kills, coin included) and Estimates
  (from the database's drop rates, marked with ~). Mobs you have started on
  show how many kills they still need. `/farm rankings` opens it.
- Gathering: herbs you pick and veins you mine are recorded against the node,
  zone and subzone, and the panel grows a Gathering section once you have
  gathered this session. Yields show as counts until a node has 20 gathers,
  then as rates. `/farm gathering` lists what you have gathered in this zone.
- Fixed: herbs and ore could be counted as a mob's drop when a looted corpse
  was still targeted. `/farm gathering check` lists any an older version
  credited to a mob, without changing anything.
- Gathered value: the top of the panel shows what this session's haul is
  worth, the coin from your kills plus everything looted, fished up or
  gathered. Items with no price are left out and counted in a note.
- Grey items are now worth their vendor price only, whatever the auction
  house shows, in worth per kill, Rankings and the session total.

## 0.3.0

For WoW: Forever (interface 16001).

- Fishing: every catch is recorded against the zone, subzone and school you
  cast into. Once you have fished this session, the kills and loot panel gets
  a Fishing section with catch rates from 20 casts and what a cast is worth.
  `/farm fishing` lists what you have caught in the zone you are in.
- Mouse over a school once before fishing it and its catches count toward
  that school. Otherwise they count as open water.
- Each kill now notes where it happened. The panel shows where you kill a mob
  most, the loot table lists the top three places, and `/farm kills` lists
  them all.
- The kill that brings a mob to 20 plays a fanfare and prints the drop rates
  it just unlocked. It also does one /emote so players nearby see the
  milestone. `/farm announce off` keeps it to yourself, and
  `/farm celebrate off` turns the celebration off. Both are in Settings too.
- A fishing spot's 20th cast gets the same fanfare, chat line and /emote,
  once per spot, under the same two switches.

## 0.2.0

For WoW: Forever (interface 16001).

- Search any material and see every mob, node or vendor it comes from, with
  zone, level range and drop rate, lowest level first.
- Search by zone, mob or category to see what is worth farming there.
- 205 items across 651 sources. Each source is marked as Classic data until
  it has been confirmed on Forever; 76 are confirmed so far, marked
  [Forever].
- Kills and loot panel down the left side that tallies what you farm and turns
  it into drop rates once a mob has 20 kills. Drag its corner to resize it.
- Click a mob in the panel for its full loot table.
- With Blackthornes Tradeskills loaded, each mob shows what a kill is worth.
- A skinned corpse counts as one kill, and its leather as that mob's drop.
- Settings window: `/farm settings`, right-click the minimap button, or the
  game's AddOns options.
- The version now shows in the settings window and when you log in.

## 0.1.0

The first upload to CurseForge.
