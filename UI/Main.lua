-- Blackthornes Farmer -- UI/Main.lua
-- The window -- a search box, filter chips and a table of results -- plus the
-- minimap button that opens it.
--
-- Results are drawn as columns rather than sentences. A fully researched entry
-- carries a mob, a level band, a landmark, coordinates and a drop rate, and
-- five facts in a sentence is a paragraph nobody scans. In columns your eye
-- goes down the one you care about: the level you can kill, or the best rate.
--
-- Rows are recycled, so a search that matches everything costs the same to
-- draw as one that matches a single item.

local _, ns = ...

local UI = ns.NewModule("UI")

local Theme = ns.Theme
local Widgets = ns.Widgets
local Util = ns.Util

local WIDTH = 660
local HEIGHT = 480
local PADDING = 14
local ROW_HEIGHT = 20

-- The Rankings tab never draws the window narrower than this either.
UI.BASE_WIDTH = WIDTH

-- The window's tabs, left to right.
local TABS = {
    { key = "search", label = "SEARCH" },
    { key = "rankings", label = "RANKINGS" },
}

-- Column widths, left to right, at their narrowest. The source, where and
-- drop columns widen to fit what a search turns up, and the window with them:
-- the game's font runs wider than widths picked by eye, and names were being
-- cut off.
local COLUMN_ORDER = { "kind", "name", "where", "level", "drop" }
local BASE_WIDTH = { kind = 40, name = 170, where = 196, level = 46, drop = 110 }
local MAX_WIDTH = { name = 320, where = 400, drop = 220 }
local COLUMN_GAP = 6

local DROP_BAR_WIDTH = 46

--- Column left edges and widths, measured from the list's left edge, for the
--- given widths (any not given are at their narrowest).
local function Columns(widths)
    local columns, x = {}, 0

    for _, key in ipairs(COLUMN_ORDER) do
        local w = widths and widths[key] or BASE_WIDTH[key]
        columns[key] = { x = x, w = w }
        x = x + w + COLUMN_GAP
    end

    -- How much wider than the narrowest layout, for the window to grow by.
    columns.extra = x - COLUMN_GAP - 586

    return columns
end

local COLUMN = Columns()

--------------------------------------------------------------------------------
-- Colour helpers
--------------------------------------------------------------------------------

--- Level text coloured the way the game colours a target: can I kill this?
-- Falls back to plain text before the player's level is known, which is the
-- case in tests and for a moment at login.
local function DifficultyColor(level)
    local player = UnitLevel and UnitLevel("player") or 0
    if not level or player <= 0 then return Theme.Unpack("text") end

    local difference = level - player

    if difference >= 5 then return 1.00, 0.35, 0.35 end
    if difference >= 3 then return 1.00, 0.60, 0.30 end
    if difference >= -2 then return 1.00, 0.88, 0.35 end
    if difference >= -7 then return 0.45, 0.88, 0.45 end

    return 0.60, 0.62, 0.66
end

--- A drop rate worth crossing a continent for should look different from one
-- that is barely worth the trip.
local function DropColor(chance)
    if chance >= 40 then return Theme.Unpack("good") end
    if chance >= 25 then return Theme.Unpack("accent") end
    return Theme.Unpack("muted")
end

--------------------------------------------------------------------------------
-- Construction
--------------------------------------------------------------------------------

function UI:Build()
    if self.frame then return self.frame end

    self.filterKind = nil
    self.collapsed = {}

    local frame = CreateFrame("Frame", "BlackthornesFarmerFrame", UIParent)
    frame:SetSize(WIDTH, HEIGHT)
    frame:SetFrameStrata("DIALOG")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")

    Theme.Fill(frame, "window")
    Theme.Border(frame, "borderLit")

    frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        UI:SavePosition()
    end)

    frame:SetScript("OnKeyDown", function(self, key)
        if key == "ESCAPE" then
            self:SetPropagateKeyboardInput(false)
            UI:Hide()
        else
            self:SetPropagateKeyboardInput(true)
        end
    end)
    frame:EnableKeyboard(true)
    frame:SetPropagateKeyboardInput(true)

    self.frame = frame
    self:ApplyScale()

    self:BuildHeader()
    self:BuildBody()

    if ns.RankingsUI then
        self.rankingsView = ns.RankingsUI:Build(frame)
    end

    self.tab = "search"
    self.tabs.search:SetSelected(true)

    frame:Hide()
    return frame
end

function UI:BuildHeader()
    local frame = self.frame

    local header = Theme.CreatePanel(frame, "header", false)
    header:SetPoint("TOPLEFT")
    header:SetPoint("TOPRIGHT")
    header:SetHeight(36)

    local title = Theme.CreateLabel(header, "title", "accent")
    title:SetPoint("LEFT", PADDING, 0)
    title:SetText("Blackthornes Farmer")

    -- Tabs sit after the title, sized to their labels.
    self.tabs = {}
    local anchor, gap = title, 16

    for _, tab in ipairs(TABS) do
        local chip = Widgets.CreateChip(header, tab.label, function() UI:ShowTab(tab.key) end)
        chip:SetHeight(20)
        chip:SetWidth(Theme.TextWidth("tiny", tab.label) + 22)
        chip:SetPoint("LEFT", anchor, "RIGHT", gap, 0)
        self.tabs[tab.key] = chip
        anchor, gap = chip, 4
    end

    local close = Widgets.CreateButton(header, "X", function() UI:Hide() end,
        { width = 22, height = 20 })
    close:SetPoint("RIGHT", -PADDING + 2, 0)

    local settings = Widgets.CreateButton(header, "Settings", function()
        if ns.SettingsUI then ns.SettingsUI:Toggle() end
    end, { width = 64, height = 20 })
    settings:SetPoint("RIGHT", close, "LEFT", -6, 0)
    self.settingsButton = settings

    local divider = Theme.CreateDivider(frame, "borderLit")
    divider:SetPoint("TOPLEFT", header, "BOTTOMLEFT")
    divider:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT")

    self.header = header
end

function UI:BuildBody()
    -- Everything below the header belongs to the Search tab, so choosing
    -- another tab hides it in one go.
    local frame = CreateFrame("Frame", nil, self.frame)
    frame:SetAllPoints(self.frame)
    self.searchView = frame

    local search = Widgets.CreateSearchBox(frame,
        "an item, a zone, a mob, or a place",
        function(text) UI:Search(text, true) end)

    search:SetPoint("TOPLEFT", PADDING, -48)
    search:SetPoint("TOPRIGHT", -PADDING, -48)
    self.searchBox = search

    -- Filter chips sit between the box and the results, showing only the kinds
    -- the current search actually turned up.
    local filters = CreateFrame("Frame", nil, frame)
    filters:SetPoint("TOPLEFT", search, "BOTTOMLEFT", 0, -8)
    filters:SetPoint("TOPRIGHT", search, "BOTTOMRIGHT", 0, -8)
    filters:SetHeight(18)
    self.filters = filters
    self.chips = {}

    local summary = Theme.CreateLabel(frame, "small", "muted", "RIGHT")
    summary:SetPoint("RIGHT", filters, "RIGHT", -2, 0)
    summary:SetWidth(260)
    self.summary = summary

    local panel = Theme.CreatePanel(frame, "panel", "border")
    panel:SetPoint("TOPLEFT", filters, "BOTTOMLEFT", 0, -8)
    panel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -PADDING, 36)
    self.panel = panel

    self:BuildColumnHeadings()

    local list = Widgets.CreateRowList(panel, {
        rowHeight = ROW_HEIGHT,
        createRow = function(row) UI:CreateRow(row) end,
        updateRow = function(row, data) UI:UpdateRow(row, data) end,
        onClick = function(data, button) UI:OnRowClick(data, button) end,
        onEnter = function(row) UI:ShowValueTooltip(row) end,
        onLeave = function() if GameTooltip then GameTooltip:Hide() end end,
    })

    list:SetPoint("TOPLEFT", 8, -24)
    list:SetPoint("BOTTOMRIGHT", -8, 8)
    self.list = list

    local footer = Theme.CreateLabel(frame, "tiny", "dim")
    footer:SetPoint("BOTTOMLEFT", PADDING, 6)
    footer:SetPoint("BOTTOMRIGHT", -PADDING, 6)
    -- Two lines if it needs them, rather than cut off.
    footer:SetHeight(26)
    footer:SetWordWrap(true)
    footer:SetJustifyV("MIDDLE")
    footer:SetText("Unmarked spots come from Classic data and are not confirmed on Forever yet. "
        .. "Click a row to print it to chat.")
    self.footer = footer
end

function UI:PlaceHeadings()
    for key, label in pairs(self.headings) do
        local column = self.columns[key]
        label:ClearAllPoints()
        label:SetPoint("TOPLEFT", 8 + column.x, -8)
        label:SetWidth(column.w)
    end
end

--- Row `row`'s columns where the current layout puts them.
function UI:PlaceRow(row)
    local columns = self.columns or COLUMN
    if row.layout == columns then return end
    row.layout = columns

    local function Place(region, column, offset, width)
        region:ClearAllPoints()
        region:SetPoint("LEFT", column.x + (offset or 0), 0)
        if width then region:SetWidth(width) end
    end

    Place(row.kindChip, columns.kind)
    Place(row.kind, columns.kind, 0, columns.kind.w - 6)
    Place(row.name, columns.name, 0, columns.name.w)
    Place(row.where, columns.where, 0, columns.where.w)
    Place(row.level, columns.level, 0, columns.level.w)
    Place(row.dropTrack, columns.drop)
    Place(row.dropFill, columns.drop)
    Place(row.drop, columns.drop, DROP_BAR_WIDTH + 6, columns.drop.w - DROP_BAR_WIDTH - 6)
end

--- The text a source row shows in each column that can grow.
local function SourceTexts(source)
    local where = ns.DB:WhereText(source)

    return source.name or source.requires or ns.DB:KindLabel(source.kind),
        where and (source.zone .. Util.Colored("dim", " / ") .. where) or source.zone,
        (not source.chance and source.requires and source.name) and source.requires or nil
end

--- Widen the columns, and the window, to fit these rows; never narrower
--- than the base layout.
function UI:FitColumns(rows)
    local widths = { name = BASE_WIDTH.name, where = BASE_WIDTH.where, drop = BASE_WIDTH.drop }

    for _, row in ipairs(rows) do
        if row.type == "source" then
            local name, where, drop = SourceTexts(row.source)
            widths.name = math.max(widths.name, Theme.TextWidth("small", name) + 8)
            widths.where = math.max(widths.where, Theme.TextWidth("small", where) + 8)
            if drop then
                widths.drop = math.max(widths.drop,
                    Theme.TextWidth("small", drop) + DROP_BAR_WIDTH + 12)
            end
        end
    end

    for key, most in pairs(MAX_WIDTH) do
        widths[key] = math.min(most, math.ceil(widths[key]))
    end

    local current = self.columns or COLUMN
    if current.name.w == widths.name and current.where.w == widths.where
        and current.drop.w == widths.drop then
        return
    end

    self.columns = Columns(widths)
    self:PlaceHeadings()

    if self.tab ~= "rankings" then
        self.frame:SetWidth(WIDTH + self.columns.extra)
    end
end

function UI:BuildColumnHeadings()
    local panel = self.panel

    self.headings = {}

    local function Heading(key, text, justify)
        local label = Theme.CreateLabel(panel, "tiny", "dim", justify)
        label:SetText(text)
        self.headings[key] = label
    end

    Heading("kind", "")
    Heading("name", "SOURCE")
    Heading("where", "WHERE")
    Heading("level", "LEVEL")
    Heading("drop", "DROP")

    self.columns = COLUMN
    self:PlaceHeadings()

    local rule = Theme.CreateDivider(panel, "border")
    rule:SetPoint("TOPLEFT", 8, -20)
    rule:SetPoint("TOPRIGHT", -8, -20)
end

--------------------------------------------------------------------------------
-- Rows
--------------------------------------------------------------------------------

--- Hovering a mob's row says what a kill is worth, priced by Tradeskills.
function UI:ShowValueTooltip(row)
    local data = row and row.data
    if not (data and data.type == "source" and data.source.name) then return end

    self:ShowMobTooltip(row, data.source.name)
end

--- What a kill of `mobName` is worth and what makes it up, beside `owner`.
--- Shows nothing for a mob with no value.
function UI:ShowMobTooltip(owner, mobName)
    if not (GameTooltip and ns.Value) then return end

    local worth, details = ns.Value:ForMob(mobName)
    if not worth then return end

    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:AddLine(mobName)
    GameTooltip:AddLine(("Worth about %s a kill"):format(ns.Value.Money(worth)),
        Theme.Unpack("good"))

    for index = 1, math.min(#details.priced, 4) do
        local entry = details.priced[index]
        GameTooltip:AddLine(("  %s  %s"):format(entry.name, ns.Value.Money(entry.perKill)),
            Theme.Unpack("muted"))
    end

    GameTooltip:AddLine(details.basis == "tally"
        and ("From your %d kills, %s."):format(details.kills, ns.Value:PriceNote(details))
        or ("Estimate from %s. Coin not counted."):format(ns.Value:PriceNote(details)),
        Theme.Unpack("muted"))
    GameTooltip:Show()
end

function UI:CreateRow(row)
    -- An item heading: full width, so it reads as a break in the list.
    row.heading = Theme.CreateLabel(row, "small", "accent")
    row.heading:SetPoint("LEFT", 2, 0)
    row.heading:SetPoint("RIGHT", -64, 0)

    row.kindChip = row:CreateTexture(nil, "ARTWORK")
    row.kindChip:SetSize(BASE_WIDTH.kind - 6, 13)

    row.kind = Theme.CreateLabel(row, "tiny", "text", "CENTER")

    row.name = Theme.CreateLabel(row, "small", "text")

    row.where = Theme.CreateLabel(row, "small", "muted")

    row.level = Theme.CreateLabel(row, "small", "text", "CENTER")

    row.dropTrack = row:CreateTexture(nil, "ARTWORK")
    row.dropTrack:SetSize(DROP_BAR_WIDTH, 6)
    row.dropTrack:SetColorTexture(Theme.Unpack("row"))

    row.dropFill = row:CreateTexture(nil, "OVERLAY")
    row.dropFill:SetHeight(6)

    row.drop = Theme.CreateLabel(row, "small", "muted")

    row.badge = Theme.CreateLabel(row, "tiny", "good", "RIGHT")
    row.badge:SetPoint("RIGHT", -2, 0)
    row.badge:SetWidth(60)

    self:PlaceRow(row)
end

local function HideSourceColumns(row)
    row.kindChip:Hide()
    row.kind:Hide()
    row.name:Hide()
    row.where:Hide()
    row.level:Hide()
    row.dropTrack:Hide()
    row.dropFill:Hide()
    row.drop:Hide()
    row.badge:Hide()
end

function UI:UpdateRow(row, data)
    self:PlaceRow(row)
    row.heading:Hide()
    HideSourceColumns(row)

    if data.type == "item" then
        local arrow = self.collapsed[data.item.name] and "+" or "-"

        -- Set every time: this row may have drawn a muted note a moment ago,
        -- and a recycled row keeps whatever the last one left on it.
        row.heading:SetTextColor(Theme.Unpack("accent"))
        row.heading:SetText(("%s  %s  %s"):format(arrow, data.item.name,
            Util.Colored("muted", ("(%s, %s)"):format(
                data.item.category, Util.Plural(data.count, "spot")))))
        row.heading:Show()
        return
    end

    if data.type == "note" or data.type == "more" then
        row.heading:SetTextColor(Theme.Unpack(data.type == "more" and "dim" or "muted"))
        row.heading:SetText("     " .. data.text)
        row.heading:Show()
        return
    end

    if data.type ~= "source" then return end

    local source = data.source

    row.kindChip:SetColorTexture(Theme.Unpack("row"))
    row.kindChip:Show()

    row.kind:SetText(ns.DB:KindTag(source.kind))
    row.kind:SetTextColor(Theme.Unpack("muted"))
    row.kind:Show()

    -- A node named after the thing it holds tells you nothing twice, so show
    -- what it needs instead.
    local name, where = SourceTexts(source)

    row.name:SetText(name)
    row.name:SetTextColor(Theme.Unpack("text"))
    row.name:Show()

    row.where:SetText(where)
    row.where:Show()

    row.level:SetText(ns.Search:LevelText(source))
    row.level:SetTextColor(DifficultyColor(source.maxLevel or source.minLevel))
    row.level:Show()

    if source.chance then
        row.dropTrack:Show()

        row.dropFill:SetWidth(math.max(1, DROP_BAR_WIDTH * (source.chance / 100)))
        row.dropFill:SetColorTexture(DropColor(source.chance))
        row.dropFill:Show()

        row.drop:SetText(("%d%%"):format(source.chance))
        row.drop:SetTextColor(DropColor(source.chance))
        row.drop:Show()
    elseif source.requires and source.name then
        -- Nothing to say about a drop rate, but the skill gate matters.
        row.drop:SetTextColor(Theme.Unpack("dim"))
        row.drop:SetText(source.requires)
        row.drop:Show()
    end

    if source.provenance == "forever" then
        row.badge:SetText("Forever")
        row.badge:Show()
    end
end

--- Clicking a row prints it to chat, which is how you paste a spot to someone
--- or keep it in the log while you fly there.
function UI:OnRowClick(data, button)
    if data.type == "item" then
        self.collapsed[data.item.name] = not self.collapsed[data.item.name]
        self:Render()
        return
    end

    if data.type ~= "source" then return end

    local source = data.source
    local parts = { source.name or ns.DB:KindLabel(source.kind), source.zone }

    local where = ns.DB:WhereText(source)
    if where then parts[#parts + 1] = where end

    parts[#parts + 1] = ("level %s"):format(ns.Search:LevelText(source))

    if source.chance then
        parts[#parts + 1] = ("~%d%%"):format(source.chance)
    end

    ns.Print(("%s -- %s"):format(
        Util.Colored("accent", data.item.name), table.concat(parts, ", ")))
end

--------------------------------------------------------------------------------
-- Searching
--------------------------------------------------------------------------------

function UI:Search(query, typed)
    self:Build()
    self:Show()

    -- A search from chat is an answer wanted now, whichever tab was open.
    if self.tab ~= "search" then self:ShowTab("search") end

    query = Util.Trim(query or "")

    if not typed then
        self.searchBox:SetText(query)
    end

    if ns.db then
        ns.db.lastSearch = query
    end

    -- A new search starts fresh: last search's filter and collapsed items are
    -- not answers to this one.
    if query ~= self.lastQuery then
        self.filterKind = nil
        self.collapsed = {}
        self.lastQuery = query
    end

    self:BuildChips(query)
    self:Render()
end

function UI:Render()
    local query = self.lastQuery or ""

    if query == "" then
        self.list:SetData({})
        self.summary:SetText(("%s, %s"):format(
            Util.Plural(ns.DB:CountItems(), "item"),
            Util.Plural(ns.DB:CountSources(), "spot")))
        return
    end

    local rows, total = ns.Search:BuildRows(query, { kind = self.filterKind })

    -- Collapsing hides an item's sources but keeps its heading, so the list
    -- stays navigable when a search turns up a lot.
    local visible = {}
    for _, row in ipairs(rows) do
        local hidden = (row.type == "source" and self.collapsed[row.item.name])
            or (row.type == "note" and false)

        if not hidden then
            visible[#visible + 1] = row
        end
    end

    self:FitColumns(visible)
    self.list:SetData(visible)

    if total == 0 then
        self.summary:SetText(Util.Colored("muted", "nothing found"))
    else
        self.summary:SetText(("%s matching"):format(Util.Plural(total, "item")))
    end
end

--- Chips for the source kinds this search turned up, plus All.
function UI:BuildChips(query)
    for _, chip in ipairs(self.chips) do
        chip:Hide()
    end

    if query == "" then return end

    local kinds = ns.Search:KindsInResults(query)

    -- One kind is not a choice, so there is nothing to offer.
    if #kinds < 2 then return end

    local entries = { { label = "ALL", kind = nil } }
    for _, kind in ipairs(kinds) do
        entries[#entries + 1] = { label = ns.DB:KindTag(kind), kind = kind }
    end

    local offset = 0

    for index, entry in ipairs(entries) do
        local chip = self.chips[index]

        if not chip then
            -- The handler's argument is the chip, not this module; naming it
            -- self here would read as if it were UI.
            chip = Widgets.CreateChip(self.filters, entry.label, function(clicked)
                UI.filterKind = clicked:GetFilterKind()
                UI:Render()
                UI:RefreshChipStates()
            end)
            self.chips[index] = chip
        end

        chip.label:SetText(entry.label)
        chip:SetWidth(math.max(34, (chip.label:GetStringWidth() or 30) + 16))

        -- Stored as false rather than nil for the All chip, so "no filter" is
        -- a value the chip actually holds rather than an absent field.
        chip.filterKind = entry.kind or false

        chip:ClearAllPoints()
        chip:SetPoint("LEFT", self.filters, "LEFT", offset, 0)
        chip:Show()

        offset = offset + chip:GetWidth() + 4
    end

    self:RefreshChipStates()
end

function UI:RefreshChipStates()
    for _, chip in ipairs(self.chips) do
        if chip:IsShown() then
            chip:SetSelected(chip:GetFilterKind() == self.filterKind)
        end
    end
end

function UI:Refresh()
    if self.frame and self.frame:IsShown() then
        self:Render()
    end
end

--------------------------------------------------------------------------------
-- Tabs
--------------------------------------------------------------------------------

--- Switch the window to a tab: "search" or "rankings". Remembered for the
--- next time the window opens.
function UI:ShowTab(key)
    self:Build()
    if key ~= "rankings" or not self.rankingsView then key = "search" end

    self.tab = key
    if ns.db then ns.db.lastTab = key end

    for tabKey, chip in pairs(self.tabs) do
        chip:SetSelected(tabKey == key)
    end

    self.searchView:SetShown(key == "search")
    if self.rankingsView then self.rankingsView:SetShown(key == "rankings") end

    if key == "rankings" then
        -- A hidden search box keeping the keyboard would eat your keys.
        self.searchBox:ClearFocus()
        ns.RankingsUI:Render()
    else
        self.frame:SetWidth(WIDTH + (self.columns or COLUMN).extra)
    end
end

--------------------------------------------------------------------------------
-- Position
--------------------------------------------------------------------------------

function UI:SavePosition()
    if not (ns.db and self.frame) then return end

    local point, _, relativePoint, x, y = self.frame:GetPoint()

    ns.db.point = point
    ns.db.relativePoint = relativePoint
    ns.db.x = x
    ns.db.y = y
end

function UI:RestorePosition()
    if not self.frame then return end

    local db = ns.db or {}

    self.frame:ClearAllPoints()
    self.frame:SetPoint(db.point or "CENTER", UIParent,
        db.relativePoint or "CENTER", db.x or 0, db.y or 40)
end

--- The window's size, as chosen on the settings page.
function UI:ApplyScale()
    if self.frame then
        self.frame:SetScale(((ns.db and ns.db.windowScale) or 100) / 100)
    end
end

--------------------------------------------------------------------------------
-- Visibility
--------------------------------------------------------------------------------

function UI:Show()
    self:Build()

    if self.frame:IsShown() then return end

    self:RestorePosition()
    self.frame:Show()
end

function UI:Hide()
    if self.frame then
        self.frame:Hide()
    end
end

function UI:Toggle()
    self:Build()

    if self.frame:IsShown() then
        self:Hide()
        return
    end

    self:Show()

    if ns.db and ns.db.lastTab == "rankings" then
        self:ShowTab("rankings")
        return
    end

    self:Search(ns.db and ns.db.lastSearch or "")
    self.searchBox:SetFocus()
end

function UI:OnEnable()
    self:Build()
    self:BuildMinimapButton()

    -- The minimap's final size is not always settled at login, and other addons
    -- resize it afterwards, so re-seat the button once things have calmed down.
    if C_Timer and C_Timer.After then
        C_Timer.After(1, function() UI:RepositionMinimapButton() end)
    end

    -- Cheap enough to check, and catches a minimap resized at any point.
    if C_Timer and C_Timer.NewTicker then
        self.ticker = C_Timer.NewTicker(5, function()
            if Minimap and UI.lastMinimapWidth ~= Minimap:GetWidth() then
                UI:RepositionMinimapButton()
            end
        end)
    end
end

--------------------------------------------------------------------------------
-- Minimap button
--
-- Ported from Blackthornes Tradeskills so the two behave identically: drag it
-- around the ring, left-click to open. The orbit radius is derived from the
-- minimap's real size rather than assumed, because a fixed radius only clears
-- the ring on a default 140px minimap and anyone running a larger one gets the
-- button sitting on top of the map.
--------------------------------------------------------------------------------

local DEFAULT_ANGLE = math.rad(200)

function UI:BuildMinimapButton()
    if self.minimapButton or not Minimap then return end

    local button = CreateFrame("Button", "BlackthornesFarmerMinimapButton", Minimap)
    button:SetSize(31, 31)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(8)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    local background = button:CreateTexture(nil, "BACKGROUND")
    background:SetSize(20, 20)
    background:SetPoint("CENTER")
    background:SetColorTexture(Theme.Unpack("window"))

    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetSize(18, 18)
    icon:SetPoint("CENTER")
    icon:SetTexture([[Interface\Icons\Trade_Mining]])
    icon:SetTexCoord(0.1, 0.9, 0.1, 0.9)

    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT")
    border:SetTexture([[Interface\Minimap\MiniMap-TrackingBorder]])

    local function GetOrbitRadius()
        local size = Minimap:GetWidth()
        if not size or size <= 0 then size = 140 end

        return (size / 2) + (ns.db and ns.db.minimapGap or 16)
    end

    local function UpdatePosition(angle)
        local radius = GetOrbitRadius()

        button:ClearAllPoints()
        button:SetPoint("CENTER", Minimap, "CENTER",
            math.cos(angle) * radius, math.sin(angle) * radius)
    end

    button.UpdatePosition = UpdatePosition
    UpdatePosition((ns.db and ns.db.minimapAngle) or DEFAULT_ANGLE)

    -- Dragging around the minimap edge is the expected behaviour for these.
    button:SetMovable(true)
    button:RegisterForDrag("LeftButton")

    button:SetScript("OnDragStart", function(self)
        self.dragging = true
        self:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            local cx, cy = GetCursorPosition()
            local scale = UIParent:GetEffectiveScale()

            local newAngle = math.atan2((cy / scale) - my, (cx / scale) - mx)
            UpdatePosition(newAngle)

            if ns.db then ns.db.minimapAngle = newAngle end
        end)
    end)

    button:SetScript("OnDragStop", function(self)
        self.dragging = false
        self:SetScript("OnUpdate", nil)
    end)

    button:SetScript("OnClick", function(_, mouseButton)
        if mouseButton == "RightButton" and ns.SettingsUI then
            ns.SettingsUI:Toggle()
        else
            UI:Toggle()
        end
    end)

    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("Blackthornes Farmer")
        GameTooltip:AddLine("Click to open", 0.7, 0.7, 0.7)
        GameTooltip:AddLine("Right-click for settings", 0.7, 0.7, 0.7)
        GameTooltip:AddLine("Drag to move it round the minimap", 0.5, 0.5, 0.5)
        GameTooltip:Show()
    end)

    button:SetScript("OnLeave", function() GameTooltip:Hide() end)

    self.minimapButton = button
    self.lastMinimapWidth = Minimap:GetWidth()

    self:ApplyMinimapVisibility()
end

--- Re-seat the button at its stored angle, using the current radius.
function UI:RepositionMinimapButton()
    local button = self.minimapButton
    if not button or not button.UpdatePosition then return end

    button.UpdatePosition((ns.db and ns.db.minimapAngle) or DEFAULT_ANGLE)
    self.lastMinimapWidth = Minimap and Minimap:GetWidth()
end

function UI:ApplyMinimapVisibility()
    local button = self.minimapButton
    if not button then return end

    if ns.db and ns.db.minimapHidden then
        button:Hide()
    else
        button:Show()
    end
end

--- Show or hide the button. Returns true when it ends up visible.
function UI:ToggleMinimapButton()
    if ns.db then
        ns.db.minimapHidden = not ns.db.minimapHidden
    end

    self:ApplyMinimapVisibility()
    return not (ns.db and ns.db.minimapHidden)
end

ns.RegisterCommand("minimap", "show or hide the minimap button", function()
    local shown = ns.UI:ToggleMinimapButton()

    if shown then
        ns.Print("minimap button shown.")
    else
        ns.Print("minimap button hidden. /farm minimap brings it back.")
    end
end)
