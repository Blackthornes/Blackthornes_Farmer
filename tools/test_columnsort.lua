-- Every column title sorts its list (a player's request, 2026-10-11).
--
-- What matters: the loot table and the Rankings tab sort by any heading the
-- way the search does (first click one way, second turns it round, third
-- gives back the usual order), rows with nothing to sort by go last, the
-- Rankings boards stay apart with their ranks unchanged, the choice is kept
-- for the next session, and a click only re-orders what is already built.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("columnsort")

local ns = env.Load({ ui = true })
local Util, Tracker = ns.Util, ns.Tracker
local LTU, RankingsUI, UI = ns.LootTableUI, ns.RankingsUI, ns.UI

_G.C_Item = { GetItemInfo = function(id)
    return "item", nil, 1, 1, 1, "", "", 1, "", "", ({ [2934] = 5, [5637] = 10 })[id] or 0
end }
_G.BlackthornesTS = { Prices = { GetValue = function(_, id)
    return ({ [5637] = 50, [2934] = 3, [99001] = 200 })[id]
end } }

--------------------------------------------------------------------------------
-- The shared sort
--------------------------------------------------------------------------------

local items = { { n = "b", v = 2 }, { n = "a" }, { n = "C", v = 9 }, { n = "d", v = 2 } }
local function Order(list)
    local out = {}
    for _, item in ipairs(list) do out[#out + 1] = item.n end
    return table.concat(out)
end
suite.check("biggest first, nothing-to-sort-by last, ties as they came",
    Order(Util.SortBy(items, false, function(i) return i.v end)) == "Cbda",
    Order(Util.SortBy(items, false, function(i) return i.v end)))
suite.check("turned round, the empty one is still last",
    Order(Util.SortBy(items, true, function(i) return i.v end)) == "bdCa")
suite.check("names sort A to Z whatever their case",
    Order(Util.SortBy(items, true, function(i) return i.n end)) == "abCd")
suite.check("the list itself is left alone", Order(items) == "baCd")

--------------------------------------------------------------------------------
-- The loot table
--------------------------------------------------------------------------------

local serial = 0
local function Loot(mob, loot)
    serial = serial + 1
    env.world.target = { name = mob, level = 8, dead = true, guid = "S-" .. serial }
    env.world.loot = loot
    Tracker:OnLoot()
end

local FANG = { name = "Large Fang", id = 5637 }
local SCRAPS = { name = "Ruined Leather Scraps", id = 2934, quantity = 3 }
local PAW = { name = "Wolf Paw", id = 1001 }
local COINS = { name = "12 Copper", money = true }

for index = 1, Tracker.MIN_KILLS do
    Loot("Mangy Wolf", { COINS, PAW, index <= 4 and SCRAPS or nil, index <= 8 and FANG or nil })
    Loot("Kobold Vermin", { COINS })
end

LTU:Show("Mangy Wolf")
local function LootNames()
    local out = {}
    for _, row in ipairs(LTU.list.data) do out[#out + 1] = row.name end
    return table.concat(out, ",")
end
suite.check("the usual order is most common first",
    LootNames() == "Wolf Paw,Large Fang,Ruined Leather Scraps", LootNames())

local buttons = LTU.sorter and LTU.sorter.buttons or {}
suite.check("every column title sorts",
    buttons.name and buttons.dropped and buttons.total and buttons.rate and buttons.perKill)

local function Click(sorter, key) sorter.buttons[key]:GetScript("OnClick")(sorter.buttons[key]) end

local built = 0
local realTable = LTU.Table
LTU.Table = function(...) built = built + 1 return realTable(...) end

Click(LTU.sorter, "total")
suite.check("TOTAL sorts by how many were taken, most first",
    LootNames() == "Wolf Paw,Ruined Leather Scraps,Large Fang", LootNames())
suite.check("and is kept", ns.db.lootTableSort.key == "total" and ns.db.lootTableSort.ascending == false)
suite.check("the title wears its arrow", buttons.total.arrow:IsShown())
Click(LTU.sorter, "total")
suite.check("a second click turns it round",
    LootNames() == "Large Fang,Ruined Leather Scraps,Wolf Paw", LootNames())
Click(LTU.sorter, "total")
suite.check("a third gives back the usual order", ns.db.lootTableSort == nil
    and LootNames() == "Wolf Paw,Large Fang,Ruined Leather Scraps", LootNames())
Click(LTU.sorter, "name")
suite.check("ITEM sorts A to Z", LootNames() == "Large Fang,Ruined Leather Scraps,Wolf Paw", LootNames())
Click(LTU.sorter, "perKill")
suite.check("PER KILL puts the unpriced paw last",
    LootNames() == "Large Fang,Ruined Leather Scraps,Wolf Paw", LootNames())
suite.check("sorting never reads the tally again", built == 0, built)
LTU.Table = realTable

-- New loot redraws in the chosen order.
Loot("Mangy Wolf", { PAW })
LTU:Render()
suite.check("a redraw keeps the sort", LootNames():find("Wolf Paw$") ~= nil, LootNames())

--------------------------------------------------------------------------------
-- The Rankings tab
--------------------------------------------------------------------------------

ns.DB:RegisterItem({ name = "Ogre Tooth", id = 99001, category = "misc",
    sources = { { name = "Test Ogre", zone = "Nowhere", minLevel = 30, maxLevel = 32, chance = 40 } } })

UI:Build()
UI:Show()
UI:ShowTab("rankings")

local function Measured()
    local out, on = {}, false
    for _, row in ipairs(RankingsUI.list.data) do
        if row.type == "heading" then on = row.group == "measured"
        elseif on and row.entry then out[#out + 1] = row.entry.mob .. row.entry.rank end
    end
    return table.concat(out, ",")
end

suite.check("the board starts best first", Measured() == "Mangy Wolf1,Kobold Vermin2", Measured())

local rb = RankingsUI.sorter and RankingsUI.sorter.buttons or {}
suite.check("every heading sorts", rb.rank and rb.mob and rb.worth and rb.basis
    and rb.best and rb.where and rb.level)

local builds = 0
local realBuild = ns.Rankings.Build
ns.Rankings.Build = function(...) builds = builds + 1 return realBuild(...) end

Click(RankingsUI.sorter, "mob")
suite.check("MOB sorts each board A to Z, ranks kept",
    Measured() == "Kobold Vermin2,Mangy Wolf1", Measured())
suite.check("and is kept", ns.db.rankingsSort.key == "mob" and ns.db.rankingsSort.ascending == true)
local estimateAfter = false
for _, row in ipairs(RankingsUI.list.data) do
    if row.type == "heading" and row.group == "estimate" then estimateAfter = true end
end
suite.check("the boards stay apart", estimateAfter)
suite.check("sorting never rebuilds the board", builds == 0, builds)
ns.Rankings.Build = realBuild

-- The bars still measure against the board's best.
local kobold
for _, row in ipairs(RankingsUI.list.data) do
    if row.entry and row.entry.mob == "Kobold Vermin" then kobold = row end
end
suite.check("a bar measures against the best, wherever it sorts",
    kobold and kobold.top == ns.Value:ForMob("Mangy Wolf"), kobold and kobold.top)

Click(RankingsUI.sorter, "mob")
Click(RankingsUI.sorter, "mob")
suite.check("a third click gives the usual order back",
    ns.db.rankingsSort == nil and Measured() == "Mangy Wolf1,Kobold Vermin2", Measured())

suite.done()
