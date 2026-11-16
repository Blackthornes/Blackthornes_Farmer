-- Blackthornes Farmer -- UI/SavedFarms.lua
-- The Farms tab, the Save Farm box, the Last Farm strip on the Search tab
-- and Save This Farm on Your Run (Logic/SavedFarms.lua; the owner said
-- build it from a mockup, 2026-11-16). Only while "Saved Farms:" is ticked.
--
-- The tab, top to bottom: LAST FARM with Repeat, TODAY (farms ticked Every
-- Day or added today), SAVED FARMS with New Farm, and RECENT RUNS. Every
-- list is dark glass with sortable columns; right-click a farm for Start,
-- Edit, Add to Today and Remove. Drawn only while the tab shows, and again
-- when a farm, a run or a price moves (SavedFarms.version).

local _, ns = ...
local L = ns.L

local SavedFarmsUI = {}
ns.SavedFarmsUI = SavedFarmsUI

local Theme = ns.Theme
local Widgets = ns.Widgets
local Util = ns.Util

local PADDING = 14
local ROW = 22
local HEAD = 18      -- a section's heading line
local COLS = 18      -- a list's column headings
local GAP = 8
local CARD = 42      -- the Last Farm card
local FOOT = 36      -- kept free at the window's foot
local BUTTON_W = 58

SavedFarmsUI.ROW = ROW

local function Farms() return ns.SavedFarms end

local function Coins(copper)
    if not copper then return "--" end
    return ns.Value.Coins(math.floor(copper))
end

local function ButtonWidth(...)
    local widest = 0
    for _, text in ipairs({ ... }) do
        widest = math.max(widest, Theme.TextWidth("small", text) or 0)
    end
    return math.max(BUTTON_W, math.ceil(widest) + 20)
end

local function Tip(owner, lines)
    if not GameTooltip then return end
    GameTooltip:SetOwner(owner, "ANCHOR_TOP")
    for index, line in ipairs(lines) do
        if index == 1 and #lines > 1 then
            GameTooltip:AddLine(line, Theme.Unpack("accent"))
        else
            GameTooltip:AddLine(line, 1, 1, 1, true)
        end
    end
    GameTooltip:Show()
end

local function HideTip()
    if GameTooltip then GameTooltip:Hide() end
end

local function HoverTip(frame, lines)
    frame:HookScript("OnEnter", function(self) Tip(self, type(lines) == "function" and lines() or lines) end)
    frame:HookScript("OnLeave", HideTip)
end
SavedFarmsUI.HoverTip = HoverTip

-- The hovers, in the owner's approved words.
SavedFarmsUI.TIPS = {
    hour = L["About what this farm makes in an hour, from your own runs at today's prices. Before your first run it uses how fast you got the item before."],
    unknown = L["Farm it once to see."],
    start = L["Sets the goal, points the arrow to the spot and starts the timer if you use it."],
    again = L["Starts your last farm again, just like last time."],
    today = L["Farms you want to do today. A farm is done once you reach its goal. The list starts fresh each day."],
    daily = L["Puts this farm on your Today list each day."],
}

-- The four ways to run a farm, for the How: drop-down and its hover.
SavedFarmsUI.HOWS = {
    { value = "spot", text = L["Farm This Spot"], tip = L["the arrow takes you to the spot."] },
    { value = "route", text = L["Route Mode"], tip = L["runs a gather route here, for herbs, ore or leather."] },
    { value = "kills", text = L["Kill Goal"], tip = L["counts kills instead of an item."] },
    { value = "goal", text = L["Goal Only"], tip = L["sets the goal and nothing else."] },
}

--------------------------------------------------------------------------------
-- Cells
--------------------------------------------------------------------------------

--- A farm's name, in its item's rarity colour when it has one.
function SavedFarmsUI.FarmName(farm, dim)
    if type(farm) ~= "table" then return "" end
    if dim then return Util.Colored("dim", farm.name or "") end
    if farm.item then return Util.ColorItemOr("text", farm.item, nil, farm.name or farm.item) end
    return farm.name or ""
end

--- What the Goal column reads: Route, or how many.
function SavedFarmsUI.GoalText(farm)
    if farm.how == "route" and not farm.amount then return L["Route"] end
    return farm.amount and tostring(farm.amount) or "--"
end

local function ItemID(farm)
    return farm and farm.item and ns.Value and ns.Value:ItemID(farm.item) or nil
end

--------------------------------------------------------------------------------
-- A section: its heading, column headings and dark glass list
--------------------------------------------------------------------------------

-- Each list's columns, left to right: key, heading, width (0 shares what is
-- left), justify, and whether it sorts.
SavedFarmsUI.COLUMNS = {
    today = {
        { key = "check", w = 18 }, { key = "icon", w = 18 },
        { key = "farm", text = L["Farm"], w = 0, sort = true },
        { key = "where", text = L["Where"], w = 0, sort = true },
        { key = "goal", text = L["Goal"], w = 70, justify = "RIGHT", sort = true },
        { key = "hour", text = L["An Hour"], w = 96, justify = "RIGHT", sort = true },
        { key = "action", w = BUTTON_W + 12 },
    },
    saved = {
        { key = "icon", w = 18 },
        { key = "farm", text = L["Farm"], w = 0, sort = true },
        { key = "where", text = L["Where"], w = 0, sort = true },
        { key = "goal", text = L["Goal"], w = 70, justify = "RIGHT", sort = true },
        { key = "hour", text = L["An Hour"], w = 96, justify = "RIGHT", sort = true },
        { key = "last", text = L["Last Run"], w = 96, justify = "RIGHT", sort = true },
        { key = "action", w = BUTTON_W + 12 },
    },
    runs = {
        { key = "when", text = L["When"], w = 96, sort = true },
        { key = "farm", text = L["Farm"], w = 0, sort = true },
        { key = "time", text = L["Time"], w = 80, justify = "RIGHT", sort = true },
        { key = "got", text = L["Got"], w = 60, justify = "RIGHT", sort = true },
        { key = "gold", text = L["Gold"], w = 110, justify = "RIGHT", sort = true },
        { key = "hour", text = L["An Hour"], w = 110, justify = "RIGHT", sort = true },
    },
}

--- Left edges and widths for `columns` across `width`.
function SavedFarmsUI.Place(columns, width)
    local fixed, shares = 0, 0
    for _, column in ipairs(columns) do
        if column.w > 0 then fixed = fixed + column.w else shares = shares + 1 end
        fixed = fixed + 6
    end
    local share = shares > 0 and math.max(60, math.floor((width - fixed) / shares)) or 0
    local placed, x = {}, 0
    for _, column in ipairs(columns) do
        local w = column.w > 0 and column.w or share
        placed[column.key] = { x = x, w = w }
        x = x + w + 6
    end
    return placed
end

local function SortValue(kind, key, data)
    local Logic = Farms()
    if kind == "runs" then
        local run = data.run
        if key == "when" then return tonumber(run.at) or 0 end
        if key == "farm" then return (run.name or ""):lower() end
        if key == "time" then return tonumber(run.seconds) or 0 end
        if key == "got" then return tonumber(run.got) or 0 end
        if key == "gold" then return tonumber(run.copper) or 0 end
        if key == "hour" then return data.rate or -1 end
        return 0
    end
    local farm = data.farm
    if key == "farm" then return (farm.name or ""):lower() end
    if key == "where" then return (farm.zone or ""):lower() end
    if key == "goal" then return tonumber(farm.amount) or 0 end
    if key == "hour" then return data.hour or -1 end
    if key == "last" then
        local run = Logic:LastRunOf(farm.id)
        return run and tonumber(run.at) or 0
    end
    return 0
end

--- `rows` sorted by the section's column, or as they are with none.
function SavedFarmsUI.Sort(kind, rows, key, ascending)
    if not key then return rows end
    for index, data in ipairs(rows) do
        data.order = index
        data.sortValue = SortValue(kind, key, data)
    end
    table.sort(rows, function(a, b)
        if a.sortValue == b.sortValue then return a.order < b.order end
        if ascending then return a.sortValue < b.sortValue end
        return a.sortValue > b.sortValue
    end)
    return rows
end

function SavedFarmsUI:Section(kind, title, opts)
    opts = opts or {}
    local view = self.view
    local section = { kind = kind, columns = SavedFarmsUI.COLUMNS[kind] }

    section.title = Theme.CreateLabel(view, "small", "accent")
    section.title:SetText(title)

    section.headings = CreateFrame("Frame", nil, view)
    section.headings:SetHeight(COLS)
    local rule = section.headings:CreateTexture(nil, "BORDER")
    rule:SetPoint("BOTTOMLEFT")
    rule:SetPoint("BOTTOMRIGHT")
    rule:SetHeight(1)
    rule:SetColorTexture(Theme.Unpack("accent", 0.5))

    local labels, tips, startsLow = {}, {}, {}
    section.labels = {}
    for _, column in ipairs(section.columns) do
        if column.text then
            local label = Theme.CreateLabel(section.headings, "tiny", "dim", column.justify or "LEFT")
            label:SetText(column.text)
            section.labels[column.key] = label
            if column.sort then
                labels[column.key] = label
                tips[column.key] = column.key == "hour" and SavedFarmsUI.TIPS.hour or column.text
                if column.key == "farm" or column.key == "where" then startsLow[column.key] = true end
            end
        end
    end
    section.sorter = Widgets.SortableHeadings(labels, tips, function(key, ascending)
        section.sortKey, section.ascending = key, ascending
        SavedFarmsUI:Render()
    end, { startsLow = startsLow, key = opts.sortKey, ascending = opts.ascending })
    section.sortKey, section.ascending = opts.sortKey, opts.ascending and true or false

    section.list = Widgets.CreateRowList(view, {
        rowHeight = ROW,
        createRow = function(row) SavedFarmsUI:CreateRow(section, row) end,
        updateRow = function(row, data) SavedFarmsUI:UpdateRow(section, row, data) end,
        onClick = function(data, button) SavedFarmsUI:OnClick(section, data, button) end,
        onEnter = function(row, data) SavedFarmsUI:OnEnter(section, row, data) end,
        onLeave = HideTip,
        fadeKey = "window",
    })

    section.empty = Theme.CreateLabel(view, "small", "dim", "CENTER")
    section.empty:SetWordWrap(true)
    section.empty:SetText(opts.empty or "")
    section.empty:Hide()

    return section
end

function SavedFarmsUI:CreateRow(section, row)
    row.cells = {}
    -- False rather than nil: test frames answer a field never given.
    row.icon, row.check, row.button, row.done = false, false, false, false
    for _, column in ipairs(section.columns) do
        local key = column.key
        if key == "icon" then
            row.icon = Theme.CreateItemIcon(row, 16)
        elseif key == "check" then
            local box = CreateFrame("Frame", nil, row)
            box:SetSize(12, 12)
            box.fill = Theme.Fill(box, "well")
            Theme.Border(box, "metal")
            box.tick = box:CreateTexture(nil, "OVERLAY")
            box.tick:SetPoint("CENTER")
            box.tick:SetSize(7, 7)
            box.tick:SetColorTexture(Theme.Unpack("accentHi"))
            row.check = box
        elseif key == "action" then
            row.button = Widgets.CreateButton(row, L["Start"], function()
                SavedFarmsUI:Act(row.data)
            end, { primary = true, width = BUTTON_W, height = 16 })
            HoverTip(row.button, function()
                local farm = row.data and row.data.farm
                if farm and Farms().run and Farms().run.id == farm.id then return { L["Stop"] } end
                return { L["Start"], SavedFarmsUI.TIPS.start }
            end)
            row.done = Theme.CreateLabel(row, "small", "good", "RIGHT")
            row.done:SetText(L["Done"])
        else
            local size = (key == "farm" or key == "where") and "small" or "small"
            local label = Theme.CreateLabel(row, size, key == "where" and "muted" or "text", column.justify or "LEFT")
            label:SetWordWrap(false)
            row.cells[key] = label
        end
    end
    row.placedFor = nil
end

--- Put a row's cells where the section's columns are now.
function SavedFarmsUI:PlaceRow(section, row)
    local placed = section.placed
    if not placed or row.placedFor == section.placedVersion then return end
    row.placedFor = section.placedVersion
    for key, label in pairs(row.cells) do
        local column = placed[key]
        label:ClearAllPoints()
        label:SetPoint("LEFT", row, "LEFT", 6 + column.x, 0)
        label:SetWidth(column.w)
    end
    if row.icon and placed.icon then
        row.icon:ClearAllPoints()
        row.icon:SetPoint("LEFT", row, "LEFT", 6 + placed.icon.x, 0)
    end
    if row.check and placed.check then
        row.check:ClearAllPoints()
        row.check:SetPoint("LEFT", row, "LEFT", 8 + placed.check.x, 0)
    end
    if row.button and placed.action then
        row.button:ClearAllPoints()
        row.button:SetPoint("RIGHT", row, "RIGHT", -6, 0)
        row.done:ClearAllPoints()
        row.done:SetPoint("RIGHT", row, "RIGHT", -10, 0)
    end
end

function SavedFarmsUI:UpdateRow(section, row, data)
    self:PlaceRow(section, row)
    local Logic = Farms()
    if section.kind == "runs" then
        local run, farm = data.run, data.farm
        row.cells.when:SetText(Logic.When(run.at))
        row.cells.farm:SetText(farm and SavedFarmsUI.FarmName(farm) or (run.name or ""))
        row.cells.time:SetText(Logic.Duration(run.seconds))
        row.cells.got:SetText(tostring(run.got or 0))
        row.cells.gold:SetText(Coins(tonumber(run.copper) or 0))
        row.cells.hour:SetText(Coins(data.rate))
        return
    end

    local farm = data.farm
    local done = section.kind == "today" and Logic:DoneToday(farm)
    local running = Logic.run and Logic.run.id == farm.id
    Theme.SetItemIcon(row.icon, ItemID(farm))
    if row.icon then row.icon:SetAlpha(done and 0.5 or 1) end
    if row.check then row.check.tick:SetShown(done and true or false) end
    row.cells.farm:SetText(SavedFarmsUI.FarmName(farm, done))
    row.cells.where:SetText(farm.zone or "")
    row.cells.goal:SetText(SavedFarmsUI.GoalText(farm))
    row.cells.goal:SetTextColor(Theme.Unpack(done and "dim" or "text"))
    row.cells.hour:SetText(data.hour and Coins(data.hour) or Util.Colored("dim", "--"))
    if row.cells.last then
        local run = Logic:LastRunOf(farm.id)
        row.cells.last:SetText(Logic.When(run and run.at))
        row.cells.last:SetTextColor(Theme.Unpack("muted"))
    end
    row.done:SetShown(done and not running and true or false)
    row.button:SetShown(not done or running)
    row.button:SetText(running and L["Stop"] or L["Start"])
end

--- Start (or Stop) from a row's button.
function SavedFarmsUI:Act(data)
    local farm = data and data.farm
    if not farm then return end
    local Logic = Farms()
    if Logic.run and Logic.run.id == farm.id then
        Logic:End("stop")
    else
        Logic:Start(farm.id)
    end
    self:Render()
end

function SavedFarmsUI:OnClick(section, data, button)
    if button ~= "RightButton" then return end
    local farm = data and data.farm
    if farm then self:Menu(farm) end
end

--- The right-click menu: Start, Edit, Add to Today, Remove.
function SavedFarmsUI:Menu(farm)
    local Logic = Farms()
    if not (ns.RowMenu and farm) then return end
    local id = farm.id
    ns.RowMenu:Open({
        { text = L["Start"], run = function() Logic:Start(id) end },
        { text = L["Edit"], run = function() SavedFarmsUI:OpenBox(Logic:Find(id), id) end },
        { text = L["Add to Today"], checked = Logic:OnToday(farm),
            disabled = farm.daily and true or false, run = function() Logic:ToggleToday(id) end },
        { text = L["Remove"], run = function() Logic:Remove(id) end },
    }, { title = farm.name })
end

function SavedFarmsUI:OnEnter(section, row, data)
    if section.kind ~= "runs" and data.farm and not data.hour then
        Tip(row, { data.farm.name or "", SavedFarmsUI.TIPS.unknown })
    end
end

--------------------------------------------------------------------------------
-- The tab
--------------------------------------------------------------------------------

function SavedFarmsUI:Build(frame)
    if self.view then return self.view end
    local view = CreateFrame("Frame", nil, frame)
    view:SetAllPoints(frame)
    view:Hide()
    self.view = view
    self.frame = frame

    -- LAST FARM: the newest run and Repeat.
    self.lastTitle = Theme.CreateLabel(view, "small", "accent")
    self.lastTitle:SetText(L["LAST FARM"])

    local card = Theme.CreatePanel(view, "glassActive", "accent")
    card:SetHeight(CARD)
    if Theme.Halo then Theme.Halo(card, 4, 0.08) end
    self.card = card
    card.icon = Theme.CreateItemIcon(card, 20)
    card.icon:SetPoint("LEFT", 10, 0)
    card.top = Theme.CreateLabel(card, "small", "text")
    card.top:SetPoint("TOPLEFT", 38, -6)
    card.bottom = Theme.CreateLabel(card, "small", "muted")
    card.bottom:SetPoint("TOPLEFT", card.top, "BOTTOMLEFT", 0, -3)
    card.button = Widgets.CreateButton(card, L["Repeat"], function()
        Farms():Repeat()
        SavedFarmsUI:Render()
    end, { primary = true, width = ButtonWidth(L["Repeat"]), height = 20 })
    card.button:SetPoint("RIGHT", -10, 0)
    HoverTip(card.button, { L["Repeat"], SavedFarmsUI.TIPS.again })
    card.top:SetPoint("RIGHT", card.button, "LEFT", -10, 0)
    card.bottom:SetPoint("RIGHT", card.button, "LEFT", -10, 0)
    card.empty = Theme.CreateLabel(card, "small", "dim", "CENTER")
    card.empty:SetPoint("LEFT", 10, 0)
    card.empty:SetPoint("RIGHT", -10, 0)
    card.empty:SetText(L["Your runs show here once you finish one."])

    self.today = self:Section("today", L["TODAY"],
        { empty = L["Nothing on today's list. Tick Every Day on a farm, or right-click it and pick Add to Today."] })
    self.todayCount = Theme.CreateLabel(view, "small", "muted", "RIGHT")
    local todayHover = CreateFrame("Frame", nil, view)
    todayHover:SetPoint("TOPLEFT", self.today.title, "TOPLEFT", -2, 2)
    todayHover:SetPoint("BOTTOMRIGHT", self.today.title, "BOTTOMRIGHT", 2, -2)
    todayHover:EnableMouse(true)
    todayHover:SetScript("OnEnter", function(hover) Tip(hover, { L["TODAY"], SavedFarmsUI.TIPS.today }) end)
    todayHover:SetScript("OnLeave", HideTip)

    self.saved = self:Section("saved", L["SAVED FARMS"],
        { empty = L["No saved farms yet. Look up an item on the Search tab and press Save Farm."] })
    self.newButton = Widgets.CreateButton(view, L["New Farm"], function()
        SavedFarmsUI:OpenBox({})
    end, { width = ButtonWidth(L["New Farm"]), height = 18 })

    self.runs = self:Section("runs", L["RECENT RUNS"],
        { empty = L["Your runs show here once you finish one."], sortKey = "when", ascending = false })

    self.foot = Theme.CreateLabel(view, "tiny", "dim")
    self.foot:SetText(L["Right-click a farm to edit it, add it to today or remove it."])
    return view
end

--- How many rows each list shows: today and runs as many as they have, a
--- few at most, and saved farms whatever is left.
function SavedFarmsUI.Heights(height, todayCount, runCount)
    local top = (ns.UI and ns.UI.HEAD_TOP or 26) + 22 + CARD + GAP
    local block = HEAD + COLS
    local todayRows = math.max(1, math.min(todayCount, 4))
    local runRows = math.max(1, math.min(runCount, 4))
    local used = top + 3 * block + (todayRows + runRows) * ROW + 3 * GAP + FOOT
    local savedRows = math.max(3, math.floor((height - used) / ROW))
    return todayRows, savedRows, runRows
end

function SavedFarmsUI:Lay(section, y, rows, width)
    local view = self.view
    section.title:ClearAllPoints()
    section.title:SetPoint("TOPLEFT", view, "TOPLEFT", PADDING, -y)
    y = y + HEAD
    section.headings:ClearAllPoints()
    section.headings:SetPoint("TOPLEFT", view, "TOPLEFT", PADDING, -y)
    section.headings:SetPoint("TOPRIGHT", view, "TOPRIGHT", -PADDING, -y)
    y = y + COLS
    section.list:ClearAllPoints()
    section.list:SetPoint("TOPLEFT", view, "TOPLEFT", PADDING, -y)
    section.list:SetPoint("TOPRIGHT", view, "TOPRIGHT", -PADDING, -y)
    section.list:SetHeight(rows * ROW)
    section.empty:ClearAllPoints()
    section.empty:SetPoint("TOPLEFT", view, "TOPLEFT", PADDING, -y)
    section.empty:SetPoint("TOPRIGHT", view, "TOPRIGHT", -PADDING, -y)
    section.empty:SetHeight(rows * ROW)

    -- The rows stop at the list's scrollbar.
    local rowWidth = width - 2 * PADDING - 20
    local key = math.floor(rowWidth)
    if section.placedWidth ~= key then
        section.placedWidth = key
        section.placed = SavedFarmsUI.Place(section.columns, rowWidth - 12)
        section.placedVersion = (section.placedVersion or 0) + 1
        for columnKey, label in pairs(section.labels) do
            local column = section.placed[columnKey]
            label:ClearAllPoints()
            label:SetPoint("LEFT", section.headings, "LEFT", 6 + column.x, 0)
            label:SetWidth(column.w)
        end
    end
    return y + rows * ROW + GAP
end

local function ViewSize(view)
    local width = view:GetWidth()
    local height = view:GetHeight()
    if type(width) ~= "number" or width <= 0 then width = ns.UI and ns.UI.WindowWidth and ns.UI:WindowWidth() or 980 end
    if type(height) ~= "number" or height <= 0 then height = ns.UI and ns.UI.WindowHeight and ns.UI:WindowHeight() or 620 end
    return width, height
end

--- The lists' rows, worked out from the saved farms and runs.
function SavedFarmsUI:Data()
    local Logic = Farms()
    local today = {}
    local list, done = Logic:TodayList()
    for _, farm in ipairs(list) do today[#today + 1] = { farm = farm, hour = (Logic:AnHour(farm)) } end
    local saved = {}
    for _, farm in ipairs(Logic:List()) do saved[#saved + 1] = { farm = farm, hour = (Logic:AnHour(farm)) } end
    local runs = {}
    for _, run in ipairs(Logic:Runs()) do
        if type(run) == "table" then
            local farm = Logic:Find(run.id)
            runs[#runs + 1] = { run = run, farm = farm,
                rate = Logic.RunRate(run, farm and farm.how ~= "kills" and farm.item or nil) }
        end
    end
    return today, saved, runs, done, #list
end

--- The Last Farm card's two lines, or nil with no run yet.
function SavedFarmsUI.LastLines(last)
    if not last then return nil end
    local farm, run = last.farm, last.run
    local name = farm.item and Util.ColorItemOr("accent", farm.item, nil, farm.name) or Util.Colored("accent", farm.name)
    local top = farm.zone and L.Format("%s in %s", name, farm.zone) or name
    local what = farm.how == "kills" and farm.name or (farm.item or farm.name)
    local bottom = L.Format("%s. %s, %d %s, %s in all.", Farms().When(run.at), Farms().Duration(run.seconds),
        tonumber(run.got) or 0, what, Coins(tonumber(run.copper) or 0))
    return top, bottom
end

function SavedFarmsUI:Render()
    if not self.view or not self.view:IsShown() then return end
    local Logic = Farms()
    local view = self.view
    local width, height = ViewSize(view)
    local headTop = ns.UI and ns.UI.HEAD_TOP or 26
    local headLeft = ns.UI and ns.UI.HEAD_LEFT or 58

    -- LAST FARM
    self.lastTitle:ClearAllPoints()
    self.lastTitle:SetPoint("TOPLEFT", view, "TOPLEFT", headLeft, -(headTop + 2))
    self.card:ClearAllPoints()
    self.card:SetPoint("TOPLEFT", view, "TOPLEFT", headLeft, -(headTop + 20))
    self.card:SetPoint("TOPRIGHT", view, "TOPRIGHT", -PADDING, -(headTop + 20))
    local last = Logic:LastFarm()
    local top, bottom = SavedFarmsUI.LastLines(last)
    local card = self.card
    card.top:SetShown(top ~= nil)
    card.bottom:SetShown(top ~= nil)
    card.button:SetShown(top ~= nil)
    card.empty:SetShown(top == nil)
    if top then
        card.top:SetText(top)
        card.bottom:SetText(bottom)
        Theme.SetItemIcon(card.icon, ItemID(last.farm))
    else
        card.icon:Hide()
    end

    local today, saved, runs, done, todayTotal = self:Data()
    today = SavedFarmsUI.Sort("today", today, self.today.sortKey, self.today.ascending)
    saved = SavedFarmsUI.Sort("saved", saved, self.saved.sortKey, self.saved.ascending)
    runs = SavedFarmsUI.Sort("runs", runs, self.runs.sortKey, self.runs.ascending)

    local todayRows, savedRows, runRows = SavedFarmsUI.Heights(height, #today, #runs)
    local y = headTop + 22 + CARD + GAP
    y = self:Lay(self.today, y, todayRows, width)
    y = self:Lay(self.saved, y, savedRows, width)
    self:Lay(self.runs, y, runRows, width)

    self.todayCount:ClearAllPoints()
    self.todayCount:SetPoint("RIGHT", self.today.headings, "TOPRIGHT", -6, HEAD / 2 + 1)
    self.todayCount:SetText(todayTotal > 0 and L.Format("%d of %d done today.", done, todayTotal) or "")
    self.newButton:ClearAllPoints()
    self.newButton:SetPoint("BOTTOMRIGHT", self.saved.headings, "TOPRIGHT", 0, 2)

    for _, pair in ipairs({ { self.today, today }, { self.saved, saved }, { self.runs, runs } }) do
        local section, data = pair[1], pair[2]
        section.list:SetShown(#data > 0)
        section.headings:SetShown(#data > 0)
        section.empty:SetShown(#data == 0)
        section.list:SetData(data, true)
    end

    self.foot:ClearAllPoints()
    self.foot:SetPoint("BOTTOMLEFT", view, "BOTTOMLEFT", PADDING, 12)
    self.drawn = Logic.version
end

--- A farm, a run or today's list moved: redraw what shows.
function SavedFarmsUI:Changed()
    if self.view and self.view:IsShown() then self:Render() end
    self:PlaceSearchStrip()
end

--------------------------------------------------------------------------------
-- The Save Farm box
--------------------------------------------------------------------------------

local BOX_W = 420
local LABEL_W = 100

--- The Where: choices for `item`: each spot the data knows, best first.
function SavedFarmsUI.WhereOptions(item)
    local options = {}
    local found = type(item) == "string" and ns.DB and ns.DB:GetItem(item)
    if found and found.sources then
        local sorted = ns.Search and ns.Search.SortedSources and ns.Search:SortedSources(found) or found.sources
        for _, source in ipairs(sorted) do
            if source.zone then
                local zone = ns.Spots and ns.Spots.Show and ns.Spots.Show(source.zone) or source.zone
                options[#options + 1] = {
                    text = source.name and (zone .. ", " .. source.name) or zone,
                    value = #options + 1, zone = zone, mob = source.name,
                }
            end
            if #options >= 30 then break end
        end
    end
    return options
end

function SavedFarmsUI:BuildBox()
    if self.box then return self.box end
    local frame = CreateFrame("Frame", "BlackthornesFarmerSaveFarm", UIParent)
    frame:SetSize(BOX_W, 290)
    frame:SetPoint("CENTER", 0, 80)
    frame:SetFrameStrata("DIALOG")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(f) f:StartMoving() end)
    frame:SetScript("OnDragStop", function(f) f:StopMovingOrSizing() end)
    frame:Hide()

    Theme.Fill(frame, "window")
    if ns.Titanforged then
        ns.Titanforged:Dress(frame, { title = L["SAVE FARM"], close = function() SavedFarmsUI:CloseBox() end })
    else
        Theme.Border(frame, "borderLit")
    end
    if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, "BlackthornesFarmerSaveFarm") end

    local y = 40
    local function Line(text, tall)
        local line = CreateFrame("Frame", nil, frame)
        line:SetPoint("TOPLEFT", PADDING, -y)
        line:SetPoint("TOPRIGHT", -PADDING, -y)
        line:SetHeight(tall or 30)
        local rule = line:CreateTexture(nil, "BORDER")
        rule:SetPoint("BOTTOMLEFT")
        rule:SetPoint("BOTTOMRIGHT")
        rule:SetHeight(1)
        rule:SetColorTexture(Theme.Unpack("border", 0.6))
        line.label = Theme.CreateLabel(line, "small", "text")
        line.label:SetPoint("LEFT", 4, 0)
        line.label:SetWidth(LABEL_W - 8)
        line.label:SetText(text)
        y = y + (tall or 30)
        return line
    end
    local controlW = BOX_W - 2 * PADDING - LABEL_W - 4

    local nameLine = Line(L["Name:"])
    frame.name = Widgets.CreateSearchBox(nameLine, "", nil, nil, { plain = true })
    frame.name:SetPoint("LEFT", LABEL_W, 0)
    frame.name:SetPoint("RIGHT", -4, 0)

    local itemLine = Line(L["Item:"])
    frame.item = Widgets.CreateSearchBox(itemLine, "", function(text)
        SavedFarmsUI:ItemTyped(text)
    end, nil, { plain = true })
    frame.item:SetPoint("LEFT", LABEL_W, 0)
    frame.item:SetPoint("RIGHT", -4, 0)

    local whereLine = Line(L["Where:"])
    frame.where = Widgets.CreateDropdown(whereLine, {}, function() end, { width = controlW })
    frame.where:SetPoint("LEFT", LABEL_W, 0)

    local amountLine = Line(L["How Many:"])
    frame.amount = Widgets.CreateSearchBox(amountLine, "", nil, nil, { plain = true })
    frame.amount:SetPoint("LEFT", LABEL_W, 0)
    frame.amount:SetWidth(70)

    local howLine = Line(L["How:"])
    local hows = {}
    for _, how in ipairs(SavedFarmsUI.HOWS) do hows[#hows + 1] = { text = how.text, value = how.value } end
    frame.how = Widgets.CreateDropdown(howLine, hows, function() end, { width = controlW })
    frame.how:SetPoint("LEFT", LABEL_W, 0)
    HoverTip(howLine, function()
        local lines = { L["How:"] }
        for _, how in ipairs(SavedFarmsUI.HOWS) do lines[#lines + 1] = how.text .. ": " .. how.tip end
        return lines
    end)
    howLine:EnableMouse(true)

    local dailyLine = Line(L["Every Day:"])
    frame.daily = Widgets.CreateCheckbox(dailyLine, "", nil, true)
    frame.daily:SetPoint("LEFT", LABEL_W, 0)
    HoverTip(dailyLine, { L["Every Day:"], SavedFarmsUI.TIPS.daily })
    dailyLine:EnableMouse(true)

    local confirm = Widgets.CreateButton(frame, L["Confirm"], function() SavedFarmsUI:ConfirmBox() end,
        { primary = true, width = ButtonWidth(L["Confirm"], L["Cancel"]) + 10 })
    confirm:SetPoint("TOPRIGHT", -PADDING, -(y + 12))
    local cancel = Widgets.CreateButton(frame, L["Cancel"], function() SavedFarmsUI:CloseBox() end,
        { width = ButtonWidth(L["Confirm"], L["Cancel"]) + 10 })
    cancel:SetPoint("RIGHT", confirm, "LEFT", -8, 0)

    frame.note = Theme.CreateLabel(frame, "small", "loss")
    frame.note:SetPoint("TOPLEFT", PADDING, -(y + 14))
    frame.note:SetPoint("RIGHT", cancel, "LEFT", -8, 0)
    frame.note:SetWordWrap(true)

    frame:SetHeight(y + 12 + 22 + PADDING + 4)
    if ns.SharedWindow and ns.SharedWindow.KeepSpot then ns.SharedWindow.KeepSpot(frame, "farmer.savefarm") end
    self.box = frame
    return frame
end

--- The item typed changed: the Where: choices follow it.
function SavedFarmsUI:ItemTyped(text, keep)
    local box = self.box
    if not box then return end
    local options = SavedFarmsUI.WhereOptions(text)
    box.whereChoices = options
    if #options == 0 then
        box.where:SetOptions({ { text = "--", value = 0 } })
        box.where:SetValue(0)
        return
    end
    box.where:SetOptions(options)
    local pick = 1
    if keep then
        for index, option in ipairs(options) do
            if option.zone == keep.zone and (keep.mob == nil or option.mob == keep.mob) then pick = index end
        end
    end
    box.where:SetValue(pick)
end

--- Open the box, filled from `farm` (any fields known). `editID` edits
--- that saved farm instead of saving a new one.
function SavedFarmsUI:OpenBox(farm, editID)
    local Logic = Farms()
    if not Logic.On() then
        ns.PrintRaw(("|c%sBlackthornes Farmer:|r %s"):format(ns.COLORS.accent, L["Turn on Saved Farms in Settings first."]))
        return false
    end
    farm = farm or {}
    local box = self:BuildBox()
    self.editID = editID
    self.boxPage = farm.page
    self.boxZone = farm.zone
    box.note:SetText("")
    box.name:SetText(farm.name or farm.item or "")
    box.item:SetText(farm.item or "")
    self:ItemTyped(farm.item, farm)
    if (not box.whereChoices or #box.whereChoices == 0) and farm.zone then
        box.where:SetOptions({ { text = farm.mob and (farm.zone .. ", " .. farm.mob) or farm.zone, value = 0 } })
        box.where:SetValue(0)
    end
    box.amount:SetText(farm.amount and tostring(farm.amount) or "")
    box.how:SetValue(farm.how or Logic.DefaultHow(farm.item))
    box.daily:SetChecked(editID and farm.daily and true or (not editID))
    box:Show()
    return true
end

function SavedFarmsUI:CloseBox()
    if self.box then self.box:Hide() end
    self.editID = nil
end

--- What the box holds, as fields for SavedFarms:Save.
function SavedFarmsUI:BoxFields()
    local box = self.box
    local fields = {
        name = box.name:GetText(), item = box.item:GetText(), amount = box.amount:GetText(),
        how = box.how:GetValue(), daily = box.daily.checked, page = self.boxPage,
    }
    local value = box.where:GetValue()
    local choice = box.whereChoices and box.whereChoices[value]
    if choice then
        fields.zone, fields.mob = choice.zone, choice.mob
    elseif self.boxZone then
        fields.zone = self.boxZone
    end
    return fields
end

function SavedFarmsUI:ConfirmBox()
    local Logic = Farms()
    local fields = self:BoxFields()
    local farm, why
    if self.editID then
        farm, why = Logic:Edit(self.editID, fields)
    else
        farm, why = Logic:Save(fields)
    end
    if not farm then
        if why then self.box.note:SetText(why:sub(1, 1):upper() .. why:sub(2) .. ".") end
        return false
    end
    self:CloseBox()
    self:Render()
    return true
end

--- Save Farm on a Search tab item heading: the box, filled from the item.
function SavedFarmsUI:SaveItem(name)
    local Goals = ns.Goals
    local best = Goals and Goals:BestSpot(name)
    local goal = Goals and Goals:Find(name)
    return self:OpenBox({
        name = name, item = name, zone = best and best.zone, mob = best and best.name,
        amount = goal and goal.target or ns.SavedFarms.DEFAULT_AMOUNT,
        how = ns.SavedFarms.DefaultHow(name),
    })
end

--- Save This Farm on Your Run: the box, filled from the goal you follow.
function SavedFarmsUI:SaveRun()
    local goal = ns.Arrow and ns.Arrow.Goal and ns.Arrow:Goal()
    if goal and goal.item then return self:SaveItem(goal.item) end
    return self:OpenBox({})
end

--- Save Farm in Route Mode: a route farm on that Grind page.
function SavedFarmsUI:SaveRoute(gives, zone)
    local names = { herbs = L["Herbs"], ore = L["Ore"], skinning = L["Leather"] }
    return self:OpenBox({ name = names[gives], how = "route", page = gives, zone = zone })
end

--------------------------------------------------------------------------------
-- The Last Farm strip on the Search tab
--------------------------------------------------------------------------------

SavedFarmsUI.STRIP = 30

function SavedFarmsUI:BuildSearchStrip()
    local main = ns.UI
    if self.strip or not (main and main.searchView and main.filters) then return self.strip end
    local strip = Theme.CreatePanel(main.searchView, "glassActive", "accent")
    strip:SetHeight(SavedFarmsUI.STRIP - 6)
    strip:SetPoint("TOPLEFT", main.filters, "BOTTOMLEFT", 0, -6)
    strip:SetPoint("TOPRIGHT", main.filters, "BOTTOMRIGHT", 0, -6)
    strip.icon = Theme.CreateItemIcon(strip, 16)
    strip.icon:SetPoint("LEFT", 8, 0)
    strip.all = Widgets.CreateButton(strip, L["All Farms"], function()
        if ns.UI then ns.UI:ShowTab("farms") end
    end, { width = ButtonWidth(L["All Farms"]), height = 18 })
    strip.all:SetPoint("RIGHT", -6, 0)
    strip.again = Widgets.CreateButton(strip, L["Repeat"], function()
        Farms():Repeat()
    end, { primary = true, width = ButtonWidth(L["Repeat"]), height = 18 })
    strip.again:SetPoint("RIGHT", strip.all, "LEFT", -6, 0)
    HoverTip(strip.again, { L["Repeat"], SavedFarmsUI.TIPS.again })
    strip.text = Theme.CreateLabel(strip, "small", "text")
    strip.text:SetPoint("LEFT", 30, 0)
    strip.text:SetPoint("RIGHT", strip.again, "LEFT", -8, 0)
    strip.text:SetWordWrap(false)
    strip:Hide()
    self.strip = strip
    return strip
end

--- The strip's line, or nil with no last farm.
function SavedFarmsUI.StripText(last)
    if not last then return nil end
    local farm, run = last.farm, last.run
    local name = farm.item and Util.ColorItemOr("accent", farm.item, nil, farm.name) or Util.Colored("accent", farm.name)
    return L.Format("Last farm: %s, %s, %s", name, Farms().Duration(run.seconds), Coins(tonumber(run.copper) or 0))
end

--- Show the strip over the Search results (and make room for it) while
--- Saved Farms and Last Farm on Search are on and there is a last farm.
function SavedFarmsUI:PlaceSearchStrip()
    local main = ns.UI
    if not (main and main.panel and main.filters) then return end
    local last = Farms().LastOnSearch() and Farms():LastFarm()
    local text = SavedFarmsUI.StripText(last)
    local strip = text and self:BuildSearchStrip() or self.strip
    if strip then
        strip:SetShown(text ~= nil)
        if text then
            strip.text:SetText(text)
            Theme.SetItemIcon(strip.icon, ItemID(last.farm))
        end
    end
    local shown = text ~= nil
    if self.stripShown == shown then return end
    self.stripShown = shown
    main.panel:ClearAllPoints()
    main.panel:SetPoint("TOPLEFT", main.filters, "BOTTOMLEFT", 0, -8 - (shown and SavedFarmsUI.STRIP or 0))
    main.panel:SetPoint("BOTTOMRIGHT", main.searchView, "BOTTOMRIGHT", -PADDING, 36)
    if main.list and main.list.Refresh then pcall(main.list.Refresh, main.list) end
end

--------------------------------------------------------------------------------
-- Save This Farm on Your Run
--------------------------------------------------------------------------------

--- Show the button on the Your Run card while Saved Farms is on and no
--- saved farm was the run.
function SavedFarmsUI:DressRecap()
    local Recap = ns.RecapUI
    local frame = Recap and Recap.frame
    if not frame then return end
    if not rawget(frame, "saveFarm") then
        frame.saveFarm = Widgets.CreateButton(frame, L["Save This Farm"], function()
            SavedFarmsUI:SaveRun()
        end, { primary = true, width = ButtonWidth(L["Save This Farm"]), height = 18 })
    end
    local show = Farms().On() and not Farms().justEnded
    frame.saveFarm:SetShown(show and true or false)
    if show then
        frame.saveFarm:ClearAllPoints()
        frame.saveFarm:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", PADDING, 10)
        -- Show sets the card's height afresh each time; room for the button.
        local height = frame:GetHeight()
        if type(height) == "number" then frame:SetHeight(height + 26) end
    end
end

if ns.RecapUI and ns.RecapUI.Show then
    local show = ns.RecapUI.Show
    ns.RecapUI.Show = function(recap, ...)
        local result = show(recap, ...)
        pcall(SavedFarmsUI.DressRecap, SavedFarmsUI)
        return result
    end
end
