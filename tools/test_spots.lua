-- The best places near you to farm a goal (Trent, 2026-09-27): the Where?
-- button on each goal card, and /farm where.
--
-- What matters: "near" is zones crossed from where you stand, with the other
-- continent far away; a spot above your level drops down the list; your own
-- kills and gathers count for more than Classic data; nothing breaks when
-- the client will not say where you are; and a click prints the place, and
-- pins it on the map only when it is in the zone you are in.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("spots")

local ns = env.Load({ ui = true })
local Spots = ns.Spots
local GUI = ns.GoalsUI

_G.GetTime = function() return 5000 end
_G.C_Item = { GetItemCount = function() return 0 end }

--------------------------------------------------------------------------------
-- The map
--------------------------------------------------------------------------------

suite.check("same zone", Spots.Hops("Westfall", "Westfall") == 0)
suite.check("next door", Spots.Hops("Elwynn Forest", "Westfall") == 1)
suite.check("two over", Spots.Hops("Westfall", "Redridge Mountains") == 2, Spots.Hops("Westfall", "Redridge Mountains"))
suite.check("other continent is far", Spots.Hops("Elwynn Forest", "Durotar") >= 8)
suite.check("a dungeon counts as its zone", Spots.Hops("Tanaris", "Zul'Farrak") == 0)
suite.check("a capital counts as its zone", Spots.Hops("Orgrimmar", "The Barrens") == 1)
suite.check("unknown place, no answer", Spots.Hops("Westfall", "Somewhere Odd") == nil)
suite.check("'any coastline' is no one zone", Spots.ZoneOf("any coastline") == nil)

-- Every border goes both ways, so the ranking does not depend on direction.
local oneWay = {}
for zone, near in pairs(Spots.BORDERS) do
    for _, other in ipairs(near) do
        local back = false
        for _, z in ipairs(Spots.BORDERS[other] or {}) do if z == zone then back = true end end
        if not back then oneWay[#oneWay + 1] = zone .. " -> " .. other end
    end
end
suite.check("borders are two-way", #oneWay == 0, table.concat(oneWay, "; "))

-- Every zone the data names is on the map, or is a dungeon, capital or "any".
local missing = {}
for item in ns.DB:Iterate() do
    for _, source in ipairs(item.sources) do
        local zone = Spots.ZoneOf(source.zone)
        if zone and not Spots.BORDERS[zone] then missing[zone] = true end
    end
end
local names = {}
for zone in pairs(missing) do names[#names + 1] = zone end
suite.check("every data zone is placed", #names == 0, table.concat(names, ", "))

--------------------------------------------------------------------------------
-- Ranking
--------------------------------------------------------------------------------

local spots = Spots:For("Copper Ore", { zone = "Westfall", level = 12 })
suite.check("where you stand comes first", spots[1] and spots[1].zone == "Westfall", spots[1] and spots[1].zone)
suite.check("then next door", spots[2] and spots[2].hops == 1, spots[2] and spots[2].zone)
suite.check("no more than the most shown", #spots <= Spots.MAX)

spots = Spots:For("Copper Ore", { zone = "Durotar", level = 5 })
suite.check("from Durotar, Durotar", spots[1].zone == "Durotar")
suite.check("and Kalimdor before the other continent", Spots.Continent(spots[2].zone) == "Kalimdor", spots[2].zone)

-- Too high a level drops a nearby spot below a safer one further off.
local near = { name = "Near", zone = "Westfall", minLevel = 40, maxLevel = 45 }
local safe = { name = "Safe", zone = "Duskwood", minLevel = 10, maxLevel = 20 }
local player = { zone = "Elwynn Forest", level = 12 }
Spots:Score(near, player)
Spots:Score(safe, player)
suite.check("far above your level ranks lower", safe.score < near.score, safe.score .. " vs " .. near.score)
suite.check("marked as dangerous", near.danger == 28, near.danger)

-- Unreadable zone: still ranked, by level and rate.
spots = Spots:For("Copper Ore", { zone = nil, level = 12 })
suite.check("no zone, still an answer", #spots > 0)

-- Your own record: a node you mined in Loch Modan beats Classic data there.
ns.Gathering:Record("Loch Modan", "Stonesplinter Valley", "Copper Vein", "node",
    { "Copper Ore" }, { ["Copper Ore"] = 3 }, { 35.5, 60.1 })
spots = Spots:For("Copper Ore", { zone = "Loch Modan", level = 12 })
local mine
for _, spot in ipairs(spots) do if spot.yours then mine = spot end end
suite.check("your gathers are in the list", mine ~= nil)
suite.check("merged with nothing false", mine and mine.yours.got == 3, mine and mine.yours and mine.yours.got)
suite.check("and first", spots[1] == mine, spots[1] and spots[1].name)
suite.check("its note says so", GUI.SpotNote(mine):find("you gathered 3 here") ~= nil)

--------------------------------------------------------------------------------
-- The panel and the button
--------------------------------------------------------------------------------

env.world.zone = "Loch Modan"
_G.UnitLevel = function() return 12 end

local placed
_G.UiMapPoint = { CreateFromCoordinates = function(map, x, y) return { map = map, x = x, y = y } end }
_G.C_Map.SetUserWaypoint = function(point) placed = point end

ns.HandleSlash("goal Copper Ore 40")
GUI:Refresh()
local card = GUI.cards[1]
suite.check("the card has a Where button", card.where and card.where:IsShown())
suite.check("the line under the name is the nearest place", card.sub:GetText():find("here") ~= nil, card.sub:GetText())

card.where:GetScript("OnClick")(card.where, "LeftButton")
local panel = GUI.spots
suite.check("the panel opens", panel and panel:IsShown())
suite.check("titled for the item", panel.title:GetText():find("Copper Ore") ~= nil)
suite.check("says where from", panel.from:GetText():find("Loch Modan") ~= nil, panel.from:GetText())
suite.check("rows drawn", panel.rows[1]:IsShown() and panel.rows[1].rank:GetText() == "1")
suite.check("first row is yours", panel.rows[1].spot == Spots:For("Copper Ore")[1] or panel.rows[1].spot.yours ~= nil)

for _ = 1, 30 do GUI:Step(0.1) end

env.chat = {}
panel.rows[1]:GetScript("OnClick")(panel.rows[1])
suite.check("clicking prints it", env.chat[1] and env.chat[1]:find("Copper Vein") ~= nil, env.chat[1])
suite.check("and pins it here", placed and math.abs(placed.x - 0.355) < 0.001, placed and placed.x)
suite.check("says it is pinned", env.chat[1]:find("pinned") ~= nil)

-- A place in another zone is printed, not pinned.
placed = nil
local far = { name = "Copper Vein", zone = "Westfall", coords = { 50, 50 }, hops = 3 }
Spots:Share("Copper Ore", far)
suite.check("another zone is not pinned", placed == nil)

-- The same button again closes it.
card.where:GetScript("OnClick")(card.where, "LeftButton")
suite.check("second click closes", not panel:IsShown())

-- /farm where works without a goal.
ns.HandleSlash("where tin")
suite.check("/farm where opens it", panel:IsShown() and panel.title:GetText():find("Tin Ore") ~= nil)

-- A zone the client refuses to read: the panel still opens.
_G.GetRealZoneText = function() return env.Secret("zone") end
panel:Hide()
local ok = pcall(GUI.OpenSpots, GUI, "Copper Ore")
suite.check("a secret zone does not raise", ok)
suite.check("and says why it is not by distance", panel.from:GetText():find("could not be read") ~= nil)

suite.done()
