-- The best places near you to farm a goal (2026-09-27): the Where?
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
-- Forever's name for it, read from inside.
suite.check("The Wailing Caverns is in the Barrens",
    Spots.Hops("The Wailing Caverns", "The Barrens") == 0)

-- How far, said right: a long walk on your own continent is so many zones,
-- not "other continent", and Teldrassil to the mainland is a boat.
local hops, travel = Spots.Hops("Tirisfal Glades", "Elwynn Forest")
suite.check("a long walk is a walk", hops == 10 and travel == nil,
    tostring(hops) .. ", " .. tostring(travel))
suite.check("and says how many zones",
    Spots.DistanceText(hops, "Elwynn Forest", travel) == "10 zones away",
    Spots.DistanceText(hops, "Elwynn Forest", travel))
hops, travel = Spots.Hops("Elwynn Forest", "Durotar")
suite.check("the other continent says so",
    Spots.DistanceText(hops, "Durotar", travel) == "other continent",
    Spots.DistanceText(hops, "Durotar", travel))
hops, travel = Spots.Hops("Teldrassil", "Darkshore")
suite.check("Teldrassil to Darkshore is a boat",
    Spots.DistanceText(hops, "Darkshore", travel) == "by boat",
    Spots.DistanceText(hops, "Darkshore", travel))

-- Scored and printed the same way; a spot scored again from somewhere else
-- forgets how it was reached before.
local trapper = { name = "Defias Trapper", zone = "Westfall", minLevel = 12, maxLevel = 13 }
Spots:Score(trapper, { zone = "Tirisfal Glades", level = 14 })
suite.check("the chat line counts the zones",
    Spots:Line(trapper):find("11 zones away", 1, true) ~= nil, Spots:Line(trapper))
local shore = { name = "Copper Vein", zone = "Darkshore" }
Spots:Score(shore, { zone = "Teldrassil", level = 10 })
suite.check("by boat from Teldrassil",
    Spots:Line(shore):find("by boat", 1, true) ~= nil, Spots:Line(shore))
Spots:Score(shore, { zone = "Ashenvale", level = 10 })
suite.check("next door from Ashenvale", shore.travel == nil
    and Spots:Line(shore):find("next zone over", 1, true) ~= nil, Spots:Line(shore))

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

-- A spot whose zone was never read is not "near", nor "in many places".
local lost = { name = "Lost", zone = nil, minLevel = 10 }
Spots:Score(lost, player)
Spots:Score(safe, player)
suite.check("an unread zone ranks below a real spot", lost.score > safe.score, lost.score .. " vs " .. safe.score)
suite.check("and says nothing about distance", Spots.DistanceText(lost.hops, lost.zone) == "")
suite.check("any coastline is still many places", Spots.DistanceText(1, "any coastline") == "in many places")

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

-- A rare drop reads "<1%", as the kills panel writes it, not "0%".
suite.check("a rare rate is not 0%", GUI.SpotNote({ chance = 0.4 }) == "<1% drop", GUI.SpotNote({ chance = 0.4 }))
local rare = ns.Util.StripColor(GUI.SpotNote({ measured = 0.4, yours = { kills = 250, got = 1 } }))
suite.check("nor is one you measured", rare == "<1% in your 250 kills", rare)
suite.check("a common rate reads as before", GUI.SpotNote({ chance = 25 }) == "25% drop", GUI.SpotNote({ chance = 25 }))

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

-- Layout (2026-09-27: "the where button kind of overlaps the progress
-- bar"): the button sits under the bar, the time left stops before it, and
-- the panel is wide enough for every line.
local wp = card.where._point
suite.check("Where? hangs under the bar", wp and wp[2] == card.track and wp[3] == "BOTTOMRIGHT"
    and wp[5] < 0, wp and tostring(wp[3]))
local rp = card.right._point
suite.check("time left ends before the button", rp and rp[2] == card.where and rp[3] == "LEFT")
suite.check("wide enough for its lines", GUI.frame:GetWidth() >= GUI:CardNeeds(card, card.goal),
    GUI.frame:GetWidth() .. " < " .. GUI:CardNeeds(card, card.goal))

-- A long place name widens the panel rather than being cut off.
local long = ns.Spots.For
ns.Spots.For = function() return { { name = "A Very Long Named Thick-shelled Clam Bed", zone = "Desolace", hops = 4 } } end
GUI:Refresh()
suite.check("widens for a long line", GUI.frame:GetWidth() > 236, GUI.frame:GetWidth())
suite.check("sub line gets the full width", card.sub._width == GUI:BarWidth() - 22 - 8, card.sub._width)
ns.Spots.For = long
GUI:Refresh()

card.where:GetScript("OnClick")(card.where, "LeftButton")
local panel = GUI.spots
suite.check("the panel opens", panel and panel:IsShown())
suite.check("titled for the item", panel.title:GetText():find("Copper Ore") ~= nil)
suite.check("says where from", panel.from:GetText():find("Loch Modan") ~= nil, panel.from:GetText())
suite.check("rows drawn", panel.rows[1]:IsShown() and panel.rows[1].rank:GetText() == "1")
suite.check("first row is yours", panel.rows[1].spot == Spots:For("Copper Ore")[1] or panel.rows[1].spot.yours ~= nil)

-- Levels are coloured as the search window colours them: red well above
-- you. They were yellow there, the colour it gives your own level.
local levels, sameColour = 0, true
for _, row in ipairs(panel.rows) do
    if row:IsShown() and row.spot and row.spot.minLevel then
        levels = levels + 1
        local r, g, b = ns.UI.DifficultyColor(row.spot.maxLevel or row.spot.minLevel)
        local c = row.level._color or {}
        if c[1] ~= r or c[2] ~= g or c[3] ~= b then sameColour = false end
    end
end
suite.check("levels coloured as the search window does", levels > 0 and sameColour, levels)
local _, green = ns.UI.DifficultyColor(30)
suite.check("so a place well above you is red", green < 0.5, green)

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

-- A dungeon inside the zone counts as "here" (hops 0) for the ranking, but
-- its coordinates are on a map of its own: never pinned on the zone's map.
placed = nil
local inside = { name = "Copper Vein", zone = "Ragefire Chasm", coords = { 50, 50 }, hops = 0 }
Spots:Share("Copper Ore", inside)
suite.check("a dungeon in your zone is not pinned", placed == nil, placed and placed.map)

-- Standing in a city or cave map inside the zone, the pin goes on the zone's
-- map, found by walking up the parents.
local MAPS = {
    [1426] = { name = "Dun Morogh", parentMapID = 1415 },
    [1415] = { name = "Eastern Kingdoms", parentMapID = 947 },
    [427] = { name = "Coldridge Valley", parentMapID = 1426 },
}
env.world.zone = "Dun Morogh"
env.world.mapID = 427
_G.C_Map.GetMapInfo = function(id) return MAPS[id] end
placed = nil
Spots:Share("Copper Ore", { name = "Copper Vein", zone = "Dun Morogh", coords = { 40, 60 }, hops = 0 })
suite.check("a sub-map pins on the zone's map", placed and placed.map == 1426, placed and placed.map)

-- No map up the chain carries the zone's name (Forever may spell a map its
-- own way): the pin still goes on the map you are on, as it always did.
env.world.zone = "Loch Modan"
placed = nil
Spots:Share("Copper Ore", { name = "Copper Vein", zone = "Loch Modan", coords = { 40, 60 }, hops = 0 })
suite.check("no matching map pins where you stand", placed and placed.map == 427, placed and placed.map)
_G.C_Map.GetMapInfo = nil
env.world.mapID = 21

-- The same button again closes it.
card.where:GetScript("OnClick")(card.where, "LeftButton")
suite.check("second click closes", not panel:IsShown())

-- /farm where works without a goal.
ns.HandleSlash("where tin")
suite.check("/farm where opens it", panel:IsShown() and panel.title:GetText():find("Tin Ore") ~= nil)

-- From Teldrassil the mainland is a boat away, on the panel too.
env.world.zone = "Teldrassil"
panel:Hide()
GUI:OpenSpots("Copper Ore")
local boat = false
for _, row in ipairs(panel.rows) do
    if row:IsShown() and row.zone:GetText():find("by boat", 1, true) then boat = true end
end
suite.check("the panel says how you get there", boat)
env.world.zone = "Loch Modan"

-- A zone the client refuses to read: the panel still opens.
_G.GetRealZoneText = function() return env.Secret("zone") end
panel:Hide()
local ok = pcall(GUI.OpenSpots, GUI, "Copper Ore")
suite.check("a secret zone does not raise", ok)
suite.check("and says why it is not by distance", panel.from:GetText():find("could not be read") ~= nil)

suite.done()
