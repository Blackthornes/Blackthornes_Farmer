-- Where to Farm beside the world map (UI/MapDock.lua): off unless ticked,
-- placed from the map's edges without anchoring to the map, never in a
-- fight, not with no room, and back to its own spot when the map closes.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("mapdock")

local ns = env.Load({ ui = true })
local Dock, Goals = ns.MapDock, ns.GoalsUI

suite.check("the module loads", Dock ~= nil)
suite.check("off unless ticked", Dock:IsOn() == false and ns.db.goalSpotsDockMap ~= true)

-- A screen 1600 wide, and a world map whose right edge is at 900.
UIParent._width = 1600
local map = env.Stub({ _shown = true })
function map:GetRight() return 900 end
function map:GetTop() return 700 end
function map:GetEffectiveScale() return 1 end
local hooks = {}
function map:HookScript(script, fn) hooks[script] = fn end
_G.WorldMapFrame = map
_G.InCombatLockdown = function() return false end

local panel = Goals:BuildSpots()
panel:SetWidth(240)
panel:Show()
panel.anchor = nil

Goals:PlaceSpots()
suite.check("off, it takes its own spot", panel._point[2] == UIParent and panel._point[1] == "CENTER",
    tostring(panel._point[1]))

Dock:SetOn(true)
suite.check("ticking it saves the choice", ns.db.goalSpotsDockMap == true)
suite.check("on, it sits at the map's right edge",
    panel._point[1] == "TOPLEFT" and panel._point[2] == UIParent and panel._point[3] == "BOTTOMLEFT"
        and panel._point[4] == 906 and panel._point[5] == 700,
    tostring(panel._point[4]) .. "," .. tostring(panel._point[5]))
suite.check("placed against the screen, never anchored to the map", panel._point[2] ~= map)

-- The map closes: back to its own spot. It opens: docked again.
Dock:OnEnable()
suite.check("it listens for the map", type(hooks.OnShow) == "function" and type(hooks.OnHide) == "function")
map._shown = false
hooks.OnHide()
suite.check("the map closed, it goes back", panel._point[1] == "CENTER", tostring(panel._point[1]))
map._shown = true
hooks.OnShow()
suite.check("the map opened, it docks again", panel._point[4] == 906)

-- Dragged away, it stays put until the map opens again.
Dock:Dragged()
Goals:PlaceSpots()
suite.check("dragged away, it is left alone", panel._point[1] == "CENTER")
hooks.OnShow()
suite.check("the next time the map opens it docks", panel._point[4] == 906)

-- No room right of the map (a full-screen map).
function map:GetRight() return 1500 end
Goals:PlaceSpots()
suite.check("with no room it does not dock", panel._point[1] == "CENTER")
function map:GetRight() return 900 end

-- Never in a fight.
_G.InCombatLockdown = function() return true end
suite.check("in a fight it has no spot", Dock:Spot(panel) == nil)
_G.InCombatLockdown = function() return false end

-- A map that will not say where it is.
function map:GetRight() return nil end
suite.check("a map with no edge is no dock", Dock:Spot(panel) == nil)
function map:GetRight() return 900 end

-- The panel's own size (its grip) is counted.
function panel:GetEffectiveScale() return 2 end
local x, y = Dock:Spot(panel)
suite.check("a scaled panel is placed in its own units", x == 453 and y == 350, tostring(x) .. "," .. tostring(y))

Dock:SetOn(false)
suite.check("unticked, it goes back", panel._point[1] == "CENTER" and ns.db.goalSpotsDockMap == false)

_G.WorldMapFrame = nil
_G.InCombatLockdown = nil
UIParent._width = nil

suite.done()
