-- Core/WhatsNewText.lua
-- Written by tools/make_whatsnew.py from NEWS.md. Never edit it by hand:
-- change NEWS.md and run the tool. UI/WhatsNew.lua shows it.

local _, ns = ...

ns.WHATS_NEW = {
    { version = "1.28.0", lines = {
        "Panels and rows have a warm brown-black look.",
        "Kills & Loot and Goals can look like the game's quest list. Pick Like Quest List under Panel Style on the Windows page.",
        "Item rows link in chat and try on gear.",
        "Farmer has its own key in Key Bindings.",
    } },
    { version = "1.27.0", lines = {
        "Every window has a gold gem on its title bar. Click it to switch between the one window and separate windows.",
    } },
    { version = "1.25.0", lines = {
        "The Kill Heat card starts smaller, and you can size it.",
        "A mob's card shows what you picked from its pockets.",
        "A new Exclude Rarity choice leaves rarities out of worth per kill.",
    } },
}
