-- Which mobs to farm for an enchanting material (Logic/DisenchantFarm.lua),
-- for Tradeskills' Find a material view.
--
-- What matters: only your own loot records count, a mob only once
-- MIN_SAMPLE corpses are behind it; records of one mob in one zone add up;
-- each item is asked about once; the mob that gives the most a kill comes
-- first; hidden mobs and items are left out; a kill's pace is only the
-- mob's own; and nothing raises.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("disenchantfarm")
local check = suite.check

local ns = env.Load({})
local Farm, Harvest, Stats, DB = ns.DisenchantFarm, ns.Harvest, ns.Stats, ns.DB

check("the module is loaded", Farm ~= nil)
check("it is on the global", _G.BlackthornesFarmer.DisenchantFarm == Farm)

local BLUE, GREEN, CLOTH = 101, 102, 103

Harvest.records = {
    -- Two records of one mob in one zone: 30 corpses, 3 blues, 6 greens.
    ["Felpaw Ravager|Felwood|a"] = { mob = "Felpaw Ravager", zone = "Felwood", corpses = 20, items = {
        ["Ironfeather Shoulders"] = { name = "Ironfeather Shoulders", id = BLUE, count = 2, corpses = 2 },
        ["Cindercloth Boots"] = { name = "Cindercloth Boots", id = GREEN, count = 4, corpses = 4 },
        ["Runecloth"] = { name = "Runecloth", id = CLOTH, count = 30, corpses = 15 },
    } },
    ["Felpaw Ravager|Felwood|b"] = { mob = "Felpaw Ravager", zone = "Felwood", corpses = 10, items = {
        ["Ironfeather Shoulders"] = { name = "Ironfeather Shoulders", id = BLUE, count = 1, corpses = 1 },
        ["Cindercloth Boots"] = { name = "Cindercloth Boots", id = GREEN, count = 2, corpses = 2 },
    } },
    -- Lots of greens, no blues: 40 corpses, 20 greens.
    ["Deadwood Warrior|Felwood|"] = { mob = "Deadwood Warrior", zone = "Felwood", corpses = 40, items = {
        ["Cindercloth Boots"] = { name = "Cindercloth Boots", id = GREEN, count = 20, corpses = 20 },
    } },
    -- Too few corpses yet.
    ["Jadefire Rogue|Felwood|"] = { mob = "Jadefire Rogue", zone = "Felwood", corpses = 5, items = {
        ["Ironfeather Shoulders"] = { name = "Ironfeather Shoulders", id = BLUE, count = 5, corpses = 5 },
    } },
}

-- A blue gives one shard, a green one in twenty; cloth gives nothing.
local asked = {}
local function gives(id)
    asked[id] = (asked[id] or 0) + 1
    if id == BLUE then return 1 end
    if id == GREEN then return 0.05 end
    return 0
end

local list = Farm:Best(gives, 5)
check("two mobs have enough corpses and give some", #list == 2)
check("the ravager first", list[1] and list[1].mob == "Felpaw Ravager")
check("its records add up", list[1] and list[1].kills == 30)
-- (3 * 1 + 6 * 0.05) / 30 = 0.11
check("0.11 a kill", list[1] and math.abs(list[1].perKill - 0.11) < 1e-9)
check("with its zone", list[1] and list[1].zone == "Felwood")
check("its best item first", list[1] and list[1].items[1] and list[1].items[1].id == BLUE)
check("cloth is not listed", list[1] and #list[1].items == 2)
check("the warrior second", list[2] and list[2].mob == "Deadwood Warrior"
    and math.abs(list[2].perKill - 0.025) < 1e-9)
check("each item asked once", asked[BLUE] == 1 and asked[GREEN] == 1)
check("no pace of its own, no hour", list[1] and list[1].perHour == nil)
check("at most max", #Farm:Best(gives, 1) == 1)

-- The mob's own pace gives an hour: 36 s a kill, 100 kills an hour.
local stats = Stats:Store()
stats.pace["Felpaw Ravager"] = { kills = 30, seconds = 1080 }
list = Farm:Best(gives, 5)
check("an hour at the mob's own pace", list[1] and math.abs((list[1].perHour or 0) - 11) < 1e-6)

-- Hidden mobs and items are left out.
DB:Hide("source", "Felpaw Ravager")
list = Farm:Best(gives, 5)
check("a hidden mob is left out", list[1] and list[1].mob == "Deadwood Warrior")
DB:Unhide("source", "Felpaw Ravager")

-- Where an item dropped most.
check("dropped most by the warrior", Farm:DroppedBy(GREEN) == "Deadwood Warrior")
check("the blue by the jadefire rogue", Farm:DroppedBy(BLUE) == "Jadefire Rogue")
check("nothing for an item never seen", Farm:DroppedBy(999) == nil)

-- Nothing raises.
check("a gives that raises counts as none", #Farm:Best(function() error("boom") end) == 0)
check("no function, no list", #Farm:Best(nil) == 0)
check("no records, no list", (function()
    local kept = Harvest.records
    Harvest.records = nil
    local result = Farm:Best(gives)
    Harvest.records = kept
    return #result == 0
end)())
check("show a mob never killed is false", Farm:Show("Nobody") == false)

suite.done()
