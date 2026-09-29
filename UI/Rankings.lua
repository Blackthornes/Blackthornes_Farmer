-- Blackthornes Farmer -- UI/Rankings.lua
-- The Rankings tab of the main window: mobs by what a kill is worth.
--
-- Two boards, never one. Measured values come from your own kills, coin and
-- all; estimates come from the database's rates, one of each drop and no coin,
-- so they run low. Ranked together an estimate would sit under a mob worth
-- less, so each has its own heading, its own ranks and its own colour, and the
-- estimate's number carries a "~" so it cannot pass for a measured one.
--
-- Below the measured board are the mobs you have started on: not ranked yet,
-- with how many kills each still needs.

local _, ns = ...

local RankingsUI = ns.NewModule("RankingsUI")

local Theme = ns.Theme
local Widgets = ns.Widgets
local Util = ns.Util

local PADDING = 14
local ROW_HEIGHT = 20
local COLUMN_GAP = 6
local BAR_WIDTH = 46

-- What the window adds around the columns: padding, the list's insets and its
-- scrollbar. The same as the search tab's, so the two line up.
local CHROME = 74

local COLUMN_ORDER = { "rank", "mob", "worth", "basis", "best", "where", "level" }
local BASE_WIDTH = { rank = 24, mob = 160, worth = 130, basis = 64, best = 130, where = 170, level = 46 }
local MAX_WIDTH = { mob = 300, worth = 200, basis = 110, best = 240, where = 340 }

local FILTERS = {
    { label = "ALL", group = false },
    { label = "MEASURED", group = "measured" },
    { label = "ESTIMATES", group = "estimate" },
}

local HEADINGS = {
    measured = { "YOUR KILLS", "measured, coin included" },
    estimate = { "ESTIMATES", "database drop rates, no coin, so they run low" },
    pending = { "NOT RANKED YET", "keep killing" },
}

--- Column left edges and widths for the given widths.
local function Columns(widths)
    local columns, x = {}, 0

    for _, key in ipairs(COLUMN_ORDER) do
        local w = widths and widths[key] or BASE_WIDTH[key]
        columns[key] = { x = x, w = w }
        x = x + w + COLUMN_GAP
    end

    columns.total = x - COLUMN_GAP
    return columns
end

--------------------------------------------------------------------------------
-- Construction
--------------------------------------------------------------------------------

--- Build the tab's contents into `frame`, the main window. Hidden until the
--- tab is chosen.
function RankingsUI:Build(frame)
    if self.view then return self.view end

    self.group = nil

    local view = CreateFrame("Frame", nil, frame)
    view:SetAllPoints(frame)
    self.view = view

    local filters = CreateFrame("Frame", nil, view)
    filters:SetPoint("TOPLEFT", PADDING, -48)
    filters:SetPoint("TOPRIGHT", -PADDING, -48)
    filters:SetHeight(18)
    self.filters = filters

    self.chips = {}
    local offset = 0

    for index, entry in ipairs(FILTERS) do
        local chip = Widgets.CreateChip(filters, entry.label, function(clicked)
            RankingsUI.group = clicked:GetFilterKind()
            RankingsUI:Render()
        end)
        chip.filterKind = entry.group
        chip:SetWidth(math.max(34, Theme.TextWidth("tiny", entry.label) + 16))
        chip:SetPoint("LEFT", filters, "LEFT", offset, 0)
        offset = offset + chip:GetWidth() + 4
        self.chips[index] = chip
    end

    -- Where the prices come from, on the right of the chips.
    local summary = Theme.CreateLabel(view, "small", "muted", "RIGHT")
    summary:SetPoint("LEFT", filters, "LEFT", offset + 8, 0)
    summary:SetPoint("RIGHT", filters, "RIGHT", -2, 0)
    self.summary = summary

    local panel = Theme.CreatePanel(view, "panel", "border")
    panel:SetPoint("TOPLEFT", filters, "BOTTOMLEFT", 0, -8)
    panel:SetPoint("BOTTOMRIGHT", view, "BOTTOMRIGHT", -PADDING, 36)
    self.panel = panel

    self.headings = {}
    for key, text in pairs({ rank = "#", mob = "MOB", worth = "PER KILL", basis = "FROM",
        best = "BEST DROP", where = "WHERE", level = "LEVEL" }) do
        local justify = (key == "rank" and "RIGHT") or (key == "level" and "CENTER") or nil
        local label = Theme.CreateLabel(panel, "tiny", "dim", justify)
        label:SetText(text)
        self.headings[key] = label
    end

    self.columns = Columns()
    self:PlaceHeadings()

    local rule = Theme.CreateDivider(panel, "border")
    rule:SetPoint("TOPLEFT", 8, -20)
    rule:SetPoint("TOPRIGHT", -8, -20)

    local list = Widgets.CreateRowList(panel, {
        rowHeight = ROW_HEIGHT,
        createRow = function(row) RankingsUI:CreateRow(row) end,
        updateRow = function(row, data, index) RankingsUI:UpdateRow(row, data, index) end,
        onClick = function(data) RankingsUI:OnRowClick(data) end,
        onEnter = function(row, data)
            if data.entry then ns.UI:ShowMobTooltip(row, data.entry.mob) end
        end,
        onLeave = function() if GameTooltip then GameTooltip:Hide() end end,
    })
    list:SetPoint("TOPLEFT", 8, -24)
    list:SetPoint("BOTTOMRIGHT", -8, 8)
    self.list = list

    local footer = Theme.CreateLabel(view, "tiny", "dim")
    footer:SetPoint("BOTTOMLEFT", PADDING, 6)
    footer:SetPoint("BOTTOMRIGHT", -PADDING, 6)
    footer:SetHeight(26)
    footer:SetWordWrap(true)
    footer:SetJustifyV("MIDDLE")
    footer:SetText(("A mob is measured once you have %d kills of it. "
        .. "Hover a mob for what makes up its worth, click it for its loot table.")
        :format(ns.Tracker.MIN_KILLS))
    self.footer = footer

    view:Hide()
    return view
end

function RankingsUI:PlaceHeadings()
    for key, label in pairs(self.headings) do
        local column = self.columns[key]
        label:ClearAllPoints()
        label:SetPoint("TOPLEFT", 8 + column.x, -8)
        label:SetWidth(column.w)
    end
end

--------------------------------------------------------------------------------
-- Rows
--------------------------------------------------------------------------------

-- The top three of each board: gold, silver and bronze.
local MEDALS = {
    { 1.00, 0.82, 0.30 },
    { 0.78, 0.80, 0.84 },
    { 0.80, 0.52, 0.30 },
}
RankingsUI.MEDALS = MEDALS

function RankingsUI:CreateRow(row)
    -- A board's heading sits on a band, as the search tab's items do.
    row.band = row:CreateTexture(nil, "BACKGROUND", nil, 1)
    row.band:SetAllPoints(row)
    row.band:SetColorTexture(Theme.Unpack("header"))

    row.bandStripe = row:CreateTexture(nil, "ARTWORK")
    row.bandStripe:SetPoint("TOPLEFT")
    row.bandStripe:SetPoint("BOTTOMLEFT")
    row.bandStripe:SetWidth(2)
    row.bandStripe:SetColorTexture(Theme.Unpack("accent", 0.8))

    -- A medal behind the top three ranks.
    row.medal = row:CreateTexture(nil, "ARTWORK")
    row.medal:SetSize(16, 14)

    row.heading = Theme.CreateLabel(row, "small", "accent")
    row.heading:SetPoint("LEFT", 8, 0)
    row.heading:SetPoint("RIGHT", -2, 0)

    row.rank = Theme.CreateLabel(row, "small", "dim", "RIGHT")
    row.mob = Theme.CreateLabel(row, "small", "text")

    row.barTrack = row:CreateTexture(nil, "ARTWORK")
    row.barTrack:SetSize(BAR_WIDTH, 6)
    row.barTrack:SetColorTexture(Theme.Unpack("row"))

    row.barFill = row:CreateTexture(nil, "OVERLAY")
    row.barFill:SetHeight(6)

    row.worth = Theme.CreateLabel(row, "small", "good")
    row.basis = Theme.CreateLabel(row, "small", "muted")
    row.best = Theme.CreateLabel(row, "small", "muted")
    row.where = Theme.CreateLabel(row, "small", "muted")
    row.level = Theme.CreateLabel(row, "small", "text", "CENTER")

    self:PlaceRow(row)
end

--- Row `row`'s columns where the current layout puts them.
function RankingsUI:PlaceRow(row)
    local columns = self.columns
    if row.layout == columns then return end
    row.layout = columns

    local function Place(region, key, offset, width)
        region:ClearAllPoints()
        region:SetPoint("LEFT", columns[key].x + (offset or 0), 0)
        region:SetWidth(width or columns[key].w)
    end

    Place(row.rank, "rank", 0, columns.rank.w - 4)
    row.medal:ClearAllPoints()
    row.medal:SetPoint("RIGHT", row, "LEFT", columns.rank.x + columns.rank.w + 1, 0)
    Place(row.mob, "mob")
    Place(row.barTrack, "worth", 0, BAR_WIDTH)
    row.barFill:ClearAllPoints()
    row.barFill:SetPoint("LEFT", columns.worth.x, 0)
    Place(row.worth, "worth", BAR_WIDTH + 6, columns.worth.w - BAR_WIDTH - 6)
    Place(row.basis, "basis")
    Place(row.best, "best")
    Place(row.where, "where")
    Place(row.level, "level")
end

local CELLS = { "rank", "mob", "barTrack", "barFill", "worth", "basis", "best", "where", "level" }

--- The texts a mob's row shows, by column; shared by drawing and fitting.
local function EntryTexts(data)
    local entry = data.entry
    local texts = { mob = entry.mob, where = entry.where or "", level = entry.level or "" }

    if entry.group == "pending" then
        texts.worth = entry.unpriced and "no prices yet"
            or ("%d more to go"):format(entry.needed)
        texts.basis = Util.Plural(entry.kills, "kill")
        texts.best = ""
        return texts
    end

    texts.rank = tostring(entry.rank)
    texts.best = entry.best and entry.best.name or ""

    if entry.group == "measured" then
        texts.worth = ns.Value.Coins(entry.value)
        texts.basis = Util.Plural(entry.kills, "kill")
    else
        texts.worth = "~" .. ns.Value.Coins(entry.value)
        texts.basis = "estimate"
    end

    return texts
end

function RankingsUI:UpdateRow(row, data, index)
    self:PlaceRow(row)

    row.heading:Hide()
    row.band:Hide()
    row.bandStripe:Hide()
    row.medal:Hide()
    for _, key in ipairs(CELLS) do row[key]:Hide() end

    if data.type == "heading" then
        row.band:Show()
        row.bandStripe:Show()
        local heading = HEADINGS[data.group]
        row.heading:SetTextColor(Theme.Unpack("accent"))
        row.heading:SetText(("%s  %s"):format(heading[1],
            Util.Colored("muted", "(" .. heading[2] .. ")")))
        row.heading:Show()
        return
    end

    if data.type == "note" then
        row.heading:SetTextColor(Theme.Unpack("muted"))
        row.heading:SetText("     " .. data.text)
        row.heading:Show()
        return
    end

    local entry = data.entry
    local texts = EntryTexts(data)
    local measured = entry.group == "measured"

    for _, key in ipairs({ "mob", "basis", "best", "where", "level" }) do
        row[key]:SetText(texts[key])
        row[key]:Show()
    end

    row.mob:SetTextColor(Theme.Unpack(entry.group == "pending" and "muted" or "text"))
    row.best:SetTextColor(Theme.Unpack(entry.group == "pending" and "dim" or "muted"))

    if entry.group == "pending" then
        -- No worth yet, so no bar: just how far there is to go.
        row.worth:SetText(texts.worth)
        row.worth:SetTextColor(Theme.Unpack("dim"))
        row.worth:Show()
        return
    end

    row.rank:SetText(texts.rank)
    -- The top three of a board wear gold, silver and bronze.
    local medal = MEDALS[entry.rank]
    if medal then
        row.rank:SetTextColor(0.06, 0.06, 0.07)
        row.medal:SetColorTexture(medal[1], medal[2], medal[3], measured and 0.95 or 0.6)
        row.medal:Show()
    else
        row.rank:SetTextColor(Theme.Unpack("dim"))
    end
    row.rank:Show()

    local color = measured and "good" or "accent"
    local share = data.top > 0 and entry.value / data.top or 0
    local width = math.max(1, BAR_WIDTH * share)
    local fill = row.barFill

    row.barTrack:Show()
    fill:SetColorTexture(Theme.Unpack(color, measured and 1 or 0.6))
    fill:Show()

    -- A board shown fresh grows its bars from nothing, top down.
    if self.arriving and index then
        ns.Motion:Run(row, "bar", 0.5, function(p) fill:SetWidth(math.max(1, width * p)) end,
            { delay = 0.1 + math.min(index - 1, 14) * 0.025 })
    else
        ns.Motion:Stop(row, "bar")
        fill:SetWidth(width)
    end

    row.worth:SetText(texts.worth)
    row.worth:SetTextColor(Theme.Unpack(measured and "good" or "muted"))
    row.worth:Show()
end

--- A mob you have killed opens its loot table; one you have not says so.
function RankingsUI:OnRowClick(data)
    if not data.entry then return end

    local mob = data.entry.mob
    if ns.LootTableUI and ns.LootTableUI:Show(mob) then return end

    ns.Print(("%s: you have not killed one yet, so there is no loot table. "
        .. "Its worth is an estimate from the database."):format(Util.Colored("accent", mob)))
end

--------------------------------------------------------------------------------
-- Drawing
--------------------------------------------------------------------------------

--- The board as list rows, for the chosen filter.
function RankingsUI:Rows(board)
    local rows = {}
    local wanted = self.group

    local function Add(group, emptyText)
        local entries = board[group]
        if #entries == 0 and not emptyText then return end

        rows[#rows + 1] = { type = "heading", group = group }

        if #entries == 0 then
            rows[#rows + 1] = { type = "note", text = emptyText }
            return
        end

        local top = entries[1].value or 0
        for _, entry in ipairs(entries) do
            rows[#rows + 1] = { type = "mob", entry = entry, top = top }
        end
    end

    if not wanted or wanted == "measured" then
        Add("measured", ("Nothing yet. Kill a mob %d times to rank it from your own loot.")
            :format(ns.Tracker.MIN_KILLS))
    end

    if not wanted or wanted == "estimate" then
        Add("estimate", "No database drop rate has a price yet.")
    end

    if not wanted or wanted == "measured" then
        Add("pending")
    end

    return rows
end

--- Widen the columns to fit these rows, and return the window width they want.
function RankingsUI:FitColumns(rows)
    local widths = {}
    for key, w in pairs(BASE_WIDTH) do widths[key] = w end

    for _, row in ipairs(rows) do
        if row.type == "mob" then
            local texts = EntryTexts(row)
            for _, key in ipairs({ "mob", "basis", "best", "where" }) do
                widths[key] = math.max(widths[key], Theme.TextWidth("small", texts[key]) + 8)
            end
            if texts.worth then
                widths.worth = math.max(widths.worth,
                    Theme.TextWidth("small", texts.worth) + BAR_WIDTH + 12)
            end
        end
    end

    for key, most in pairs(MAX_WIDTH) do
        widths[key] = math.min(most, math.ceil(widths[key]))
    end

    local current = self.columns
    local changed = false
    for key in pairs(MAX_WIDTH) do
        if current[key].w ~= widths[key] then changed = true end
    end

    if changed then
        self.columns = Columns(widths)
        self:PlaceHeadings()
    end

    return self.columns.total + CHROME
end

function RankingsUI:PriceText()
    if ns.Value:HasAuctionPrices() then
        return "Tradeskills auction prices"
    end
    return "vendor prices, Tradeskills not loaded"
end

--- Rebuild the board and draw it. Returns the window width it wants.
function RankingsUI:Render(arrive)
    if not self.view then return end

    for _, chip in ipairs(self.chips) do
        chip:SetSelected(chip:GetFilterKind() == self.group)
    end

    local board = ns.Rankings:Build()
    local rows = self:Rows(board)
    self.board = board

    local width = self:FitColumns(rows)

    -- The board comes in row by row when the tab is opened or the filter
    -- changes; a kill that redraws it while you look just redraws.
    local fresh = arrive or self.shownGroup ~= self.group
    self.shownGroup = self.group
    self.arriving = fresh
    -- A redraw after a kill keeps your place on the board.
    self.list:SetData(rows, not fresh)
    self.arriving = false
    if fresh then self.list:Arrive() end
    self.summary:SetText(self:PriceText())

    -- The window grows to fit, never narrower than the search tab's base.
    if ns.UI and ns.UI.frame and ns.UI.tab == "rankings" then
        ns.UI.frame:SetWidth(math.max(ns.UI.BASE_WIDTH or 0, width))
    end

    return width
end

--- Redraw if the tab is on screen: a kill can change the board.
function RankingsUI:Refresh()
    if self.view and self.view:IsShown() and ns.UI.frame:IsShown() then
        self:Render()
    end
end
