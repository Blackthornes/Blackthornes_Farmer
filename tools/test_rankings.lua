-- The Rankings tab: mobs by what a kill is worth.
--
-- What matters: measured values and estimates are ranked on separate boards
-- and never mixed, each board runs best first, a mob below MIN_KILLS with no
-- estimate waits under "not ranked yet" with how far it has to go, and the tab
-- sits in the main window beside the search, remembered between openings.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("rankings")

local ns = env.Load({ ui = true })
local Rankings = ns.Rankings
local RankingsUI = ns.RankingsUI
local Tracker = ns.Tracker
local UI = ns.UI

local VENDOR = { [5637] = 10, [2934] = 5 }

_G.C_Item = {
    GetItemInfo = function(id)
        return "item", nil, 1, 1, 1, "", "", 1, "", "", VENDOR[id] or 0
    end,
}

local AUCTION = { [5637] = 50, [2934] = 3, [99001] = 200, [99002] = 20 }

_G.BlackthornesTS = {
    Prices = { GetValue = function(_, id) return AUCTION[id] end },
}

local serial = 0

local function Loot(mob, items)
    serial = serial + 1
    env.world.target = { name = mob, level = 8, dead = true, guid = "R-" .. serial }
    env.world.loot = items
    Tracker:OnLoot()
end

local FANG = { name = "Large Fang", id = 5637 }
local SCRAPS = { name = "Ruined Leather Scraps", id = 2934, quantity = 2 }
local COINS = { name = "12 Copper", money = true }

-- Two measured mobs, one worth more than the other.
for index = 1, 20 do
    Loot("Mangy Wolf", { COINS, SCRAPS, index <= 5 and FANG or nil })
    Loot("Kobold Vermin", { COINS })
end

-- One started on, not yet ranked.
for _ = 1, 7 do Loot("Defias Thug", { COINS }) end

-- Two database estimates; the richer one is worth more than either measured
-- mob, which is exactly why the boards must stay apart.
ns.DB:RegisterItem({ name = "Ogre Tooth", id = 99001, category = "misc",
    sources = { { name = "Test Ogre", zone = "Nowhere", location = "The Hill",
        minLevel = 30, maxLevel = 32, chance = 40 } } })
ns.DB:RegisterItem({ name = "Troll Tusk", id = 99002, category = "misc",
    sources = { { name = "Test Troll", zone = "Elsewhere", minLevel = 20, chance = 10 } } })

--------------------------------------------------------------------------------
-- The board
--------------------------------------------------------------------------------

local board = Rankings:Build()

local function Names(list)
    local names = {}
    for _, entry in ipairs(list) do names[#names + 1] = entry.mob end
    return table.concat(names, ", ")
end

suite.check("measured mobs are ranked best first",
    Names(board.measured) == "Mangy Wolf, Kobold Vermin", Names(board.measured))
suite.check("estimates are ranked best first on their own board",
    Names(board.estimate):find("^Test Ogre, Test Troll") ~= nil, Names(board.estimate))
suite.check("a measured mob is never on the estimate board",
    not Names(board.estimate):find("Mangy Wolf", 1, true), Names(board.estimate))
suite.check("ranks restart on each board",
    board.measured[1].rank == 1 and board.estimate[1].rank == 1)
suite.check("the measured value is Value's own",
    board.measured[1].value == ns.Value:ForMob("Mangy Wolf"), board.measured[1].value)
suite.check("a measured mob counts its kills", board.measured[1].kills == 20, board.measured[1].kills)
-- Fang: 5 in 20 at 50c is 12.5c a kill; scraps: 2 a kill at 5c is 10c.
suite.check("its best drop is the one worth most per kill",
    board.measured[1].best and board.measured[1].best.name == "Large Fang",
    board.measured[1].best and board.measured[1].best.name)

suite.check("a mob short of the kills waits unranked",
    Names(board.pending) == "Defias Thug", Names(board.pending))
suite.check("with how many kills it still needs",
    board.pending[1].needed == Tracker.MIN_KILLS - 7, board.pending[1].needed)

local ogre = board.estimate[1]
suite.check("an estimate says where the database puts it",
    ogre.where == "Nowhere, The Hill", ogre.where)
suite.check("and at what level", ogre.level == "30-32", ogre.level)

-- A measured mob the database has no row for still shows the levels you
-- met it at, from your own loot records.
suite.check("a mob only you have measured has no database spot",
    board.measured[1].spot == nil)
ns.Harvest:GetRecord("Mangy Wolf", 7, "Elwynn Forest")
ns.Harvest:GetRecord("Mangy Wolf", 9, "Elwynn Forest", "Northshire")
ns.Harvest.changes = (ns.Harvest.changes or 0) + 1
local wolf = Rankings:Entry("Mangy Wolf")
suite.check("its level comes from the levels you met it at",
    wolf.level == "7-9", wolf.level)
suite.check("and sorts by the lowest", wolf.minLevel == 7, wolf.minLevel)

-- Your own levels win over the database's, as where you farm it does.
ns.Harvest:GetRecord("Test Ogre", 28, "Nowhere", "The Hill")
ns.Harvest.changes = ns.Harvest.changes + 1
suite.check("your levels win over the database's",
    Rankings:Entry("Test Ogre").level == "28", Rankings:Entry("Test Ogre").level)
suite.check("a mob you never met keeps the database's level",
    Rankings:Entry("Test Troll").level == "20", Rankings:Entry("Test Troll").level)

-- Twenty kills of something nobody will pay for.
for _ = 1, 20 do Loot("Pauper Rat", { { name = "Rat Whisker", id = 99999 } }) end
local rat = Rankings:Entry("Pauper Rat")
suite.check("enough kills with nothing priced waits on prices",
    rat and rat.group == "pending" and rat.unpriced, rat and rat.group)

suite.check("a mob with no value and no kills is nowhere",
    Rankings:Entry("Nobody At All") == nil)

--------------------------------------------------------------------------------
-- The tab
--------------------------------------------------------------------------------

UI:Build()

suite.check("the window has a Rankings tab", UI.tabs.rankings ~= nil)
suite.check("it opens on Search", UI.tab == "search" and UI.tabs.search.selected)

UI:Show()
UI:ShowTab("rankings")

suite.check("choosing Rankings shows its view", UI.rankingsView:IsShown())
suite.check("and hides the search", not UI.searchView:IsShown())
suite.check("the tab is marked", UI.tabs.rankings.selected and not UI.tabs.search.selected)
suite.check("it is remembered", ns.db.lastTab == "rankings", ns.db.lastTab)

local rows = RankingsUI.list.data

local function Kinds()
    local out = {}
    for _, row in ipairs(rows) do
        out[#out + 1] = row.type == "heading" and row.group or (row.entry and row.entry.mob) or row.type
    end
    return table.concat(out, " | ")
end

suite.check("the boards are drawn under their own headings, measured first",
    Kinds():find("^measured | Mangy Wolf | Kobold Vermin | estimate | Test Ogre") ~= nil
        and Kinds():find("pending | .*Defias Thug$") ~= nil, Kinds())

-- Read the first drawn mob row.
local function DrawnRow(mob)
    for _, row in ipairs(RankingsUI.list.rows) do
        if row:IsShown() and row.data and row.data.entry and row.data.entry.mob == mob then
            return row
        end
    end
end

local wolf = DrawnRow("Mangy Wolf")
suite.check("a measured row shows its rank", wolf and wolf.rank:GetText() == "1")
suite.check("and its worth", wolf and wolf.worth:GetText() == ns.Value.Coins(board.measured[1].value),
    wolf and wolf.worth:GetText())
suite.check("and its kills", wolf and wolf.basis:GetText() == "20 kills", wolf and wolf.basis:GetText())

local ogreRow = DrawnRow("Test Ogre")
suite.check("an estimate's worth is marked as approximate",
    ogreRow and ogreRow.worth:GetText():sub(1, 1) == "~", ogreRow and ogreRow.worth:GetText())
suite.check("and says it is an estimate", ogreRow and ogreRow.basis:GetText() == "estimate")

local thug = DrawnRow("Defias Thug")
suite.check("an unranked row has no rank", thug and not thug.rank:IsShown())
suite.check("and says how far it has to go",
    thug and thug.worth:GetText() == ("%d more to go"):format(Tracker.MIN_KILLS - 7),
    thug and thug.worth:GetText())

suite.check("the prices are named",
    RankingsUI.summary:GetText():find("auction", 1, true) ~= nil, RankingsUI.summary:GetText())

-- Filters.
RankingsUI.group = "estimate"
RankingsUI:Render()
rows = RankingsUI.list.data
suite.check("the Estimates filter shows only estimates",
    not Kinds():find("measured", 1, true) and Kinds():find("^estimate") ~= nil, Kinds())

RankingsUI.group = "measured"
RankingsUI:Render()
rows = RankingsUI.list.data
suite.check("the Measured filter leaves estimates out",
    not Kinds():find("estimate", 1, true), Kinds())
RankingsUI.group = nil

-- The columns stay put as the chips change (2026-10-22): they are measured
-- on the whole board, not only the rows a chip shows.
local function ColumnWidths()
    local list = {}
    for key, column in pairs(RankingsUI.columns) do
        if type(column) == "table" and column.w then list[#list + 1] = key .. "=" .. column.w end
    end
    table.sort(list)
    return table.concat(list, " ")
end
RankingsUI:Render()
local allWidths = ColumnWidths()
RankingsUI.group = "estimate"
RankingsUI:Render()
local estimateWidths = ColumnWidths()
RankingsUI.group = "measured"
RankingsUI:Render()
local measuredWidths = ColumnWidths()
RankingsUI.group = nil
RankingsUI:Render()
suite.check("a chip leaves the column widths as they were",
    allWidths == estimateWidths and allWidths == measuredWidths,
    allWidths .. " | " .. estimateWidths .. " | " .. measuredWidths)

-- Text fits: a long mob name widens its column rather than being cut off,
-- on a screen with room for it.
UIParent._width = 1920
local long = "Venture Co. Deforestation Supervisor Extraordinaire"
for _ = 1, 20 do Loot(long, { COINS }) end
RankingsUI:Render()
-- The stub measures 6px a character, so this one wants more than the cap.
suite.check("a long name widens the mob column, up to its cap",
    RankingsUI.columns.mob.w == 300, RankingsUI.columns.mob.w)
suite.check("and the window with it",
    UI.frame:GetWidth() >= RankingsUI.columns.total + 74, UI.frame:GetWidth())

-- Never wider than the screen, as the search tab: the widest columns give
-- the room back first (0.12.0 capped the search tab and missed this one).
UIParent._width = 900
RankingsUI:Render()
suite.check("on a narrow screen the window still fits",
    UI.frame:GetWidth() <= UI:ScreenRoom(), UI.frame:GetWidth() .. " > " .. tostring(UI:ScreenRoom()))
suite.check("the long name gives the room back", RankingsUI.columns.mob.w < 300, RankingsUI.columns.mob.w)
UIParent._width = nil

-- A long board's ranks run to three figures; the rank column makes room.
RankingsUI:FitColumns({ { type = "mob", top = 10, entry = { mob = "Test Ogre", group = "estimate",
    rank = 120, value = 5, where = "Nowhere", level = "30" } } })
suite.check("a rank of 120 fits its column",
    RankingsUI.columns.rank.w - 4 >= ns.Theme.TextWidth("small", "120"), RankingsUI.columns.rank.w)

-- The mobs not ranked yet: one short of kills, one with its kills and
-- nothing priced. The heading says what they wait on, not just "keep killing".
local pendingHeading
for _, data in ipairs(RankingsUI.list.data) do
    if data.type == "heading" and data.group == "pending" then pendingHeading = data end
end
suite.check("the waiting mobs' heading names both reasons",
    pendingHeading and pendingHeading.note == "waiting on kills or prices", pendingHeading and pendingHeading.note)
local spare = RankingsUI.list.rows[1]
RankingsUI:UpdateRow(spare, pendingHeading)
suite.check("and draws it", spare.heading:GetText():find("waiting on kills or prices", 1, true) ~= nil,
    spare.heading:GetText())
RankingsUI:Render()

-- A kill while the tab is open redraws it.
for _ = 1, 13 do Loot("Defias Thug", { COINS }) end
ns.TrackerUI:Refresh()
suite.check("a kill that ranks a mob moves it onto the board",
    Names(RankingsUI.board.measured):find("Defias Thug", 1, true) ~= nil,
    Names(RankingsUI.board.measured))

-- Hover and click.
GameTooltip._lines = {}
wolf = DrawnRow("Mangy Wolf")
wolf:GetScript("OnEnter")(wolf)
suite.check("hovering a mob shows its worth",
    (GameTooltip._lines[2] or ""):find("Worth about", 1, true) ~= nil, GameTooltip._lines[2])

--------------------------------------------------------------------------------
-- Getting there and back
--------------------------------------------------------------------------------

UI:Hide()
UI:Toggle()
suite.check("the window reopens on the tab it was left on", UI.tab == "rankings", UI.tab)

UI:Search("wool cloth")
suite.check("a search goes back to the Search tab",
    UI.tab == "search" and UI.searchView:IsShown() and not UI.rankingsView:IsShown())

ns.HandleSlash("rankings")
suite.check("/farm rankings opens the tab", UI.tab == "rankings" and UI.frame:IsShown())

UI:ShowTab("search")
ns.HandleSlash("rank")
suite.check("/farm rank does too", UI.tab == "rankings")

-- A price this client will not let us read costs that item, not the tab.
_G.BlackthornesTS.Prices.GetValue = function() return env.Secret("price") end
local ok, err = pcall(RankingsUI.Render, RankingsUI)
suite.check("a secret price does not break the tab", ok, err)

suite.check("nothing on the tab touched the tally",
    Tracker:Store()["Mangy Wolf"].kills == 20, Tracker:Store()["Mangy Wolf"].kills)

-- The World Drops view draws its own tiles and headings, and puts them away again.
RankingsUI.group = "worlddrops"
RankingsUI:Render()
suite.check("World Drops shows its tiles", RankingsUI.tiles:IsShown())
suite.check("and its own headings", RankingsUI.worldHeadings.level:IsShown())
suite.check("the tiles are named by rarity", RankingsUI.tileFrames[1].name:GetText() == "Uncommon"
    and RankingsUI.tileFrames[4].name:GetText() == "Legendary", RankingsUI.tileFrames[1].name:GetText())
RankingsUI.group = nil
RankingsUI:Render()
suite.check("the mob board hides them again", not RankingsUI.tiles:IsShown())

suite.done()
