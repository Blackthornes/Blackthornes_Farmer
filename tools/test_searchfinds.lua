-- Search finds what you looted, gathered or fished even when the data has
-- never heard of it, and "crates" finds Crate.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("searchfinds")

local ns = env.Load()
local Search = ns.Search

--------------------------------------------------------------------------------
-- Plurals
--------------------------------------------------------------------------------

suite.check("crates is crate", Search.Singular("crates") == "crate", Search.Singular("crates"))
suite.check("boxes is box", Search.Singular("boxes") == "box", Search.Singular("boxes"))
suite.check("ores is ore", Search.Singular("ores") == "ore", Search.Singular("ores"))
suite.check("glass stays", Search.Singular("glass") == nil, Search.Singular("glass"))
suite.check("cloth has none", Search.Singular("cloth") == nil)

local ores = Search:Run("copper ores")
suite.check("a plural finds the item", ores[1] and ores[1].item.name == "Copper Ore",
    ores[1] and ores[1].item.name)

for _, result in ipairs(Search:Run("craters")) do
    suite.check("a plural never matches a zone the shorter way",
        result.why ~= "zone", result.item.name)
end

--------------------------------------------------------------------------------
-- Your own finds
--------------------------------------------------------------------------------

local before = #Search:Run("crate")

ns.Harvest.records["Ruin Ghoul|Ruins of Lordaeron|"] = {
    mob = "Ruin Ghoul", zone = "Ruins of Lordaeron", minLevel = 22, maxLevel = 24,
    corpses = 40,
    items = {
        ["Sealed Supply Crate"] = { corpses = 10, count = 10, id = 990001 },
        ["Linen Cloth"] = { corpses = 12, count = 15, id = 2589 },
    },
}
ns.Harvest.records["Mystery Bat|Elwynn Forest|"] = {
    mob = "Mystery Bat", zone = "Elwynn Forest", minLevel = 5, maxLevel = 5,
    corpses = 3,
    items = { ["Sealed Supply Crate"] = { corpses = 1, count = 1, id = 990001 } },
}
ns.db.gathering = { nodes = { ["Durotar||Odd Chest"] = {
    zone = "Durotar", node = "Odd Chest", kind = "chest", gathers = 2,
    items = { ["Dusty Crate"] = { gathers = 2, count = 2 } },
} } }
ns.db.fishing = { spots = { ["Westfall||"] = {
    zone = "Westfall", casts = 25,
    items = { ["Floating Crate"] = { casts = 5, count = 5 } },
} } }
ns.Harvest.changes = (ns.Harvest.changes or 0) + 1
Search.found = nil

local results = Search:Run("crates")
local byName = {}
for _, result in ipairs(results) do byName[result.item.name] = result.item end

local sealed = byName["Sealed Supply Crate"]
suite.check("a looted crate the data does not know is found", sealed ~= nil)
suite.check("both spots it came from are listed", sealed and #sealed.sources == 2,
    sealed and #sealed.sources)
local rated, thin
for _, source in ipairs(sealed and sealed.sources or {}) do
    if source.name == "Ruin Ghoul" then rated = source else thin = source end
end
suite.check("a rate once 20 corpses are behind it", rated and math.abs(rated.chance - 25) < 0.01,
    rated and rated.chance)
suite.check("no rate off 3 corpses", thin and thin.chance == nil)
suite.check("marked as measured on Forever", rated and rated.provenance == "forever")
suite.check("a gathered crate is found", byName["Dusty Crate"] ~= nil)
suite.check("a fished crate is found", byName["Floating Crate"] ~= nil)
suite.check("the found item keeps its ID", sealed and sealed.id == 990001)
suite.check("more than before", #Search:Run("crate") > before)

suite.check("an item the data knows is not listed twice", (function()
    local count = 0
    for _, result in ipairs(Search:Run("linen cloth")) do
        if result.item.name == "Linen Cloth" then count = count + 1 end
    end
    return count == 1
end)())

suite.check("nothing is added to the database", ns.DB:GetItem("Sealed Supply Crate") == nil)

suite.check("a find's mob finds it too", (function()
    for _, result in ipairs(Search:Run("ruin ghoul")) do
        if result.item.name == "Sealed Supply Crate" then return true end
    end
    return false
end)())

ns.DB:Hide("item", "Sealed Supply Crate")
local hidden = false
for _, result in ipairs(Search:Run("sealed supply")) do
    if result.item.name == "Sealed Supply Crate" then hidden = true end
end
suite.check("a hidden find stays hidden", not hidden)
ns.DB:Unhide("item", "Sealed Supply Crate")

local rows = Search:BuildRows("sealed supply")
suite.check("the window draws it", rows[1] and rows[1].type == "item"
    and rows[1].item.name == "Sealed Supply Crate", rows[1] and rows[1].type)

suite.done()
