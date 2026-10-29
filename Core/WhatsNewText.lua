-- Core/WhatsNewText.lua
-- Written by tools/make_whatsnew.py from NEWS.md. Never edit it by hand:
-- change NEWS.md and run the tool. UI/WhatsNew.lua shows it.

local _, ns = ...

ns.WHATS_NEW = {
    { version = "1.1.0", lines = {
        "One minimap button now covers every Blackthornes addon you have. Click it to pick one. Turn it off with Combine Addon Buttons on the Windows page.",
        "Show on Map in Where to farm puts a gold marker with the name on the spot.",
    } },
    { version = "1.0.1", lines = {
        "Settings is now the last tab, at the bottom right.",
        "The Fishing window's Cast and Add Lure buttons have the gold plaque look.",
    } },
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
}
