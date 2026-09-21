-- The seed database holds together: every item is findable, every source says
-- where to go and at what level, and every row declares where its facts came
-- from.
--
-- These are the invariants the window's layout quietly assumes. A source with
-- no zone renders as a blank line, and one with no level sorts to the top as
-- if it were the lowest-level option in the list, which is worse than missing.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("data")

local ns = env.Load()
local DB = ns.DB

suite.check("items loaded", DB:CountItems() > 0, DB:CountItems())
suite.check("sources loaded", DB:CountSources() > 0, DB:CountSources())

for item in DB:Iterate() do
    suite.check(("%s has at least one source"):format(item.name), #item.sources > 0)
    suite.check(("%s has a category"):format(item.name),
        type(item.category) == "string" and item.category ~= "")

    for _, source in ipairs(item.sources) do
        suite.check(("%s source has a zone"):format(item.name),
            type(source.zone) == "string" and source.zone ~= "")

        suite.check(("%s source in %s has a level"):format(item.name, source.zone),
            type(source.minLevel) == "number")

        suite.check(("%s source in %s has a sane level band"):format(item.name, source.zone),
            source.maxLevel >= source.minLevel,
            ("%s-%s"):format(tostring(source.minLevel), tostring(source.maxLevel)))

        suite.check(("%s source in %s declares its provenance"):format(item.name, source.zone),
            DB.PROVENANCE[source.provenance] ~= nil, source.provenance)

        suite.check(("%s source in %s has a known kind"):format(item.name, source.zone),
            DB.KIND_LABEL[source.kind] ~= nil, source.kind)
    end
end

--------------------------------------------------------------------------------
-- Mob drops
--------------------------------------------------------------------------------

-- The point of the mob-drop data is naming the mob. A row that says only
-- "Eastern Plaguelands, level 53-60" is not something anyone can act on.
local mobSources, namedMobSources = 0, 0

for item in DB:Iterate() do
    for _, source in ipairs(item.sources) do
        if source.kind == "mob" then
            mobSources = mobSources + 1
            if source.name and source.name ~= "" then
                namedMobSources = namedMobSources + 1
            end
        end
    end
end

suite.check("the database has mob drops in it", mobSources > 20, mobSources)
suite.check("every mob source names the mob", namedMobSources == mobSources,
    ("%d of %d"):format(namedMobSources, mobSources))

--------------------------------------------------------------------------------
-- Provenance
--------------------------------------------------------------------------------

local counts = DB:CountByProvenance()

suite.check("provenance counts cover every source",
    (counts.classic or 0) + (counts.forever or 0) == DB:CountSources())

-- Everything shipped is Classic data. If this ever fails it is because
-- somebody marked a row confirmed, which is fine -- but the claim is that they
-- checked it in game, so the failing test is the prompt to say so in the
-- commit rather than a mistake to paper over.
suite.check("seed data is all Classic-sourced", (counts.forever or 0) == 0,
    counts.forever)

--------------------------------------------------------------------------------
-- Registering the same name merges
--------------------------------------------------------------------------------

local before = DB:GetItem("Copper Ore")
local beforeCount = #before.sources

DB:RegisterItem({
    name = "Copper Ore",
    sources = { { kind = "node", zone = "Testing Grounds", minLevel = 1, maxLevel = 2 } },
})

suite.check("re-registering merges rather than replacing",
    #DB:GetItem("Copper Ore").sources == beforeCount + 1)

suite.check("merging does not create a second item",
    DB:GetItem("Copper Ore") == before)

--------------------------------------------------------------------------------
-- Bad data is refused, not stored
--------------------------------------------------------------------------------

suite.check("an item with no name is refused", DB:RegisterItem({}) == nil)
suite.check("a non-table is refused", DB:RegisterItem("Copper Ore") == nil)

local item = DB:RegisterItem({
    name = "Zone Free Test Item",
    sources = { { kind = "mob", name = "nowhere in particular" } },
})

suite.check("a source with no zone is dropped", #item.sources == 0)

--------------------------------------------------------------------------------
-- The new fields
--------------------------------------------------------------------------------

-- Coordinates point somewhere. A pair outside the map, or a string where a
-- number belongs, is worse than no coordinates at all: it sends someone on a
-- flight to nowhere instead of letting them read the landmark name.
local function SourceWithCoords(coords)
    local item = DB:RegisterItem({
        name = "Coordinate Test " .. tostring(coords and coords[1] or "none"),
        sources = { { kind = "mob", name = "x", zone = "Durotar",
            minLevel = 5, coords = coords } },
    })
    return item.sources[1]
end

suite.check("good coordinates are kept", SourceWithCoords({ 45.5, 68.2 }).coords ~= nil)
suite.check("coordinates off the map are dropped",
    SourceWithCoords({ 145, 20 }).coords == nil)
suite.check("negative coordinates are dropped", SourceWithCoords({ -4, 20 }).coords == nil)
suite.check("a half pair is dropped", SourceWithCoords({ 40 }).coords == nil)
suite.check("a text coordinate is dropped", SourceWithCoords({ "40", 20 }).coords == nil)

local function SourceWithChance(chance)
    local item = DB:RegisterItem({
        name = "Chance Test " .. tostring(chance),
        sources = { { kind = "mob", name = "x", zone = "Durotar",
            minLevel = 5, chance = chance } },
    })
    return item.sources[1]
end

suite.check("a real drop rate is kept", SourceWithChance(35).chance == 35)
suite.check("a rate over 100 is dropped", SourceWithChance(140).chance == nil)
suite.check("a zero rate is dropped", SourceWithChance(0).chance == nil)

--------------------------------------------------------------------------------
-- Wool Cloth is the template
--
-- It is the worked example of a fully researched item, so it is the one entry
-- that has to stay complete. If these fail, the thing the rest of the data is
-- meant to be copied from has rotted.
--------------------------------------------------------------------------------

local wool = DB:GetItem("Wool Cloth")

suite.check("Wool Cloth is in the database", wool ~= nil)
suite.check("it has a serious number of spots", #wool.sources >= 15, #wool.sources)

local withCoords, zones = 0, {}

for _, source in ipairs(wool.sources) do
    suite.check("every Wool Cloth row names its mob",
        source.name and source.name ~= "", source.zone)

    suite.check("every Wool Cloth row names where in the zone",
        source.location and source.location ~= "", source.name)

    suite.check("every Wool Cloth row has a drop rate",
        type(source.chance) == "number", source.name)

    suite.check("every Wool Cloth row has a level band",
        source.minLevel and source.maxLevel, source.name)

    if source.coords then withCoords = withCoords + 1 end
    zones[source.zone] = true
end

suite.check("some rows carry coordinates", withCoords > 0, withCoords)

local zoneCount = 0
for _ in pairs(zones) do zoneCount = zoneCount + 1 end
suite.check("it spans several zones", zoneCount >= 5, zoneCount)

--------------------------------------------------------------------------------
-- Where text
--------------------------------------------------------------------------------

suite.check("landmark and coordinates read together",
    DB:WhereText({ location = "Durnholde Keep", coords = { 80, 60 } })
        :find("Durnholde Keep", 1, true) ~= nil)

suite.check("a landmark alone is enough",
    DB:WhereText({ location = "Render's Camp" }) == "Render's Camp")

suite.check("coordinates alone still read",
    DB:WhereText({ coords = { 80, 60 } }) == "80.0, 60.0")

suite.check("nothing known reads as nothing", DB:WhereText({}) == nil)

suite.done()
