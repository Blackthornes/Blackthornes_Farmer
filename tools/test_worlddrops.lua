-- World drops: how often green gear and better drops, by mob level.
--
-- What matters: only gear counts (a green gem is no world drop), quality
-- comes from the loot link's colour, mobs are grouped five levels a band and
-- a dungeon's records are left out; a band says nothing below MIN_KILLS; the
-- shipped counts stand in until the player has killed more in a band, never
-- added to theirs; the sums follow a new corpse; the export block reads back
-- as the same counts; and the kills panel, tooltip, Rankings and search show
-- it only while the setting is on.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("worlddrops")

local ns = env.Load({ ui = true })
local WorldDrops = ns.WorldDrops

local now = 1000
_G.GetTime = function() return now end

-- The client's item classes (2 weapon, 4 armour, 7 trade goods) and
-- qualities, by ID.
local CLASS = { [100] = 2, [101] = 4, [102] = 4, [103] = 4, [200] = 7, [300] = 2 }
local QUALITY = { [100] = 2, [101] = 3, [102] = 1, [103] = 4, [200] = 2, [300] = 2 }
_G.C_Item = {
    GetItemInfoInstant = function(id)
        if not CLASS[id] then return nil end
        return id, "Weapon", "Sword", "INVTYPE_WEAPON", 1, CLASS[id], 0
    end,
    GetItemQualityByID = function(id) return QUALITY[id] end,
}

ns.Harvest.records = {}
local function Record(key, record)
    record.corpses = record.corpses or 0
    record.items = record.items or {}
    ns.Harvest.records[key] = record
    return record
end

-- A level-16 harpy: 300 corpses, 12 held the green sword, 1 the blue helm,
-- 5 a green gem (not gear), 40 a white glove.
local harpy = Record("harpy", { mob = "Witchwing Slayer", zone = "The Barrens",
    location = "The Dry Hills", minLevel = 16, maxLevel = 17, corpses = 300, items = {
        ["Green Sword"] = { id = 100, count = 12, corpses = 12 },
        ["Blue Helm"] = { id = 101, count = 1, corpses = 1 },
        ["Green Gem"] = { id = 200, count = 5, corpses = 5 },
        ["White Glove"] = { id = 102, count = 40, corpses = 40 },
    } })

-- The kills panel's link colour wins over the client's own quality.
ns.db.tracker = ns.db.tracker or {}
ns.db.tracker.looks = { ["Blue Helm"] = { color = "FF0070DD", id = 101 } }

-- A level-31 mob with too few kills, and a dungeon boss with no level.
Record("ogre", { mob = "Ogre", zone = "Feralas", minLevel = 31, maxLevel = 32, corpses = 50,
    items = { ["Green Sword"] = { id = 100, count = 3, corpses = 3 } } })
Record("boss", { mob = "Boss", zone = "Deadmines", corpses = 400,
    items = { ["Purple Robe"] = { id = 103, count = 9, corpses = 9 } } })
-- Some dungeon records carry a level: the zone still leaves them out.
Record("caverns", { mob = "Deviate Stalker", zone = "The Wailing Caverns", minLevel = 16, corpses = 400,
    items = { ["Purple Robe"] = { id = 103, count = 9, corpses = 9 } } })

--------------------------------------------------------------------------------
-- Counting
--------------------------------------------------------------------------------

suite.check("levels 16 and 17 are one band", WorldDrops.Band(16) == 15 and WorldDrops.Band(19) == 15)
suite.check("levels 1 to 4 are the first band", WorldDrops.Band(1) == 0 and WorldDrops.Band(4) == 0)
suite.check("no level, no band", WorldDrops.Band(nil) == nil)
suite.check("the band is labelled by its levels", WorldDrops.BandLabel(15) == "Levels 15-19",
    WorldDrops.BandLabel(15))

local list, byBand = WorldDrops:Bands()
local band = byBand[15]
suite.check("the harpy's band holds its kills", band and band.kills == 300, band and band.kills)
suite.check("only gear counts: the green sword, not the green gem", band.drops[2] == 12, band.drops[2])
suite.check("the blue helm counts as blue", band.drops[3] == 1, band.drops[3])
suite.check("white gear is no world drop", band.drops[4] == 0 and band.drops[5] == 0)
suite.check("the dungeon is left out", #list == 2 and not byBand[0], #list)

suite.check("the chance reads 1 in 25 kills", WorldDrops:GreenText(16) == "1 in 25 kills",
    WorldDrops:GreenText(16))
suite.check("too few kills say nothing", WorldDrops:GreenText(31) == nil)
suite.check("a level with no kills says nothing", WorldDrops:GreenText(50) == nil)

-- A new corpse moves the sums at once.
harpy.corpses = 312
harpy.items["Green Sword"].corpses = 13
ns.Harvest.changes = (ns.Harvest.changes or 0) + 1
local _, again = WorldDrops:Bands()
suite.check("a new corpse is counted", again[15].kills == 312 and again[15].drops[2] == 13,
    again[15].kills)

--------------------------------------------------------------------------------
-- The shipped counts
--------------------------------------------------------------------------------

ns.DB:WorldDrops({
    kills = { [15] = 1000, [20] = 400 },
    drops = {
        { 15, 100, 2, 25, "Witchwing Slayer" },
        { 20, 300, 2, 8, "Shipped Mob" },
        { 20, 200, 2, 50, "Shipped Mob" },
    },
    mobs = { ["Shipped Mob"] = { 21, 22, 400, "Ashenvale", "The Zoram Strand" } },
})

local _, mixed = WorldDrops:Bands()
suite.check("a band with more shipped kills uses the shipped ones", mixed[15].kills == 1000,
    mixed[15].kills)
suite.check("never the two added", mixed[15].drops[2] == 25, mixed[15].drops[2])
suite.check("a band only the shipped counts know is there", mixed[20] and mixed[20].kills == 400)
suite.check("the shipped green gem is no gear either", mixed[20].drops[2] == 8, mixed[20].drops[2])
suite.check("levels 20-24 read 1 in 50", WorldDrops:GreenText(22) == "1 in 50 kills",
    WorldDrops:GreenText(22))

harpy.corpses = 1200
ns.Harvest.changes = ns.Harvest.changes + 1
local _, own = WorldDrops:Bands()
suite.check("once you have killed more, your own count stands", own[15].kills == 1200,
    own[15].kills)

--------------------------------------------------------------------------------
-- The export block reads back
--------------------------------------------------------------------------------

local block = WorldDrops:ExportBlock()
suite.check("the export writes a block", type(block) == "string" and block:find("DB:WorldDrops", 1, true))
local read
assert(loadstring("local DB = ... " .. block))({ WorldDrops = function(_, data) read = data end })
suite.check("its kills by band read back", read and read.kills[15] == 1200 and read.kills[30] == 50,
    read and read.kills[15])
suite.check("the dungeon stays out of it", read and read.kills[0] == nil)
local rows = 0
for _, row in ipairs(read and read.drops or {}) do
    if row[1] == 15 and row[5] == "Witchwing Slayer" then rows = rows + 1 end
end
suite.check("every green or better item goes, gear or not (the game decides later)", rows == 3, rows)
suite.check("its mobs carry level, kills and place",
    read and read.mobs["Witchwing Slayer"][3] == 1200 and read.mobs["Witchwing Slayer"][4] == "The Barrens")
assert(loadstring("local DB = ... " .. block))({ RegisterItem = function() end })
suite.check("a reader with only RegisterItem skips it", true)

--------------------------------------------------------------------------------
-- Where it shows
--------------------------------------------------------------------------------

local card = WorldDrops:CardLines("Witchwing Slayer")
suite.check("the open mob gets its level's chance", card and card.label == "World drops, level 16"
    and card.chance == "1 in 92 kills", card and card.chance)
suite.check("and what you have had from it", card and card.had:find("13 green", 1, true)
    and card.had:find("1 blue", 1, true))
suite.check("purple is left out until you have had one", not card.had:find("purple", 1, true))

local lines = {}
local tooltip = {}
_G.UnitLevel = function(unit) return unit == "mouseover" and 16 or 25 end
suite.check("the mob tooltip says the greens", ns.KillTooltip:GreensLine("mouseover")
    == "Greens: 1 in 92 kills", ns.KillTooltip:GreensLine("mouseover"))
_G.UnitLevel = function() return -1 end
suite.check("a skull level says nothing", ns.KillTooltip:GreensLine("mouseover") == nil)

local rankRows = ns.RankingsUI:WorldRows()
suite.check("Rankings opens with a heading", rankRows and rankRows[1].type == "heading"
    and rankRows[1].group == "worlddrops")
local bands, best, rare = 0, nil, 0
for _, row in ipairs(rankRows) do
    if row.type == "band" then bands = bands + 1 end
    if row.best then best = row end
    if row.type == "rare" then rare = rare + 1 end
end
suite.check("a row for each band", bands == 3, bands)
suite.check("the band with the best chance glows", best and best.label == "Levels 20-24",
    best and best.label)
suite.check("blue, purple and orange each have a row", rare == 3, rare)
local bandText = ""
for _, row in ipairs(rankRows) do
    if row.type == "band" then bandText = bandText .. (row.text or "") end
end
suite.check("a band says its chance as a percent too", bandText:find("%", 1, true), bandText)

local RUI = ns.RankingsUI
suite.check("4.0% for 12 in 300", RUI.Percent(12, 300) == "4.0%", RUI.Percent(12, 300))
suite.check("whole numbers from 10%", RUI.Percent(30, 100) == "30%", RUI.Percent(30, 100))
suite.check("none reads 0%", RUI.Percent(0, 300) == "0%")
suite.check("a tiny chance reads <0.1%", RUI.Percent(1, 5000) == "<0.1%", RUI.Percent(1, 5000))
suite.check("no kills, no percent", RUI.Percent(0, 0) == nil)

local world = RUI:WorldData()
local view = RUI:WorldViewRows(world)
local first, last = view[1], nil
local measured, waiting = 0, nil
for _, row in ipairs(view) do
    if row.type == "wband" then
        last = row
        if row.measured then measured = measured + 1 else waiting = row end
    end
end
suite.check("the view puts the best chance first", first and first.best and first.label == "Levels 20-24",
    first and first.label)
suite.check("a measured band has its percent and 1 in", first.pct and first.oneInText:find("1 in", 1, true),
    first.pct)
suite.check("a band short of kills says how far along", waiting and waiting.killsText == "50 of 200"
    and waiting.oneInText == "Needs more kills", waiting and waiting.killsText)
suite.check("and it comes last", last == waiting)
suite.check("two bands are measured", measured == 2, measured)

local tiles = RUI.TileTexts(world)
suite.check("the green tile counts the greens", tiles[2] and tostring(tiles[2].count) ~= "0"
    and tiles[2].note:find("1 in", 1, true), tiles[2] and tiles[2].note)
suite.check("no data says it needs more kills", RUI.TileTexts(nil)[2].note == "Needs more kills")

_G.UnitLevel = function() return 16 end
local mine
for _, row in ipairs(RUI:WorldViewRows(RUI:WorldData())) do
    if row.yours then mine = row end
end
suite.check("your own level's band is marked", mine and mine.label == "Levels 15-19", mine and mine.label)
_G.UnitLevel = function() return -1 end

ns.db.rankingsWorldSort = { key = "level", ascending = true }
local byLevel = {}
for _, row in ipairs(RUI:WorldViewRows(RUI:WorldData())) do
    if row.type == "wband" then byLevel[#byLevel + 1] = row.label end
end
suite.check("sorted by level, lowest first", byLevel[1] == "Levels 15-19" and byLevel[3] == "Levels 30-34",
    table.concat(byLevel, ", "))
ns.db.rankingsWorldSort = nil

suite.check("'greens' is a world drops search", WorldDrops.IsQuery(" Greens "))
suite.check("'world drops' too", WorldDrops.IsQuery("world drops"))
suite.check("'green' alone is a name search", not WorldDrops.IsQuery("green"))

local results = ns.Search:Run("greens")
local first = results[1] and results[1].item
suite.check("the search leads with the best mobs", first and first.worldDrops, first and first.name)
suite.check("most green gear first", first.sources[1].name == "Witchwing Slayer",
    first.sources[1].name)
suite.check("each says how many in how many kills", first.sources[1].dropText == "14 in 1200",
    first.sources[1].dropText)

--------------------------------------------------------------------------------
-- The setting
--------------------------------------------------------------------------------

ns.HandleSlash("worlddrops off")
suite.check("/farm worlddrops off turns it off", ns.db.worldDrops == false)
suite.check("the open mob says nothing", WorldDrops:CardLines("Witchwing Slayer") == nil)
_G.UnitLevel = function() return 16 end
suite.check("nor the tooltip", ns.KillTooltip:GreensLine("mouseover") == nil)
suite.check("nor Rankings", ns.RankingsUI:WorldRows() == nil)
local plain = ns.Search:Run("greens")
suite.check("nor the search", not (plain[1] and plain[1].item.worldDrops))
ns.HandleSlash("worlddrops on")
suite.check("/farm worlddrops on turns it back on", ns.db.worldDrops == true)

local printed = {}
local realPrint = ns.Print
ns.Print = function(text) printed[#printed + 1] = text end
ns.HandleSlash("worlddrops")
ns.Print = realPrint
local said = table.concat(printed, "\n")
suite.check("/farm worlddrops lists the bands", said:find("Levels 15-19: green gear 1 in 92 kills", 1, true),
    said)

ns.WorldDrops.Forget()
suite.check("forgetting writes no global", rawget(_G, "mobInfo") == nil)

suite.done()
