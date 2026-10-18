-- A pearl comes out of Giant Clams and Thick-shelled Clams. Clams you
-- opened, found in many zones, must not push the Giant Clams off the Where?
-- list, and what came out of them shows in the search.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("clamspots")

local ns = env.Load()
local Spots, Search, Containers = ns.Spots, ns.Search, ns.Containers

local function Names(list)
    local seen = {}
    for _, spot in ipairs(list) do seen[spot.name] = (seen[spot.name] or 0) + 1 end
    return seen
end

local far = { zone = "Stormwind City", level = 30 }

local before = Names(Spots:For("Iridescent Pearl", far))
suite.check("Giant Clams on the list with nothing opened", (before["Giant Clam"] or 0) > 0)

-- Clams off mobs in many zones, ten opened, a pearl in three.
local zones = { "Wetlands", "Darkshore", "Hillsbrad Foothills", "Alterac Mountains",
    "Silverpine Forest", "Loch Modan", "Westfall", "Ashenvale" }
for index, zone in ipairs(zones) do
    local mob = "Clam Murloc " .. index
    ns.Harvest.records[mob .. "|" .. zone .. "|"] = {
        mob = mob, zone = zone, minLevel = 20, maxLevel = 22, corpses = 30,
        items = { ["Thick-shelled Clam"] = { corpses = 6, count = 6, id = 5524 } },
    }
end
ns.Harvest.changes = (ns.Harvest.changes or 0) + 1
for index = 1, 10 do
    local items = { "Tangy Clam Meat" }
    if index % 3 == 0 then items[2] = "Iridescent Pearl" end
    Containers:Record("Thick-shelled Clam", 5524, items)
end

local list = Spots:For("Iridescent Pearl", far)
local after = Names(list)
suite.check("still six places", #list == Spots.MAX, #list)
suite.check("Giant Clams stay after opening clams", (after["Giant Clam"] or 0) > 0)
suite.check("Big-mouth Clams stay too", (after["Big-mouth Clam"] or 0) > 0)
suite.check("the clams you opened lead", list[1].name == "Thick-shelled Clam", list[1].name)
for index = 2, #list do
    suite.check("best first", list[index - 1].score <= list[index].score)
end

-- Mobs are ranked as before: one mob can take two rows.
local mobs = Spots:For("Thick-shelled Clam", far)
suite.check("mob items still list", #mobs > 0)

--------------------------------------------------------------------------------
-- The search
--------------------------------------------------------------------------------

Search.found = nil
local found
for _, result in ipairs(Search:Run("Iridescent Pearl")) do
    if result.item.name == "Iridescent Pearl" then found = result.item end
end
suite.check("the pearl is found", found ~= nil)
local giant, yours = 0, {}
for _, source in ipairs(found and found.sources or {}) do
    if source.name == "Giant Clam" then giant = giant + 1 end
    if source.name == "Thick-shelled Clam" and source.provenance == "forever" then
        yours[source.zone] = source
    end
end
suite.check("search keeps the Giant Clams", giant == 3, giant)
suite.check("search shows where your clams came from", yours["Loch Modan"] ~= nil)
suite.check("each of your zones once", yours.Wetlands ~= nil and yours.Westfall ~= nil)
suite.check("says how many held one", yours.Wetlands and yours.Wetlands.dropText == "3 in 10",
    yours.Wetlands and tostring(yours.Wetlands.dropText))

-- A clam never opened adds nothing.
Search.found = nil
local meat
for _, result in ipairs(Search:Run("Tangy Clam Meat")) do
    if result.item.name == "Tangy Clam Meat" then meat = result.item end
end
suite.check("meat from your clams is found", meat ~= nil)

suite.done()
