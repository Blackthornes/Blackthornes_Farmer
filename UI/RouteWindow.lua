local _, ns = ...
local L = ns.L

-- The small route window: floats on screen while a route runs with Route
-- Mode ticked, so you can see the next stops and skip one without opening
-- the Grind tab. On unless unticked ("Route Window:" under GATHER ROUTE on
-- the Map & goals page). Saved, account wide, never renamed:
-- `routeWindow` (nil off, true on), `routeWindowScale` (its size grip) and
-- `routeWindowSeeThrough` (Transparent, UI/SeeThrough.lua's "route").
-- Its spot is kept by SharedWindow.KeepSpot as "farmer.routewindow".
-- The close gem hides it until the next route starts. It redraws only
-- when what it shows changed, and never in a fight.

local RouteWindow = ns.NewModule("RouteWindow")
ns.RouteWindow = RouteWindow

RouteWindow.WIDTH = 300
RouteWindow.ROWS = 4            -- stops shown
RouteWindow.ROW_H = 24
RouteWindow.ICON = 18
RouteWindow.PAD = 8
RouteWindow.TICK_H = 22
RouteWindow.BUTTON_H = 24
RouteWindow.FOOT_H = 18
RouteWindow.LOOK = 1            -- seconds between redraws while it shows
RouteWindow.SPOT_KEY = "farmer.routewindow"

local Theme, Widgets = ns.Theme, ns.Widgets

local function Route() return ns.GatherRoute end

local function Fighting()
    return type(InCombatLockdown) == "function" and InCombatLockdown() and true or false
end

local function Now()
    return ns.Gathering and ns.Gathering.Clock and ns.Gathering.Clock() or nil
end

--- Ticked in Settings.
function RouteWindow.IsOn()
    return not (ns.db and ns.db.routeWindow == false)
end

function RouteWindow:SetOn(on)
    if not ns.db then return end
    if on then ns.db.routeWindow = nil else ns.db.routeWindow = false end
    self.closed = nil
    self:Refresh()
end

--- Should it be on screen: ticked, Route Mode on a page, a route running,
--- and not closed with its gem since the route started.
function RouteWindow:Wanted()
    if not RouteWindow.IsOn() then return false end
    local route = Route()
    if not (route and route.page and route.Running()) then return false end
    return not self.closed
end

--------------------------------------------------------------------------------
-- What it shows
--------------------------------------------------------------------------------

--- The next stops, starting at the one to go to, then the ones not done
--- yet in the loop's order, wrapping round; at most ROWS.
function RouteWindow.Stops(plan, most)
    local list = {}
    most = most or RouteWindow.ROWS
    local stops = plan and plan.stops
    local first = plan and plan.nextStop
    if type(stops) ~= "table" or not first then return list end
    local total = #stops
    local start = first.n or 1
    for i = 0, total - 1 do
        if #list >= most then break end
        local stop = stops[((start - 1 + i) % total) + 1]
        if stop and (stop == first or not stop.done) then list[#list + 1] = stop end
    end
    return list
end

--- The title: "ROUTE <zone>", folded "ROUTE <next stop>, 40 yd".
function RouteWindow.Title(plan, folded)
    local word = L["ROUTE"]
    if folded and plan and plan.nextStop then
        local stop = plan.nextStop
        local name = stop.spot and stop.spot.node or "?"
        if stop.yards then
            return L.Format("%s %s, %d yd", word, name, stop.yards)
        end
        return word .. " " .. name
    end
    local zone = plan and plan.zone
    if zone and ns.Spots and ns.Spots.Show then zone = ns.Spots.Show(zone) end
    if zone and zone ~= "" then return word .. " " .. zone end
    return word
end

--- A row's status words and colour key; "Should be up" reads green here.
function RouteWindow.Status(stop, now)
    local words, color = Route().Status(stop, now)
    if words == L["Should be up"] then color = "good" end
    return words, color
end

--------------------------------------------------------------------------------
-- Building
--------------------------------------------------------------------------------

local function Dress(frame, onClose)
    local back = Theme.Fill(frame, "window")
    local trim
    if ns.Titanforged then
        trim = ns.Titanforged:Dress(frame, { title = L["ROUTE"], close = onClose })
        local left, right, top, bottom = ns.Titanforged.Reach(trim)
        if frame.SetClampRectInsets then pcall(frame.SetClampRectInsets, frame, -left, right, top, -bottom) end
    else
        Theme.Border(frame, "borderLit")
    end
    frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    Widgets.ApplySize(frame, ns.db and ns.db.routeWindowScale)
    frame.sizeGrip = Widgets.CreateSizeGrip(frame, {
        below = trim and select(4, ns.Titanforged.Reach(trim)) or 0,
        get = function() return ns.db and ns.db.routeWindowScale end,
        save = function(percent) if ns.db then ns.db.routeWindowScale = percent end end,
    })
    return back, trim
end

function RouteWindow:MakeRow(index)
    local frame = self.frame
    local row = CreateFrame("Frame", nil, frame)
    row:SetHeight(self.ROW_H)
    row:SetPoint("TOPLEFT", self.PAD, -self.PAD - (index - 1) * self.ROW_H)
    row:SetPoint("TOPRIGHT", -self.PAD, -self.PAD - (index - 1) * self.ROW_H)
    row.stripe = row:CreateTexture(nil, "BACKGROUND")
    row.stripe:SetAllPoints()
    row.line = row:CreateTexture(nil, "BORDER")
    row.line:SetPoint("BOTTOMLEFT")
    row.line:SetPoint("BOTTOMRIGHT")
    row.line:SetHeight(1)
    row.line:SetColorTexture(Theme.Unpack("border", 0.6))
    row.active = row:CreateTexture(nil, "ARTWORK")
    row.active:SetPoint("TOPLEFT")
    row.active:SetPoint("BOTTOMLEFT")
    row.active:SetWidth(3)
    row.active:SetColorTexture(Theme.Unpack("accentHi"))
    if ns.SeeThrough then
        ns.SeeThrough:AddGlass("route", row.stripe)
        ns.SeeThrough:AddGlass("route", row.line)
        ns.SeeThrough:AddGlass("route", row.active, 0.6)
    end

    row.icon = Theme.CreateItemIcon(row, self.ICON)
    row.icon:SetPoint("LEFT", 6, 0)
    row.status = Theme.CreateLabel(row, "small", "text", "RIGHT")
    row.status:SetPoint("RIGHT", -4, 0)
    row.status:SetWidth(96)
    row.yards = Theme.CreateLabel(row, "small", "muted", "RIGHT")
    row.yards:SetPoint("RIGHT", row.status, "LEFT", -4, 0)
    row.yards:SetWidth(50)
    row.name = Theme.CreateLabel(row, "small", "text")
    row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
    row.name:SetPoint("RIGHT", row.yards, "LEFT", -4, 0)
    row.name:SetWordWrap(false)
    row:Hide()
    self.rows[index] = row
    return row
end

function RouteWindow:Build()
    if self.frame then return self.frame end
    local name = "BlackthornesFarmerRouteWindow"
    local frame = CreateFrame("Frame", name, UIParent)
    frame:SetSize(self.WIDTH, 200)
    frame:SetPoint("CENTER", 300, 120)
    frame:SetFrameStrata("MEDIUM")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:Hide()
    self.frame = frame
    self.rows = {}

    local back, trim = Dress(frame, function() RouteWindow:Close() end)
    self.trim = trim
    if ns.SeeThrough then ns.SeeThrough:AddGlass("route", back) end
    if ns.FoldWindow and ns.FoldWindow.Add then
        ns.FoldWindow:Add(frame, { onToggle = function() RouteWindow.key = nil; RouteWindow:Update() end })
    end

    for index = 1, self.ROWS do self:MakeRow(index) end

    local leveling = Widgets.CreateCheckbox(frame, L["Leveling Mode:"], function(on)
        local route = Route()
        local gives = route.PageGives()
        if gives then route:SetLeveling(gives, on) end
        RouteWindow.key = nil
        RouteWindow:Update()
    end, false)
    if ns.GatherRouteUI and ns.GatherRouteUI.TipLeveling then ns.GatherRouteUI.TipLeveling(leveling) end
    self.leveling = leveling

    self.skip = Widgets.CreateButton(frame, L["Skip Stop"], function()
        Route():Skip()
        RouteWindow.key = nil
        RouteWindow:Update()
    end, { primary = true, height = self.BUTTON_H })
    self.stop = Widgets.CreateButton(frame, L["Stop"], function()
        Route():Stop()
    end, { height = self.BUTTON_H })

    self.foot = Theme.CreateLabel(frame, "small", "muted")
    self.foot:SetHeight(self.FOOT_H)
    self.foot:SetWordWrap(true)

    if ns.GatherRouteUI and ns.GatherRouteUI.TrainBox then
        self.train = ns.GatherRouteUI.TrainBox(frame)
    end

    frame:SetScript("OnShow", function() RouteWindow:Watch(true) end)
    frame:SetScript("OnHide", function() RouteWindow:Watch(false) end)

    if ns.SeeThrough then ns.SeeThrough:Attach("route", frame) end
    if ns.SharedWindow and ns.SharedWindow.KeepSpot then
        ns.SharedWindow.KeepSpot(frame, self.SPOT_KEY)
    end
    return frame
end

--------------------------------------------------------------------------------
-- Drawing
--------------------------------------------------------------------------------

function RouteWindow:FillRow(row, stop, index, now)
    row.stripe:SetColorTexture(Theme.Unpack(stop.next and "glassActive"
        or (index % 2 == 1 and "glass" or "glassAlt")))
    row.active:SetShown(stop.next and true or false)
    local item = ns.MapMarkers and ns.MapMarkers.SpotItem and ns.MapMarkers:SpotItem(stop.spot)
    Theme.SetItemIcon(row.icon, item)
    row.name:SetText(stop.spot and stop.spot.node or "?")
    local tier = Route().TierColor(stop)
    if tier then
        row.name:SetTextColor(tier[1], tier[2], tier[3])
    else
        row.name:SetTextColor(Theme.Unpack("text"))
    end
    row.yards:SetText(stop.yards and L.Format("%d yd", stop.yards) or "")
    local words, color = RouteWindow.Status(stop, now)
    row.status:SetText(words)
    row.status:SetTextColor(Theme.Unpack(color))
    row:Show()
end

--- A key for what shows, so a redraw happens only when it moved.
function RouteWindow.Key(plan, stops, folded, now)
    local parts = { folded and "f" or "o", tostring(plan and plan.zone), tostring(plan and plan.leveling),
        tostring(plan and #(plan.stops or {})) }
    for _, stop in ipairs(stops) do
        local words = RouteWindow.Status(stop, now)
        parts[#parts + 1] = table.concat({ tostring(stop.spot and stop.spot.node), tostring(stop.n),
            tostring(stop.yards), tostring(stop.tier), tostring(stop.next), words }, ",")
    end
    parts[#parts + 1] = Route().FootText(plan)
    parts[#parts + 1] = tostring((Route().TrainText()))
    return table.concat(parts, "|")
end

function RouteWindow:Update()
    local frame = self.frame
    if not frame or not frame:IsShown() or Fighting() then return end
    local route = Route()
    local plan = route:Plan()
    local now = Now()
    local folded = ns.FoldWindow and ns.FoldWindow.IsFolded and ns.FoldWindow:IsFolded(frame) or false
    local stops = RouteWindow.Stops(plan)
    local key = RouteWindow.Key(plan, stops, folded, now)
    if key == self.key then return end
    self.key = key

    local title = RouteWindow.Title(plan, folded)
    if self.trim and self.trim.plate and self.trim.plate.SetTitle then self.trim.plate:SetTitle(title) end
    if folded then return end

    for index, row in ipairs(self.rows) do
        local stop = stops[index]
        if stop then self:FillRow(row, stop, index, now) else row:Hide() end
    end

    local pad, y = self.PAD, self.PAD + #stops * self.ROW_H + 4
    self.leveling:ClearAllPoints()
    self.leveling:SetPoint("TOPLEFT", pad, -y)
    self.leveling:SetChecked(route.LevelingOn())
    y = y + self.TICK_H + 2

    self.skip:ClearAllPoints()
    self.skip:SetPoint("TOPLEFT", pad, -y)
    self.stop:ClearAllPoints()
    self.stop:SetPoint("LEFT", self.skip, "RIGHT", 6, 0)
    y = y + self.BUTTON_H + 4

    local inner = self.WIDTH - pad * 2
    self.foot:ClearAllPoints()
    self.foot:SetPoint("TOPLEFT", pad, -y)
    self.foot:SetWidth(inner)
    self.foot:SetText(route.FootText(plan))
    local footH = math.max(self.FOOT_H, math.ceil(self.foot:GetStringHeight() or 0))
    y = y + footH + 2

    local trainText, trainColor = route.TrainText()
    local train = self.train
    if train and ns.GatherRouteUI.FillTrain(train, trainText, trainColor) then
        train:ClearAllPoints()
        train:SetPoint("TOPLEFT", pad, -y)
        train:SetWidth(inner)
        train:Show()
        y = y + (train:GetHeight() or 30) + 4
    elseif train then
        train:Hide()
    end
    frame:SetHeight(y + pad)
end

--- Show or hide it by what is wanted, then redraw. Called by GatherRoute
--- whenever the route moves.
function RouteWindow:Refresh()
    local route = Route()
    if not (route and route.Running()) then self.closed = nil end
    if Fighting() then self.waiting = true; return end
    if not self:Wanted() then
        if self.frame and self.frame:IsShown() then self.frame:Hide() end
        return
    end
    self:Build()
    if not self.frame:IsShown() then
        self.key = nil
        self.frame:Show()
    end
    self:Update()
end

--- The close gem: put away until the next route.
function RouteWindow:Close()
    self.closed = true
    if self.frame then self.frame:Hide() end
end

--- Back to its first place and size.
function RouteWindow:ResetPlace()
    if ns.db then ns.db.routeWindowScale = nil end
    if ns.db and type(ns.db.windowSpots) == "table" then ns.db.windowSpots[self.SPOT_KEY] = nil end
    local frame = self.frame
    if frame then
        Widgets.ApplySize(frame, 100)
        frame:ClearAllPoints()
        frame:SetPoint("CENTER", UIParent, "CENTER", 300, 120)
    end
end

function RouteWindow:Watch(on)
    if self.ticker then
        pcall(self.ticker.Cancel, self.ticker)
        self.ticker = nil
    end
    if on and type(C_Timer) == "table" and type(C_Timer.NewTicker) == "function" then
        self.ticker = C_Timer.NewTicker(self.LOOK, function() RouteWindow:Update() end)
    end
end

function RouteWindow:OnEnable()
    if ns.RegisterEvent then
        ns.RegisterEvent(self, "PLAYER_REGEN_ENABLED", function()
            if RouteWindow.waiting then
                RouteWindow.waiting = nil
                RouteWindow:Refresh()
            elseif RouteWindow.frame and RouteWindow.frame:IsShown() then
                RouteWindow.key = nil
                RouteWindow:Update()
            end
        end)
    end
    if ns.SharedWindow and ns.SharedWindow.AddSpotReset then
        pcall(ns.SharedWindow.AddSpotReset, "farmer.routewindow", function() RouteWindow:ResetPlace() end)
    end
end

ns.RegisterCommand("routewindow", L["the small route window: on, off or reset"], function(rest)
    local word = (rest or ""):lower():match("^%s*(%S*)")
    if word == "reset" then
        RouteWindow:ResetPlace()
        ns.Print(L["The route window is back in its first spot."])
        return
    elseif word == "on" or word == "off" then
        RouteWindow:SetOn(word == "on")
    elseif word == "" then
        RouteWindow:SetOn(not RouteWindow.IsOn())
    end
    if RouteWindow.IsOn() then
        ns.Print(L["The route window is on. It shows while a route is running."])
    else
        ns.Print(L["The route window is off."])
    end
    if ns.SettingsUI and ns.SettingsUI.Refresh then pcall(ns.SettingsUI.Refresh, ns.SettingsUI) end
end)
