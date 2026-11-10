# News

What each release says in the Discord server's #general channel: a few
short bullets per version, in plain words for players, saying what they'll
notice, then one line thanking, by their Discord name, everyone whose
feedback or report led to the changes (each name once; no line when nobody
asked). Each release PR writes the new version's section here next to its
CHANGELOG.md section, and after the upload `tools/post_general.py` posts it
under a line with the addon's name and version that points players to
#announcements for the full list. No link or addon card goes with it. This
is the only report that names players. A version with no section here posts
nothing in #general.
This file does not ship in the addon, but its newest sections do, without
the thanks line: `python tools/make_whatsnew.py` writes them into
Core/WhatsNewText.lua for the in-game What's New window. Run it after
writing a section; the release check refuses a tag while it is behind.

The window shows new features only. Write a section's features first, then
a "Fixes and changes:" line with the fixes and other changes under it: those
go to Discord but stay out of the window, and a section of only fixes puts
nothing in it. Say what each feature does in a few plain words, the way you'd
tell a friend: no hype, no questions to the reader, no exclamation marks
outside the thanks line, no dashes as punctuation, no "now you can". The
tool prints a note for a shipped line that reads like an advert.

## 1.11.0

- Pick a sound for when you find a node. Your character can call out, a peon can say he is ready to work, or you can get a little ping.
- It starts off, so you only hear it if you choose it.

## 1.10.2

Fixes and changes:

- A goal keeps the item you named, so Salt stays Salt.
- The quest count shows over quest mobs again.
- Holding Shift over a tooltip no longer causes an error.

## 1.10.1

Fixes and changes:

- The fishing panel shows what you caught, not a cast count.
- Cast and Add Lure are the same height now.

## 1.10.0

- Loot Beacons put a beam over the body in front of you while it still has loot. You can pick the color and size. Turn it on in Settings, on the Loot page.

Fixes and changes:

- Search finds items by their Deutsch names on a Deutsch client.

## 1.9.3

Fixes and changes:

- Fixed an error that popped up when you killed a mob.

## 1.9.2

Fixes and changes:

- The quest count is back on mob nameplates, and it still stays off the level.

## 1.9.1

Fixes and changes:

- The quest count over a mob no longer sits on top of its level.

## 1.9.0

- A new box in Settings, on the Map & goals page, called My Professions Only. Ticked, only the herbs, ore and fish your character can gather light up. It starts off.

Fixes and changes:

- Veins now get their beam on Deutsch (German) and other non-English games.

## 1.8.1

Fixes and changes:

- If you share your drops, they now go to one more of our characters. It is still off until you turn it on.

## 1.8.0

- You can turn off the beam over your fishing bobber if it hides the bob. It is in Settings, on the Map & goals page, under Sparkles.

## 1.7.0

- You can drag the Top 15 window where you want it. Set Default in Settings, on the Kills page, puts it back.

## 1.6.6

Fixes and changes:

- Herbs with Forever's new names, like Wilted Peacebloom, now always get a beam in the right skill color.

## 1.6.5

Fixes and changes:

- The interact plate stays off NPCs when friendly NPC nameplates are off. Beams still show on herbs and ore.

## 1.6.4

Fixes and changes:

- One Window keeps its size when it docks while folded.

## 1.6.3

Fixes and changes:

- Fish in the Fishing panel show their icons.
- The Add Lure button shows a dimmed lure icon when you have no lures.

## 1.6.2

Fixes and changes:

- The quest count on nameplates no longer covers the mob's level.
- Sparkles no longer turn the game's Interact Key back on after you turn it off.

## 1.6.1

Fixes and changes:

- Various bug fixes for Farmer.

## 1.6.0

- Drop rates on a mob's loot table count your guild's kills too, once you've killed that mob 20 times yourself. Guild sharing has to be on.

Fixes and changes:

- Various bug fixes for Farmer.

## 1.5.2

Fixes and changes:

- Various bug fixes for Farmer.

