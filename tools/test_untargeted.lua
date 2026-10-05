-- Kills looted without the corpse targeted, and loot read before fast loot
-- empties the window.
--
-- A player's report (2026-10-05): the Kills & Loot panel stayed empty while
-- goals kept up. The panel only counted a corpse that was your target, and
-- only on LOOT_OPENED. What matters: a corpse the loot window names by guid
-- counts when it is under the mouse or the interact key, or was seen alive;
-- an unknown guid still counts nothing (no guessing); and a window read on
-- LOOT_READY is not read again on LOOT_OPENED.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("untargeted")

local ns = env.Load({ ui = true })
local Tracker = ns.Tracker

ns.Harvest:OnEnable()
Tracker:OnEnable()

local fire = ns.eventFrame:GetScript("OnEvent")

-- The world beyond the target: units by token.
local units = {}
local baseName, baseDead, baseGUID, basePlayer = UnitName, UnitIsDead, UnitGUID, UnitIsPlayer
_G.UnitName = function(unit) if units[unit] then return units[unit].name end return baseName(unit) end
_G.UnitIsDead = function(unit) if units[unit] then return units[unit].dead == true end return baseDead(unit) end
_G.UnitGUID = function(unit) if units[unit] then return units[unit].guid end return baseGUID(unit) end
_G.UnitIsPlayer = function(unit) if units[unit] then return false end return basePlayer(unit) end

local WOLF = "Mangy Wolf"
local FANG = { name = "Large Fang", id = 5637 }

local function Window(guid, items)
    env.world.loot = items
    _G.GetLootSourceInfo = function(slot) if items[slot] then return guid, 1 end end
end

local function Kills(mob)
    local tally = Tracker:Store()[mob]
    return tally and tally.kills or 0
end

-- The target is a living mob you have moved on to; the corpse is elsewhere.
env.world.target = { name = "Young Wolf", level = 5, dead = false, guid = "Creature-0-1-2-3-50-Z" }

-- 1. A nameplate showed the wolf alive; later its corpse is looted untargeted.
units.nameplate1 = { name = WOLF, dead = false, guid = "Creature-0-1-2-3-50-A" }
fire(ns.eventFrame, "NAME_PLATE_UNIT_ADDED", "nameplate1")
units.nameplate1 = nil
Window("Creature-0-1-2-3-50-A", { FANG })
fire(ns.eventFrame, "LOOT_OPENED")
suite.check("a corpse seen alive counts untargeted", Kills(WOLF) == 1, Kills(WOLF))
suite.check("with its drop", Tracker:Store()[WOLF].items[FANG.name] == 1)
fire(ns.eventFrame, "LOOT_CLOSED")

-- 2. Right-clicked: the corpse is under the mouse, never seen before.
units.mouseover = { name = WOLF, dead = true, guid = "Creature-0-1-2-3-50-B" }
Window("Creature-0-1-2-3-50-B", { FANG })
fire(ns.eventFrame, "LOOT_OPENED")
suite.check("the corpse under the mouse counts", Kills(WOLF) == 2, Kills(WOLF))
fire(ns.eventFrame, "LOOT_CLOSED")
units.mouseover = nil

-- 3. A dead mob under the mouse that is not this window's source is not it.
units.mouseover = { name = "Kobold Vermin", dead = true, guid = "Creature-0-1-2-3-50-K" }
Window("Creature-0-1-2-3-50-C", { FANG })
fire(ns.eventFrame, "LOOT_OPENED")
suite.check("a corpse the window does not name is not counted",
    Tracker:Store()["Kobold Vermin"] == nil and Kills(WOLF) == 2)
fire(ns.eventFrame, "LOOT_CLOSED")
units.mouseover = nil

-- 4. Fast loot: read on LOOT_READY, the window gone by LOOT_OPENED.
units.softinteract = { name = WOLF, dead = true, guid = "Creature-0-1-2-3-50-D" }
Window("Creature-0-1-2-3-50-D", { FANG })
fire(ns.eventFrame, "LOOT_READY")
env.world.loot = {}
fire(ns.eventFrame, "LOOT_OPENED")
suite.check("read on LOOT_READY, once", Kills(WOLF) == 3, Kills(WOLF))
fire(ns.eventFrame, "LOOT_CLOSED")
units.softinteract = nil

-- 5. The harvester takes the same corpse.
suite.check("the harvest has the untargeted corpses too", ns.Harvest:CountCorpses() >= 3,
    ns.Harvest:CountCorpses())

_G.GetLootSourceInfo = nil
_G.UnitName, _G.UnitIsDead, _G.UnitGUID, _G.UnitIsPlayer = baseName, baseDead, baseGUID, basePlayer

suite.done()
