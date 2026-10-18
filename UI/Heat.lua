-- Blackthornes Farmer -- UI/Heat.lua
-- Draws Logic/Heat.lua's kill cells as a glow on the world map and the
-- minimap. A test feature, off unless ticked.
--
-- Each cell is one soft dot (Media/Frame/HeatDot.tga) coloured by how busy
-- it is next to your busiest cell, added together where they overlap, so
-- a crowd of kills glows hotter than a few. The world map's dots sit on a
-- frame of their own at the canvas's own level, under the gathered-node
-- markers and the game's pins, so a live node and the game's icons always
-- show over the glow. The minimap's are fainter still, since its blips are
-- part of the minimap and every addon frame draws over them. Nothing here
-- touches a Blizzard frame, and the world map is left alone in a fight.
--
-- Smooth play: a map is drawn again only when what it depends on changes,
-- and a long list of cells is placed a few a frame (SLICE). The minimap
-- is placed again only when you have moved a little, turned, or its zoom
-- changed.

local _, ns = ...

local HeatUI = ns.NewModule("HeatUI")

local Heat = ns.Heat

local DOT = [[Interface\AddOns\Blackthornes_Farmer\Media\Frame\HeatDot.tga]]

-- Dots placed a frame while a long list is laid out.
local SLICE = 150

-- Most dots on the world map (the busiest cells win), and on the minimap.
local MAX_WORLD = 2500
local MAX_MINIMAP = 200

-- A dot is this many cells across, so neighbours run together into a glow.
local SPREAD = 2.6

-- The least a dot is drawn, in pixels, on the minimap.
local MINIMAP_LEAST = 6

-- How often the minimap looks again while you move, in seconds.
local MINIMAP_STEP = 0.2

-- A cell's strongest and faintest alpha before the strength setting, and
-- the minimap's share of it.
local ALPHA_LOW, ALPHA_HIGH = 0.18, 0.7
local MINIMAP_SHARE = 0.5

--------------------------------------------------------------------------------
-- Dots
--------------------------------------------------------------------------------

local function NewLayer(parent, level)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetAllPoints(parent)
    frame:EnableMouse(false)
    if level then frame:SetFrameLevel(level) end
    return { frame = frame, dots = {}, used = 0 }
end

local function Dot(layer, index)
    local dot = layer.dots[index]
    if not dot then
        dot = layer.frame:CreateTexture(nil, "ARTWORK")
        dot:SetTexture(DOT)
        dot:SetBlendMode("ADD")
        layer.dots[index] = dot
    end
    return dot
end

--- Hide every dot past `used`.
local function Trim(layer, used)
    for index = used + 1, #layer.dots do layer.dots[index]:Hide() end
    layer.used = used
end

--- The share of the busiest cell a count is, eased so a few kills still show.
local function Share(count, highest)
    if highest <= 0 then return 0 end
    return (math.min(count, highest) / highest) ^ 0.6
end

--- How strong a dot of this share is drawn: 0 to 1.
function HeatUI.AlphaFor(share, level)
    local strength = Heat.LEVELS[level] or Heat.LEVELS[2]
    return (ALPHA_LOW + (ALPHA_HIGH - ALPHA_LOW) * share) * strength
end

local function Colour(dot, share, alpha)
    local r, g, b = Heat.Colour(share)
    dot:SetVertexColor(r, g, b, alpha)
end

--- The list, busiest first and no longer than `most`.
local function Busiest(list, most)
    if #list <= most then return list end
    table.sort(list, function(a, b)
        if a.count ~= b.count then return a.count > b.count end
        return a.cell < b.cell
    end)
    local kept = {}
    for index = 1, most do kept[index] = list[index] end
    return kept
end

--------------------------------------------------------------------------------
-- World map
--------------------------------------------------------------------------------

local function InFight()
    if type(InCombatLockdown) == "function" then
        local ok, fighting = pcall(InCombatLockdown)
        if ok and fighting then return true end
    end
    if type(UnitAffectingCombat) == "function" then
        local ok, fighting = pcall(UnitAffectingCombat, "player")
        if ok and fighting then return true end
    end
    return false
end

--- Put the world map's glow away, once.
function HeatUI:ClearWorld()
    self.job = nil
    self.worldKey = nil
    if self.world and self.world.used > 0 then Trim(self.world, 0) end
end

function HeatUI:DrawWorld()
    if not Heat.WorldOn() or InFight() then
        self:ClearWorld()
        return
    end

    local view = ns.MapMarkers and ns.MapMarkers:WorldView()
    if not view then
        self:ClearWorld()
        return
    end

    -- The canvas keeps its own units at any zoom, so zoom is not in the key.
    local key = ("%d:%s:%s:%d:%d:%s"):format(view.mapID, view.width, view.height,
        Heat.version, Heat:Level(), Heat:TargetKey())
    if key == self.worldKey then return end

    if not self.world or self.world.parent ~= view.canvas then
        if self.world then Trim(self.world, 0) end
        local okLevel, level = pcall(view.canvas.GetFrameLevel, view.canvas)
        self.world = NewLayer(view.canvas, okLevel and tonumber(level) or nil)
        self.world.parent = view.canvas
    end

    local list, highest = Heat:Cells(view.mapID)
    self.worldKey = key
    self.job = {
        layer = self.world, list = Busiest(list, MAX_WORLD), highest = highest,
        index = 0, level = Heat:Level(),
        width = view.width, height = view.height,
    }
end

--- Place the next few dots of a long list.
function HeatUI:Slice()
    local job = self.job
    if not job then return end

    local across = job.width * SPREAD / Heat.GRID
    local down = job.height * SPREAD / Heat.GRID
    local last = math.min(#job.list, job.index + SLICE)

    for index = job.index + 1, last do
        local entry = job.list[index]
        local x, y = Heat.CellCentre(entry.cell)
        local share = Share(entry.count, job.highest)
        local dot = Dot(job.layer, index)
        dot:SetSize(across, down)
        dot:ClearAllPoints()
        dot:SetPoint("CENTER", job.layer.frame, "TOPLEFT", x * job.width, -y * job.height)
        Colour(dot, share, HeatUI.AlphaFor(share, job.level))
        dot:Show()
    end

    job.index = last

    if last >= #job.list then
        Trim(job.layer, #job.list)
        self.job = nil
    end
end

--------------------------------------------------------------------------------
-- Minimap
--------------------------------------------------------------------------------

--- Which way you face when the minimap turns with you, else nil.
local function Facing()
    if type(GetCVar) ~= "function" then return nil end
    local ok, rotate = pcall(GetCVar, "rotateMinimap")
    if not (ok and rotate == "1") then return nil end
    if type(GetPlayerFacing) ~= "function" then return nil end
    local gotFacing, facing = pcall(GetPlayerFacing)
    return gotFacing and ns.Harvest.ReadableNumber(facing) or nil
end

local function IsSquare()
    if type(GetMinimapShape) ~= "function" then return false end
    local ok, shape = pcall(GetMinimapShape)
    return ok and shape == "SQUARE"
end

function HeatUI:ClearMinimap()
    self.minimapKey = nil
    if self.minimap and self.minimap.used > 0 then Trim(self.minimap, 0) end
end

function HeatUI:DrawMinimap()
    if not (Minimap and Heat.MinimapOn()) then
        self:ClearMinimap()
        return
    end

    local mapID, px, py = ns.Harvest:PlayerMapPosition()
    if not mapID then
        self:ClearMinimap()
        return
    end

    local radius = ns.MapMarkers.MinimapRadius()
    local okSize, size = pcall(Minimap.GetWidth, Minimap)
    size = okSize and ns.Harvest.ReadableNumber(size) or nil
    local width, height = ns.Gathering.MapSize(mapID)
    if not (radius and size and width and height) then
        self:ClearMinimap()
        return
    end

    local facing, square = Facing(), IsSquare()

    -- A few yards of walking is not worth drawing again.
    local key = ("%d|%.3f|%.3f|%s|%s|%s|%s|%d|%d|%s"):format(mapID, px, py,
        tostring(facing and ("%.2f"):format(facing)), tostring(square), tostring(radius),
        tostring(size), Heat.version, Heat:Level(), Heat:TargetKey())
    if key == self.minimapKey then return end

    if not self.minimap then
        local okLevel, level = pcall(Minimap.GetFrameLevel, Minimap)
        self.minimap = NewLayer(Minimap, okLevel and tonumber(level) or nil)
    end

    local layer = self.minimap
    local list, highest = Heat:Cells(mapID)
    local player = { x = px, y = py }
    local half = size / 2
    local dotSize = math.max(MINIMAP_LEAST, width * SPREAD / Heat.GRID / radius * half)
    local strength = Heat.LEVELS[Heat:Level()] or Heat.LEVELS[2]

    local near = {}
    for _, entry in ipairs(list) do
        local x, y = Heat.CellCentre(entry.cell)
        local ox, oy = ns.MapMarkers.MinimapOffset({ x = x, y = y }, player, width, height,
            radius, facing, square, half)
        if ox then near[#near + 1] = { entry = entry, x = ox, y = oy } end
    end

    if #near > MAX_MINIMAP then
        table.sort(near, function(a, b) return a.entry.count > b.entry.count end)
    end

    local used = math.min(#near, MAX_MINIMAP)
    for index = 1, used do
        local item = near[index]
        local share = Share(item.entry.count, highest)
        local dot = Dot(layer, index)
        dot:SetSize(dotSize, dotSize)
        dot:ClearAllPoints()
        dot:SetPoint("CENTER", Minimap, "CENTER", item.x, item.y)
        Colour(dot, share, (ALPHA_LOW + (ALPHA_HIGH - ALPHA_LOW) * share) * strength * MINIMAP_SHARE)
        dot:Show()
    end
    Trim(layer, used)

    self.minimapKey = key
end

--------------------------------------------------------------------------------
-- What the world map shows (Show on Map)
--------------------------------------------------------------------------------

-- A small dark glass card in the world map's top left corner while the glow
-- is for one mob or item: what it shows, the mobs behind an item's glow,
-- the colour key and Show All Mobs. Our own frame, a child of the map so it
-- comes and goes with it; nothing on the map is written.

-- Mobs listed under an item, the likeliest first.
HeatUI.KEY_MOST = 5

local PANEL_WIDTH = 230

local function Card(map)
    local L = ns.L
    local Theme = ns.Theme

    local card = Theme.CreatePanel(map, "glass", "border")
    card:SetWidth(PANEL_WIDTH)
    card:SetFrameStrata("HIGH")
    card:EnableMouse(true)

    card.showing = Theme.CreateLabel(card, "small", "text")
    card.showing:SetPoint("TOPLEFT", 8, -8)
    card.showing:SetPoint("TOPRIGHT", -8, -8)

    card.lines = {}

    card.bar = CreateFrame("Frame", nil, card)
    card.bar:SetHeight(6)
    card.bar.parts = {}
    local stops = { 0, 0.25, 0.5, 0.75, 1 }
    for index = 1, #stops - 1 do
        local part = card.bar:CreateTexture(nil, "ARTWORK")
        part:SetColorTexture(1, 1, 1, 1)
        local r1, g1, b1 = Heat.Colour(stops[index])
        local r2, g2, b2 = Heat.Colour(stops[index + 1])
        local ok = type(CreateColor) == "function" and pcall(part.SetGradient, part, "HORIZONTAL",
            CreateColor(r1, g1, b1, 1), CreateColor(r2, g2, b2, 1))
        if not ok then part:SetColorTexture(r1, g1, b1, 1) end
        card.bar.parts[index] = part
    end
    card.bar:SetScript("OnSizeChanged", function(bar, width)
        local each = (tonumber(width) or 0) / #bar.parts
        for index, part in ipairs(bar.parts) do
            part:ClearAllPoints()
            part:SetPoint("TOPLEFT", (index - 1) * each, 0)
            part:SetSize(each, 6)
        end
    end)

    card.little = Theme.CreateLabel(card, "tiny", "muted")
    card.little:SetText(L["Seen here a little"])
    card.best = Theme.CreateLabel(card, "tiny", "muted", "RIGHT")
    card.best:SetText(L["Your best spot"])

    card.all = ns.Widgets.CreateButton(card, L["Show All Mobs"], function()
        Heat:ShowAll()
    end, { width = 100, height = 18 })

    card:Hide()
    return card
end

--- The text for the card: what it shows, and the item's mobs.
function HeatUI.CardText()
    local L = ns.L
    local item = Heat.item
    local name = item and item.name or Heat:Mob()
    if not name then return nil end

    local lines = {}
    if item then
        for index = 1, math.min(#item.mobs, HeatUI.KEY_MOST) do
            local entry = item.mobs[index]
            lines[index] = L.Format("%s (%s a kill)", entry.mob,
                ns.Tracker.FormatChance(entry.chance * 100))
        end
    end
    return L.Format("Showing: %s", ns.Util.Colored("accent", name)), lines
end

function HeatUI:UpdateCard()
    local map = _G.WorldMapFrame
    local showing, lines
    if Heat.WorldOn() and type(map) == "table" then showing, lines = HeatUI.CardText() end

    local open = false
    if showing then
        local ok, shown = pcall(map.IsShown, map)
        open = ok and shown
    end

    if not open then
        if self.card then self.card:Hide() end
        self.cardKey = nil
        return
    end

    local key = Heat:TargetKey() .. "|" .. Heat.version
    if key == self.cardKey and self.card:IsShown() then return end
    self.cardKey = key

    if not self.card then
        self.card = Card(map)
        local corner = map.ScrollContainer or map
        self.card:SetPoint("TOPLEFT", corner, "TOPLEFT", 8, -8)
    end

    local card = self.card
    card.showing:SetText(showing)

    local y = -8 - 16
    for index, text in ipairs(lines) do
        local line = card.lines[index]
        if not line then
            line = ns.Theme.CreateLabel(card, "tiny", "muted")
            card.lines[index] = line
        end
        line:ClearAllPoints()
        line:SetPoint("TOPLEFT", 12, y)
        line:SetPoint("TOPRIGHT", -8, y)
        line:SetText(text)
        line:Show()
        y = y - 13
    end
    for index = #lines + 1, #card.lines do card.lines[index]:Hide() end

    y = y - 4
    card.bar:ClearAllPoints()
    card.bar:SetPoint("TOPLEFT", 8, y)
    card.bar:SetPoint("TOPRIGHT", -8, y)
    y = y - 9
    card.little:ClearAllPoints()
    card.little:SetPoint("TOPLEFT", 8, y)
    card.best:ClearAllPoints()
    card.best:SetPoint("TOPRIGHT", -8, y)
    y = y - 16
    card.all:ClearAllPoints()
    card.all:SetPoint("TOPLEFT", 8, y)
    y = y - 18 - 8

    card:SetHeight(-y)
    card:Show()
end

--------------------------------------------------------------------------------
-- Driving
--------------------------------------------------------------------------------

--- Draw both again: after a switch, a setting or a kill.
function HeatUI:Refresh()
    if not ns.db then return end
    self.worldKey, self.minimapKey, self.cardKey = nil, nil, nil

    local ok, err = pcall(self.DrawWorld, self)
    if not ok then ns.Debug("heat world:", tostring(err)) end

    ok, err = pcall(self.DrawMinimap, self)
    if not ok then ns.Debug("heat minimap:", tostring(err)) end

    ok, err = pcall(self.UpdateCard, self)
    if not ok then ns.Debug("heat card:", tostring(err)) end
end

function HeatUI:Step(elapsed)
    -- A long list is laid out a few dots a frame.
    if self.job then
        local ok, err = pcall(self.Slice, self)
        if not ok then
            self.job = nil
            ns.Debug("heat slice:", tostring(err))
        end
    end

    self.since = (self.since or 0) + (elapsed or 0)
    if self.since < MINIMAP_STEP then return end
    self.since = 0

    local ok, err = pcall(self.DrawWorld, self)
    if not ok then ns.Debug("heat world:", tostring(err)) end

    ok, err = pcall(self.DrawMinimap, self)
    if not ok then ns.Debug("heat minimap:", tostring(err)) end

    ok, err = pcall(self.UpdateCard, self)
    if not ok then ns.Debug("heat card:", tostring(err)) end
end

function HeatUI:OnEnable()
    local driver = CreateFrame("Frame", nil, UIParent)
    driver:SetScript("OnUpdate", function(_, elapsed) HeatUI:Step(elapsed) end)
    driver:Show()
    self.driver = driver
end
