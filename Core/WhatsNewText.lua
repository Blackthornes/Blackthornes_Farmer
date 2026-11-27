-- Core/WhatsNewText.lua
-- Written by tools/make_whatsnew.py from NEWS.md. Never edit it by hand:
-- change NEWS.md and run the tool. UI/WhatsNew.lua shows it.

local _, ns = ...

ns.WHATS_NEW = {
    { version = "1.34.0", lines = {
        "A see-through Farm HUD ring shows your saved spots near you and points to the next stop on your route.",
        "Kills & Loot has a Slim Bar, a small graph of your run and a Run Recap that stays until you close it.",
        "Move Windows lets you drag every Farmer piece into place.",
        "Names show under the search box as you type.",
        "New Font, Colors and Fold Gem choices on the All Addons page.",
    } },
    { version = "1.33.0", lines = {
        "Your Way There is now a small see-through box with only your current step and a dial that points the way.",
    } },
    { version = "1.32.0", lines = {
        "The All Addons page in Settings has a Set Default button. Click Confirm and this addon's settings go back to how they started.",
    } },
}
