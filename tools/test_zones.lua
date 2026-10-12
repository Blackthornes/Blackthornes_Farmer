-- Zone names from the Forever client's game tables (2026-10-12): each
-- zone's map ID, and the German names of zones, dungeons and raids
-- (Data/Zones.lua, written by tools/make_zones.py).
--
-- What matters: the map IDs are Forever's own; on a German client a record
-- kept under "Wald von Elwynn" is Elwynn Forest without standing there
-- first, the windows show "Wald von Elwynn", the search finds it by that
-- name, and everything compared stays English; an English client sees
-- exactly what it did before.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("zones")

local ns = env.Load({ ui = true })
local Spots = ns.Spots
local data = ns.ZONE_DATA

-- The data.
suite.check("the data loaded", type(data) == "table" and type(data.maps) == "table")
suite.check("Elwynn Forest's map is 1429", Spots.ZONE_MAPS["Elwynn Forest"] == 1429)
suite.check("Orgrimmar's map is 1454", Spots.ZONE_MAPS["Orgrimmar"] == 1454)
suite.check("1413 is The Barrens", Spots.MAP_ZONES[1413] == "The Barrens")
suite.check("Forever's Mount Hyjal has its map", Spots.ZONE_MAPS["Mount Hyjal"] == 2482)
local count = 0
for zone, mapID in pairs(Spots.ZONE_MAPS) do
    count = count + 1
    suite.check(zone .. " maps back to itself", Spots.MAP_ZONES[mapID] == zone)
end
suite.check("every Classic zone and capital has a map", count >= 46, count)

-- Every German name reads back to the English one it shows for.
for english, german in pairs(data.names.deDE) do
    suite.check(german .. " reads back", data.english.deDE[german] ~= nil, english)
end
suite.check("no test rows", data.names.deDE["Test Dungeon"] == nil and data.names.deDE["GM Island"] == nil)

-- An English client: nothing changes.
_G.GetLocale = function() return "enUS" end
suite.check("English: shown as it is", Spots.Show("Elwynn Forest") == "Elwynn Forest")
suite.check("English: a German name is left", Spots.English("Wald von Elwynn") == "Wald von Elwynn")
suite.check("English: nil stays nil", Spots.Show(nil) == nil)

-- A German client.
_G.GetLocale = function() return "deDE" end
suite.check("German: Elwynn Forest shows in German", Spots.Show("Elwynn Forest") == "Wald von Elwynn")
suite.check("German: a dungeon too", Spots.Show("Ragefire Chasm") == "Ragefireabgrund")
suite.check("German: a German name shows as it is", Spots.Show("Wald von Elwynn") == "Wald von Elwynn")
suite.check("German: a name not known shows as it is", Spots.Show("any coastline") == "any coastline")
suite.check("German: the English name of a German one", Spots.English("Wald von Elwynn") == "Elwynn Forest")
suite.check("German: the map's name reads too", Spots.English("Das Brachland") == "The Barrens")
suite.check("German: the zone's own name reads", Spots.English("Brachland") == "The Barrens")
suite.check("German: a record never visited counts",
    Spots.Hops("Dämmerwald", "Elwynn Forest") == 1, Spots.Hops("Dämmerwald", "Elwynn Forest"))
suite.check("German: a German dungeon is in its zone", Spots.ZoneOf("Ragefireabgrund") == "Durotar")

-- Standing there, with no map to read: the name alone says where.
_G.C_Map = { GetBestMapForUnit = function() return nil end }
env.world.zone = "Dämmerwald"
local player = Spots:Player()
suite.check("German: where you stand by name", player.zone == "Duskwood", player.zone)

-- The search finds a zone by its German name.
local german = ns.Search:Run("Dämmerwald")
local germanCount = #(german or {})
local english = ns.Search:Run("Duskwood")
suite.check("German: the search finds a zone by its German name",
    germanCount > 0 and germanCount == #(english or {}), germanCount)

-- A Spanish client, whose names are not shipped: as an English one.
_G.GetLocale = function() return "esES" end
suite.check("Spanish: shown as it is", Spots.Show("Elwynn Forest") == "Elwynn Forest")
suite.check("Spanish: a German name is left", Spots.English("Wald von Elwynn") == "Wald von Elwynn")

_G.GetLocale = nil
suite.check("no GetLocale: shown as it is", Spots.Show("Elwynn Forest") == "Elwynn Forest")

suite.done()
