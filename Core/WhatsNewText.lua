-- Core/WhatsNewText.lua
-- Written by tools/make_whatsnew.py from NEWS.md. Never edit it by hand:
-- change NEWS.md and run the tool. UI/WhatsNew.lua shows it.

local _, ns = ...

ns.WHATS_NEW = {
    { version = "0.40.0", lines = {
        "The World Drops view on Rankings shows how often Uncommon, Rare, Epic and Legendary gear drops at each mob level. You can sort it, and it points out the best level and yours.",
    } },
    { version = "0.39.0", lines = {
        "The settings for making each panel transparent now sit together in one place on the UI page.",
    } },
    { version = "0.38.0", lines = {
        "The goals panel, Where to farm, your top 15, the run recap and the XP bar can be transparent. Each is off until you turn it on, and you pick how clear.",
    } },
}
