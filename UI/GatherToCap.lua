-- Blackthornes Farmer -- UI/GatherToCap.lua
-- Gather to cap, drawn at the top of the Grind tab's list in the Ore,
-- Herbs and Leather views (Logic/GatherToCap.lua works the path out).
--
-- A heading ("MINING 87 / 150", "Gather to cap"), a thin meter with a
-- segment a stop (done green, the one you are on gold with a glow, the
-- rest dark), then a dark glass row a stop: the last one done, the one you
-- are on (lit, with its item's icon and Show the Way) and a few after it.
-- Under them a line on where the gold an hour comes from and Set Goal.
--
-- Drawn only when the Grind tab draws; the rows are made once and filled
-- again only when the path or its words moved (a key per draw).

local _, ns = ...
local L = ns.L

local GatherToCapUI = ns.NewModule("GatherToCapUI")

local Theme = ns.Theme
local Widgets = ns.Widgets

GatherToCapUI.HEAD_H = 18
GatherToCapUI.METER_H = 5
GatherToCapUI.STOP_H = 34
GatherToCapUI.FOOT_H = 26
-- Stops shown after the one you are on.
GatherToCapUI.LATER = 3
-- Room left under the block, before the list's headings.
GatherToCapUI.GAP = 8

local CHECK = [[Interface\RaidFrame\ReadyCheck-Ready]]
local ICON = 22

--- Upper case that keeps German's umlauts upper too.
local function Upper(text)
    return (text:upper():gsub("ä", "Ä"):gsub("ö", "Ö"):gsub("ü", "Ü"))
end

local function ButtonWidth(text)
    return math.ceil(Theme.TextWidth("small", text or "")) + 24
end

--------------------------------------------------------------------------------
-- Words
--------------------------------------------------------------------------------

--- "MINING 87 / 150".
function GatherToCapUI.HeadingText(path)
    return L.Format("%s %d / %d", Upper(ns.GatherToCap.SkillLabel(path.english)), path.skill,
        path.most or ns.GatherToCap.TOP)
end

--- "Tin Vein in Wetlands".
function GatherToCapUI.TitleText(stop)
    return L.Format("%s in %s", stop.node, ns.Spots.Show(stop.zone))
end

--- "1 to 65", or "now to 125" for the one you are on.
function GatherToCapUI.RangeText(stop)
    if stop.state == "now" then return L.Format("now to %d", stop.to) end
    return L.Format("%d to %d", stop.from, stop.to)
end

--- "Train Expert Mining at 125 first."
function GatherToCapUI.TrainText(path, stop)
    local rank = stop.train
    if not rank then return nil end
    return L.Format("Train %s %s at %d first.", ns.GatherToCap.RankLabel(rank.key),
        ns.GatherToCap.SkillLabel(path.english), rank.at)
end

--- The line under a stop's name.
function GatherToCapUI.SubText(path, stop)
    if stop.state == "done" then return "" end
    local parts = {}
    if stop.state == "now" then
        if (stop.spots or 0) > 0 then parts[#parts + 1] = L.Format("You've mapped %d spots here.", stop.spots) end
        if stop.gathers then parts[#parts + 1] = L.Format("About %d more gathers.", stop.gathers) end
        parts[#parts + 1] = GatherToCapUI.TrainText(path, stop)
    else
        local train = GatherToCapUI.TrainText(path, stop)
        if train then
            parts[#parts + 1] = train
        elseif stop.minLevel then
            parts[#parts + 1] = L.Format("Mobs here are level %d to %d.", stop.minLevel,
                stop.maxLevel or stop.minLevel)
        end
    end
    return table.concat(parts, " ")
end

--- "2g 40s an hour", or "" when nothing says.
function GatherToCapUI.WorthText(stop)
    if not stop.perHour then return "" end
    return L.Format("%s an hour", ns.Value.Coins(stop.perHour))
end

--------------------------------------------------------------------------------
-- Construction
--------------------------------------------------------------------------------

--- The block, inside the Grind tab's panel. Hidden until a path shows.
function GatherToCapUI:Build(panel)
    if self.frame then return self.frame end
    local frame = CreateFrame("Frame", nil, panel)
    frame:SetPoint("TOPLEFT", 8, -8)
    frame:SetPoint("TOPRIGHT", -8, -8)
    frame:SetHeight(1)
    frame:Hide()
    self.frame = frame

    local head = Theme.CreateLabel(frame, "small", "accent")
    head:SetPoint("TOPLEFT", 2, 0)
    head:SetHeight(self.HEAD_H)
    self.head = head

    local note = Theme.CreateLabel(frame, "tiny", "muted", "RIGHT")
    note:SetPoint("TOPRIGHT", -2, 0)
    note:SetHeight(self.HEAD_H)
    note:SetText(L["Gather to cap"])
    self.note = note

    local meter = CreateFrame("Frame", nil, frame)
    meter:SetPoint("TOPLEFT", 0, -(self.HEAD_H + 2))
    meter:SetPoint("TOPRIGHT", 0, -(self.HEAD_H + 2))
    meter:SetHeight(self.METER_H)
    meter.segments = {}
    -- The glow round the stop you are on: a soft gold light, lit through
    -- Theme.LightGradient so it is hidden, never just faded.
    meter.glow = meter:CreateTexture(nil, "BACKGROUND")
    pcall(meter.glow.SetBlendMode, meter.glow, "ADD")
    meter.glow:Hide()
    self.meter = meter

    self.rows = {}

    local foot = Theme.CreateLabel(frame, "tiny", "muted")
    foot:SetText(L["Gold an hour is from your own gathers where you have them."])
    self.foot = foot

    local goal = Widgets.CreateButton(frame, L["Set Goal"], function()
        if GatherToCapUI.current then ns.GatherToCap:SetGoal(GatherToCapUI.current) end
    end, { width = ButtonWidth(L["Set Goal"]), height = 20 })
    self.goalButton = goal

    return frame
end

function GatherToCapUI:Row(index)
    local row = self.rows[index]
    if row then return row end

    row = CreateFrame("Frame", nil, self.frame)
    row:SetHeight(self.STOP_H)
    row:EnableMouse(true)

    row.stripe = Theme.Fill(row, "glass")
    row.line = row:CreateTexture(nil, "BACKGROUND", nil, 1)
    row.line:SetPoint("BOTTOMLEFT")
    row.line:SetPoint("BOTTOMRIGHT")
    row.line:SetHeight(1)
    row.line:SetColorTexture(Theme.Unpack("border", 0.6))
    Widgets.RowLight(row)

    -- The one you are on: a bright gold edge down its left.
    row.active = row:CreateTexture(nil, "OVERLAY", nil, 1)
    row.active:SetPoint("TOPLEFT")
    row.active:SetPoint("BOTTOMLEFT")
    row.active:SetWidth(2)
    row.active:SetColorTexture(Theme.Unpack("accentHi"))

    row.icon = Theme.CreateItemIcon(row, ICON)
    row.icon:SetPoint("LEFT", 8, 0)
    row.check = row:CreateTexture(nil, "ARTWORK")
    row.check:SetSize(14, 14)
    row.check:SetTexture(CHECK)
    row.check:SetPoint("CENTER", row.icon, "CENTER", 0, 0)

    row.title = Theme.CreateLabel(row, "small", "text")
    row.title:SetPoint("TOPLEFT", 8 + ICON + 8, -4)
    row.range = Theme.CreateLabel(row, "tiny", "muted")
    row.range:SetPoint("LEFT", row.title, "RIGHT", 8, 0)
    row.sub = Theme.CreateLabel(row, "tiny", "muted")
    row.sub:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -3)

    row.worth = Theme.CreateLabel(row, "small", "text", "RIGHT")
    row.done = Theme.CreateLabel(row, "small", "good", "RIGHT")
    row.done:SetText(L["Done"])
    row.done:SetPoint("RIGHT", -10, 0)

    row.button = Widgets.CreateButton(row, L["Show the Way"], function()
        ns.GatherToCap:ShowTheWay(row.stop)
    end, { primary = true, width = ButtonWidth(L["Show the Way"]), height = 20 })
    row.button:SetPoint("RIGHT", -8, 0)

    row:SetScript("OnEnter", function(self)
        if self.stop and self.stop.state ~= "now" then Widgets.SetRowLight(self, 1) end
    end)
    row:SetScript("OnLeave", function(self) Widgets.SetRowLight(self, 0) end)

    self.rows[index] = row
    return row
end

--------------------------------------------------------------------------------
-- Drawing
--------------------------------------------------------------------------------

function GatherToCapUI:PaintMeter(path)
    local meter = self.meter
    local count = #path.stops
    local width = meter:GetWidth()
    if type(width) ~= "number" or width <= 0 then width = 600 end
    local gap = 2
    local each = count > 0 and (width - gap * (count - 1)) / count or width
    meter.glow:Hide()
    for index, stop in ipairs(path.stops) do
        local segment = meter.segments[index]
        if not segment then
            segment = meter:CreateTexture(nil, "ARTWORK")
            meter.segments[index] = segment
        end
        segment:ClearAllPoints()
        segment:SetPoint("TOPLEFT", (index - 1) * (each + gap), 0)
        segment:SetSize(math.max(1, each), self.METER_H)
        local key = stop.state == "done" and "good" or stop.state == "now" and "accentHi" or "glassHover"
        segment:SetColorTexture(Theme.Unpack(key))
        segment:Show()
        if stop.state == "now" then
            meter.glow:ClearAllPoints()
            meter.glow:SetPoint("TOPLEFT", segment, "TOPLEFT", -4, 4)
            meter.glow:SetPoint("BOTTOMRIGHT", segment, "BOTTOMRIGHT", 4, -4)
            Theme.LightGradient(meter.glow, "VERTICAL", "accent", 0.45, 0.45, 1)
            meter.glow:Show()
        end
    end
    for index = count + 1, #meter.segments do meter.segments[index]:Hide() end
end

function GatherToCapUI:FillRow(row, path, stop, index)
    row.stop = stop
    local state = stop.state
    row.stripe:SetColorTexture(Theme.Unpack(state == "now" and "glassActive"
        or (index % 2 == 1 and "glass" or "glassAlt")))
    row.active:SetShown(state == "now")
    Widgets.SetRowLight(row, 0)

    if state == "done" then
        row.icon:Hide()
        row.check:Show()
    else
        row.check:Hide()
        Theme.SetItemIcon(row.icon, stop.itemID)
    end

    row.title:SetText(GatherToCapUI.TitleText(stop))
    row.title:SetTextColor(Theme.Unpack(state == "now" and "accentHi" or "text"))
    row.range:SetText(GatherToCapUI.RangeText(stop))
    local sub = GatherToCapUI.SubText(path, stop)
    row.sub:SetText(sub)
    row.sub:SetShown(sub ~= "")
    row.title:ClearAllPoints()
    if sub ~= "" then
        row.title:SetPoint("TOPLEFT", 8 + ICON + 8, -4)
    else
        row.title:SetPoint("LEFT", 8 + ICON + 8, 0)
    end

    row.done:SetShown(state == "done")
    row.button:SetShown(state == "now")
    local worth = state ~= "done" and GatherToCapUI.WorthText(stop) or ""
    row.worth:SetText(worth)
    row.worth:SetShown(worth ~= "")
    row.worth:ClearAllPoints()
    if state == "now" then
        row.worth:SetPoint("RIGHT", row.button, "LEFT", -10, 0)
    else
        row.worth:SetPoint("RIGHT", -10, 0)
    end

    -- The ones done fade back more than the ones still to come.
    local alpha = state == "done" and 0.55 or state == "later" and 0.8 or 1
    for _, region in ipairs({ row.icon, row.check, row.title, row.range, row.sub, row.worth, row.done }) do
        region:SetAlpha(alpha)
    end
end

--- Draw the path for the Grind view `view` ("ore", "herbs", "skinning"),
--- or hide it. Returns the room it takes at the top of the list.
function GatherToCapUI:Update(view)
    if not self.frame then return 0 end
    local path = view and ns.GatherToCap:Path(view)
    if not path or #path.stops == 0 then
        self.frame:Hide()
        self.current, self.path = nil, nil
        return 0
    end

    local shown = ns.GatherToCap.Shown(path, self.LATER)
    self.path = path
    self.current = path.current and path.stops[path.current] or nil

    self.head:SetText(GatherToCapUI.HeadingText(path))
    self:PaintMeter(path)

    local top = self.HEAD_H + 2 + self.METER_H + 6
    for index, stop in ipairs(shown) do
        local row = self:Row(index)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 0, -(top + (index - 1) * self.STOP_H))
        row:SetPoint("TOPRIGHT", 0, -(top + (index - 1) * self.STOP_H))
        self:FillRow(row, path, stop, index)
        row:Show()
    end
    for index = #shown + 1, #self.rows do self.rows[index]:Hide() end

    local footTop = top + #shown * self.STOP_H + 4
    self.foot:ClearAllPoints()
    self.foot:SetPoint("TOPLEFT", 2, -footTop - 4)
    self.goalButton:ClearAllPoints()
    self.goalButton:SetPoint("TOPRIGHT", -2, -footTop)
    self.goalButton:SetShown(self.current ~= nil)

    local height = footTop + self.FOOT_H - 4
    self.frame:SetHeight(height)
    self.frame:Show()
    return height + self.GAP
end
