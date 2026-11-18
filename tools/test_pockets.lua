-- A rogue's picked pockets on the mob's card (2026-11-18).
--
-- What matters: each pocket counts once on its mob's card, with its coin
-- and items; it is never a kill and never in the drop rates; the card shows
-- a "Picked Pockets:" line after its drops, inside the card; the panel's
-- Clear empties it; and "Keep between sessions" keeps it.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("pockets")

local ns = env.Load({ ui = true })
local Harvest, Tracker, L = ns.Harvest, ns.Tracker, ns.L

Harvest:OnEnable()
Tracker:OnEnable()

local fire = ns.eventFrame:GetScript("OnEvent")
local clock = 100
_G.GetTime = function() return clock end

local units = {}
local baseName, baseDead, baseGUID, basePlayer = UnitName, UnitIsDead, UnitGUID, UnitIsPlayer
_G.UnitName = function(unit) if units[unit] then return units[unit].name end return baseName(unit) end
_G.UnitIsDead = function(unit) if units[unit] then return units[unit].dead == true end return baseDead(unit) end
_G.UnitGUID = function(unit) if units[unit] then return units[unit].guid end return baseGUID(unit) end
_G.UnitIsPlayer = function(unit) if units[unit] then return false end return basePlayer(unit) end

local MOB = "Hungering Dead"
local CAP = { name = "Forest Mushroom Cap", id = 4604 }
local CLOTH = { name = "Linen Cloth", id = 2589 }

local function Window(guid, items)
    env.world.loot = items
    _G.GetLootSourceInfo = function(slot) if items[slot] then return guid, 1 end end
end

local function Pick(guid, items, cast)
    clock = clock + 30
    units.target = { name = MOB, dead = false, guid = guid }
    fire(ns.eventFrame, "PLAYER_TARGET_CHANGED")
    fire(ns.eventFrame, "UNIT_SPELLCAST_SENT", "player", MOB, cast, 921)
    Window(guid, items)
    fire(ns.eventFrame, "LOOT_OPENED")
    fire(ns.eventFrame, "LOOT_CLOSED")
end

local GUID1 = "Creature-0-1-2-3-1525-0000AAAA"
local GUID2 = "Creature-0-1-2-3-1525-0000BBBB"
env.world.target = nil
Pick(GUID1, { CAP, { name = "9 Copper", money = true } }, "Cast-1")
Pick(GUID2, { { name = "6 Copper", money = true } }, "Cast-2")

local pockets = Tracker:PocketsOf(MOB)
suite.check("two pockets picked", pockets and pockets.picks == 2, pockets and pockets.picks)
suite.check("their coin", pockets and pockets.copper == 15, pockets and pockets.copper)
suite.check("the mushroom, once", pockets and #pockets.items == 1 and pockets.items[1].name == CAP.name
    and pockets.items[1].n == 1)
suite.check("no kill", (Tracker:Store()[MOB] or {}).kills == nil or Tracker:Store()[MOB].kills == 0)
suite.check("still in the Loot tab", Tracker.sessionLoot[CAP.name] == 1)
suite.check("another mob has none", Tracker:PocketsOf("Shambling Horror") == nil)

-- Then killed and looted: a kill with its own drop, the pocket kept apart.
clock = clock + 30
units.target.dead = true
Window(GUID1, { CLOTH })
fire(ns.eventFrame, "LOOT_OPENED")
fire(ns.eventFrame, "LOOT_CLOSED")
local tally = Tracker:Store()[MOB]
suite.check("the kill counts", tally and tally.kills == 1)
suite.check("the drops have no mushroom", tally and tally.items[CAP.name] == nil)
suite.check("the pockets are unchanged", Tracker:PocketsOf(MOB).picks == 2)

-- The card: drops, then the pocket line and its icons, in one card.
local UI = ns.TrackerUI

local lines = UI:Lines()
local drops, label, icons
for index, line in ipairs(lines) do
    if line.style == "value" and line.left == L["Picked Pockets:"] then
        label = index
    elseif line.style == "icons" and not label then
        drops = drops or index
    elseif line.style == "icons" and label and not icons then
        icons = index
    end
end
suite.check("the card has a Picked Pockets line", label ~= nil)
suite.check("after its drops", drops and label and drops < label, tostring(drops) .. " " .. tostring(label))
suite.check("which keep the card open past them", drops and lines[drops].more == true)
suite.check("it says picks and coin", label and lines[label].right:find("2 picks", 1, true) == 1,
    label and lines[label].right)
local icon = icons and lines[icons].icons[1]
suite.check("the mushroom as an icon", icon and icon.item == CAP.name and icon.text == "1")
suite.check("its hover says where from", icon and icon.about == "1 from 2 pockets picked",
    icon and icon.about)
suite.check("never a rate", icon and not icon.text:find("%%"))
suite.check("no loot table click", icon and icon.mob == nil)

local ok, err = pcall(function() UI:Refresh() end)
suite.check("the panel draws", ok, err)

-- Kept between sessions, and emptied by Clear.
local function Has(list, key) for _, v in ipairs(list) do if v == key then return true end end end
local fields = ns.Session.FIELDS.Tracker
suite.check("kept between sessions", Has(fields.counts, "sessionPockets")
    and Has(fields.counts, "sessionPocketCopper") and Has(fields.nested, "sessionPocketFrom"))
ns.Session:Clear()
suite.check("Clear empties it", Tracker:PocketsOf(MOB) == nil)

suite.done()
