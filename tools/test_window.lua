-- The window, built against a stub client.
--
-- It cannot prove anything about how the frames look, but it does prove the
-- wiring: that typing reaches the search, that results reach the right
-- columns, that the filters and the collapsing narrow what is drawn, and that
-- scrolling stops at both ends instead of running off into blank space.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("window")

local ns = env.Load({ ui = true })
local UI = ns.UI
local Util = ns.Util

UI:Build()

suite.check("the window starts hidden", not UI.frame:IsShown())
suite.check("it has a search box", UI.searchBox ~= nil)
suite.check("it has a result list", UI.list ~= nil)

--------------------------------------------------------------------------------
-- Searching
--------------------------------------------------------------------------------

UI:Search("wool cloth")

suite.check("searching shows the window", UI.frame:IsShown())
suite.check("the search box holds the query",
    UI.searchBox:GetText() == "wool cloth", UI.searchBox:GetText())

local data = UI.list.data
suite.check("results reach the list", #data > 1, #data)
suite.check("the first row is the item heading", data[1].type == "item", data[1].type)

local sourceRows = 0
for _, row in ipairs(data) do
    if row.type == "source" then sourceRows = sourceRows + 1 end
end

suite.check("every source is drawn", sourceRows == #ns.DB:GetItem("Wool Cloth").sources,
    sourceRows)

suite.check("the summary counts the matches",
    Util.StripColor(UI.summary:GetText()):find("matching", 1, true) ~= nil,
    UI.summary:GetText())

--------------------------------------------------------------------------------
-- Columns
--------------------------------------------------------------------------------

-- Find the first drawn source row and read what landed in its columns.
local function FirstSourceRow()
    for index = 1, #UI.list.rows do
        local row = UI.list.rows[index]
        if row.data and row.data.type == "source" and row:IsShown() then
            return row
        end
    end
end

local row = FirstSourceRow()
suite.check("a source row is drawn", row ~= nil)

suite.check("the source column names the mob",
    row.name:GetText() == row.data.source.name,
    row.name:GetText())

suite.check("the where column names the zone",
    Util.StripColor(row.where:GetText()):find(row.data.source.zone, 1, true) ~= nil,
    row.where:GetText())

suite.check("the where column names the landmark",
    Util.StripColor(row.where:GetText()):find(row.data.source.location, 1, true) ~= nil,
    row.where:GetText())

suite.check("the level column shows the band",
    row.level:GetText() == ns.Search:LevelText(row.data.source),
    row.level:GetText())

suite.check("the drop column shows the rate",
    row.drop:GetText() == ("%d%%"):format(row.data.source.chance),
    row.drop:GetText())

suite.check("the kind column is tagged", row.kind:GetText() == "MOB", row.kind:GetText())

-- Sources that carry no drop rate must not leave the previous row's rate
-- behind them: rows are recycled, so anything not reset is a ghost.
UI:Search("copper ore")
local oreRow = FirstSourceRow()

suite.check("a node row hides the drop bar", not oreRow.dropFill:IsShown())
suite.check("a node row shows what it needs instead",
    Util.StripColor(oreRow.drop:GetText()):find("Mining", 1, true) ~= nil,
    oreRow.drop:GetText())

--------------------------------------------------------------------------------
-- Collapsing
--------------------------------------------------------------------------------

UI:Search("wool cloth")
local expanded = #UI.list.data

UI:OnRowClick({ type = "item", item = ns.DB:GetItem("Wool Cloth") })
suite.check("collapsing hides the sources", #UI.list.data < expanded, #UI.list.data)
suite.check("collapsing keeps the heading", UI.list.data[1].type == "item")

UI:OnRowClick({ type = "item", item = ns.DB:GetItem("Wool Cloth") })
suite.check("expanding brings them back", #UI.list.data == expanded, #UI.list.data)

--------------------------------------------------------------------------------
-- Filter chips
--------------------------------------------------------------------------------

-- A zone search turns up several kinds, so there is a real choice to make.
UI:Search("un'goro")

local shownChips = 0
for _, chip in ipairs(UI.chips) do
    if chip:IsShown() then shownChips = shownChips + 1 end
end

suite.check("a mixed search offers filters", shownChips > 1, shownChips)
suite.check("the first chip is ALL", UI.chips[1].label:GetText() == "ALL")
suite.check("ALL starts selected", UI.chips[1].selected == true)

local allRows = #UI.list.data

UI.filterKind = "mob"
UI:Render()

local mobOnly = true
for _, entry in ipairs(UI.list.data) do
    if entry.type == "source" and entry.source.kind ~= "mob" then
        mobOnly = false
    end
end

suite.check("filtering to mobs drops the other kinds", mobOnly)
suite.check("filtering narrows the list", #UI.list.data < allRows, #UI.list.data)

-- An item left with nothing after filtering must not leave a bare heading.
local headings, sources = 0, 0
for _, entry in ipairs(UI.list.data) do
    if entry.type == "item" then headings = headings + 1 end
    if entry.type == "source" then sources = sources + 1 end
end
suite.check("no heading is left without sources", sources >= headings,
    ("%d headings, %d sources"):format(headings, sources))

UI.filterKind = nil
UI:Render()
suite.check("clearing the filter restores the list", #UI.list.data == allRows)

-- A new search is not the old search's filter.
UI.filterKind = "mob"
UI:Search("copper ore")
suite.check("a new search clears the filter", UI.filterKind == nil)

--------------------------------------------------------------------------------
-- Clicking a row
--------------------------------------------------------------------------------

UI:Search("wool cloth")

local before = #env.chat
local clicked
for _, entry in ipairs(UI.list.data) do
    if entry.type == "source" then clicked = entry break end
end

UI:OnRowClick(clicked)
suite.check("clicking a source prints it", #env.chat > before)

local printed = Util.StripColor(env.chat[#env.chat])
suite.check("the printed line names the item",
    printed:find("Wool Cloth", 1, true) ~= nil, printed)
suite.check("the printed line names the mob",
    printed:find(clicked.source.name, 1, true) ~= nil, printed)
suite.check("the printed line carries the coordinates",
    not clicked.source.coords
        or printed:find(("%.1f"):format(clicked.source.coords[1]), 1, true) ~= nil,
    printed)

--------------------------------------------------------------------------------
-- Resting state
--------------------------------------------------------------------------------

UI:Search("")
suite.check("an empty query clears the list", #UI.list.data == 0)
suite.check("an empty query still says what is loaded",
    Util.StripColor(UI.summary:GetText()):find("item", 1, true) ~= nil,
    UI.summary:GetText())

local noChips = true
for _, chip in ipairs(UI.chips) do
    if chip:IsShown() then noChips = false end
end
suite.check("an empty query offers no filters", noChips)

--------------------------------------------------------------------------------
-- Scrolling
--------------------------------------------------------------------------------

local rows = {}
for index = 1, 100 do rows[index] = { type = "more", text = "line " .. index } end

UI.list:SetData(rows)
suite.check("a fresh list starts at the top", UI.list.offset == 0)

UI.list:Scroll(-1)
suite.check("the wheel scrolls down", UI.list.offset == 3, UI.list.offset)

UI.list:Scroll(1)
suite.check("the wheel scrolls back up", UI.list.offset == 0, UI.list.offset)

UI.list:Scroll(5)
suite.check("scrolling stops at the top", UI.list.offset == 0, UI.list.offset)

UI.list:Scroll(-500)
suite.check("scrolling stops at the end",
    UI.list.offset == UI.list:MaxOffset(), UI.list.offset)

UI.list:SetData({ { type = "more", text = "one" } })
UI.list:Scroll(-10)
suite.check("a short list does not scroll", UI.list.offset == 0, UI.list.offset)

--------------------------------------------------------------------------------
-- Showing and hiding
--------------------------------------------------------------------------------

UI:Hide()
suite.check("hiding hides", not UI.frame:IsShown())

UI:Toggle()
suite.check("toggle opens", UI.frame:IsShown())

UI:Toggle()
suite.check("toggle closes", not UI.frame:IsShown())

--------------------------------------------------------------------------------
-- Position
--------------------------------------------------------------------------------

UI:SavePosition()
suite.check("the position is saved", ns.db.point == "CENTER", ns.db.point)

ns.db.x, ns.db.y = 120, -60
UI:RestorePosition()
suite.check("a saved position survives a restore", ns.db.x == 120)

--------------------------------------------------------------------------------
-- Slash commands
--------------------------------------------------------------------------------

local run = SlashCmdList["BLACKTHORNESFARMER"]
suite.check("the slash command is registered", type(run) == "function")

local function ChatSince(fn)
    local start = #env.chat
    fn()
    return #env.chat - start
end

suite.check("/farm help prints", ChatSince(function() run("help") end) > 0)
suite.check("/farm stats prints", ChatSince(function() run("stats") end) > 0)
suite.check("/farm data prints", ChatSince(function() run("data") end) > 0)
suite.check("/farm list prints", ChatSince(function() run("list") end) > 0)
suite.check("/farm chat prints results",
    ChatSince(function() run("chat wool cloth") end) > 1)

run("mithril")
suite.check("/farm <query> searches",
    UI.searchBox:GetText() == "mithril", UI.searchBox:GetText())

run("linen cloth")
suite.check("/farm <two word query> keeps both words",
    UI.searchBox:GetText() == "linen cloth", UI.searchBox:GetText())


--------------------------------------------------------------------------------
-- Recycled rows do not carry the last row's colours
--
-- Rows are reused as the list scrolls, so anything set on one row type and not
-- reset on another shows up as a ghost: an item heading drawn in the muted
-- grey of the note that used the row before it.
--------------------------------------------------------------------------------

local function ColorOf(label)
    return label._color and table.concat(label._color, ",") or "unset"
end

local probe = env.Stub()
UI:CreateRow(probe)

UI:UpdateRow(probe, { type = "note", text = "a note" })
local noteColor = ColorOf(probe.heading)

UI:UpdateRow(probe, { type = "item", item = ns.DB:GetItem("Wool Cloth"), count = 3 })
local itemColor = ColorOf(probe.heading)

suite.check("an item heading is not left in the note's colour",
    itemColor ~= noteColor, itemColor)

-- Same story for the drop column: a 45% row followed by a node row.
UI:UpdateRow(probe, {
    type = "source",
    item = ns.DB:GetItem("Wool Cloth"),
    source = ns.DB:GetItem("Wool Cloth").sources[1],
})
local chanceColor = ColorOf(probe.drop)

UI:UpdateRow(probe, {
    type = "source",
    item = ns.DB:GetItem("Copper Ore"),
    source = ns.DB:GetItem("Copper Ore").sources[1],
})

suite.check("a node row is not left in the drop rate's colour",
    ColorOf(probe.drop) ~= chanceColor, ColorOf(probe.drop))

--------------------------------------------------------------------------------
-- Escape closes the windows through the game's own list, not by taking the
-- keyboard: SetPropagateKeyboardInput is protected in combat.
--------------------------------------------------------------------------------

local function Listed(name)
    for _, listed in ipairs(_G.UISpecialFrames) do
        if listed == name then return true end
    end
    return false
end

ns.SettingsUI:Build()
suite.check("the search window closes on Escape", Listed("BlackthornesFarmerFrame"))
suite.check("so does the settings window", Listed("BlackthornesFarmerSettings"))
suite.check("neither takes the keyboard",
    ns.UI.frame:GetScript("OnKeyDown") == nil
        and ns.SettingsUI.frame:GetScript("OnKeyDown") == nil)

suite.done()
