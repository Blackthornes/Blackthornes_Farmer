-- Blackthornes Farmer -- UI/GatherRoute.lua
-- The Grind tab's Route view (Logic/GatherRoute.lua works the loop out).
--
-- "GATHER ROUTE: ZONE" with your skills, tick boxes for Herbs, Ore, Skins,
-- Current Zone Only and Draw on Maps, the best zone you know with Show,
-- then a dark glass row a stop (STOP, AWAY, STATUS), the next one lit with
-- a gold edge. Under them Start Route, Skip Stop and Redo Route, and how
-- long one loop takes and what it brings in. A zone with too few spots
-- shows how many more it needs and your best zone.
--
-- Drawn only while the Route view shows; the rows are made once and filled
-- again only when the plan or its words moved (a key per draw).

local _, ns = ...
local L = ns.L

local GatherRouteUI = ns.NewModule("GatherRouteUI")

local Theme = ns.Theme
local Widgets = ns.Widgets

GatherRouteUI.HEAD_H = 18
GatherRouteUI.TICK_H = 22
GatherRouteUI.BEST_H = 26
GatherRouteUI.HEADING_H = 18
GatherRouteUI.ROW_H = 24
GatherRouteUI.FOOT_H = 30
GatherRouteUI.TRAIN_H = 30
GatherRouteUI.AWAY_X = 300
GatherRouteUI.STATUS_X = 400

local CHECK = [[Interface\RaidFrame\ReadyCheck-Ready]]
local ICON = 18

local function Upper(text)
    return (tostring(text or ""):upper():gsub("ä", "Ä"):gsub("ö", "Ö"):gsub("ü", "Ü"))
end

local function ButtonWidth(text)
    return math.ceil(Theme.TextWidth("small", text or "")) + 24
end

local function Route() return ns.GatherRoute end

local function Now() return ns.Gathering.Clock() end

--------------------------------------------------------------------------------
-- Words
--------------------------------------------------------------------------------

function GatherRouteUI.HeadText(plan)
    local zone = plan and (plan.zone or plan.hereZone)
    return L.Format("GATHER ROUTE: %s", Upper(zone and ns.Spots.Show(zone) or "?"))
end

function GatherRouteUI.BestText(best)
    if not best then return "" end
    local hour = best.hour and best.hour > 0 and ns.Value.Coins(best.hour) or nil
    if hour then
        return L.Format("Best zone for you right now: %s, about %s an hour, %d spots known.",
            ns.Spots.Show(best.zone), hour, best.spots or 0)
    end
    return L.Format("Your best zone: %s, %d spots known.", ns.Spots.Show(best.zone), best.spots or 0)
end

function GatherRouteUI.LoopText(plan)
    if not plan or not plan.loopSeconds then return "" end
    local time = ns.Respawn.Duration(plan.loopSeconds)
    if plan.loopWorth then
        return L.Format("One loop: about %s, %s", time, ns.Value.Coins(plan.loopWorth))
    end
    return L.Format("One loop: about %s", time)
end

function GatherRouteUI.FooterText(plan)
    if not plan then return "" end
    if plan.needs then return L.Format("%d spots learned here", plan.spotsZone or 0) end
    return L.Format("%d stops, %d spots learned here", #plan.stops, plan.spotsZone or 0)
end

--------------------------------------------------------------------------------
-- Building
--------------------------------------------------------------------------------

--- The Leveling Mode tick's hover.
function GatherRouteUI.TipLeveling(box)
    if not (box and box.SetScript) then return end
    box:HookScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(L["Leveling Mode:"], 1, 0.82, 0)
        GameTooltip:AddLine(L["Go to the spots that still give you skill first. Spots that give nothing are left for last."],
            1, 1, 1, true)
        GameTooltip:Show()
    end)
    box:HookScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
end

--- A box for the train line: amber edge, warm dark glass, wrapped words.
function GatherRouteUI.TrainBox(parent)
    local box = CreateFrame("Frame", nil, parent)
    box:SetHeight(GatherRouteUI.TRAIN_H)
    box.back = box:CreateTexture(nil, "BACKGROUND")
    box.back:SetAllPoints()
    box.back:SetColorTexture(0.14, 0.11, 0.05, 0.92)
    box.edges = {}
    for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
        local edge = box:CreateTexture(nil, "BORDER")
        edge:SetColorTexture(0.48, 0.35, 0.10, 1)
        if side == "TOP" or side == "BOTTOM" then
            edge:SetPoint(side .. "LEFT")
            edge:SetPoint(side .. "RIGHT")
            edge:SetHeight(1)
        else
            edge:SetPoint("TOP" .. side)
            edge:SetPoint("BOTTOM" .. side)
            edge:SetWidth(1)
        end
        box.edges[#box.edges + 1] = edge
    end
    box.text = Theme.CreateLabel(box, "small", "warn", "LEFT")
    box.text:SetPoint("LEFT", 8, 0)
    box.text:SetPoint("RIGHT", -8, 0)
    if box.text.SetWordWrap then box.text:SetWordWrap(true) end
    box:Hide()
    return box
end

--- Put the train line in its box; false when there is none.
function GatherRouteUI.FillTrain(box, text, color)
    if not (box and text and text ~= "") then return false end
    box.text:SetText(text)
    box.text:SetTextColor(Theme.Unpack(color == "loss" and "loss" or "warn"))
    return true
end

function GatherRouteUI:Build(panel)
    if self.frame then return self.frame end
    local frame = CreateFrame("Frame", nil, panel)
    frame:SetPoint("TOPLEFT", 8, -8)
    frame:SetPoint("BOTTOMRIGHT", -8, 26)
    frame:Hide()
    self.frame = frame
    self.offset = 0

    local head = Theme.CreateLabel(frame, "small", "accent")
    head:SetPoint("TOPLEFT", 2, 0)
    head:SetHeight(self.HEAD_H)
    self.head = head

    local skills = Theme.CreateLabel(frame, "tiny", "muted", "RIGHT")
    skills:SetPoint("TOPRIGHT", -2, 0)
    skills:SetHeight(self.HEAD_H)
    self.skills = skills

    -- Tick boxes, one row.
    local function Refresh()
        if ns.GrindingUI and ns.GrindingUI.Refresh then ns.GrindingUI:Refresh() end
    end
    self.ticks = {}
    local function Tick(key, text, getter, setter)
        local box = Widgets.CreateCheckbox(frame, text, function(checked)
            setter(checked)
            GatherRouteUI.key = nil
            Refresh()
        end, getter())
        box.getter = getter
        self.ticks[#self.ticks + 1] = box
        self.ticks[key] = box
        return box
    end
    Tick("herbs", L["Herbs"], function() return Route().Ticked("herbs") end,
        function(on) Route():SetTicked("herbs", on) end)
    Tick("ore", L["Ore"], function() return Route().Ticked("ore") end,
        function(on) Route():SetTicked("ore", on) end)
    Tick("skins", L["Skins"], function() return Route().Ticked("skins") end,
        function(on) Route():SetTicked("skins", on) end)
    Tick("zone", L["Current Zone Only:"], function() return Route().ZoneOnly() end,
        function(on) Route():SetZoneOnly(on) end)
    Tick("draw", L["Draw on Maps:"], function() return Route().DrawsOnMaps() end,
        function(on)
            Route():SetDraw(on)
            if ns.RouteMap and ns.RouteMap.Refresh then pcall(ns.RouteMap.Refresh, ns.RouteMap) end
        end)
    local leveling = Tick("leveling", L["Leveling Mode:"],
        function() local gives = Route().PageGives(); return gives ~= nil and Route().Leveling(gives) end,
        function(on) local gives = Route().PageGives(); if gives then Route():SetLeveling(gives, on) end end)
    GatherRouteUI.TipLeveling(leveling)

    -- The best zone strip.
    local best = CreateFrame("Frame", nil, frame)
    best:SetHeight(self.BEST_H)
    best.stripe = Theme.Fill(best, "glassAlt")
    best.text = Theme.CreateLabel(best, "small", "text")
    best.text:SetPoint("LEFT", 8, 0)
    best.button = Widgets.CreateButton(best, L["Show"], function()
        local plan = GatherRouteUI.plan
        if plan and plan.best then Route():ShowZone(plan.best) end
    end, { width = ButtonWidth(L["Show"]), height = 20 })
    best.button:SetPoint("RIGHT", -6, 0)
    best.text:SetPoint("RIGHT", best.button, "LEFT", -8, 0)
    self.best = best

    -- Column headings.
    local headings = CreateFrame("Frame", nil, frame)
    headings:SetHeight(self.HEADING_H)
    local stopHead = Theme.CreateLabel(headings, "tiny", "muted")
    stopHead:SetPoint("LEFT", 8, 0)
    stopHead:SetText(L["STOP"])
    local awayHead = Theme.CreateLabel(headings, "tiny", "muted")
    awayHead:SetPoint("LEFT", self.AWAY_X, 0)
    awayHead:SetText(L["AWAY"])
    local statusHead = Theme.CreateLabel(headings, "tiny", "muted")
    statusHead:SetPoint("LEFT", self.STATUS_X, 0)
    statusHead:SetText(L["STATUS"])
    self.headings = headings

    -- The list.
    local list = CreateFrame("Frame", nil, frame)
    list:EnableMouseWheel(true)
    list:SetScript("OnMouseWheel", function(_, delta)
        GatherRouteUI:Scroll(delta)
    end)
    self.list = list
    self.rows = {}

    -- The train line, in a box under the list.
    self.train = GatherRouteUI.TrainBox(frame)

    -- The foot: buttons and the loop line.
    local foot = CreateFrame("Frame", nil, frame)
    foot:SetPoint("BOTTOMLEFT", 0, 0)
    foot:SetPoint("BOTTOMRIGHT", 0, 0)
    foot:SetHeight(self.FOOT_H)
    self.foot = foot

    local startWidth = math.max(ButtonWidth(L["Start Route"]), ButtonWidth(L["Stop"]))
    self.startButton = Widgets.CreateButton(foot, L["Start Route"], function()
        if Route().Running() then Route():Stop() else Route():Start() end
        GatherRouteUI.key = nil
        Refresh()
    end, { primary = true, width = startWidth, height = 20 })
    self.startButton:SetPoint("LEFT", 0, 0)

    self.skipButton = Widgets.CreateButton(foot, L["Skip Stop"], function()
        Route():Skip()
        GatherRouteUI.key = nil
        Refresh()
    end, { width = ButtonWidth(L["Skip Stop"]), height = 20 })
    self.skipButton:SetPoint("LEFT", self.startButton, "RIGHT", 6, 0)

    self.redoButton = Widgets.CreateButton(foot, L["Redo Route"], function()
        Route():Redo()
        GatherRouteUI.key = nil
        Refresh()
    end, { width = ButtonWidth(L["Redo Route"]), height = 20 })
    self.redoButton:SetPoint("LEFT", self.skipButton, "RIGHT", 6, 0)

    -- Save Farm (UI/SavedFarms.lua), while Saved Farms is on: this page's
    -- route as a saved farm.
    self.saveFarmButton = Widgets.CreateButton(foot, L["Save Farm"], function()
        if ns.SavedFarmsUI then
            local plan = GatherRouteUI.plan
            ns.SavedFarmsUI:SaveRoute(Route().PageGives(), plan and plan.zone)
        end
    end, { width = ButtonWidth(L["Save Farm"]), height = 20 })
    self.saveFarmButton:SetPoint("LEFT", self.redoButton, "RIGHT", 6, 0)
    self.saveFarmButton:SetShown(ns.SavedFarms ~= nil and ns.SavedFarms.On() and Route().page ~= nil)

    self.loop = Theme.CreateLabel(foot, "small", "text", "RIGHT")
    self.loop:SetPoint("RIGHT", -4, 0)

    -- The empty view: a zone with too few spots.
    local empty = CreateFrame("Frame", nil, frame)
    empty.title = Theme.CreateLabel(empty, "normal", "text", "CENTER")
    empty.title:SetPoint("TOP", 0, -24)
    empty.title:SetText(L["Pick a few herbs or mine a few veins here and a route will show."])
    empty.count = Theme.CreateLabel(empty, "small", "muted", "CENTER")
    empty.count:SetPoint("TOP", empty.title, "BOTTOM", 0, -8)
    empty.best = Theme.CreateLabel(empty, "small", "text", "CENTER")
    empty.best:SetPoint("TOP", empty.count, "BOTTOM", 0, -16)
    empty.button = Widgets.CreateButton(empty, L["Show the Way"], function()
        local plan = GatherRouteUI.plan
        if plan and plan.best then Route():ShowZone(plan.best) end
    end, { primary = true, width = ButtonWidth(L["Show the Way"]), height = 20 })
    empty.button:SetPoint("TOP", empty.best, "BOTTOM", 0, -10)
    empty:Hide()
    self.empty = empty

    return frame
end

function GatherRouteUI:Row(index)
    local row = self.rows[index]
    if row then return row end
    row = CreateFrame("Frame", nil, self.list)
    row:SetHeight(self.ROW_H)
    row:EnableMouse(true)
    row:EnableMouseWheel(true)
    row:SetScript("OnMouseWheel", function(_, delta) GatherRouteUI:Scroll(delta) end)

    row.stripe = Theme.Fill(row, "glass")
    row.line = row:CreateTexture(nil, "BACKGROUND", nil, 1)
    row.line:SetPoint("BOTTOMLEFT")
    row.line:SetPoint("BOTTOMRIGHT")
    row.line:SetHeight(1)
    row.line:SetColorTexture(Theme.Unpack("border", 0.6))
    Widgets.RowLight(row)

    row.active = row:CreateTexture(nil, "OVERLAY", nil, 1)
    row.active:SetPoint("TOPLEFT")
    row.active:SetPoint("BOTTOMLEFT")
    row.active:SetWidth(2)
    row.active:SetColorTexture(Theme.Unpack("accentHi"))

    row.number = Theme.CreateLabel(row, "small", "accent", "CENTER")
    row.number:SetPoint("LEFT", 6, 0)
    row.number:SetWidth(18)
    row.check = row:CreateTexture(nil, "ARTWORK")
    row.check:SetSize(14, 14)
    row.check:SetTexture(CHECK)
    row.check:SetPoint("CENTER", row.number, "CENTER", 0, 0)

    row.icon = Theme.CreateItemIcon(row, ICON)
    row.icon:SetPoint("LEFT", 30, 0)
    row.name = Theme.CreateLabel(row, "small", "text")
    row.name:SetPoint("LEFT", 30 + ICON + 6, 0)
    row.away = Theme.CreateLabel(row, "small", "muted")
    row.away:SetPoint("LEFT", self.AWAY_X, 0)
    row.status = Theme.CreateLabel(row, "small", "text")
    row.status:SetPoint("LEFT", self.STATUS_X, 0)

    row:SetScript("OnEnter", function(self)
        if self.stop and not self.stop.next then Widgets.SetRowLight(self, 1) end
    end)
    row:SetScript("OnLeave", function(self) Widgets.SetRowLight(self, 0) end)

    self.rows[index] = row
    return row
end

--------------------------------------------------------------------------------
-- Drawing
--------------------------------------------------------------------------------

function GatherRouteUI:Scroll(delta)
    local plan = self.plan
    if not plan then return end
    local most = math.max(0, #plan.stops - (self.shownRows or 0))
    self.offset = math.max(0, math.min(most, (self.offset or 0) - delta))
    self.key = nil
    self:Update()
end

function GatherRouteUI:FillRow(row, stop, index, now)
    row.stop = stop
    row.stripe:SetColorTexture(Theme.Unpack(stop.next and "glassActive"
        or (index % 2 == 1 and "glass" or "glassAlt")))
    row.active:SetShown(stop.next and true or false)
    Widgets.SetRowLight(row, 0)

    if stop.done then
        row.number:SetText("")
        row.check:Show()
    else
        row.number:SetText(tostring(stop.n))
        row.check:Hide()
    end
    local item = ns.MapMarkers and ns.MapMarkers.SpotItem and ns.MapMarkers:SpotItem(stop.spot)
    Theme.SetItemIcon(row.icon, item)
    row.name:SetText(stop.spot.node or "?")
    local tier = Route().TierColor(stop)
    if tier then
        row.name:SetTextColor(tier[1], tier[2], tier[3])
    else
        row.name:SetTextColor(Theme.Unpack(stop.next and "accentHi" or "text"))
    end
    row.away:SetText(stop.yards and L.Format("%d yd", stop.yards) or "")
    local words, color = Route().Status(stop, now)
    row.status:SetText(words)
    row.status:SetTextColor(Theme.Unpack(color))
    local alpha = stop.done and 0.55 or 1
    for _, region in ipairs({ row.number, row.check, row.icon, row.name, row.away, row.status }) do
        region:SetAlpha(alpha)
    end
end

--- Show or hide the view, and the Grind tab's own list with it.
function GatherRouteUI:Toggle(grinding, on)
    if not self.frame then return end
    self.frame:SetShown(on and true or false)
    if grinding then
        -- The list and its headings go while the route shows; turned off,
        -- the Grind tab lays its headings out again (PlaceHeadings).
        for _, piece in ipairs({ grinding.list, grinding.rule }) do
            if type(piece) == "table" and piece.SetShown then piece:SetShown(not on) end
        end
        if on then
            for _, label in pairs(type(grinding.headings) == "table" and grinding.headings or {}) do
                if type(label) == "table" and label.Hide then label:Hide() end
            end
            local buttons = type(grinding.sorter) == "table" and grinding.sorter.buttons
            for _, button in pairs(type(buttons) == "table" and buttons or {}) do
                if type(button) == "table" and button.Hide then button:Hide() end
            end
        end
    end
    if on then
        if not self.ticker and type(C_Timer) == "table" and type(C_Timer.NewTicker) == "function" then
            self.ticker = C_Timer.NewTicker(1, function()
                if GatherRouteUI.frame and GatherRouteUI.frame:IsShown() then GatherRouteUI:Update() end
            end)
        end
    elseif self.ticker then
        pcall(self.ticker.Cancel, self.ticker)
        self.ticker = nil
    end
end

local function Key(plan, now)
    local parts = { tostring(plan), tostring(plan.zone), tostring(plan.needs), tostring(#plan.stops),
        tostring(GatherRouteUI.offset), tostring(Route().Running()), tostring(Route().page),
        tostring(plan.leveling), tostring((Route().TrainText())) }
    for _, stop in ipairs(plan.stops) do
        local words = Route().Status(stop, now)
        parts[#parts + 1] = table.concat({ tostring(stop.yards), words, tostring(stop.next), tostring(stop.tier) }, ",")
    end
    for _, box in ipairs(GatherRouteUI.ticks or {}) do
        parts[#parts + 1] = tostring(box.getter())
    end
    return table.concat(parts, "|")
end

--- Draw the view. Returns the footer's words.
function GatherRouteUI:Update()
    if not self.frame then return "" end
    local plan = Route():Plan()
    self.plan = plan
    local now = Now()
    local key = Key(plan, now)
    if self.saveFarmButton then
        self.saveFarmButton:SetShown(ns.SavedFarms ~= nil and ns.SavedFarms.On() and Route().page ~= nil)
    end
    if key == self.key then return GatherRouteUI.FooterText(plan) end
    self.key = key

    self.head:SetText(GatherRouteUI.HeadText(plan))
    self.skills:SetText(Route().SkillLine())

    -- Tick boxes, Skins only for a skinner. A page's Route Mode picks
    -- the kind itself, so Herbs, Ore and Skins step aside there.
    local x = 0
    local top = -(self.HEAD_H + 4)
    local page = Route().page
    for _, box in ipairs(self.ticks) do
        box:SetChecked(box.getter())
        local shown
        if box == self.ticks.herbs or box == self.ticks.ore then
            shown = not page
        elseif box == self.ticks.skins then
            shown = not page and Route().KnowsSkinning()
        elseif box == self.ticks.leveling then
            shown = page ~= nil
        else
            shown = true
        end
        box:SetShown(shown)
        if shown then
            box:ClearAllPoints()
            box:SetPoint("TOPLEFT", x, top)
            x = x + box:GetWidth() + 14
        end
    end
    top = top - self.TICK_H

    local empty = plan.needs ~= nil
    self.empty:SetShown(empty)
    self.headings:SetShown(not empty)
    self.list:SetShown(not empty)
    self.foot:SetShown(not empty)
    local trainText, trainColor = Route().TrainText()
    local trainShown = (not empty) and GatherRouteUI.FillTrain(self.train, trainText, trainColor)
    self.train:SetShown(trainShown and true or false)

    -- The best zone strip, when there is a better one than here.
    local showBest = (not empty) and plan.best ~= nil
    self.best:SetShown(showBest)
    if showBest then
        self.best:ClearAllPoints()
        self.best:SetPoint("TOPLEFT", 0, top)
        self.best:SetPoint("TOPRIGHT", 0, top)
        self.best.text:SetText(GatherRouteUI.BestText(plan.best))
        top = top - self.BEST_H - 4
    end

    if empty then
        self.empty:ClearAllPoints()
        self.empty:SetPoint("TOPLEFT", 0, top)
        self.empty:SetPoint("BOTTOMRIGHT", 0, 0)
        self.empty.count:SetText(L.Format("You've gathered %d spots here so far. A route needs %d.",
            plan.spotsZone or 0, plan.needs))
        local best = plan.best
        self.empty.best:SetText(best and L.Format("Your best zone: %s, %d spots known.",
            ns.Spots.Show(best.zone), best.spots or 0) or "")
        self.empty.best:SetShown(best ~= nil)
        self.empty.button:SetShown(best ~= nil)
        for _, row in ipairs(self.rows) do row:Hide() end
        return GatherRouteUI.FooterText(plan)
    end

    self.headings:ClearAllPoints()
    self.headings:SetPoint("TOPLEFT", 0, top)
    self.headings:SetPoint("TOPRIGHT", 0, top)
    top = top - self.HEADING_H

    self.list:ClearAllPoints()
    self.list:SetPoint("TOPLEFT", 0, top)
    local below = self.FOOT_H + 4
    if trainShown then
        self.train:ClearAllPoints()
        self.train:SetPoint("BOTTOMLEFT", 0, below)
        self.train:SetPoint("BOTTOMRIGHT", 0, below)
        below = below + self.TRAIN_H + 4
    end
    self.list:SetPoint("BOTTOMRIGHT", 0, below)
    local height = self.list:GetHeight()
    if type(height) ~= "number" or height <= 0 then height = 10 * self.ROW_H end
    local fits = math.max(1, math.floor(height / self.ROW_H))
    self.shownRows = fits
    self.offset = math.max(0, math.min(self.offset or 0, #plan.stops - fits))

    local shown = 0
    for index = 1, fits do
        local stop = plan.stops[index + self.offset]
        local row = self:Row(index)
        if stop then
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", 0, -(index - 1) * self.ROW_H)
            row:SetPoint("TOPRIGHT", 0, -(index - 1) * self.ROW_H)
            self:FillRow(row, stop, index + self.offset, now)
            row:Show()
            shown = index
        else
            row:Hide()
        end
    end
    for index = math.max(shown, fits) + 1, #self.rows do self.rows[index]:Hide() end

    self.startButton:SetText(Route().Running() and L["Stop"] or L["Start Route"])
    self.loop:SetText(GatherRouteUI.LoopText(plan))
    return GatherRouteUI.FooterText(plan)
end
