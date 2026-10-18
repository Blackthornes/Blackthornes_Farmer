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
--
-- Only while something is tracked (a mob or an item from the Map button, or
-- /farm heat mob): with nothing picked, neither map glows. The glow's outer
-- edge gets a gold line over a dark one (HeatUI.Outline), so where you have
-- killed and where you haven't reads at a glance on any map.

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

-- The outline: a gold line over a dark one, as wide as a share of the map
-- on the world map and in pixels on the minimap, and at most this many
-- pieces.
local EDGE_GOLD = { 1, 0.82, 0.3, 0.95 }
local EDGE_DARK = { 0, 0, 0, 0.7 }
local WORLD_GOLD, WORLD_DARK = 0.003, 0.0065
local MINIMAP_GOLD, MINIMAP_DARK = 1.5, 3.5
local MAX_WORLD_EDGES = 4000
local MAX_MINIMAP_EDGES = 400

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

--- The outline's two lines for piece `index`, dark under gold; nil on a
--- client with no lines.
local function Edge(layer, index)
    layer.edges = layer.edges or {}
    local edge = layer.edges[index]
    if edge then return edge end
    if type(layer.frame.CreateLine) ~= "function" then return nil end
    local okDark, dark = pcall(layer.frame.CreateLine, layer.frame, nil, "OVERLAY", nil, 1)
    local okGold, gold = pcall(layer.frame.CreateLine, layer.frame, nil, "OVERLAY", nil, 2)
    if not (okDark and dark and okGold and gold) then return nil end
    dark:SetColorTexture(EDGE_DARK[1], EDGE_DARK[2], EDGE_DARK[3], EDGE_DARK[4])
    gold:SetColorTexture(EDGE_GOLD[1], EDGE_GOLD[2], EDGE_GOLD[3], EDGE_GOLD[4])
    edge = { dark = dark, gold = gold }
    layer.edges[index] = edge
    return edge
end

local function PlaceEdge(edge, frame, point, x1, y1, x2, y2, darkWidth, goldWidth)
    for _, line in ipairs({ edge.dark, edge.gold }) do
        line:SetStartPoint(point, frame, x1, y1)
        line:SetEndPoint(point, frame, x2, y2)
        line:SetThickness(line == edge.dark and darkWidth or goldWidth)
        line:Show()
    end
end

--- Hide every outline piece past `used`.
local function TrimEdges(layer, used)
    for index = used + 1, #(layer.edges or {}) do
        layer.edges[index].dark:Hide()
        layer.edges[index].gold:Hide()
    end
    layer.edgesUsed = used
end

-- Marching squares: for each of a square's 16 ways of having its corners
-- inside, the edges whose middles a piece of outline joins. Corners are
-- top left 8, top right 4, bottom right 2, bottom left 1; edges T, R, B, L.
local CASES = {
    [1] = { { "L", "B" } }, [2] = { { "B", "R" } }, [3] = { { "L", "R" } },
    [4] = { { "T", "R" } }, [5] = { { "T", "R" }, { "L", "B" } }, [6] = { { "T", "B" } },
    [7] = { { "T", "L" } }, [8] = { { "T", "L" } }, [9] = { { "T", "B" } },
    [10] = { { "T", "L" }, { "B", "R" } }, [11] = { { "T", "R" } }, [12] = { { "L", "R" } },
    [13] = { { "R", "B" } }, [14] = { { "L", "B" } },
}

--- The outer edge of a list of cells, as pieces { x1, y1, x2, y2 } in map
--- fractions (0 to 1, y down). The cells are grown by one all round first,
--- so the line sits just outside the glow the dots make, and small gaps
--- inside it close up.
function HeatUI.Outline(list)
    local grid = Heat.GRID
    local inside = {}
    for _, entry in ipairs(list or {}) do
        local cx = entry.cell % grid
        local cy = (entry.cell - cx) / grid
        for dy = -1, 1 do
            for dx = -1, 1 do
                local x, y = cx + dx, cy + dy
                if x >= 0 and x < grid and y >= 0 and y < grid then inside[y * grid + x] = true end
            end
        end
    end

    local function In(x, y)
        return x >= 0 and x < grid and y >= 0 and y < grid and inside[y * grid + x] or false
    end

    -- Squares are named by their top left corner, from -1 so the map's own
    -- edge closes the line.
    local squares, order = {}, {}
    for cell in pairs(inside) do
        local cx = cell % grid
        local cy = (cell - cx) / grid
        for dy = -1, 0 do
            for dx = -1, 0 do
                local key = (cy + dy + 1) * (grid + 1) + (cx + dx + 1)
                if not squares[key] then
                    squares[key] = true
                    order[#order + 1] = key
                end
            end
        end
    end
    table.sort(order)

    local pieces = {}
    for _, key in ipairs(order) do
        local x = key % (grid + 1) - 1
        local y = (key - (x + 1)) / (grid + 1) - 1
        local case = (In(x, y) and 8 or 0) + (In(x + 1, y) and 4 or 0)
            + (In(x + 1, y + 1) and 2 or 0) + (In(x, y + 1) and 1 or 0)
        local joins = CASES[case]
        if joins then
            local left, right = (x + 0.5) / grid, (x + 1.5) / grid
            local top, bottom = (y + 0.5) / grid, (y + 1.5) / grid
            local midX, midY = (x + 1) / grid, (y + 1) / grid
            local at = {
                T = { midX, top }, B = { midX, bottom },
                L = { left, midY }, R = { right, midY },
            }
            for _, join in ipairs(joins) do
                local a, b = at[join[1]], at[join[2]]
                pieces[#pieces + 1] = { a[1], a[2], b[1], b[2] }
            end
        end
    end
    return pieces
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
    if self.world then
        if self.world.used > 0 then Trim(self.world, 0) end
        if (self.world.edgesUsed or 0) > 0 then TrimEdges(self.world, 0) end
    end
end

--- True while a mob or an item is picked, the only time the maps glow.
function HeatUI.Tracking()
    return Heat:TargetKey() ~= "all"
end

function HeatUI:DrawWorld()
    if not Heat.WorldOn() or not HeatUI.Tracking() or InFight() then
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
        if self.world then
            Trim(self.world, 0)
            TrimEdges(self.world, 0)
        end
        local okLevel, level = pcall(view.canvas.GetFrameLevel, view.canvas)
        self.world = NewLayer(view.canvas, okLevel and tonumber(level) or nil)
        self.world.parent = view.canvas
    end

    local list, highest = Heat:Cells(view.mapID)
    local kept = Busiest(list, MAX_WORLD)
    self.worldKey = key
    self.job = {
        layer = self.world, list = kept, highest = highest,
        index = 0, level = Heat:Level(),
        width = view.width, height = view.height,
        edges = HeatUI.Outline(kept), edgeIndex = 0,
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
    if last < #job.list then return end
    if not job.trimmed then
        Trim(job.layer, #job.list)
        job.trimmed = true
        return
    end

    -- Then the outline, a few pieces a frame.
    local most = math.min(#job.edges, MAX_WORLD_EDGES)
    local gold, dark = job.width * WORLD_GOLD, job.width * WORLD_DARK
    local done = math.min(most, job.edgeIndex + SLICE)
    local placed = job.edgeIndex
    for index = job.edgeIndex + 1, done do
        local edge = Edge(job.layer, index)
        if not edge then
            done = most
            break
        end
        local piece = job.edges[index]
        PlaceEdge(edge, job.layer.frame, "TOPLEFT", piece[1] * job.width, -piece[2] * job.height,
            piece[3] * job.width, -piece[4] * job.height, dark, gold)
        placed = index
    end
    job.edgeIndex = done

    if done >= most then
        TrimEdges(job.layer, placed)
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
    if self.minimap then
        if self.minimap.used > 0 then Trim(self.minimap, 0) end
        if (self.minimap.edgesUsed or 0) > 0 then TrimEdges(self.minimap, 0) end
    end
end

function HeatUI:DrawMinimap()
    if not (Minimap and Heat.MinimapOn() and HeatUI.Tracking()) then
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

    -- The outline, laid out once a map and target, then only placed.
    local outlineKey = mapID .. "|" .. Heat:TargetKey() .. "|" .. Heat.version
    if self.outlineKey ~= outlineKey then
        self.outlineKey = outlineKey
        self.outline = HeatUI.Outline(list)
    end
    local placed = 0
    for _, piece in ipairs(self.outline) do
        if placed >= MAX_MINIMAP_EDGES then break end
        local x1, y1 = ns.MapMarkers.MinimapOffset({ x = piece[1], y = piece[2] }, player,
            width, height, radius, facing, square, half)
        local x2, y2
        if x1 then
            x2, y2 = ns.MapMarkers.MinimapOffset({ x = piece[3], y = piece[4] }, player,
                width, height, radius, facing, square, half)
        end
        if x2 then
            local edge = Edge(layer, placed + 1)
            if not edge then break end
            placed = placed + 1
            PlaceEdge(edge, Minimap, "CENTER", x1, y1, x2, y2, MINIMAP_DARK, MINIMAP_GOLD)
        end
    end
    TrimEdges(layer, placed)

    self.minimapKey = key
end

--------------------------------------------------------------------------------
-- What the world map shows (Show on Map)
--------------------------------------------------------------------------------

-- A small dark glass card in the world map's top left corner while the glow
-- is for one mob or item: what it shows, the mobs behind an item's glow,
-- the colour key and Stop Tracking. Our own frame, a child of the map so it
-- comes and goes with it; nothing on the map is written. It sits in the top
-- left corner until dragged, then where it was left (heatCardX, heatCardY,
-- from the map's top left; never rename them), kept inside the map.

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
    card:SetMovable(true)
    card:RegisterForDrag("LeftButton")
    card:SetScript("OnDragStart", function(self) self:StartMoving() end)
    card:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        HeatUI:KeepCardPlace()
    end)

    card.showing = Theme.CreateLabel(card, "small", "text")
    card.showing:SetPoint("TOPLEFT", 8, -8)
    card.showing:SetPoint("TOPRIGHT", -8, -8)

    card.lines = {}

    card.empty = Theme.CreateLabel(card, "tiny", "muted")
    card.empty:SetText(L["Kill a few first and it will show here."])

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

    card.all = ns.Widgets.CreateButton(card, L["Stop Tracking"], function()
        Heat:ShowAll()
    end, { width = 100, height = 18 })

    card:Hide()
    return card
end

-- The map area the card sits in and is kept inside.
local function CardCorner(map)
    return map.ScrollContainer or map
end

-- How far the card may go from the corner's top left, so it stays inside.
local function CardRoom(card, corner)
    local okW, width = pcall(corner.GetWidth, corner)
    local okH, height = pcall(corner.GetHeight, corner)
    local roomX = math.max(0, ((okW and tonumber(width)) or 0) - (card:GetWidth() or 0) - 8)
    local roomY = math.max(0, ((okH and tonumber(height)) or 0) - (card:GetHeight() or 0) - 8)
    return roomX, roomY
end

--- Put the card where it was left, or the top left corner, inside the map.
function HeatUI:PlaceCard()
    local card, map = self.card, _G.WorldMapFrame
    if not (card and type(map) == "table") then return end
    local corner = CardCorner(map)
    local x = tonumber(ns.db and ns.db.heatCardX) or 8
    local y = tonumber(ns.db and ns.db.heatCardY) or 8
    local roomX, roomY = CardRoom(card, corner)
    if roomX > 0 then x = math.min(math.max(x, 8), roomX) end
    if roomY > 0 then y = math.min(math.max(y, 8), roomY) end
    card:ClearAllPoints()
    card:SetPoint("TOPLEFT", corner, "TOPLEFT", x, -y)
end

--- After a drag: keep where the card was left, as an offset from the map's
--- top left, and anchor it there again.
function HeatUI:KeepCardPlace()
    local card, map = self.card, _G.WorldMapFrame
    if not (card and type(map) == "table" and ns.db) then return end
    local corner = CardCorner(map)
    local ok, left, top, cornerLeft, cornerTop = pcall(function()
        local cardScale = card:GetEffectiveScale() or 1
        local cornerScale = corner:GetEffectiveScale() or 1
        return (card:GetLeft() or 0) * cardScale / cornerScale, (card:GetTop() or 0) * cardScale / cornerScale,
            corner:GetLeft() or 0, corner:GetTop() or 0
    end)
    if ok then
        ns.db.heatCardX = math.floor(left - cornerLeft + 0.5)
        ns.db.heatCardY = math.floor(cornerTop - top + 0.5)
    end
    self:PlaceCard()
end

--- Has the glow anywhere to show? False until a kill of what it is for was
--- kept with its spot.
function HeatUI.HasGlow()
    local item = Heat.item
    if item then return Heat:ItemHasSpots(item.name) end
    local mob = Heat:Mob()
    return mob ~= nil and Heat:HasSpots(mob)
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

    if not self.card then self.card = Card(map) end

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

    if HeatUI.HasGlow() then
        card.empty:Hide()
    else
        y = y - 2
        card.empty:ClearAllPoints()
        card.empty:SetPoint("TOPLEFT", 8, y)
        card.empty:SetPoint("TOPRIGHT", -8, y)
        card.empty:Show()
        y = y - (card.empty:GetStringHeight() or 13) - 2
    end

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
    self:PlaceCard()
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
