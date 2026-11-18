local _, ns = ...
local L = ns.L

-- The hunt window (Logic/ZoneBoard.lua; the owner said build it from a
-- mockup, 2026-11-18). Like the Route Window: it floats only while a Zone
-- Board hunt runs (after Take Me There), with "Hunt Window:" ticked (on
-- unless unticked), and goes away on Stop or when the zone is done. The
-- mob to hunt, how far and its kills, then the one after it, Next Mob and
-- Stop. Folded it is one line: "FINISH Dustwind Harpy 17/20". Its spot is
-- kept as "farmer.zonehunt", its size as zoneHuntScale. Redrawn only when
-- what it shows moved; distances once a second while it shows.

local ZoneHunt = ns.NewModule("ZoneHunt")
ns.ZoneHunt = ZoneHunt

ZoneHunt.WIDTH = 270
ZoneHunt.PAD = 8
ZoneHunt.ROW_H = 44
ZoneHunt.BUTTON_H = 24
ZoneHunt.LOOK = 1
ZoneHunt.SPOT_KEY = "farmer.zonehunt"

local Theme, Widgets = ns.Theme, ns.Widgets

local function Board() return ns.ZoneBoard end
local function UI() return ns.ZoneBoardUI end

--- Should it be on screen: Zone Board and Hunt Window ticked, a hunt
--- running, and not closed with its gem since the hunt started.
function ZoneHunt:Wanted()
    local board = Board()
    if not (board.IsOn() and board.HuntWindowOn() and board:Hunting()) then return false end
    return not self.closed
end

--- The title: "FINISH Durotar 9/14", folded "FINISH Dustwind Harpy 17/20".
function ZoneHunt.Title(zone, unlocked, total, target, folded)
    local word = L["FINISH"]
    if folded and target then
        return ("%s %s %s"):format(word, target.name, UI().Count(target.kills))
    end
    if zone then
        return ("%s %s %s"):format(word, ns.Spots.Show(zone), ("%d/%d"):format(unlocked or 0, total or 0))
    end
    return word
end

--- The target's second line: "140 yd, Razormane Grounds".
function ZoneHunt.Where(entry)
    local place = entry.location or ns.Spots.Show(entry.zone)
    if entry.yards then return ns.Arrow.Yards(entry.yards) .. ", " .. place end
    return place
end

local function MakeRow(frame, index)
    local row = CreateFrame("Frame", nil, frame)
    row:SetHeight(ZoneHunt.ROW_H)
    row.stripe = row:CreateTexture(nil, "BACKGROUND")
    row.stripe:SetAllPoints()
    row.stripe:SetColorTexture(Theme.Unpack(index == 1 and "glassActive" or "glassAlt"))
    row.line = row:CreateTexture(nil, "BORDER")
    row.line:SetPoint("BOTTOMLEFT")
    row.line:SetPoint("BOTTOMRIGHT")
    row.line:SetHeight(1)
    row.line:SetColorTexture(Theme.Unpack("border", 0.6))
    -- Transparent (UI/SeeThrough.lua's "hunt"); the picked row's glass
    -- keeps enough to read and its gold edge stays.
    if ns.SeeThrough then
        ns.SeeThrough:AddGlass("hunt", row.stripe, index == 1 and 0.6 or 0)
        ns.SeeThrough:AddGlass("hunt", row.line)
    end
    if index == 1 then
        local edge = row:CreateTexture(nil, "ARTWORK")
        edge:SetPoint("TOPLEFT")
        edge:SetPoint("BOTTOMLEFT")
        edge:SetWidth(3)
        edge:SetColorTexture(Theme.Unpack("accentHi"))
        row.pointer = row:CreateTexture(nil, "ARTWORK")
        row.pointer:SetSize(16, 16)
        row.pointer:SetPoint("LEFT", 10, 0)
        row.pointer:SetTexture([[Interface\ChatFrame\ChatFrameExpandArrow]])
        row.pointer:SetVertexColor(Theme.Unpack("accentHi"))
    end
    row.bar = UI().Bar(row, 76)
    row.bar:SetPoint("RIGHT", -8, 4)
    row.count = Theme.CreateLabel(row, "tiny", "muted", "RIGHT")
    row.count:SetPoint("TOPRIGHT", row.bar, "BOTTOMRIGHT", 0, -2)
    row.name = Theme.CreateLabel(row, "small", index == 1 and "text" or "muted")
    row.name:SetPoint("TOPLEFT", 32, -6)
    row.name:SetPoint("RIGHT", row.bar, "LEFT", -6, 0)
    row.name:SetWordWrap(true)
    row.sub = Theme.CreateLabel(row, "tiny", "muted")
    row.sub:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -2)
    row.sub:SetPoint("RIGHT", row.bar, "LEFT", -6, 0)
    row.sub:SetWordWrap(true)
    row.tag = UI().Tag(row)
    row:Hide()
    return row
end

function ZoneHunt:Build()
    if self.frame then return self.frame end
    local frame = CreateFrame("Frame", "BlackthornesFarmerZoneHunt", UIParent)
    frame:SetSize(self.WIDTH, 160)
    frame:SetPoint("CENTER", 300, 160)
    frame:SetFrameStrata("MEDIUM")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:Hide()
    self.frame = frame

    local back = Theme.Fill(frame, "window")
    if ns.SeeThrough then ns.SeeThrough:AddGlass("hunt", back) end
    if ns.Titanforged then
        self.trim = ns.Titanforged:Dress(frame, { title = L["FINISH"], close = function() ZoneHunt:Close() end })
        local left, right, top, bottom = ns.Titanforged.Reach(self.trim)
        if frame.SetClampRectInsets then pcall(frame.SetClampRectInsets, frame, -left, right, top, -bottom) end
    else
        Theme.Border(frame, "borderLit")
    end
    frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    Widgets.ApplySize(frame, ns.db and ns.db.zoneHuntScale)
    frame.sizeGrip = Widgets.CreateSizeGrip(frame, {
        below = self.trim and select(4, ns.Titanforged.Reach(self.trim)) or 0,
        get = function() return ns.db and ns.db.zoneHuntScale end,
        save = function(percent) if ns.db then ns.db.zoneHuntScale = percent end end,
    })
    if ns.FoldWindow and ns.FoldWindow.Add then
        ns.FoldWindow:Add(frame, { onToggle = function() ZoneHunt.key = nil; ZoneHunt:Update(true) end })
    end

    self.rows = { MakeRow(frame, 1), MakeRow(frame, 2) }
    for index, row in ipairs(self.rows) do
        row:SetPoint("TOPLEFT", self.PAD, -self.PAD - (index - 1) * self.ROW_H)
        row:SetPoint("TOPRIGHT", -self.PAD, -self.PAD - (index - 1) * self.ROW_H)
    end
    self.next = Widgets.CreateButton(frame, L["Next Mob"], function() Board():NextMob(true) end,
        { primary = true, height = self.BUTTON_H })
    self.stop = Widgets.CreateButton(frame, L["Stop"], function() Board():StopHunt() end,
        { height = self.BUTTON_H })

    frame:SetScript("OnShow", function() ZoneHunt:Watch(true) end)
    frame:SetScript("OnHide", function() ZoneHunt:Watch(false) end)
    if ns.SeeThrough then ns.SeeThrough:Attach("hunt", frame) end
    if ns.SharedWindow and ns.SharedWindow.KeepSpot then ns.SharedWindow.KeepSpot(frame, self.SPOT_KEY) end
    return frame
end

--- What it shows: the target, the one after and the zone's counts. The
--- queue and counts are read again only when `full` (a kill, a new target);
--- the once a second look measures the target's yards alone.
function ZoneHunt:Look(full)
    local board = Board()
    local here = board.Position()
    if full or not self.seen then
        local queue = board:Queue(here)
        local _, unlocked, total = board:Rows(board.hunt and board:List(board.hunt.zone))
        self.seen = { after = board:After(queue), unlocked = unlocked, total = total }
    end
    local target = board:Target()
    if target then target.yards = board.Yards(target, here) end
    local seen = self.seen
    return target, seen.after, seen.unlocked, seen.total
end

local function Yards(entry)
    return entry and entry.yards and math.floor(entry.yards / 10 + 0.5) or -1
end

function ZoneHunt:Update(full)
    local frame = self.frame
    if not (frame and frame:IsShown()) then return end
    local board = Board()
    local target, after, unlocked, total = self:Look(full)
    local folded = ns.FoldWindow and ns.FoldWindow.IsFolded and ns.FoldWindow:IsFolded(frame) or false
    local key = table.concat({ tostring(folded), tostring(target and target.name), tostring(target and target.kills),
        Yards(target), tostring(after and after.name), tostring(after and after.kills), unlocked, total }, "|")
    if key == self.key then return end
    self.key = key

    local zone = board.hunt and board.hunt.zone
    if self.trim and self.trim.plate and self.trim.plate.SetTitle then
        self.trim.plate:SetTitle(ZoneHunt.Title(zone, unlocked, total, target, folded))
    end
    if folded then return end

    local need = ns.Tracker.MIN_KILLS
    local one, two = self.rows[1], self.rows[2]
    if target then
        one.name:SetText(target.name)
        one.sub:SetText(ZoneHunt.Where(target))
        one.bar:SetShare((target.kills or 0) / need)
        one.count:SetText(UI().Count(target.kills))
        local almost = (target.kills or 0) >= board.ALMOST
        one.tag:ClearAllPoints()
        one.tag:SetPoint("TOPLEFT", one.sub, "BOTTOMLEFT", 0, -2)
        one.tag:SetShown(almost)
        one:Show()
    else
        one:Hide()
    end
    local y = self.PAD + self.ROW_H
    if after then
        two.name:SetText(L.Format("Then: %s", after.name))
        local same = target and after.location and after.location == target.location
        two.sub:SetText(same and L["Same camp"] or (after.location or ns.Spots.Show(after.zone)))
        two.bar:SetShare((after.kills or 0) / need)
        two.count:SetText(UI().Count(after.kills))
        two:Show()
        y = y + self.ROW_H
    else
        two:Hide()
    end
    y = y + 6
    self.next:ClearAllPoints()
    self.next:SetPoint("TOPLEFT", self.PAD, -y)
    self.next:SetEnabled(after ~= nil)
    self.stop:ClearAllPoints()
    self.stop:SetPoint("LEFT", self.next, "RIGHT", 6, 0)
    frame:SetHeight(y + self.BUTTON_H + self.PAD)
end

--- A kill moved the target's or the next mob's count.
function ZoneHunt:Killed()
    if not (self.frame and self.frame:IsShown()) then return end
    -- In a fight only the target's count moves; the rest after it.
    local fighting = type(InCombatLockdown) == "function" and InCombatLockdown()
    self:Update(not fighting)
end

--- Show or hide it by what is wanted, then redraw.
function ZoneHunt:Refresh()
    if not Board():Hunting() then self.closed = nil end
    if not self:Wanted() then
        if self.frame and self.frame:IsShown() then self.frame:Hide() end
        return
    end
    self:Build()
    if not self.frame:IsShown() then self.frame:Show() end
    self.key = nil
    self:Update(true)
end

--- The close gem: put away until the next hunt; the hunt goes on.
function ZoneHunt:Close()
    self.closed = true
    if self.frame then self.frame:Hide() end
end

function ZoneHunt:ResetPlace()
    if ns.db then ns.db.zoneHuntScale = nil end
    if ns.db and type(ns.db.windowSpots) == "table" then ns.db.windowSpots[self.SPOT_KEY] = nil end
    local frame = self.frame
    if frame then
        Widgets.ApplySize(frame, 100)
        frame:ClearAllPoints()
        frame:SetPoint("CENTER", UIParent, "CENTER", 300, 160)
    end
end

function ZoneHunt:Watch(on)
    if self.ticker then
        pcall(self.ticker.Cancel, self.ticker)
        self.ticker = nil
    end
    if on and type(C_Timer) == "table" and type(C_Timer.NewTicker) == "function" then
        self.ticker = C_Timer.NewTicker(self.LOOK, function() ZoneHunt:Update() end)
    end
end

function ZoneHunt:OnEnable()
    if ns.SharedWindow and ns.SharedWindow.AddSpotReset then
        pcall(ns.SharedWindow.AddSpotReset, self.SPOT_KEY, function() ZoneHunt:ResetPlace() end)
    end
end
