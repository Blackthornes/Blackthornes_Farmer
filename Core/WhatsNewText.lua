-- Core/WhatsNewText.lua
-- Written by tools/make_whatsnew.py from NEWS.md. Never edit it by hand:
-- change NEWS.md and run the tool. UI/WhatsNew.lua shows it.

local _, ns = ...

ns.WHATS_NEW = {
    { version = "1.16.0", lines = {
        "You can pick which TSM price to use, on the Loot page. It starts on the recent price.",
        "In a group, only the loot you really got counts now.",
    } },
    { version = "1.15.0", lines = {
        "Windows now remember where you drag them, so they come back in the same spot.",
        "A new button on the General page puts every window back where it started.",
    } },
    { version = "1.14.0", lines = {
        "There is a new box that mutes every sound from all the Blackthornes addons at once. It starts off, so nothing changes until you tick it.",
    } },
}
