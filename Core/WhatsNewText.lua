-- Core/WhatsNewText.lua
-- Written by tools/make_whatsnew.py from NEWS.md. Never edit it by hand:
-- change NEWS.md and run the tool. UI/WhatsNew.lua shows it.

local _, ns = ...

ns.WHATS_NEW = {
    { version = "0.38.0", lines = {
        "The goals panel, Where to farm, your top 15, the run recap and the XP bar can be transparent. Each is off until you turn it on, and you pick how clear.",
    } },
    { version = "0.37.0", lines = {
        "The Kills & Loot panel can be see-through. It's off until you turn it on, and you pick how clear.",
        "Tradeskills can tell which items you looted, gathered or fished yourself.",
        "When your bags are full, the trash can points at two short stacks you can join first, so nothing gets thrown away.",
    } },
    { version = "0.36.0", lines = {
        "A mob with the same name in another zone gets its own line.",
        "Tradeskills can show which of your kills drop items that break into an enchanting material.",
    } },
}
