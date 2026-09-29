-- Blackthornes Farmer -- UI/Tracker.lua
-- The kills and loot panel, down the left side of the screen.
--
-- A tall, narrow column under the player and party frames that fills in as
-- you farm, on two tabs (Trent, 2026-09-28: showing only three items a mob
-- was "limiting"):
--
--   * Farm: a card for every mob killed this session (and every fishing spot
--     and node). The one you are on leads, open and glowing gold: its
--     all-time kills, where, a progress bar toward the 20 it takes for drop
--     rates, what a kill is worth, and everything it has dropped as bag
--     icons -- a count on each until 20 kills, its drop rate after. The rest
--     fold to one line with their loot as small icons; click a band to open
--     or fold it. The Sort button orders the rest.
--   * Loot: everything looted, fished and gathered this session in one list,
--     best earners first, medals on the top three, and where each came from.
--
-- Items are drawn the way the bags draw them, icon and quality colour, both
-- remembered from the loot window by the tracker. Click an item icon for
-- that mob's whole loot table (UI/LootTable.lua). The wheel scrolls.
--
-- /farm tracker (or its X) turns it off and on, and it stays that way from one
-- session to the next. Drag it if the left edge is busy. In a party or raid it
-- steps aside from the group frames (see "In a group" at the bottom).

local _, ns = ...

local TrackerUI = ns.NewModule("TrackerUI")

local Theme = ns.Theme
local Widgets = ns.Widgets
local Util = ns.Util

-- The starting size. Drag the corner grip to change it; the size is saved.
local WIDTH = 260
local HEIGHT = 420

-- How small and how large the grip will let it go.
local MIN_WIDTH, MAX_WIDTH = 180, 600
local MIN_HEIGHT, MAX_HEIGHT = 120, 1000
local PADDING = 8
-- The title bar: "Kills & Loot" and the X on top, the session's gathered
-- value on a second line under them.
local TITLE_LINE = 28
local TOTAL_LINE = 20
local HEADER = TITLE_LINE + TOTAL_LINE
TrackerUI.HEADER = HEADER
-- The Farm and Loot tabs under it, then the toolbar with the Sort button.
local TAB_HEIGHT = 22
local TOOLBAR = 22
local TOP = HEADER + TAB_HEIGHT + TOOLBAR
TrackerUI.TOP = TOP
local LINE = 18
local ICON = 14
local BAR = 40
TrackerUI.BAR = BAR

-- The progress bar toward rates (Trent, 2026-09-27: "a progress bar like
-- the goals"): as tall as a goal's, never shorter than MIN_PROGRESS.
local PROGRESS_HEIGHT = 7
local MIN_PROGRESS = 60
local BRIGHT_GOLD = { 1, 0.906, 0.639 }
local GREEN_TIP = { 0.66, 1, 0.77 }

-- Marks on the bar, and the last stretch that turns it green: a goal's.
local MARKS = { 0.25, 0.5, 0.75 }
local FINAL = 0.1

-- Right-hand value and the green badge beside it, in pixels.
local RIGHT_WIDTH = 54
local BADGE_WIDTH = 28

-- A kill streak shows once it reaches this many.
local STREAK_SHOWN = 3

-- An open card's loot, as bag slots, and a folded card's as small icons.
local SLOT = 30
local SLOT_GAP = 4
local MINI = 12
local MINIS = 6
TrackerUI.SLOT = SLOT

-- A Loot tab row: two lines, its icon, and the rank's medal.
local LOOT_ROW = 32
local LOOT_ICON = 22
local MEDAL = 14
-- How many sources an item names before "+2 more".
local SOURCES_SHOWN = 2

-- The Rankings tab's medals: gold, silver, bronze.
local MEDALS = {
    { 1.00, 0.82, 0.30 },
    { 0.78, 0.80, 0.84 },
    { 0.80, 0.52, 0.30 },
}

-- Lines the wheel moves at a time.
local SCROLL_STEP = 2

-- Per hour shows once the session has run this long, in seconds; before
-- that one lucky drop would say you earn a fortune.
local PER_HOUR_AFTER = 300

-- Bumped when the default position moves, so a panel saved at the old spot
-- comes to the new one once instead of staying where nobody asked for it.
local LAYOUT = 2

local FALLBACK_ICON = [[Interface\Icons\INV_Misc_QuestionMark]]
local PLACE_ICON = [[Interface\Icons\INV_Misc_Map_01]]

--- A rate worth staying for should look different from one that is not.
local function RateColor(chance)
    if chance >= 40 then return "good" end
    if chance >= 15 then return "accent" end
    return "muted"
end

--- A "ffrrggbb" colour as the four numbers SetTextColor takes.
local function HexColor(hex)
    if type(hex) ~= "string" or #hex ~= 8 then return nil end

    local r = tonumber(hex:sub(3, 4), 16)
    local g = tonumber(hex:sub(5, 6), 16)
    local b = tonumber(hex:sub(7, 8), 16)
    if not (r and g and b) then return nil end

    return r / 255, g / 255, b / 255, 1
end

--------------------------------------------------------------------------------
-- Size
--
-- The width is exactly what you drag it to. The height you drag to is the
-- tallest it grows: a short session still gets a short panel, and a long one
-- fills down to where you put the bottom edge and says what did not fit.
--------------------------------------------------------------------------------

local function Clamp(value, low, high)
    value = tonumber(value)
    if not value then return nil end
    return math.max(low, math.min(high, value))
end

function TrackerUI:Width()
    return Clamp(ns.db and ns.db.trackerWidth, MIN_WIDTH, MAX_WIDTH) or WIDTH
end

--- The panel's width for lines that need `needs` pixels: the saved width, or
--- wider up to MAX_WIDTH.
function TrackerUI:FitWidth(needs)
    return math.min(MAX_WIDTH, math.max(self:Width(), math.ceil(tonumber(needs) or 0)))
end

function TrackerUI:MaxHeight()
    return Clamp(ns.db and ns.db.trackerHeight, MIN_HEIGHT, MAX_HEIGHT) or HEIGHT
end

--- How many lines fit under the header at a given height.
function TrackerUI:LinesFor(height)
    return math.max(2, math.floor((height - HEADER - PADDING * 2) / LINE))
end

--- Row `index`, made the first time it is needed.
function TrackerUI:Line(index)
    local row = self.lines[index]
    if not row then
        row = self:CreateLine(self.frame, index)
        self.lines[index] = row
    end
    return row
end

function TrackerUI:SaveSize()
    if not (ns.db and self.frame) then return end

    ns.db.trackerWidth = math.floor(self.frame:GetWidth() + 0.5)
    ns.db.trackerHeight = math.floor(self.frame:GetHeight() + 0.5)
end

--- The corner grip. Drag it and the panel follows; let go and it keeps that.
function TrackerUI:BuildGrip(frame)
    frame:SetResizable(true)

    -- Retail spells the limits one way and older clients another; try both,
    -- and let neither's absence stop the panel from building.
    if not pcall(frame.SetResizeBounds, frame, MIN_WIDTH, MIN_HEIGHT, MAX_WIDTH, MAX_HEIGHT) then
        pcall(frame.SetMinResize, frame, MIN_WIDTH, MIN_HEIGHT)
        pcall(frame.SetMaxResize, frame, MAX_WIDTH, MAX_HEIGHT)
    end

    local grip = CreateFrame("Button", nil, frame)
    grip:SetSize(14, 14)
    grip:SetPoint("BOTTOMRIGHT", -2, 2)
    grip:SetFrameLevel(frame:GetFrameLevel() + 5)
    grip:EnableMouse(true)

    pcall(grip.SetNormalTexture, grip, [[Interface\ChatFrame\UI-ChatIM-SizeGrabber-Up]])
    pcall(grip.SetHighlightTexture, grip, [[Interface\ChatFrame\UI-ChatIM-SizeGrabber-Highlight]])
    pcall(grip.SetPushedTexture, grip, [[Interface\ChatFrame\UI-ChatIM-SizeGrabber-Down]])

    grip:SetScript("OnMouseDown", function()
        TrackerUI.sizing = true
        -- Pin the top first, so the panel grows downward from where it is.
        TrackerUI:AnchorTop()
        -- Start from the size on screen, so the corner stays under the
        -- cursor. Changing the height here would move the corner away from
        -- the mouse, and the drag would keep that gap the whole way.
        frame:StartSizing("BOTTOMRIGHT")
    end)

    grip:SetScript("OnMouseUp", function()
        frame:StopMovingOrSizing()
        TrackerUI.sizing = false
        TrackerUI.tabNeeds = nil
        TrackerUI:AnchorTop()
        TrackerUI:SaveSize()
        -- Resizing is not picking a spot; in a group it stays beside the
        -- group frames rather than being pinned where it happens to be.
        if not TrackerUI.grouped then TrackerUI:SavePosition() end
        TrackerUI:Render()
    end)

    -- Redraw while dragging, so you see what fits as you go.
    frame:SetScript("OnSizeChanged", function()
        if TrackerUI.sizing then TrackerUI:Render() end
    end)

    self.grip = grip
end

--------------------------------------------------------------------------------
-- Construction
--------------------------------------------------------------------------------

local TABS = {
    { key = "farm", label = "Farm" },
    { key = "loot", label = "Loot" },
}

-- What each tab's Sort button steps through, first the default.
local SORTS = {
    farm = { { key = "recent", label = "Recent" }, { key = "worth", label = "Worth per kill" },
        { key = "kills", label = "Kills" }, { key = "value", label = "Loot value" } },
    loot = { { key = "value", label = "Value" }, { key = "count", label = "Count" },
        { key = "name", label = "Name" } },
}
TrackerUI.SORTS = SORTS

--- The tab showing: "farm" or "loot".
function TrackerUI:Tab()
    local tab = ns.db and ns.db.trackerTab
    return tab == "loot" and "loot" or "farm"
end

--- The Sort button's choice on `tab`, one of SORTS[tab]'s keys.
function TrackerUI:Sort(tab)
    tab = tab or self:Tab()
    local saved = ns.db and ns.db[tab == "loot" and "trackerLootSort" or "trackerSort"]
    for _, sort in ipairs(SORTS[tab]) do
        if sort.key == saved then return sort.key, sort.label end
    end
    return SORTS[tab][1].key, SORTS[tab][1].label
end

function TrackerUI:SetTab(tab)
    if not ns.db or tab == self:Tab() then return end
    ns.db.trackerTab = tab
    self.scroll = 0
    -- What the new tab shows was not just gained: take note, play nothing.
    if ns.TrackerFX and ns.TrackerFX.Rebase then ns.TrackerFX:Rebase() end
    self:Refresh()
end

--- The next way of sorting the tab showing.
function TrackerUI:NextSort()
    local tab = self:Tab()
    local current = self:Sort(tab)
    local list = SORTS[tab]
    local nextKey = list[1].key

    for index, sort in ipairs(list) do
        if sort.key == current then nextKey = list[index % #list + 1].key end
    end

    ns.db[tab == "loot" and "trackerLootSort" or "trackerSort"] = nextKey
    self.scroll = 0
    if ns.TrackerFX and ns.TrackerFX.Rebase then ns.TrackerFX:Rebase() end
    self:Refresh()
end

--- Whether a card is open. The one you are on is open unless you folded it;
--- the rest are folded unless you opened them (Trent, 2026-09-28).
function TrackerUI:IsOpen(key, default)
    local chosen = self.open and self.open[key]
    if chosen ~= nil then return chosen end
    return default and true or false
end

function TrackerUI:Toggle(key, default)
    self.open = self.open or {}
    self.open[key] = not self:IsOpen(key, default)
    if ns.TrackerFX and ns.TrackerFX.Rebase then ns.TrackerFX:Rebase() end
    self:Refresh()
end

function TrackerUI:Build()
    if self.frame then return self.frame end

    local frame = CreateFrame("Frame", "BlackthornesFarmerTracker", UIParent)
    frame:SetSize(self:Width(), self:MaxHeight())
    frame:SetFrameStrata("LOW")
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")

    Theme.Fill(frame, "window", 0.88)
    Theme.Border(frame, "border")

    frame:SetScript("OnDragStart", function(self)
        TrackerUI.dragging = true
        self:StartMoving()
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        TrackerUI.dragging = false
        TrackerUI:AnchorTop()
        TrackerUI:SavePosition()
    end)

    -- The wheel scrolls the column rather than cutting it off.
    pcall(frame.EnableMouseWheel, frame, true)
    frame:SetScript("OnMouseWheel", function(_, delta)
        TrackerUI:ScrollBy(-(tonumber(delta) or 0) * SCROLL_STEP)
    end)

    -- Title bar: the house header, with an accent stripe down its left edge
    -- so the panel reads as part of the same set as the search window.
    local header = Theme.CreatePanel(frame, "header", false)
    header:SetPoint("TOPLEFT")
    header:SetPoint("TOPRIGHT")
    header:SetHeight(HEADER)

    Theme.HouseHeader(header)

    local title = Theme.CreateLabel(header, "normal", "accent")
    title:SetPoint("LEFT", header, "TOPLEFT", PADDING + 4, -TITLE_LINE / 2)
    title:SetText("Kills & Loot")

    local close = Widgets.CreateButton(header, "X", function()
        ns.db.trackerHidden = true
        TrackerUI:Refresh()
        ns.Print("kill and loot panel hidden. /farm tracker brings it back.")
    end, { width = 18, height = 16, danger = true })
    close:SetPoint("RIGHT", header, "TOPRIGHT", -6, -TITLE_LINE / 2)

    -- The session's gathered value on the title bar's second line (Trent,
    -- 2026-09-27). Built like a line row so the count-up, glow and "+38s" in
    -- UI/TrackerFX.lua work on it unchanged.
    local total = CreateFrame("Frame", nil, header)
    total:SetPoint("TOPLEFT", header, "TOPLEFT", 3, -TITLE_LINE + 2)
    total:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", 0, 2)

    total.left = Theme.CreateLabel(total, "small", "muted")
    total.left:SetPoint("LEFT", PADDING + 1, 0)
    total.left:SetText("Gathered value")

    total.right = Theme.CreateLabel(total, "normal", "good", "RIGHT")
    total.right:SetPoint("RIGHT", -PADDING, 0)

    total.badge = Theme.CreateLabel(total, "tiny", "good", "RIGHT")
    total.badge:SetPoint("RIGHT", total.right, "LEFT", -4, 0)

    self.frame = frame
    self.title = title
    self.titleRow = total
    self.header = header
    self.closeButton = close
    self.lines = {}
    self.cards = {}
    self.scroll = self.scroll or 0

    self:BuildTabs(frame)
    self:BuildToolbar(frame)

    local rule = Theme.CreateDivider(frame, "borderLit")
    rule:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -TOP)
    rule:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, -TOP)

    -- "12 more below" at the bottom edge while the column scrolls.
    local more = Theme.CreateLabel(frame, "tiny", "muted", "RIGHT")
    more:SetPoint("BOTTOMRIGHT", -20, 4)
    more:Hide()
    self.moreLabel = more

    -- While the column scrolls, its cut edges fade into the panel rather
    -- than stopping hard, so it reads as more above or below.
    self.fadeTop = self:BuildFade(frame, "TOP")
    self.fadeBottom = self:BuildFade(frame, "BOTTOM")

    self:BuildGrip(frame)

    self:RestorePosition()
    frame:Hide()

    return frame
end

--- A soft fade over one cut edge of the column, above the rows.
function TrackerUI:BuildFade(frame, side)
    local fade = Widgets.CreateFade(frame, side, "window", 16)
    if not fade then return nil end
    if side == "TOP" then
        fade:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -(TOP + 1))
        fade:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -1, -(TOP + 1))
    else
        fade:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 1, 14)
        fade:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -1, 14)
    end
    return fade
end

--- The Farm and Loot tabs under the title bar: a gold line under the one
--- showing that slides to the other when you pick it, and a green dot on
--- the other when something new lands there.
function TrackerUI:BuildTabs(frame)
    local strip = CreateFrame("Frame", nil, frame)
    strip:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -HEADER)
    strip:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -1, -HEADER)
    strip:SetHeight(TAB_HEIGHT)
    Theme.Fill(strip, "header", 0.7)

    self.tabs = {}

    for index, spec in ipairs(TABS) do
        local tab = CreateFrame("Button", nil, strip)
        tab:SetHeight(TAB_HEIGHT)
        tab.key = spec.key
        tab.index = index

        tab.hover = Theme.Fill(tab, "rowHover", 0.5, "BORDER")
        tab.hover:Hide()

        tab.label = Theme.CreateLabel(tab, "small", "muted", "CENTER")
        tab.label:SetPoint("CENTER", -6, 0)
        tab.label:SetText(spec.label)

        -- How many there are, beside the name.
        tab.count = Theme.CreateLabel(tab, "tiny", "muted", "LEFT")
        tab.count:SetPoint("LEFT", tab.label, "RIGHT", 4, 0)

        tab.dot = tab:CreateTexture(nil, "OVERLAY")
        tab.dot:SetSize(6, 6)
        tab.dot:SetPoint("LEFT", tab.count, "RIGHT", 4, 3)
        tab.dot:SetColorTexture(Theme.Unpack("good"))
        tab.dot:Hide()

        tab:SetScript("OnEnter", function(self) self.hover:Show() end)
        tab:SetScript("OnLeave", function(self) self.hover:Hide() end)
        tab:SetScript("OnClick", function(self) TrackerUI:SetTab(self.key) end)

        self.tabs[index] = tab
    end

    -- The gold line, and its glow, under the tab showing.
    local line = strip:CreateTexture(nil, "OVERLAY")
    line:SetHeight(2)
    line:SetColorTexture(Theme.Unpack("accent"))
    local glow = strip:CreateTexture(nil, "ARTWORK")
    glow:SetHeight(6)
    glow:SetColorTexture(Theme.Unpack("accent", 0.25))
    pcall(glow.SetBlendMode, glow, "ADD")

    self.tabStrip = strip
    self.tabLine = line
    self.tabGlow = glow
end

--- Lay the tabs out across the panel's width and put the gold line under
--- the one showing, sliding it there when it moved.
function TrackerUI:DrawTabs(counts)
    local width = tonumber(self.frame:GetWidth()) or self:Width()
    local each = (width - 2) / #self.tabs
    local showing = self:Tab()

    for _, tab in ipairs(self.tabs) do
        tab:ClearAllPoints()
        tab:SetPoint("TOPLEFT", self.tabStrip, "TOPLEFT", (tab.index - 1) * each, 0)
        tab:SetWidth(each)

        local on = tab.key == showing
        tab.label:SetTextColor(Theme.Unpack(on and "text" or "muted"))
        if on then tab.label:SetTextColor(BRIGHT_GOLD[1], BRIGHT_GOLD[2], BRIGHT_GOLD[3], 1) end

        local count = counts and counts[tab.key]
        tab.count:SetText(count and count > 0 and tostring(count) or "")
        tab.dot:SetShown(not on and self.dots and self.dots[tab.key] == true)
    end

    local index = showing == "loot" and 2 or 1
    local inset = math.floor(each * 0.18)
    local target = (index - 1) * each + inset
    local lineWidth = math.max(10, each - inset * 2)

    local function Place(x)
        self.tabLine:ClearAllPoints()
        self.tabLine:SetPoint("BOTTOMLEFT", self.tabStrip, "BOTTOMLEFT", x, 0)
        self.tabLine:SetWidth(lineWidth)
        self.tabGlow:ClearAllPoints()
        self.tabGlow:SetPoint("BOTTOMLEFT", self.tabStrip, "BOTTOMLEFT", x - 2, 0)
        self.tabGlow:SetWidth(lineWidth + 4)
    end

    local from = self.tabLineX
    self.tabLineX = target
    if ns.Motion and from and from ~= target and not self.sizing then
        ns.Motion:Run(self, "tabline", 0.25, function(p) Place(from + (target - from) * p) end)
    else
        Place(target)
    end
end

--- Under the tabs: what the session is earning on the left, and the Sort
--- button on the right.
function TrackerUI:BuildToolbar(frame)
    local bar = CreateFrame("Frame", nil, frame)
    bar:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -(HEADER + TAB_HEIGHT))
    bar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -1, -(HEADER + TAB_HEIGHT))
    bar:SetHeight(TOOLBAR)
    Theme.Fill(bar, "rowAlt", 0.8)

    bar.left = Theme.CreateLabel(bar, "small", "muted")
    bar.left:SetPoint("LEFT", PADDING, 0)

    bar.sort = Widgets.CreateButton(bar, "Sort: Recent", function() TrackerUI:NextSort() end,
        { width = 60, height = 16 })
    bar.sort:SetPoint("RIGHT", -PADDING + 2, 0)
    bar.sort:SetScript("OnEnter", function(self)
        if self.Light then ns.Motion:Blend(self, "hover", 1, 0.12, self.Light) end
        if GameTooltip then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine("Sort")
            GameTooltip:AddLine("Click for the next order.", 1, 1, 1)
            GameTooltip:Show()
        end
    end)
    bar.sort:SetScript("OnLeave", function(self)
        if self.Light then ns.Motion:Blend(self, "hover", 0, 0.18, self.Light) end
        if GameTooltip then GameTooltip:Hide() end
    end)

    self.toolbar = bar
end

--- The toolbar's words. Returns how wide the panel must be for them.
function TrackerUI:DrawToolbar()
    local bar = self.toolbar
    local tab = self:Tab()
    local _, label = self:Sort(tab)
    bar.sort:SetText("Sort: " .. label)

    local text
    if tab == "loot" then
        local looted = 0
        for _, count in pairs(ns.Tracker.sessionLoot or {}) do looted = looted + count end
        for _, count in pairs(ns.Fishing and ns.Fishing.sessionCatch or {}) do looted = looted + count end
        for _, count in pairs(ns.Gathering and ns.Gathering.sessionItems or {}) do looted = looted + count end
        text = ("%d looted"):format(looted)
    else
        local hour = self:PerHour()
        text = hour and ("Per hour  " .. ns.Value.Coins(hour)) or "This session"
    end

    bar.left:SetText(text)

    local sortWidth = tonumber(bar.sort:GetWidth()) or 60
    return PADDING + Theme.TextWidth("small", Util.StripColor(text)) + 12 + sortWidth + PADDING
end

--- What the session is earning an hour, in copper, once it has run long
--- enough to mean something. Timed from the first thing gathered.
function TrackerUI:PerHour()
    local total = self:NoteStart()
    local now = type(GetTime) == "function" and GetTime() or nil
    if not (total and self.startedAt and type(now) == "number") then return nil end

    local elapsed = now - self.startedAt
    if elapsed < PER_HOUR_AFTER then return nil end

    return total / elapsed * 3600
end

--- Start the per-hour clock at the first thing gathered, and stop it when
--- the session is cleared. Called on every refresh, shown or not: timed
--- only from when the panel was first drawn, a panel opened an hour into a
--- session said you earned a fortune. Returns the session's value.
function TrackerUI:NoteStart()
    local total = ns.Value and ns.Value:Session()
    if not (total and total > 0) then
        self.startedAt = nil
        return nil
    end

    if not self.startedAt and type(GetTime) == "function" then
        local ok, now = pcall(GetTime)
        if ok and type(now) == "number" then self.startedAt = now end
    end
    return total
end

--- One row of the column. Every row can be any kind of line; DrawLine
--- decides which parts to show and Render where it goes.
function TrackerUI:CreateLine(parent, index)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(LINE)
    row:SetFrameLevel(parent:GetFrameLevel() + 3)

    -- A full-width band behind headings and mob names, so the column reads as
    -- blocks rather than one long list.
    row.band = Theme.Fill(row, "row", 0.9)

    -- The card you are on: a gold wash fading across and a bright edge.
    row.live = row:CreateTexture(nil, "BACKGROUND", nil, 2)
    row.live:SetAllPoints(row)
    row.live:SetColorTexture(1, 1, 1, 1)
    row.live:Hide()

    row.edge = row:CreateTexture(nil, "ARTWORK")
    row.edge:SetPoint("TOPLEFT")
    row.edge:SetPoint("BOTTOMLEFT")
    row.edge:SetWidth(2)
    row.edge:Hide()

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(ICON, ICON)
    row.icon:SetPoint("LEFT", PADDING + 6, 0)
    -- Trim the icon's built-in border, as the bags do.
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    -- Anchored at both ends rather than given a width, so it stretches with
    -- the panel; DrawLine sets where it stops.
    row.left = Theme.CreateLabel(row, "small", "text")
    row.left:SetPoint("LEFT", PADDING, 0)
    row.left:SetPoint("RIGHT", -PADDING, 0)

    -- A second, smaller line under the name, on the Loot tab.
    row.sub = Theme.CreateLabel(row, "tiny", "muted")
    row.sub:Hide()

    row.right = Theme.CreateLabel(row, "small", "muted", "RIGHT")
    row.right:SetPoint("RIGHT", -PADDING, 0)
    row.right:SetWidth(RIGHT_WIDTH)

    row.below = Theme.CreateLabel(row, "tiny", "good", "RIGHT")
    row.below:Hide()

    row.badge = Theme.CreateLabel(row, "tiny", "good", "RIGHT")
    row.badge:SetPoint("RIGHT", row.right, "LEFT", -2, 0)
    row.badge:SetWidth(BADGE_WIDTH)

    -- The Loot tab's rank, on a medal for the top three.
    row.medal = row:CreateTexture(nil, "ARTWORK")
    row.medal:SetSize(MEDAL, MEDAL)
    row.medal:Hide()
    row.rank = Theme.CreateLabel(row, "tiny", "muted", "CENTER")
    row.rank:Hide()

    -- A thin bar under the value: a drop rate, or kills toward MIN_KILLS.
    row.track = row:CreateTexture(nil, "BORDER")
    row.track:SetPoint("BOTTOMRIGHT", -PADDING, 1)
    row.track:SetSize(BAR, 2)
    row.track:SetColorTexture(Theme.Unpack("rowAlt"))

    row.fill = row:CreateTexture(nil, "ARTWORK")
    row.fill:SetPoint("BOTTOMLEFT", row.track, "BOTTOMLEFT")
    row.fill:SetHeight(2)

    -- A folded card's loot, as small icons before its kills.
    row.minis = {}

    -- An open card's loot, as bag slots (made as needed).
    row.slots = {}

    -- The progress bar, the Goals panel's: a dark track, the fill, a
    -- brighter tip, the part just gained, a shine, and the quarter marks.
    -- DrawLine sets where the track runs.
    local bar = {}
    row.progress = bar

    bar.track = row:CreateTexture(nil, "BORDER")
    bar.track:SetHeight(PROGRESS_HEIGHT)
    bar.track:SetColorTexture(Theme.Unpack("row"))

    bar.fill = row:CreateTexture(nil, "ARTWORK")
    bar.fill:SetPoint("TOPLEFT", bar.track, "TOPLEFT")
    bar.fill:SetHeight(PROGRESS_HEIGHT)

    bar.tip = row:CreateTexture(nil, "OVERLAY")
    bar.tip:SetPoint("TOPRIGHT", bar.fill, "TOPRIGHT")
    bar.tip:SetSize(4, PROGRESS_HEIGHT)

    bar.fresh = row:CreateTexture(nil, "OVERLAY")
    bar.fresh:SetHeight(PROGRESS_HEIGHT)
    bar.fresh:SetColorTexture(1, 0.95, 0.8, 1)
    pcall(bar.fresh.SetBlendMode, bar.fresh, "ADD")
    bar.fresh:SetAlpha(0)

    bar.shine = row:CreateTexture(nil, "OVERLAY")
    bar.shine:SetHeight(PROGRESS_HEIGHT)
    bar.shine:SetColorTexture(1, 1, 1, 1)
    pcall(bar.shine.SetBlendMode, bar.shine, "ADD")
    bar.shine:SetAlpha(0)

    bar.marks = {}
    for index = 1, #MARKS do
        local mark = row:CreateTexture(nil, "OVERLAY")
        mark:SetSize(1, PROGRESS_HEIGHT)
        mark:SetColorTexture(1, 1, 1, 0.22)
        bar.marks[index] = mark
    end

    bar.parts = { bar.track, bar.fill, bar.tip, bar.fresh, bar.shine }
    for _, mark in ipairs(bar.marks) do bar.parts[#bar.parts + 1] = mark end

    -- A card's band folds and opens it.
    row.dragged = false
    row.hover = Theme.Fill(row, "rowHover", 0.7, "BORDER")
    row.hover:Hide()

    row:SetScript("OnEnter", function(self)
        local line = self.line
        if not (line and (line.openKey or line.mob)) then return end
        self.hover:Show()

        if GameTooltip then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(line.left)
            if line.openKey then
                GameTooltip:AddLine(line.folded and "Click to show its loot." or "Click to fold it.",
                    1, 1, 1)
                if line.mob then
                    GameTooltip:AddLine("Click an item for everything it has dropped.", 1, 1, 1)
                end
            else
                GameTooltip:AddLine("Click for everything it has dropped.", 1, 1, 1)
            end
            GameTooltip:Show()
        end
    end)

    row:SetScript("OnLeave", function(self)
        self.hover:Hide()
        if GameTooltip then GameTooltip:Hide() end
    end)

    row:SetScript("OnMouseUp", function(self, button)
        -- Letting go at the end of a drag is not a click.
        if self.dragged then
            self.dragged = false
            return
        end

        local line = self.line
        if button ~= "LeftButton" or not line then return end

        if line.openKey then
            TrackerUI:Toggle(line.openKey, line.openDefault)
        elseif line.mob and ns.LootTableUI then
            ns.LootTableUI:Toggle(line.mob)
        end
    end)

    -- A row that takes the mouse would stop the panel dragging from it;
    -- hand the drag on to the panel.
    row:RegisterForDrag("LeftButton")
    row:SetScript("OnDragStart", function(self)
        self.dragged = true
        local start = parent:GetScript("OnDragStart")
        if start then start(parent) end
    end)
    row:SetScript("OnDragStop", function()
        local stop = parent:GetScript("OnDragStop")
        if stop then stop(parent) end
    end)
    row:SetScript("OnMouseWheel", function(_, delta)
        TrackerUI:ScrollBy(-(tonumber(delta) or 0) * SCROLL_STEP)
    end)

    return row
end

--- Slot `index` of a row's loot icons, made the first time it is needed:
--- the item's icon on a quality-coloured edge, its count or rate in the
--- corner, and what the effects light up (a glow, "+2", a NEW tag).
function TrackerUI:Slot(row, index)
    local slot = row.slots[index]
    if slot then return slot end

    slot = CreateFrame("Button", nil, row)
    slot:SetSize(SLOT, SLOT)
    slot.dragged = false
    slot:SetFrameLevel(row:GetFrameLevel() + 2)

    Theme.Fill(slot, "window", 0.9)
    slot.glow = slot:CreateTexture(nil, "BACKGROUND", nil, 1)
    slot.glow:SetPoint("TOPLEFT", -3, 3)
    slot.glow:SetPoint("BOTTOMRIGHT", 3, -3)
    slot.glow:SetColorTexture(1, 1, 1, 1)
    pcall(slot.glow.SetBlendMode, slot.glow, "ADD")
    slot.glow:SetAlpha(0)

    slot.icon = slot:CreateTexture(nil, "ARTWORK")
    slot.icon:SetPoint("TOPLEFT", 1, -1)
    slot.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    slot.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    Theme.Border(slot, "borderLit")

    -- A light that washes over the icon when its count goes up.
    slot.flash = slot:CreateTexture(nil, "OVERLAY")
    slot.flash:SetPoint("TOPLEFT", 1, -1)
    slot.flash:SetPoint("BOTTOMRIGHT", -1, 1)
    slot.flash:SetColorTexture(1, 1, 1, 1)
    pcall(slot.flash.SetBlendMode, slot.flash, "ADD")
    slot.flash:SetAlpha(0)

    slot.count = Theme.CreateLabel(slot, "tiny", "text", "RIGHT")
    pcall(slot.count.SetFont, slot.count, Theme.FONT, Theme.sizes.tiny, "OUTLINE")
    slot.count:SetPoint("BOTTOMRIGHT", -1, 2)

    slot.gain = Theme.CreateLabel(slot, "tiny", "good", "RIGHT")
    pcall(slot.gain.SetFont, slot.gain, Theme.FONT, Theme.sizes.tiny, "OUTLINE")
    slot.gain:SetPoint("TOPRIGHT", 4, 5)
    slot.gain:SetAlpha(0)

    slot.tag = slot:CreateTexture(nil, "OVERLAY", nil, 2)
    slot.tag:SetSize(24, 9)
    slot.tag:SetPoint("TOP", 0, 5)
    slot.tag:SetColorTexture(BRIGHT_GOLD[1], BRIGHT_GOLD[2], BRIGHT_GOLD[3], 1)
    slot.tag:SetAlpha(0)
    slot.tagText = Theme.CreateLabel(slot, "tiny", "window", "CENTER")
    pcall(slot.tagText.SetFont, slot.tagText, Theme.FONT, 8, "")
    slot.tagText:SetPoint("CENTER", slot.tag, "CENTER", 0, 0)
    slot.tagText:SetText("NEW")
    slot.tagText:SetTextColor(0.1, 0.08, 0.03, 1)
    slot.tagText:SetAlpha(0)

    slot.hover = slot:CreateTexture(nil, "HIGHLIGHT")
    slot.hover:SetAllPoints(slot.icon)
    slot.hover:SetColorTexture(1, 1, 1, 0.15)

    slot:SetScript("OnEnter", function(self) TrackerUI:SlotTooltip(self) end)
    slot:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    slot:SetScript("OnClick", function(self)
        if self.dragged then
            self.dragged = false
            return
        end
        local icon = self.line
        if icon and icon.mob and ns.LootTableUI then ns.LootTableUI:Toggle(icon.mob) end
    end)
    slot:RegisterForDrag("LeftButton")
    slot:SetScript("OnDragStart", function(self)
        self.dragged = true
        local panel = TrackerUI.frame
        local start = panel and panel:GetScript("OnDragStart")
        if start then start(panel) end
    end)
    slot:SetScript("OnDragStop", function()
        local panel = TrackerUI.frame
        local stop = panel and panel:GetScript("OnDragStop")
        if stop then stop(panel) end
    end)
    slot:SetScript("OnMouseWheel", function(_, delta)
        TrackerUI:ScrollBy(-(tonumber(delta) or 0) * SCROLL_STEP)
    end)

    row.slots[index] = slot
    return slot
end

--- An icon's name, what its number means, and what one is worth.
function TrackerUI:SlotTooltip(slot)
    local icon = slot.line
    if not (icon and GameTooltip) then return end

    GameTooltip:SetOwner(slot, "ANCHOR_RIGHT")
    local r, g, b = HexColor(ns.Tracker:LookOf(icon.item).color)
    GameTooltip:AddLine(icon.item, r or 1, g or 1, b or 1)
    if icon.about then GameTooltip:AddLine(icon.about, 1, 1, 1) end

    local unit = ns.Value and ns.Value:UnitPrice(ns.Value:ItemID(icon.item))
    if unit then GameTooltip:AddLine("Worth " .. ns.Value.Coins(unit) .. " each", 1, 1, 1) end

    if icon.mob then
        GameTooltip:AddLine("Click for everything it has dropped.", 0.6, 0.6, 0.6)
    end
    GameTooltip:Show()
end

--------------------------------------------------------------------------------
-- What goes in it
--
-- Built as a flat list of lines first, then drawn, so the layout rules live in
-- one place and a test can read the list without a frame.
--------------------------------------------------------------------------------

--- Every line the tab showing would hold, top to bottom.
--
-- Each is { style, left, right }, plus as it applies: `item` (a name whose
-- icon and colour to draw), `badge` (small green text beside the value),
-- `bar` (0-1) and `barColor`, `rightColor`, `mob` (a mob whose loot table a
-- click opens) and `openKey` (a card's band: a click folds or opens it).
-- A line whose number can go up also has a `key` that names it from one
-- redraw to the next and that `count`, so UI/TrackerFX.lua can tell what just
-- went up and make it move.
-- Styles: "heading", "mob" (a card's band; `folded` for one line with
-- `minis`, `live` for the card you are on), "place", "value", "item",
-- "note", "link", "progress" (the bar toward rates: `have`, `target`,
-- `progress` 0-1, `milestone` for the marks passed, `final` in the last
-- stretch), "icons" (an open card's loot as bag slots: `icons`, each
-- { item, text, key, count, about, mob }) and "loot" (a Loot tab item:
-- `sub` under the name, `below` under the count, `rank`).
-- A fishing spot or a node is drawn as a card with no `mob`.
function TrackerUI:Lines()
    local out = {}

    local function Add(line)
        line.right = line.right or ""
        out[#out + 1] = line
        return line
    end

    if self:Tab() == "loot" then
        self:LootLines(Add)
        return out
    end

    local mobs = ns.Tracker:SessionMobs()

    -- The Fishing and Gathering sections are there only once you have done
    -- that this session (Trent, 2026-09-25), and whichever you did last goes
    -- on top.
    local fished = ns.Fishing and ns.Fishing.sessionCasts > 0
    local gathered = ns.Gathering and ns.Gathering.sessionGathers > 0

    if #mobs == 0 and not fished and not gathered then
        Add({ style = "note", left = "Nothing killed yet this session." })
        Add({ style = "note", left = "Loot a corpse and it shows up here." })
        return out
    end

    local sections = {}

    if #mobs > 0 then
        sections[#sections + 1] = { key = "kill", draw = function(withTotal, first)
            self:KillLines(Add, mobs, first)
        end }
    end

    if fished then
        sections[#sections + 1] = { key = "fishing", draw = function(withTotal, first)
            self:FishingLines(Add, withTotal, first)
        end }
    end

    if gathered then
        sections[#sections + 1] = { key = "gathering", draw = function(withTotal, first)
            self:GatheringLines(Add, withTotal, first)
        end }
    end

    for index, section in ipairs(sections) do
        if section.key == ns.lastLoot and index > 1 then
            table.remove(sections, index)
            table.insert(sections, 1, section)
            break
        end
    end

    -- The haul's total goes with the kills when there are any, as it always
    -- has; otherwise under whichever heading is on top.
    for index, section in ipairs(sections) do
        section.draw(#mobs == 0 and index == 1, index == 1)
    end

    return out
end

--- "12 / 20", the first part bright, as a goal's count reads.
function TrackerUI.CountText(have, target)
    return ("%d|c%s / %d|r"):format(have, ns.COLORS.muted, target)
end

--- In the last stretch toward `target`: a few left, and the bar goes green.
function TrackerUI.Final(have, target)
    local left = target - have
    return left > 0 and left <= math.max(1, math.floor(target * FINAL))
end

--- Under a band still short of rates (Trent, 2026-09-27): a progress bar
--- like a goal's, then how many more. `key` is the band's; `more` is the
--- countdown's text, "%d" for the number.
function TrackerUI:ProgressLines(Add, key, have, target, more)
    have = math.max(0, math.min(have, target))
    local fraction = target > 0 and have / target or 0

    local milestone = 0
    for index, at in ipairs(MARKS) do
        if fraction >= at then milestone = index end
    end

    local final = TrackerUI.Final(have, target)
    Add({ style = "progress", key = key .. ":progress", count = have,
        have = have, target = target, progress = fraction,
        milestone = milestone, final = final,
        right = TrackerUI.CountText(have, target), rightColor = "text" })

    -- The last few say so in green, as a goal's do.
    local left = target - have
    Add({ style = "note", left = more:format(left) .. (final and "!" or ""),
        leftColor = final and "good" or nil })
end

--- One card: a mob, a fishing spot or a node (Trent, 2026-09-28: every
--- item it has given as bag icons, not just the top three).
--
-- Open, it is the band, where, the bar toward rates, what one is worth and
-- its loot as icons. Folded, it is the band alone with its loot as small
-- icons, so a long session still fits. `card` is:
-- { key, name, mob, total, session, rated, target, more, place, placeMore,
--   worth, worthLabel, items = { { name, n, chance } }, noun, open, default,
--   live }
function TrackerUI:CardLines(Add, card)
    local open = self:IsOpen(card.key, card.default)

    local band = Add({ style = "mob", left = card.name, mob = card.mob,
        openKey = card.key, openDefault = card.default, folded = not open,
        live = card.live and open or nil,
        right = tostring(card.total), badge = ("+%d"):format(card.session),
        key = card.key, count = card.total })

    if not open then
        -- Folded: kills toward rates as the thin bar under the count, and
        -- what it drops as small icons.
        if not card.rated then
            band.bar = card.target > 0 and card.total / card.target or 0
            band.barColor = TrackerUI.Final(card.total, card.target) and "good" or "accent"
        end
        band.minis = {}
        for index = 1, math.min(#card.items, MINIS) do
            band.minis[index] = card.items[index].name
        end
        return
    end

    if card.place then
        Add({ style = "place", left = card.place, right = card.placeMore })
    end

    if not card.rated then
        self:ProgressLines(Add, card.key, card.total, card.target, card.more)
    end

    if card.worth then
        Add({ style = "value", left = card.worthLabel,
            right = ns.Value.Coins(card.worth), rightColor = "good" })
    end

    if #card.items == 0 then
        if card.rated then Add({ style = "note", left = "nothing dropped yet" }) end
        return
    end

    local icons = {}
    for _, item in ipairs(card.items) do
        local icon = { item = item.name, mob = card.mob,
            key = ("%s:%s"):format(card.key, item.name), count = item.n }

        if card.rated then
            icon.text = ns.Tracker.FormatChance(item.chance)
            icon.textColor = RateColor(item.chance)
            icon.about = ("In %s of %s"):format(ns.Tracker.FormatChance(item.chance), card.noun)
        else
            icon.text = tostring(item.n)
            icon.about = ("%d of %d %s"):format(item.n, card.total, card.noun)
        end

        icons[#icons + 1] = icon
    end

    Add({ style = "icons", icons = icons, mob = card.mob, card = card.key, live = card.live })
end

--- The mobs in the order the Sort button says. The one you are on always
--- leads, open, whatever the order.
function TrackerUI:SortMobs(mobs)
    local sort = self:Sort("farm")
    if sort == "recent" then return mobs end

    local keyed = {}
    for _, summary in ipairs(mobs) do
        local value = 0
        if sort == "kills" then
            value = summary.session
        elseif sort == "worth" then
            value = ns.Value and ns.Value:ForMob(summary.mob) or 0
        elseif sort == "value" then
            value = self:MobLootValue(summary.mob)
        end
        keyed[#keyed + 1] = { summary = summary, value = tonumber(value) or 0 }
    end

    table.sort(keyed, function(a, b)
        if a.value ~= b.value then return a.value > b.value end
        return a.summary.mob < b.summary.mob
    end)

    local sorted = {}
    for index, entry in ipairs(keyed) do sorted[index] = entry.summary end
    return sorted
end

--- What a mob's loot this session is worth, in copper, from the items that
--- have a price.
function TrackerUI:MobLootValue(mob)
    local total = 0
    if not ns.Value then return total end

    for name, from in pairs(ns.Tracker.sessionFrom or {}) do
        local count = from[mob]
        if count then
            local unit = ns.Value:UnitPrice(ns.Value:ItemID(name))
            if unit then total = total + count * unit end
        end
    end
    return total
end

--- This session's kills: the heading, then a card for each mob killed.
function TrackerUI:KillLines(Add, mobs, first)
    local Tracker = ns.Tracker

    Add({ style = "heading", left = "THIS SESSION",
        right = Util.Plural(Tracker:SessionKills(), "kill") })

    self:TotalLines(Add)

    -- A streak shows from its third kill (Trent, 2026-09-26), with the
    -- session's best beside it once there is a better one to beat.
    local streak = Tracker:Streak()
    if streak >= STREAK_SHOWN then
        local best = Tracker.bestStreak
        Add({ style = "value", key = "streak", count = streak,
            left = best > streak and ("Kill streak  (best %d)"):format(best) or "Kill streak",
            right = ("x%d"):format(streak), rightColor = "accent" })
    end

    -- The mob you are on leads; the rest follow in the order picked.
    local current = Tracker.current
    local ordered = {}
    for _, summary in ipairs(mobs) do
        if summary.mob == current then table.insert(ordered, 1, summary) end
    end
    local rest = {}
    for _, summary in ipairs(mobs) do
        if summary.mob ~= current then rest[#rest + 1] = summary end
    end
    for _, summary in ipairs(self:SortMobs(rest)) do ordered[#ordered + 1] = summary end

    for _, summary in ipairs(ordered) do
        local worth, details
        if ns.Value then worth, details = ns.Value:ForMob(summary.mob) end

        local top = summary.places[1]
        local items = {}
        for _, item in ipairs(summary.items) do
            items[#items + 1] = { name = item.name, n = item.corpses, chance = item.chance }
        end

        local isCurrent = summary.mob == current
        self:CardLines(Add, {
            key = "mob:" .. summary.mob, name = summary.mob, mob = summary.mob,
            total = summary.kills, session = summary.session,
            rated = summary.rated, target = Tracker.MIN_KILLS,
            more = summary.needed == 1 and "%d more kill for drop rates" or "%d more kills for drop rates",
            place = top and top.name,
            placeMore = top and #summary.places > 1 and ("+%d more"):format(#summary.places - 1) or nil,
            worth = worth,
            worthLabel = details and details.basis == "tally" and "Worth per kill" or "Worth per kill (est.)",
            items = items, noun = "kills",
            default = isCurrent, live = isCurrent and first,
        })
    end
end

--- What everything gathered this session is worth (Trent, 2026-09-25): coin,
--- loot and fishing catches together, priced like worth per kill. Items with
--- no price are left out, so the total never guesses.
--
-- The total itself sits in the title bar (Trent, 2026-09-27). Returns its
-- line, or nil when nothing gathered this session has a price.
function TrackerUI:TitleTotal()
    if not ns.Value then return nil end

    local total = ns.Value:Session()
    if not total then return nil end

    return { style = "value", left = "Gathered value",
        right = ns.Value.Coins(total), rightColor = "good",
        key = "total", count = total }
end

--- The note under the top heading when some items had no price to count.
function TrackerUI:TotalLines(Add)
    if not ns.Value then return end

    local total, details = ns.Value:Session()
    if not total then return end

    local missing = #details.unpriced
    if missing > 0 then
        Add({ style = "note", left = ("%s with no price not counted"):format(
            Util.Plural(missing, "item")) })
    end
end

--- This session's fishing: a card for each spot fished, latest first.
function TrackerUI:FishingLines(Add, withTotal, first)
    local Fishing = ns.Fishing

    Add({ style = "heading", left = "FISHING",
        right = Util.Plural(Fishing.sessionCasts, "cast") })

    -- No kills this session and this on top: the haul's total goes here.
    if withTotal then self:TotalLines(Add) end

    for index, summary in ipairs(Fishing:SessionSpots()) do
        local items = {}
        for _, item in ipairs(summary.items) do
            items[#items + 1] = { name = item.name, n = item.casts, chance = item.chance }
        end

        self:CardLines(Add, {
            key = "spot:" .. tostring(summary.key),
            name = (summary.name:gsub("^%l", string.upper)),
            total = summary.casts, session = summary.session,
            rated = summary.rated, target = Fishing.MIN_CASTS,
            more = summary.needed == 1 and "%d more cast for catch rates" or "%d more casts for catch rates",
            place = summary.place,
            worth = Fishing:WorthPerCast(summary.key), worthLabel = "Worth per cast",
            items = items, noun = "casts",
            default = index == 1, live = index == 1 and first,
        })
    end
end

--- This session's gathering: a card for each herb or vein, latest first.
function TrackerUI:GatheringLines(Add, withTotal, first)
    local Gathering = ns.Gathering

    Add({ style = "heading", left = "GATHERING",
        right = Util.Plural(Gathering.sessionGathers, "gather") })

    if withTotal then self:TotalLines(Add) end

    for index, summary in ipairs(Gathering:SessionNodes()) do
        local items = {}
        for _, item in ipairs(summary.items) do
            items[#items + 1] = { name = item.name, n = item.gathers, chance = item.chance }
        end

        self:CardLines(Add, {
            key = "node:" .. tostring(summary.key), name = summary.name,
            total = summary.gathers, session = summary.session,
            rated = summary.rated, target = Gathering.MIN_GATHERS,
            more = "%d more for gather rates",
            place = summary.place,
            worth = Gathering:WorthPerGather(summary.key), worthLabel = "Worth per node",
            items = items, noun = "gathers",
            default = index == 1, live = index == 1 and first,
        })
    end
end

--------------------------------------------------------------------------------
-- The Loot tab
--
-- Everything looted, fished and gathered this session in one list (Trent,
-- 2026-09-28), best earners first, with where each came from under its name.
--------------------------------------------------------------------------------

--- "Rabid Gnoll 7, Mangy Wolf 3, +2 more" from { [source] = count }, and
--- the short form, "Rabid Gnoll 7, +2 more", for a narrow panel.
local function SourcesText(sources)
    local list = {}
    for name, count in pairs(sources) do list[#list + 1] = { name = name, count = count } end
    table.sort(list, function(a, b)
        if a.count ~= b.count then return a.count > b.count end
        return a.name < b.name
    end)

    local function Text(shown)
        local parts = {}
        for index = 1, math.min(#list, shown) do
            parts[index] = ("%s %d"):format(list[index].name, list[index].count)
        end
        if #list > shown then parts[#parts + 1] = ("+%d more"):format(#list - shown) end
        return table.concat(parts, ", ")
    end

    return Text(SOURCES_SHOWN), Text(1)
end

--- This session's items: { name, count, value (copper or nil), sources }.
function TrackerUI:SessionItems()
    local byName = {}

    local function Take(counts, fromTable, label)
        for name, count in pairs(counts or {}) do
            local entry = byName[name]
            if not entry then
                entry = { name = name, count = 0, sources = {} }
                byName[name] = entry
            end
            entry.count = entry.count + count

            local from = fromTable and fromTable[name]
            if type(from) == "table" and next(from) then
                for source, n in pairs(from) do
                    entry.sources[source] = (entry.sources[source] or 0) + n
                end
            elseif label then
                entry.sources[label] = (entry.sources[label] or 0) + count
            end
        end
    end

    Take(ns.Tracker.sessionLoot, ns.Tracker.sessionFrom, nil)
    if ns.Fishing then Take(ns.Fishing.sessionCatch, nil, "Fishing") end
    if ns.Gathering then Take(ns.Gathering.sessionItems, ns.Gathering.sessionFrom, "Gathering") end

    local items = {}
    for _, entry in pairs(byName) do
        local unit = ns.Value and ns.Value:UnitPrice(ns.Value:ItemID(entry.name))
        entry.value = unit and entry.count * unit or nil
        items[#items + 1] = entry
    end

    local sort = self:Sort("loot")
    table.sort(items, function(a, b)
        if sort == "count" and a.count ~= b.count then return a.count > b.count end
        if sort == "value" then
            local va, vb = a.value or -1, b.value or -1
            if va ~= vb then return va > vb end
        end
        return a.name < b.name
    end)

    return items
end

function TrackerUI:LootLines(Add)
    local items = self:SessionItems()

    if #items == 0 then
        Add({ style = "note", left = "No loot yet this session." })
        Add({ style = "note", left = "Everything you loot, fish or gather lands here." })
        return
    end

    for rank, entry in ipairs(items) do
        local sub, short = SourcesText(entry.sources)
        Add({ style = "loot", item = entry.name, left = entry.name,
            sub = sub, subShort = short, rank = rank,
            right = ("x%d"):format(entry.count),
            below = entry.value and ns.Value.Coins(entry.value) or "no price",
            belowColor = entry.value and "good" or "muted",
            key = "loot:" .. entry.name, count = entry.count })
    end

    local coin = tonumber(ns.Tracker.sessionCopper) or 0
    if coin > 0 then
        Add({ style = "value", left = "Coin from kills", right = ns.Value.Coins(coin),
            rightColor = "good" })
    end

    self:TotalLines(Add)
end

--------------------------------------------------------------------------------
-- Drawing
--------------------------------------------------------------------------------

local BAND = {
    heading = { key = "header", alpha = 1 },
    mob     = { key = "row", alpha = 0.9 },
}

--- How tall a line is drawn. Icons wrap to the panel's width.
function TrackerUI:LineHeight(line, width)
    if line.style == "loot" then return LOOT_ROW end
    if line.style == "icons" then
        local perRow = self:SlotsPerRow(width)
        local rows = math.max(1, math.ceil(#line.icons / perRow))
        return rows * (SLOT + SLOT_GAP) + 6
    end
    if line.style == "mob" and not line.folded then return LINE + 4 end
    return LINE
end

function TrackerUI:SlotsPerRow(width)
    width = tonumber(width) or self:Width()
    return math.max(1, math.floor((width - 2 - PADDING * 2 - 4 + SLOT_GAP) / (SLOT + SLOT_GAP)))
end

--- Hide everything a line style may have shown, before drawing another.
local function ClearExtras(row)
    for _, slot in ipairs(row.slots) do slot:Hide() end
    for _, mini in ipairs(row.minis) do mini:Hide() end
    row.sub:Hide()
    row.below:Hide()
    row.medal:Hide()
    row.rank:Hide()
    row.live:Hide()
    row.edge:Hide()
end

--- A quality-coloured item's colour as four numbers, text colour if none.
local function ItemColor(name)
    local r, g, b, a = HexColor(ns.Tracker:LookOf(name).color)
    if r then return r, g, b, a end
    return Theme.Unpack("text")
end

function TrackerUI:DrawLine(row, line)
    ClearExtras(row)
    row.line = line

    local band = BAND[line.style]

    if band then
        row.band:SetColorTexture(Theme.Unpack(band.key, band.alpha))
        row.band:Show()
    else
        row.band:Hide()
    end

    if line.style == "icons" then
        return self:DrawIcons(row, line)
    end

    -- Items get an icon and their quality colour; everything else is text.
    local indent = PADDING

    row.icon:ClearAllPoints()
    row.icon:SetPoint("LEFT", PADDING + 6, 0)
    row.icon:SetSize(ICON, ICON)

    if line.style == "item" then
        local look = ns.Tracker:LookOf(line.item)
        row.icon:SetTexture(look.icon or FALLBACK_ICON)
        row.icon:Show()
        indent = PADDING + 6 + ICON + 4
        row.left:SetTextColor(ItemColor(line.item))
    elseif line.style == "loot" then
        indent = self:DrawLootParts(row, line)
    elseif line.style == "place" then
        row.icon:SetTexture(PLACE_ICON)
        row.icon:Show()
        indent = PADDING + 6 + ICON + 4
        row.left:SetTextColor(Theme.Unpack("muted"))
    else
        row.icon:Hide()

        if line.style == "note" or line.style == "value" or line.style == "progress" then
            indent = PADDING + 6
            row.left:SetTextColor(Theme.Unpack(line.leftColor or "muted"))
        elseif line.style == "link" then
            indent = PADDING + 6
            row.left:SetTextColor(Theme.Unpack("accent"))
        elseif line.style == "heading" then
            row.left:SetTextColor(Theme.Unpack("muted"))
        elseif line.live then
            row.left:SetTextColor(BRIGHT_GOLD[1], BRIGHT_GOLD[2], BRIGHT_GOLD[3], 1)
        else
            row.left:SetTextColor(Theme.Unpack("accent"))
        end
    end

    -- The card you are on glows: a gold wash across its band and a bright
    -- edge down its left (Trent, 2026-09-28: "i like that neon glow").
    if line.style == "mob" and line.live then
        row.live:SetColorTexture(1, 1, 1, 1)
        local r, g, b = Theme.Unpack("accent")
        local ok = type(CreateColor) == "function" and pcall(row.live.SetGradient, row.live, "HORIZONTAL",
            CreateColor(r, g, b, 0.34), CreateColor(r, g, b, 0.04))
        if not ok then row.live:SetColorTexture(r, g, b, 0.18) end
        row.live:Show()
        row.edge:SetColorTexture(BRIGHT_GOLD[1], BRIGHT_GOLD[2], BRIGHT_GOLD[3], 1)
        row.edge:SetWidth(3)
        row.edge:Show()
    end

    -- The text runs to the value column, or all the way across when a line
    -- has no value. That second case is what cut "Nothing killed yet this
    -- session." short: it stopped where a value would have started.
    --
    -- The value and badge columns are as wide as their text needs, at least
    -- their usual width, so neither is cut short either.
    local rightWidth = math.max(RIGHT_WIDTH, Theme.TextWidth("small", Util.StripColor(line.right)) + 2)
    local badgeWidth = math.max(BADGE_WIDTH, Theme.TextWidth("tiny", line.badge) + 2)
    if line.style == "loot" then
        rightWidth = math.max(rightWidth, Theme.TextWidth("tiny", Util.StripColor(line.below)) + 2)
    end
    row.right:SetWidth(rightWidth)
    row.badge:SetWidth(badgeWidth)

    local stop = PADDING
    if line.right ~= "" then stop = stop + rightWidth + 4 end
    if line.badge then stop = stop + badgeWidth + 2 end

    -- A folded card's small icons sit just before its count.
    local minisWidth = 0
    if line.minis and #line.minis > 0 then
        minisWidth = self:DrawMinis(row, line.minis, stop)
        stop = stop + minisWidth
    end

    row.left:ClearAllPoints()
    if line.style == "loot" then
        row.left:SetPoint("TOPLEFT", indent, -3)
        row.left:SetPoint("TOPRIGHT", -stop, -3)
        row.sub:ClearAllPoints()
        row.sub:SetPoint("BOTTOMLEFT", indent, 4)
        row.sub:SetPoint("BOTTOMRIGHT", -stop, 4)
        -- Where it came from, shortened to the first source when the panel
        -- is too narrow for two: it never widens the panel on its own.
        local room = (tonumber(self.frame and self.frame:GetWidth()) or self:Width()) - 2 - indent - stop
        local sub = line.sub or ""
        if line.subShort and Theme.TextWidth("tiny", sub) > room then sub = line.subShort end
        row.sub:SetText(sub)
        row.sub:Show()
    else
        row.left:SetPoint("LEFT", indent, 0)
        row.left:SetPoint("RIGHT", -stop, 0)
    end
    row.leftStop = stop
    row.leftIndent = indent

    -- How wide the panel must be for this line to show in full.
    row.needs = indent + Theme.TextWidth("small", line.left) + stop + 4
    if line.style == "loot" then
        row.needs = math.max(row.needs, indent + Theme.TextWidth("tiny", line.subShort or line.sub) + stop + 4)
    end
    row.left:SetText(line.left or "")
    row.left:Show()

    -- The progress bar runs from the indent to just short of its count.
    local bar = row.progress
    if line.style == "progress" then
        row.barLeft = indent
        row.barRight = stop
        row.needs = indent + MIN_PROGRESS + stop + 4

        bar.track:ClearAllPoints()
        bar.track:SetPoint("LEFT", indent, 0)
        bar.track:SetPoint("RIGHT", -stop, 0)
        for _, part in ipairs(bar.parts) do part:Show() end
        -- Drawn at its real width once the panel's width is settled.
        self:SetProgress(row, line.progress, line.final)
    else
        for _, part in ipairs(bar.parts) do part:Hide() end
    end

    row.right:ClearAllPoints()
    if line.style == "loot" then
        row.right:SetPoint("TOPRIGHT", -PADDING, -3)
        row.below:ClearAllPoints()
        row.below:SetPoint("BOTTOMRIGHT", -PADDING, 4)
        row.below:SetWidth(rightWidth)
        row.below:SetText(line.below or "")
        row.below:SetTextColor(Theme.Unpack(line.belowColor or "good"))
        row.below:Show()
    else
        row.right:SetPoint("RIGHT", -PADDING, 0)
    end
    row.right:SetText(line.right)
    row.right:SetTextColor(Theme.Unpack(line.rightColor
        or ((line.style == "mob" or line.style == "loot") and "text" or "muted")))
    if line.live then row.right:SetTextColor(1, 1, 1, 1) end
    row.right:Show()

    if line.badge then
        row.badge:SetText(line.badge)
        row.badge:Show()
    else
        row.badge:SetText("")
        row.badge:Hide()
    end

    if line.bar then
        row.track:Show()
        row.fill:SetWidth(math.max(1, BAR * math.min(1, line.bar)))
        row.fill:SetColorTexture(Theme.Unpack(line.barColor or "accent"))
        row.fill:Show()
    else
        row.track:Hide()
        row.fill:Hide()
    end

    -- Only rows that open or fold something take the mouse, so the rest of
    -- the panel still drags from anywhere.
    row.hover:Hide()
    row:EnableMouse(line.mob ~= nil or line.openKey ~= nil)

    row:Show()
end

--- A Loot tab row's rank and medal, icon and quality wash. Returns where
--- its name starts.
function TrackerUI:DrawLootParts(row, line)
    local medal = MEDALS[line.rank]
    row.medal:ClearAllPoints()
    row.medal:SetPoint("LEFT", PADDING - 2, 0)
    row.rank:ClearAllPoints()
    row.rank:SetPoint("CENTER", row.medal, "CENTER", 0, 0)
    row.rank:SetText(tostring(line.rank or ""))
    row.rank:Show()

    if medal then
        row.medal:SetColorTexture(medal[1], medal[2], medal[3], 0.95)
        row.medal:Show()
        row.rank:SetTextColor(0.1, 0.08, 0.03, 1)
    else
        row.rank:SetTextColor(Theme.Unpack("muted"))
    end

    local look = ns.Tracker:LookOf(line.item)
    row.icon:ClearAllPoints()
    row.icon:SetPoint("LEFT", PADDING - 2 + MEDAL + 5, 0)
    row.icon:SetSize(LOOT_ICON, LOOT_ICON)
    row.icon:SetTexture(look.icon or FALLBACK_ICON)
    row.icon:Show()

    row.left:SetTextColor(ItemColor(line.item))

    -- Green and better glow in their own colour.
    local quality = ns.TrackerFX and ns.TrackerFX.QualityOf(line.item) or nil
    if quality and quality >= 2 then
        local r, g, b = ItemColor(line.item)
        row.live:SetColorTexture(1, 1, 1, 1)
        local ok = type(CreateColor) == "function" and pcall(row.live.SetGradient, row.live, "HORIZONTAL",
            CreateColor(r, g, b, 0.26), CreateColor(r, g, b, 0.02))
        if not ok then row.live:SetColorTexture(r, g, b, 0.14) end
        row.live:Show()
        row.edge:SetColorTexture(r, g, b, 1)
        row.edge:SetWidth(2)
        row.edge:Show()
    end

    row.band:SetColorTexture(Theme.Unpack(line.rank % 2 == 0 and "rowAlt" or "row", 0.55))
    row.band:Show()

    return PADDING - 2 + MEDAL + 5 + LOOT_ICON + 6
end

--- A folded card's loot as small icons, right to left from `stop`.
--- Returns the width they take.
function TrackerUI:DrawMinis(row, names, stop)
    for index, name in ipairs(names) do
        local mini = row.minis[index]
        if not mini then
            mini = row:CreateTexture(nil, "ARTWORK")
            mini:SetSize(MINI, MINI)
            mini:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            row.minis[index] = mini
        end

        mini:ClearAllPoints()
        mini:SetPoint("RIGHT", row, "RIGHT", -(stop + 2 + (#names - index) * (MINI + 2)), 0)
        mini:SetTexture(ns.Tracker:LookOf(name).icon or FALLBACK_ICON)
        mini:Show()
    end

    return #names * (MINI + 2) + 4
end

--- An open card's loot as bag slots, wrapping to the panel's width.
function TrackerUI:DrawIcons(row, line)
    row.icon:Hide()
    row.left:SetText("")
    row.left:Hide()
    row.right:SetText("")
    row.right:Hide()
    row.badge:Hide()
    row.track:Hide()
    row.fill:Hide()
    for _, part in ipairs(row.progress.parts) do part:Hide() end

    row.needs = PADDING * 2 + SLOT + 8
    row.hover:Hide()
    row:EnableMouse(false)

    for index, icon in ipairs(line.icons) do
        local slot = self:Slot(row, index)
        slot.line = icon
        slot.icon:SetTexture(ns.Tracker:LookOf(icon.item).icon or FALLBACK_ICON)

        local r, g, b = ItemColor(icon.item)
        local quality = ns.TrackerFX and ns.TrackerFX.QualityOf(icon.item) or nil
        for _, edge in ipairs(slot.borderTextures or {}) do
            if quality and quality >= 1 then
                edge:SetColorTexture(r, g, b, quality >= 2 and 1 or 0.55)
            else
                edge:SetColorTexture(Theme.Unpack("borderLit"))
            end
        end

        -- Green and better keep a soft glow in their colour.
        if quality and quality >= 2 then
            slot.glow:SetColorTexture(r, g, b, 1)
            slot.glow:SetAlpha(quality >= 3 and 0.35 or 0.2)
        else
            slot.glow:SetAlpha(0)
        end
        slot.rest = slot.glow:GetAlpha()

        slot.count:SetText(icon.text or "")
        slot.count:SetTextColor(Theme.Unpack(icon.textColor or "text"))
        if icon.textColor == "good" then slot.count:SetTextColor(0.62, 0.96, 0.75, 1) end
        slot:Show()
    end

    for index = #line.icons + 1, #row.slots do row.slots[index]:Hide() end

    row:Show()
end

--- Put an icons row's slots where they go for `width`.
function TrackerUI:PlaceSlots(row, line, width)
    local perRow = self:SlotsPerRow(width)
    for index = 1, #line.icons do
        local slot = row.slots[index]
        local column = (index - 1) % perRow
        local down = math.floor((index - 1) / perRow)
        slot:ClearAllPoints()
        slot:SetPoint("TOPLEFT", row, "TOPLEFT", PADDING + 5 + column * (SLOT + SLOT_GAP),
            -(5 + down * (SLOT + SLOT_GAP)))
    end
end

--- How long a row's progress bar is: the panel's width, less the indent
--- and the count.
function TrackerUI:ProgressWidth(row)
    local width = tonumber(self.frame and self.frame:GetWidth()) or self:Width()
    return math.max(20, width - 2 - (row.barLeft or PADDING) - (row.barRight or PADDING))
end

--- A row's progress bar filled to `fraction`, green in the last stretch, as
--- a goal's is (GoalsUI:SetBar).
function TrackerUI:SetProgress(row, fraction, green)
    local bar = row.progress
    local width = self:ProgressWidth(row)
    fraction = math.max(0, math.min(1, tonumber(fraction) or 0))

    bar.fill:SetColorTexture(Theme.Unpack(green and "good" or "accent"))
    bar.fill:SetWidth(math.max(1, width * fraction))
    bar.fill:SetShown(fraction > 0)

    local tip = green and GREEN_TIP or BRIGHT_GOLD
    bar.tip:SetColorTexture(tip[1], tip[2], tip[3], 0.9)
    bar.tip:SetShown(fraction > 0.02 and fraction < 1)

    for index, at in ipairs(MARKS) do
        local mark = bar.marks[index]
        mark:ClearAllPoints()
        mark:SetPoint("TOPLEFT", bar.track, "TOPLEFT", math.floor(width * at), 0)
    end
end

--------------------------------------------------------------------------------
-- Cards
--
-- An open card sits on a panel of its own with an edge round it: gold with
-- a soft outer glow for the one you are on, plain for the rest.
--------------------------------------------------------------------------------

function TrackerUI:Card(index)
    local card = self.cards[index]
    if card then return card end

    card = CreateFrame("Frame", nil, self.frame)
    card:SetFrameLevel(self.frame:GetFrameLevel() + 1)
    card.fill = Theme.Fill(card, "rowAlt", 0.55)

    card.edges, card.halo = {}, {}
    for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
        local edge = card:CreateTexture(nil, "BORDER")
        local halo = card:CreateTexture(nil, "BACKGROUND", nil, -1)
        pcall(halo.SetBlendMode, halo, "ADD")

        if side == "TOP" or side == "BOTTOM" then
            edge:SetPoint(side .. "LEFT")
            edge:SetPoint(side .. "RIGHT")
            edge:SetHeight(1)
            local out = side == "TOP" and 1 or -1
            halo:SetPoint(side .. "LEFT", -3, out * 3)
            halo:SetPoint(side .. "RIGHT", 3, out * 3)
            halo:SetHeight(4)
        else
            edge:SetPoint("TOP" .. side)
            edge:SetPoint("BOTTOM" .. side)
            edge:SetWidth(1)
            local out = side == "LEFT" and -1 or 1
            halo:SetPoint("TOP" .. side, out * 3, 0)
            halo:SetPoint("BOTTOM" .. side, out * 3, 0)
            halo:SetWidth(4)
        end

        card.edges[#card.edges + 1] = edge
        card.halo[#card.halo + 1] = halo
    end

    self.cards[index] = card
    return card
end

--- Draw a card behind rows `first` to `last` of the ones showing.
function TrackerUI:DrawCard(index, first, last, live)
    local card = self:Card(index)
    card:ClearAllPoints()
    card:SetPoint("TOPLEFT", first, "TOPLEFT", PADDING - 5, 1)
    card:SetPoint("BOTTOMRIGHT", last, "BOTTOMRIGHT", -(PADDING - 5), -1)

    for _, edge in ipairs(card.edges) do
        if live then
            edge:SetColorTexture(Theme.Unpack("accent", 0.95))
        else
            edge:SetColorTexture(Theme.Unpack("border"))
        end
    end
    for _, halo in ipairs(card.halo) do
        halo:SetColorTexture(Theme.Unpack("accent", live and 0.22 or 0))
        halo:SetShown(live == true)
    end

    card:Show()
end

--------------------------------------------------------------------------------
-- Scrolling
--------------------------------------------------------------------------------

function TrackerUI:ScrollBy(lines)
    local was = self.scroll or 0
    self.scroll = math.max(0, math.min(self.maxScroll or 0, was + (tonumber(lines) or 0)))
    if self.scroll ~= was then self:Render() end
end

--------------------------------------------------------------------------------
-- Render
--------------------------------------------------------------------------------

--- How many there are on each tab, for the numbers beside their names.
function TrackerUI:TabCounts()
    local mobs = 0
    for _ in pairs(ns.Tracker.session or {}) do mobs = mobs + 1 end
    if ns.Fishing then for _ in pairs(ns.Fishing.session or {}) do mobs = mobs + 1 end end
    if ns.Gathering then for _ in pairs(ns.Gathering.session or {}) do mobs = mobs + 1 end end

    local items, looted = {}, 0
    local function Take(counts)
        for name, count in pairs(counts or {}) do
            items[name] = true
            looted = looted + count
        end
    end
    Take(ns.Tracker.sessionLoot)
    if ns.Fishing then Take(ns.Fishing.sessionCatch) end
    if ns.Gathering then Take(ns.Gathering.sessionItems) end

    local distinct = 0
    for _ in pairs(items) do distinct = distinct + 1 end

    return { farm = mobs, loot = distinct }, looted, ns.Tracker:SessionKills()
end

--- A green dot on the tab not showing when something new lands there.
function TrackerUI:NoteDots(looted, kills)
    self.dots = self.dots or {}
    local tab = self:Tab()

    if self.seenLooted and looted > self.seenLooted and tab ~= "loot" then self.dots.loot = true end
    if self.seenKills and kills > self.seenKills and tab ~= "farm" then self.dots.farm = true end

    self.seenLooted, self.seenKills = looted, kills
    self.dots[tab] = nil
end

function TrackerUI:Render()
    self:Build()

    local counts, looted, kills = self:TabCounts()
    self:NoteDots(looted, kills)

    local all = self:Lines()

    -- The gathered value goes in the title bar. The effects see it as the
    -- first line, ahead of the column's.
    local titleLine = self:TitleTotal()
    self.titleLine = titleLine
    local titleNeeds = self:DrawTitle(titleLine)
    local toolbarNeeds = self:DrawToolbar()

    -- While the grip is held, the panel is whatever size the drag says;
    -- otherwise it is the saved size. The column scrolls within it.
    local limit = self.sizing and self.frame:GetHeight() or self:MaxHeight()
    local room = math.max(LINE * 2, limit - TOP - PADDING * 2)

    -- The width first: every line drawn once to see what it needs.
    local width = tonumber(self.frame:GetWidth()) or self:Width()
    if not self.sizing then
        local needs = math.max(titleNeeds, toolbarNeeds)
        for _, line in ipairs(all) do
            if line.style ~= "icons" then
                needs = math.max(needs, self:Needs(line))
            end
        end
        -- As wide as the wider tab has needed, so switching tabs never
        -- makes the panel jump.
        self.tabNeeds = self.tabNeeds or {}
        self.tabNeeds[self:Tab()] = needs
        for _, other in pairs(self.tabNeeds) do needs = math.max(needs, other) end
        width = self:FitWidth(needs)
        self.frame:SetWidth(width)
    end

    local heights, total = {}, 0
    for index, line in ipairs(all) do
        heights[index] = self:LineHeight(line, width)
        total = total + heights[index]
    end

    -- Scrolled no further than it takes to bring the last line to the
    -- bottom edge.
    local maxScroll, tail = 0, 0
    for index = #all, 1, -1 do
        tail = tail + heights[index]
        if tail > room then
            maxScroll = index
            break
        end
    end
    self.maxScroll = maxScroll
    self.scroll = math.max(0, math.min(self.scroll or 0, maxScroll))

    local shown, used = {}, 0
    for index = self.scroll + 1, #all do
        if used + heights[index] > room and #shown > 0 then break end
        shown[#shown + 1] = all[index]
        used = used + heights[index]
    end
    local first = self.scroll + 1
    local below = #all - (self.scroll + #shown)

    self.shown = shown

    local fxAll = { }
    for _, line in ipairs(all) do fxAll[#fxAll + 1] = line end
    local fxShown = shown
    if titleLine then
        table.insert(fxAll, 1, titleLine)
        fxShown = { titleLine }
        for _, line in ipairs(shown) do fxShown[#fxShown + 1] = line end
    end

    local function RowFor(index)
        if titleLine then
            if index == 1 then return self.titleRow end
            index = index - 1
        end
        return self.lines[index]
    end

    -- What went up since the last redraw, worked out before drawing so the
    -- value line can carry its "+38s". Never allowed to stop the panel.
    local FX = ns.TrackerFX
    local plan
    if FX then
        local ok, result = pcall(FX.Prepare, FX, fxAll, fxShown)
        plan = ok and result or nil
        if not ok then ns.Debug("panel effects:", tostring(result)) end

        -- Prepare is what gives the gathered value its "+38s": draw the
        -- title again so the badge is there to show.
        if titleLine and titleLine.badge then self:DrawTitle(titleLine) end
    end

    -- Drawn top down, each row under the last.
    local y = TOP + PADDING
    for index = 1, math.max(#shown, #self.lines) do
        local line = shown[index]

        if line then
            local row = self:Line(index)
            local height = heights[first + index - 1]
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 1, -y)
            row:SetPoint("TOPRIGHT", self.frame, "TOPRIGHT", -1, -y)
            row:SetHeight(height)
            self:DrawLine(row, line)
            if line.style == "icons" then self:PlaceSlots(row, line, width) end
            y = y + height
        elseif self.lines[index] then
            self.lines[index]:Hide()
        end
    end

    self:DrawCards(shown)
    self:DrawTabs(counts)

    if below > 0 then
        self.moreLabel:SetText(("%d more below, scroll"):format(below))
        self.moreLabel:Show()
    else
        self.moreLabel:Hide()
    end
    if self.fadeTop then
        self.fadeTop:SetShown(self.scroll > 0)
        self.fadeBottom:SetShown(below > 0)
    end

    if not self.sizing then
        self.frame:SetHeight(TOP + PADDING * 2 + used + (below > 0 and 10 or 0))
    end

    self:FitTitleBadge()

    -- The progress bars again, now that the panel has its width.
    for index, line in ipairs(shown) do
        if line.style == "progress" then
            self:SetProgress(self.lines[index], line.progress, line.final)
        end
    end

    if plan then
        local ok, err = pcall(FX.Play, FX, plan, RowFor)
        if not ok then ns.Debug("panel effects:", tostring(err)) end
    end

    self:NoteRanks(shown)
end

--- How wide the panel must be for `line` to show in full, measured on a
--- spare row that is never shown.
function TrackerUI:Needs(line)
    if not self.measure then
        self.measure = self:CreateLine(self.frame, 0)
    end
    local row = self.measure
    self:DrawLine(row, line)
    row:Hide()
    for _, slot in ipairs(row.slots) do slot:Hide() end
    return row.needs or 0
end

--- Whether the line at `index`, a note or value line at the top of the
--- column, belongs to a card scrolled half out of sight: the card's icons
--- or bar come after it before any band or heading does.
function TrackerUI:InCard(shown, index)
    for next = index + 1, #shown do
        local style = shown[next].style
        if style == "icons" or style == "progress" then return true end
        if style == "mob" or style == "heading" or style == "loot" then return false end
    end
    return false
end

--- The cards behind every open card showing: from its band to its icons.
function TrackerUI:DrawCards(shown)
    local used = 0
    local open

    local function Close(last)
        if not open then return end
        used = used + 1
        self:DrawCard(used, self.lines[open.first], self.lines[last], open.live)
        open = nil
    end

    for index, line in ipairs(shown) do
        if line.style == "mob" or line.style == "heading" or line.style == "loot" then
            Close(index - 1)
            if line.style == "mob" and not line.folded then
                open = { first = index, live = line.live == true }
            end
        elseif not open and (line.style == "place" or line.style == "progress"
            or line.style == "icons"
            or ((line.style == "note" or line.style == "value") and index == 1
                and self:InCard(shown, index))) then
            -- A card scrolled half out of sight: its rest still sits on one.
            open = { first = index, live = false }
        end
        if open and line.style == "icons" then Close(index) end
    end
    Close(#shown)

    for index = used + 1, #self.cards do self.cards[index]:Hide() end
end

--- On the Loot tab, an item that climbs past another floats where it got
--- to (Trent, 2026-09-28: dopamine hits wherever they fit).
function TrackerUI:NoteRanks(shown)
    if self:Tab() ~= "loot" or self:Sort("loot") ~= "value" then
        self.ranks = nil
        return
    end

    local ranks = {}
    for index, line in ipairs(shown) do
        if line.style == "loot" then
            ranks[line.item] = line.rank
            local was = self.ranks and self.ranks[line.item]
            local FX = ns.TrackerFX
            if was and line.rank < was and FX and FX.Level() == "full" and self.lines[index] then
                pcall(FX.FloatText, FX, Util.Colored("good", ("Up to #%d!"):format(line.rank)),
                    self.lines[index], 0.2, 14)
            end
        end
    end
    self.ranks = ranks
end

--- The gathered value on the title bar's second line; "0c" until something
--- gathered has a price. Returns how wide the panel must be for both title
--- lines to show in full.
function TrackerUI:DrawTitle(line)
    local row = self.titleRow
    -- False rather than nil, so an effect still running on it sees no line.
    row.line = line or false
    self.titleBadgeNeeds = nil

    -- Top line: the title, a gap, and the X with its margins.
    local top = PADDING + 4 + Theme.TextWidth("normal", self.title:GetText()) + 8 + 6 + 18 + 6

    local value = line and line.right or (ns.Value and ns.Value.Coins(0) or "0c")
    local valueWidth = Theme.TextWidth("normal", Util.StripColor(value)) + 2
    -- No fixed width: hung from its right edge, it sizes to its text, so
    -- the count-up passing through "99s 87c" on its way to "1g 2s" is
    -- never cut to "99s...".
    row.right:SetWidth(0)
    row.right:SetText(value)
    row.right:SetTextColor(Theme.Unpack(line and (line.rightColor or "good") or "muted"))

    -- Second line: the label, a gap, and the value.
    local labelEnd = 3 + PADDING + 1 + Theme.TextWidth("small", row.left:GetText())
    local second = labelEnd + 12 + valueWidth + PADDING

    local badge = line and line.badge
    local badgeWidth = badge and (Theme.TextWidth("tiny", badge) + 2) or 0
    row.badge:SetWidth(math.max(1, badgeWidth))
    row.badge:SetText(badge or "")
    if badge then self.titleBadgeNeeds = labelEnd + 8 + badgeWidth + 4 + valueWidth + PADDING end

    return math.max(top, second)
end

--- The "+38s" only lasts a few seconds, so the panel does not widen for it:
--- it shows when there is room between the label and the value.
function TrackerUI:FitTitleBadge()
    local row = self.titleRow
    local width = self.frame:GetWidth()
    local needs = self.titleBadgeNeeds

    if needs and type(width) == "number" and needs <= width then
        row.badge:Show()
    else
        row.badge:Hide()
    end
end

--------------------------------------------------------------------------------
-- On and off
--------------------------------------------------------------------------------

--- Redraw, and show or hide to match the saved setting.
function TrackerUI:Refresh()
    self:Build()

    -- An open loot table follows the same tally.
    if ns.LootTableUI then ns.LootTableUI:Refresh() end
    if ns.RankingsUI then ns.RankingsUI:Refresh() end

    self:NoteStart()

    if ns.db.trackerHidden then
        self.frame:Hide()
        -- Hidden, nothing plays but the rare-drop chime; shown again, the
        -- counts start from there.
        if ns.TrackerFX then
            ns.TrackerFX:Forget()
            pcall(ns.TrackerFX.HiddenLoot, ns.TrackerFX)
        end
        return
    end

    if ns.TrackerFX and ns.TrackerFX.Shown then ns.TrackerFX:Shown() end

    self:Render()
    self.frame:Show()

    -- The goals panel hangs under this one, as wide as it is: follow it
    -- when it comes back or changes width.
    local goals = ns.GoalsUI
    if goals and goals.frame and goals.frame:IsShown() and not ns.db.goalsX then
        if goals.lastBase ~= goals:Width() then pcall(goals.Render, goals) end
        pcall(goals.Place, goals)
    end
end

--- Forget what the panel remembered about the last session's lines: its
--- widest width on each tab, which cards you opened or folded, the
--- per-hour clock, the Loot tab's ranks and the scroll. For a reset.
function TrackerUI:ResetState()
    self.tabNeeds = nil
    self.open = nil
    self.startedAt = nil
    self.ranks = nil
    self.scroll = 0
    self.dots = nil
end

function TrackerUI:Hide()
    if self.frame then self.frame:Hide() end
    if ns.TrackerFX then ns.TrackerFX:Forget() end
end

function TrackerUI:OnEnable()
    self:Refresh()
    self:Place()

    local function Settle() TrackerUI:PlaceSoon() end
    ns.RegisterEvent(self, "GROUP_ROSTER_UPDATE", Settle)
    ns.RegisterEvent(self, "PLAYER_ENTERING_WORLD", Settle)
    -- The group frames moved in Edit Mode. Clients without it skip this.
    ns.RegisterEvent(self, "EDIT_MODE_LAYOUTS_UPDATED", Settle)
end

--------------------------------------------------------------------------------
-- Position
--------------------------------------------------------------------------------

-- After a drag the client re-anchors the panel to whichever corner or edge is
-- nearest, often the bottom or the centre. The panel's height then changes
-- to fit its contents, and a bottom or centre anchor would move its top.
-- Anchor it by its top-left corner instead, where it is now on screen.
-- UIParent's bottom-left is 0,0 in every scale, so the panel's own left and
-- top are the offsets.
function TrackerUI:AnchorTop()
    local frame = self.frame
    if not frame then return end

    local ok, left, top = pcall(function() return frame:GetLeft(), frame:GetTop() end)
    if not (ok and type(left) == "number" and type(top) == "number") then return end

    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
end

function TrackerUI:SavePosition()
    if not (ns.db and self.frame) then return end

    local point, _, relativePoint, x, y = self.frame:GetPoint()

    -- Moved while in a group: that is where it goes in a group from now on,
    -- and the spot it has when you play alone stays as it was.
    if self.grouped then
        ns.db.trackerGroupX = x
        ns.db.trackerGroupY = y
        return
    end

    ns.db.trackerPoint = point
    ns.db.trackerRelativePoint = relativePoint
    ns.db.trackerX = x
    ns.db.trackerY = y
end

function TrackerUI:RestorePosition()
    if not self.frame then return end

    local db = ns.db or {}

    -- The first version sat on the right; move a panel saved there once.
    if db.trackerLayout ~= LAYOUT then
        db.trackerPoint = "TOPLEFT"
        db.trackerRelativePoint = "TOPLEFT"
        db.trackerX = 8
        db.trackerY = -190
        db.trackerLayout = LAYOUT
    end

    local point = db.trackerPoint or "TOPLEFT"

    self.frame:ClearAllPoints()
    self.frame:SetPoint(point, UIParent, db.trackerRelativePoint or point,
        db.trackerX or 8, db.trackerY or -190)

    -- A panel saved by an earlier version may hang from its bottom or centre.
    if point ~= "TOPLEFT" then
        self:AnchorTop()
        self:SavePosition()
    end
end

--------------------------------------------------------------------------------
-- In a group
--------------------------------------------------------------------------------

-- The default spot is right where the party frames are. In a party or raid
-- the panel steps to the right of whichever group frames are showing, and
-- goes back when you are on your own again. Drag it while grouped and it
-- keeps that spot for groups instead (trackerGroupX/Y).
--
-- The panel is a plain frame anchored to UIParent, so moving it in combat is
-- allowed; the group frames are only read, never touched.

-- Blizzard's group frames, newest layout first. Whichever are showing count.
local GROUP_FRAMES = {
    "CompactRaidFrameContainer",
    "CompactPartyFrame",
    "PartyFrame",
    "PartyMemberFrame1", "PartyMemberFrame2", "PartyMemberFrame3", "PartyMemberFrame4",
}

-- Space left between the group frames and the panel.
local GROUP_GAP = 8

-- How long to let the group frames lay themselves out after a change.
local SETTLE = 0.5

function TrackerUI:InGroup()
    local ok, grouped = pcall(function()
        if IsInRaid and IsInRaid() then return true end
        if IsInGroup and IsInGroup() then return true end
        return (GetNumGroupMembers and GetNumGroupMembers() or 0) > 0
    end)
    return ok and grouped == true
end

function TrackerUI:DodgeGroupOn()
    return not (ns.db and ns.db.trackerDodgeGroup == false)
end

--- A frame's edges in the panel's own units, or nil if it is not on screen.
local function EdgesIn(frame, scale)
    local ok, left, right, top, bottom = pcall(function()
        if not (frame.IsVisible and frame:IsVisible()) then return end
        local own = frame:GetEffectiveScale() / scale
        local l, r, t, b = frame:GetLeft(), frame:GetRight(), frame:GetTop(), frame:GetBottom()
        -- Compared here, inside the pcall: a secret value raises on it.
        if not (type(l) == "number" and type(r) == "number" and r > l
            and type(t) == "number" and type(b) == "number" and t > b) then
            return
        end
        return l * own, r * own, t * own, b * own
    end)
    if ok and left then return left, right, top, bottom end
end

--- Where the showing group frames are, as one box in the panel's units.
function TrackerUI:GroupFrameBox()
    local ok, scale = pcall(self.frame.GetEffectiveScale, self.frame)
    if not (ok and type(scale) == "number" and scale > 0) then return end

    local box
    for _, name in ipairs(GROUP_FRAMES) do
        local frame = _G[name]
        if frame then
            local left, right, top, bottom = EdgesIn(frame, scale)
            if left then
                if box then
                    box.left = math.min(box.left, left)
                    box.right = math.max(box.right, right)
                    box.top = math.max(box.top, top)
                    box.bottom = math.min(box.bottom, bottom)
                else
                    box = { left = left, right = right, top = top, bottom = bottom }
                end
            end
        end
    end
    return box
end

--- Put the panel where it belongs for being solo or grouped.
function TrackerUI:Place()
    if not self.frame then return end
    -- Never pull it out from under a drag.
    if self.sizing or self.dragging then return end

    self:RestorePosition()

    local db = ns.db or {}
    self.grouped = self:DodgeGroupOn() and self:InGroup()
    if not self.grouped then return end

    if type(db.trackerGroupX) == "number" and type(db.trackerGroupY) == "number" then
        self.frame:ClearAllPoints()
        self.frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", db.trackerGroupX, db.trackerGroupY)
        return
    end

    local box = self:GroupFrameBox()
    if not box then return end

    local ok, left, top = pcall(function() return self.frame:GetLeft(), self.frame:GetTop() end)
    if not (ok and type(left) == "number" and type(top) == "number") then return end

    -- The panel grows downward as it fills, so check the whole height it may
    -- take, not just what it has now.
    local okWidth, width = pcall(self.frame.GetWidth, self.frame)
    if not (okWidth and type(width) == "number") then width = self:Width() end
    local right = left + width
    local bottom = top - self:MaxHeight()
    local overlaps = left < box.right and right > box.left
        and top > box.bottom and bottom < box.top
    if not overlaps then return end

    self.frame:ClearAllPoints()
    self.frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", box.right + GROUP_GAP, top)
end

--- Place it again once the group frames have settled.
function TrackerUI:PlaceSoon()
    if C_Timer and type(C_Timer.After) == "function" then
        pcall(C_Timer.After, SETTLE, function() TrackerUI:Place() end)
    else
        self:Place()
    end
end

function TrackerUI:SetDodgeGroup(on)
    ns.db.trackerDodgeGroup = on and true or false
    self:Place()
end

--- Forget the spot picked for groups; it goes back beside the group frames.
function TrackerUI:ResetGroupSpot()
    if not ns.db then return end
    ns.db.trackerGroupX = nil
    ns.db.trackerGroupY = nil
end
