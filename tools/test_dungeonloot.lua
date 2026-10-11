-- Loot inside a dungeon (asked 2026-10-10, for every dungeon).
--
-- What matters: in a dungeon the corpse's name and guid are hidden, but the
-- loot window names its source by guid, so the drop is recorded under that
-- mob's ID and the name the game gives the ID; a name the game will not give
-- leaves "Creature #ID", kept but not exported; and a window naming no mob
-- is still skipped.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("dungeonloot")

local ns = env.Load()
local Harvest = ns.Harvest

suite.check("a creature guid gives its ID",
    Harvest.NpcID("Creature-0-4621-389-76516-11320-0000CB0C4B") == 11320)
suite.check("a pet's does not", Harvest.NpcID("Pet-0-4615-1-548-165189-0200360DE2") == nil)
suite.check("nor a secret value", Harvest.NpcID(env.Secret("string")) == nil)

-- The corpse targeted, its name and guid hidden.
_G.UnitName = function() return env.Secret("string") end
_G.UnitGUID = function() return env.Secret("string") end
_G.UnitIsDead = function() return true end
_G.GetRealZoneText = function() return "Ragefire Chasm" end
_G.GetSubZoneText = function() return "" end

local EARTHBORER = "Creature-0-4621-389-76516-11320-0000CB0C4B"
local function Open(sources, loot)
    env.world.loot = loot
    _G.GetLootSourceInfo = function(slot) return unpack(sources[slot] or {}) end
    ns.Harvest.opened = {}
    Harvest:RecordCorpse()
end

_G.C_TooltipInfo = { GetHyperlink = function(link)
    if link == "unit:" .. EARTHBORER then return { lines = { { leftText = "Earthborer" } } } end
    return nil
end }

Open({ { EARTHBORER, 1 } }, { { name = "Gelatinous Goo", id = 3669 } })
local record = Harvest.records["Earthborer|Ragefire Chasm|"]
suite.check("the corpse is recorded under the name its ID has", record ~= nil)
suite.check("one corpse", record and record.corpses == 1, record and record.corpses)
suite.check("with its drop", record and record.items["Gelatinous Goo"] ~= nil)
suite.check("and its ID", record and record.npc == 11320, record and record.npc)
suite.check("the name is kept for next time", ns.db.npcNames[11320] == "Earthborer")

-- Area loot: only the first mob's slots count against it.
local OTHER = "Creature-0-4621-389-76516-11321-0000CB0C4C"
ns.db.npcNames[11321] = "Rockbiter"
Open({ { EARTHBORER, 1 }, { OTHER, 2 } },
    { { name = "Gelatinous Goo", id = 3669 }, { name = "Linen Cloth", id = 2589, quantity = 2 } })
record = Harvest.records["Earthborer|Ragefire Chasm|"]
suite.check("a second corpse of it counts", record.corpses == 2, record.corpses)
suite.check("without the other mob's drop", record.items["Linen Cloth"] == nil)

-- The game will not name it.
_G.C_TooltipInfo = nil
local UNKNOWN = "Creature-0-4621-389-76516-99999-0000CB0C4D"
Open({ { UNKNOWN, 1 } }, { { name = "Gelatinous Goo", id = 3669 } })
local unnamed = Harvest.records["Creature #99999|Ragefire Chasm|"]
suite.check("an unnamed mob is still kept, by its ID", unnamed and unnamed.npc == 99999)
suite.check("and is not exported", not Harvest:ExportItem("Gelatinous Goo"):find("Creature #", 1, true))

-- A chest, or a window that names nobody, is still skipped.
local before = Harvest:CountCorpses()
Open({ { "GameObject-0-4621-389-76516-1234-0000CB0C4E", 1 } }, { { name = "Linen Cloth", id = 2589 } })
suite.check("a chest is not a corpse", Harvest:CountCorpses() == before, Harvest:CountCorpses())
Open({}, { { name = "Linen Cloth", id = 2589 } })
suite.check("nor a window naming nobody", Harvest:CountCorpses() == before, Harvest:CountCorpses())

suite.done()
