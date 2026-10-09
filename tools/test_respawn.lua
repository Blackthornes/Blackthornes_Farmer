-- When a gathered herb or vein grows back, learned from your own returns.
--
-- What matters: only a return to a marked spot teaches anything; the same
-- visit (a vein mined three times) and a return after a long time away
-- teach nothing; nothing is guessed below MIN_RETURNS, so the marker and
-- the node's tooltip say "?"; after that the estimate is the middle of the
-- three quickest returns, and the marker counts down from when the spot was
-- last taken; each node on each map learns apart; only the last MAX_GAPS
-- returns are kept; the node's own tooltip gets one line, once, and units,
-- items and nodes never gathered on this map get none; and the learning
-- lives in a saved key of its own, leaving the record and the spots alone.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("respawn")

local wall = 1000000

local ns = env.Load({ ui = true })
local Gathering, Respawn, MapMarkers = ns.Gathering, ns.Respawn, ns.MapMarkers

_G.time = function() return wall end
_G.GetTime = function() return wall end
_G.C_Map.GetMapWorldSize = function() return 3000, 2000 end

local hooks = {}
_G.GameTooltip.HookScript = function(_, script, fn)
    hooks[script] = hooks[script] or {}
    table.insert(hooks[script], fn)
end
local tooltip = { text = nil, unit = nil }
_G.GameTooltip.GetUnit = function() return tooltip.unit end
_G.GameTooltip.GetItem = function() return nil end
_G.GameTooltipTextLeft1 = { GetText = function() return tooltip.text end }

for _, module in ipairs(ns.moduleOrder) do
    if module.OnEnable then module:OnEnable() end
end

local MAP = 37
env.world.zone, env.world.subZone = "Elwynn Forest", "Goldshire"
env.world.mapID = MAP
env.world.position = { 0.45, 0.68 }

local function Take(node, x, y, kind)
    return Gathering:AddSpot(MAP, x or 0.45, y or 0.68, node, kind or "herb")
end

--------------------------------------------------------------------------------
-- Learning
--------------------------------------------------------------------------------

local spot = Take("Peacebloom")
suite.check("a first gather teaches nothing", Respawn:Estimate(MAP, "Peacebloom").returns == 0)

wall = wall + 20
Take("Peacebloom")
suite.check("a second loot window in the same visit teaches nothing",
    Respawn:Estimate(MAP, "Peacebloom").returns == 0)

wall = wall + 3 * 60 * 60
Take("Peacebloom")
suite.check("a return after hours away teaches nothing",
    Respawn:Estimate(MAP, "Peacebloom").returns == 0)

local line = Respawn:SpotLine(spot, wall)
suite.check("no returns yet: the marker says ?",
    line == "Grows back: ?  (learning, 0 of 3 returns)", line)

wall = wall + 9 * 60
Take("Peacebloom")
wall = wall + 6 * 60
Take("Peacebloom")
local estimate = Respawn:Estimate(MAP, "Peacebloom")
suite.check("each real return is counted", estimate.returns == 2, estimate.returns)
suite.check("two returns are still not enough", estimate.seconds == nil and estimate.needed == 1)
line = Respawn:SpotLine(spot, wall)
suite.check("and the marker still says ?", line == "Grows back: ?  (learning, 2 of 3 returns)", line)

wall = wall + 40 * 60
Take("Peacebloom")
estimate = Respawn:Estimate(MAP, "Peacebloom")
suite.check("three returns give an estimate", estimate.seconds ~= nil)
suite.check("the middle of the three quickest", estimate.seconds == 9 * 60, estimate.seconds)

wall = wall + 7 * 60
Take("Peacebloom")
estimate = Respawn:Estimate(MAP, "Peacebloom")
suite.check("a quicker return pulls it down", estimate.seconds == 7 * 60, estimate.seconds)

--------------------------------------------------------------------------------
-- Words
--------------------------------------------------------------------------------

line = Respawn:SpotLine(spot, wall + 2 * 60)
suite.check("the marker counts down from the last gather",
    line == "Back in about 5 min  (from 4 returns)", line)

line = Respawn:SpotLine(spot, wall + 30 * 60)
suite.check("and says when it should be back already",
    line == "Should be back by now  (from 4 returns)", line)

suite.check("duration: seconds", Respawn.Duration(30) == "under a minute")
suite.check("duration: minutes", Respawn.Duration(7 * 60 + 10) == "7 min")
suite.check("duration: hours", Respawn.Duration(80 * 60) == "1 h 20 min")
suite.check("duration: whole hours", Respawn.Duration(120 * 60) == "2 h")

-- The marker's own hover carries it.
local pin = MapMarkers.CreatePin(UIParent, 18)
MapMarkers.Dress(pin, spot, wall)
GameTooltip._lines = {}
wall = wall + 2 * 60
local target = rawget(pin, "hit") or pin
target:GetScript("OnEnter")(target)
suite.check("the marker's hover shows it",
    GameTooltip._lines[3] == "Back in about 5 min  (from 4 returns)", GameTooltip._lines[3])

--------------------------------------------------------------------------------
-- Apart
--------------------------------------------------------------------------------

suite.check("another herb on the same map learns apart",
    Respawn:Estimate(MAP, "Silverleaf").returns == 0)
suite.check("the same herb on another map learns apart",
    Respawn:Estimate(12, "Peacebloom").returns == 0)

-- A different Peacebloom across the field teaches Peacebloom on this map.
local far = Take("Peacebloom", 0.6, 0.68)
wall = wall + 8 * 60
Take("Peacebloom", 0.6, 0.68)
suite.check("every spot of a herb teaches that herb on its map",
    Respawn:Estimate(MAP, "Peacebloom").returns == 5)
suite.check("and every one of its markers shares the estimate",
    Respawn:SpotLine(far, wall):find("^Back in about") ~= nil)

for _ = 1, Respawn.MAX_GAPS + 5 do Respawn:Learn(MAP, "Tin Vein", 600) end
suite.check("only the latest returns are kept",
    #Respawn:Store()[Respawn.Key(MAP, "Tin Vein")].gaps == Respawn.MAX_GAPS)

--------------------------------------------------------------------------------
-- The node's own tooltip
--------------------------------------------------------------------------------

local function ShowTooltip(text, unit)
    tooltip.text, tooltip.unit = text, unit
    GameTooltip._lines = { text }
    for _, fn in ipairs(hooks.OnShow or {}) do fn(_G.GameTooltip) end
end

local function HideTooltip()
    for _, fn in ipairs(hooks.OnHide or {}) do fn(_G.GameTooltip) end
end

ShowTooltip("Peacebloom")
suite.check("a herb under the mouse says how long it takes here",
    GameTooltip._lines[2] == "Grows back in about 7 min here  (from 5 returns)", GameTooltip._lines[2])
for _, fn in ipairs(hooks.OnShow or {}) do fn(_G.GameTooltip) end
suite.check("once per showing", GameTooltip._lines[3] == nil, GameTooltip._lines[3])
HideTooltip()

Take("Silverleaf")
ShowTooltip("Silverleaf")
suite.check("one gathered but not yet learned says ?",
    GameTooltip._lines[2] == "Grows back: ?  (learning, 0 of 3 returns)", GameTooltip._lines[2])
HideTooltip()

ShowTooltip("Mageroyal")
suite.check("one never gathered on this map gets nothing", GameTooltip._lines[2] == nil)
HideTooltip()

ShowTooltip("Peacebloom", "Peacebloom")
suite.check("a unit gets nothing", GameTooltip._lines[2] == nil)
HideTooltip()

ShowTooltip(env.Secret("name"))
suite.check("a name the client will not let us read gets nothing", GameTooltip._lines[2] == nil)
HideTooltip()

--------------------------------------------------------------------------------
-- Saved data
--------------------------------------------------------------------------------

suite.check("learned under a key of its own", type(ns.db.gathering.respawn) == "table")
Gathering:ClearSpots()
suite.check("clearing the markers keeps what was learned",
    Respawn:Estimate(MAP, "Peacebloom").returns == 5)
suite.check("a broken saved entry reads as nothing learned", (function()
    Respawn:Store()["37|Broken"] = "junk"
    Respawn:Store()["37|Odd"] = { gaps = { "x", 600 } }
    return Respawn:Estimate(MAP, "Broken").returns == 0 and Respawn:Estimate(MAP, "Odd").returns == 1
end)())

suite.done()
