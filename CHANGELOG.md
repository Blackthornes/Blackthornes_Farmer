# Changelog

Versions follow [semantic versioning](https://semver.org): the middle number
moves for new behaviour, the last for fixes alone. The newest version goes at
the top; a release is refused if its version has no section here.

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
