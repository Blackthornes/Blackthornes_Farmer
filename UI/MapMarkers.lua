-- Blackthornes Farmer -- UI/MapMarkers.lua
-- Markers on the world map and the minimap where you gathered herbs and ore.
--
-- Trent's rules for these: they must never read as a node you can gather, and
-- a live node must always show over them. On the world map a marker is the
-- node's icon greyed out and faded, in a gold ring, with a green check in the
-- corner, at the bottom of the map's pins. On the minimap, where the game's
-- node blips are part of the map and every addon frame draws over them, a
-- marker is an empty gold frame with the check outside a corner, so a node
-- that has grown back shows through its middle. The longer ago the gather,
-- the fainter the marker. Hover one and it says what it was, how many times
-- you took it and when last.
--
-- The spots themselves are Logic/Gathering.lua's. This file only draws them,
-- and only the ones on the map you are looking at (world map) or standing on
-- (minimap). Each map has its own switch, both on unless turned off on the
-- settings page or with /farm markers.
--
-- Nothing here has a template or XML behind it: markers are plain frames
-- parented to the map's canvas and to the minimap, placed by hand. Every
-- client call is guarded, since nothing documents which of the map APIs this
-- client ships; a map this cannot read simply gets no markers.

local _, ns = ...

local MapMarkers = ns.NewModule("MapMarkers")

local Theme = ns.Theme
local Util = ns.Util

-- On screen, whatever the zoom. The minimap's is the outside of its frame;
-- the clear middle is a little smaller, and wider than the game's node blip.
local WORLD_SIZE = 18
local MINIMAP_SIZE = 20

-- The minimap is redrawn this often while you move, in seconds.
local MINIMAP_STEP = 0.1

-- At most this many markers on the minimap, nearest first.
local MINIMAP_MAX = 40

-- Fading with age: full strength for FRESH seconds, down to FADED_ALPHA by OLD.
local FRESH = 5 * 60
local OLD = 60 * 60
local FRESH_ALPHA = 0.95
local FADED_ALPHA = 0.5

local ICONS = {
    herb = [[Interface\Icons\INV_Misc_Flower_02]],
    ore = [[Interface\Icons\INV_Ore_Copper_01]],
}

-- A soft round alpha mask the game ships: it rounds the icon and, tinted,
-- makes the ring behind it.
local ROUND = [[Interface\CharacterFrame\TempPortraitAlphaMask]]
local CHECK = [[Interface\RaidFrame\ReadyCheck-Ready]]

MapMarkers.FRESH = FRESH
MapMarkers.OLD = OLD

--------------------------------------------------------------------------------
-- Switches
--------------------------------------------------------------------------------

function MapMarkers.WorldOn()
    return ns.db and ns.db.markersWorld ~= false
end

function MapMarkers.MinimapOn()
    return ns.db and ns.db.markersMinimap ~= false
end

function MapMarkers:SetWorld(on)
    ns.db.markersWorld = on and true or false
    self:Refresh()
end

function MapMarkers:SetMinimap(on)
    ns.db.markersMinimap = on and true or false
    self:Refresh()
end

--------------------------------------------------------------------------------
-- Words
--------------------------------------------------------------------------------

--- "just now", "12 min ago", "3 h ago", "2 days ago". Nil if unknown.
function MapMarkers.Ago(when, now)
    when, now = tonumber(when), tonumber(now)
    if not (when and now) then return nil end

    local seconds = math.max(0, now - when)

    if seconds < 60 then return "just now" end
    if seconds < 3600 then return ("%d min ago"):format(math.floor(seconds / 60)) end
    if seconds < 86400 then return ("%d h ago"):format(math.floor(seconds / 3600)) end

    local days = math.floor(seconds / 86400)
    return days == 1 and "yesterday" or ("%d days ago"):format(days)
end

--- How strongly to draw a spot last gathered at `when`.
function MapMarkers.AlphaFor(when, now)
    when, now = tonumber(when), tonumber(now)
    if not (when and now) then return FADED_ALPHA end

    local age = now - when
    if age <= FRESH then return FRESH_ALPHA end
    if age >= OLD then return FADED_ALPHA end

    local through = (age - FRESH) / (OLD - FRESH)
    return FRESH_ALPHA + (FADED_ALPHA - FRESH_ALPHA) * through
end

--------------------------------------------------------------------------------
-- A marker
--------------------------------------------------------------------------------

local function ShowTooltip(pin)
    local spot = pin.spot
    if not (spot and GameTooltip) then return end

    pcall(GameTooltip.SetOwner, GameTooltip, pin, "ANCHOR_RIGHT")

    GameTooltip:AddLine(spot.node or "Node", Theme.Unpack("accent"))

    local gathers = tonumber(spot.gathers) or 1
    local ago = MapMarkers.Ago(spot.last, ns.Gathering.Clock())
    local line = gathers == 1 and "Gathered" or ("Gathered %d times"):format(gathers)
    if ago then line = ("%s, last %s"):format(line, ago) end

    GameTooltip:AddLine(line, Theme.Unpack("text"))
    GameTooltip:Show()
end

local function HideTooltip()
    if GameTooltip then GameTooltip:Hide() end
end

--- Hover and the marker's check, shared by both kinds.
local function Complete(pin, size, corner)
    local badge = pin:CreateTexture(nil, "OVERLAY")
    badge:SetSize(math.ceil(size * 0.6), math.ceil(size * 0.6))
    badge:SetPoint("CENTER", pin, corner, 0, 0)
    badge:SetTexture(CHECK)
    pin.badge = badge

    if pin.hollow then
        -- A minimap marker takes the mouse only on its check, never over
        -- its clear middle: a node grown back in there keeps the game's own
        -- tooltip, and a click there still pings the minimap.
        local hit = CreateFrame("Frame", nil, pin)
        hit:SetAllPoints(badge)
        hit:EnableMouse(true)
        hit:SetScript("OnEnter", function() ShowTooltip(pin) end)
        hit:SetScript("OnLeave", HideTooltip)
        pin.hit = hit
    else
        pin:SetScript("OnEnter", ShowTooltip)
        pin:SetScript("OnLeave", HideTooltip)
    end
    pin:Hide()

    return pin
end

-- The minimap's own herb and ore blips are drawn by the minimap itself, as
-- part of its map, and anything an addon puts on the minimap is drawn over
-- that map: there is no layer between the two. So a marker there cannot sit
-- under a live node; it has to leave the node room to show. It is an empty
-- gold frame, four corner brackets round a clear middle wide enough for the
-- game's blip, with the check outside a corner. A node that has grown back
-- shows through the middle, untouched.
local BRACKET = 2

--- A minimap marker: gold corner brackets round an empty middle.
function MapMarkers.CreateFramePin(parent, size)
    local pin = CreateFrame("Frame", nil, parent)
    pin:SetSize(size, size)
    pin:EnableMouse(false)
    pin.hollow = true

    local arm = math.max(3, math.floor(size / 4))
    local r, g, b = Theme.Unpack("accent")
    local corners = {}

    for _, corner in ipairs({ "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT" }) do
        local across = pin:CreateTexture(nil, "ARTWORK")
        across:SetColorTexture(r, g, b, 1)
        across:SetSize(arm, BRACKET)
        across:SetPoint(corner)

        local down = pin:CreateTexture(nil, "ARTWORK")
        down:SetColorTexture(r, g, b, 1)
        down:SetSize(BRACKET, arm)
        down:SetPoint(corner)

        corners[#corners + 1] = across
        corners[#corners + 1] = down
    end

    pin.corners = corners
    return Complete(pin, math.floor(size * 0.7), "TOPRIGHT")
end

--- A world map marker: a greyed, faded node icon in a gold ring, checked.
function MapMarkers.CreatePin(parent, size)
    local pin = CreateFrame("Frame", nil, parent)
    pin:SetSize(size, size)
    pin:EnableMouse(true)

    local ring = pin:CreateTexture(nil, "BACKGROUND")
    ring:SetAllPoints(pin)
    ring:SetTexture(ROUND)
    ring:SetVertexColor(Theme.Unpack("accent"))

    local icon = pin:CreateTexture(nil, "ARTWORK")
    local inset = math.max(1, math.floor(size / 8))
    icon:SetPoint("TOPLEFT", inset, -inset)
    icon:SetPoint("BOTTOMRIGHT", -inset, inset)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    pcall(icon.SetMask, icon, ROUND)
    pcall(icon.SetDesaturated, icon, true)
    icon:SetVertexColor(0.8, 0.8, 0.8)

    pin.ring, pin.icon = ring, icon

    return Complete(pin, size, "BOTTOMRIGHT")
end

--- Point a marker at a spot.
function MapMarkers.Dress(pin, spot, now)
    pin.spot = spot
    if not pin.hollow then pin.icon:SetTexture(ICONS[spot.kind] or ICONS.herb) end
    pin:SetAlpha(MapMarkers.AlphaFor(spot.last, now))
end

--- A pool of markers under one parent, reused from one redraw to the next.
local function Pool(parent, size, create)
    return { parent = parent, size = size, create = create or MapMarkers.CreatePin,
        pins = {}, used = 0 }
end

local function Acquire(pool)
    pool.used = pool.used + 1
    local pin = pool.pins[pool.used]

    if not pin then
        pin = pool.create(pool.parent, pool.size)
        pool.pins[pool.used] = pin
    end

    return pin
end

--- Start a redraw. Markers are reused in place rather than hidden and shown
--- again, so one under the mouse keeps its tooltip while the minimap turns.
local function Begin(pool)
    pool.used = 0
end

--- End a redraw: put away whatever this one did not use.
local function Finish(pool)
    for index = pool.used + 1, #pool.pins do pool.pins[index]:Hide() end
end

local function Release(pool)
    Begin(pool)
    Finish(pool)
end

--------------------------------------------------------------------------------
-- World map
--------------------------------------------------------------------------------

--- The world map's canvas, the map it shows, and how far it is zoomed.
function MapMarkers:WorldView()
    local map = _G.WorldMapFrame
    if type(map) ~= "table" then return nil end

    local okShown, shown = pcall(map.IsShown, map)
    if not (okShown and shown) then return nil end

    local canvas
    if type(map.GetCanvas) == "function" then
        local ok, value = pcall(map.GetCanvas, map)
        if ok then canvas = value end
    end
    canvas = canvas or (map.ScrollContainer and map.ScrollContainer.Child)
    if type(canvas) ~= "table" then return nil end

    local mapID
    if type(map.GetMapID) == "function" then
        local ok, value = pcall(map.GetMapID, map)
        if ok then mapID = ns.Harvest.ReadableNumber(value) end
    end
    if not mapID then return nil end

    local scale = 1
    local scroll = map.ScrollContainer
    if type(scroll) == "table" and type(scroll.GetCanvasScale) == "function" then
        local ok, value = pcall(scroll.GetCanvasScale, scroll)
        scale = ok and ns.Harvest.ReadableNumber(value) or 1
    end
    if scale <= 0 then scale = 1 end

    local okW, width = pcall(canvas.GetWidth, canvas)
    local okH, height = pcall(canvas.GetHeight, canvas)
    width = okW and ns.Harvest.ReadableNumber(width) or nil
    height = okH and ns.Harvest.ReadableNumber(height) or nil
    if not (width and height and width > 0 and height > 0) then return nil end

    return { canvas = canvas, mapID = mapID, scale = scale, width = width, height = height }
end

function MapMarkers:DrawWorld()
    local view = self:WorldView()

    if not view then
        if self.worldPool then Release(self.worldPool) end
        self.worldKey = nil
        return
    end

    local key = ("%d:%s:%s:%s:%d"):format(view.mapID, view.scale, view.width,
        view.height, ns.Gathering.spotsVersion or 0)

    if key == self.worldKey and self.worldOn == MapMarkers.WorldOn() then return end
    self.worldKey, self.worldOn = key, MapMarkers.WorldOn()

    if not self.worldPool or self.worldPool.parent ~= view.canvas then
        if self.worldPool then Release(self.worldPool) end
        self.worldPool = Pool(view.canvas, WORLD_SIZE)
    end

    local pool = self.worldPool
    Begin(pool)

    if not MapMarkers.WorldOn() then return Finish(pool) end

    local now = ns.Gathering.Clock()
    -- The bottom of the canvas's own pins: whatever else the map shows, the
    -- game's or another addon's, draws over a spot you have already taken.
    local okLevel, level = pcall(view.canvas.GetFrameLevel, view.canvas)
    level = (okLevel and tonumber(level) or 1) + 1

    -- Same size on screen at any zoom: shrink the marker as the canvas grows,
    -- and place it in its own, smaller, units.
    local scale = 1 / view.scale

    for _, spot in ipairs(ns.Gathering:SpotsOn(view.mapID)) do
        local pin = Acquire(pool)
        MapMarkers.Dress(pin, spot, now)
        pin:SetScale(scale)
        pin:SetFrameLevel(level)
        pin:ClearAllPoints()
        pin:SetPoint("CENTER", view.canvas, "TOPLEFT",
            spot.x * view.width / scale, -spot.y * view.height / scale)
        pin:Show()
    end

    Finish(pool)
end

--------------------------------------------------------------------------------
-- Minimap
--------------------------------------------------------------------------------

-- How many yards from the centre to the edge of the minimap, by zoom level,
-- for a client without Minimap:GetViewRadius. The game's own figures.
local OUTDOOR_RADIUS = { [0] = 233.33, 200, 166.67, 133.33, 100, 66.67 }
local INDOOR_RADIUS = { [0] = 150, 120, 90, 60, 40, 25 }

--- Yards from the minimap's centre to its edge.
function MapMarkers.MinimapRadius()
    if not Minimap then return nil end

    if type(Minimap.GetViewRadius) == "function" then
        local ok, radius = pcall(Minimap.GetViewRadius, Minimap)
        radius = ok and ns.Harvest.ReadableNumber(radius) or nil
        if radius and radius > 0 then return radius end
    end

    local zoom = 0
    if type(Minimap.GetZoom) == "function" then
        local ok, value = pcall(Minimap.GetZoom, Minimap)
        zoom = ok and ns.Harvest.ReadableNumber(value) or 0
    end

    local indoors = false
    if type(IsIndoors) == "function" then
        local ok, value = pcall(IsIndoors)
        indoors = ok and value == true
    end

    local radii = indoors and INDOOR_RADIUS or OUTDOOR_RADIUS
    return radii[zoom] or radii[0]
end

--- Does the minimap turn with you, and which way are you facing (radians)?
local function Facing()
    if type(GetCVar) ~= "function" then return nil end

    local ok, rotate = pcall(GetCVar, "rotateMinimap")
    if not (ok and rotate == "1") then return nil end

    if type(GetPlayerFacing) ~= "function" then return nil end
    local gotFacing, facing = pcall(GetPlayerFacing)
    return gotFacing and ns.Harvest.ReadableNumber(facing) or nil
end

--- Is the minimap square? Some UI addons make it so.
local function IsSquare()
    if type(GetMinimapShape) ~= "function" then return false end
    local ok, shape = pcall(GetMinimapShape)
    return ok and shape == "SQUARE"
end

--- Where a spot sits on the minimap, in pixels from its centre, or nil when
--- it is off the edge. `player` is { mapID, x, y }.
function MapMarkers.MinimapOffset(spot, player, width, height, radius, facing, square, half)
    -- Yards east and north of you. Map y runs down the map, which is south.
    local east = (spot.x - player.x) * width
    local north = (player.y - spot.y) * height

    -- A turning minimap turns the world so that ahead of you is up.
    if facing then
        local c, s = math.cos(facing), math.sin(facing)
        east, north = east * c + north * s, north * c - east * s
    end

    -- Kept a marker's width inside the rim, so it never hangs off it.
    local reach = radius * 0.94

    if square then
        if math.abs(east) > reach or math.abs(north) > reach then return nil end
    elseif east * east + north * north > reach * reach then
        return nil
    end

    return east / radius * half, north / radius * half, east * east + north * north
end

function MapMarkers:DrawMinimap()
    if not Minimap then return end

    self.minimapPool = self.minimapPool or Pool(Minimap, MINIMAP_SIZE, MapMarkers.CreateFramePin)
    local pool = self.minimapPool
    Begin(pool)

    -- Whatever happens below, nothing left over from the last redraw stays.
    local ok, err = pcall(self.PlaceMinimap, self, pool)
    Finish(pool)
    if not ok then error(err, 0) end
end

function MapMarkers:PlaceMinimap(pool)
    if not MapMarkers.MinimapOn() then return end

    local mapID, px, py = ns.Harvest:PlayerMapPosition()
    if not mapID then return end

    local spots = ns.Gathering:SpotsOn(mapID)
    if #spots == 0 then return end

    local width, height = ns.Gathering.MapSize(mapID)
    local radius = MapMarkers.MinimapRadius()
    if not (width and radius) then return end

    local okWidth, size = pcall(Minimap.GetWidth, Minimap)
    size = okWidth and ns.Harvest.ReadableNumber(size) or nil
    if not size then return end

    local player = { x = px, y = py }
    local facing, square = Facing(), IsSquare()

    local near = {}
    for _, spot in ipairs(spots) do
        local ox, oy, distance = MapMarkers.MinimapOffset(spot, player, width, height,
            radius, facing, square, size / 2)
        if ox then near[#near + 1] = { spot = spot, x = ox, y = oy, distance = distance } end
    end

    table.sort(near, function(a, b) return a.distance < b.distance end)

    local now = ns.Gathering.Clock()
    -- Just above the minimap, so another addon's pins draw over these.
    local okLevel, level = pcall(Minimap.GetFrameLevel, Minimap)
    level = (okLevel and tonumber(level) or 1) + 1

    for index = 1, math.min(#near, MINIMAP_MAX) do
        local entry = near[index]
        local pin = Acquire(pool)
        MapMarkers.Dress(pin, entry.spot, now)
        pin:SetFrameLevel(level)
        pin:ClearAllPoints()
        pin:SetPoint("CENTER", Minimap, "CENTER", entry.x, entry.y)
        pin:Show()
    end
end

--------------------------------------------------------------------------------
-- Redrawing
--------------------------------------------------------------------------------

--- Draw both again: after a gather, a switch, or a clear.
function MapMarkers:Refresh()
    if not ns.db then return end
    self.worldKey = nil

    local ok, err = pcall(self.DrawWorld, self)
    if not ok then ns.Debug("world map markers:", tostring(err)) end

    ok, err = pcall(self.DrawMinimap, self)
    if not ok then ns.Debug("minimap markers:", tostring(err)) end
end

--- One tick of the driver: the world map when it changes, the minimap as you
--- move.
function MapMarkers:Step(elapsed)
    self.since = (self.since or 0) + (elapsed or 0)
    if self.since < MINIMAP_STEP then return end
    self.since = 0

    local ok, err = pcall(self.DrawWorld, self)
    if not ok then ns.Debug("world map markers:", tostring(err)) end

    ok, err = pcall(self.DrawMinimap, self)
    if not ok then ns.Debug("minimap markers:", tostring(err)) end
end

function MapMarkers:OnEnable()
    local driver = CreateFrame("Frame", nil, UIParent)
    driver:SetScript("OnUpdate", function(_, elapsed) MapMarkers:Step(elapsed) end)
    driver:Show()
    self.driver = driver
end

--------------------------------------------------------------------------------
-- Commands
--------------------------------------------------------------------------------

local function OnOff(on) return on and "on" or "off" end

local function Status()
    ns.Print(("gathered-node markers: world map %s, minimap %s. %s marked."):format(
        Util.Colored("accent", OnOff(MapMarkers.WorldOn())),
        Util.Colored("accent", OnOff(MapMarkers.MinimapOn())),
        Util.Plural(#ns.Gathering:Spots(), "spot")))
    ns.PrintRaw(Util.Colored("muted",
        "  /farm markers on|off, /farm markers map on|off, /farm markers minimap on|off"))
end

ns.RegisterCommand("markers", "gathered herb and ore markers on the maps (on, off, map, minimap)", function(rest)
    local argument = Util.Trim(rest):lower()
    local which, state = argument:match("^(%S+)%s*(%S*)$")

    if argument == "" then
        Status()
        return
    end

    if argument == "clear" then
        ns.Print(("this removes all %s from your maps, for good. Your gathering "
            .. "record stays. Type /farm markers clear confirm to do it."):format(
            Util.Plural(#ns.Gathering:Spots(), "marker")))
        return
    end

    if argument == "clear confirm" then
        local count = ns.Gathering:ClearSpots()
        ns.Print(("%s cleared from your maps."):format(Util.Plural(count, "marker")))
        return
    end

    if which == "on" or which == "off" then
        MapMarkers:SetWorld(which == "on")
        MapMarkers:SetMinimap(which == "on")
    elseif (which == "map" or which == "world") and (state == "on" or state == "off") then
        MapMarkers:SetWorld(state == "on")
    elseif which == "minimap" and (state == "on" or state == "off") then
        MapMarkers:SetMinimap(state == "on")
    end

    Status()
end)
