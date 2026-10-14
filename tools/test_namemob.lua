-- "Name this mob" (2026-10-14). Inside Ruins of Lordaeron Forever hides
-- every mob's name and tooltip from addons, and the mobs Forever added are
-- in no list, so they showed as "Creature #250484".
--
-- What matters: the player can name a numbered mob from the kills panel's
-- right-click; a junk or numbered name is refused; an ID something already
-- names is left alone; the panel shows the name at once and the saved data
-- moves to it at the next login; names shipped in Data/ForeverNpcNames.lua
-- name a mob for everyone.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("namemob")

local ns = env.Load({ ui = true })
local Harvest = ns.Harvest

-- Cleaning what was typed.
suite.check("spaces are trimmed", Harvest.CleanName("  Lordaeron   Ghoul ") == "Lordaeron Ghoul")
suite.check("an empty name is refused", Harvest.CleanName("   ") == nil)
suite.check("a number is refused", Harvest.CleanName("250484") == nil)
suite.check("a Creature # name is refused", Harvest.CleanName("Creature #250484") == nil)
suite.check("pipes are taken out", Harvest.CleanName("Brood|cffffffffling") == "Broodcffffffffling")
suite.check("a long name is refused", Harvest.CleanName(string.rep("a", 61)) == nil)
suite.check("not a string is refused", Harvest.CleanName(nil) == nil and Harvest.CleanName(5) == nil)

-- Naming by hand.
ns.db.npcNames = {}
suite.check("a numbered mob takes a name", Harvest:NameByHand(250484, " Broodling ") == "Broodling")
suite.check("kept by its ID", ns.db.npcNames[250484] == "Broodling")
suite.check("a named one is not renamed", Harvest:NameByHand(250484, "Spider") == nil
    and ns.db.npcNames[250484] == "Broodling")
suite.check("a Classic mob is never named by hand", Harvest:NameByHand(11318, "Something") == nil
    and ns.db.npcNames[11318] == nil)
suite.check("junk keeps nothing", Harvest:NameByHand(250485, "123") == nil
    and ns.db.npcNames[250485] == nil)
suite.check("the panel shows it at once", Harvest.ShowName("Creature #250484") == "Broodling")

-- Shipped names count for everyone.
ns.FOREVER_NPC_NAMES = ns.FOREVER_NPC_NAMES or {}
ns.FOREVER_NPC_NAMES[250490] = "Lordaeron Ghoul"
suite.check("a shipped name names the mob", Harvest.KnownNpcName(250490) == "Lordaeron Ghoul")
suite.check("and it is not asked for", Harvest:NameByHand(250490, "Other") == nil)
ns.FOREVER_NPC_NAMES[250490] = nil

-- The right-click menu offers it only for a numbered mob nobody names.
local offered
local open = ns.HideMenu.Open
ns.HideMenu.Open = function(_, choices) offered = choices; return true end
local function Kinds(choices)
    local kinds = {}
    for _, choice in ipairs(choices or {}) do kinds[#kinds + 1] = choice.kind end
    return table.concat(kinds, ",")
end
ns.HideMenu:Open({ { kind = "name", name = "Creature #250486", npcID = 250486 },
    { kind = "source", name = "Creature #250486" } })
suite.check("the menu gets both lines", Kinds(offered) == "name,source")
ns.HideMenu.Open = open

-- Picking it opens the box; Save keeps the name.
ns.HideMenu:Pick({ kind = "name", name = "Creature #250486", npcID = 250486 })
suite.check("the box opens for that mob", ns.NamePrompt.npcID == 250486
    and ns.NamePrompt.frame and ns.NamePrompt.frame:IsShown())
suite.check("a bad name keeps the box open", ns.NamePrompt:Save("   ") == nil
    and ns.NamePrompt.npcID == 250486)
suite.check("Save keeps the name", ns.NamePrompt:Save("Lordaeron Skulker") == "Lordaeron Skulker"
    and ns.db.npcNames[250486] == "Lordaeron Skulker")
suite.check("and closes the box", ns.NamePrompt.npcID == nil)
suite.check("the box will not open for a named mob", ns.NamePrompt:Open(250486) == false)
suite.check("nor for Classic's", ns.NamePrompt:Open(11318) == false)

-- The saved data moves at the next login, nothing lost.
Harvest.records["Creature #250486|Ruins of Lordaeron|"] = {
    mob = "Creature #250486", zone = "Ruins of Lordaeron", corpses = 3, npc = 250486,
    items = { ["Linen Cloth"] = { name = "Linen Cloth", id = 2589, corpses = 2, count = 3 } },
}
ns.db.tracker = ns.db.tracker or {}
ns.db.tracker.mobs = ns.db.tracker.mobs or {}
ns.db.tracker.mobs["Creature #250486"] = { kills = 3, copper = 60, coinKills = 3,
    items = { ["Linen Cloth"] = 3 }, places = { ["Ruins of Lordaeron"] = 3 } }
Harvest:NameUnnamed()
local record = Harvest.records["Lordaeron Skulker|Ruins of Lordaeron|"]
suite.check("the record takes the name", record and record.corpses == 3
    and record.items["Linen Cloth"].count == 3
    and Harvest.records["Creature #250486|Ruins of Lordaeron|"] == nil)
local tally = ns.db.tracker.mobs["Lordaeron Skulker"]
suite.check("the kill tally too", tally and tally.kills == 3
    and ns.db.tracker.mobs["Creature #250486"] == nil)

suite.done()
