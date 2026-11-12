-- Core/WhatsNewText.lua
-- Written by tools/make_whatsnew.py from NEWS.md. Never edit it by hand:
-- change NEWS.md and run the tool. UI/WhatsNew.lua shows it.

local _, ns = ...

ns.WHATS_NEW = {
    { version = "1.15.0", lines = {
        "Windows now remember where you drag them, so they come back in the same spot.",
        "A new button on the General page puts every window back where it started.",
    } },
    { version = "1.14.0", lines = {
        "There is a new box that mutes every sound from all the Blackthornes addons at once. It starts off, so nothing changes until you tick it.",
    } },
    { version = "1.13.0", lines = {
        "Pick where the quest count sits next to a mob's name: above, below, left or right.",
        "The quest count is bigger and brighter, so it is easier to read.",
        "It still starts on the right, so nothing moves unless you pick a new spot.",
    } },
}
