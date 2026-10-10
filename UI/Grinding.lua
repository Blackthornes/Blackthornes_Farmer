-- Blackthornes Farmer -- UI/Grinding.lua
-- The Grind tab of the main window: where mobs of a level band and a kind
-- gather (Logic/Grinding.lua).
--
-- Across the top: the level band on two steppers, with My level to follow
-- yours. Under it: the creature type (Any, Humanoid, Beast, ...), what they
-- give (Cloth, Skinning), and the Sort menu (Busiest, Nearest, Level, Level
-- then nearest). The list is one band per camp with its mobs under it:
-- type, level, what they give and what a kill is worth; the column
-- headings sort the mobs within each camp. A click on a camp points the
-- arrow there; the camps listed also show on the world map
-- (UI/GrindPins.lua).

local _, ns = ...

local GrindingUI = ns.NewModule("GrindingUI")

local Theme = ns.Theme
local Widgets = ns.Widgets
local Util = ns.Util

local PADDING = 14
local ROW_HEIGHT = 20
local COLUMN_GAP = 6

-- What the window adds around the columns, as the Rankings tab counts it.
local CHROME = 74

local COLUMN_ORDER = { "type", "mob", "level", "gives", "worth", "badge" }
local BASE_WIDTH = { type = 74, mob = 190, level = 46, gives = 110, worth = 90, badge = 50 }
local MAX_WIDTH = { type = 110, mob = 320, gives = 160, worth = 160 }

local BADGE_TEXT = "Forever"
local INDENT = "     "

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

local function Tip(owner, title, text)
    if not GameTooltip then return end
    GameTooltip:SetOwner(owner, "ANCHOR_TOP")
    GameTooltip:AddLine(title, 1, 1, 1)
    if text then GameTooltip:AddLine(text, Theme.Unpack("muted")) end
    GameTooltip:Show()
end

local function HideTip()
    if GameTooltip then GameTooltip:Hide() end
end

--- A chip with a tooltip, sized to its words.
local function Chip(parent, label, onClick, tip)
    local chip = Widgets.CreateChip(parent, label, onClick)
    if tip then
        chip:HookScript("OnEnter", function(self) Tip(self, tip[1], tip[2]) end)
        chip:HookScript("OnLeave", HideTip)
    end
    return chip
end

--- Build the tab's contents into `frame`, the main window. Hidden until the
--- tab is chosen.
function GrindingUI:Build(frame)
    if self.view then return self.view end

    local Grinding = ns.Grinding

    local view = CreateFrame("Frame", nil, frame)
    view:SetAllPoints(frame)
    self.view = view

    local left, top = ns.UI.HEAD_LEFT or PADDING, ns.UI.HEAD_TOP or 26

    -- The top row, beside the portrait: the level band.
    local band = CreateFrame("Frame", nil, view)
    band:SetPoint("TOPLEFT", left, -top)
    band:SetHeight(24)
    band:SetWidth(420)
    self.band = band

    local levelLabel = Theme.CreateLabel(band, "small", "muted")
    levelLabel:SetPoint("LEFT", 0, 0)
    levelLabel:SetText("Levels")
    self.levelLabel = levelLabel

    local function Changed()
        local low, high = self.low:GetValue(), self.high:GetValue()
        Grinding:SetRange(low, high)
        GrindingUI:Render(true)
    end

    self.low = Widgets.CreateStepper(band, {
        min = Grinding.MIN_LEVEL, max = Grinding.MAX_LEVEL, step = 1, value = 1,
        onChange = function(value)
            -- The low end pushes the high one up rather than passing it.
            if value > (self.high:GetValue() or value) then self.high:SetValue(value, true) end
            Changed()
        end,
    })
    self.low:SetWidth(96)
    self.low:SetPoint("LEFT", levelLabel, "RIGHT", 8, 0)

    local to = Theme.CreateLabel(band, "small", "muted")
    to:SetPoint("LEFT", self.low, "RIGHT", 6, 0)
    to:SetText("to")
    self.toLabel = to

    self.high = Widgets.CreateStepper(band, {
        min = Grinding.MIN_LEVEL, max = Grinding.MAX_LEVEL, step = 1, value = Grinding.MAX_LEVEL,
        onChange = function(value)
            if value < (self.low:GetValue() or value) then self.low:SetValue(value, true) end
            Changed()
        end,
    })
    self.high:SetWidth(96)
    self.high:SetPoint("LEFT", to, "RIGHT", 6, 0)

    local mine = Widgets.CreateButton(band, "My level", function()
        Grinding:FollowLevel()
        GrindingUI:Render(true)
    end, { width = 70, height = 20 })
    mine:SetPoint("LEFT", self.high, "RIGHT", 10, 0)
    mine:HookScript("OnEnter", function(self)
        Tip(self, "Follow your level", ("From %d below your level to %d above, moving as you level.")
            :format(Grinding.BELOW, Grinding.ABOVE))
    end)
    mine:HookScript("OnLeave", HideTip)
    self.mineButton = mine

    -- The row under it, across the window: type, what they give, the order.
    local filters = CreateFrame("Frame", nil, view)
    filters:SetPoint("TOPLEFT", PADDING, -(top + 24 + 8))
    filters:SetPoint("TOPRIGHT", -PADDING, -(top + 24 + 8))
    filters:SetHeight(18)
    self.filters = filters

    -- Placed by LayoutChips, sized from their words as the game draws them.
    self.typeChips = {}

    local any = Chip(filters, "ANY TYPE", function()
        Grinding:SetType(nil)
        GrindingUI:Render(true)
    end)
    any.filterKind = false
    self.typeChips[1] = any

    local kinds = {}
    for _, kind in ipairs(Grinding.TYPES) do kinds[#kinds + 1] = kind end
    kinds[#kinds + 1] = Grinding.OTHER

    for _, kind in ipairs(kinds) do
        local chip = Chip(filters, kind:upper(), function()
            Grinding:SetType(kind)
            GrindingUI:Render(true)
        end, kind == Grinding.OTHER
            and { "Other types", "Giants, dragonkin, mechanical and the rest." } or nil)
        chip.filterKind = kind
        self.typeChips[#self.typeChips + 1] = chip
    end

    self.givesChips = {}
    for _, entry in ipairs(Grinding.GIVES) do
        local chip = Chip(filters, entry.label:upper(), function()
            -- A second click lets it go.
            Grinding:SetGives(Grinding:Gives() ~= entry.key and entry.key or nil)
            GrindingUI:Render(true)
        end, entry.key == "cloth"
            and { "Drops cloth", "Mobs the data has dropping cloth. Click again for any." }
            or { "Skinning", "Mobs the data lists for skinning. Click again for any." })
        chip.givesKey = entry.key
        self.givesChips[#self.givesChips + 1] = chip
    end

    -- The order of the camps. Up in the top row beside My level, where
    -- there is room: on the chip row it ran into Skinning (2026-10-10).
    local sort = Chip(band, GrindingUI.SortText(), function()
        GrindingUI:ToggleSortMenu()
    end, { "Sort the camps", "Busiest, nearest, by level, or by level and then the nearest." })
    self.sortChip = sort
    self:BuildSortMenu(view)

    self:LayoutChips()

    local panel = Theme.CreatePanel(view, "panel", "border")
    panel:SetPoint("TOPLEFT", filters, "BOTTOMLEFT", 0, -8)
    panel:SetPoint("BOTTOMRIGHT", view, "BOTTOMRIGHT", -PADDING, 36)
    if Theme.Recess then Theme.Recess(panel) end
    self.panel = panel

    self.headings = {}
    for key, text in pairs({ type = "TYPE", mob = "MOB", level = "LEVEL", gives = "GIVES",
        worth = "PER KILL" }) do
        local label = Theme.CreateLabel(panel, "tiny", "dim")
        label:SetText(text)
        self.headings[key] = label
    end

    self.columns = Columns()
    self:PlaceHeadings()

    -- The headings sort the mobs within each camp; the Sort menu orders the
    -- camps. Saved as grindColumns.
    local saved = type(ns.db.grindColumns) == "table" and ns.db.grindColumns or {}
    self.sorter = Widgets.SortableHeadings(self.headings, {
        type = "Sort each camp's mobs by type.",
        mob = "Sort each camp's mobs by name.",
        level = "Sort each camp's mobs by level.",
        gives = "Sort each camp's mobs by what they give.",
        worth = "Sort each camp's mobs by what a kill is worth.",
    }, function(key, ascending)
        ns.db.grindColumns = key and { key = key, ascending = ascending } or nil
        GrindingUI:Render()
    end, {
        startsLow = { type = true, mob = true, level = true, gives = true },
        key = GrindingUI.MOB_KEYS[saved.key] and saved.key or nil,
        ascending = saved.ascending,
    })

    local rule = Theme.CreateDivider(panel, "border")
    rule:SetPoint("TOPLEFT", 8, -20)
    rule:SetPoint("TOPRIGHT", -8, -20)

    local list = Widgets.CreateRowList(panel, {
        rowHeight = ROW_HEIGHT,
        createRow = function(row) GrindingUI:CreateRow(row) end,
        updateRow = function(row, data) GrindingUI:UpdateRow(row, data) end,
        onClick = function(data) GrindingUI:OnRowClick(data) end,
        onEnter = function(row, data) GrindingUI:ShowRowTooltip(row, data) end,
        onLeave = HideTip,
        fadeKey = "well",
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
    footer:SetText("Click a camp to point the arrow there; the camps also show on your world map. "
        .. "A mob's type is learned when you target or hover one.")
    self.footer = footer

    view:Hide()
    return view
end

--------------------------------------------------------------------------------
-- The Sort menu
--------------------------------------------------------------------------------

local MENU_ROW = 20

--- The sort chip's words: "SORT: NEAREST".
function GrindingUI.SortText()
    return ("SORT: %s"):format(ns.Grinding.SortLabel():upper())
end

--- A small list under the sort chip, one line per order, the one in use lit.
function GrindingUI:BuildSortMenu(view)
    local menu = Theme.CreatePanel(view, "panel", "metal")
    pcall(menu.SetFrameStrata, menu, "DIALOG")
    pcall(menu.SetClampedToScreen, menu, true)
    menu:EnableMouse(true)
    menu:Hide()
    self.sortMenu = menu

    menu.items = {}
    for index, entry in ipairs(ns.Grinding.SORTS) do
        local item = Widgets.CreateChip(menu, entry.label, function()
            ns.Grinding:SetSort(entry.key)
            menu:Hide()
            GrindingUI:Render(true)
        end, { noUnderline = true })
        item.sortKey = entry.key
        item:SetPoint("TOPLEFT", 4, -4 - (index - 1) * MENU_ROW)
        item:SetPoint("TOPRIGHT", -4, -4 - (index - 1) * MENU_ROW)
        item:HookScript("OnEnter", function(self) Tip(self, entry.label, entry.tip) end)
        item:HookScript("OnLeave", HideTip)
        menu.items[index] = item
    end
    menu:SetHeight(8 + #menu.items * MENU_ROW - 2)

    -- Gone with the tab, so it never waits over another one.
    view:HookScript("OnHide", function() menu:Hide() end)
end

function GrindingUI:ToggleSortMenu()
    local menu = self.sortMenu
    if menu:IsShown() then
        menu:Hide()
        return
    end

    local width = 0
    for _, item in ipairs(menu.items) do
        local text = item.label:GetText() or ""
        local w = Theme.TextWidth("tiny", text)
        local ok, drawn = pcall(item.label.GetStringWidth, item.label)
        if ok and type(drawn) == "number" and drawn > w then w = drawn end
        width = math.max(width, math.ceil(w) + 24)
        item:SetSelected(item.sortKey == ns.Grinding.Sort())
    end
    menu:SetWidth(math.max(width, self.sortChip:GetWidth()))
    menu:ClearAllPoints()
    menu:SetPoint("TOPLEFT", self.sortChip, "BOTTOMLEFT", 0, -2)
    menu:Show()
end

-- Gaps between chips, and the wider one before what the mobs give.
local CHIP_GAP = 4
local GROUP_GAP = 12
local CHIP_LINE = 22

--- A chip's width from its words as the game draws them: the font runs
--- wider than Theme.TextWidth's guess, which let chips overlap.
local function ChipWidth(chip)
    local text = chip.label:GetText() or ""
    local width = Theme.TextWidth("tiny", text)
    local ok, drawn = pcall(chip.label.GetStringWidth, chip.label)
    if ok and type(drawn) == "number" and drawn > width then width = drawn end
    return math.max(34, math.ceil(width) + 16)
end

--- Size the chips to their words and lay them along the row, wrapping onto
--- another line rather than overlapping when the row is too narrow. The
--- list's panel hangs below the row, so it moves down with it. Only on a
--- build or a redraw, never on a timer.
function GrindingUI:LayoutChips()
    local filters = self.filters
    local room = filters:GetWidth()
    if type(room) ~= "number" or room <= 0 then
        room = (ns.UI.BASE_WIDTH or 724) - 2 * PADDING
    end

    local chips = {}
    for _, chip in ipairs(self.typeChips) do chips[#chips + 1] = { chip, 0 } end
    for index, chip in ipairs(self.givesChips) do
        chips[#chips + 1] = { chip, index == 1 and GROUP_GAP or 0 }
    end

    -- Sort sits in the top row beside My level while it clears the Settings
    -- button there (larger text or a longer order can push it); otherwise it
    -- joins the end of the chip row.
    local sort = self.sortChip
    local sortWidth = ChipWidth(sort)
    sort:SetWidth(sortWidth)
    sort:ClearAllPoints()
    if self:TopRowRoom() >= sortWidth + 10 then
        sort:SetParent(self.band)
        sort:SetPoint("LEFT", self.mineButton, "RIGHT", 10, 0)
    else
        sort:SetParent(filters)
        chips[#chips + 1] = { sort, GROUP_GAP }
    end

    local x, line = 0, 0
    for _, entry in ipairs(chips) do
        local chip, gap = entry[1], entry[2]
        local width = ChipWidth(chip)
        chip:SetWidth(width)
        if x > 0 and x + gap + width > room then
            x, line, gap = 0, line + 1, 0
        elseif x == 0 then
            gap = 0
        end
        chip:ClearAllPoints()
        chip:SetPoint("TOPLEFT", filters, "TOPLEFT", x + gap, -line * CHIP_LINE)
        x = x + gap + width + CHIP_GAP
    end
    filters:SetHeight(18 + line * CHIP_LINE)
    self.chipLines = line + 1
end

--- How much of the top row is left after My level, before Settings.
function GrindingUI:TopRowRoom()
    local function Width(label)
        local text = label:GetText() or ""
        local width = Theme.TextWidth("small", text)
        local ok, drawn = pcall(label.GetStringWidth, label)
        if ok and type(drawn) == "number" and drawn > width then width = drawn end
        return width
    end

    local used = Width(self.levelLabel) + 8 + self.low:GetWidth() + 6 + Width(self.toLabel)
        + 6 + self.high:GetWidth() + 10 + self.mineButton:GetWidth()
    local frameWidth = ns.UI.frame and ns.UI.frame:GetWidth()
    if type(frameWidth) ~= "number" or frameWidth <= 0 then frameWidth = ns.UI.BASE_WIDTH or 724 end
    local settings = ns.UI.settingsButton and ns.UI.settingsButton:GetWidth() or 64
    return frameWidth - PADDING - settings - 8 - (ns.UI.HEAD_LEFT or PADDING) - used
end

function GrindingUI:PlaceHeadings()
    for key, label in pairs(self.headings) do
        local column = self.columns[key]
        local x, w = column.x, column.w
        if key == "level" then
            -- Centred over its column by width, so the sort arrow, placed
            -- after the words, stays clear of them.
            local text = math.ceil(Theme.TextWidth("tiny", label:GetText() or "")) + 2
            x, w = x + math.max(0, math.floor((w - text) / 2)), math.min(w, text)
        end
        label:ClearAllPoints()
        label:SetPoint("TOPLEFT", 8 + x, -8)
        label:SetWidth(w)
    end
end

--------------------------------------------------------------------------------
-- Rows
--------------------------------------------------------------------------------

local CELLS = { "type", "mob", "level", "gives", "worth", "badge" }

function GrindingUI:CreateRow(row)
    row.band = row:CreateTexture(nil, "BACKGROUND", nil, 1)
    row.band:SetAllPoints(row)
    row.band:SetColorTexture(Theme.Unpack("header"))

    row.bandGlow = row:CreateTexture(nil, "BACKGROUND", nil, 2)
    row.bandGlow:SetAllPoints(row)
    row.bandGlow:SetColorTexture(1, 1, 1, 1)
    do
        local r, g, b = Theme.Unpack("accent")
        local ok = type(CreateColor) == "function" and pcall(row.bandGlow.SetGradient, row.bandGlow,
            "HORIZONTAL", CreateColor(r, g, b, 0.16), CreateColor(r, g, b, 0))
        if not ok then row.bandGlow:SetColorTexture(r, g, b, 0.05) end
    end

    row.bandStripe = row:CreateTexture(nil, "ARTWORK")
    row.bandStripe:SetPoint("TOPLEFT")
    row.bandStripe:SetPoint("BOTTOMLEFT")
    row.bandStripe:SetWidth(2)
    row.bandStripe:SetColorTexture(Theme.Unpack("accent", 0.8))

    row.heading = Theme.CreateLabel(row, "small", "accent")
    row.heading:SetPoint("LEFT", 8, 0)
    row.heading:SetPoint("RIGHT", -2, 0)

    row.type = Theme.CreateLabel(row, "small", "muted")
    row.mob = Theme.CreateLabel(row, "small", "text")
    row.level = Theme.CreateLabel(row, "small", "text", "CENTER")
    row.gives = Theme.CreateLabel(row, "small", "muted")
    row.worth = Theme.CreateLabel(row, "small", "good")
    row.badge = Theme.CreateLabel(row, "tiny", "good", "RIGHT")

    self:PlaceRow(row)
end

function GrindingUI:PlaceRow(row)
    local columns = self.columns
    if row.layout == columns then return end
    row.layout = columns

    for _, key in ipairs(CELLS) do
        row[key]:ClearAllPoints()
        row[key]:SetPoint("LEFT", columns[key].x, 0)
        row[key]:SetWidth(columns[key].w)
    end
end

--- What a mob gives, in words: "Cloth, Skinning".
local function GivesText(mob)
    local parts = {}
    for _, entry in ipairs(ns.Grinding.GIVES) do
        if mob[entry.key] then parts[#parts + 1] = entry.label end
    end
    return table.concat(parts, ", ")
end

--- What a kill is worth, as the Rankings tab shows it: your own kills
--- plainly, the database's estimate with a "~". Empty when nothing is priced.
function GrindingUI:WorthText(mob)
    self.worthKept = self.worthKept or {}
    self.worthCopper = self.worthCopper or {}
    local kept = self.worthKept[mob.name]
    if kept == nil then
        local ok, value, details = pcall(ns.Value.ForMob, ns.Value, mob.name)
        kept = ""
        self.worthCopper[mob.name] = -1
        if ok and type(value) == "number" then
            kept = (details and details.basis == "tally" and "" or "~") .. ns.Value.Coins(value)
            self.worthCopper[mob.name] = value
        end
        self.worthKept[mob.name] = kept
    end
    return kept, self.worthCopper[mob.name]
end

--- The texts a mob's row shows, by column; shared by drawing and fitting.
function GrindingUI:MobTexts(mob)
    return {
        type = mob.type or "?",
        mob = mob.name,
        level = ns.Search:LevelText(mob),
        gives = GivesText(mob),
        worth = self:WorthText(mob),
    }
end

--- A camp's band: "The Barrens, The Dry Hills  14-18, 4 mobs, next zone over".
function GrindingUI.CampText(camp)
    local parts = { Util.Plural(camp.count, "mob") }
    local distance = ns.Spots.DistanceText(camp.hops, camp.zone, camp.travel)
    if distance ~= "" then parts[#parts + 1] = distance end
    return ("%s, %s  %s"):format(camp.zone, camp.label,
        Util.Colored("muted", ("(%s, %s)"):format(ns.Search:LevelText(camp), table.concat(parts, ", "))))
end

function GrindingUI:UpdateRow(row, data)
    self:PlaceRow(row)

    row.heading:Hide()
    row.band:Hide()
    row.bandGlow:Hide()
    row.bandStripe:Hide()
    for _, key in ipairs(CELLS) do row[key]:Hide() end

    if data.type == "camp" then
        row.band:Show()
        row.bandGlow:Show()
        row.bandStripe:Show()
        row.heading:SetTextColor(Theme.Unpack("accent"))
        row.heading:SetText(GrindingUI.CampText(data.camp))
        row.heading:Show()
        return
    end

    if data.type == "note" then
        row.heading:SetTextColor(Theme.Unpack("muted"))
        row.heading:SetText(INDENT .. data.text)
        row.heading:Show()
        return
    end

    local mob = data.mob
    local texts = self:MobTexts(mob)
    for _, key in ipairs({ "type", "mob", "level", "gives", "worth" }) do
        row[key]:SetText(texts[key])
        row[key]:Show()
    end
    row.type:SetTextColor(Theme.Unpack(mob.type and "muted" or "dim"))
    row.worth:SetTextColor(Theme.Unpack(texts.worth:sub(1, 1) == "~" and "muted" or "good"))

    if mob.forever then
        row.badge:SetText(BADGE_TEXT)
        row.badge:Show()
    end
end

function GrindingUI:ShowRowTooltip(row, data)
    if not GameTooltip then return end

    if data.type == "mob" then
        if ns.UI and ns.UI.ShowMobTooltip then ns.UI:ShowMobTooltip(row, data.mob.name) end
        return
    end

    if data.type ~= "camp" then return end
    local camp = data.camp
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:AddLine(("%s, %s"):format(camp.zone, camp.label), Theme.Unpack("accent"))
    for _, mob in ipairs(camp.mobs) do
        GameTooltip:AddDoubleLine(mob.name, ns.Search:LevelText(mob), 1, 1, 1, Theme.Unpack("muted"))
    end
    GameTooltip:AddLine("Click to point the arrow here.", Theme.Unpack("good"))
    GameTooltip:Show()
end

--- A camp points the arrow there; a mob opens its loot table, or says why not.
function GrindingUI:OnRowClick(data)
    if data.type == "camp" then
        local camp = data.camp
        ns.Arrow:Grind(camp)
        ns.Print(ns.Grinding:Line(camp))
        return
    end

    if data.type ~= "mob" then return end
    local mob = data.mob.name
    if ns.LootTableUI and ns.LootTableUI:Show(mob) then return end
    ns.Print(("%s: you have not killed one yet, so there is no loot table."):format(
        Util.Colored("accent", mob)))
end

--------------------------------------------------------------------------------
-- Drawing
--------------------------------------------------------------------------------

-- The headings that sort a camp's mobs.
GrindingUI.MOB_KEYS = { type = true, mob = true, level = true, gives = true, worth = true }

--- What a mob sorts by under heading `key`; mobs with nothing go last.
function GrindingUI:SortValue(mob, key)
    if key == "type" then return mob.type and mob.type:lower() or "~" end
    if key == "mob" then return mob.name:lower() end
    if key == "level" then return (mob.minLevel or 0) * 100 + (mob.maxLevel or mob.minLevel or 0) end
    if key == "gives" then
        local text = GivesText(mob)
        return text ~= "" and text:lower() or "~"
    end
    local _, copper = self:WorthText(mob)
    return copper or -1
end

--- A camp's mobs in the order the headings ask for (a copy; the camp keeps
--- its own order).
function GrindingUI:SortedMobs(mobs)
    local saved = ns.db.grindColumns
    local key = type(saved) == "table" and saved.key
    if not GrindingUI.MOB_KEYS[key or ""] then return mobs end

    local up = saved.ascending and true or false
    local sorted = {}
    for index, mob in ipairs(mobs) do sorted[index] = mob end
    table.sort(sorted, function(a, b)
        local va, vb = self:SortValue(a, key), self:SortValue(b, key)
        if va ~= vb then
            if up then return va < vb end
            return va > vb
        end
        return a.name < b.name
    end)
    return sorted
end

--- The camps as list rows: a band per camp, its mobs under it.
function GrindingUI:Rows(camps, unknown, low, high)
    local rows = {}
    local Grinding = ns.Grinding

    for _, camp in ipairs(camps) do
        rows[#rows + 1] = { type = "camp", camp = camp }
        for _, mob in ipairs(self:SortedMobs(camp.mobs)) do
            rows[#rows + 1] = { type = "mob", mob = mob, camp = camp }
        end
    end

    if #camps == 0 then
        local what = Grinding:Type() and (Grinding:Type():lower() .. " ") or ""
        rows[#rows + 1] = { type = "note", text = ("No %smobs from level %d to %d that Farmer has seen yet.")
            :format(what, low, high) }
    end

    if unknown > 0 then
        rows[#rows + 1] = { type = "note", text = ("%s in this range not shown: nobody has seen "
            .. "their type yet. Target or hover one to learn it."):format(Util.Plural(unknown, "more mob")) }
    end

    return rows
end

--- Widen the columns to fit these rows, and return the window width they want.
function GrindingUI:FitColumns(rows)
    local widths = {}
    for key, w in pairs(BASE_WIDTH) do widths[key] = w end

    for _, row in ipairs(rows) do
        if row.type == "mob" then
            local texts = self:MobTexts(row.mob)
            for _, key in ipairs({ "type", "mob", "gives", "worth" }) do
                widths[key] = math.max(widths[key], Theme.TextWidth("small", texts[key]) + 8)
            end
        end
    end

    for key, most in pairs(MAX_WIDTH) do
        widths[key] = math.min(most, math.ceil(widths[key]))
    end

    local room = ns.UI and ns.UI.ScreenRoom and ns.UI:ScreenRoom()
    if room then
        local over = Columns(widths).total + CHROME - room
        for _, key in ipairs({ "mob", "gives", "worth", "type" }) do
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

--- Put the controls in step with what is saved.
function GrindingUI:PaintControls(low, high)
    local Grinding = ns.Grinding
    self.sortChip.label:SetText(GrindingUI.SortText())
    -- The game's font is loaded by the first draw: measure again.
    self:LayoutChips()
    self.low:SetValue(low, true)
    self.high:SetValue(high, true)
    self.mineButton:SetLabelColor(Grinding:FollowsLevel() and "good" or nil)

    local kind = Grinding:Type()
    for _, chip in ipairs(self.typeChips) do
        chip:SetSelected((chip:GetFilterKind() or nil) == kind)
    end
    local gives = Grinding:Gives()
    for _, chip in ipairs(self.givesChips) do
        chip:SetSelected(chip.givesKey == gives)
    end
    self.sortChip:SetSelected(Grinding.Sort() ~= "busiest")
    if self.sorter then
        local saved = ns.db.grindColumns
        local key = type(saved) == "table" and GrindingUI.MOB_KEYS[saved.key or ""] and saved.key or nil
        self.sorter:Set(key, key and saved.ascending)
    end
end

--- Work the camps out again and draw them. Returns the window width it wants.
function GrindingUI:Render(arrive)
    if not self.view then return end

    -- Prices and tallies can move between renders; worth is kept per render.
    self.worthKept = {}
    self.worthCopper = {}

    local camps, unknown, low, high = ns.Grinding:Camps()
    self.camps = camps
    self:PaintControls(low, high)

    local rows = self:Rows(camps, unknown, low, high)
    local width = self:FitColumns(rows)

    self.list:SetData(rows, not arrive)
    if arrive then self.list:Arrive() end

    -- The world map shows what the list shows.
    if ns.GrindPins then ns.GrindPins:Show(camps) end

    if ns.UI and ns.UI.frame and ns.UI.tab == "grind" then
        ns.UI.frame:SetWidth(math.max(ns.UI.BASE_WIDTH or 0, width))
    end

    return width
end

--- Redraw if the tab is on screen.
function GrindingUI:Refresh()
    if self.view and self.view:IsShown() and ns.UI.frame:IsShown() then
        self:Render()
    end
end
