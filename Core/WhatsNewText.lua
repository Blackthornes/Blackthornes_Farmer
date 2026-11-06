-- Core/WhatsNewText.lua
-- Written by tools/make_whatsnew.py from NEWS.md. Never edit it by hand:
-- change NEWS.md and run the tool. UI/WhatsNew.lua shows it.

local _, ns = ...

ns.WHATS_NEW = {
    { version = "1.7.0", lines = {
        "You can drag the Top 15 window where you want it. Set Default in Settings, on the Kills page, puts it back.",
    } },
    { version = "1.6.0", lines = {
        "Drop rates on a mob's loot table count your guild's kills too, once you've killed that mob 20 times yourself. Guild sharing has to be on.",
    } },
}
