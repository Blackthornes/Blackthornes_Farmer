-- The loot harvester: what it records, what it refuses to record, and the
-- data file it hands back.
--
-- The refusals matter as much as the recording. A rate measured off the wrong
-- mob, or off six corpses, would go into the repository looking exactly like a
-- real one, so the cases that must produce nothing are tested first.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("harvest")

local ns = env.Load({ ui = true })
local Harvest = ns.Harvest

-- The real carryover would fold 84 corpses into every Restore below. It gets
-- its own section at the end; everything before it runs without.
local SHIPPED_CARRYOVER = ns.HarvestCarryover
ns.HarvestCarryover = nil

local APPRENTICE = { name = "Dalaran Apprentice", level = 22, dead = true }
local WOOL = { name = "Wool Cloth", quantity = 1, id = 2592 }
local SILVER = { name = "Silver Bar", quantity = 1 }

--- Loot `count` corpses of `mob`, `withItems` of them holding `items`.
local function Farm(mob, count, withItems, items)
    for index = 1, count do
        env.Loot(ns, mob, index <= withItems and items or {})
    end
end

--------------------------------------------------------------------------------
-- Capabilities
--------------------------------------------------------------------------------

local caps = Harvest:Capabilities()
suite.check("the stub client looks usable", caps.usable == true)
suite.check("it sees the map API", caps.bestMap and caps.playerPos)

--------------------------------------------------------------------------------
-- Recording
--------------------------------------------------------------------------------

Harvest:Reset()
Farm(APPRENTICE, 4, 3, { WOOL })

suite.check("every corpse counts", Harvest:CountCorpses() == 4, Harvest:CountCorpses())
suite.check("one mob is one record", Harvest:CountMobs() == 1, Harvest:CountMobs())

local rows = Harvest:ForItem("Wool Cloth")
suite.check("the item was seen", #rows == 1, #rows)
suite.check("only the corpses that held it count",
    rows[1] and rows[1].entry.corpses == 3, rows[1] and rows[1].entry.corpses)
suite.check("the rate is holders over corpses",
    rows[1] and rows[1].chance == 75, rows[1] and rows[1].chance)

local record = rows[1].record
suite.check("the zone came from the client",
    record.zone == "Silverpine Forest", record.zone)
suite.check("the subzone became the location",
    record.location == "The Sepulcher", record.location)
suite.check("the level came from the corpse", record.minLevel == 22, record.minLevel)
suite.check("coordinates are map percentages",
    record.coords and math.abs(record.coords[1] - 45) < 0.01
        and math.abs(record.coords[2] - 68) < 0.01,
    record.coords and table.concat(record.coords, ","))

suite.check("the item id came off the loot link",
    rows[1].entry.id == 2592, rows[1].entry.id)

-- Two of the same item in one corpse is one corpse that held it.
Harvest:Reset()
env.Loot(ns, APPRENTICE, { WOOL, WOOL })

local doubled = Harvest:ForItem("Wool Cloth")[1]
suite.check("two stacks in one corpse is one corpse",
    doubled.entry.corpses == 1, doubled.entry.corpses)
suite.check("but both stacks are counted", doubled.entry.count == 2, doubled.entry.count)

--------------------------------------------------------------------------------
-- What it refuses to record
--------------------------------------------------------------------------------

Harvest:Reset()
env.world.fishing = true
env.Loot(ns, APPRENTICE, { WOOL })
env.world.fishing = false
suite.check("a fishing pool is not a mob", Harvest:CountCorpses() == 0)

Harvest:Reset()
env.Loot(ns, { name = "Blackthornes", level = 25, dead = true, isPlayer = true }, { WOOL })
suite.check("a player corpse is not a farming spot", Harvest:CountCorpses() == 0)

Harvest:Reset()
env.Loot(ns, { name = "Dalaran Apprentice", level = 22, dead = false }, { WOOL })
suite.check("a living target means the corpse is unknown",
    Harvest:CountCorpses() == 0)

Harvest:Reset()
env.world.target = nil
env.Loot(ns, nil, { WOOL })
suite.check("no target means no sample", Harvest:CountCorpses() == 0)
suite.check("a dropped sample is counted as skipped", Harvest.skipped and Harvest.skipped > 0)

-- Two mobs of the same name in different zones are different spots.
Harvest:Reset()
env.world.zone = "Silverpine Forest"
env.Loot(ns, APPRENTICE, { WOOL })
env.world.zone = "Hillsbrad Foothills"
env.Loot(ns, APPRENTICE, { WOOL })
suite.check("the same mob in two zones is two records",
    Harvest:CountMobs() == 2, Harvest:CountMobs())
env.world.zone = "Silverpine Forest"

--------------------------------------------------------------------------------
-- Values the client will not let us read
--------------------------------------------------------------------------------
--
-- Ragefire Chasm, 2026-09-22: "Harvest.lua:112: attempt to compare local
-- 'name' (a secret string value, while execution tainted by
-- 'Blackthornes_Farmer')", twice over one run. The call to UnitName succeeded
-- and comparing what it handed back is what raised, so the pcall around the
-- call was never going to catch it.
--
-- env.Secret stands in for such a value: it raises on the operations a secret
-- value raises on. Every check below would have errored rather than merely
-- failed before Readable existed.

local SECRET_MOB = { name = env.Secret("string"), level = 15, dead = true }

Harvest:Reset()
env.Loot(ns, SECRET_MOB, { WOOL })

suite.check("a corpse whose name cannot be read is skipped, not recorded",
    Harvest:CountCorpses() == 0, Harvest:CountCorpses())
suite.check("and counted as a dropped sample",
    Harvest.skipped and Harvest.skipped > 0, Harvest.skipped)

-- A level is worth less than a name: without it the spot still tells you where
-- to go, so the corpse is kept and the band left empty rather than guessed.
Harvest:Reset()
env.Loot(ns, { name = "Ragefire Trogg", level = env.Secret("number"), dead = true },
    { WOOL })

local trogg = Harvest:ForItem("Wool Cloth")[1]
suite.check("a corpse whose level cannot be read is still recorded",
    Harvest:CountCorpses() == 1, Harvest:CountCorpses())
suite.check("with no level band rather than a wrong one",
    trogg and trogg.record.minLevel == nil, trogg and trogg.record.minLevel)

-- One unreadable slot must not cost the whole loot window.
Harvest:Reset()
env.Loot(ns, APPRENTICE, { { name = env.Secret("string"), quantity = 1 }, WOOL })

suite.check("an unreadable loot slot loses only that slot",
    #Harvest:Items() == 1 and Harvest:Items()[1].name == "Wool Cloth",
    Harvest:Items()[1] and Harvest:Items()[1].name)
suite.check("and the corpse around it still counts",
    Harvest:CountCorpses() == 1, Harvest:CountCorpses())

Harvest:Reset()
env.Loot(ns, APPRENTICE,
    { { name = "Wool Cloth", quantity = env.Secret("number"), id = 2592 } })

local unread = Harvest:ForItem("Wool Cloth")[1]
suite.check("an unreadable quantity counts as the one it must be",
    unread and unread.entry.count == 1, unread and unread.entry.count)

-- A zone that cannot be read leaves the spot unplaced rather than erroring.
Harvest:Reset()
local realZone, realSub = env.world.zone, env.world.subZone
env.world.zone = env.Secret("string")
env.world.subZone = env.Secret("string")
env.Loot(ns, APPRENTICE, { WOOL })
env.world.zone, env.world.subZone = realZone, realSub

local unplaced = Harvest:ForItem("Wool Cloth")[1]
suite.check("an unreadable zone does not take the sample with it",
    Harvest:CountCorpses() == 1, Harvest:CountCorpses())
suite.check("the spot is left unplaced instead",
    unplaced and unplaced.record.zone == nil, unplaced and unplaced.record.zone)
suite.check("and what it exports is still loadable Lua",
    loadstring(Harvest:ExportAll()) ~= nil)

-- Through the event the client actually fires, which is where Trent saw it:
-- the dispatcher pcalls each handler and hands what it catches to
-- geterrorhandler, which in this harness re-raises. So a raise anywhere under
-- LOOT_OPENED comes back out here as a failed pcall.
Harvest:Reset()
Harvest:OnEnable()

local dispatch = ns.eventFrame:GetScript("OnEvent")
env.world.target = SECRET_MOB
env.world.loot = { WOOL }

local delivered = pcall(dispatch, ns.eventFrame, "LOOT_OPENED")

env.world.target = APPRENTICE
suite.check("looting such a corpse raises nothing at all", delivered == true)

--------------------------------------------------------------------------------
-- Export
--------------------------------------------------------------------------------

Harvest:Reset()
Farm(APPRENTICE, 40, 30, { WOOL, SILVER })

local block = Harvest:ExportItem("Wool Cloth")
suite.check("the export registers the item",
    block:find('name = "Wool Cloth"', 1, true) ~= nil, block)
suite.check("it carries the item id", block:find("id = 2592", 1, true) ~= nil, block)
suite.check("it names the mob",
    block:find('name = "Dalaran Apprentice"', 1, true) ~= nil, block)
suite.check("it carries the measured rate",
    block:find("chance = 75", 1, true) ~= nil, block)
suite.check("a measured row is marked as Forever",
    block:find('provenance = "forever"', 1, true) ~= nil, block)
suite.check("it says how big the sample was",
    block:find("30 of 40 corpses", 1, true) ~= nil, block)

-- A rate off a handful of corpses is a number pretending to be evidence.
Harvest:Reset()
Farm(APPRENTICE, 6, 3, { WOOL })

local thin = Harvest:ExportItem("Wool Cloth")
suite.check("a thin sample publishes no rate",
    thin:find("chance =", 1, true) == nil, thin)
suite.check("and says why", thin:find("too few for a rate", 1, true) ~= nil, thin)

suite.check("nothing harvested for an item exports nothing",
    Harvest:ExportItem("Mithril Ore") == nil)

local all = Harvest:ExportAll()
suite.check("the whole export is a loadable chunk",
    loadstring(all) ~= nil or load(all) ~= nil)
suite.check("it explains where to put it",
    all:find("Data/", 1, true) ~= nil, all)

Harvest:Reset()
suite.check("an empty export still says something",
    Harvest:ExportAll():find("Nothing harvested", 1, true) ~= nil)

--------------------------------------------------------------------------------
-- Naming an item
--------------------------------------------------------------------------------

Harvest:Reset()
Farm(APPRENTICE, 2, 2, { WOOL, SILVER })

suite.check("an exact name resolves",
    Harvest:ResolveItem("Wool Cloth") == "Wool Cloth")
suite.check("case does not matter",
    Harvest:ResolveItem("wool cloth") == "Wool Cloth")
suite.check("a prefix resolves", Harvest:ResolveItem("wool") == "Wool Cloth")
suite.check("a word from the middle resolves",
    Harvest:ResolveItem("cloth") == "Wool Cloth")
suite.check("a prefix beats a mid-word match",
    Harvest:ResolveItem("silver") == "Silver Bar")
suite.check("nothing matching resolves to nothing",
    Harvest:ResolveItem("mithril") == nil)
suite.check("an empty name resolves to nothing", Harvest:ResolveItem("") == nil)

--------------------------------------------------------------------------------
-- Commands and the export window
--------------------------------------------------------------------------------

local UI = ns.UI

UI:ShowExport("hello\nworld", "Export -- test")
suite.check("the export window opens", UI.exportFrame:IsShown() == true)
suite.check("it holds the text", UI.exportEdit:GetText() == "hello\nworld",
    UI.exportEdit:GetText())
suite.check("it is titled", UI.exportTitle:GetText() == "Export -- test",
    UI.exportTitle:GetText())
suite.check("it counts what is in it",
    UI.exportCount:GetText():find("2 lines", 1, true) ~= nil,
    UI.exportCount:GetText())

UI:HideExport()
suite.check("and closes", UI.exportFrame:IsShown() == false)

ns.HandleSlash("export wool")
suite.check("/farm export <item> opens the window", UI.exportFrame:IsShown() == true)
suite.check("with only that item",
    UI.exportEdit:GetText():find("Silver Bar", 1, true) == nil,
    UI.exportEdit:GetText())
UI:HideExport()

ns.HandleSlash("export mithril")
suite.check("/farm export for something unharvested says so, and opens nothing",
    UI.exportFrame:IsShown() == false)

ns.HandleSlash("export")
suite.check("/farm export with no item exports everything",
    UI.exportEdit:GetText():find("Silver Bar", 1, true) ~= nil,
    UI.exportEdit:GetText())
UI:HideExport()

ns.HandleSlash("harvest")
suite.check("/farm harvest reports the corpses",
    #env.chat > 0 and table.concat(env.chat, "\n"):find("2 corpses", 1, true) ~= nil,
    table.concat(env.chat, "\n"))

ns.HandleSlash("harvest off")
env.Loot(ns, APPRENTICE, { WOOL })
suite.check("harvesting off records nothing", Harvest:CountCorpses() == 2,
    Harvest:CountCorpses())

ns.HandleSlash("harvest on")
env.Loot(ns, APPRENTICE, { WOOL })
suite.check("harvesting on records again", Harvest:CountCorpses() == 3,
    Harvest:CountCorpses())

-- The harvest is the whole history now, so one word must not wipe it.
env.chat = {}
ns.HandleSlash("harvest reset")
suite.check("a bare reset keeps everything", Harvest:CountCorpses() == 3,
    Harvest:CountCorpses())
suite.check("and says how to confirm it",
    table.concat(env.chat, "\n"):find("reset confirm", 1, true) ~= nil,
    table.concat(env.chat, "\n"))

ns.HandleSlash("harvest reset confirm")
suite.check("reset confirm empties it", Harvest:CountCorpses() == 0)

--------------------------------------------------------------------------------
-- Coins are not drops
--------------------------------------------------------------------------------
--
-- Money shares the loot window with the items, so the first real harvest came
-- back with "12 Copper" and "3 Silver 40 Copper" registered as things that
-- drop off Razormane Defenders. Twenty-five of the fifty-three entries were
-- coins. They have to be filtered on the way in, and pruned out of data an
-- older version already wrote.

local COINS = { name = "14 Copper", quantity = 1, money = true }
local MIXED = { name = "3 Silver 40 Copper", quantity = 1, money = true }

Harvest:Reset()
env.Loot(ns, APPRENTICE, { COINS, WOOL, MIXED })

suite.check("the corpse still counts", Harvest:CountCorpses() == 1,
    Harvest:CountCorpses())
suite.check("the item on it is kept",
    Harvest:ForItem("Wool Cloth") and #Harvest:ForItem("Wool Cloth") == 1)
suite.check("the coins beside it are not",
    #Harvest:Items() == 1, #Harvest:Items())

-- Now with the slot-type API missing, which is the case the name heuristic
-- exists for: nobody knows yet whether this client has GetLootSlotType.
local realSlotType = _G.GetLootSlotType
_G.GetLootSlotType = nil

Harvest:Reset()
env.Loot(ns, APPRENTICE, { COINS, WOOL, MIXED })

suite.check("coins are caught by name when the slot API is missing",
    #Harvest:Items() == 1, #Harvest:Items())

-- The heuristic must not be greedy. Silver Bar is a real item whose name
-- starts with a coin word, and an earlier attempt at this deleted it.
Harvest:Reset()
env.Loot(ns, APPRENTICE, { SILVER, COINS })

suite.check("an item named after a coin survives",
    #Harvest:Items() == 1 and Harvest:Items()[1].name == "Silver Bar",
    Harvest:Items()[1] and Harvest:Items()[1].name)

_G.GetLootSlotType = realSlotType

suite.check("a bare number is not money", Harvest:NameLooksLikeMoney("14") == false)
suite.check("a bare word is not money",
    Harvest:NameLooksLikeMoney("Copper") == false)
suite.check("an ore is not money",
    Harvest:NameLooksLikeMoney("14 Pound Salmon") == false)
suite.check("coins are money", Harvest:NameLooksLikeMoney("14 Copper") == true)
suite.check("mixed coins are money",
    Harvest:NameLooksLikeMoney("3 Silver 40 Copper") == true)
suite.check("all three denominations are money",
    Harvest:NameLooksLikeMoney("1 Gold 2 Silver 3 Copper") == true)
suite.check("nothing is not money", Harvest:NameLooksLikeMoney(nil) == false)

-- Restoring data an older version wrote drops the coins it recorded, so the
-- bad entries disappear on the next login rather than living forever.
Harvest:Reset()
ns.db.harvest = {
    ["Dalaran Apprentice|Silverpine Forest|"] = {
        mob = "Dalaran Apprentice", zone = "Silverpine Forest", corpses = 9,
        items = {
            ["Wool Cloth"] = { name = "Wool Cloth", count = 4, corpses = 4, id = 2592 },
            ["14 Copper"] = { name = "14 Copper", count = 2, corpses = 2 },
        },
    },
}

suite.check("restoring old data brings the spot back",
    Harvest:Restore() == 1, Harvest:Restore())
suite.check("with its corpses", Harvest:CountCorpses() == 9,
    Harvest:CountCorpses())
suite.check("and the coins pruned out of it",
    #Harvest:Items() == 1 and Harvest:Items()[1].name == "Wool Cloth",
    Harvest:Items()[1] and Harvest:Items()[1].name)

--------------------------------------------------------------------------------
-- The harvest carries from one session to the next
--------------------------------------------------------------------------------
--
-- Since the Forever patch of 2026-09-24 the client reads saved variables back
-- at login. So the saved harvest is the whole history, and every session adds
-- to it rather than standing in for it.

--- Log out and back in: a fresh copy of the addon, handed what the last one
--- saved, exactly as the client does it.
local function Relog(saved, carryover)
    local fresh = env.Load()
    fresh.HarvestCarryover = carryover
    _G.BlackthornesFarmerDB = saved
    fresh.LoadSavedVariables()
    fresh.Harvest:Restore()
    return fresh
end

Harvest:Reset()
Harvest:Restore()
Farm(APPRENTICE, 3, 2, { WOOL })

suite.check("the saved harvest is the live one",
    ns.db.harvest == Harvest.records)
suite.check("so a corpse is in the save the moment it is looted, logout or not",
    Harvest:CountCorpses() == 3)

local second = Relog(ns.db)
suite.check("the next login starts with everything from the last",
    second.Harvest:CountCorpses() == 3, second.Harvest:CountCorpses())

env.Loot(second, APPRENTICE, { WOOL })
env.Loot(second, APPRENTICE, {})

local wool = second.Harvest:ForItem("Wool Cloth")[1]
suite.check("and adds to it rather than replacing it",
    second.Harvest:CountCorpses() == 5, second.Harvest:CountCorpses())
suite.check("item counts add up across sessions",
    wool and wool.entry.corpses == 3, wool and wool.entry.corpses)

local third = Relog(second.db)
suite.check("a login that loots nothing keeps it all",
    third.Harvest:CountCorpses() == 5, third.Harvest:CountCorpses())

-- The field the old import used to spot a client that reads its saved data
-- back. That question is answered, and nothing reads it.
second.db.harvestRestored = 0
local fourth = Relog(second.db)
suite.check("the old harvestRestored stamp is cleared",
    fourth.db.harvestRestored == nil, fourth.db.harvestRestored)

-- A reset is the whole history now, and it has to reach the save.
fourth.Harvest:Reset()
suite.check("a reset empties the save too",
    next(fourth.db.harvest) == nil and fourth.db.harvest == fourth.Harvest.records)

--------------------------------------------------------------------------------
-- The harvest from before the fix comes in once
--------------------------------------------------------------------------------
--
-- Everything gathered while the client could not read saved variables back
-- lived in the repository, not in the save. The first login after the fix
-- adds it; no login after that may add it again.

local CARRY = {
    id = "test-carry",
    records = {
        ["Dalaran Apprentice|Silverpine Forest|The Sepulcher"] = {
            mob = "Dalaran Apprentice", zone = "Silverpine Forest",
            location = "The Sepulcher", minLevel = 20, maxLevel = 21,
            coords = { 44.0, 67.0 }, corpses = 10,
            items = { ["Wool Cloth"] = { name = "Wool Cloth", count = 6, corpses = 5, id = 2592 } },
        },
        ["Moonrage Whitescalp|Silverpine Forest|"] = {
            mob = "Moonrage Whitescalp", zone = "Silverpine Forest",
            minLevel = 18, maxLevel = 19, corpses = 4,
            items = { ["Wolf Meat"] = { name = "Wolf Meat", count = 3, corpses = 3 } },
        },
    },
}

local before = {
    harvest = {
        ["Dalaran Apprentice|Silverpine Forest|The Sepulcher"] = {
            mob = "Dalaran Apprentice", zone = "Silverpine Forest",
            location = "The Sepulcher", minLevel = 22, maxLevel = 22,
            coords = { 45.0, 68.0 }, corpses = 2,
            items = { ["Wool Cloth"] = { name = "Wool Cloth", count = 1, corpses = 1 } },
        },
    },
}

local first = Relog(before, CARRY)
local sepulcher = first.Harvest.records["Dalaran Apprentice|Silverpine Forest|The Sepulcher"]

suite.check("the first login after the fix adds the carryover",
    first.Harvest:CountCorpses() == 16, first.Harvest:CountCorpses())
suite.check("and says so", first.Harvest.carriedOver == 14, first.Harvest.carriedOver)
suite.check("a shared spot adds up",
    sepulcher.corpses == 12 and sepulcher.items["Wool Cloth"].corpses == 6,
    sepulcher.corpses)
suite.check("its level band covers both",
    sepulcher.minLevel == 20 and sepulcher.maxLevel == 22,
    sepulcher.minLevel .. "-" .. sepulcher.maxLevel)
suite.check("it keeps the coordinates it already had",
    sepulcher.coords[1] == 45.0, sepulcher.coords[1])
suite.check("an item id arrives with the carryover",
    sepulcher.items["Wool Cloth"].id == 2592, sepulcher.items["Wool Cloth"].id)
suite.check("a new spot arrives whole",
    first.Harvest.records["Moonrage Whitescalp|Silverpine Forest|"].corpses == 4)
suite.check("the save is stamped with it",
    first.db.harvestCarryover == "test-carry", first.db.harvestCarryover)
suite.check("the carryover itself is left as shipped",
    CARRY.records["Dalaran Apprentice|Silverpine Forest|The Sepulcher"].corpses == 10
        and CARRY.records["Moonrage Whitescalp|Silverpine Forest|"].items["Wolf Meat"].corpses == 3)

local again = Relog(first.db, CARRY)
suite.check("THE NEXT LOGIN DOES NOT ADD IT AGAIN",
    again.Harvest:CountCorpses() == 16, again.Harvest:CountCorpses())
suite.check("and says nothing about it", (again.Harvest.carriedOver or 0) == 0)

-- If the client ever loses the save again, the stamp goes with it and the
-- carryover comes back into an empty harvest: the history, not twice it.
local lost = Relog(nil, CARRY)
suite.check("a lost save gets the carryover back",
    lost.Harvest:CountCorpses() == 14, lost.Harvest:CountCorpses())

-- The file that actually ships: everything imported before the fix.
local shipped = Relog(nil, SHIPPED_CARRYOVER)
suite.check("the shipped carryover loads",
    SHIPPED_CARRYOVER ~= nil and shipped.Harvest:CountCorpses() == 84,
    shipped.Harvest:CountCorpses())
suite.check("across all 22 spots", shipped.Harvest:CountMobs() == 22,
    shipped.Harvest:CountMobs())

local coins = 0
for _, item in ipairs(shipped.Harvest:Items()) do
    if shipped.Harvest:NameLooksLikeMoney(item.name) then coins = coins + 1 end
end
suite.check("with no coins in it", coins == 0, coins)

suite.done()
