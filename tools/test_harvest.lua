-- The loot harvester: what it records, what it refuses to record, and the
-- data file it hands back.
--
-- The refusals matter as much as the recording. A rate measured off the wrong
-- mob, or off six corpses, would go into the repository looking exactly like a
-- real one, so the cases that must produce nothing are tested first.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("harvest")

local ns = env.Load({ ui = true })
local Harvest = ns.Harvest

local APPRENTICE = { name = "Dalaran Apprentice", level = 22, dead = true }
local WOOL = { name = "Wool Cloth", quantity = 1, id = 2592 }
local SILVER = { name = "Silver Bar", quantity = 1 }

--- Loot `count` corpses of `mob`, `withItems` of them holding `items`.
local function Farm(mob, count, withItems, items)
    for index = 1, count do
        env.Loot(ns, mob, index <= withItems and items or {})
    end
end

--------------------------------------------------------------------------------
-- Capabilities
--------------------------------------------------------------------------------

local caps = Harvest:Capabilities()
suite.check("the stub client looks usable", caps.usable == true)
suite.check("it sees the map API", caps.bestMap and caps.playerPos)

--------------------------------------------------------------------------------
-- Recording
--------------------------------------------------------------------------------

Harvest:Reset()
Farm(APPRENTICE, 4, 3, { WOOL })

suite.check("every corpse counts", Harvest:CountCorpses() == 4, Harvest:CountCorpses())
suite.check("one mob is one record", Harvest:CountMobs() == 1, Harvest:CountMobs())

local rows = Harvest:ForItem("Wool Cloth")
suite.check("the item was seen", #rows == 1, #rows)
suite.check("only the corpses that held it count",
    rows[1] and rows[1].entry.corpses == 3, rows[1] and rows[1].entry.corpses)
suite.check("the rate is holders over corpses",
    rows[1] and rows[1].chance == 75, rows[1] and rows[1].chance)

local record = rows[1].record
suite.check("the zone came from the client",
    record.zone == "Silverpine Forest", record.zone)
suite.check("the subzone became the location",
    record.location == "The Sepulcher", record.location)
suite.check("the level came from the corpse", record.minLevel == 22, record.minLevel)
suite.check("coordinates are map percentages",
    record.coords and math.abs(record.coords[1] - 45) < 0.01
        and math.abs(record.coords[2] - 68) < 0.01,
    record.coords and table.concat(record.coords, ","))

suite.check("the item id came off the loot link",
    rows[1].entry.id == 2592, rows[1].entry.id)

-- Two of the same item in one corpse is one corpse that held it.
Harvest:Reset()
env.Loot(ns, APPRENTICE, { WOOL, WOOL })

local doubled = Harvest:ForItem("Wool Cloth")[1]
suite.check("two stacks in one corpse is one corpse",
    doubled.entry.corpses == 1, doubled.entry.corpses)
suite.check("but both stacks are counted", doubled.entry.count == 2, doubled.entry.count)

--------------------------------------------------------------------------------
-- What it refuses to record
--------------------------------------------------------------------------------

Harvest:Reset()
env.world.fishing = true
env.Loot(ns, APPRENTICE, { WOOL })
env.world.fishing = false
suite.check("a fishing pool is not a mob", Harvest:CountCorpses() == 0)

Harvest:Reset()
env.Loot(ns, { name = "Blackthornes", level = 25, dead = true, isPlayer = true }, { WOOL })
suite.check("a player corpse is not a farming spot", Harvest:CountCorpses() == 0)

Harvest:Reset()
env.Loot(ns, { name = "Dalaran Apprentice", level = 22, dead = false }, { WOOL })
suite.check("a living target means the corpse is unknown",
    Harvest:CountCorpses() == 0)

Harvest:Reset()
env.world.target = nil
env.Loot(ns, nil, { WOOL })
suite.check("no target means no sample", Harvest:CountCorpses() == 0)
suite.check("a dropped sample is counted as skipped", Harvest.skipped and Harvest.skipped > 0)

-- Two mobs of the same name in different zones are different spots.
Harvest:Reset()
env.world.zone = "Silverpine Forest"
env.Loot(ns, APPRENTICE, { WOOL })
env.world.zone = "Hillsbrad Foothills"
env.Loot(ns, APPRENTICE, { WOOL })
suite.check("the same mob in two zones is two records",
    Harvest:CountMobs() == 2, Harvest:CountMobs())
env.world.zone = "Silverpine Forest"

--------------------------------------------------------------------------------
-- Export
--------------------------------------------------------------------------------

Harvest:Reset()
Farm(APPRENTICE, 40, 30, { WOOL, SILVER })

local block = Harvest:ExportItem("Wool Cloth")
suite.check("the export registers the item",
    block:find('name = "Wool Cloth"', 1, true) ~= nil, block)
suite.check("it carries the item id", block:find("id = 2592", 1, true) ~= nil, block)
suite.check("it names the mob",
    block:find('name = "Dalaran Apprentice"', 1, true) ~= nil, block)
suite.check("it carries the measured rate",
    block:find("chance = 75", 1, true) ~= nil, block)
suite.check("a measured row is marked as Forever",
    block:find('provenance = "forever"', 1, true) ~= nil, block)
suite.check("it says how big the sample was",
    block:find("30 of 40 corpses", 1, true) ~= nil, block)

-- A rate off a handful of corpses is a number pretending to be evidence.
Harvest:Reset()
Farm(APPRENTICE, 6, 3, { WOOL })

local thin = Harvest:ExportItem("Wool Cloth")
suite.check("a thin sample publishes no rate",
    thin:find("chance =", 1, true) == nil, thin)
suite.check("and says why", thin:find("too few for a rate", 1, true) ~= nil, thin)

suite.check("nothing harvested for an item exports nothing",
    Harvest:ExportItem("Mithril Ore") == nil)

local all = Harvest:ExportAll()
suite.check("the whole export is a loadable chunk",
    loadstring(all) ~= nil or load(all) ~= nil)
suite.check("it explains where to put it",
    all:find("Data/", 1, true) ~= nil, all)

Harvest:Reset()
suite.check("an empty export still says something",
    Harvest:ExportAll():find("Nothing harvested", 1, true) ~= nil)

--------------------------------------------------------------------------------
-- Naming an item
--------------------------------------------------------------------------------

Harvest:Reset()
Farm(APPRENTICE, 2, 2, { WOOL, SILVER })

suite.check("an exact name resolves",
    Harvest:ResolveItem("Wool Cloth") == "Wool Cloth")
suite.check("case does not matter",
    Harvest:ResolveItem("wool cloth") == "Wool Cloth")
suite.check("a prefix resolves", Harvest:ResolveItem("wool") == "Wool Cloth")
suite.check("a word from the middle resolves",
    Harvest:ResolveItem("cloth") == "Wool Cloth")
suite.check("a prefix beats a mid-word match",
    Harvest:ResolveItem("silver") == "Silver Bar")
suite.check("nothing matching resolves to nothing",
    Harvest:ResolveItem("mithril") == nil)
suite.check("an empty name resolves to nothing", Harvest:ResolveItem("") == nil)

--------------------------------------------------------------------------------
-- Commands and the export window
--------------------------------------------------------------------------------

local UI = ns.UI

UI:ShowExport("hello\nworld", "Export -- test")
suite.check("the export window opens", UI.exportFrame:IsShown() == true)
suite.check("it holds the text", UI.exportEdit:GetText() == "hello\nworld",
    UI.exportEdit:GetText())
suite.check("it is titled", UI.exportTitle:GetText() == "Export -- test",
    UI.exportTitle:GetText())
suite.check("it counts what is in it",
    UI.exportCount:GetText():find("2 lines", 1, true) ~= nil,
    UI.exportCount:GetText())

UI:HideExport()
suite.check("and closes", UI.exportFrame:IsShown() == false)

ns.HandleSlash("export wool")
suite.check("/farm export <item> opens the window", UI.exportFrame:IsShown() == true)
suite.check("with only that item",
    UI.exportEdit:GetText():find("Silver Bar", 1, true) == nil,
    UI.exportEdit:GetText())
UI:HideExport()

ns.HandleSlash("export mithril")
suite.check("/farm export for something unharvested says so, and opens nothing",
    UI.exportFrame:IsShown() == false)

ns.HandleSlash("export")
suite.check("/farm export with no item exports everything",
    UI.exportEdit:GetText():find("Silver Bar", 1, true) ~= nil,
    UI.exportEdit:GetText())
UI:HideExport()

ns.HandleSlash("harvest")
suite.check("/farm harvest reports the corpses",
    #env.chat > 0 and table.concat(env.chat, "\n"):find("2 corpses", 1, true) ~= nil,
    table.concat(env.chat, "\n"))

ns.HandleSlash("harvest off")
env.Loot(ns, APPRENTICE, { WOOL })
suite.check("harvesting off records nothing", Harvest:CountCorpses() == 2,
    Harvest:CountCorpses())

ns.HandleSlash("harvest on")
env.Loot(ns, APPRENTICE, { WOOL })
suite.check("harvesting on records again", Harvest:CountCorpses() == 3,
    Harvest:CountCorpses())

ns.HandleSlash("harvest reset")
suite.check("reset empties it", Harvest:CountCorpses() == 0)

suite.done()
