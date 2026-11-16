--------------------------------------------------------------------------------
-- UI/MapDock.lua
--
-- Where to Farm beside the world map (the owner said build it from a
-- mockup, 2026-11-16). While the world map is open, the panel sits on the
-- map's right edge instead of floating over the part being read; when the
-- map closes it goes back to its own spot (GoalsUI:PlaceSpots). Off unless
-- ticked: "Dock to the Map:" on the Map & Goals page, saved account wide as
-- `goalSpotsDockMap` (never rename it).
--
-- The game's map is never hidden, moved, sized or anchored to. Its edges
-- are read, and the panel is placed against the screen from them, so
-- nothing of ours hangs off a game frame. Never in a fight. With no room
-- right of the map (a full-screen map) the panel stays where it is.
-- Dragged away while docked, it stays where it was dropped until the map
-- is opened again.
--------------------------------------------------------------------------------

local _, ns = ...

local MapDock = ns.NewModule("MapDock")

-- Between the map's edge and the panel, in screen pixels.
MapDock.GAP = 6

function MapDock:IsOn()
    return ns.db and ns.db.goalSpotsDockMap == true or false
end

function MapDock:SetOn(on)
    if not ns.db then return end
    ns.db.goalSpotsDockMap = on and true or false
    self.loose = nil
    self:Follow()
end

local function Fighting()
    return type(InCombatLockdown) == "function" and InCombatLockdown() and true or false
end

--- A number the client gave, or nil (a secret value raises when compared).
local function Number(value)
    if type(value) ~= "number" then return nil end
    local ok, fine = pcall(function() return value == value end)
    return ok and fine and value or nil
end

--- The world map's right and top edges and the screen's width, in screen
--- pixels; nil while the map is closed or will not say.
function MapDock.MapEdge()
    local map = _G.WorldMapFrame
    if type(map) ~= "table" then return nil end
    local ok, shown, right, top, scale = pcall(function()
        return map:IsShown(), map:GetRight(), map:GetTop(), map:GetEffectiveScale()
    end)
    right, top, scale = Number(right), Number(top), Number(scale)
    if not (ok and shown and right and top and scale and scale > 0) then return nil end

    local okScreen, width, uiScale = pcall(function()
        return UIParent:GetWidth(), UIParent:GetEffectiveScale()
    end)
    width, uiScale = Number(width), Number(uiScale)
    if not (okScreen and width and uiScale and uiScale > 0) then return nil end

    return right * scale, top * scale, width * uiScale
end

--- Where `panel` goes beside the map: x and y from the screen's bottom
--- left, in the panel's own units. Nil when it is not to dock: off, in a
--- fight, dragged away, the map closed, or no room right of the map.
function MapDock:Spot(panel)
    if not self:IsOn() or self.loose or Fighting() then return nil end
    local right, top, screen = MapDock.MapEdge()
    if not right then return nil end

    local ok, scale, width = pcall(function() return panel:GetEffectiveScale(), panel:GetWidth() end)
    scale, width = Number(scale), Number(width)
    if not (ok and scale and scale > 0 and width) then return nil end

    if right + MapDock.GAP + width * scale > screen then return nil end
    return (right + MapDock.GAP) / scale, top / scale
end

--- Place `panel` beside the map. True when it was docked there.
function MapDock:Place(panel)
    if not panel then return false end
    local x, y = self:Spot(panel)
    if not x then
        self.docked = nil
        return false
    end
    panel:ClearAllPoints()
    panel:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x, y)
    self.docked = true
    return true
end

--- The panel was dragged: let go of the map until it opens again.
function MapDock:Dragged()
    if self.docked then
        self.docked = nil
        self.loose = true
    end
end

--- The map opened or closed, or the setting changed: the panel, if it is
--- up, goes to the map's edge or back to its own spot.
function MapDock:Follow()
    local goals = ns.GoalsUI
    local panel = goals and rawget(goals, "spots")
    if not (panel and panel.IsShown and panel:IsShown()) then return end
    if Fighting() then return end
    if goals.PlaceSpots then goals:PlaceSpots() end
end

function MapDock:MapShown()
    self.loose = nil
    self:Follow()
end

function MapDock:MapHidden()
    self.loose = nil
    self:Follow()
end

function MapDock:OnEnable()
    local map = _G.WorldMapFrame
    if type(map) ~= "table" or type(map.HookScript) ~= "function" then return end
    -- Hooks only listen; the map's own scripts run as before.
    pcall(map.HookScript, map, "OnShow", function() pcall(MapDock.MapShown, MapDock) end)
    pcall(map.HookScript, map, "OnHide", function() pcall(MapDock.MapHidden, MapDock) end)
end
