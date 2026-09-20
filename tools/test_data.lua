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

suite.done()
