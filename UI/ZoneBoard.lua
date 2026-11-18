local ADDON, ns = ...
local L = ns.L

-- The Zone Board window (Logic/ZoneBoard.lua; the owner said build it from
-- a mockup whose words he approved, 2026-11-18). Its own small window, not
-- part of Kills & Loot: FINISH and BEST tabs, the house frame, dark glass
-- rows. Opens from /farm zone, Shift-click on Farmer's minimap button (or
-- its row in the shared menu) and the Zone Board button on Kills & Loot,
-- only while "Zone Board:" is ticked. Its spot is kept by
-- SharedWindow.KeepSpot as "farmer.zoneboard", its size as zoneBoardScale.
--
-- Smooth play: a redraw only when something moved (a tab, a scan, a 20th
-- kill, the zone); a kill sets one row's count; distances are read once a
-- second for the rows on screen while it shows, and the rows re-sort by
-- distance at most every RESORT seconds, never in a fight.

local ZoneBoardUI = ns.NewModule("ZoneBoardUI")
ns.ZoneBoardUI = ZoneBoardUI

ZoneBoardUI.WIDTH = 340
ZoneBoardUI.PAD = 8
ZoneBoardUI.ROW_H = 36
ZoneBoardUI.ROWS = 6
ZoneBoardUI.HEAD_H = 56
ZoneBoardUI.TICK_H = 24
ZoneBoardUI.BUTTON_H = 24
ZoneBoardUI.BAR_W = 84
ZoneBoardUI.DOTS = 28
ZoneBoardUI.LOOK = 1          -- seconds between distance reads while open
ZoneBoardUI.RESORT = 5        -- seconds between re-sorts by distance
ZoneBoardUI.SPOT_KEY = "farmer.zoneboard"
ZoneBoardUI.ORANGE = { 1, 0.5, 0.25 }

local Theme, Widgets, Util = ns.Theme, ns.Widgets, ns.Util

local function Board() return ns.ZoneBoard end

local function Fighting()
    return type(InCombatLockdown) == "function" and InCombatLockdown() and true or false
end

--- Colour a label by a key, "orange" for a mob well above you.
function ZoneBoardUI.Paint(label, key)
    if key == "orange" then
        local c = ZoneBoardUI.ORANGE
        label:SetTextColor(c[1], c[2], c[3])
    else
        label:SetTextColor(Theme.Unpack(key or "text"))
    end
end

--- "17/20".
function ZoneBoardUI.Count(kills)
    local need = ns.Tracker.MIN_KILLS
    return ("%d/%d"):format(math.min(kills or 0, need), need)
end

--- A progress bar: a dark well and a gold fill.
function ZoneBoardUI.Bar(parent, width)
    local bar = CreateFrame("Frame", nil, parent)
    bar:SetSize(width, 6)
    local well = bar:CreateTexture(nil, "BACKGROUND")
    well:SetAllPoints()
    well:SetColorTexture(Theme.Unpack("well"))
    bar.fill = bar:CreateTexture(nil, "ARTWORK")
    bar.fill:SetPoint("TOPLEFT")
    bar.fill:SetPoint("BOTTOMLEFT")
    bar.fill:SetColorTexture(Theme.Unpack("accentHi"))
    bar.width = width
    function bar:SetShare(share)
        share = math.max(0, math.min(1, share or 0))
        self.fill:SetWidth(math.max(1, self.width * share))
        self.fill:SetShown(share > 0)
    end
    return bar
end

--- The small gold ALMOST tag.
function ZoneBoardUI.Tag(parent)
    local tag = CreateFrame("Frame", nil, parent)
    tag:SetHeight(12)
    Theme.Fill(tag, "accent", 0.25)
    Theme.Border(tag, "accent", 0.8)
    tag.label = Theme.CreateLabel(tag, "tiny", "accentHi")
    tag.label:SetPoint("CENTER")
    tag.label:SetText(L["ALMOST"])
    tag:SetWidth(Theme.TextWidth("tiny", L["ALMOST"]) + 10)
    tag:Hide()
    return tag
end

--------------------------------------------------------------------------------
-- Building
--------------------------------------------------------------------------------

local function Glass(row)
    row.stripe = row:CreateTexture(nil, "BACKGROUND")
    row.stripe:SetAllPoints()
    row.line = row:CreateTexture(nil, "BORDER")
    row.line:SetPoint("BOTTOMLEFT")
    row.line:SetPoint("BOTTOMRIGHT")
    row.line:SetHeight(1)
    row.line:SetColorTexture(Theme.Unpack("border", 0.6))
    row.edge = row:CreateTexture(nil, "ARTWORK")
    row.edge:SetPoint("TOPLEFT")
    row.edge:SetPoint("BOTTOMLEFT")
    row.edge:SetWidth(3)
    row.edge:SetColorTexture(Theme.Unpack("accentHi"))
    row.edge:Hide()
end

--- Dark glass by place; glassActive and a gold left edge when picked,
--- glassHover with a gold edge under the mouse.
function ZoneBoardUI.Stripe(row)
    local key
    if row.picked then key = "glassActive"
    elseif row.hover then key = "glassHover"
    else key = row.index % 2 == 1 and "glass" or "glassAlt" end
    row.stripe:SetColorTexture(Theme.Unpack(key))
    row.edge:SetShown((row.picked or row.hover) and true or false)
    row.edge:SetAlpha(row.picked and 1 or 0.6)
end

function ZoneBoardUI:MakeRow(index)
    local frame = self.body
    local row = CreateFrame("Button", nil, frame)
    row.index = index
    row:SetHeight(self.ROW_H)
    Glass(row)

    row.rank = Theme.CreateLabel(row, "normal", "muted", "CENTER")
    row.rank:SetPoint("LEFT", 2, 0)
    row.rank:SetWidth(26)
    row.icon = Theme.CreateItemIcon(row, 20)
    row.icon:SetPoint("LEFT", 30, 0)
    row.mystery = Theme.CreateLabel(row, "normal", "accent", "CENTER")
    row.mystery:SetPoint("CENTER", row.icon, "CENTER")
    row.mystery:SetText("?")

    row.right = Theme.CreateLabel(row, "small", "muted", "RIGHT")
    row.right:SetPoint("RIGHT", -6, 0)
    row.right:SetWidth(64)
    row.bar = ZoneBoardUI.Bar(row, self.BAR_W)
    row.bar:SetPoint("RIGHT", row.right, "LEFT", -6, 4)
    row.count = Theme.CreateLabel(row, "tiny", "muted", "RIGHT")
    row.count:SetPoint("TOPRIGHT", row.bar, "BOTTOMRIGHT", 0, -2)

    row.name = Theme.CreateLabel(row, "small", "text")
    row.name:SetPoint("TOPLEFT", 30, -5)
    row.name:SetPoint("RIGHT", row.bar, "LEFT", -6, 0)
    row.name:SetWordWrap(false)
    row.sub = Theme.CreateLabel(row, "tiny", "muted")
    row.sub:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -2)
    row.sub:SetPoint("RIGHT", row.bar, "LEFT", -6, 0)
    row.sub:SetWordWrap(false)
    row.tag = ZoneBoardUI.Tag(row)
    row.tag:SetPoint("LEFT", row.sub, "LEFT", 0, 0)

    row:SetScript("OnClick", function(self)
        if self.data then ZoneBoardUI:Pick(self.data.name) end
    end)
    row:SetScript("OnDoubleClick", function(self)
        if self.data then ZoneBoardUI:Pick(self.data.name); ZoneBoardUI:Go() end
    end)
    row:SetScript("OnEnter", function(self) self.hover = true; ZoneBoardUI.Stripe(self) end)
    row:SetScript("OnLeave", function(self) self.hover = nil; ZoneBoardUI.Stripe(self) end)
    row:Hide()
    self.rows[index] = row
    return row
end

--- The ring of gold dots round "9/14": lit as far as the zone is done.
function ZoneBoardUI:MakeRing(parent)
    local ring = CreateFrame("Frame", nil, parent)
    ring:SetSize(48, 48)
    ring.dots = {}
    local count, radius = self.DOTS, 21
    for i = 1, count do
        local angle = math.pi / 2 - (i - 1) / count * 2 * math.pi
        local dot = ring:CreateTexture(nil, "ARTWORK")
        dot:SetSize(5, 5)
        dot:SetTexture(([[Interface\AddOns\%s\Media\Frame\HeatDot]]):format(ADDON))
        dot:SetPoint("CENTER", ring, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
        ring.dots[i] = dot
    end
    ring.text = Theme.CreateLabel(ring, "small", "text", "CENTER")
    ring.text:SetPoint("CENTER")
    function ring:SetShare(done, total)
        local lit = total > 0 and math.floor(count * done / total + 0.5) or 0
        for i, dot in ipairs(self.dots) do
            if i <= lit then dot:SetVertexColor(Theme.Unpack("accentHi"))
            else dot:SetVertexColor(Theme.Unpack("border")) end
        end
        self.text:SetText(("%d/%d"):format(done, total))
    end
    return ring
end

function ZoneBoardUI:Build()
    if self.frame then return self.frame end
    local name = "BlackthornesFarmerZoneBoard"
    local frame = CreateFrame("Frame", name, UIParent)
    frame:SetSize(self.WIDTH, 420)
    frame:SetPoint("CENTER", -320, 60)
    frame:SetFrameStrata("MEDIUM")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:EnableMouseWheel(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:Hide()
    if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, name) end
    self.frame = frame
    self.rows = {}
    self.picks = {}
    self.offset = 0

    Theme.Fill(frame, "window")
    if ns.Titanforged then
        self.trim = ns.Titanforged:Dress(frame, { title = L["ZONE BOARD"], close = function() ZoneBoardUI:Hide() end })
        local left, right, top, bottom = ns.Titanforged.Reach(self.trim)
        if frame.SetClampRectInsets then pcall(frame.SetClampRectInsets, frame, -left, right, top, -bottom) end
    else
        Theme.Border(frame, "borderLit")
    end
    frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    Widgets.ApplySize(frame, ns.db and ns.db.zoneBoardScale)
    frame.sizeGrip = Widgets.CreateSizeGrip(frame, {
        below = self.trim and select(4, ns.Titanforged.Reach(self.trim)) or 0,
        get = function() return ns.db and ns.db.zoneBoardScale end,
        save = function(percent) if ns.db then ns.db.zoneBoardScale = percent end end,
    })

    local pad = self.PAD
    self.tabs = Widgets.CreateTabStrip(frame, {
        { key = "finish", text = L["FINISH"] },
        { key = "best", text = L["BEST"] },
    }, function(key)
        Board():SetTab(key)
        ZoneBoardUI.offset = 0
        ZoneBoardUI:Draw()
    end, { width = self.WIDTH - pad * 2 })
    self.tabs:SetPoint("TOPLEFT", pad, -pad)
    self.tabs:SetPoint("TOPRIGHT", -pad, -pad)

    -- FINISH's head: the ring and the counts.
    local head = CreateFrame("Frame", nil, frame)
    head:SetHeight(self.HEAD_H)
    head:SetPoint("TOPLEFT", pad, -pad - 34)
    head:SetPoint("TOPRIGHT", -pad, -pad - 34)
    self.head = head
    self.ring = self:MakeRing(head)
    self.ring:SetPoint("LEFT", 4, 0)
    self.headline = Theme.CreateLabel(head, "normal", "text")
    self.headline:SetPoint("TOPLEFT", self.ring, "TOPRIGHT", 12, -6)
    self.headline:SetPoint("RIGHT", head, "RIGHT", -4, 0)
    self.headsub = Theme.CreateLabel(head, "tiny", "muted")
    self.headsub:SetPoint("TOPLEFT", self.headline, "BOTTOMLEFT", 0, -4)
    self.headsub:SetPoint("RIGHT", head, "RIGHT", -4, 0)
    self.headsub:SetWordWrap(true)

    -- FINISH's ticks.
    local ticks = CreateFrame("Frame", nil, frame)
    ticks:SetHeight(self.TICK_H)
    self.ticks = ticks
    self.near = Widgets.CreateCheckbox(ticks, L["Near Me First:"], function(on)
        Board():SetNearFirst(on)
    end, true)
    self.near:SetPoint("LEFT", 2, 0)
    if self.near.HookScript then
        self.near:HookScript("OnEnter", function(box)
            if not GameTooltip then return end
            GameTooltip:SetOwner(box, "ANCHOR_RIGHT")
            GameTooltip:AddLine(L["Near Me First:"])
            GameTooltip:AddLine(L["Puts the closest mobs at the top. Untick it to put the ones you're closest to finishing first."], 1, 1, 1, true)
            GameTooltip:Show()
        end)
        self.near:HookScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    end
    self.showDone = Widgets.CreateCheckbox(ticks, L["Show Finished:"], function(on)
        Board():SetShowDone(on)
    end, false)
    self.showDone:SetPoint("LEFT", ticks, "LEFT", 150, 0)

    self.body = CreateFrame("Frame", nil, frame)
    for index = 1, self.ROWS do self:MakeRow(index) end
    self.empty = Theme.CreateLabel(self.body, "small", "muted", "CENTER")
    self.empty:SetPoint("TOPLEFT", 8, -20)
    self.empty:SetPoint("TOPRIGHT", -8, -20)
    self.empty:SetWordWrap(true)

    self.go = Widgets.CreateButton(frame, L["Take Me There"], function() ZoneBoardUI:Go() end,
        { primary = true, height = self.BUTTON_H })
    self.skip = Widgets.CreateButton(frame, L["Skip"], function() ZoneBoardUI:SkipPicked() end,
        { height = self.BUTTON_H })
    self.save = Widgets.CreateButton(frame, L["Save Farm"], function() ZoneBoardUI:SavePicked() end,
        { height = self.BUTTON_H })
    self.foot = Theme.CreateLabel(frame, "tiny", "muted")
    self.foot:SetWordWrap(true)

    frame:SetScript("OnMouseWheel", function(_, delta)
        ZoneBoardUI:Scroll(delta > 0 and -1 or 1)
    end)
    frame:SetScript("OnShow", function() ZoneBoardUI:Watch(true) end)
    frame:SetScript("OnHide", function() ZoneBoardUI:Watch(false) end)

    if ns.SharedWindow and ns.SharedWindow.KeepSpot then ns.SharedWindow.KeepSpot(frame, self.SPOT_KEY) end
    return frame
end

--------------------------------------------------------------------------------
-- Drawing
--------------------------------------------------------------------------------

--- The title: "ZONE BOARD Durotar".
function ZoneBoardUI.Title(zone)
    if zone then return L["ZONE BOARD"] .. " " .. ns.Spots.Show(zone) end
    return L["ZONE BOARD"]
end

--- FINISH's two head lines.
function ZoneBoardUI.HeadLines(unlocked, total)
    local left = total - unlocked
    local first = L.Format("%d of %d mobs unlocked", unlocked, total)
    if left <= 0 then return first, L["Every mob here is unlocked."] end
    return first, L.Format("%d to go. Each one opens its drop list.", left)
end

--- BEST's foot line.
function ZoneBoardUI.BestFoot(mysteries)
    local line = L["Worth a kill, coin and drops, from your own kills."]
    if mysteries > 0 then
        line = line .. " " .. L.Format("%d mobs here are still a mystery.", mysteries)
    end
    return line
end

--- "Skull Rock", or the zone when the drop list names no place.
local function Where(entry)
    return entry.location or ns.Spots.Show(entry.zone)
end

function ZoneBoardUI:FillFinish(row, entry)
    row.data = entry
    row.rank:SetText(entry.minLevel and entry.minLevel >= 0 and tostring(entry.minLevel) or "")
    ZoneBoardUI.Paint(row.rank, Board().LevelColor(entry))
    row.icon:Hide()
    row.mystery:Hide()
    row.name:ClearAllPoints()
    row.name:SetPoint("TOPLEFT", 32, -5)
    row.name:SetPoint("RIGHT", row.bar, "LEFT", -6, 0)
    row.name:SetText(entry.name)
    ZoneBoardUI.Paint(row.name, entry.done and "good" or "text")
    self:FillProgress(row, entry)
    row.bar:Show()
    row.count:Show()
    row.right:SetText(entry.yards and ns.Arrow.Yards(entry.yards) or "")
    ZoneBoardUI.Paint(row.right, "muted")
end

--- The parts a kill moves: the bar, the count, ALMOST.
function ZoneBoardUI:FillProgress(row, entry)
    local need = ns.Tracker.MIN_KILLS
    row.bar:SetShare((entry.kills or 0) / need)
    row.count:SetText(ZoneBoardUI.Count(entry.kills))
    local almost = not entry.done and (entry.kills or 0) >= Board().ALMOST
    row.tag:SetShown(almost)
    row.sub:SetText(almost and "" or Where(entry))
    if almost then
        row.tag:ClearAllPoints()
        row.tag:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -2)
        row.sub:SetText("")
    end
end

function ZoneBoardUI:FillBest(row, item, rank)
    local entry = item.entry or item
    row.data = entry
    row.bar:Hide()
    row.count:Hide()
    row.tag:Hide()
    row.name:ClearAllPoints()
    row.name:SetPoint("TOPLEFT", 56, -5)
    row.name:SetPoint("RIGHT", row.right, "LEFT", -6, 0)
    row.sub:ClearAllPoints()
    row.sub:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -2)
    row.sub:SetPoint("RIGHT", row.right, "LEFT", -6, 0)
    if item.entry then
        row.mystery:Hide()
        row.icon:Show()
        Theme.SetItemIcon(row.icon, item.bestID)
        row.rank:SetText(rank == 1 and ns.TrackerUI.CROWN or tostring(rank))
        ZoneBoardUI.Paint(row.rank, rank == 1 and "accentHi" or "muted")
        row.name:SetText(entry.name)
        ZoneBoardUI.Paint(row.name, rank == 1 and "accentHi" or "text")
        local sub = Where(entry)
        if rank == 1 and item.best then
            sub = L.Format("%s. Best drop: %s", sub, Util.ColorItem(item.best, item.bestID))
        end
        row.sub:SetText(sub)
        row.right:SetText(ns.Value.Coins(item.value))
    else
        row.icon:Hide()
        row.mystery:Show()
        row.rank:SetText("")
        row.name:SetText(entry.name)
        ZoneBoardUI.Paint(row.name, "muted")
        local need = math.max(0, ns.Tracker.MIN_KILLS - (entry.kills or 0))
        row.sub:SetText(L.Format("%d more kills to find out", need))
        row.right:SetText("???")
        ZoneBoardUI.Paint(row.right, "muted")
    end
end

--- The rows for the tab showing, in order: FINISH entries, or BEST's ranked
--- then mysteries.
function ZoneBoardUI:Data(tab, list)
    local board = Board()
    if tab == "best" then
        local best = board:Best(list)
        local data = {}
        for rank, item in ipairs(best.ranked) do data[#data + 1] = { item = item, rank = rank } end
        for _, entry in ipairs(best.mysteries) do data[#data + 1] = { item = entry } end
        return data, best
    end
    local rows, unlocked, total = board:Rows(list)
    if not Fighting() or not self.order then
        board.Order(rows, board.Position())
    end
    self.order = rows
    local data = {}
    for _, entry in ipairs(rows) do data[#data + 1] = { item = entry } end
    return data, nil, unlocked, total
end

--- The name picked on a tab, else the first row's.
function ZoneBoardUI:Picked(data)
    local tab = Board().Tab()
    local name = self.picks[tab]
    for _, d in ipairs(data or self.data or {}) do
        local entry = d.item.entry or d.item
        if entry.name == name then return entry end
    end
    local first = data and data[1] or (self.data or {})[1]
    return first and (first.item.entry or first.item) or nil
end

function ZoneBoardUI:Pick(name)
    self.picks[Board().Tab()] = name
    for _, row in ipairs(self.rows) do
        row.picked = row:IsShown() and row.data and row.data.name == name or nil
        ZoneBoardUI.Stripe(row)
    end
end

function ZoneBoardUI:Draw()
    local frame = self.frame
    if not frame or not frame:IsShown() then return end
    local board = Board()
    local tab = board.Tab()
    if self.tabs.selected ~= tab then self.tabs:Select(tab) end
    local zone = board.Here()
    local list = zone and board:List(zone)
    if self.trim and self.trim.plate and self.trim.plate.SetTitle then
        self.trim.plate:SetTitle(ZoneBoardUI.Title(zone))
    end

    local pad, y = self.PAD, self.PAD + 34
    local data, best, unlocked, total = {}, nil, 0, 0
    if list and list.ready then
        data, best, unlocked, total = self:Data(tab, list)
    end
    self.data = data

    local finish = tab == "finish"
    self.head:SetShown(finish)
    self.ticks:SetShown(finish)
    if finish then
        self.ring:SetShare(unlocked, total)
        local first, second = ZoneBoardUI.HeadLines(unlocked, total)
        self.headline:SetText(first)
        self.headsub:SetText(second)
        y = y + self.HEAD_H
        self.ticks:ClearAllPoints()
        self.ticks:SetPoint("TOPLEFT", pad, -y)
        self.ticks:SetPoint("TOPRIGHT", -pad, -y)
        self.near:SetChecked(board.NearFirst())
        self.showDone:SetChecked(board.ShowDone())
        y = y + self.TICK_H + 2
    end

    local shown = math.min(self.ROWS, #data)
    self.offset = math.max(0, math.min(self.offset or 0, #data - shown))
    self.body:ClearAllPoints()
    self.body:SetPoint("TOPLEFT", pad, -y)
    self.body:SetPoint("TOPRIGHT", -pad, -y)
    local bodyH = math.max(shown, 1) * self.ROW_H
    self.body:SetHeight(bodyH)
    local picked = self:Picked(data)
    for index, row in ipairs(self.rows) do
        local d = data[index + self.offset]
        if d and index <= shown then
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", 0, -(index - 1) * self.ROW_H)
            row:SetPoint("TOPRIGHT", 0, -(index - 1) * self.ROW_H)
            if finish then self:FillFinish(row, d.item) else self:FillBest(row, d.item, d.rank) end
            row.picked = picked and row.data and row.data.name == picked.name or nil
            ZoneBoardUI.Stripe(row)
            row:Show()
        else
            row.data = nil
            row:Hide()
        end
    end

    -- A new best here: its row slides up from the foot of the list into
    -- first place, the way the top 15 shuffles.
    if not finish and self.shuffle then
        local name = self.shuffle
        self.shuffle = nil
        for index, row in ipairs(self.rows) do
            if row:IsShown() and row.data and row.data.name == name and index < shown and ns.Motion then
                local to, from = -(index - 1) * self.ROW_H, -(shown - 1) * self.ROW_H
                ns.Motion:Run(row, "shuffle", 0.6, function(p)
                    local at = from + (to - from) * p
                    row:ClearAllPoints()
                    row:SetPoint("TOPLEFT", 0, at)
                    row:SetPoint("TOPRIGHT", 0, at)
                end, { ease = ns.Motion.EaseOutBack })
            end
        end
    end

    local empty
    if not zone then empty = L["Nothing to hunt here."]
    elseif not (list and list.ready) then empty = L["Reading this zone."]
    elseif #data == 0 then empty = finish and total > 0 and L["Every mob here is unlocked."] or L["Nothing to hunt here."] end
    self.empty:SetText(empty or "")
    self.empty:SetShown(empty ~= nil)
    y = y + bodyH + 6

    self.go:ClearAllPoints()
    self.go:SetPoint("TOPLEFT", pad, -y)
    self.go:SetEnabled(picked ~= nil and (finish and not picked.done or not finish))
    local second = finish and self.skip or self.save
    self.skip:SetShown(finish)
    self.save:SetShown(not finish)
    second:ClearAllPoints()
    second:SetPoint("LEFT", self.go, "RIGHT", 6, 0)
    second:SetEnabled(picked ~= nil)
    y = y + self.BUTTON_H + 6

    self.foot:ClearAllPoints()
    self.foot:SetPoint("TOPLEFT", pad, -y)
    self.foot:SetWidth(self.WIDTH - pad * 2)
    if finish then
        self.foot:SetText(L["Rare mobs, bosses and town guards are left out."])
    else
        self.foot:SetText(ZoneBoardUI.BestFoot(best and #best.mysteries or 0))
    end
    local footH = math.max(14, math.ceil(self.foot:GetStringHeight() or 0))
    frame:SetHeight(y + footH + pad)
    self.ticksSince = 0
end

--- A kill moved one mob's count: only its row changes.
function ZoneBoardUI:Killed(entry)
    if not (self.frame and self.frame:IsShown()) then return end
    for _, row in ipairs(self.rows) do
        if row:IsShown() and row.data and row.data.name == entry.name then
            if Board().Tab() == "finish" then
                self:FillProgress(row, entry)
            elseif not entry.done then
                self:FillBest(row, entry)
            end
        end
    end
end

--- Once a second while it shows: the yards on the rows on screen, and a
--- re-sort by distance every RESORT seconds, never in a fight.
function ZoneBoardUI:Tick()
    if not (self.frame and self.frame:IsShown()) or Board().Tab() ~= "finish" then return end
    local board = Board()
    local here = board.Position()
    for _, row in ipairs(self.rows) do
        if row:IsShown() and row.data then
            row.data.yards = board.Yards(row.data, here)
            row.right:SetText(row.data.yards and ns.Arrow.Yards(row.data.yards) or "")
        end
    end
    self.ticksSince = (self.ticksSince or 0) + 1
    if self.ticksSince >= self.RESORT and board.NearFirst() and not Fighting() and self.order then
        self.ticksSince = 0
        local before = {}
        for i, entry in ipairs(self.order) do before[i] = entry.name end
        board.Order(self.order, here)
        for i, entry in ipairs(self.order) do
            if before[i] ~= entry.name then self:Draw(); return end
        end
    end
end

function ZoneBoardUI:Scroll(by)
    local data = self.data or {}
    local most = math.max(0, #data - self.ROWS)
    local offset = math.max(0, math.min(most, (self.offset or 0) + by))
    if offset ~= self.offset then
        self.offset = offset
        self:Draw()
    end
end

--------------------------------------------------------------------------------
-- Buttons
--------------------------------------------------------------------------------

--- Take Me There: on FINISH a hunt; on BEST the arrow to that mob's camp.
function ZoneBoardUI:Go()
    local entry = self:Picked()
    if not entry then return end
    local board = Board()
    if board.Tab() == "finish" then
        board:StartHunt(entry.name)
    else
        local camp = board:Camp(entry)
        if camp and ns.Arrow then ns.Arrow:Grind(camp) end
    end
end

function ZoneBoardUI:SkipPicked()
    local entry = self:Picked()
    if entry then Board():Skip(entry.zone, entry.name) end
end

--- Save Farm: the Saved Farms box, a kills farm of that mob here.
function ZoneBoardUI:SavePicked()
    local entry = self:Picked()
    if not (entry and ns.SavedFarmsUI) then return end
    ns.SavedFarmsUI:OpenBox({
        name = entry.name, mob = entry.name, zone = entry.zone, how = "kills",
        amount = ns.SavedFarms and ns.SavedFarms.DEFAULT_AMOUNT,
    })
end

--------------------------------------------------------------------------------
-- Showing
--------------------------------------------------------------------------------

function ZoneBoardUI:Shown()
    return self.frame and self.frame:IsShown() and true or false
end

function ZoneBoardUI:Show()
    if not Board().IsOn() then return false end
    self:Build()
    self.frame:Show()
    Board():List()
    self:Draw()
    return true
end

function ZoneBoardUI:Hide()
    if self.frame then self.frame:Hide() end
end

function ZoneBoardUI:Toggle()
    if self:Shown() then self:Hide() else self:Show() end
end

--- Redraw when something moved; hide when Zone Board was unticked.
function ZoneBoardUI:Refresh()
    if not Board().IsOn() then self:Hide(); return end
    if self:Shown() then self:Draw() end
end

function ZoneBoardUI:ResetPlace()
    if ns.db then ns.db.zoneBoardScale = nil end
    if ns.db and type(ns.db.windowSpots) == "table" then ns.db.windowSpots[self.SPOT_KEY] = nil end
    local frame = self.frame
    if frame then
        Widgets.ApplySize(frame, 100)
        frame:ClearAllPoints()
        frame:SetPoint("CENTER", UIParent, "CENTER", -320, 60)
    end
end

function ZoneBoardUI:Watch(on)
    if self.ticker then
        pcall(self.ticker.Cancel, self.ticker)
        self.ticker = nil
    end
    if on and type(C_Timer) == "table" and type(C_Timer.NewTicker) == "function" then
        self.ticker = C_Timer.NewTicker(self.LOOK, function() ZoneBoardUI:Tick() end)
    end
end

function ZoneBoardUI:OnEnable()
    if ns.SharedWindow and ns.SharedWindow.AddSpotReset then
        pcall(ns.SharedWindow.AddSpotReset, self.SPOT_KEY, function() ZoneBoardUI:ResetPlace() end)
    end
end
