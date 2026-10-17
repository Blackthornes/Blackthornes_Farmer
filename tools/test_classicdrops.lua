-- Classic's drops fill the search before anything is looted here: spots
-- only, never a rate, and a spot of your own takes the Classic one's place.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("classicdrops")

local ns = env.Load()
local DB, Search = ns.DB, ns.Search

local function Find(item, mob, zone)
    for _, source in ipairs(item.sources) do
        if source.name == mob and source.zone == zone then return source end
    end
end

local function Count(item, mob, zone)
    local n = 0
    for _, source in ipairs(item.sources) do
        if source.name == mob and source.zone == zone then n = n + 1 end
    end
    return n
end

--------------------------------------------------------------------------------
-- The shipped rows
--------------------------------------------------------------------------------

local rows, withChance, notClassic = 0, 0, 0
for item in DB:Iterate() do
    for _, source in ipairs(item.sources) do
        if source.searchOnly then
            rows = rows + 1
            if source.chance then withChance = withChance + 1 end
            if source.provenance ~= "classic" then notClassic = notClassic + 1 end
        end
    end
end
suite.check("the file adds spots", rows > 1000, rows)
suite.check("never with a drop rate", withChance == 0, withChance)
suite.check("and all shown as Classic's", notClassic == 0, notClassic)

local linen = DB:GetItem("Linen Cloth")
suite.check("a hand-typed item gains spots, not a second entry",
    linen and Find(linen, "Riverpaw Gnoll", "Westfall") ~= nil)

--------------------------------------------------------------------------------
-- Measured rows win, in either order
--------------------------------------------------------------------------------

DB:RegisterItem({ name = "Test Pelt", id = 990101, sources = {
    { name = "Test Wolf", zone = "Elwynn Forest", minLevel = 5, maxLevel = 6, searchOnly = true },
} })
DB:AddSource("Test Pelt", { name = "Test Wolf", zone = "Elwynn Forest",
    location = "Stone Cairn Lake", minLevel = 7, maxLevel = 8, chance = 30, provenance = "forever" })

local pelt = DB:GetItem("Test Pelt")
suite.check("a looted row takes the Classic one's place",
    Count(pelt, "Test Wolf", "Elwynn Forest") == 1
        and Find(pelt, "Test Wolf", "Elwynn Forest").provenance == "forever",
    Count(pelt, "Test Wolf", "Elwynn Forest"))

DB:AddSource("Test Pelt", { name = "Test Wolf", zone = "Elwynn Forest",
    minLevel = 5, maxLevel = 6, searchOnly = true })
suite.check("a Classic row coming after a looted one is left out",
    Count(pelt, "Test Wolf", "Elwynn Forest") == 1
        and Find(pelt, "Test Wolf", "Elwynn Forest").chance == 30)

DB:AddSource("Test Pelt", { name = "Test Wolf", zone = "Westfall",
    minLevel = 10, maxLevel = 11, searchOnly = true })
suite.check("another zone is its own spot", Count(pelt, "Test Wolf", "Westfall") == 1)

--------------------------------------------------------------------------------
-- They stay out of the Grind tab and Rankings
--------------------------------------------------------------------------------

DB:RegisterItem({ name = "Test Fang", id = 990102, sources = {
    { name = "Lonely Test Boar", zone = "Durotar", minLevel = 4, maxLevel = 5, searchOnly = true },
} })
suite.check("Rankings never takes a spot from them", ns.Rankings:Spot("Lonely Test Boar") == nil)

--------------------------------------------------------------------------------
-- Your own records replace a Classic spot in the search
--------------------------------------------------------------------------------

ns.Harvest.records["Riverpaw Gnoll|Westfall|"] = {
    mob = "Riverpaw Gnoll", zone = "Westfall", minLevel = 11, maxLevel = 12,
    corpses = 5,
    items = { ["Linen Cloth"] = { corpses = 2, count = 3, id = 2589 } },
}
ns.Harvest.changes = (ns.Harvest.changes or 0) + 1
Search.found = nil
Search:Run("linen cloth")

local shown = Search:WithYourSpots(linen)
local gnolls, mine = 0, nil
for _, source in ipairs(shown.sources) do
    if source.name == "Riverpaw Gnoll" and source.zone == "Westfall" then
        gnolls = gnolls + 1
        mine = source
    end
end
suite.check("your spot shows once, in the Classic one's place",
    gnolls == 1 and mine.provenance == "forever", gnolls)
suite.check("the database itself is unchanged",
    Find(linen, "Riverpaw Gnoll", "Westfall").provenance == "classic")

suite.done()
