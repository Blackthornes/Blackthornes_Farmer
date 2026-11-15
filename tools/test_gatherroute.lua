-- The Gather Route (the owner said build it, 2026-11-15, from a mockup).
--
-- What matters: off by default, with Current Zone Only and Draw on Maps on
-- unless unticked; only your own spots for the skills you know; a zone
-- needs five spots; the loop visits spots that are up first and is short;
-- Current Zone Only keeps the route where you stand, unticked it takes the
-- best zone; the Route chip shows only while it is on; and the map lines
-- close the loop, dash the legs, cut to the minimap and look ahead.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("gatherroute")
local check = suite.check

local ns = env.Load({ ui = true })
local GatherRoute, RouteMap, Grinding = ns.GatherRoute, ns.RouteMap, ns.Grinding

check("the module loads", GatherRoute ~= nil and RouteMap ~= nil)

-- Settings ------------------------------------------------------------------
ns.db.gatherRoute, ns.db.gatherRouteZoneOnly, ns.db.gatherRouteDraw, ns.db.gatherRouteKinds = nil, nil, nil, nil
check("off by default", GatherRoute.IsOn() == false)
check("Current Zone Only on by default", GatherRoute.ZoneOnly() == true)
check("Draw on Maps on by default", GatherRoute.DrawsOnMaps() == true)
check("herbs and ore on, skins off", GatherRoute.Ticked("herbs") and GatherRoute.Ticked("ore")
    and not GatherRoute.Ticked("skins"))
check("no Route chip while off", Grinding.OffersRoute() == false)
ns.db.grindGives = "route"
check("a saved Route view waits while off", Grinding:Gives() == nil)

GatherRoute:SetOn(true)
check("on saves true", ns.db.gatherRoute == true)
check("the Route chip shows while on", Grinding.OffersRoute() == true and Grinding:Gives() == "route")
GatherRoute:SetZoneOnly(false)
check("unticked Current Zone Only saves false", ns.db.gatherRouteZoneOnly == false)
GatherRoute:SetZoneOnly(true)
check("ticked again saves nothing", ns.db.gatherRouteZoneOnly == nil)
GatherRoute:SetTicked("ore", false)
check("unticking ore keeps a false", ns.db.gatherRouteKinds and ns.db.gatherRouteKinds.ore == false)
GatherRoute:SetTicked("ore", true)
check("ticking ore again leaves no table", ns.db.gatherRouteKinds == nil)

-- Stubs ---------------------------------------------------------------------
local skills = { Herbalism = 150 }
ns.Spots.Skills = function() return skills end
local here = { 1, 0.1, 0.1 }
ns.Harvest.PlayerMapPosition = function() return here[1], here[2], here[3] end
ns.Gathering.MapSize = function() return 1000, 1000 end
local clock = 1000
ns.Gathering.Clock = function() return clock end
local backAt = {}
ns.Respawn.BackAt = function(_, spot) return backAt[spot] end
ns.Spots.MAP_ZONES = ns.Spots.MAP_ZONES or {}
ns.Spots.MAP_ZONES[1] = "Test Vale"
ns.Spots.MAP_ZONES[2] = "Test Hills"
ns.GatherRoute.ZoneHour = function(zone) return zone == "Test Hills" and 5000 or 1000 end
ns.GatherRoute.WorthEach = function() return 10 end

local spots = {}
ns.Gathering.Spots = function() return spots end
local function Add(kind, map, x, y, node)
    local spot = { kind = kind, map = map, x = x, y = y, node = node or "Peacebloom" }
    spots[#spots + 1] = spot
    return spot
end

check("only skills you know", GatherRoute.Kinds().herb == true and GatherRoute.Kinds().ore == nil)

-- Too few spots ---------------------------------------------------------------
for i = 1, 3 do Add("herb", 1, 0.1 * i, 0.2) end
GatherRoute:Changed()
local plan = GatherRoute:Plan()
check("under five spots asks for more", plan.needs == GatherRoute.MIN_SPOTS and #plan.stops == 0)

-- Ore you can't mine never counts.
Add("ore", 1, 0.5, 0.5, "Copper Vein")
Add("ore", 1, 0.6, 0.5, "Copper Vein")
GatherRoute:Changed()
check("ore without Mining stays out", GatherRoute:Plan().needs ~= nil)

-- Order -----------------------------------------------------------------------
do
    local line = {}
    for _, x in ipairs({ 0.9, 0.1, 0.5, 0.3, 0.7 }) do line[#line + 1] = { x = x, y = 0.5 } end
    local order = GatherRoute.Order(1, line, 0, 0.5, clock)
    local xs = {}
    for i, s in ipairs(order) do xs[i] = s.x end
    check("a line is walked in order", table.concat(xs, ",") == "0.1,0.3,0.5,0.7,0.9", table.concat(xs, ","))

    local waiting = { x = 0.15, y = 0.5 }
    local list = { { x = 0.1, y = 0.5 }, waiting, { x = 0.8, y = 0.5 } }
    backAt[waiting] = clock + 300
    local order2 = GatherRoute.Order(1, list, 0, 0.5, clock)
    check("spots still growing back come last", order2[#order2] == waiting)
    backAt[waiting] = nil

    -- A crossed loop is untangled: a square visited corner to corner.
    local square = { { x = 0.1, y = 0.1 }, { x = 0.9, y = 0.9 }, { x = 0.9, y = 0.1 }, { x = 0.1, y = 0.9 } }
    local path = GatherRoute.Order(1, square, 0.1, 0.0, clock)
    local walked = 0
    local at = { x = 0.1, y = 0.0 }
    for _, s in ipairs(path) do
        walked = walked + GatherRoute.Yards(1, at.x, at.y, s.x, s.y)
        at = s
    end
    check("the path is short", walked <= 2500.5, tostring(walked))
end

-- A route here ----------------------------------------------------------------
Add("herb", 1, 0.4, 0.4)
Add("herb", 1, 0.45, 0.6)
local late = Add("herb", 1, 0.2, 0.25)
backAt[late] = clock + 600
GatherRoute.order = nil
GatherRoute:Changed()
plan = GatherRoute:Plan()
check("six spots make a route", plan.needs == nil and #plan.stops == 6, tostring(#plan.stops))
check("the route is the zone you stand in", plan.zone == "Test Vale" and plan.map == 1)
check("the next stop is one that is up", plan.nextStop and plan.nextStop.back == true)
check("the stop growing back is last", plan.stops[6].spot == late and plan.stops[6].back == false)
check("a loop takes time", (plan.loopSeconds or 0) > 6 * GatherRoute.GATHER_SECONDS)
check("worth is counted", plan.loopWorth == 60)
check("yards to each stop", plan.stops[1].yards ~= nil)

-- Best zone ---------------------------------------------------------------------
for i = 1, 5 do Add("herb", 2, 0.1 * i, 0.5) end
GatherRoute:Changed()
plan = GatherRoute:Plan()
check("Current Zone Only stays here", plan.map == 1)
check("a better zone is named", plan.best and plan.best.zone == "Test Hills")
GatherRoute:SetZoneOnly(false)
plan = GatherRoute:Plan()
check("unticked it takes the best zone", plan.map == 2 and plan.zone == "Test Hills")
check("far away there are no yards from you", plan.stops[1].yards == nil)
GatherRoute:SetZoneOnly(true)

-- Map lines -----------------------------------------------------------------------
GatherRoute:Changed()
plan = GatherRoute:Plan()
local mapPlan = RouteMap.Plan()
check("the maps get the plan", mapPlan ~= nil and mapPlan.map == 1)
local legs = RouteMap.Legs(plan)
check("the loop closes", #legs == #plan.stops and legs[#legs].stop == plan.stops[1])
check("a leg into a growing spot is dashed", legs[5].up == false and legs[1].up == true)
GatherRoute:SetDraw(false)
check("Draw on Maps off draws nothing", RouteMap.Plan() == nil)
GatherRoute:SetDraw(true)

local dashes = RouteMap.Dashes(0, 0, 0.1, 0)
check("a leg is cut into dashes", #dashes > 5 and #dashes <= RouteMap.MAX_PIECES)
check("a dash starts at the start", dashes[1][1] == 0)
check("no length, no dashes", #RouteMap.Dashes(0.2, 0.2, 0.2, 0.2) == 0)

check("a line inside the minimap stays", RouteMap.Clip(-10, 0, 10, 0, 100) ~= nil)
check("a line far off is left out", RouteMap.Clip(500, 500, 600, 500, 100) == nil)
check("a square minimap clips too", RouteMap.Clip(-500, 0, 500, 0, 100, true) ~= nil)

local ahead = RouteMap.Ahead({ stops = { { n = 1 }, { n = 2 }, { n = 3 }, { n = 4 } }, nextStop = { n = 4 } })
check("the minimap looks ahead and wraps", #ahead == 3 and ahead[1].n == 4 and ahead[2].n == 1)

GatherRoute:SetOn(false)
check("off again draws nothing", RouteMap.Plan() == nil and Grinding.OffersRoute() == false)
check("off saves nothing", ns.db.gatherRoute == nil)

suite.done()
