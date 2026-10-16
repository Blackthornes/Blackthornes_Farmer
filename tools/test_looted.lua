-- Has the player looted, gathered or fished an item themselves
-- (Logic/Looted.lua), for Tradeskills' Profit by method ("Farmed").
--
-- What matters: only the player's own loot, gathering and fishing records
-- count, never the guild's; an item ID or a name finds it; the lookup is
-- built again once something new is recorded (and GAP has passed); and
-- nothing raises.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("looted")
local check = suite.check

local ns = env.Load()
local Looted = ns.Looted

check("the module is loaded", Looted ~= nil)
check("it is on the global", _G.BlackthornesFarmer.Looted == Looted)

local clock = 1000
local oldGetTime = _G.GetTime
_G.GetTime = function() return clock end
local oldItem = _G.C_Item
_G.C_Item = { GetItemNameByID = function(id)
    if id == 4306 then return "Silk Cloth" end
    if id == 2770 then return "Copper Ore" end
end }

ns.Harvest.records["Vale Bandit|Westfall|"] = {
    mob = "Vale Bandit", zone = "Westfall", corpses = 20,
    items = { ["Silk Cloth"] = { corpses = 10, count = 12 },
              ["Lead Band"] = { corpses = 1, count = 1, id = 4998 } },
}
ns.db.gathering = { nodes = { ["Westfall||Copper Vein"] = {
    zone = "Westfall", node = "Copper Vein", kind = "ore", gathers = 4,
    items = { ["Copper Ore"] = { gathers = 4, count = 8 } },
} } }
ns.db.fishing = { spots = { ["Westfall||"] = {
    zone = "Westfall", casts = 5, items = { ["Raw Brilliant Smallfish"] = { casts = 5, count = 5 } },
} } }
ns.db.guildDrops = { ["Guild Mob|Westfall|"] = { mob = "Guild Mob", zone = "Westfall", corpses = 30,
    items = { ["Guild Thing"] = { corpses = 30, count = 30, id = 9999 } } } }
ns.Harvest.changes = (ns.Harvest.changes or 0) + 1
Looted:Forget()

check("a drop, by item ID", Looted:Has(4306))
check("a drop's own ID", Looted:Has(4998))
check("a gathered ore, by ID", Looted:Has(2770))
check("a fished one, by name", Looted:Has("Raw Brilliant Smallfish"))
check("any case", Looted:Has("silk cloth"))
check("never the guild's", not Looted:Has(9999) and not Looted:Has("Guild Thing"))
check("something never looted", not Looted:Has(12345) and not Looted:Has("Arcanite Bar"))

-- Kept until a new record comes in and GAP has passed.
ns.Harvest.records["Vale Bandit|Westfall|"].items["Wool Cloth"] = { corpses = 1, count = 1, id = 2592 }
check("kept between questions", not Looted:Has(2592))
ns.Harvest.changes = ns.Harvest.changes + 1
check("not before the gap", not Looted:Has(2592))
clock = clock + Looted.GAP + 1
check("built again after a new record", Looted:Has(2592))

-- Never raises.
local records = ns.Harvest.records
ns.Harvest.records = { broken = { items = { ["X"] = "nonsense" } } }
Looted:Forget()
local ok, answer = pcall(Looted.Has, Looted, "X")
check("odd records do not raise", ok)
check("nonsense asks get false", Looted:Has(nil) == false and Looted:Has({}) == false)
ns.Harvest.records = records
ns.db.guildDrops = nil

_G.GetTime, _G.C_Item = oldGetTime, oldItem
suite.done()
