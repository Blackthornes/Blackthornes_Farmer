-- Core/WhatsNewText.lua
-- Written by tools/make_whatsnew.py from NEWS.md. Never edit it by hand:
-- change NEWS.md and run the tool. UI/WhatsNew.lua shows it.

local _, ns = ...

ns.WHATS_NEW = {
    { version = "1.2.0", lines = {
        "Drop Goals under Kills & Loot and it stays there. Drop Where to Farm under Goals and it opens there. You can turn this off with Snap Panels on the General page.",
        "Right-click a row and the thing you most likely want comes first, like Open Loot Table.",
    } },
    { version = "1.1.0", lines = {
        "One minimap button now covers every Blackthornes addon you have. Click it to pick one. Turn it off with Combine Addon Buttons on the Windows page.",
        "Show on Map in Where to farm puts a gold marker with the name on the spot.",
    } },
    { version = "1.0.1", lines = {
        "Settings is now the last tab, at the bottom right.",
        "The Fishing window's Cast and Add Lure buttons have the gold plaque look.",
    } },
}
