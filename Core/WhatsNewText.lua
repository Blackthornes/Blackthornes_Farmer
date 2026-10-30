-- Core/WhatsNewText.lua
-- Written by tools/make_whatsnew.py from NEWS.md. Never edit it by hand:
-- change NEWS.md and run the tool. UI/WhatsNew.lua shows it.

local _, ns = ...

ns.WHATS_NEW = {
    { version = "1.2.0", lines = {
        "Drop the Goals panel near the bottom of Kills & Loot and it hangs under it. Drop Where to Farm under Goals and it opens there. Turn it off with Snap Panels on the General page.",
        "Kills & Loot and Goals have a gold fold gem and a red close gem.",
        "A right-click on a row puts its own action first, like Open Loot Table or Show the Way.",
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
