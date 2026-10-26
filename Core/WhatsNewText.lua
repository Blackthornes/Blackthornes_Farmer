-- Core/WhatsNewText.lua
-- Written by tools/make_whatsnew.py from NEWS.md. Never edit it by hand:
-- change NEWS.md and run the tool. UI/WhatsNew.lua shows it.

local _, ns = ...

ns.WHATS_NEW = {
    { version = "1.0.0", lines = {
        "You can fish with a small window that has Cast and Add Lure buttons while you hold a fishing pole. Turn it on with Fishing Buttons on the Loot page.",
        "The Grind tab has a Fish view for the spots you've fished.",
        "Map pins show the item you gathered there, and close pins join into one with a count.",
        "Sparkles on nodes take the color of your skill, and you can add sparkles on corpses you can skin. Both are on the Map & goals page.",
        "The kill count by a mob's nameplate is bigger and pops when you get a kill.",
        "Price Order on the Loot page picks whether TSM or Auctionator is asked first. TSM comes first unless you change it.",
        "Arrow Size picks 50%, 75% or 100% for the guide arrow.",
        "A small gem beside the close button folds a window down to its title.",
    } },
    { version = "0.45.0", lines = {
        "You can set a kill goal, for any mob or one mob. It shows first in your Goals panel, and a summary opens when you finish. Start one with Set another in the Goals panel.",
        "The Ore, Herbs and Leather views on the Grind tab show your way from your skill to 300.",
        "With Tradeskills, Goblin Gold's hover card shows this week's kills and what their loot was worth.",
    } },
    { version = "0.44.0", lines = {
        "Loot Feed shows what you loot in a small list, with the coin and what it's all worth. It's off until you tick it on the Loot page of Settings.",
        "The trash can in your bags now puts a red glow round the item it picked. It's on the Loot page, under Trash Can When Full.",
    } },
}
