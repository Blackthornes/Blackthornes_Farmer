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

## 0.33.0

- The Grind tab now shows Leather, Ore and Herbs too, with what each is worth and which nodes you can gather.
- A mob's tooltip lists the three drops that add the most to a kill.

Fixes and changes:

- Several bug fixes for the Grind arrow, trash can, Stats tab, XP bar and sharing.

## 0.32.2

Fixes and changes:

- NPCs show their full name over their head again while sparkles are on.

## 0.32.1

Fixes and changes:

- The beam of light now shows on quest pickups that are named differently from the quest goal.
- The level-up cheer floats over the screen with no box behind it.
- Sparkles no longer put names and health bars over vendors and objects.

## 0.32.0

- This is the largest AddOn update so far across the whole suite of Blackthornes addons.
- A new XP bar shows how long until your next level, which quests would finish it, and cheers when you level up.
- A new Stats tab draws your farming as charts: gold an hour, where the gold came from, your best mobs and your luck.
- The herb, vein, chest or fishing spot you face gets sparkles or a beam of light, and mobs a quest needs show how many are left.
- A mob's tooltip shows how many you've killed, and the kills panel shows how often green, blue and purple gear drops from it.
- When your bags are full, a little trash can sits on the item worth the least.

Fixes and changes:

- Middle-click the minimap button to show or hide your goals.
- The goal arrow now lies flat like a compass.
- Sharing kills and drop rates with guildmates is there, and off until you turn it on.
- Pearls and clams show where they really drop, and what you find inside them is counted.
- A corpse you open twice is counted once.

## 0.31.0

- When a kill moves a mob into or up your top 15, the list pops up beside the Kills & Loot panel and shows it climbing.

Fixes and changes:

- The Kills & Loot panel starts empty each time you log in, like it used to. All your data is kept, and Settings can keep the panel between sessions.
- No more ADDON BLOCKED error on your 20th catch.

Thanks Mimaco for the report!

## 0.30.1

Fixes and changes:

- The Kills & Loot panel scrolls smoothly.
- Gold per hour keeps counting after a reload.
- Grey items are always priced at what a vendor pays.
- Fixes for sharing, importing, map clicks and Deutsch clients.

## 0.30.0

- Zones show their German names on a Deutsch client, and Forever's new zones are known.
- Blue drops and finished goals play a voice line.
- Export your loot, kills, gathering and fishing to a spreadsheet.

Fixes and changes:

- The Kills & Loot and Goals panels use the dark list look.

Thanks manthieus for the spreadsheet idea!

## 0.29.0

- Without Tradeskills, Farmer prices your loot from TradeSkillMaster or Auctionator.

## 0.28.0

- Farmer speaks Deutsch now if your game is in German.

## 0.27.1

- Right-click to hide something and the menu now pops up right where your mouse is.
- With skinning hidden, skins no longer count in your loot or gold per hour.

## 0.27.0

- Skinning is now hidden by default, so you see just the drops. You can turn it back on in Settings.
- Right-click anything in a list to hide it.
- Your kills and loot panel stays put after a reload. There's a Clear button when you want a fresh start.
- Share your counts with your other account, or swap them with a friend.
- Every window has a size grip now.
- Works on German game clients too.

## 0.26.0

- You can now click any column title in the loot table and on Rankings to sort it. Click again to flip it.
- Farmer remembers how you like each list sorted.

## 0.25.1

- Fixed characters with the same first name sharing goals.

## 0.25.0

- Farmer won't send you to ore or herbs your skill can't gather yet.
- Set a new goal and the arrow pops up to lead you there.

## 0.24.1

- Pick Pocket doesn't count as a kill anymore, so your drop rates stay right.
- The arrow points right at the spot where you found a mob.
- Goals keep counting after you leave the mailbox or bank.

## 0.24.0

- Farmer now keeps track of loot in dungeons and raids, so you'll see drop rates for dungeon mobs too.
- The Grind tab's Sort menu doesn't get covered up anymore.

## 0.23.1

- Dragging the goal arrow won't count as a click anymore.
- The Grind tab stops counting mob groups like "spiders" as unknown mobs.
- Farmer does less work while you kill, loot and search, so play feels smoother.

## 0.23.0

- You can pick a new window look that matches the game's own windows. The gold look is still the default.
- Lists are calmer now. The gold glow only shows on the row under your mouse.
- The arrow moves on after you pick a herb or vein, and it comes back if TomTom drops your waypoint.
- Walking around with the arrow on is lighter on your game.

## 0.22.0

Hey everyone! A small Farmer update just went up.

The buttons on the Grind tab don't pile on top of each other anymore. There's also a new Sort menu, so you can sort camps by how busy they are, how close they are or their level, and you can click the column names to sort the mobs too. Thanks Ezmode for both!

A quick /reload after you update is all you need. Have fun!

## 0.21.0

Hey everyone! A new Farmer update just went up.

There's a new Grind tab. Pick a level, a kind of mob and whether you want cloth or skins, and it shows you where those mobs hang out. Click a spot and the arrow takes you there. You can also see which version you have in the corner of the window. Thanks Ezmode for both ideas!

Hovering over things is lighter on your game now. Thanks Lottus27 for telling us about the lag!

Settings got a makeover too. It has pages, a search box and bigger text if you want it. The minimap markers don't make the game stutter anymore, and everything runs lighter.

Restart the game fully after you update. Have fun!

## 0.20.0

Hey everyone! Farmer just got an update.

Farmer now learns how long herbs and veins take to grow back, just from your own gathering. After you've come back to a spot a few times, the map tells you when it'll be ready again. Thanks Lottus27 for the idea!

If you use TomTom, the goal arrow now hands its spot to TomTom so you only see one arrow. Thanks Ezmode for asking!

Restart the game fully after you update. Happy farming!
