# Changelog

Versions follow [semantic versioning](https://semver.org): the middle number
moves for new behaviour, the last for fixes alone. The newest version goes at
the top; a release is refused if its version has no section here.

## 0.23.1

For WoW: Forever (interface 16001). No files were added, so `/reload` is
enough after updating.

- **Fixes:** letting go of the goal arrow after dragging it never counts as
  a click or eats the next one. The Grind tab no longer counts groups like
  "spiders" as unknown mobs. The Rankings tab redraws once per burst of
  kills, the goals panel stops re-ranking farming places on every loot, a
  search runs once per keystroke, and the world map's pins stop being
  hidden over and over. "Open Farmer settings" in the game's options
  leaves the game's panel alone. TomTom gets the place again after the
  arrow or Use TomTom is turned off and on. The kills panel moves once per
  burst of group changes, and the Blizzard window style's portrait ring
  stays silver on every client.

## 0.23.0

For WoW: Forever (interface 16001). A file was added, so restart the game
fully after updating (`/reload` is not enough).

- **Window style:** Settings > Windows has a new Window style switch.
  Titanforged stays the default. Blizzard gives the windows the game's own
  look: grey colours, a silver rim, the game's close button, buttons, tick
  boxes, tabs and scroll knobs, and no glows. A change takes effect after a
  reload, and a Reload now button appears when it's needed.
- **Calmer list rows:** Search, Rankings, Grind and the goal lists look like
  dark glass, every other row a shade lighter with a fine line under each.
  The gold light shows only on the row under the mouse.
- **Goal arrow:** it moves on from a herb or vein you just picked instead of
  saying "You're there". If TomTom drops the waypoint, Farmer's dial comes
  back. It also works out its places only after a gather, new loot or a
  change of zone or level, not every couple of seconds while you walk.
- **More Forever loot:** drops from two more mobs and nine more corpses you
  looted on Forever.
- **Fixes:** the search list catches up when its tab shows instead of
  redrawing behind other tabs on every gather; Settings' Search window "Open
  it" always opens the window; and fixes to the Blizzard window style.

## 0.22.0

For WoW: Forever (interface 16001). `/reload` is enough after updating.

- **Grind tab:** the filter buttons no longer overlap; they wrap onto a new
  line when they don't fit.
- **Sort menu on the Grind tab:** Busiest, Nearest, Level, or Level then
  nearest, and the column headings (Type, Mob, Level, Gives, Per kill) sort
  the mobs inside each camp. Click once to sort, twice to flip it, three
  times to go back. Both are remembered.

## 0.21.0

For WoW: Forever (interface 16001). Files were added, so restart the game
fully after updating (`/reload` is not enough).

- **Grind tab:** pick a level band (it follows your level), a creature type
  and, if you like, Cloth or Skinning, and it lists the camps where those mobs
  gather, busiest or nearest first, with what a kill is worth. Click a camp
  and the goal arrow points at its mobs; the camps show on the world map too.
  `/farm grind` opens it.
- **New Settings window** like Tradeskills': pages along the top, a tooltip on
  every row (or **Show descriptions**), **Find a setting**, and **Text size**.
  Every `/farm` command now has a button, plus **Milestone fanfare** and
  **Count the bank** tick boxes. Reset and clear stay typed commands.
- **The version number** shows in the main window's corner and in the minimap
  button's tooltip.
- **Smoother play:** minimap herb and ore markers are no longer re-placed every
  second while you stand still, and mob values, Rankings, loot and casts take
  much less CPU.
- **One tooltip hook** now serves gathering, fishing and respawn times, so
  hovering costs less.
- **Fresher Forever drop data:** 2,461 looted corpses across 217 mobs, up
  from 2,197 across 193, with each mob's creature type for the Grind tab.

## 0.20.0

For WoW: Forever (interface 16001). Files were added, so restart the game
fully after updating (`/reload` is not enough).

- **Herbs and veins grow back:** Farmer learns respawn times from your own
  gathering. Once you've come back to a marked node three times on a map, its
  map markers say "Back in about 5 min" (or "Should be back by now"), and
  hovering that herb or vein in the world says how long it takes there. Until
  then they show "?" with how many returns it has seen.
- **TomTom:** with TomTom installed, the goal arrow's place goes to TomTom as a
  waypoint and Farmer's own dial stays hidden, so only one arrow is on screen.
  Places TomTom can't point at still show on the dial. Turn it off with the
  **Use TomTom** tick box in Settings.

## 0.19.1

For WoW: Forever (interface 16001). No files were added, so `/reload` is
enough after updating.

- Only one Blackthornes arrow is on screen at a time. With Equipment's
  quest arrow or Pets' beast arrow also installed, whichever arrow was
  turned on or aimed most recently is drawn and the others wait hidden,
  coming back once it is closed or has nothing to point at. With Farmer
  alone, nothing changes.

## 0.19.0

For WoW: Forever (interface 16001). Files were added, so restart the game
fully after updating (`/reload` is not enough).

- New **goal arrow** (`/farm arrow`, or the Goal arrow switch in Settings,
  off by default). A gold dial with a glowing arrow turns as you turn and
  points to the nearest place to gather the goal it follows, with the
  goal and its count on a plate and the distance, place and why it was
  picked underneath. Click the dial for the next goal, right-click for the
  next place, and Shift-click a goal card or a Where? place to point the
  arrow there. It hides inside dungeons and when you have no open goal,
  and its red close gem turns it off.
- The arrow points first to spots where you gathered the item yourself
  (a spot picked in the last 3 minutes waits until it has grown back),
  then to places the data has coordinates for, then to the middle of a
  zone. On the other continent it tells you to take the boat or zeppelin.
- The gathering goal picker now opens beside the search window instead of
  over its gold rim and close gem, flipping to the other side near the
  screen edge and following the window when it is resized.

## 0.18.0

For WoW: Forever (interface 16001). No files were added, so `/reload` is
enough after updating.

- The kills and loot panel can now be resized as a whole, text and all,
  from 50% to 150%. Drag the gold grip just outside its bottom right corner
  (right-click it for Normal), use the Small, Normal and Large buttons
  under **Kill tally size** in Settings, or type
  `/farm tracker size small|normal|large|<percent>`. It never grows past
  the screen.
- Changing Kill tally size or Search window size no longer makes the panel
  jump across the screen. The docked goals panel and the search columns
  follow the new size at once, and a bigger search window stays on screen.
- The goal picker now closes when its row scrolls to a different item or
  the search window closes.
- A close button no longer stays lit when its panel comes back.
- A kill of yours that dropped nothing and was then skinned now counts in
  the recorded drops too, so drop rates for skinnable mobs are no longer
  too high. A corpse looted before a `/reload` and skinned after it is no
  longer counted as a second kill.

## 0.17.3

For WoW: Forever (interface 16001). No files were added, so `/reload` is
enough after updating.

- The minimap button now sits on the minimap's ring beside other addons'
  buttons, instead of floating just outside it.

## 0.17.2

For WoW: Forever (interface 16001). No files were added, so `/reload` is
enough after updating.

- Kills, gathering and fishing keep counting after the first loot window,
  even when the game doesn't say the loot window closed.
- An item looked at before the game had loaded it now picks up its real
  sell price once it loads, instead of keeping the old Classic vendor price
  all session.
- In Where to farm, the "Nearest first, from ..." line sits at the top of
  the panel again, and place names line up in their rows.

## 0.17.1

For WoW: Forever (interface 16001). Nothing in the addon itself changed, so
`/reload` is enough after updating.

- New versions are now announced in the Blackthornes Discord, in the
  #announcements channel.

## 0.17.0

For WoW: Forever (interface 16001). No files were added, so `/reload` is
enough after updating.

- Kills & Loot now counts kills however you loot them: with the interact
  key, by right-clicking a corpse while another mob is targeted, with auto
  loot, or with a fast-loot addon. Before, only the corpse you had targeted
  counted. A corpse Farmer can't match to a mob is still skipped, never
  guessed.
- Your own kill that dropped nothing now counts once you skin it, with the
  leather as its drop. Skinning someone else's kill still isn't a kill.
- In the search window, click any column heading to sort an item's spots by
  source, where (closest to you first), level, drop rate, or the new PER
  KILL column, which shows worth per kill in gold, silver and copper.
- A BY ZONE switch groups each item's spots under their zones. The sort and
  the switch are remembered.

## 0.16.0

For WoW: Forever (interface 16001). This version adds files, so fully
restart the game after updating; `/reload` is not enough.

- New look: the search window wears a gold metal frame with corner gems, a
  round portrait holding a gold pickaxe, a title plate across the top and a
  red gem to close it. The Search and Rankings tabs hang below the window.
  Settings, Export, the loot table, the goal picker and Where to farm get the
  plate and close gem too. Buttons are raised gold-edged metal, the main
  action is solid gold, and everything glows under the mouse. A light runs
  round the portrait as the window opens and a glint slides along the rim,
  both following the Window effects setting. The kills panel, goals panel,
  toasts and map pins keep their own look.
- More drop data measured on Forever: 2,197 looted corpses across 193 mobs,
  up from 2,080, including the first Wailing Caverns kills.

## 0.15.2

## 0.15.2

For WoW: Forever (interface 16001). No files were added, so `/reload` is
enough after updating.

- More drop data measured on Forever: 2,080 looted corpses across 182 mobs,
  up from 2,004.

## 0.15.1

For WoW: Forever (interface 16001). No files were added, so `/reload` is
enough after updating.

- Vendor prices now come from the item's tooltip. On Forever the game's item
  info can still hold Classic's sell price, so an item like Greater Magic
  Wand was worth 15s 35c to Farmer while a vendor pays 1c.

## 0.15.0

For WoW: Forever (interface 16001). This version adds a file, so fully
restart the game after updating; `/reload` is not enough.

- Hovering a material anywhere (bags, the auction house, a chat link) adds a
  Farm: line to its tooltip with the best place to get it from where you
  stand, such as "Farm: Copper Vein (10-20), Westfall, you are here". It's
  the same pick the Where? button makes. Turn it off in Settings under
  Tooltips, or with `/farm tooltip`.
- More drop data measured on Forever: 2,004 looted corpses across 176 mobs,
  up from 1,900.

## 0.14.0

For WoW: Forever (interface 16001). No files were added, so `/reload` is
enough after updating.

- More drop data measured on Forever: 1,900 looted corpses across 176 mobs
  (mobs are now counted once however many places they were looted in).
- Goals belong to the character that set them. Logging in on a bank alt no
  longer counts its bags toward your main's goals or finishes them. The limit
  of six goals is per character. A goal set before this update shows on every
  character until one of them loots toward it or changes it.
- A goal only finishes once your bags have settled after loot, never on a
  login or loading screen. Crafting the item, or what reaches your bags just
  after a bank, mail, vendor, auction house or trade window closes, doesn't
  count as loot. The time left at your pace no longer starts out twice too
  quick.
- With area loot, the session's loot, coin, gathered value and per hour count
  everything the loot window gave you. A corpse you only skin is no longer
  counted as a kill, so drop rates stop being pulled down and rates no longer
  unlock early. An item being rolled for still counts as the mob's drop but
  not as your loot.
- Herbs picked with a corpse targeted are no longer listed as that mob's
  drops (Peacebloom and Silverleaf on Cursed Darkhounds and Greater
  Duskbats), and the export keeps them out.
- Searching a zone, landmark or mob lists only the spots that match it, and
  the heading says how many are shown ("5 of 47 spots").
- Drop rates under 1% read "<1%" instead of "0%".
- Where to farm says "10 zones away" or "by boat" instead of "other
  continent" for a far spot on your own continent.
- The kill and goals panels wear the house glow and flare when rates unlock,
  a goal is done or a milestone passes. Cards, rows, checkboxes, search boxes
  and tabs ease under the mouse. "Window effects" in Settings (Full, Subtle,
  Off) controls all of it.
- Text fits everywhere: long goal names, the Rankings tab on a small screen
  or scaled window, ranks of 100 and up, the loot table's "Killed at" line,
  and the unlock banner on a narrow panel.
- The kill panel stays within the height you set.
- Fixed: `/farm gathering reset confirm` also removed your map markers.
- Fixed: resetting the kill tallies made per hour read far too high.
- Fixed: a card that just unfolded redrew its bar from empty and skipped its
  cheers and countdown.

## 0.13.0

For WoW: Forever (interface 16001). No files were added, so `/reload` is
enough after updating.

- Drop data measured on Forever: 1,850 looted corpses across 268 mobs, with
  drop rates for the ones killed 20 times or more, and the first fishing
  catches. These show with the green Forever tag.
- The Where? pin only goes down for a spot in the zone you're standing in,
  and on that zone's map when you're in a cave or city inside it. A dungeon
  no longer gets a pin in the wrong place.
- "Set another" on the Goals panel switches to the Search tab first, so what
  you type isn't lost on the Rankings tab.
- `/farm value` finds mobs only the database knows, and an exact name now
  beats a longer one that starts with it.
- Exported drop rows keep one order when a mob has equal counts in two places.
- Fixed: "1 more kills" now reads "1 more kill".

## 0.12.0

For WoW: Forever (interface 16001). No files were added, so `/reload` is
enough after updating.

- Every window shares one look: a soft gold glow that flares when it opens,
  gold scrollbars, colours for each kind of source, a medal podium on
  Rankings, quality borders on loot, a fade where a list has more rows, and
  a gold glow on the row, chip or button under the mouse.
- The loot window counts its worth up when it opens.
- All of it follows `/farm effects` (Full, Subtle or Off).
- Fixed: loot from an area loot was credited to the wrong mob. Now only the
  mob you looted gets it.
- Fixed: the window could grow past the edge of the screen.
- Fixed: text was cut off in settings and on goal cards.
- Fixed: hover highlights never showed.
- Fixed: the rare drop sound stayed silent while the panel was hidden.
- Fixed: exported drop rates under 1% were written as 0.
- Resetting the tracker keeps item colours.

## 0.11.0

For WoW: Forever (interface 16001). No files were added, so `/reload` is
enough after updating.

- The Kills & Loot panel has Farm and Loot tabs.
- Farm: the mob you're killing is at the top, open and lit gold, with every
  item it has dropped as icons (a count until 20 kills, then the drop
  rate). Other mobs fold to one line with small icons and a bar toward 20
  kills. Click a mob to open or fold it, or click an icon for its loot
  table. Fishing spots and nodes work the same way.
- Loot: everything you looted, fished and gathered this session, best
  earners first, with medals on the top three and where each item came
  from.
- A Sort button (Recent, Worth per kill, Kills or Loot value; on Loot:
  Value, Count or Name), and gold per hour once you've played 5 minutes.
- The panel scrolls with the mouse wheel instead of cutting off.
- A new drop flashes its icon with "+2", a mob's first drop of an item gets
  a gold NEW tag, a Loot item that moves up says so, and the other tab gets
  a green dot when something new lands there.
- Money shows in gold, silver and copper colours in the panel, loot table,
  Rankings, search tooltips, goals and `/farm value`.

## 0.10.0

For WoW: Forever (interface 16001). No files were added, so `/reload` is
enough after updating.

- Every window has the same header as Tradeskills and fades in when it
  opens. Buttons ease into their hover colour, close buttons light red, and
  a gold line slides between the Search and Rankings tabs.
- Search results come in row by row with their drop bars growing, and each
  item heading shows the item's icon. The search box lights up while you
  type and has a clear button.
- An empty search suggests a cloth, a leather, an ore and a herb for your
  level.
- Rankings gives the top three mobs gold, silver and bronze medals, and its
  bars grow in.
- The loot table counts its kills up and grows its drop rate bars.
- The minimap button grows when you point at it.
- All of this follows `/farm effects`: Full shows everything, Subtle skips
  the row-by-row arrivals, and Off shows everything at once.

## 0.9.0

For WoW: Forever (interface 16001). This version adds a file, so fully
restart the game after updating; `/reload` is not enough.

- Each goal card has a Where? button that lists the best places near you to
  farm that item. Places are ranked by how far away they are, how their
  level compares to yours, the drop rate, and where you've already killed
  or gathered it. `/farm where <item>` does the same.
- The line under each goal names the top place. Click a place in the list
  to print it to chat, and to pin it on the map when it's in your zone.
- In the kills panel, each mob, fishing spot and node still short of 20 has
  a goal-style progress bar toward its drop rates: an "N / 20" count, marks
  at a quarter, half and three quarters, and green for the last few. It
  slides up with a shine, cheers at each mark and counts down "N more!" at
  the end. It follows `/farm effects`.
- Fixed: on the goal cards, text could overlap the progress bar or be cut
  short, and things behind the panel showed through. Cards are now solid
  and the panel widens to fit its text.

## 0.8.0

For WoW: Forever (interface 16001). This version adds files, so fully
restart the game after updating; `/reload` is not enough.

- Gathering goals: pick a material and a number and the new Goals panel
  counts you toward it. Press Goal beside an item in the search results, or
  type `/farm goal Copper Ore 40`. Up to six goals run at once.
- Each goal shows how many you have, the best spot for it, how many are
  left and how long the rest should take at your pace. What's already in
  your bags counts, and `/farm goal bank on` counts your bank too.
- Looting counts the goal up with a "+3 Copper Ore", the card pulses gold at
  a quarter, half and three quarters, the bar turns green for the last few,
  and finishing drops a GOAL COMPLETE banner with a recap. The effects
  follow `/farm effects`.
- The panel sits under the kills panel until you drag it. `/farm goals`
  shows or hides it, and `/farm goals dock` puts it back.
- With Blackthornes Tradeskills 0.10.0 or later, its Gather tab can set
  Farmer goals for the materials you still need.

## 0.7.0

For WoW: Forever (interface 16001). No files were added, so `/reload` is
enough after updating.

- In a party or raid, the kills and loot panel moves to the right of the
  group frames, and goes back to its own spot when you leave. Dragging it
  while grouped saves a separate group spot. On by default; turn it off in
  Settings under In a group, or with `/farm tracker group off`.
- The session's gathered value now sits on a second line of the panel's
  title bar, under "Kills & Loot", and still counts up with its "+" when
  something is added. The panel is a little wider so both lines fit.

## 0.6.1

For WoW: Forever (interface 16001). No files were added, so `/reload` is
enough after updating.

- Minimap markers are now an empty gold frame of corner brackets with the
  check outside a corner, so a herb or ore node that has grown back shows
  through the middle instead of being hidden.
- Markers on both maps sit beneath other pins.
- A marker's tooltip is now just the node and when you gathered it.

## 0.6.0

For WoW: Forever (interface 16001). This version adds a file, so fully
restart the game after updating; `/reload` is not enough.

- Gathered herb and ore spots are marked on the world map and minimap with a
  faded node icon and a green check, so a marker never looks like a live
  node. Hover one to see what it was and when you last took it. Each map has
  its own switch in Settings and under `/farm markers`, and
  `/farm markers clear confirm` removes the markers only.
- Kill streaks: kills no more than a minute apart build a streak, shown from
  the third kill with the session's best, and every fifth gets a cheer.
- A green-or-better drop now pulses in its quality colour and floats off the
  panel as "Nice!", "Rare!" or "Epic!".
- A 20th kill, cast or gather drops a gold banner over the panel.
- All of these follow `/farm effects`.

## 0.5.0

For WoW: Forever (interface 16001). This version adds sound files, so fully
restart the game after updating; `/reload` is not enough.

- The kills panel comes alive: Gathered value counts up with a "+" beside
  it, loot floats off the panel's edge, counts that went up glow, and the mob
  you just killed pulses gold with its bar sliding toward 20.
- A new chime plays when an item of green quality or better drops.
- The 20-kill fanfare now plays the addon's own sound.
- `/farm effects full|subtle|off` sets how much the panel moves, and
  `/farm raresound on|off` turns the rare-drop chime on or off. Both are in
  Settings too.

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
