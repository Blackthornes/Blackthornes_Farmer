-- Sorting and grouping a search's spots.
--
-- A player's request (2026-10-05): sort by drop rate and by worth per kill,
-- section by zone, and find what is closest. What matters: each heading
-- sorts every item's spots and turns round on a second click; a spot with
-- nothing to sort by goes last either way, never guessed at; your own tally's
-- worth ranks ahead of estimates; "closest" puts your zone first, then zones
-- by how near their levels are to yours; By zone sections the spots; and the
-- choices are kept for the next session.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("searchsort")

local ns = env.Load({ ui = true })
local Search, UI = ns.Search, ns.UI

-- Vendor prices, so mobs have a worth from the database's rates.
_G.C_Item = { GetItemInfo = function(id)
    return "item", nil, 1, 1, 1, "", "", 1, "", "", id == 2589 and 13 or 0
end }

--------------------------------------------------------------------------------
-- The logic
--------------------------------------------------------------------------------

local spots = {
    { name = "A", zone = "Westfall", minLevel = 10, maxLevel = 12, chance = 20 },
    { name = "B", zone = "Silverpine Forest", minLevel = 30, maxLevel = 32, chance = 5 },
    { name = "C", zone = "Duskwood", minLevel = 24, maxLevel = 26 },
    { name = "D", zone = "Westfall", minLevel = 14, maxLevel = 15, chance = 40 },
}

local function Names(list)
    local names = {}
    for index, source in ipairs(list) do names[index] = source.name end
    return table.concat(names, "")
end

suite.check("no sort leaves them as they are", Names(Search:SortSources(spots, nil)) == "ABCD")
suite.check("drop rate, best first, unknown last",
    Names(Search:SortSources(spots, { key = "drop" })) == "DABC", Names(Search:SortSources(spots, { key = "drop" })))
suite.check("turned round, the unknown is still last",
    Names(Search:SortSources(spots, { key = "drop", ascending = true })) == "BADC")

-- The player is level 25 in Silverpine Forest (testenv).
suite.check("closest: your zone first, then nearest your level",
    Names(Search:SortSources(spots, { key = "where", ascending = true })) == "BCDA",
    Names(Search:SortSources(spots, { key = "where", ascending = true })))
suite.check("a band you are inside is no distance",
    Search.Distance(spots[3], 25, "Elwynn Forest") == 1000)

-- Worth: your own 20+ kills come before any estimate.
local measured = { name = "Measured Mob", zone = "Westfall", minLevel = 10, chance = 1 }
local tally = ns.Tracker:GetMob("Measured Mob")
tally.kills, tally.coinKills, tally.copper = 20, 20, 20
local cache = {}
local worth, sure = Search:Worth(measured, cache)
suite.check("a mob you have killed 20 times is worth what you saw", worth == 1 and sure == 2, worth)
local estimated = { name = "Defias Trapper", zone = "Westfall", minLevel = 12, chance = 38 }
local estimate, how = Search:Worth(estimated, cache)
suite.check("a mob from the database's rates is an estimate", estimate and how == 1, estimate)
local node = { kind = "herb", zone = "Westfall", minLevel = 1 }
suite.check("a node has no worth per kill", Search:Worth(node, cache) == nil)
local byWorth = Search:SortSources({ node, estimated, measured }, { key = "value" }, cache)
suite.check("measured worth leads, even when it is less",
    byWorth[1] == measured and byWorth[2] == estimated and byWorth[3] == node)

local groups = Search.ByZone(Search:SortSources(spots, { key = "drop" }))
suite.check("by zone: zones in the order of their best spot",
    #groups == 3 and groups[1].zone == "Westfall" and #groups[1].sources == 2
    and groups[2].zone == "Silverpine Forest" and groups[3].zone == "Duskwood")

--------------------------------------------------------------------------------
-- The window
--------------------------------------------------------------------------------

UI:Build()
UI:Search("linen cloth")

local function SourceRows()
    local list = {}
    for _, data in ipairs(UI.list.data) do
        if data.type == "source" then list[#list + 1] = data end
    end
    return list
end

local function Click(key)
    UI.sorter.buttons[key]:GetScript("OnClick")(UI.sorter.buttons[key])
end

suite.check("every heading but the tag sorts",
    UI.sorter.buttons.name and UI.sorter.buttons.where and UI.sorter.buttons.level
    and UI.sorter.buttons.drop and UI.sorter.buttons.value and not UI.sorter.buttons.kind)

Click("drop")
local rows = SourceRows()
local ordered = true
for index = 2, #rows do
    local before, now = rows[index - 1].source.chance, rows[index].source.chance
    if now and (not before or before < now) then ordered = false end
end
suite.check("DROP sorts the window's spots best first", ordered and #rows > 3)
suite.check("and is kept", ns.db.searchSort.key == "drop" and ns.db.searchSort.ascending == false)
suite.check("the heading is lit with its arrow", UI.sorter.buttons.drop.arrow:IsShown())

Click("drop")
suite.check("a second click turns it round", ns.db.searchSort.ascending == true)
Click("drop")
suite.check("a third gives back the usual order", ns.db.searchSort.key == nil)

-- Hovering a heading says what it does.
GameTooltip._lines = {}
UI.sorter.buttons.where:GetScript("OnEnter")(UI.sorter.buttons.where)
suite.check("a heading has a tooltip", (GameTooltip._lines[1] or ""):find("Closest", 1, true) ~= nil,
    GameTooltip._lines[1])
UI.sorter.buttons.where:GetScript("OnLeave")(UI.sorter.buttons.where)

-- Worth shows in its own column, in coin colours.
local shown
for _, data in ipairs(SourceRows()) do
    if UI:WorthText(data.source) then shown = UI:WorthText(data.source) break end
end
suite.check("a mob's worth shows, coloured", shown and shown:find("|cffeda55f", 1, true) ~= nil, shown)
suite.check("the worth column fits it", UI.columns.value.w >= ns.Theme.TextWidth("small", shown))

-- By zone.
UI.byZoneChip:GetScript("OnClick")(UI.byZoneChip)
suite.check("By zone is kept", ns.db.searchByZone == true)
local zones, before = 0, nil
for _, data in ipairs(UI.list.data) do
    if data.type == "zone" then zones = zones + 1 end
    if data.type == "source" and before then
        suite.check("each spot sits under its own zone", data.source.zone == before.zone or before.type == "zone")
    end
    if data.type == "zone" then before = { type = "zone", zone = data.zone } end
    if data.type == "source" then
        suite.check("a spot sits in its zone's section", data.source.zone == before.zone,
            data.source.zone .. " under " .. tostring(before.zone))
    end
end
suite.check("zone sections are drawn", zones > 1, zones)

-- Folding an item folds its zones too.
local item = UI.list.data[1]
UI:OnRowClick(item)
local left = 0
for _, data in ipairs(UI.list.data) do
    if data.type == "zone" and data.item == item.item then left = left + 1 end
end
suite.check("a folded item hides its zone rows", left == 0, left)

UI.byZoneChip:GetScript("OnClick")(UI.byZoneChip)
suite.check("and off again", ns.db.searchByZone == false)

_G.C_Item = nil

suite.done()
