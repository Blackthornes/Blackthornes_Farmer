-- The Grind tab's Leather, Ore and Herbs views (the owner said yes,
-- 2026-10-14, from a mockup).
--
-- What matters: Leather lists beasts to skin with the Skinning each needs,
-- also with "Hide skinning" ticked while you know Skinning, and never puts
-- a skin-only spot in the other views; a skin's worth is what your own
-- skins gave, each corpse counted once; Ore and Herbs list zones and their
-- nodes from the data and your own gathering (gathers, spots, grow back,
-- a gather's worth), an hour's worth only from time you spent gathering
-- (breaks and zone changes left out); a node you cannot gather yet says the
-- skill it needs; the tab, the command and a click on a node work.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("grindgather")
local check = suite.check

local ns = env.Load({ ui = true, hideSkinning = true })
local Grinding, GrindGather, GrindingUI, UI, DB = ns.Grinding, ns.GrindGather, ns.GrindingUI, ns.UI, ns.DB

local ZONE = "Test Vale"
local skills = nil
ns.Spots.Skills = function() return skills end

-- Every item 10 copper, so worth is easy to read.
ns.Value.UnitPrice = function(_, id) if id then return 10, "auction" end end

DB:RegisterItem({ name = "Test Leather", id = 900001, category = "Leatherworking", sources = {
    { kind = "skinning", name = "Vale Wolf", zone = ZONE, coords = { 10, 80 }, minLevel = 22, maxLevel = 24 },
    { kind = "skinning", name = "Vale Stag", zone = ZONE, coords = { 12, 81 }, minLevel = 15, maxLevel = 16,
        requires = "Skinning 40" },
} })
DB:RegisterItem({ name = "Test Silk", id = 900002, category = "Cloth", sources = {
    { name = "Vale Bandit", zone = ZONE, location = "Bandit Camp", coords = { 40, 40 }, minLevel = 22, maxLevel = 24 },
} })
DB:RegisterItem({ name = "Test Ore", id = 900003, category = "Mining", sources = {
    { kind = "node", name = "Test Vein", zone = ZONE, minLevel = 20, maxLevel = 30, requires = "Mining 65" },
    { kind = "node", name = "Test Deposit", zone = ZONE, minLevel = 20, maxLevel = 30, requires = "Mining 125" },
} })
DB:RegisterItem({ name = "Test Stone", id = 900004, category = "Mining", sources = {
    { kind = "node", name = "Test Vein", zone = ZONE, minLevel = 20, maxLevel = 30, requires = "Mining 65" },
} })
DB:RegisterItem({ name = "Test Weed", id = 900005, category = "Herbalism", sources = {
    { kind = "herb", zone = ZONE, minLevel = 20, maxLevel = 30, requires = "Herbalism 70" },
} })

local function Has(camps, name)
    for _, camp in ipairs(camps) do
        for _, mob in ipairs(camp.mobs) do
            if mob.name == name then return true end
        end
    end
    return false
end

--------------------------------------------------------------------------------
-- The skill a mob needs
--------------------------------------------------------------------------------

check("level 5 needs 1", Grinding.SkinSkill(5) == 1)
check("level 15 needs 50", Grinding.SkinSkill(15) == 50)
check("level 20 needs 100", Grinding.SkinSkill(20) == 100)
check("level 21 needs 105", Grinding.SkinSkill(21) == 105)
check("no level, no skill", Grinding.SkinSkill(nil) == nil)

--------------------------------------------------------------------------------
-- Leather with "Hide skinning" ticked
--------------------------------------------------------------------------------

check("hidden and no Skinning: no Leather", not Grinding.OffersLeather())
ns.db.grindGives = "skinning"
check("so a saved Leather lets go", Grinding:Gives() == nil)

skills = { Skinning = 94 }
check("knowing Skinning offers it anyway", Grinding.OffersLeather() and Grinding:Gives() == "skinning")

local camps = Grinding:Camps({ low = 14, high = 26, type = false, gives = "skinning" })
check("Leather lists the beasts to skin", Has(camps, "Vale Wolf") and Has(camps, "Vale Stag"))
check("and not the cloth droppers", not Has(camps, "Vale Bandit"))

camps = Grinding:Camps({ low = 14, high = 26, type = false, gives = false })
check("any type leaves skin-only spots out while skinning is hidden", not Has(camps, "Vale Wolf")
    and Has(camps, "Vale Bandit"))

local wolf, stag
for _, mob in pairs(Grinding:Mobs().all) do
    if mob.name == "Vale Wolf" then wolf = mob end
    if mob.name == "Vale Stag" then stag = mob end
end
check("the data's skill wins", GrindingUI.SkinNeed(stag) == 40)
check("else Classic's rule from the level", GrindingUI.SkinNeed(wolf) == 110)
check("short of it says so", GrindingUI.SkillText(110, 94) == "110, you have 94")
check("enough is just the number", GrindingUI.SkillText(40, 94) == "40")
check("the wolf gives its leather", wolf.leathers["Test Leather"] == true)

--------------------------------------------------------------------------------
-- Skins: what yours gave, once a corpse
--------------------------------------------------------------------------------

GrindGather:NoteSkin("Vale Wolf", "Creature-1", { "Test Leather" }, { ["Test Leather"] = 2 })
GrindGather:NoteSkin("Vale Wolf", "Creature-1", { "Test Leather" }, { ["Test Leather"] = 2 })
GrindGather:NoteSkin("Vale Wolf", "Creature-2", { "Test Leather" }, { ["Test Leather"] = 4 })
check("each corpse once", ns.db.skinLog["Vale Wolf"].skins == 2, ns.db.skinLog["Vale Wolf"].skins)
check("what they gave", ns.db.skinLog["Vale Wolf"].items["Test Leather"] == 6)
local worth, skins = GrindGather:SkinWorth("Vale Wolf")
check("a skin's worth", worth == 30 and skins == 2, worth)
ns.db.harvestPaused = true
GrindGather:NoteSkin("Vale Wolf", "Creature-3", { "Test Leather" }, {})
check("nothing while recording is paused", ns.db.skinLog["Vale Wolf"].skins == 2)
ns.db.harvestPaused = nil

--------------------------------------------------------------------------------
-- Ore and herbs
--------------------------------------------------------------------------------

skills = { Mining = 87, Herbalism = 112, Skinning = 94 }
ns.db.gathering = ns.db.gathering or {}
ns.db.gathering.nodes = {
    ["Test Vale||Test Vein"] = { zone = ZONE, node = "Test Vein", kind = "ore", gathers = 4,
        items = { ["Test Ore"] = { gathers = 4, count = 8, id = 900003 } } },
    ["Test Vale|Elsewhere|Test Weed"] = { zone = ZONE, node = "Test Weed", kind = "herb", gathers = 2,
        items = { ["Test Weed"] = { gathers = 2, count = 2, id = 900005 } } },
}
local mapID = ns.Spots.ZONE_MAPS["Elwynn Forest"]
ns.Spots.MAP_ZONES[99901] = ZONE
ns.db.gathering.spots = {
    { map = 99901, x = 0.5, y = 0.4, node = "Test Vein", kind = "ore", gathers = 3 },
    { map = 99901, x = 0.6, y = 0.4, node = "Test Vein", kind = "ore", gathers = 1 },
}
ns.Respawn:Learn(99901, "Test Vein", 300)
ns.Respawn:Learn(99901, "Test Vein", 360)
ns.Respawn:Learn(99901, "Test Vein", 400)

-- An hour: two gathers 100 s apart, a break, and one after a zone change.
GrindGather:NoteGather(ZONE, "Test Vein", { "Test Ore" }, { ["Test Ore"] = 2 }, 1000)
GrindGather:NoteGather(ZONE, "Test Vein", { "Test Ore" }, { ["Test Ore"] = 2 }, 1100)
GrindGather:NoteGather(ZONE, "Test Vein", { "Test Ore" }, { ["Test Ore"] = 2 }, 2000)
GrindGather:NoteGather("Other Place", "Test Vein", { "Test Ore" }, { ["Test Ore"] = 2 }, 2050)
GrindGather:NoteGather(ZONE, "Test Vein", { "Test Ore" }, { ["Test Ore"] = 2 }, 2100)
-- A chest is not a herb or a vein: it keeps no pace.
local noted = 0
local note0 = GrindGather.NoteGather
GrindGather.NoteGather = function() noted = noted + 1 end
ns.Gathering:Record("Chest Vale", "Somewhere", "Battered Chest", "container", { "Test Ore" }, { ["Test Ore"] = 1 })
check("a chest keeps no gathering pace", noted == 0)
ns.Gathering:Record("Chest Vale", "Somewhere", "Chest Vein", "ore", { "Test Ore" }, { ["Test Ore"] = 1 })
check("a vein does", noted == 1)
GrindGather.NoteGather = note0
local pace = ns.db.gathering.pace["Test Vale|Test Vein"]
check("only the time between gathers counts", pace.seconds == 100, pace.seconds)
check("every gather's yield", pace.items["Test Ore"] == 8 and pace.gathers == 4)

local function ZoneNamed(zones, name)
    for _, zone in ipairs(zones) do if zone.zone == name then return zone end end
end
local function NodeNamed(zone, name)
    for _, node in ipairs(zone and zone.nodes or {}) do if node.name == name then return node end end
end

local zone = ZoneNamed(GrindGather:Zones("ore", 20, 30), ZONE)
local vein = NodeNamed(zone, "Test Vein")
check("the zone and its nodes", zone and vein and NodeNamed(zone, "Test Deposit") ~= nil)
check("no herb among the ore", NodeNamed(zone, "Test Weed") == nil)
check("its level band", zone.minLevel == 20 and zone.maxLevel == 30)
check("the skill", vein.skill == 65)
check("what it gives", table.concat(vein.givesList, ",") == "Test Ore,Test Stone", table.concat(vein.givesList, ","))
check("your gathers", vein.gathers == 4)
check("your spots", vein.spots == 2 and #vein.spotList == 2)
check("how soon it grows back", vein.respawn == 360, vein.respawn)
check("a gather's worth", vein.perGather == 20, vein.perGather)
check("no hour yet under ten minutes", vein.perHour == nil)
pace.seconds = 720
vein = NodeNamed(ZoneNamed(GrindGather:Zones("ore", 20, 30), ZONE), "Test Vein")
check("then an hour's worth", vein.perHour == 400, vein.perHour)
check("nothing out of the band", ZoneNamed(GrindGather:Zones("ore", 1, 5), ZONE) == nil)

local herbs = ZoneNamed(GrindGather:Zones("herbs", 20, 30), ZONE)
local weed = NodeNamed(herbs, "Test Weed")
check("a herb is its own node", weed and weed.skill == 70 and weed.gathers == 2)

DB:Hide("source", "Test Deposit")
check("a hidden node is left out", NodeNamed(ZoneNamed(GrindGather:Zones("ore", 20, 30), ZONE), "Test Deposit") == nil)
DB:Unhide("source", "Test Deposit")

--------------------------------------------------------------------------------
-- The tab
--------------------------------------------------------------------------------

ns.HandleSlash("grind 20-30 ore")
check("/farm grind ore", Grinding:Gives() == "ore" and UI.tab == "grind")
local rows = GrindingUI.list.data
local zoneRow, veinRow, deposit
for _, row in ipairs(rows) do
    if row.type == "zone" and row.zone.zone == ZONE then zoneRow = row end
    if row.type == "node" and row.zone.zone == ZONE and row.node.name == "Test Vein" then veinRow = row end
    if row.type == "node" and row.zone.zone == ZONE and row.node.name == "Test Deposit" then deposit = row end
end
check("a band per zone, its nodes under it", zoneRow and veinRow and deposit)
check("the band names the zone", GrindingUI.ZoneText(zoneRow.zone):find("Test Vale") ~= nil)
check("a node you can't gather yet says the skill",
    GrindingUI:NodeTexts(deposit.node).skill == "125, you have 87" and GrindingUI:NodeTexts(deposit.node).short)
check("one you can, just the number", GrindingUI:NodeTexts(veinRow.node).skill == "65")
check("the columns are the node view's", GrindingUI.columns.layout == "nodes"
    and GrindingUI.columns.hour and not GrindingUI.columns.type)
check("its headings", GrindingUI.headings.hour:IsShown() and not GrindingUI.headings.type:IsShown()
    and GrindingUI.headings.mob:GetText() == "NODE")
check("no creature types for nodes", not GrindingUI.typeChips[1]:IsShown())
check("the footer gives your skill", GrindingUI.footer:GetText():find("Your Mining: 87") ~= nil,
    GrindingUI.footer:GetText())

local aimed
local grind0 = ns.Arrow.Grind
ns.Arrow.Grind = function(_, camp) aimed = camp return true end
local print0 = ns.Print
ns.Print = function() end
GrindingUI:OnRowClick(veinRow)
check("a click points the arrow at its spots", aimed and #aimed.mobs == 2 and aimed.mobs[1].coords[1] == 50)
ns.Arrow.Grind, ns.Print = grind0, print0

-- With more spots than the arrow takes, the ones nearest you go to it.
local many = { name = "Test Vein", zone = ZONE, spotList = {} }
for index = 1, GrindGather.MAX_SPOTS + 4 do
    many.spotList[index] = { index * 5, 10, map = 99901 }
end
many.spotList[#many.spotList + 1] = { 90, 90, map = 99901 }
local position0 = ns.Harvest.PlayerMapPosition
ns.Harvest.PlayerMapPosition = function() return 99901, 0.9, 0.88 end
local near = GrindGather.NodeCamp(many)
check("the arrow gets the spot beside you", near.mobs[1].coords[1] == 90 and #near.mobs == GrindGather.MAX_SPOTS,
    near.mobs[1].coords[1])
ns.Harvest.PlayerMapPosition = function() return nil end
check("without your position, the first ones", GrindGather.NodeCamp(many).mobs[1].coords[1] == 5)
ns.Harvest.PlayerMapPosition = position0

ns.db.grindColumns = { key = "count", ascending = false }
GrindingUI:Render()
check("the headings sort a zone's nodes", (function()
    for _, row in ipairs(GrindingUI.list.data) do
        if row.type == "node" and row.zone.zone == ZONE then return row.node.name == "Test Vein" end
    end
end)())
ns.db.grindColumns = nil

ns.HandleSlash("grind herbs")
check("/farm grind herbs", Grinding:Gives() == "herbs" and GrindingUI.headings.mob:GetText() == "HERB")

ns.HandleSlash("grind 14-26 leather")
check("/farm grind leather", Grinding:Gives() == "skinning" and GrindingUI.columns.layout == "leather")
check("the creature types are back", GrindingUI.typeChips[1]:IsShown())
local wolfRow
for _, row in ipairs(GrindingUI.list.data) do
    if row.type == "mob" and row.mob.name == "Vale Wolf" then wolfRow = row end
end
local texts = wolfRow and GrindingUI:MobTexts(wolfRow.mob)
check("a beast's row: its leather", texts and texts.gives == "Test Leather", texts and texts.gives)
check("its skill, short", texts and texts.skill == "110, you have 94" and texts.short)
check("a skin's worth and how many", texts and texts.worth ~= "" and texts.count == "2")
check("its headings", GrindingUI.headings.gives:GetText() == "LEATHER"
    and GrindingUI.headings.worth:GetText() == "PER SKIN")

ns.HandleSlash("grind any")
check("any goes back to mobs", GrindingUI.columns.layout == "mobs" and not GrindingUI.headings.skill:IsShown())
for _, row in ipairs(GrindingUI.list.data) do
    if row.type == "mob" then
        check("no Leather in what a mob gives while skinning is hidden: " .. row.mob.name,
            not GrindingUI.GivesText(row.mob):find("Leather"))
    end
end

suite.done()
