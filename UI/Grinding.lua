-- Blackthornes Farmer -- UI/Grinding.lua
-- The Grind tab of the main window: where mobs of a level band and a kind
-- gather (Logic/Grinding.lua).
--
-- Across the top: the level band on two steppers, with My level to follow
-- yours. Under it: the creature type (Any, Humanoid, Beast, ...), what they
-- give (Cloth, Leather, Ore, Herbs), and the Sort menu (Busiest, Nearest,
-- Level, Level then nearest). The list is one band per camp with its mobs
-- under it: type, level, what they give and what a kill is worth; the
-- column headings sort the mobs within each camp. A click on a camp points
-- the arrow there; the camps listed also show on the world map
-- (UI/GrindPins.lua).
--
-- Leather adds the Skinning each mob needs, what a skin is worth and how
-- many you skinned. Ore and Herbs list zones and their nodes instead
-- (Logic/GrindGather.lua): the skill, what a node gives, your gathers and
-- spots, how long it takes to grow back, a gather's worth and an hour's.
-- What you cannot gather yet is greyed with the skill it needs.

local _, ns = ...
local L = ns.L

local GrindingUI = ns.NewModule("GrindingUI")

local Theme = ns.Theme
local Widgets = ns.Widgets
local Util = ns.Util

--- Upper case that keeps German's umlauts upper too (Lua's upper only
--- knows A to Z).
local function Upper(text)
    return (text:upper():gsub("ä", "Ä"):gsub("ö", "Ö"):gsub("ü", "Ü"))
end

local PADDING = 14
local ROW_HEIGHT = 20
local COLUMN_GAP = 6

-- What the window adds around the columns, as the Rankings tab counts it.
local CHROME = 74

-- The columns each view shows, left to right.
GrindingUI.LAYOUTS = {
    mobs = { "type", "mob", "level", "gives", "worth", "badge" },
    leather = { "type", "mob", "level", "skill", "gives", "worth", "count", "badge" },
    nodes = { "mob", "skill", "gives", "count", "spots", "respawn", "worth", "hour" },
}
-- Every column any view has.
local ALL_KEYS = { "type", "mob", "level", "skill", "gives", "worth", "count", "spots", "respawn", "hour", "badge" }

local BASE_WIDTH = { type = 74, mob = 190, level = 46, gives = 110, worth = 90, badge = 50,
    skill = 50, count = 60, spots = 44, respawn = 70, hour = 76 }
local MAX_WIDTH = { type = 110, mob = 320, gives = 240, worth = 160, skill = 160, count = 90,
    respawn = 110, hour = 120 }

local BADGE_TEXT = "Forever"
local INDENT = "     "

--- The view the list is in: "mobs", "leather" or "nodes".
function GrindingUI.Layout()
    local gives = ns.Grinding:Gives()
    if ns.Grinding.IsNodeView(gives) then return "nodes" end
    if gives == "skinning" then return "leather" end
    return "mobs"
end

--- Column left edges and widths for the given widths, in view `layout`.
local function Columns(widths, layout)
    layout = layout or "mobs"
    local columns, x = { layout = layout, shown = {} }, 0
    for _, key in ipairs(GrindingUI.LAYOUTS[layout]) do
        local w = widths and widths[key] or BASE_WIDTH[key]
        columns[key] = { x = x, w = w }
        columns.shown[key] = true
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
    levelLabel:SetText(L["Levels"])
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
    to:SetText(L["to"])
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

    local mine = Widgets.CreateButton(band, L["My level"], function()
        Grinding:FollowLevel()
        GrindingUI:Render(true)
    end, { width = 70, height = 20 })
    mine:SetPoint("LEFT", self.high, "RIGHT", 10, 0)
    mine:HookScript("OnEnter", function(self)
        Tip(self, L["Follow your level"], L.Format("From %d below your level to %d above, moving as you level.",
            Grinding.BELOW, Grinding.ABOVE))
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

    local any = Chip(filters, L["ANY TYPE"], function()
        Grinding:SetType(nil)
        GrindingUI:Render(true)
    end)
    any.filterKind = false
    self.typeChips[1] = any

    local kinds = {}
    for _, kind in ipairs(Grinding.TYPES) do kinds[#kinds + 1] = kind end
    kinds[#kinds + 1] = Grinding.OTHER

    for _, kind in ipairs(kinds) do
        local chip = Chip(filters, Upper(Grinding.TypeLabel(kind)), function()
            Grinding:SetType(kind)
            GrindingUI:Render(true)
        end, kind == Grinding.OTHER
            and { L["Other types"], L["Giants, dragonkin, mechanical and the rest."] } or nil)
        chip.filterKind = kind
        self.typeChips[#self.typeChips + 1] = chip
    end

    self.givesChips = {}
    for _, entry in ipairs(Grinding.GIVES) do
        local chip = Chip(filters, Upper(entry.label), function()
            -- A second click lets it go.
            Grinding:SetGives(Grinding:Gives() ~= entry.key and entry.key or nil)
            GrindingUI:Render(true)
        end, GrindingUI.GIVES_TIPS[entry.key])
        chip.givesKey = entry.key
        self.givesChips[#self.givesChips + 1] = chip
    end

    -- The order of the camps. Up in the top row beside My level, where
    -- there is room: on the chip row it ran into Skinning (2026-10-10).
    local sort = Chip(band, GrindingUI.SortText(), function()
        GrindingUI:ToggleSortMenu()
    end, { L["Sort the camps"], L["Busiest, nearest, by level, or by level and then the nearest."] })
    self.sortChip = sort
    self:BuildSortMenu(view)

    self:LayoutChips()

    local panel = Theme.CreatePanel(view, "panel", "border")
    panel:SetPoint("TOPLEFT", filters, "BOTTOMLEFT", 0, -8)
    panel:SetPoint("BOTTOMRIGHT", view, "BOTTOMRIGHT", -PADDING, 36)
    if Theme.Recess then Theme.Recess(panel) end
    self.panel = panel

    self.headings = {}
    for _, key in ipairs(ALL_KEYS) do
        if key ~= "badge" then
            local label = Theme.CreateLabel(panel, "tiny", "dim")
            label:SetText(GrindingUI.HeadingText("mobs", key))
            self.headings[key] = label
        end
    end

    self.columns = Columns(nil, "mobs")

    -- The headings sort the mobs within each camp (the nodes within each
    -- zone); the Sort menu orders the camps. Saved as grindColumns. The
    -- tips are this view's, filled in by PlaceHeadings.
    local saved = type(ns.db.grindColumns) == "table" and ns.db.grindColumns or {}
    self.headingTips = {}
    GrindingUI.FillTips(self.headingTips, "mobs")
    self.sorter = Widgets.SortableHeadings(self.headings, self.headingTips, function(key, ascending)
        ns.db.grindColumns = key and { key = key, ascending = ascending } or nil
        GrindingUI:Render()
    end, {
        startsLow = { type = true, mob = true, level = true, gives = true, skill = true, respawn = true },
        key = GrindingUI.MOB_KEYS[saved.key] and saved.key or nil,
        ascending = saved.ascending,
    })
    self:PlaceHeadings()

    local rule = Theme.CreateDivider(panel, "border")
    rule:SetPoint("TOPLEFT", 8, -20)
    rule:SetPoint("TOPRIGHT", -8, -20)

    local list = Widgets.CreateRowList(panel, {
        rowHeight = ROW_HEIGHT,
        createRow = function(row) GrindingUI:CreateRow(row) end,
        updateRow = function(row, data) GrindingUI:UpdateRow(row, data) end,
        onClick = function(data, button) GrindingUI:OnRowClick(data, button) end,
        onEnter = function(row, data) GrindingUI:ShowRowTooltip(row, data) end,
        onLeave = HideTip,
        fadeKey = "well",
    })
    list:SetPoint("TOPLEFT", 8, -24)
    list:SetPoint("BOTTOMRIGHT", -8, 8)
    self.list = list

    local footer = Theme.CreateLabel(view, "tiny", "dim")
    footer:SetPoint("BOTTOMLEFT", PADDING, 6)
    -- Short of the version in the corner, as the other tabs' footers are.
    footer:SetPoint("BOTTOMRIGHT", -(PADDING + (ns.UI.VERSION_ROOM or 0)), 6)
    footer:SetHeight(26)
    footer:SetWordWrap(true)
    footer:SetJustifyV("MIDDLE")
    footer:SetText(L["Click a camp to point the arrow there. Camps show on your world map too. Target or hover a mob to learn its type."])
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
    return L.Format("SORT: %s", Upper(ns.Grinding.SortLabel()))
end

--- A small list under the sort chip, one line per order, the one in use lit.
function GrindingUI:BuildSortMenu(view)
    local menu = Theme.CreatePanel(view, "panel", "metal")
    -- A layer above the window it opens from (DIALOG): in the same layer it
    -- drew under the chips and headings, which showed through (2026-10-10).
    pcall(menu.SetFrameStrata, menu, "FULLSCREEN_DIALOG")
    pcall(menu.SetToplevel, menu, true)
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
    -- And over the window's own rim and trim, whatever their level.
    local ok, level = pcall(ns.UI.frame.GetFrameLevel, ns.UI.frame)
    if ok and type(level) == "number" then menu:SetFrameLevel(level + 40) end
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
    -- Ore and Herbs are nodes: no creature types.
    local nodes = ns.Grinding.IsNodeView(ns.Grinding:Gives())
    for _, chip in ipairs(self.typeChips) do
        chip:SetShown(not nodes)
        if not nodes then chips[#chips + 1] = { chip, 0 } end
    end
    -- The Leather chip goes while skinning is left out (DB:ShowsSkinning)
    -- and you do not know Skinning.
    local leather = ns.Grinding.OffersLeather()
    for index, chip in ipairs(self.givesChips) do
        if chip.givesKey == "skinning" and not leather then
            chip:Hide()
        else
            chip:Show()
            chips[#chips + 1] = { chip, (index == 1 and not nodes) and GROUP_GAP or 0 }
        end
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
    local columns = self.columns
    if self.headingTips then GrindingUI.FillTips(self.headingTips, columns.layout) end
    for key, label in pairs(self.headings) do
        local column = columns[key]
        local shown = column ~= nil
        label:SetShown(shown)
        local button = self.sorter and self.sorter.buttons[key]
        if button then button:SetShown(shown) end
    end
    for key, label in pairs(self.headings) do
        local column = columns[key]
        if not column then
            -- Not in this view.
        else
        label:SetText(GrindingUI.HeadingText(columns.layout, key))
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
    if self.sorter then self.sorter.Paint() end
end

--- A heading's words in view `layout`.
function GrindingUI.HeadingText(layout, key)
    if key == "mob" then
        if layout == "nodes" then
            return ns.Grinding:Gives() == "herbs" and L["HERB"] or L["NODE"]
        end
        return L["MOB"]
    end
    if key == "gives" then return layout == "leather" and L["LEATHER"] or L["GIVES"] end
    if key == "worth" then
        if layout == "leather" then return L["PER SKIN"] end
        if layout == "nodes" then return L["PER GATHER"] end
        return L["PER KILL"]
    end
    if key == "count" then return layout == "leather" and L["SKINNED"] or L["GATHERED"] end
    local words = { type = L["TYPE"], level = L["LEVEL"], skill = L["SKILL"], spots = L["SPOTS"],
        respawn = L["GROWS BACK"], hour = L["AN HOUR"] }
    return words[key] or ""
end

--- The headings' tips for view `layout`, written into `tips`.
function GrindingUI.FillTips(tips, layout)
    for key in pairs(tips) do tips[key] = nil end
    if layout == "nodes" then
        tips.mob = L["Sort each zone's nodes by name."]
        tips.skill = L["Sort each zone's nodes by the skill they need."]
        tips.gives = L["Sort each zone's nodes by what they give."]
        tips.count = L["Sort each zone's nodes by how often you gathered them."]
        tips.spots = L["Sort each zone's nodes by the spots you marked."]
        tips.respawn = L["Sort each zone's nodes by how soon they grow back."]
        tips.worth = L["Sort each zone's nodes by what a gather is worth."]
        tips.hour = L["Sort each zone's nodes by what an hour of them is worth."]
        return
    end
    tips.type = L["Sort each camp's mobs by type."]
    tips.mob = L["Sort each camp's mobs by name."]
    tips.level = L["Sort each camp's mobs by level."]
    tips.gives = L["Sort each camp's mobs by what they give."]
    if layout == "leather" then
        tips.skill = L["Sort each camp's mobs by the Skinning they need."]
        tips.worth = L["Sort each camp's mobs by what a skin is worth."]
        tips.count = L["Sort each camp's mobs by how many you skinned."]
    else
        tips.worth = L["Sort each camp's mobs by what a kill is worth."]
    end
end

-- The gives chips' tooltips.
GrindingUI.GIVES_TIPS = {
    cloth = { L["Drops cloth"], L["Mobs the data has dropping cloth. Click again for any."] },
    skinning = { L["Leather"], L["Beasts to skin, with the Skinning each needs. Click again for any."] },
    ore = { L["Ore"], L["Zones with mining nodes, and what yours were worth. Click again for mobs."] },
    herbs = { L["Herbs"], L["Zones with herbs, and what yours were worth. Click again for mobs."] },
}

--------------------------------------------------------------------------------
-- Rows
--------------------------------------------------------------------------------

local CELLS = ALL_KEYS

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
    row.skill = Theme.CreateLabel(row, "small", "text", "CENTER")
    row.count = Theme.CreateLabel(row, "small", "text", "CENTER")
    row.spots = Theme.CreateLabel(row, "small", "text", "CENTER")
    row.respawn = Theme.CreateLabel(row, "small", "muted")
    row.hour = Theme.CreateLabel(row, "small", "good")

    self:PlaceRow(row)
end

function GrindingUI:PlaceRow(row)
    local columns = self.columns
    if row.layout == columns then return end
    row.layout = columns

    for _, key in ipairs(CELLS) do
        local column = columns[key]
        row[key]:ClearAllPoints()
        if column then
            row[key]:SetPoint("LEFT", column.x, 0)
            row[key]:SetWidth(column.w)
        end
    end
end

--- What a mob gives, in words: "Cloth, Leather". Leather only while
--- skinning shows; in the Leather view, the leather and hides themselves.
local function GivesText(mob)
    if GrindingUI.Layout() == "leather" then
        local names = {}
        for name in pairs(mob.leathers or {}) do names[#names + 1] = name end
        table.sort(names)
        return table.concat(names, ", ")
    end
    local parts = {}
    local skinning = ns.DB:ShowsSkinning()
    for _, entry in ipairs(ns.Grinding.GIVES) do
        if mob[entry.key] and (entry.key ~= "skinning" or skinning) then parts[#parts + 1] = entry.label end
    end
    return table.concat(parts, ", ")
end
GrindingUI.GivesText = GivesText

--- The skill a row needs, and your own: the words, and whether you are
--- short of it. "105, you have 94" when short.
function GrindingUI.SkillText(need, have)
    if not need then return "", false end
    if have and have < need then return L.Format("%d, you have %d", need, have), true end
    return tostring(need), false
end

--- The Skinning a mob needs: the data's, else Classic's rule from its level.
function GrindingUI.SkinNeed(mob)
    return mob.skinSkill or ns.Grinding.SkinSkill(mob.minLevel)
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

--- What a skin of `mob` is worth, from your own skins; "" when none.
function GrindingUI:SkinText(mob)
    self.skinKept = self.skinKept or {}
    local kept = self.skinKept[mob.name]
    if kept == nil then
        local copper, skins = ns.GrindGather:SkinWorth(mob.name)
        local entry = ns.GrindGather:Skins(mob.name)
        kept = { text = copper and ns.Value.Coins(copper) or "", copper = copper or -1,
            skins = entry and entry.skins or 0 }
        self.skinKept[mob.name] = kept
    end
    return kept.text, kept.copper, kept.skins
end

--- The texts a mob's row shows, by column; shared by drawing and fitting.
function GrindingUI:MobTexts(mob)
    local texts = {
        type = mob.type and ns.Grinding.TypeLabel(mob.type) or "?",
        mob = mob.name,
        level = ns.Search:LevelText(mob),
        gives = GivesText(mob),
        worth = self:WorthText(mob),
    }
    if GrindingUI.Layout() == "leather" then
        local text, _, skins = self:SkinText(mob)
        texts.worth = text
        texts.count = skins > 0 and tostring(skins) or ""
        texts.skill, texts.short = GrindingUI.SkillText(GrindingUI.SkinNeed(mob), ns.Grinding.SkinningSkill())
    end
    return texts
end

--- The texts a node's row shows, by column.
function GrindingUI:NodeTexts(node)
    local view = ns.GrindGather.VIEWS[ns.Grinding:Gives()]
    local have = view and ns.GrindGather.PlayerSkill(view.skill)
    local skill, short = GrindingUI.SkillText(node.skill, have)
    return {
        mob = node.name,
        skill = skill,
        short = short,
        gives = table.concat(node.givesList or {}, ", "),
        count = node.gathers > 0 and tostring(node.gathers) or "",
        spots = node.spots > 0 and tostring(node.spots) or "",
        respawn = node.respawn and L.Format("about %s", ns.Respawn.Duration(node.respawn)) or "",
        worth = node.perGather and ns.Value.Coins(node.perGather) or "",
        hour = node.perHour and ns.Value.Coins(node.perHour) or "",
    }
end

--- A zone's band in the node views: "The Barrens  (10-25, 3 nodes, you're here)".
function GrindingUI.ZoneText(zone)
    local parts = {}
    if zone.minLevel then parts[#parts + 1] = ns.Search:LevelText(zone) end
    parts[#parts + 1] = Util.Plural(zone.count, L["node"], L["nodes"])
    local distance = ns.Spots.DistanceText(zone.hops, zone.zone, zone.travel)
    if distance ~= "" then parts[#parts + 1] = distance end
    return ("%s  %s"):format(ns.Spots.Show(zone.zone),
        Util.Colored("muted", ("(%s)"):format(table.concat(parts, ", "))))
end

--- The footer: your skill for the view, then what a click does.
function GrindingUI.FooterText(layout)
    local hint
    if layout == "nodes" then
        hint = L["Click a node to point the arrow at its spots you marked. Levels are the zone's."]
    elseif layout == "leather" then
        hint = L["Click a camp to point the arrow there. The Skinning a mob needs is worked out from its level."]
    else
        return L["Click a camp to point the arrow there. Camps show on your world map too. Target or hover a mob to learn its type."]
    end
    local skillName = layout == "leather" and "Skinning"
        or (ns.GrindGather.VIEWS[ns.Grinding:Gives()] or {}).skill
    local have, read = ns.GrindGather.PlayerSkill(skillName)
    local label = ({ Skinning = L["Skinning"], Mining = L["Mining"], Herbalism = L["Herbalism"] })[skillName]
        or skillName
    if have then return L.Format("Your %s: %d.", label, have) .. " " .. hint end
    if read then return L.Format("You don't know %s.", label) .. " " .. hint end
    return hint
end

--- A camp's band: "The Barrens, The Dry Hills  14-18, 4 mobs, next zone over".
function GrindingUI.CampText(camp)
    local parts = { Util.Plural(camp.count, L["mob"], L["mobs"]) }
    local distance = ns.Spots.DistanceText(camp.hops, camp.zone, camp.travel)
    if distance ~= "" then parts[#parts + 1] = distance end
    return ("%s, %s  %s"):format(ns.Spots.Show(camp.zone), camp.label,
        Util.Colored("muted", ("(%s, %s)"):format(ns.Search:LevelText(camp), table.concat(parts, ", "))))
end

function GrindingUI:UpdateRow(row, data)
    self:PlaceRow(row)

    row.heading:Hide()
    row.band:Hide()
    row.bandGlow:Hide()
    row.bandStripe:Hide()
    for _, key in ipairs(CELLS) do row[key]:Hide() end

    if data.type == "camp" or data.type == "zone" then
        row.band:Show()
        row.bandGlow:Show()
        row.bandStripe:Show()
        row.heading:SetTextColor(Theme.Unpack("accent"))
        row.heading:SetText(data.type == "zone" and GrindingUI.ZoneText(data.zone) or GrindingUI.CampText(data.camp))
        row.heading:Show()
        return
    end

    local columns = self.columns

    if data.type == "node" then
        local texts = self:NodeTexts(data.node)
        for key in pairs(columns.shown) do
            if texts[key] then
                row[key]:SetText(texts[key])
                row[key]:Show()
            end
        end
        local short = texts.short
        row.mob:SetTextColor(Theme.Unpack(short and "dim" or "text"))
        row.gives:SetTextColor(Theme.Unpack(short and "dim" or "muted"))
        row.skill:SetTextColor(Theme.Unpack(short and "loss" or "text"))
        for _, key in ipairs({ "count", "spots" }) do row[key]:SetTextColor(Theme.Unpack(short and "dim" or "text")) end
        row.respawn:SetTextColor(Theme.Unpack(short and "dim" or "muted"))
        row.worth:SetTextColor(Theme.Unpack(short and "dim" or "good"))
        row.hour:SetTextColor(Theme.Unpack(short and "dim" or "good"))
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
    for _, key in ipairs({ "type", "mob", "level", "gives", "worth", "skill", "count" }) do
        if columns.shown[key] and texts[key] then
            row[key]:SetText(texts[key])
            row[key]:Show()
        end
    end
    local short = texts.short
    row.type:SetTextColor(Theme.Unpack(mob.type and not short and "muted" or "dim"))
    row.mob:SetTextColor(Theme.Unpack(short and "dim" or "text"))
    row.level:SetTextColor(Theme.Unpack(short and "dim" or "text"))
    row.gives:SetTextColor(Theme.Unpack(short and "dim" or "muted"))
    row.skill:SetTextColor(Theme.Unpack(short and "loss" or "text"))
    row.count:SetTextColor(Theme.Unpack(short and "dim" or "text"))
    row.worth:SetTextColor(Theme.Unpack(short and "dim" or (texts.worth:sub(1, 1) == "~" and "muted" or "good")))

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

    if data.type == "node" then
        local node = data.node
        local texts = self:NodeTexts(node)
        GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
        GameTooltip:AddLine(("%s, %s"):format(node.name, ns.Spots.Show(node.zone)), Theme.Unpack("accent"))
        if texts.skill ~= "" then
            GameTooltip:AddDoubleLine(L["Skill"], texts.skill, 1, 1, 1, Theme.Unpack(texts.short and "loss" or "text"))
        end
        for _, name in ipairs(node.givesList or {}) do
            GameTooltip:AddLine(name, Theme.Unpack("muted"))
        end
        if node.gathers > 0 then
            GameTooltip:AddDoubleLine(L["You gathered it"], tostring(node.gathers), 1, 1, 1, 1, 1, 1)
        end
        if texts.respawn ~= "" then
            GameTooltip:AddDoubleLine(L["Grows back"], texts.respawn, 1, 1, 1, Theme.Unpack("muted"))
        end
        if texts.worth ~= "" then
            GameTooltip:AddDoubleLine(L["A gather"], texts.worth, 1, 1, 1, Theme.Unpack("good"))
        end
        if texts.hour ~= "" then
            GameTooltip:AddDoubleLine(L["An hour"], texts.hour, 1, 1, 1, Theme.Unpack("good"))
        elseif node.gathers > 0 then
            GameTooltip:AddLine(L["Gather here a while longer to see what an hour is worth."], Theme.Unpack("muted"), true)
        end
        if node.spots > 0 then
            GameTooltip:AddLine(L["Click to point the arrow at your spots."], Theme.Unpack("good"))
        end
        GameTooltip:Show()
        return
    end

    if data.type ~= "camp" then return end
    local camp = data.camp
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:AddLine(("%s, %s"):format(ns.Spots.Show(camp.zone), camp.label), Theme.Unpack("accent"))
    for _, mob in ipairs(camp.mobs) do
        GameTooltip:AddDoubleLine(mob.name, ns.Search:LevelText(mob), 1, 1, 1, Theme.Unpack("muted"))
    end
    GameTooltip:AddLine(L["Click to point the arrow here."], Theme.Unpack("good"))
    GameTooltip:Show()
end

--- A camp points the arrow there; a mob opens its loot table, or says why not.
function GrindingUI:OnRowClick(data, button)
    -- Right-click on a mob offers to hide it (HideMenu).
    if button == "RightButton" then
        if data.type == "mob" then
            ns.HideMenu:Open({ { kind = "source", name = data.mob.name } })
        elseif data.type == "node" then
            ns.HideMenu:Open({ { kind = "source", name = data.node.name } })
        end
        return
    end

    if data.type == "node" or data.type == "zone" then
        local node = data.node
        if data.type == "zone" then
            -- The zone's nodes you can gather, with spots, as one.
            local merged = { name = data.zone.zone, zone = data.zone.zone, spotList = {} }
            for _, each in ipairs(data.zone.nodes) do
                if not self:NodeTexts(each).short then
                    for _, coords in ipairs(each.spotList or {}) do merged.spotList[#merged.spotList + 1] = coords end
                end
            end
            node = merged
        end
        local camp = ns.GrindGather.NodeCamp(node)
        if data.type == "zone" then camp.label = ns.Spots.Show(data.zone.zone) end
        ns.Arrow:Grind(camp)
        ns.Print(data.type == "zone" and ns.Spots.Show(data.zone.zone) or ns.GrindGather.NodeLine(node))
        return
    end

    if data.type == "camp" then
        local camp = data.camp
        ns.Arrow:Grind(camp)
        ns.Print(ns.Grinding:Line(camp))
        return
    end

    if data.type ~= "mob" then return end
    local mob = data.mob.name
    if ns.LootTableUI and ns.LootTableUI:Show(mob) then return end
    ns.Print(L.Format("%s: no kills yet, so no loot table.",
        Util.Colored("accent", mob)))
end

--------------------------------------------------------------------------------
-- Drawing
--------------------------------------------------------------------------------

-- The headings that sort a camp's mobs (or a zone's nodes).
GrindingUI.MOB_KEYS = { type = true, mob = true, level = true, gives = true, worth = true,
    skill = true, count = true, spots = true, respawn = true, hour = true }

--- What a node sorts by under heading `key`; nodes with nothing go last.
function GrindingUI:NodeSortValue(node, key)
    if key == "mob" then return node.name:lower() end
    if key == "skill" then return node.skill or 0 end
    if key == "gives" then return table.concat(node.givesList or {}, ", "):lower() end
    if key == "count" then return node.gathers end
    if key == "spots" then return node.spots end
    if key == "respawn" then return node.respawn or math.huge end
    if key == "worth" then return node.perGather or -1 end
    if key == "hour" then return node.perHour or -1 end
    return 0
end

--- A zone's nodes in the order the headings ask for (a copy).
function GrindingUI:SortedNodes(nodes)
    local saved = ns.db.grindColumns
    local key = type(saved) == "table" and saved.key
    if not (key and self.columns.shown[key]) then return nodes end
    local up = saved.ascending and true or false
    local sorted = {}
    for index, node in ipairs(nodes) do sorted[index] = node end
    table.sort(sorted, function(a, b)
        local va, vb = self:NodeSortValue(a, key), self:NodeSortValue(b, key)
        if va ~= vb then
            if up then return va < vb end
            return va > vb
        end
        return a.name < b.name
    end)
    return sorted
end

--- What a mob sorts by under heading `key`; mobs with nothing go last.
function GrindingUI:SortValue(mob, key)
    if key == "type" then return mob.type and ns.Grinding.TypeLabel(mob.type):lower() or "~" end
    if key == "mob" then return mob.name:lower() end
    if key == "level" then return (mob.minLevel or 0) * 100 + (mob.maxLevel or mob.minLevel or 0) end
    if key == "gives" then
        local text = GivesText(mob)
        return text ~= "" and text:lower() or "~"
    end
    if key == "skill" then return GrindingUI.SkinNeed(mob) or 0 end
    if key == "count" then
        local _, _, skins = self:SkinText(mob)
        return skins
    end
    if GrindingUI.Layout() == "leather" then
        local _, copper = self:SkinText(mob)
        return copper or -1
    end
    local _, copper = self:WorthText(mob)
    return copper or -1
end

--- A camp's mobs in the order the headings ask for (a copy; the camp keeps
--- its own order).
function GrindingUI:SortedMobs(mobs)
    local saved = ns.db.grindColumns
    local key = type(saved) == "table" and saved.key
    if not (GrindingUI.MOB_KEYS[key or ""] and self.columns.shown[key]) then return mobs end

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
        local text
        if Grinding:Type() then
            local what = Grinding.TypeLabel(Grinding:Type())
            if Util.EnglishClient() then what = what:lower() end
            text = L.Format("No %s mobs from level %d to %d that Farmer has seen yet.", what, low, high)
        else
            text = L.Format("No mobs from level %d to %d that Farmer has seen yet.", low, high)
        end
        rows[#rows + 1] = { type = "note", text = text }
    end

    if unknown > 0 then
        rows[#rows + 1] = { type = "note", text = L.Format("%s not shown until their type is known. Target or hover one.",
            Util.Plural(unknown, L["more mob"], L["more mobs"])) }

    end

    return rows
end

--- The node views' rows: a band per zone, its nodes under it.
function GrindingUI:NodeRows(zones, low, high)
    local rows = {}
    for _, zone in ipairs(zones) do
        rows[#rows + 1] = { type = "zone", zone = zone }
        for _, node in ipairs(self:SortedNodes(zone.nodes)) do
            rows[#rows + 1] = { type = "node", node = node, zone = zone }
        end
    end
    if #zones == 0 then
        local text = ns.Grinding:Gives() == "herbs"
            and L.Format("No herbs from level %d to %d that Farmer knows yet.", low, high)
            or L.Format("No mining nodes from level %d to %d that Farmer knows yet.", low, high)
        rows[#rows + 1] = { type = "note", text = text }
    end
    return rows
end

--- Widen the columns to fit these rows, and return the window width they want.
function GrindingUI:FitColumns(rows, layout)
    layout = layout or "mobs"
    local widths = {}
    for key, w in pairs(BASE_WIDTH) do widths[key] = w end

    -- Each heading fits its words, German included.
    for _, key in ipairs(GrindingUI.LAYOUTS[layout]) do
        if key ~= "badge" then
            widths[key] = math.max(widths[key],
                Theme.TextWidth("tiny", GrindingUI.HeadingText(layout, key)) + 14)
        end
    end

    for _, row in ipairs(rows) do
        local texts = row.type == "mob" and self:MobTexts(row.mob)
            or row.type == "node" and self:NodeTexts(row.node) or nil
        if texts then
            for _, key in ipairs({ "type", "mob", "gives", "worth", "skill", "count", "respawn", "hour" }) do
                if texts[key] then
                    widths[key] = math.max(widths[key], Theme.TextWidth("small", texts[key]) + 8)
                end
            end
        end
    end

    for key, most in pairs(MAX_WIDTH) do
        widths[key] = math.min(most, math.ceil(widths[key]))
    end

    local room = ns.UI and ns.UI.ScreenRoom and ns.UI:ScreenRoom()
    if room then
        local over = Columns(widths, layout).total + CHROME - room
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
    local changed = current.layout ~= layout
    for _, key in ipairs(GrindingUI.LAYOUTS[layout]) do
        if not current[key] or current[key].w ~= widths[key] then changed = true end
    end
    if changed then
        self.columns = Columns(widths, layout)
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
        if key and not GrindingUI.LAYOUTS[GrindingUI.Layout()] then key = nil end
        local shown = false
        for _, each in ipairs(GrindingUI.LAYOUTS[GrindingUI.Layout()]) do if each == key then shown = true end end
        if not shown then key = nil end
        self.sorter:Set(key, key and saved.ascending)
    end
end

--- Work the camps out again and draw them. Returns the window width it wants.
function GrindingUI:Render(arrive)
    if not self.view then return end

    -- Prices and tallies can move between renders; worth is kept per render.
    self.worthKept = {}
    self.worthCopper = {}
    self.skinKept = {}

    local layout = GrindingUI.Layout()
    local camps, unknown, low, high = ns.Grinding:Camps()
    local rows
    if layout == "nodes" then
        local zones = ns.GrindGather:Zones(ns.Grinding:Gives(), low, high)
        self.zones = zones
        camps = {}
        rows = self:NodeRows(zones, low, high)
    else
        self.zones = nil
        rows = self:Rows(camps, unknown, low, high)
    end
    self.camps = camps
    self:PaintControls(low, high)
    self.footer:SetText(GrindingUI.FooterText(layout))

    local width = self:FitColumns(rows, layout)

    self.list:SetData(rows, not arrive)
    if arrive then self.list:Arrive() end

    -- The world map shows what the list shows (camps; the gathering spots
    -- are already the map markers').
    if ns.GrindPins then ns.GrindPins:Show(camps) end

    if ns.UI and ns.UI.frame and ns.UI.tab == "grind" then
        ns.UI.frame:SetWidth(math.max(ns.UI.BASE_WIDTH or 0, width))
    end

    return width
end

--- "Hide skinning" moved: the chips are laid out again (the Skinning
--- chip comes or goes) and the camps redrawn if the tab is on screen; out
--- of sight, the list's stamp moved, so its next draw builds it again.
function GrindingUI:SkinningChanged()
    if not self.view then return end
    self:LayoutChips()
    self:Refresh()
end

ns.DB.hideWatchers.grind = function() GrindingUI:SkinningChanged() end

--- Redraw if the tab is on screen.
function GrindingUI:Refresh()
    local frame = ns.UI and ns.UI.frame
    if self.view and self.view:IsShown() and frame and frame:IsShown() then
        self:Render()
    end
end

-- "My level" follows the character's level, and the order by nearest the
-- zone they are in, so a level or a new zone redraws the tab (and its map
-- pins) while it is on screen; it is left alone when it is not.
function GrindingUI:OnEnable()
    local function Changed() GrindingUI:Refresh() end
    -- The new level can reach UnitLevel a moment after the event.
    ns.RegisterEvent(self, "PLAYER_LEVEL_UP", function()
        if C_Timer and C_Timer.After then C_Timer.After(1, Changed) else Changed() end
    end)
    ns.RegisterEvent(self, "ZONE_CHANGED_NEW_AREA", Changed)
end
