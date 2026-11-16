-- Blackthornes -- UI/RouteMap.lua
-- The Gather Route (Logic/GatherRoute.lua) drawn on the world map and the
-- minimap while "Draw on Maps:" is ticked: a gold line over a dark one
-- through the stops in order and back to the first, grey dashes into a
-- stop still growing back, a dot at each stop (bigger at the next one),
-- and a small YOUR ROUTE key in the map's corner. On the minimap, a line
-- from you to the next stop and on to the few after it, cut at the rim,
-- with a thin hollow gold ring at each stop that is up. The minimap draws
-- its own herb and ore blips under every addon frame, so the ring keeps
-- its middle clear and the line stops at its edge: the blip shows inside
-- (the owner said build it, 2026-11-16, from the mockup).
-- The owner said build it (2026-11-15) from the mockup.
--
-- Our own frames only: a layer over the world map's canvas (just under the
-- gathered-node markers, as TravelMap's), a key on the map's scroll area
-- and a layer on the minimap. No Blizzard frame is touched. Never drawn in
-- a fight. Drawn again only when its key (map, size, plan, where you stand
-- by MOVED yards, the minimap's zoom and turn) changes.

local addonName, ns = ...

local RouteMap = ns.NewModule("RouteMap")

local DOT = "Interface\\AddOns\\" .. tostring(addonName) .. "\\Media\\Frame\\TravelDot.tga"

local GOLD = { 1, 0.82, 0.3, 0.95 }
local GREY = { 0.62, 0.62, 0.62, 0.85 }
local DARK = { 0, 0, 0, 0.7 }
-- World map line widths as a share of the map's width.
local GOLD_WIDTH, DARK_WIDTH = 0.0028, 0.006
-- Grey dashes as a share of the map's width: drawn, gap.
RouteMap.DASH = { 0.006, 0.006 }
-- Most world map pieces.
RouteMap.MAX_PIECES = 600
-- Stops ahead drawn on the minimap after the next one.
RouteMap.MINIMAP_AHEAD = 2
-- Minimap line widths in pixels.
local MINI_GOLD, MINI_DARK = 2, 4
-- Minimap stop rings: radius in pixels (next stop, the ones after), the
-- pieces round, and the widths. Wide enough for the game's blip inside.
RouteMap.RING_NEXT, RouteMap.RING_AHEAD = 9, 7
RouteMap.RING_PIECES = 16
local RING_GOLD, RING_DARK = 1.5, 3
-- Yards you move before the lines are drawn again.
RouteMap.MOVED = 8
-- Seconds between looks.
local LOOK = 0.5
-- Frame level over the world map's canvas, as TravelMap's.
RouteMap.WORLD_ABOVE = 2
-- Frame level over the minimap, under Farmer's own markers.
RouteMap.MINIMAP_ABOVE = 2

local function InFight()
    return type(InCombatLockdown) == "function" and InCombatLockdown() == true
end

local function Number(value)
    if ns.Harvest and ns.Harvest.ReadableNumber then return ns.Harvest.ReadableNumber(value) end
    return tonumber(value)
end

--- The plan when the route should be drawn, else nil.
function RouteMap.Plan()
    local route = ns.GatherRoute
    if not (route and route.IsOn() and route.DrawsOnMaps()) then return nil end
    -- Only once Route Mode showed a route for a page.
    if not route.page then return nil end
    local ok, plan = pcall(route.Plan, route)
    if not ok or type(plan) ~= "table" or not plan.map then return nil end
    if #(plan.stops or {}) < 2 then return nil end
    return plan
end

--- The world map's legs: { { x1, y1, x2, y2, up, stop } } through the
--- stops in order and back to the first. `up` is the stop it goes into.
function RouteMap.Legs(plan)
    local legs = {}
    local stops = plan and plan.stops or {}
    local count = #stops
    if count < 2 then return legs end
    for index = 1, count do
        local from = stops[index].spot
        local stop = stops[index % count + 1]
        local to = stop.spot
        legs[#legs + 1] = { from.x, from.y, to.x, to.y, up = stop.back and true or false, stop = stop }
    end
    return legs
end

--- Dashes along a line, as { x1, y1, x2, y2 } in map shares.
function RouteMap.Dashes(x1, y1, x2, y2, aspect)
    aspect = aspect or 1
    local dx, dy = x2 - x1, (y2 - y1) * aspect
    local length = math.sqrt(dx * dx + dy * dy)
    if length <= 0 then return {} end
    local pieces = {}
    local drawn, gap = RouteMap.DASH[1], RouteMap.DASH[2]
    local along = 0
    while along < length and #pieces < RouteMap.MAX_PIECES do
        local stop = math.min(length, along + drawn)
        local a, b = along / length, stop / length
        pieces[#pieces + 1] = { x1 + (x2 - x1) * a, y1 + (y2 - y1) * a, x1 + (x2 - x1) * b, y1 + (y2 - y1) * b }
        along = along + drawn + gap
    end
    return pieces
end

--- Yards east and north of you for a spot, turned with the minimap.
function RouteMap.Offset(x, y, px, py, width, height, facing)
    local east = (x - px) * width
    local north = (py - y) * height
    if facing then
        local c, s = math.cos(facing), math.sin(facing)
        east, north = east * c + north * s, north * c - east * s
    end
    return east, north
end

--- A line cut to what the minimap shows (`reach` yards from you, round or
--- square), or nil when none of it shows.
function RouteMap.Clip(x1, y1, x2, y2, reach, square)
    local dx, dy = x2 - x1, y2 - y1
    local t0, t1 = 0, 1
    if square then
        local checks = { { -dx, x1 + reach }, { dx, reach - x1 }, { -dy, y1 + reach }, { dy, reach - y1 } }
        for _, check in ipairs(checks) do
            local p, q = check[1], check[2]
            if p == 0 then
                if q < 0 then return nil end
            else
                local r = q / p
                if p < 0 then
                    if r > t1 then return nil end
                    if r > t0 then t0 = r end
                else
                    if r < t0 then return nil end
                    if r < t1 then t1 = r end
                end
            end
        end
    else
        local a = dx * dx + dy * dy
        local b = 2 * (x1 * dx + y1 * dy)
        local c = x1 * x1 + y1 * y1 - reach * reach
        if a == 0 then
            if c > 0 then return nil end
        else
            local d = b * b - 4 * a * c
            if d < 0 then return nil end
            d = math.sqrt(d)
            local enter, leave = (-b - d) / (2 * a), (-b + d) / (2 * a)
            if enter > t0 then t0 = enter end
            if leave < t1 then t1 = leave end
            if t0 > t1 then return nil end
        end
    end
    return x1 + dx * t0, y1 + dy * t0, x1 + dx * t1, y1 + dy * t1
end

--------------------------------------------------------------------------------
-- Layers
--------------------------------------------------------------------------------

local function NewLayer(parent)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetAllPoints(parent)
    frame:EnableMouse(false)
    return { frame = frame, parent = parent, lines = {}, dots = {} }
end

local function Line(layer, index)
    local pair = layer.lines[index]
    if pair then return pair end
    if type(layer.frame.CreateLine) ~= "function" then return nil end
    local okDark, dark = pcall(layer.frame.CreateLine, layer.frame, nil, "OVERLAY", nil, 1)
    local okLine, line = pcall(layer.frame.CreateLine, layer.frame, nil, "OVERLAY", nil, 2)
    if not (okDark and dark and okLine and line) then return nil end
    dark:SetColorTexture(DARK[1], DARK[2], DARK[3], DARK[4])
    pair = { dark = dark, line = line }
    layer.lines[index] = pair
    return pair
end

local function Dot(layer, index)
    local dot = layer.dots[index]
    if not dot then
        dot = layer.frame:CreateTexture(nil, "OVERLAY", nil, 3)
        dot:SetTexture(DOT)
        layer.dots[index] = dot
    end
    return dot
end

local function Trim(layer, lines, dots)
    if not layer then return end
    for index = (lines or 0) + 1, #layer.lines do
        layer.lines[index].dark:Hide()
        layer.lines[index].line:Hide()
    end
    for index = (dots or 0) + 1, #layer.dots do layer.dots[index]:Hide() end
end

-- One line piece: `colour` over the dark edge (none for a dash).
local function Piece(layer, index, x1, y1, x2, y2, colour, thick, darkThick, anchor, point)
    local pair = Line(layer, index)
    if not pair then return false end
    pair.line:SetColorTexture(colour[1], colour[2], colour[3], colour[4])
    for _, line in ipairs({ pair.dark, pair.line }) do
        line:SetStartPoint(point, anchor, x1, y1)
        line:SetEndPoint(point, anchor, x2, y2)
        line:SetThickness(line == pair.dark and darkThick or thick)
    end
    if darkThick > 0 then pair.dark:Show() else pair.dark:Hide() end
    pair.line:Show()
    return true
end

--------------------------------------------------------------------------------
-- World map
--------------------------------------------------------------------------------

function RouteMap:ClearWorld()
    Trim(self.world, 0, 0)
    if self.key then self.key:Hide() end
    self.worldKey = nil
end

-- The key in the map's corner: YOUR ROUTE, the two line kinds, the next stop.
function RouteMap:Key(map)
    local key = self.keyCard
    local container = rawget(map, "ScrollContainer")
    local corner = type(container) == "table" and container or map
    if key and key.corner == corner then return key end
    local L, Theme = ns.L, ns.Theme
    key = CreateFrame("Frame", nil, corner)
    key.corner = corner
    key:EnableMouse(false)
    key:SetFrameStrata("HIGH")
    key:SetPoint("BOTTOMLEFT", corner, "BOTTOMLEFT", 12, 12)
    if Theme and Theme.Fill then Theme.Fill(key, "glass") end
    if Theme and Theme.Border then Theme.Border(key, "borderLit") end
    local function Label(size, colour)
        if Theme and Theme.CreateLabel then return Theme.CreateLabel(key, size, colour) end
        return key:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    end
    key.title = Label("tiny", "accent")
    key.title:SetPoint("TOPLEFT", 10, -8)
    key.title:SetText(L["YOUR ROUTE"])
    key.goldLine = key:CreateTexture(nil, "ARTWORK")
    key.goldLine:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 1)
    key.goldLine:SetSize(18, 2)
    key.goldLine:SetPoint("TOPLEFT", 10, -28)
    key.up = Label("small", "text")
    key.up:SetPoint("LEFT", key.goldLine, "RIGHT", 6, 0)
    key.up:SetText(L["Spots that should be up"])
    key.greyLine = key:CreateTexture(nil, "ARTWORK")
    key.greyLine:SetColorTexture(GREY[1], GREY[2], GREY[3], 1)
    key.greyLine:SetSize(18, 2)
    key.greyLine:SetPoint("TOPLEFT", 10, -46)
    key.down = Label("small", "muted")
    key.down:SetPoint("LEFT", key.greyLine, "RIGHT", 6, 0)
    key.down:SetText(L["Still growing back"])
    key.next = Label("small", "accentHi")
    key.next:SetPoint("TOPLEFT", 10, -60)
    key.next:SetJustifyH("LEFT")
    self.keyCard = key
    return key
end

function RouteMap:ShowKey(map, plan)
    local key = self:Key(map)
    local stop = plan.nextStop
    if stop then
        key.next:SetText(ns.L.Format("Next stop: %d, %s", stop.n, tostring(stop.spot.node or "")))
        key.next:Show()
    else
        key.next:SetText("")
        key.next:Hide()
    end
    local wide = 0
    for _, label in ipairs({ key.title, key.up, key.down, key.next }) do
        local ok, w = pcall(label.GetStringWidth, label)
        w = ok and tonumber(w) or 0
        if label == key.up or label == key.down then w = w + 24 end
        if w > wide then wide = w end
    end
    key:SetSize(math.max(140, wide + 22), stop and 80 or 62)
    key:Show()
end

function RouteMap:DrawWorld(plan)
    local view = ns.TravelMap and ns.TravelMap.WorldView and ns.TravelMap.WorldView()
    if not (plan and view and view.mapID == plan.map) then
        self:ClearWorld()
        return
    end
    local mapID, px, py = ns.Harvest:PlayerMapPosition()
    local moved = RouteMap.MOVED
    local yardsX, yardsY = ns.Gathering.MapSize(plan.map)
    local hereKey = "-"
    if mapID == plan.map and px and yardsX then
        hereKey = math.floor(px * yardsX / moved) .. "," .. math.floor(py * yardsY / moved)
    end
    local parts = { view.mapID, view.width, view.height, ns.GatherRoute.version, hereKey }
    for _, stop in ipairs(plan.stops) do
        parts[#parts + 1] = (stop.back and "u" or "d") .. (stop.done and "x" or "") .. (stop.next and "n" or "")
    end
    local key = table.concat(parts, ":")
    if key == self.worldKey and self.world and self.world.frame:IsShown() then return end
    self.worldKey = key

    local canvas = view.canvas
    if not self.world or self.world.parent ~= canvas then
        if self.world then Trim(self.world, 0, 0) self.world.frame:Hide() end
        self.world = NewLayer(canvas)
    end
    local layer = self.world
    local base = ns.TravelMap.BaseLevel(canvas)
    pcall(layer.frame.SetFrameLevel, layer.frame, base + RouteMap.WORLD_ABOVE)
    layer.frame:Show()

    local width, height = view.width, view.height
    local aspect = height / width
    local lines, dots = 0, 0
    for _, leg in ipairs(RouteMap.Legs(plan)) do
        local pieces = leg.up and { { leg[1], leg[2], leg[3], leg[4] } }
            or RouteMap.Dashes(leg[1], leg[2], leg[3], leg[4], aspect)
        for _, p in ipairs(pieces) do
            if lines >= RouteMap.MAX_PIECES then break end
            if not Piece(layer, lines + 1, p[1] * width, -p[2] * height, p[3] * width, -p[4] * height,
                leg.up and GOLD or GREY, width * GOLD_WIDTH, leg.up and width * DARK_WIDTH or 0,
                layer.frame, "TOPLEFT") then break end
            lines = lines + 1
        end
    end
    for _, stop in ipairs(plan.stops) do
        dots = dots + 1
        local dot = Dot(layer, dots)
        local size = width * (stop.next and 0.018 or 0.011)
        dot:SetSize(size, size)
        local colour = stop.back and GOLD or GREY
        dot:SetVertexColor(colour[1], colour[2], colour[3], stop.done and 0.5 or 1)
        dot:ClearAllPoints()
        dot:SetPoint("CENTER", layer.frame, "TOPLEFT", stop.spot.x * width, -stop.spot.y * height)
        dot:Show()
    end
    Trim(layer, lines, dots)
    self:ShowKey(_G.WorldMapFrame, plan)
end

--------------------------------------------------------------------------------
-- Minimap
--------------------------------------------------------------------------------

local function Facing()
    if type(GetCVar) ~= "function" then return nil end
    local ok, rotate = pcall(GetCVar, "rotateMinimap")
    if not (ok and rotate == "1") then return nil end
    if type(GetPlayerFacing) ~= "function" then return nil end
    local gotFacing, facing = pcall(GetPlayerFacing)
    return gotFacing and Number(facing) or nil
end

local function IsSquare()
    if type(GetMinimapShape) ~= "function" then return false end
    local ok, shape = pcall(GetMinimapShape)
    return ok and shape == "SQUARE"
end

function RouteMap:ClearMinimap()
    Trim(self.mini, 0, 0)
    self.miniKey = nil
end

--- The stops the minimap follows: the next one and a few after it.
function RouteMap.Ahead(plan)
    local list = {}
    local stops = plan and plan.stops or {}
    local start = plan and plan.nextStop and plan.nextStop.n
    if not start then return list end
    local count = #stops
    for offset = 0, math.min(RouteMap.MINIMAP_AHEAD, count - 1) do
        list[#list + 1] = stops[(start - 1 + offset) % count + 1]
    end
    return list
end

--- A minimap dot only where something should be up to gather: never on a
--- stop you reached or picked, one resting, or one still growing back.
function RouteMap.ShowsDot(stop)
    return stop and stop.back == true and not stop.done and not stop.resting or false
end

--- The line from x1,y1 to x2,y2 cut `by` short at its far end; the start
--- itself when the line is shorter than that.
function RouteMap.ShortenTo(x1, y1, x2, y2, by)
    local dx, dy = x2 - x1, y2 - y1
    local length = math.sqrt(dx * dx + dy * dy)
    if length <= by then return x1, y1 end
    local keep = (length - by) / length
    return x1 + dx * keep, y1 + dy * keep
end

--- A ring as `count` straight pieces: { { x1, y1, x2, y2 }, ... }.
function RouteMap.Ring(cx, cy, radius, count)
    local pieces = {}
    for index = 0, count - 1 do
        local a, b = index / count * 2 * math.pi, (index + 1) / count * 2 * math.pi
        pieces[#pieces + 1] = { cx + radius * math.cos(a), cy + radius * math.sin(a),
            cx + radius * math.cos(b), cy + radius * math.sin(b) }
    end
    return pieces
end

function RouteMap:DrawMinimap(plan)
    local minimap = _G.Minimap
    local mapID, px, py = ns.Harvest:PlayerMapPosition()
    if not (plan and minimap and mapID and mapID == plan.map and px) then
        self:ClearMinimap()
        return
    end
    local radius = ns.MapMarkers and ns.MapMarkers.MinimapRadius()
    local okSize, size = pcall(minimap.GetWidth, minimap)
    size = okSize and Number(size) or nil
    local width, height = ns.Gathering.MapSize(mapID)
    if not (radius and size and width and height and radius > 0) then
        self:ClearMinimap()
        return
    end
    local facing, square = Facing(), IsSquare()
    local ahead = RouteMap.Ahead(plan)
    local parts = { mapID, ("%.4f"):format(px), ("%.4f"):format(py),
        tostring(facing and ("%.2f"):format(facing)), tostring(square), tostring(radius), tostring(size),
        ns.GatherRoute.version }
    for _, stop in ipairs(ahead) do parts[#parts + 1] = stop.n .. (RouteMap.ShowsDot(stop) and "u" or "d") end
    local key = table.concat(parts, "|")
    if key == self.miniKey then return end
    self.miniKey = key

    if not self.mini then
        self.mini = NewLayer(minimap)
        local okLevel, level = pcall(minimap.GetFrameLevel, minimap)
        pcall(self.mini.frame.SetFrameLevel, self.mini.frame, (okLevel and tonumber(level) or 1) + RouteMap.MINIMAP_ABOVE)
    end
    local layer = self.mini
    layer.frame:Show()
    local half = size / 2
    local reach = radius * 0.94
    local lines, dots = 0, 0
    local fromE, fromN = 0, 0
    for _, stop in ipairs(ahead) do
        local toE, toN = RouteMap.Offset(stop.spot.x, stop.spot.y, px, py, width, height, facing)
        local x1, y1, x2, y2 = RouteMap.Clip(fromE, fromN, toE, toN, reach, square)
        if x1 then
            local scale = half / radius
            local inside = x2 == toE and y2 == toN
            local ring = inside and RouteMap.ShowsDot(stop)
                and (stop.next and RouteMap.RING_NEXT or RouteMap.RING_AHEAD) or nil
            -- The line stops at the ring's edge, so the blip inside is clear.
            if ring then x2, y2 = RouteMap.ShortenTo(x1, y1, x2, y2, ring / scale) end
            if stop.back then
                if Piece(layer, lines + 1, x1 * scale, y1 * scale, x2 * scale, y2 * scale, GOLD,
                    MINI_GOLD, MINI_DARK, minimap, "CENTER") then lines = lines + 1 end
            else
                local length = math.sqrt((x2 - x1) ^ 2 + (y2 - y1) ^ 2) * scale
                local count = math.max(1, math.floor(length / 8))
                for index = 0, count - 1 do
                    local a, b = index / count, (index + 0.5) / count
                    if Piece(layer, lines + 1, (x1 + (x2 - x1) * a) * scale, (y1 + (y2 - y1) * a) * scale,
                        (x1 + (x2 - x1) * b) * scale, (y1 + (y2 - y1) * b) * scale, GREY,
                        MINI_GOLD, 0, minimap, "CENTER") then lines = lines + 1 end
                end
            end
            -- A hollow ring where the stop shows inside the rim.
            if ring then
                local cx, cy = toE * scale, toN * scale
                for _, piece in ipairs(RouteMap.Ring(cx, cy, ring, RouteMap.RING_PIECES)) do
                    if Piece(layer, lines + 1, piece[1], piece[2], piece[3], piece[4], GOLD,
                        RING_GOLD, RING_DARK, minimap, "CENTER") then lines = lines + 1 end
                end
            end
        end
        fromE, fromN = toE, toN
    end
    Trim(layer, lines, dots)
end

--------------------------------------------------------------------------------
-- Driver
--------------------------------------------------------------------------------

function RouteMap:Clear()
    self:ClearWorld()
    self:ClearMinimap()
end

function RouteMap:Draw()
    if InFight() then return end
    local plan = RouteMap.Plan()
    if not plan then
        self:Clear()
        return
    end
    self:DrawWorld(plan)
    self:DrawMinimap(plan)
end

--- Draw again at the next look, from scratch.
function RouteMap:Refresh()
    self.worldKey, self.miniKey = nil, nil
    if InFight() then return end
    local ok, err = pcall(self.Draw, self)
    if not ok and ns.Debug then ns.Debug("route map:", tostring(err)) end
end

function RouteMap:Step(elapsed)
    self.since = (self.since or 0) + (elapsed or 0)
    if self.since < LOOK then return end
    self.since = 0
    local route = ns.GatherRoute
    if not (route and route.IsOn() and route.DrawsOnMaps()) then
        if self.worldKey or self.miniKey or (self.keyCard and self.keyCard:IsShown()) then
            self:Clear()
        end
        return
    end
    local ok, err = pcall(self.Draw, self)
    if not ok and ns.Debug then ns.Debug("route map:", tostring(err)) end
end

function RouteMap:OnEnable()
    local driver = CreateFrame("Frame", nil, UIParent)
    driver:SetScript("OnUpdate", function(_, elapsed) RouteMap:Step(elapsed) end)
    driver:Show()
    self.driver = driver
end
