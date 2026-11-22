-- Core/WhatsNewText.lua
-- Written by tools/make_whatsnew.py from NEWS.md. Never edit it by hand:
-- change NEWS.md and run the tool. UI/WhatsNew.lua shows it.

local _, ns = ...

ns.WHATS_NEW = {
    { version = "1.30.0", lines = {
        "Right-click a mob on the Zone Board to hide it in that zone. Show Again brings it back.",
    } },
    { version = "1.29.0", lines = {
        "Windows fold into a round button. Kills & Loot shows your kills on it, and Goals shows goals done.",
    } },
    { version = "1.28.0", lines = {
        "Panels and rows have a warm brown-black look.",
        "Kills & Loot and Goals can look like the game's quest list. Pick Like Quest List under Panel Style on the Windows page.",
        "Item rows link in chat and try on gear.",
        "Farmer has its own key in Key Bindings.",
    } },
}
