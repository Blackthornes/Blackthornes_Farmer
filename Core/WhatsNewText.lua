-- Core/WhatsNewText.lua
-- Written by tools/make_whatsnew.py from NEWS.md. Never edit it by hand:
-- change NEWS.md and run the tool. UI/WhatsNew.lua shows it.

local _, ns = ...

ns.WHATS_NEW = {
    { version = "0.33.0", lines = {
        "The Grind tab now shows Leather, Ore and Herbs too, with what each is worth and which nodes you can gather.",
        "A mob's tooltip lists the three drops that add the most to a kill.",
    } },
    { version = "0.32.0", lines = {
        "This is the largest AddOn update so far across the whole suite of Blackthornes addons.",
        "A new XP bar shows how long until your next level, which quests would finish it, and cheers when you level up.",
        "A new Stats tab draws your farming as charts: gold an hour, where the gold came from, your best mobs and your luck.",
        "The herb, vein, chest or fishing spot you face gets sparkles or a beam of light, and mobs a quest needs show how many are left.",
        "A mob's tooltip shows how many you've killed, and the kills panel shows how often green, blue and purple gear drops from it.",
        "When your bags are full, a little trash can sits on the item worth the least.",
    } },
    { version = "0.31.0", lines = {
        "When a kill moves a mob into or up your top 15, the list pops up beside the Kills & Loot panel and shows it climbing.",
    } },
}
