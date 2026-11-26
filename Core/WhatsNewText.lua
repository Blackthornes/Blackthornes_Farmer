-- Core/WhatsNewText.lua
-- Written by tools/make_whatsnew.py from NEWS.md. Never edit it by hand:
-- change NEWS.md and run the tool. UI/WhatsNew.lua shows it.

local _, ns = ...

ns.WHATS_NEW = {
    { version = "1.33.0", lines = {
        "Your Way There is now a small see-through box with only your current step and a dial that points the way.",
    } },
    { version = "1.32.0", lines = {
        "The All Addons page in Settings has a Set Default button. Click Confirm and this addon's settings go back to how they started.",
    } },
    { version = "1.31.0", lines = {
        "A new Near My Level box on Rankings and Estimates lists only mobs close to your level. It starts off.",
    } },
}
