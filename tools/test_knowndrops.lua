-- Mobs known to drop items nobody has looted yet: leads for the search,
-- never a rate, never worth or Rankings, and a looted row takes their place.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("knowndrops")

local ns = env.Load()
local DB = ns.DB

local function Rows(path)
    local rows = {}
    local handle = assert(io.open(lfs_cwd .. "/" .. path, "r"))
    for line in handle:lines() do
        local id = line:match("RegisterItem%(%{ name = \".-\", id = (%d+)")
        if id then rows[#rows + 1] = tonumber(id) end
    end
    handle:close()
    return rows
end

--------------------------------------------------------------------------------
-- The shipped rows
--------------------------------------------------------------------------------

local ids = Rows("Data/Data_KnownDrops.lua")
suite.check("the file adds items", #ids > 100, #ids)

local byID, rows, rated, measured, noLevels = DB:ByID(), 0, 0, 0, 0
for _, id in ipairs(ids) do
    local item = byID[id]
    suite.check("item " .. id .. " is in the database", item ~= nil)
    if item then
        for _, source in ipairs(item.sources) do
            if source.searchOnly then
                rows = rows + 1
                if source.chance then rated = rated + 1 end
                if source.provenance ~= "classic" then measured = measured + 1 end
                if not (source.minLevel and source.maxLevel and source.maxLevel >= source.minLevel) then
                    noLevels = noLevels + 1
                end
            end
        end
    end
end
suite.check("every item has a mob", rows >= #ids, rows)
suite.check("never with a drop rate", rated == 0, rated)
suite.check("shown without the Forever mark", measured == 0, measured)
suite.check("every row has a level band", noLevels == 0, noLevels)

-- No item is registered twice: an item another file has is left out.
local seen = {}
for _, path in ipairs({ "Data/Data_ClassicDrops.lua", "Data/Data_Harvested.lua" }) do
    local handle = assert(io.open(lfs_cwd .. "/" .. path, "r"))
    local text = handle:read("*a")
    handle:close()
    for id in text:gmatch("id = (%d+)") do seen[tonumber(id)] = true end
end
local twice = 0
for _, id in ipairs(ids) do
    if seen[id] then twice = twice + 1 end
end
suite.check("never an item another data file has", twice == 0, twice)

-- A known row shows in the search like a Classic lead.
local femur = DB:GetItem("Stitches' Femur")
suite.check("a boss's drop names its boss",
    femur and femur.sources[1] and femur.sources[1].name == "Stitches"
        and femur.sources[1].zone == "Duskwood")
suite.check("and stays out of Rankings", ns.Rankings:Spot("Stitches") == nil)

--------------------------------------------------------------------------------
-- A looted row takes the known one's place
--------------------------------------------------------------------------------

DB:AddSource("Stitches' Femur", { name = "Stitches", zone = "Duskwood",
    location = "Raven Hill", minLevel = 35, maxLevel = 35, chance = 50, provenance = "forever" })
local count, kept = 0, nil
for _, source in ipairs(femur.sources) do
    if source.name == "Stitches" and source.zone == "Duskwood" then
        count = count + 1
        kept = source
    end
end
suite.check("one row, the looted one", count == 1 and kept.provenance == "forever", count)

suite.done()
