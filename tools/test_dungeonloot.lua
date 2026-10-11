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

-- No link, but Classic knows the ID.
suite.check("Classic's dungeon names are shipped", ns.NPC_NAMES[11318] == "Ragefire Trogg")
local TROGG = "Creature-0-4621-389-76516-11318-000CCB0C4B"
Open({ { TROGG, 1 } }, { { name = "Heavy Shortbow", id = 3036 } })
suite.check("Classic's name stands in when the game gives none",
    Harvest.records["Ragefire Trogg|Ragefire Chasm|"] ~= nil)
suite.check("and is not kept as the game's", ns.db.npcNames[11318] == nil)

-- What was saved as "Creature #11318" before the names shipped.
Harvest.records["Creature #11318|Ragefire Chasm|"] = {
    mob = "Creature #11318", zone = "Ragefire Chasm", corpses = 3, npc = 11318,
    items = { ["Heavy Shortbow"] = { name = "Heavy Shortbow", id = 3036, corpses = 1, count = 1 },
              ["Feeble Shortbow"] = { name = "Feeble Shortbow", id = 2777, corpses = 1, count = 1 } },
}
ns.db.tracker = ns.db.tracker or {}
ns.db.tracker.mobs = ns.db.tracker.mobs or {}
ns.db.tracker.mobs["Creature #11318"] = { kills = 3, copper = 121, coinKills = 3,
    items = { ["Heavy Shortbow"] = 1 }, places = { ["Ragefire Chasm"] = 3 } }
ns.db.tracker.mobs["Ragefire Trogg"] = { kills = 1, copper = 10, coinKills = 1,
    items = { ["Heavy Shortbow"] = 1 }, places = { ["Ragefire Chasm"] = 1 } }

Harvest:NameUnnamed()
local trogg = Harvest.records["Ragefire Trogg|Ragefire Chasm|"]
suite.check("the old record takes its name", Harvest.records["Creature #11318|Ragefire Chasm|"] == nil)
suite.check("adding its corpses to the named one", trogg.corpses == 4, trogg.corpses)
suite.check("and its drops", trogg.items["Heavy Shortbow"].count == 2
    and trogg.items["Feeble Shortbow"].count == 1, trogg.items["Heavy Shortbow"].count)
local tally = ns.db.tracker.mobs["Ragefire Trogg"]
suite.check("the kill tally is named too", ns.db.tracker.mobs["Creature #11318"] == nil)
suite.check("with the kills added", tally.kills == 4 and tally.copper == 131, tally.kills)
suite.check("and the drops", tally.items["Heavy Shortbow"] == 2 and tally.places["Ragefire Chasm"] == 4)
suite.check("a mob still unnamed is left as it is",
    Harvest.records["Creature #99999|Ragefire Chasm|"] ~= nil)

-- A chest, or a window that names nobody, is still skipped.
local before = Harvest:CountCorpses()
Open({ { "GameObject-0-4621-389-76516-1234-0000CB0C4E", 1 } }, { { name = "Linen Cloth", id = 2589 } })
suite.check("a chest is not a corpse", Harvest:CountCorpses() == before, Harvest:CountCorpses())
Open({}, { { name = "Linen Cloth", id = 2589 } })
suite.check("nor a window naming nobody", Harvest:CountCorpses() == before, Harvest:CountCorpses())

suite.done()
