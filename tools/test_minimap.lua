-- The minimap button.
--
-- It is the only way into the addon that does not involve typing, so the
-- things that matter are that it opens the window, that dragging it remembers
-- where it was put, and that it can be got rid of and brought back.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("minimap")

local ns = env.Load({ ui = true })
local UI = ns.UI

-- OnEnable is what the client calls at PLAYER_LOGIN; it builds the button and
-- re-seats it once the minimap has settled.
UI:OnEnable()

local button = UI.minimapButton

suite.check("the button is built", button ~= nil)
suite.check("it is parented to the minimap", button._parent == Minimap)
suite.check("it starts visible", button:IsShown())

--------------------------------------------------------------------------------
-- Opening
--------------------------------------------------------------------------------

local click = button:GetScript("OnClick")
suite.check("it has a click handler", type(click) == "function")

suite.check("the window starts closed", not UI.frame:IsShown())

click(button)
suite.check("clicking opens the window", UI.frame:IsShown())

click(button)
suite.check("clicking again closes it", not UI.frame:IsShown())

--------------------------------------------------------------------------------
-- Tooltip
--------------------------------------------------------------------------------

local enter = button:GetScript("OnEnter")
suite.check("it has a tooltip handler", type(enter) == "function")

GameTooltip._lines = {}
enter(button)

suite.check("the tooltip names the addon",
    GameTooltip._lines[1] == "Blackthornes Farmer", GameTooltip._lines[1])
suite.check("then its version", GameTooltip._lines[2] == ns.VersionLabel(), GameTooltip._lines[2])
suite.check("the tooltip says what a click does", #GameTooltip._lines > 1)

--------------------------------------------------------------------------------
-- Dragging round the ring
--------------------------------------------------------------------------------

local startingAngle = ns.db.minimapAngle

local dragStart = button:GetScript("OnDragStart")
local dragStop = button:GetScript("OnDragStop")

suite.check("it can be dragged", type(dragStart) == "function")

dragStart(button)
suite.check("dragging is flagged while it happens", button.dragging == true)

-- The drag follows the cursor on every frame. The stub cursor sits due east of
-- the minimap centre, so one update should swing the button to angle 0.
local onUpdate = button:GetScript("OnUpdate")
suite.check("dragging installs a frame handler", type(onUpdate) == "function")

onUpdate(button)

suite.check("dragging moves it to the cursor's angle",
    math.abs(ns.db.minimapAngle) < 0.001, ns.db.minimapAngle)
suite.check("the angle actually changed",
    ns.db.minimapAngle ~= startingAngle)

dragStop(button)
suite.check("releasing clears the flag", button.dragging == false)
suite.check("releasing stops the frame handler",
    button:GetScript("OnUpdate") == nil)

-- The saved angle is what survives a reload, so re-seating from it must work.
UI:RepositionMinimapButton()
suite.check("it re-seats from the saved angle", button._point ~= nil)

--------------------------------------------------------------------------------
-- The orbit clears the ring
--------------------------------------------------------------------------------

-- A fixed radius only clears a default 140px minimap. On a bigger one the
-- button has to move further out, or it sits on top of the map.
local function OrbitDistance()
    local x, y = button._point[4], button._point[5]
    return math.sqrt((x * x) + (y * y))
end

local defaultDistance = OrbitDistance()
suite.check("it orbits outside a default minimap",
    defaultDistance > 70, defaultDistance)

Minimap._width = 240
UI:RepositionMinimapButton()

suite.check("a larger minimap pushes it further out",
    OrbitDistance() > defaultDistance, OrbitDistance())

Minimap._width = 140
UI:RepositionMinimapButton()

--------------------------------------------------------------------------------
-- Always shown (the owner, 2026-10-15: no setting, no command)
--------------------------------------------------------------------------------

suite.check("there is no minimap command any more",
    not (ns.commandOrder and (function()
        for _, name in ipairs(ns.commandOrder) do
            if name == "minimap" then return true end
        end
    end)()))
suite.check("the button shows", button:IsShown())

--------------------------------------------------------------------------------
-- Building twice
--------------------------------------------------------------------------------

UI:BuildMinimapButton()
suite.check("building again does not make a second button",
    UI.minimapButton == button)

-- A save from before, with the button hidden, still shows it. The key is
-- kept in the save, only no longer read.
ns.db.minimapHidden = true
UI.minimapButton = nil

UI:BuildMinimapButton()
suite.check("an old saved hide is ignored", UI.minimapButton:IsShown())
suite.check("the old key stays in the save", ns.db.minimapHidden == true)

suite.done()
