-- Core/WhatsNewText.lua
-- Written by tools/make_whatsnew.py from NEWS.md. Never edit it by hand:
-- change NEWS.md and run the tool. UI/WhatsNew.lua shows it.

local _, ns = ...

ns.WHATS_NEW = {
    { version = "1.35.0", lines = {
        "The Grind tab has Rares and Treasures. Each row shows where it is, what it can give and a Show Way button.",
        "Rares and treasures can show on your world map. Both start off.",
        "A sound can play when a rare comes into view. It starts off.",
    } },
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
}
