-- Core/WhatsNewText.lua
-- Written by tools/make_whatsnew.py from NEWS.md. Never edit it by hand:
-- change NEWS.md and run the tool. UI/WhatsNew.lua shows it.

local _, ns = ...

ns.WHATS_NEW = {
    { version = "1.5.0", lines = {
        "There's a new fishing panel. It shows your session, how each spot is doing and every fish you've caught. It's off until you tick \"Fishing Panel:\" in the Loot settings.",
    } },
    { version = "1.4.3", lines = {
        "Map markers now show only the nodes your character can gather.",
    } },
    { version = "1.4.0", lines = {
        "One key can now put on a lure, cast and reel in your line.",
        "The Grind tab shows what each camp earns you an hour.",
        "Item icons look nicer, with quality rings and counts in the corner.",
    } },
}
