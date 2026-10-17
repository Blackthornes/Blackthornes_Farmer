-- Core/WhatsNewText.lua
-- Written by tools/make_whatsnew.py from NEWS.md. Never edit it by hand:
-- change NEWS.md and run the tool. UI/WhatsNew.lua shows it.

local _, ns = ...

ns.WHATS_NEW = {
    { version = "0.41.0", lines = {
        "Search now shows where trade goods, quest items and recipes drop, even before you've looted them. You get the mobs and a spot to find each one.",
    } },
    { version = "0.40.0", lines = {
        "The World Drops view on Rankings shows how often Uncommon, Rare, Epic and Legendary gear drops at each mob level. You can sort it, and it points out the best level and yours.",
    } },
    { version = "0.39.0", lines = {
        "The settings for making each panel transparent now sit together in one place on the UI page.",
    } },
}
