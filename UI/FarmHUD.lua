-- Blackthornes Farmer -- UI/FarmHUD.lua
-- The Farm HUD (a player asked, the owner said build it, 2026-11-26, from a
-- mockup whose words he approved): a see-through ring in the middle of the
-- screen that shows your own saved herb, ore and fishing spots around you,
-- like a big minimap you can see while you ride.
--
-- It is a flat picture on the screen. Nothing is drawn in the game world,
-- which Forever does not allow. North is up; the gold arrow in the middle
-- turns with you. A filled dot is a spot that should be back, a hollow one
-- a spot still growing back (Logic/Respawn.lua). Fishing spots never grow
-- back, so they stay filled. When a Gather Route runs, a gold dotted line
-- points at its next stop, named with how far it is.
--
-- The spots are the minimap markers' (MapMarkers:SpotsOn), so My
-- Professions Only counts here too. Off unless turned on (farmHud, saved
-- true only when on) on the Map page, with /farm hud or with its key. Its
-- size is farmHudSize (nil is Medium). It lets clicks through, but for its
-- small red close gem; it hides in fights and inside dungeons and raids.
--
-- Speed: nothing runs while it is off or hidden. While it shows, a short
-- list of the spots near you is made again only when you have moved
-- NEAR_MOVE yards or the spots change; each step only moves the dots already
-- made, and a step where nothing moved does nothing.

local ADDON, ns = ...
local L = ns.L

local FarmHUD = ns.NewModule("FarmHUD")

local Theme = ns.Theme

local MEDIA = ([[Interface\AddOns\%s\Media\Frame\]]):format(ADDON)
FarmHUD.MEDIA = MEDIA

FarmHUD.SIZES = { "small", "medium", "large" }
FarmHUD.PIXELS = { small = 300, medium = 420, large = 560 }

FarmHUD.REACH = 250       -- yards from the middle to the rim
FarmHUD.STEP = 0.2        -- seconds between looks while it shows
FarmHUD.MAX_DOTS = 60     -- the nearest this many spots are drawn
FarmHUD.NEAR_MOVE = 40    -- yards you move before the near list is made again
FarmHUD.NEAR_EXTRA = 80   -- yards past the rim the near list reaches
FarmHUD.DOT = 12          -- a dot's size at Medium, in pixels
FarmHUD.ROUTE_DASHES = 9

-- A spot's colour by kind, as on the mockup.
FarmHUD.COLORS = {
    herb = { 0.224, 0.827, 0.290 },
    ore = { 0.878, 0.627, 0.188 },
    fish = { 0.290, 0.659, 1.000 },
}

--------------------------------------------------------------------------------
-- Switches
--------------------------------------------------------------------------------

function FarmHUD.IsOn()
    return type(ns.db) == "table" and ns.db.farmHud == true
end

--- Turn it on or off. `quiet` leaves chat alone (the Settings box).
function FarmHUD:SetOn(on, quiet)
    if type(ns.db) ~= "table" then return end
    ns.db.farmHud = on and true or nil
    if not quiet then
        ns.Print(on and L["The Farm HUD is on."] or L["The Farm HUD is off."])
    end
    self:Update()
    if ns.SettingsUI and ns.SettingsUI.Refresh then pcall(ns.SettingsUI.Refresh, ns.SettingsUI) end
end

function FarmHUD:Toggle()
    self:SetOn(not FarmHUD.IsOn())
end

--- The size picked: "small", "medium" or "large".
function FarmHUD.Size()
    local size = type(ns.db) == "table" and ns.db.farmHudSize
    if FarmHUD.PIXELS[size] then return size end
    return "medium"
end

function FarmHUD.SizeName(size)
    if size == "small" then return L["Small"] end
    if size == "large" then return L["Large"] end
    return L["Medium"]
end

function FarmHUD:SetSize(size)
    if not FarmHUD.PIXELS[size] or type(ns.db) ~= "table" then return false end
    ns.db.farmHudSize = size ~= "medium" and size or nil
    if self.frame then self:Layout() end
    return true
end

--------------------------------------------------------------------------------
-- When it shows
--------------------------------------------------------------------------------

local function InCombat()
    if type(InCombatLockdown) == "function" then
        local ok, value = pcall(InCombatLockdown)
        if ok and value == true then return true end
    end
    if type(UnitAffectingCombat) == "function" then
        local ok, value = pcall(UnitAffectingCombat, "player")
        if ok and value == true then return true end
    end
    return false
end

local function InInstance()
    if type(IsInInstance) ~= "function" then return false end
    local ok, inside = pcall(IsInInstance)
    return ok and inside == true
end

--- On, out of a fight and out of dungeons and raids.
function FarmHUD:ShouldShow()
    if not FarmHUD.IsOn() then return false end
    if self.fighting or InCombat() then return false end
    return not InInstance()
end

--- Show or hide it as it should be, building it the first time.
function FarmHUD:Update()
    if not self:ShouldShow() then
        if self.frame then self.frame:Hide() end
        return
    end
    self:Build()
    self.key, self.near = nil, nil
    self.frame:Show()
    self:Draw()
end

--------------------------------------------------------------------------------
-- The ring
--------------------------------------------------------------------------------

local function Tex(parent, file, layer, sub)
    local tex = parent:CreateTexture(nil, layer or "ARTWORK", nil, sub)
    tex:SetTexture(MEDIA .. file)
    return tex
end

function FarmHUD:Build()
    if self.frame then return self.frame end

    local frame = CreateFrame("Frame", "BlackthornesFarmerHUD", UIParent)
    frame:SetFrameStrata("BACKGROUND")
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    -- Clicks go through to the game; only the close gem takes them.
    if frame.EnableMouse then frame:EnableMouse(false) end
    frame:Hide()

    frame.floor = Tex(frame, "HudDisc", "BACKGROUND")
    frame.floor:SetAllPoints()
    frame.floor:SetVertexColor(0, 0, 0, 0.18)

    local gold = Theme.colors.accentHi
    frame.rim = Tex(frame, "HudRing", "BORDER")
    frame.rim:SetAllPoints()
    frame.rim:SetVertexColor(gold[1], gold[2], gold[3], 0.7)

    frame.inner = {}
    for index = 1, 2 do
        local ring = Tex(frame, "HudDash", "BORDER")
        ring:SetVertexColor(gold[1], gold[2], gold[3], 0.25)
        frame.inner[index] = ring
    end

    frame.north = frame:CreateFontString(nil, "OVERLAY")
    frame.north:SetFont(Theme.FONT, 15, "OUTLINE")
    frame.north:SetTextColor(gold[1], gold[2], gold[3])
    frame.north:SetText(L["N"])

    frame.dashes = {}
    for index = 1, FarmHUD.ROUTE_DASHES do
        local dash = Tex(frame, "HudDot", "ARTWORK", 1)
        dash:SetVertexColor(gold[1], gold[2], gold[3], 0.9)
        dash:Hide()
        frame.dashes[index] = dash
    end

    frame.nextRim = Tex(frame, "HudDot", "OVERLAY", 1)
    frame.nextRim:SetVertexColor(1, 1, 1, 1)
    frame.nextRim:Hide()
    frame.nextDot = Tex(frame, "HudDot", "OVERLAY", 2)
    frame.nextDot:Hide()

    frame.nextLabel = frame:CreateFontString(nil, "OVERLAY")
    frame.nextLabel:SetFont(Theme.FONT, 13, "OUTLINE")
    frame.nextLabel:SetTextColor(1, 1, 1)
    frame.nextLabel:Hide()

    frame.arrow = Tex(frame, "HudArrow", "OVERLAY", 3)
    frame.arrow:SetVertexColor(gold[1], gold[2], gold[3], 1)
    frame.arrow:SetPoint("CENTER", frame, "CENTER", 0, 0)

    -- The only part that takes a click: small floating things must close.
    if ns.Widgets and ns.Widgets.HeaderCloseGem then
        frame.close = ns.Widgets.HeaderCloseGem(frame, function() FarmHUD:SetOn(false) end, 18)
        if frame.close.SetAlpha then frame.close:SetAlpha(0.8) end
    end

    frame.dots = {}
    frame:SetScript("OnUpdate", function(_, elapsed) FarmHUD:Step(elapsed) end)

    self.frame = frame
    self:Layout()
    return frame
end

--- Size the ring and its parts for the size picked.
function FarmHUD:Layout()
    local frame = self.frame
    if not frame then return end
    local pixels = FarmHUD.PIXELS[FarmHUD.Size()]
    local scale = pixels / FarmHUD.PIXELS.medium
    frame:SetWidth(pixels)
    frame:SetHeight(pixels)
    self.half = pixels / 2
    self.dotSize = math.floor(FarmHUD.DOT * scale + 0.5)

    for index, ring in ipairs(frame.inner) do
        local across = pixels * index / 3
        ring:ClearAllPoints()
        ring:SetPoint("CENTER", frame, "CENTER", 0, 0)
        ring:SetSize(across, across)
    end

    frame.north:ClearAllPoints()
    frame.north:SetPoint("TOP", frame, "TOP", 0, -6 * scale)

    local dash = math.max(3, math.floor(3 * scale + 0.5))
    for _, piece in ipairs(frame.dashes) do piece:SetSize(dash, dash) end
    frame.nextRim:SetSize(self.dotSize + 8, self.dotSize + 8)
    frame.nextDot:SetSize(self.dotSize + 4, self.dotSize + 4)
    frame.arrow:SetSize(26 * scale, 26 * scale)

    if frame.close then
        -- On the rim, up and to the right.
        local out = self.half * 0.7071
        frame.close:ClearAllPoints()
        frame.close:SetPoint("CENTER", frame, "CENTER", out, out)
    end

    for _, dot in ipairs(frame.dots) do dot:SetSize(self.dotSize, self.dotSize) end
    self.key = nil
end

--------------------------------------------------------------------------------
-- Drawing
--------------------------------------------------------------------------------

local function Facing()
    if type(GetPlayerFacing) ~= "function" then return nil end
    local ok, facing = pcall(GetPlayerFacing)
    return ok and ns.Harvest.ReadableNumber(facing) or nil
end

--- Where a spot sits on the ring, in pixels from the middle (x east, y
--- north), and how far it is in yards. North is always up.
function FarmHUD.Offset(spot, px, py, width, height, half, reach)
    local east = (spot.x - px) * width
    local north = (py - spot.y) * height
    local yards = math.sqrt(east * east + north * north)
    return east / reach * half, north / reach * half, yards
end

--- The spots within reach of the ring and a little past it, made again only
--- after you move NEAR_MOVE yards or the spots change.
function FarmHUD:Near(mapID, px, py, width, height)
    local spots = ns.MapMarkers:SpotsOn(mapID)
    local near = self.near
    if near and near.map == mapID and near.spots == spots then
        local east = (px - near.x) * width
        local north = (py - near.y) * height
        if east * east + north * north < FarmHUD.NEAR_MOVE * FarmHUD.NEAR_MOVE then
            return near.list
        end
    end
    local limit = FarmHUD.REACH + FarmHUD.NEAR_EXTRA
    local list = {}
    for _, spot in ipairs(spots) do
        local east = (spot.x - px) * width
        local north = (py - spot.y) * height
        if east * east + north * north <= limit * limit then list[#list + 1] = spot end
    end
    self.near = { map = mapID, x = px, y = py, spots = spots, list = list }
    return list
end

--- The route's next stop: the one its plan picks now, as the Route list and
--- the minimap show it. The plan can pick a new stop on its own as you
--- move, before the stop it was aimed at is reached (Trent, 2026-11-26), so
--- run.aimed is only the fallback. Plan is kept a second at a time, so
--- asking each step costs little, and only while a route runs.
local function Aimed(mapID)
    local route = ns.GatherRoute
    local run = route and route.run
    if not run then return nil end
    local spot
    if type(route.Plan) == "function" then
        local ok, plan = pcall(route.Plan, route)
        local stop = ok and type(plan) == "table" and plan.nextStop
        spot = type(stop) == "table" and stop.spot or nil
    end
    spot = spot or run.aimed
    if type(spot) == "table" and spot.map == mapID and spot.x and spot.y then return spot end
    return nil
end

--- What the drawing depends on. Standing still with nothing new, it stays
--- the same and the step does nothing.
function FarmHUD:Key()
    local mapID, px, py = ns.Harvest:PlayerMapPosition()
    if not mapID then return "nowhere" end
    local now = ns.Gathering.Clock() or 0
    local _, stamp = ns.MapMarkers:ShownKinds()
    local aimed = Aimed(mapID)
    return ("%d|%s|%s|%s|%s|%s|%s|%d|%s"):format(mapID, tostring(px), tostring(py),
        tostring(Facing()), tostring(ns.Gathering.spotsVersion or 0), tostring(stamp),
        tostring(aimed), math.floor(now / 5), FarmHUD.Size())
end

function FarmHUD:Step(elapsed)
    self.since = (self.since or 0) + (elapsed or 0)
    if self.since < FarmHUD.STEP then return end
    self.since = 0
    local ok, err = pcall(self.Draw, self)
    if not ok then ns.Debug("farm HUD:", tostring(err)) end
end

local function Dot(frame, index, size)
    local dot = frame.dots[index]
    if not dot then
        dot = frame:CreateTexture(nil, "ARTWORK")
        dot:SetSize(size, size)
        frame.dots[index] = dot
    end
    return dot
end

function FarmHUD:Draw()
    local frame = self.frame
    if not (frame and frame:IsShown()) then return end

    local key = self:Key()
    if key == self.key then return end
    self.key = key

    local used = 0
    local aimed
    local mapID, px, py = ns.Harvest:PlayerMapPosition()
    local width, height
    if mapID then width, height = ns.Gathering.MapSize(mapID) end

    frame.arrow:SetRotation(Facing() or 0)

    if mapID and width and height then
        local half, reach = self.half, FarmHUD.REACH
        local edge = half - self.dotSize / 2
        local placed = {}
        for _, spot in ipairs(self:Near(mapID, px, py, width, height)) do
            local x, y, yards = FarmHUD.Offset(spot, px, py, width, height, half, reach)
            if x * x + y * y <= edge * edge then
                placed[#placed + 1] = { spot = spot, x = x, y = y, yards = yards }
            end
        end
        table.sort(placed, function(a, b) return a.yards < b.yards end)

        local now = ns.Gathering.Clock()
        for index = 1, math.min(#placed, FarmHUD.MAX_DOTS) do
            local entry = placed[index]
            used = index
            local dot = Dot(frame, index, self.dotSize)
            local back = FarmHUD.IsBack(entry.spot, now)
            dot:SetTexture(MEDIA .. (back and "HudDot" or "HudHollow"))
            local color = FarmHUD.COLORS[entry.spot.kind] or FarmHUD.COLORS.herb
            dot:SetVertexColor(color[1], color[2], color[3], back and 1 or 0.55)
            dot:ClearAllPoints()
            dot:SetPoint("CENTER", frame, "CENTER", entry.x, entry.y)
            dot:Show()
        end

        aimed = Aimed(mapID)
        if aimed then self:DrawRoute(aimed, px, py, width, height) end
    end

    for index = used + 1, #frame.dots do frame.dots[index]:Hide() end
    if not aimed then self:HideRoute() end
    self.shown = used
end

--- A spot is drawn filled when it should be back, or never grows back (a
--- fishing spot, or one whose grow-back time isn't learned yet).
function FarmHUD.IsBack(spot, now)
    local at = ns.Respawn and ns.Respawn:BackAt(spot) or nil
    if type(at) ~= "number" or type(now) ~= "number" then return true end
    return now >= at
end

function FarmHUD:HideRoute()
    local frame = self.frame
    for _, dash in ipairs(frame.dashes) do dash:Hide() end
    frame.nextRim:Hide()
    frame.nextDot:Hide()
    frame.nextLabel:Hide()
end

--- The gold dotted line to the route's next stop, held to the rim when the
--- stop is past it, and the stop's name with how far it is.
function FarmHUD:DrawRoute(spot, px, py, width, height)
    local frame = self.frame
    local half = self.half
    local x, y, yards = FarmHUD.Offset(spot, px, py, width, height, half, FarmHUD.REACH)
    local length = math.sqrt(x * x + y * y)
    local edge = half - self.dotSize
    if length > edge and length > 0 then
        x, y, length = x / length * edge, y / length * edge, edge
    end

    -- Dots from just past the arrow to the stop.
    local start = 18 * (half / (FarmHUD.PIXELS.medium / 2))
    local count = #frame.dashes
    for index, dash in ipairs(frame.dashes) do
        local along = start + (length - start) * (index - 0.5) / count
        if length > start and length > 0 then
            dash:ClearAllPoints()
            dash:SetPoint("CENTER", frame, "CENTER", x / length * along, y / length * along)
            dash:Show()
        else
            dash:Hide()
        end
    end

    local color = FarmHUD.COLORS[spot.kind] or FarmHUD.COLORS.herb
    frame.nextDot:SetVertexColor(color[1], color[2], color[3], 1)
    for _, piece in ipairs({ frame.nextRim, frame.nextDot }) do
        piece:ClearAllPoints()
        piece:SetPoint("CENTER", frame, "CENTER", x, y)
        piece:Show()
    end

    frame.nextLabel:SetText(L.Format("%s, %d yards", tostring(spot.node or ""),
        math.floor(yards + 0.5)))
    frame.nextLabel:ClearAllPoints()
    if x >= 0 then
        frame.nextLabel:SetPoint("BOTTOMLEFT", frame, "CENTER", x + 8, y + 6)
    else
        frame.nextLabel:SetPoint("BOTTOMRIGHT", frame, "CENTER", x - 8, y + 6)
    end
    frame.nextLabel:Show()
end

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------

function FarmHUD:OnEnable()
    ns.RegisterEvent(self, "PLAYER_REGEN_DISABLED", function()
        FarmHUD.fighting = true
        FarmHUD:Update()
    end)
    ns.RegisterEvent(self, "PLAYER_REGEN_ENABLED", function()
        FarmHUD.fighting = false
        FarmHUD:Update()
    end)
    ns.RegisterEvent(self, "PLAYER_ENTERING_WORLD", function() FarmHUD:Update() end)
    ns.RegisterEvent(self, "ZONE_CHANGED_NEW_AREA", function() FarmHUD:Update() end)
    self:Update()
end

--------------------------------------------------------------------------------
-- The key and the command
--------------------------------------------------------------------------------

_G.BINDING_NAME_BLACKTHORNESFARMER_HUD = L["Show or Hide Farm HUD"]

ns.RegisterCommand("hud", L["Show or Hide Farm HUD"], function(rest)
    local argument = (rest or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    local which, state = argument:match("^(%S+)%s*(%S*)$")
    if argument == "" then
        FarmHUD:Toggle()
    elseif which == "on" or which == "off" then
        FarmHUD:SetOn(which == "on")
    elseif which == "size" and FarmHUD:SetSize(state) then
        ns.Print(L["Farm HUD Size:"] .. " " .. FarmHUD.SizeName(FarmHUD.Size()))
    else
        ns.PrintRaw("  /farm hud, /farm hud on|off, /farm hud size small|medium|large")
    end
end)
