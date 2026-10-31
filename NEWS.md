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

## 1.4.0

- One key can now put on a lure, cast and reel in your line.
- The Grind tab shows what each camp earns you an hour.
- Item icons look nicer, with quality rings and counts in the corner.

Fixes and changes:

- Various bug fixes for Farmer.

## 1.3.0

- All your Blackthornes addons share one window. A strip down the left has a button for each addon you have, and the tabs of the one you pick sit beside it. At the auction house, mailbox, vendor and trainer it sits next to the game's window, and it goes back when you close that one. Turn it off with One Window on the General page.

Fixes and changes:

- Various bug fixes for Farmer.

## 1.2.0

- Drop Goals under Kills & Loot and it stays there. Drop Where to Farm under Goals and it opens there. You can turn this off with Snap Panels on the General page.
- Right-click a row and the thing you most likely want comes first, like Open Loot Table.

Fixes and changes:

- Various bug fixes for Farmer.

## 1.1.0

- One minimap button now covers every Blackthornes addon you have. Click it to pick one. Turn it off with Combine Addon Buttons on the Windows page.
- Show on Map in Where to farm puts a gold marker with the name on the spot.

Fixes and changes:

- Several bug fixes for text that wrapped over the line under it.

## 1.0.1

- Settings is now the last tab, at the bottom right.
- The Fishing window's Cast and Add Lure buttons have the gold plaque look.

Fixes and changes:

- Various UI improvements.

## 1.0.0

- You can fish with a small window that has Cast and Add Lure buttons while you hold a fishing pole. Turn it on with Fishing Buttons on the Loot page.
- The Grind tab has a Fish view for the spots you've fished.
- Map pins show the item you gathered there, and close pins join into one with a count.
- Sparkles on nodes take the color of your skill, and you can add sparkles on corpses you can skin. Both are on the Map & goals page.
- The kill count by a mob's nameplate is bigger and pops when you get a kill.
- Price Order on the Loot page picks whether TSM or Auctionator is asked first. TSM comes first unless you change it.
- Arrow Size picks 50%, 75% or 100% for the guide arrow.
- A small gem beside the close button folds a window down to its title.

Fixes and changes:

- Several bug fixes for the loot table, hidden items, the gather arrow and the Settings page.
- Word choices in Settings are now drop-downs.

## 0.45.0

- You can set a kill goal, for any mob or one mob. It shows first in your Goals panel, and a summary opens when you finish. Start one with Set another in the Goals panel.
- The Ore, Herbs and Leather views on the Grind tab show your way from your skill to 300.
- With Tradeskills, Goblin Gold's hover card shows this week's kills and what their loot was worth.

Fixes and changes:

- Several bug fixes for the Grind tab, Open After Loot, guild sharing and the Settings page.

## 0.44.0

- Loot Feed shows what you loot in a small list, with the coin and what it's all worth. It's off until you tick it on the Loot page of Settings.
- The trash can in your bags now puts a red glow round the item it picked. It's on the Loot page, under Trash Can When Full.

Fixes and changes:

- Several bug fixes for the XP bar and for looting with fast-loot addons.

## 0.43.0

- Each tooltip line Farmer adds can be Off, Shift or Always. You pick under Tooltips on the Map & goals page of Settings.
- Kill count on nameplates has a Counter Position choice. It can sit above, below, left or right of the name.

Fixes and changes:

- Coin and items from Pick Pocket count toward your session loot and gold.
- The words around the XP bar don't run into each other now.

## 0.42.0

- Farmer speaks Simplified Chinese, French, Spanish and Russian now if your game is in one of those.

## 0.41.0

- A heat map shows where you have killed on the world map and the minimap. It's off until you turn it on under Kill Heat on the Map & goals page of Settings. Then press Map beside a mob or item in the search, or on a mob's loot card.
- Rankings can leave Uncommon, Rare and Epic drops out of worth per kill. The tick box is on the Rankings tab.
- Quest items are marked Quest in the loot lists.

Fixes and changes:

- Item names use their rarity color in goals, loot tables, rankings and tooltips.
- Various fixes to Where to farm and the search.

## 0.40.2

Fixes and changes:

- Various fixes to Farmer.

## 0.40.0

- The World Drops view on Rankings shows how often Uncommon, Rare, Epic and Legendary gear drops at each mob level. You can sort it, and it points out the best level and yours.

Fixes and changes:

- The main window keeps the same size on every tab.

## 0.39.0

- The settings for making each panel transparent now sit together in one place on the UI page.

Fixes and changes:

- The XP bar fades all the way when it's transparent.
- Various fixes to Farmer.

## 0.38.0

- The goals panel, Where to farm, your top 15, the run recap and the XP bar can be transparent. Each is off until you turn it on, and you pick how clear.

## 0.37.0

- The Kills & Loot panel can be see-through. It's off until you turn it on, and you pick how clear.
- Tradeskills can tell which items you looted, gathered or fished yourself.
- When your bags are full, the trash can points at two short stacks you can join first, so nothing gets thrown away.

Fixes and changes:

- Various fixes to Farmer.

## 0.36.0

- A mob with the same name in another zone gets its own line.
- Tradeskills can show which of your kills drop items that break into an enchanting material.

Fixes and changes:

- Rankings show the levels you met a mob at when the data has none.
- The minimap button is always on.
- Various fixes to Farmer.

## 0.35.0

- Thanks Manthieus, seancool_com and their communities for the ideas and feedback! Catch their streams at twitch.tv/Manthieus and twitch.tv/seancool_com.
- An Open button on the kills panel opens your clams, sacks and lockboxes. Turn on Open after loot in Settings to open them as you go.
- Clams and sacks count for what's inside them, and a small note shows each one you open.
- A notice shows when your bags are full.
- Search finds items you looted, gathered or fished yourself, and plurals like "crates" work.
- Mobs show your kill count beside their nameplate.
- Material tooltips say when crafting pays more than selling.
- Tooltips and Settings descriptions are shorter and easier to read.

Fixes and changes:

- The XP bar is off until you turn it on in Settings.
- Various fixes to Farmer.

Thanks Manthieus, seancool_com and their communities for the ideas and feedback! Catch their streams at twitch.tv/Manthieus and twitch.tv/seancool_com.

## 0.34.0

- After an auction house scan, your top 15 farms pop up and show how they moved. A new best farm gets its own sound.
- Mobs in Forever's new dungeons get their names, and you can name any that are still numbers.
- The Rankings tab has a box that hides mobs found only in dungeons.

Fixes and changes:

- Several bug fixes for the Grind window.

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
