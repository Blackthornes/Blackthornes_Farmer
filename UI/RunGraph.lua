--------------------------------------------------------------------------------
-- UI/RunGraph.lua
--
-- The run graph on Kills & Loot (the owner said build it, 2026-11-26, from
-- the mockup farmer-improve-4-run-graph-and-recap, and approved its words).
-- Under the title bar: gold an hour as the big number, how it stands
-- against your usual pace in this zone, and a small graph of the run with
-- a dashed line for your usual and a green dot for each good drop.
--
-- "Run Graph:" on the Kills page, on unless unticked (`runGraph`, false
-- when off; never rename it). Hidden in Slim Bar, Like Quest List and while
-- the panel is folded, and until the panel knows its gold an hour.
--
-- Built from what the panel already reads (its value and its clock, or the
-- session timer's run): a point at most once a minute, taken when the panel
-- redraws, never on a timer. Lines move only when a point is added.
--
-- Your usual here: every minute of play adds its time and gold to the zone
-- you are in, account wide in `zonePace[zone] = { s = seconds, c = copper }`
-- (never rename it). The line shows once USUAL_AFTER seconds were played in
-- the zone before this session.
--------------------------------------------------------------------------------

local _, ns = ...

local RunGraph = ns.NewModule("RunGraph")

local L = ns.L
local Theme = ns.Theme

--- Seconds between points.
RunGraph.STEP = 60
--- Gold an hour at a point is read over this many seconds back.
RunGraph.WINDOW = 600
--- A gap longer than this between points (away, or the panel was hidden)
--- adds nothing to your usual here.
RunGraph.GAP = 600
--- Seconds played in a zone before this session for its usual to show.
RunGraph.USUAL_AFTER = 1200
--- Points drawn at most, the run thinned to fit.
RunGraph.MAX = 40
--- Green drop dots kept.
RunGraph.DOTS = 5

-- The strip's rows.
local BIG = 28
local PLOT = 40
local AXIS = 14
RunGraph.HEIGHT = BIG + PLOT + AXIS + 6
local PADDING = 8
local BIG_SIZE = 20

function RunGraph.On()
    return not (ns.db and ns.db.runGraph == false)
end

function RunGraph:SetOn(on)
    if not ns.db then return end
    if on == false then ns.db.runGraph = false else ns.db.runGraph = nil end
    local ui = ns.TrackerUI
    if ui and ui.frame and ui.frame:IsShown() then ui:Refresh() end
end

--------------------------------------------------------------------------------
-- The points
--------------------------------------------------------------------------------

--- The run as the panel times it: seconds and copper, or nil before it
--- has a clock. The session timer's run while it is on.
function RunGraph.Read()
    local timer = ns.SessionTimer
    if timer and timer.On and timer.On() and timer.state ~= "ready" then
        local ok, seconds = pcall(timer.Seconds, timer)
        local okGain, copper = pcall(timer.Gained, timer)
        if ok and okGain and type(seconds) == "number" and type(copper) == "number" then
            return seconds, copper
        end
        return nil
    end
    local ui = ns.TrackerUI
    local started = ui and ui.startedAt
    local total = ns.Value and ns.Value.Session and ns.Value:Session()
    if type(started) ~= "number" or type(total) ~= "number" or type(GetTime) ~= "function" then
        return nil
    end
    local ok, now = pcall(GetTime)
    if not (ok and type(now) == "number") then return nil end
    return math.max(0, now - started), total
end

--- The zone you are in, or nil inside a pcall's refusal.
function RunGraph.Zone()
    if type(GetRealZoneText) ~= "function" then return nil end
    local ok, zone = pcall(function()
        local text = GetRealZoneText()
        if type(text) == "string" and text ~= "" then return text end
    end)
    return ok and zone or nil
end

--- Forget the run (a Clear panel, or the clock going back).
function RunGraph:Forget()
    self.points = nil
    self.dots = nil
    self.seen = nil
    self.version = (self.version or 0) + 1
end

--- What this session added to each zone's usual, kept apart so the usual
--- line is the play before it.
RunGraph.session = RunGraph.session or {}

local function AddPace(zone, seconds, copper)
    if not (zone and ns.db) then return end
    if type(ns.db.zonePace) ~= "table" then ns.db.zonePace = {} end
    local saved = ns.db.zonePace[zone]
    if type(saved) ~= "table" then
        saved = { s = 0, c = 0 }
        ns.db.zonePace[zone] = saved
    end
    saved.s = (tonumber(saved.s) or 0) + seconds
    saved.c = (tonumber(saved.c) or 0) + copper
    local mine = RunGraph.session[zone] or { s = 0, c = 0 }
    mine.s, mine.c = mine.s + seconds, mine.c + copper
    RunGraph.session[zone] = mine
end

--- Your usual gold an hour in `zone` before this session, or nil while
--- you have played there less than USUAL_AFTER seconds.
function RunGraph.UsualIn(zone)
    local saved = zone and ns.db and type(ns.db.zonePace) == "table" and ns.db.zonePace[zone]
    if type(saved) ~= "table" then return nil end
    local mine = RunGraph.session[zone] or { s = 0, c = 0 }
    local seconds = (tonumber(saved.s) or 0) - mine.s
    local copper = (tonumber(saved.c) or 0) - mine.c
    if seconds < RunGraph.USUAL_AFTER or copper < 0 then return nil end
    return copper / seconds * 3600
end

--- Take a point when the panel redraws: at most one a minute, the newest
--- numbers kept in the minute's point. A green drop gets a dot.
function RunGraph:Note()
    local seconds, copper = RunGraph.Read()
    if not seconds then
        if self.points then self:Forget() end
        return
    end
    local points = self.points
    local last = points and points[#points]
    if last and (seconds < last.s or copper < last.c) then
        self:Forget()
        points, last = nil, nil
    end
    if not points then
        points = { { s = 0, c = 0 } }
        self.points = points
        last = points[1]
    end

    -- The good drops, as the bar on Slim Bar sees them.
    local Slim = ns.SlimBar
    if Slim and Slim.Counts then
        local counts = Slim.Counts()
        if Slim.BestNew(self.seen, counts) then
            self.dots = self.dots or {}
            self.dots[#self.dots + 1] = seconds
            while #self.dots > RunGraph.DOTS do table.remove(self.dots, 1) end
            self.version = (self.version or 0) + 1
        end
        self.seen = counts
    end

    if seconds - last.s < RunGraph.STEP then
        if last.c ~= copper then
            -- The minute's point moves with it; its time stays.
            self.version = (self.version or 0) + 1
        end
        return
    end
    local gap = seconds - last.s
    if gap > 0 and gap <= RunGraph.GAP then AddPace(RunGraph.Zone(), gap, copper - last.c) end
    points[#points + 1] = { s = seconds, c = copper }
    self.version = (self.version or 0) + 1
end

--- Copper at `seconds`, read along the points.
local function CopperAt(points, seconds)
    if seconds <= points[1].s then return points[1].c end
    for index = 2, #points do
        local a, b = points[index - 1], points[index]
        if seconds <= b.s then
            if b.s == a.s then return b.c end
            return a.c + (b.c - a.c) * (seconds - a.s) / (b.s - a.s)
        end
    end
    return points[#points].c
end

--- The graph's line: { { s, rate } }, at most MAX, each the gold an hour
--- over the WINDOW before it. Nil with under two minutes of points.
function RunGraph:Series()
    local points = self.points
    if not points or #points < 3 then return nil end
    local count = math.min(#points - 1, RunGraph.MAX)
    local series = {}
    for step = 1, count do
        local index = 1 + math.floor(step * (#points - 1) / count + 0.5)
        index = math.max(2, math.min(#points, index))
        local point = points[index]
        local from = math.max(0, point.s - RunGraph.WINDOW)
        local span = point.s - from
        local rate = span > 0 and (point.c - CopperAt(points, from)) / span * 3600 or 0
        series[#series + 1] = { s = point.s, rate = math.max(0, rate) }
    end
    return series
end

--------------------------------------------------------------------------------
-- Drawing
--------------------------------------------------------------------------------

--- Whether the strip shows on the panel now.
function RunGraph:Shows(ui)
    if not RunGraph.On() or not ui or ui.folded or ui.glassBare then return false end
    if ns.SlimBar and ns.SlimBar.On() then return false end
    local perHour = ui.PerHour and ui:PerHour()
    return type(perHour) == "number"
end

function RunGraph:Build(parent)
    if self.strip then return self.strip end
    local strip = CreateFrame("Frame", nil, parent)
    strip:SetHeight(RunGraph.HEIGHT)

    strip.big = Theme.CreateLabel(strip, BIG_SIZE, "text")
    strip.big:SetPoint("TOPLEFT", strip, "TOPLEFT", PADDING + 2, -4)
    strip.versus = Theme.CreateLabel(strip, "small", "good", "RIGHT")
    strip.versus:SetPoint("RIGHT", strip, "TOPRIGHT", -PADDING, -BIG / 2 - 2)

    local plot = CreateFrame("Frame", nil, strip)
    plot:SetPoint("TOPLEFT", strip, "TOPLEFT", PADDING + 6, -BIG - 2)
    plot:SetPoint("TOPRIGHT", strip, "TOPRIGHT", -PADDING - 6, -BIG - 2)
    plot:SetHeight(PLOT)
    strip.plot = plot

    strip.lines, strip.wash, strip.dashes, strip.dots = {}, {}, {}, {}
    for index = 1, RunGraph.MAX - 1 do
        local line = plot.CreateLine and plot:CreateLine(nil, "ARTWORK", nil, 2)
        if line then
            line:SetColorTexture(Theme.Unpack("accentHi"))
            pcall(line.SetThickness, line, 2)
            line:Hide()
            strip.lines[index] = line
        end
        local wash = plot:CreateTexture(nil, "BORDER")
        wash:SetColorTexture(Theme.Unpack("accent", 0.22))
        wash:Hide()
        strip.wash[index] = wash
    end
    for index = 1, 40 do
        local dash = plot:CreateTexture(nil, "ARTWORK", nil, 1)
        dash:SetHeight(1)
        dash:SetWidth(4)
        dash:SetColorTexture(Theme.Unpack("muted", 0.8))
        dash:Hide()
        strip.dashes[index] = dash
    end
    for index = 1, RunGraph.DOTS do
        local dot = plot:CreateTexture(nil, "OVERLAY", nil, 3)
        dot:SetWidth(6)
        dot:SetHeight(6)
        dot:SetColorTexture(0.12, 1, 0, 1)
        dot:Hide()
        strip.dots[index] = dot
    end

    strip.start = Theme.CreateLabel(strip, "tiny", "dim")
    strip.start:SetPoint("BOTTOMLEFT", strip, "BOTTOMLEFT", PADDING + 2, 3)
    strip.start:SetText(L["Start"])
    strip.usual = Theme.CreateLabel(strip, "tiny", "muted")
    strip.usual:SetPoint("BOTTOM", strip, "BOTTOM", 0, 3)
    strip.length = Theme.CreateLabel(strip, "tiny", "dim", "RIGHT")
    strip.length:SetPoint("BOTTOMRIGHT", strip, "BOTTOMRIGHT", -PADDING, 3)

    strip:Hide()
    self.strip = strip
    return strip
end

--- "12% over your usual here", or under, or nil without a usual.
function RunGraph.VersusText(perHour, usual)
    if not (perHour and usual and usual > 0) then return nil, nil end
    local percent = math.floor((perHour / usual - 1) * 100 + 0.5)
    if percent >= 0 then return L.Format("%d%% over your usual here", percent), "good" end
    return L.Format("%d%% under your usual here", -percent), "muted"
end

--- The words on the strip's top line, and how wide the panel must be for
--- them. Read on every redraw; cheap.
function RunGraph:Words(ui)
    local perHour = ui:PerHour()
    local big = L.Format("%s an hour", ns.Value.Coins(math.floor((perHour or 0) + 0.5)))
    local usual = RunGraph.UsualIn(RunGraph.Zone())
    local versus, color = RunGraph.VersusText(perHour, usual)
    local needs = PADDING * 2 + 4 + Theme.TextWidth(BIG_SIZE, ns.Util.StripColor(big))
    if versus then needs = needs + 12 + Theme.TextWidth("small", versus) end
    return big, versus, color, usual, needs
end

--- How wide the panel must be for the strip, or 0 while it is hidden.
function RunGraph:Needs(ui)
    if not self:Shows(ui) then return 0 end
    local _, _, _, _, needs = self:Words(ui)
    return needs
end

local function Minutes(seconds)
    return L.Format("%d min", math.floor((tonumber(seconds) or 0) / 60 + 0.5))
end

--- Draw the strip at `width`. The lines move only when a point was added
--- or the width changed.
function RunGraph:Draw(ui, width)
    local strip = self:Build(ui.frame)
    local big, versus, color, usual = self:Words(ui)
    strip.big:SetText(big)
    strip.versus:SetText(versus or "")
    strip.versus:SetTextColor(Theme.Unpack(color or "muted"))
    strip:Show()

    local series = self:Series()
    local key = table.concat({ tostring(self.version), tostring(width), tostring(usual and math.floor(usual)) }, ":")
    if key == self.drawn then return end
    self.drawn = key

    local plotWidth = math.max(20, (tonumber(width) or 260) - PADDING * 2 - 12)
    for _, line in pairs(strip.lines) do line:Hide() end
    for _, wash in ipairs(strip.wash) do wash:Hide() end
    for _, dash in ipairs(strip.dashes) do dash:Hide() end
    for _, dot in ipairs(strip.dots) do dot:Hide() end

    local points = self.points
    local length = points and points[#points] and points[#points].s or 0
    strip.length:SetText(Minutes(length))
    strip.usual:SetText(usual and ("- - " .. L["your usual here"]) or "")

    if not series then return end
    local top = usual or 0
    for _, point in ipairs(series) do top = math.max(top, point.rate) end
    if top <= 0 then top = 1 end
    top = top * 1.15
    local span = math.max(1, length)

    local function X(seconds) return math.max(0, math.min(plotWidth, seconds / span * plotWidth)) end
    local function Y(rate) return math.max(1, math.min(PLOT - 1, rate / top * PLOT)) end

    local placed = {}
    for index, point in ipairs(series) do placed[index] = { x = X(point.s), y = Y(point.rate) } end
    if #placed == 1 then placed[2] = { x = plotWidth, y = placed[1].y } end
    table.insert(placed, 1, { x = 0, y = placed[1].y })

    for index = 1, math.min(#placed - 1, RunGraph.MAX - 1) do
        local a, b = placed[index], placed[index + 1]
        local line = strip.lines[index]
        if line then
            line:SetStartPoint("BOTTOMLEFT", strip.plot, a.x, a.y)
            line:SetEndPoint("BOTTOMLEFT", strip.plot, b.x, b.y)
            line:Show()
        end
        local wash = strip.wash[index]
        wash:ClearAllPoints()
        wash:SetPoint("BOTTOMLEFT", strip.plot, "BOTTOMLEFT", a.x, 0)
        wash:SetWidth(math.max(1, b.x - a.x + 0.5))
        wash:SetHeight(math.max(1, (a.y + b.y) / 2))
        wash:Show()
    end

    if usual then
        local y = Y(usual)
        for index, dash in ipairs(strip.dashes) do
            local x = (index - 1) * 8
            if x >= plotWidth then break end
            dash:ClearAllPoints()
            dash:SetPoint("BOTTOMLEFT", strip.plot, "BOTTOMLEFT", x, y)
            dash:Show()
        end
    end

    for index, seconds in ipairs(self.dots or {}) do
        local dot = strip.dots[index]
        if dot then
            -- On the line, where the drop fell.
            local y = placed[#placed].y
            for i = 2, #placed do
                local x = X(seconds)
                if placed[i].x >= x then
                    local a, b = placed[i - 1], placed[i]
                    local t = (b.x > a.x) and (x - a.x) / (b.x - a.x) or 1
                    y = a.y + (b.y - a.y) * t
                    break
                end
            end
            dot:ClearAllPoints()
            dot:SetPoint("CENTER", strip.plot, "BOTTOMLEFT", X(seconds), y)
            dot:Show()
        end
    end
end

function RunGraph:Hide()
    if self.strip then self.strip:Hide() end
end
