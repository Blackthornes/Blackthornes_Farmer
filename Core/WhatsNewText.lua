-- Core/WhatsNewText.lua
-- Written by tools/make_whatsnew.py from NEWS.md. Never edit it by hand:
-- change NEWS.md and run the tool. UI/WhatsNew.lua shows it.

local _, ns = ...

ns.WHATS_NEW = {
    { version = "1.31.0", lines = {
        "A new Near My Level box on Rankings and Estimates lists only mobs close to your level. It starts off.",
    } },
    { version = "1.30.0", lines = {
        "Right-click a mob on the Zone Board to hide it in that zone. Show Again brings it back.",
    } },
    { version = "1.29.0", lines = {
        "Windows fold into a round button. Kills & Loot shows your kills on it, and Goals shows goals done.",
    } },
}
