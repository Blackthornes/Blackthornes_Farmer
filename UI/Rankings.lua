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
local L = ns.L

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
    { label = L["ALL"], group = false },
    { label = L["MEASURED"], group = "measured" },
    { label = L["ESTIMATES"], group = "estimate" },
    { label = L["WORLD DROPS"], group = "worlddrops" },
}

local HEADINGS = {
    measured = { L["YOUR KILLS"], L["measured, coin included"] },
    estimate = { L["ESTIMATES"], L["database drop rates, no coin, so they run low"] },
    pending = { L["NOT RANKED YET"], L["keep killing"] },
    worlddrops = { L["WORLD DROPS"], L["green gear and better, by mob level"] },
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

    -- Up in the window's top row, where the Search tab has its box: beside
    -- the portrait and level with the Settings button.
    local filters = CreateFrame("Frame", nil, view)
    local left, top = ns.UI.HEAD_LEFT or PADDING, (ns.UI.HEAD_TOP or 45) + 3
    filters:SetPoint("TOPLEFT", left, -top)
    if ns.UI.settingsButton then
        filters:SetPoint("TOPRIGHT", ns.UI.settingsButton, "TOPLEFT", -8, -3)
    else
        filters:SetPoint("TOPRIGHT", -PADDING, -top)
    end
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

    -- Below the portrait, as wide as the Search tab's results.
    local panel = Theme.CreatePanel(view, "panel", "border")
    panel:SetPoint("TOPLEFT", view, "TOPLEFT", PADDING, -(top + 18 + 8))
    panel:SetPoint("BOTTOMRIGHT", view, "BOTTOMRIGHT", -PADDING, 36)
    -- Sunk into the window, as the game's inset panels sit (Titanforged).
    if Theme.Recess then Theme.Recess(panel) end
    self.panel = panel

    self.headings = {}
    for key, text in pairs({ rank = "#", mob = L["MOB"], worth = L["PER KILL"], basis = L["FROM"],
        best = L["BEST DROP"], where = L["WHERE"], level = L["LEVEL"] }) do
        -- "#" sits over the ranks' right edge; the sort arrow goes before it.
        local label = Theme.CreateLabel(panel, "tiny", "dim", key == "rank" and "RIGHT" or nil)
        label:SetText(text)
        self.headings[key] = label
    end

    self.columns = Columns()
    self:PlaceHeadings()

    -- Click a heading to sort each board by it (a player's request,
    -- 2026-10-11), as the search's headings do. The boards stay apart and
    -- each mob keeps its rank and medal. Kept in `rankingsSort`.
    local key, ascending = self:SortChoice()
    self.sorter = Widgets.SortableHeadings(self.headings, {
        rank = L["Sort by rank, best first: the usual order."],
        mob = L["Sort by mob name, A to Z."],
        worth = L["Sort by what a kill is worth, best first."],
        basis = L["Sort by how many you have killed, most first."],
        best = L["Sort by the best drop's name, A to Z."],
        where = L["Sort by where it is, A to Z."],
        level = L["Sort by level, lowest first."],
    }, function(newKey, newAscending)
        if ns.db then
            ns.db.rankingsSort = newKey and { key = newKey, ascending = newAscending } or nil
        end
        RankingsUI:Resort()
    end, { startsLow = RankingsUI.SORT_STARTS_LOW, key = key, ascending = ascending })

    local rule = Theme.CreateDivider(panel, "border")
    rule:SetPoint("TOPLEFT", 8, -20)
    rule:SetPoint("TOPRIGHT", -8, -20)

    local list = Widgets.CreateRowList(panel, {
        rowHeight = ROW_HEIGHT,
        createRow = function(row) RankingsUI:CreateRow(row) end,
        updateRow = function(row, data, index) RankingsUI:UpdateRow(row, data, index) end,
        onClick = function(data, button) RankingsUI:OnRowClick(data, button) end,
        onEnter = function(row, data)
            if data.entry then ns.UI:ShowMobTooltip(row, data.entry.mob) end
        end,
        onLeave = function() if GameTooltip then GameTooltip:Hide() end end,
        -- The colour of the well the rows sit in.
        fadeKey = "well",
    })
    list:SetPoint("TOPLEFT", 8, -24)
    list:SetPoint("BOTTOMRIGHT", -8, 8)
    self.list = list

    -- Clear of the version in the window's corner (UI/Main.lua).
    local footer = Theme.CreateLabel(view, "tiny", "dim")
    footer:SetPoint("BOTTOMLEFT", PADDING, 6)
    footer:SetPoint("BOTTOMRIGHT", -(PADDING + (ns.UI.VERSION_ROOM or 0)), 6)
    footer:SetHeight(26)
    footer:SetWordWrap(true)
    footer:SetJustifyV("MIDDLE")
    footer:SetText(L.Format("Ranked after %d kills. Hover a mob to see its worth, click it for its loot.",
        ns.Tracker.MIN_KILLS))
    self.footer = footer

    view:Hide()
    return view
end

function RankingsUI:PlaceHeadings()
    for key, label in pairs(self.headings) do
        local column = self.columns[key]
        local x, w = column.x, column.w
        if key == "level" then
            -- Centred over its column by width, so the sort arrow, placed
            -- after the words, stays clear of them (as the Grind tab's).
            local text = math.ceil(Theme.TextWidth("tiny", label:GetText() or "")) + 2
            x, w = x + math.max(0, math.floor((w - text) / 2)), math.min(w, text)
        end
        label:ClearAllPoints()
        label:SetPoint("TOPLEFT", 8 + x, -8)
        label:SetWidth(w)
    end
end

--------------------------------------------------------------------------------
-- Sorting by the headings
--------------------------------------------------------------------------------

-- What each heading sorts by, and the ones that start lowest first: rank,
-- names and level; worth and kills start with the biggest.
RankingsUI.SORT_KEYS = { rank = true, mob = true, worth = true, basis = true, best = true,
    where = true, level = true }
RankingsUI.SORT_STARTS_LOW = { rank = true, mob = true, best = true, where = true, level = true }

local SORT_VALUE = {
    rank = function(entry) return entry.rank end,
    mob = function(entry) return entry.mob end,
    worth = function(entry) return entry.value end,
    basis = function(entry) return entry.kills end,
    best = function(entry) return entry.best and entry.best.name end,
    where = function(entry) return entry.where end,
    level = function(entry) return entry.spot and tonumber(entry.spot.minLevel) end,
}

--- The sort the headings were left on: key (nil for the usual order) and
--- ascending. Kept in `rankingsSort`.
function RankingsUI:SortChoice()
    local saved = ns.db and type(ns.db.rankingsSort) == "table" and ns.db.rankingsSort or {}
    if not RankingsUI.SORT_KEYS[saved.key or ""] then return nil, false end
    return saved.key, saved.ascending and true or false
end

--- One board's entries in the order the headings ask for, as a new list.
function RankingsUI:SortEntries(entries)
    local key, ascending = self:SortChoice()
    if not key then return entries end
    return Util.SortBy(entries, ascending, SORT_VALUE[key])
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

    -- The house glow: gold fading across the band from its stripe.
    row.bandGlow = row:CreateTexture(nil, "BACKGROUND", nil, 2)
    row.bandGlow:SetAllPoints(row)
    row.bandGlow:SetColorTexture(1, 1, 1, 1)
    do
        local r, g, b = Theme.Unpack("accent")
        local ok = type(CreateColor) == "function" and pcall(row.bandGlow.SetGradient, row.bandGlow,
            "HORIZONTAL", CreateColor(r, g, b, 0.16), CreateColor(r, g, b, 0))
        if not ok then row.bandGlow:SetColorTexture(r, g, b, 0.05) end
    end
    row.bandGlow:Hide()

    -- The top three glow faintly in their medal's colour.
    row.podium = row:CreateTexture(nil, "BACKGROUND", nil, 2)
    row.podium:SetAllPoints(row)
    row.podium:SetColorTexture(1, 1, 1, 1)
    row.podium:Hide()

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
        texts.worth = entry.unpriced and L["no prices yet"]
            or L.Format("%d more to go", entry.needed)
        texts.basis = Util.Plural(entry.kills, L["kill"], L["kills"])
        texts.best = ""
        return texts
    end

    texts.rank = tostring(entry.rank)
    texts.best = entry.best and entry.best.name or ""

    if entry.group == "measured" then
        texts.worth = ns.Value.Coins(entry.value)
        texts.basis = Util.Plural(entry.kills, L["kill"], L["kills"])
    else
        texts.worth = "~" .. ns.Value.Coins(entry.value)
        texts.basis = L["estimate"]
    end

    return texts
end

function RankingsUI:UpdateRow(row, data, index)
    self:PlaceRow(row)

    row.heading:Hide()
    row.band:Hide()
    row.bandGlow:Hide()
    row.podium:Hide()
    row.bandStripe:Hide()
    row.medal:Hide()
    for _, key in ipairs(CELLS) do row[key]:Hide() end

    if data.type == "heading" then
        row.band:Show()
        row.bandGlow:Show()
        row.bandStripe:Show()
        local heading = HEADINGS[data.group]
        row.heading:SetTextColor(Theme.Unpack("accent"))
        row.heading:SetText(("%s  %s"):format(heading[1],
            Util.Colored("muted", "(" .. (data.note or heading[2]) .. ")")))
        row.heading:Show()
        return
    end

    if data.type == "note" then
        row.heading:SetTextColor(Theme.Unpack("muted"))
        row.heading:SetText("     " .. data.text)
        row.heading:Show()
        return
    end

    if data.type == "band" or data.type == "rare" then
        self:UpdateWorldRow(row, data, index)
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
    row.rank:ClearAllPoints()
    if medal then
        row.rank:SetTextColor(0.06, 0.06, 0.07)
        row.medal:SetColorTexture(medal[1], medal[2], medal[3], measured and 0.95 or 0.6)
        row.medal:Show()
        -- The number sits in the middle of its medal.
        row.rank:SetPoint("CENTER", row.medal, "CENTER", 0, 0)
        row.rank:SetJustifyH("CENTER")

        local r, g, b = medal[1], medal[2], medal[3]
        local peak = measured and 0.14 or 0.07
        local ok = type(CreateColor) == "function" and pcall(row.podium.SetGradient, row.podium,
            "HORIZONTAL", CreateColor(r, g, b, peak), CreateColor(r, g, b, 0))
        if not ok then row.podium:SetColorTexture(r, g, b, peak * 0.4) end
        row.podium:Show()
    else
        row.rank:SetTextColor(Theme.Unpack("dim"))
        row.rank:SetPoint("LEFT", self.columns.rank.x, 0)
        row.rank:SetJustifyH("RIGHT")
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

-- The colours of green, blue, purple and orange gear.
local QUALITY_RGB = {
    [2] = { 0.12, 1.00, 0.00 },
    [3] = { 0.00, 0.44, 0.87 },
    [4] = { 0.64, 0.21, 0.93 },
    [5] = { 1.00, 0.50, 0.00 },
}
RankingsUI.QUALITY_RGB = QUALITY_RGB

--- A world drops row: a level band's chance of green gear, its bar against
--- the best band, or one of the rarer colours over every measured kill.
function RankingsUI:UpdateWorldRow(row, data, index)
    row.mob:SetText(data.label)
    row.mob:SetTextColor(Theme.Unpack("text"))
    if data.quality then
        local rgb = QUALITY_RGB[data.quality]
        row.mob:SetTextColor(rgb[1], rgb[2], rgb[3])
    end
    row.mob:Show()

    row.worth:SetText(data.text)
    row.worth:SetTextColor(Theme.Unpack(data.share and "good" or "dim"))
    row.worth:Show()

    if data.share then
        local rgb = QUALITY_RGB[2]
        local width = math.max(1, BAR_WIDTH * data.share)
        local fill = row.barFill
        row.barTrack:Show()
        fill:SetColorTexture(rgb[1], rgb[2], rgb[3], 0.9)
        fill:Show()
        if self.arriving and index then
            ns.Motion:Run(row, "bar", 0.5, function(p) fill:SetWidth(math.max(1, width * p)) end,
                { delay = 0.1 + math.min(index - 1, 14) * 0.025 })
        else
            ns.Motion:Stop(row, "bar")
            fill:SetWidth(width)
        end
    end

    -- The best band for greens glows gold, as the top of a board does.
    if data.best then
        local medal = MEDALS[1]
        local ok = type(CreateColor) == "function" and pcall(row.podium.SetGradient, row.podium,
            "HORIZONTAL", CreateColor(medal[1], medal[2], medal[3], 0.14),
            CreateColor(medal[1], medal[2], medal[3], 0))
        if not ok then row.podium:SetColorTexture(medal[1], medal[2], medal[3], 0.06) end
        row.podium:Show()
    end
end

--- The world drops rows (Logic/WorldDrops.lua): a heading, a row per level
--- band, the rarer colours and what greens add to a kill where they drop
--- most. Nil while it is turned off.
function RankingsUI:WorldRows(onlyWithKills)
    local WorldDrops = ns.WorldDrops
    if not (WorldDrops and WorldDrops:IsEnabled()) then return nil end

    local bands = WorldDrops:Bands()
    -- Under ALL it shows once there is something to show.
    if onlyWithKills and #bands == 0 then return nil end
    local rows = {}
    local total, measuredKills = 0, 0
    local rare = { [3] = 0, [4] = 0, [5] = 0 }
    local best, bestRate
    for _, entry in ipairs(bands) do
        total = total + entry.kills
        if WorldDrops.Measured(entry) then
            measuredKills = measuredKills + entry.kills
            for quality in pairs(rare) do rare[quality] = rare[quality] + entry.drops[quality] end
            local rate = entry.drops[2] / entry.kills
            if rate > 0 and (not bestRate or rate > bestRate) then best, bestRate = entry, rate end
        end
    end

    rows[1] = { type = "heading", group = "worlddrops",
        note = L.Format("green gear, from %d kills", total) }

    if #bands == 0 then
        rows[2] = { type = "note", text = L["No kills with a level yet."] }
        return rows
    end

    for _, entry in ipairs(bands) do
        local text, share
        if not WorldDrops.Measured(entry) then
            text = L.Format("needs more kills (%d)", entry.kills)
        elseif entry.drops[2] == 0 then
            text = L.Format("none in %d", entry.kills)
        else
            text = L.Format("1 in %d", WorldDrops.OneIn(entry.kills, entry.drops[2]))
            share = (entry.drops[2] / entry.kills) / bestRate
        end
        rows[#rows + 1] = { type = "band", label = WorldDrops.BandLabel(entry.band),
            text = text, share = share, best = entry == best or nil, band = entry }
    end

    if measuredKills > 0 then
        local names = { [3] = L["Blue"], [4] = L["Purple"], [5] = L["Orange"] }
        for _, quality in ipairs({ 3, 4, 5 }) do
            local n = rare[quality]
            rows[#rows + 1] = { type = "rare", quality = quality, label = names[quality],
                text = n > 0 and L.Format("%1$d in %2$d kills", n, measuredKills)
                    or L.Format("none yet in %d kills", measuredKills) }
        end
    end

    local worth = best and WorldDrops.GreenWorth(best)
    if worth and worth > 0 then
        local label = WorldDrops.BandLabel(best.band)
        rows[#rows + 1] = { type = "note", text = L.Format("Greens add about %1$s a kill at %2$s.",
            ns.Value.Coins(worth), label) }
    end

    return rows
end

--- A mob you have killed opens its loot table; one you have not says so.
function RankingsUI:OnRowClick(data, button)
    if not data.entry then return end

    -- Right-click offers to hide the mob (HideMenu).
    if button == "RightButton" then
        ns.HideMenu:Open({ { kind = "source", name = data.entry.mob } })
        return
    end

    local mob = data.entry.mob
    if ns.LootTableUI and ns.LootTableUI:Show(mob) then return end

    ns.Print(L.Format("%s: no kills yet, so no loot table. Its worth is a guess from the data.",
        Util.Colored("accent", mob)))
end

--------------------------------------------------------------------------------
-- Drawing
--------------------------------------------------------------------------------

--- What the mobs not ranked yet are waiting on, when it is not only kills:
--- a mob with its kills but nothing priced waits on prices.
local function PendingNote(entries)
    local kills, prices = false, false
    for _, entry in ipairs(entries) do
        if entry.unpriced then prices = true else kills = true end
    end
    if not prices then return nil end
    return kills and L["waiting on kills or prices"] or L["waiting on prices"]
end

--- The board as list rows, for the chosen filter.
function RankingsUI:Rows(board)
    local rows = {}
    local wanted = self.group

    local function Add(group, emptyText)
        local entries = board[group]
        if #entries == 0 and not emptyText then return end

        rows[#rows + 1] = { type = "heading", group = group,
            note = group == "pending" and PendingNote(entries) or nil }

        if #entries == 0 then
            rows[#rows + 1] = { type = "note", text = emptyText }
            return
        end

        -- The bars are measured against the board's best, wherever the
        -- sort has put it.
        local top = 0
        for _, entry in ipairs(entries) do
            if (entry.value or 0) > top then top = entry.value end
        end
        for _, entry in ipairs(self:SortEntries(entries)) do
            rows[#rows + 1] = { type = "mob", entry = entry, top = top }
        end
    end

    if not wanted or wanted == "measured" then
        Add("measured", L.Format("Nothing yet. Kill a mob %d times to rank it.",
            ns.Tracker.MIN_KILLS))
    end

    if not wanted or wanted == "estimate" then
        Add("estimate", L["No database drop rate has a price yet."])
    end

    if not wanted or wanted == "measured" then
        Add("pending")
    end

    if not wanted or wanted == "worlddrops" then
        for _, row in ipairs(self:WorldRows(not wanted) or {}) do rows[#rows + 1] = row end
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
            -- A long board's ranks run to three figures: "100" was cut off.
            if texts.rank then
                widths.rank = math.max(widths.rank, Theme.TextWidth("small", texts.rank) + 8)
            end
        elseif row.type == "band" or row.type == "rare" then
            widths.mob = math.max(widths.mob, Theme.TextWidth("small", row.label) + 8)
            widths.worth = math.max(widths.worth, Theme.TextWidth("small", row.text) + BAR_WIDTH + 12)
        end
    end

    for key, most in pairs(MAX_WIDTH) do
        widths[key] = math.min(most, math.ceil(widths[key]))
    end

    -- Never wider than the screen, as the search tab: on a small screen, or
    -- with the window scaled up, the widest columns give back room (their
    -- text ends in "...") before the close button goes off the edge.
    local room = ns.UI and ns.UI.ScreenRoom and ns.UI:ScreenRoom()
    if room then
        local over = Columns(widths).total + CHROME - room
        for _, key in ipairs({ "where", "best", "mob", "worth", "basis" }) do
            if over <= 0 then break end
            local give = math.min(over, widths[key] - BASE_WIDTH[key])
            if give > 0 then
                widths[key] = widths[key] - give
                over = over - give
            end
        end
    end

    local current = self.columns
    local changed = false
    for _, key in ipairs(COLUMN_ORDER) do
        if current[key].w ~= widths[key] then changed = true end
    end

    if changed then
        self.columns = Columns(widths)
        self:PlaceHeadings()
    end

    return self.columns.total + CHROME
end

function RankingsUI:PriceText()
    local source = ns.Value:PriceSource()
    if source == "tradeskills" then
        return L["Tradeskills auction prices"]
    elseif source then
        return L["TSM or Auctionator auction prices"]
    end
    return L["vendor prices, Tradeskills not loaded"]
end

--- A click on a heading: the board already built, in the new order, from
--- the top. Nothing is priced or counted again.
function RankingsUI:Resort()
    if not (self.view and self.view:IsShown() and self.board) then return end
    local rows = self:Rows(self.board)
    local width = self:FitColumns(rows)
    self.list:SetData(rows)
    if ns.UI and ns.UI.frame and ns.UI.tab == "rankings" then
        ns.UI.frame:SetWidth(math.max(ns.UI.BASE_WIDTH or 0, width))
    end
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

-- "Hide skinning" moved: leather counts toward a kill's worth or not.
ns.DB.hideWatchers.rankings = function() RankingsUI:Refresh() end

--- Redraw if the tab is on screen: a kill can change the board. The board
--- prices every rated mob, so a burst of loot gets one redraw, not one each.
function RankingsUI:Refresh()
    if not (self.view and self.view:IsShown() and ns.UI.frame:IsShown()) then return end
    if self.pending then return end
    if C_Timer and type(C_Timer.After) == "function" then
        self.pending = true
        local ok = pcall(C_Timer.After, 0.2, function()
            RankingsUI.pending = nil
            if RankingsUI.view and RankingsUI.view:IsShown() and ns.UI.frame:IsShown() then
                RankingsUI:Render()
            end
        end)
        if ok then return end
        self.pending = nil
    end
    self:Render()
end
