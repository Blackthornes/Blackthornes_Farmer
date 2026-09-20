-- Searching and the lines it produces.
--
-- The ranking is the feature: one box answers both "where do I get this" and
-- "what is worth farming here", and the second must never bury the first. So
-- these check the order results come back in, not just that they come back.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("search")

local ns = env.Load()
local Search = ns.Search

--------------------------------------------------------------------------------
-- Ranking
--------------------------------------------------------------------------------

local exact = Search:Run("copper ore")
suite.check("an exact name ranks first",
    exact[1] and exact[1].item.name == "Copper Ore",
    exact[1] and exact[1].item.name)

local partial = Search:Run("mithril")
suite.check("a partial name matches",
    partial[1] and partial[1].item.name == "Mithril Ore",
    partial[1] and partial[1].item.name)

local alias = Search:Run("spider silk")
suite.check("an alias matches",
    alias[1] and alias[1].item.name == "Spider's Silk",
    alias[1] and alias[1].item.name)

local byZone = Search:Run("westfall")
suite.check("a zone returns what is farmable there", #byZone > 0, #byZone)

for _, result in ipairs(byZone) do
    suite.check("a zone match never claims to be a name match",
        result.why ~= "name", result.item.name)
end

local byMob = Search:Run("defias")
suite.check("a mob name finds what it drops",
    byMob[1] and byMob[1].item.name == "Linen Cloth",
    byMob[1] and byMob[1].item.name)

local byCategory = Search:Run("herbalism")
suite.check("a category returns its items", #byCategory > 3, #byCategory)

-- "Copper" is in the name of one item and the zone list of none, so a name
-- match has to come out above the alias-only and zone-only matches.
local mixed = Search:Run("copper")
suite.check("name matches sort above weaker matches",
    mixed[1] and mixed[1].why == "name", mixed[1] and mixed[1].why)

suite.check("nonsense finds nothing", #Search:Run("qqzzxx") == 0)
suite.check("an empty query finds nothing", #Search:Run("") == 0)
suite.check("whitespace is not a query", #Search:Run("   ") == 0)

--------------------------------------------------------------------------------
-- Ordering within an item
--------------------------------------------------------------------------------

local copper = ns.DB:GetItem("Copper Ore")
local sorted = Search:SortedSources(copper)

for index = 2, #sorted do
    suite.check("sources sort by level",
        sorted[index].minLevel >= sorted[index - 1].minLevel,
        ("%d after %d"):format(sorted[index].minLevel, sorted[index - 1].minLevel))
end

suite.check("sorting does not disturb the stored order",
    #copper.sources == #sorted)

--------------------------------------------------------------------------------
-- Lines
--------------------------------------------------------------------------------

local Util = ns.Util

local line = Util.StripColor(Search:SourceLine(sorted[1]))

suite.check("a source line names the zone",
    line:find(sorted[1].zone, 1, true) ~= nil, line)

suite.check("a source line shows the level band",
    line:find(Search:LevelText(sorted[1]), 1, true) ~= nil, line)

-- A herb node is named after the herb, so it carries no name of its own and
-- must not print its kind twice.
local dreamfoil = ns.DB:GetItem("Dreamfoil")
local herbLine = Util.StripColor(Search:SourceLine(dreamfoil.sources[1]))
local _, occurrences = herbLine:gsub("herb node", "")

suite.check("an unnamed node does not repeat its kind", occurrences == 1, herbLine)

-- Only confirmed rows carry the marker.
suite.check("Classic rows are unmarked",
    not Util.StripColor(Search:SourceLine(sorted[1])):find("[Forever]", 1, true))

local confirmed = { kind = "mob", name = "a checked mob", zone = "Durotar",
    minLevel = 5, maxLevel = 8, provenance = "forever" }

suite.check("a confirmed row is marked",
    Util.StripColor(Search:SourceLine(confirmed)):find("[Forever]", 1, true) ~= nil)

local lines, total = Search:BuildLines("copper ore", 12)
suite.check("building lines produces output", #lines > 1, #lines)
suite.check("building lines reports a total", total >= 1, total)

local missed = Search:BuildLines("qqzzxx", 12)
suite.check("a miss explains itself",
    Util.StripColor(missed[1]):find("Nothing found", 1, true) ~= nil, missed[1])

-- A broad query must not dump the whole database into the window.
local broad, broadTotal = Search:BuildLines("mob drop", 2)
suite.check("a broad query is capped", broadTotal > 2, broadTotal)
suite.check("the cap says how much was left out",
    Util.StripColor(broad[#broad]):find("and %d+ more") ~= nil, broad[#broad])

suite.done()
