-- The Gather Route (the owner said build it, 2026-11-15, from a mockup).
--
-- What matters: off by default, with Current Zone Only and Draw on Maps on
-- unless unticked; only your own spots for the skills you know; a zone
-- needs five spots; the loop visits spots that are up first and is short;
-- Current Zone Only keeps the route where you stand, unticked it takes the
-- best zone; Route Mode shows on Herbs, Ore and Leather only while it is on; and the map lines
-- close the loop, dash the legs, cut to the minimap and look ahead.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("gatherroute")
local check = suite.check

local ns = env.Load({ ui = true })
local GatherRoute, RouteMap, Grinding = ns.GatherRoute, ns.RouteMap, ns.Grinding

check("the module loads", GatherRoute ~= nil and RouteMap ~= nil)

-- Settings ------------------------------------------------------------------
ns.db.gatherRoute, ns.db.gatherRouteZoneOnly, ns.db.gatherRouteDraw, ns.db.gatherRouteKinds = nil, nil, nil, nil
check("on by default", GatherRoute.IsOn() == true)
check("Current Zone Only on by default", GatherRoute.ZoneOnly() == true)
check("Draw on Maps on by default", GatherRoute.DrawsOnMaps() == true)
check("herbs and ore on, skins off", GatherRoute.Ticked("herbs") and GatherRoute.Ticked("ore")
    and not GatherRoute.Ticked("skins"))
local GrindingUI = ns.GrindingUI
GatherRoute:SetOn(false)
check("no Route Mode while off", GrindingUI.OffersRouteMode("herbs") == false)
check("off saves false", ns.db.gatherRoute == false)
ns.db.gatherRoute = nil
ns.db.grindGives = "route"
check("an old saved Route view reads as any mob", Grinding:Gives() == nil)

GatherRoute:SetOn(true)
check("on saves nothing", ns.db.gatherRoute == nil and GatherRoute.IsOn())
check("Route Mode shows on Herbs and Ore while on", GrindingUI.OffersRouteMode("herbs")
    and GrindingUI.OffersRouteMode("ore") and not GrindingUI.OffersRouteMode("cloth")
    and not GrindingUI.OffersRouteMode("fish"))
check("Route Mode is off unless ticked", GatherRoute.RouteMode("herbs") == false and ns.db.grindRouteMode == nil)
ns.db.grindGives = "herbs"
check("unticked, Herbs shows its list", GrindingUI.Layout() == "nodes")
GatherRoute:SetRouteMode("herbs", true)
check("ticking saves it for that page only", ns.db.grindRouteMode and ns.db.grindRouteMode.herbs == true
    and GatherRoute.RouteMode("ore") == false)
check("ticked, Herbs shows the route", GrindingUI.Layout() == "route" and GatherRoute.page == "herb")
check("the page keeps to herbs", (function()
    local k = GatherRoute.Kinds()
    return not k.ore and not k.skin
end)())
ns.db.grindGives = "ore"
check("Ore stays a list while only Herbs is ticked", GrindingUI.Layout() == "nodes")
ns.db.grindGives = "herbs"
GatherRoute:SetRouteMode("herbs", false)
check("unticking leaves nothing saved", ns.db.grindRouteMode == nil and GatherRoute.page == nil)
check("unticked, the list comes back", GrindingUI.Layout() == "nodes")
ns.db.grindGives = nil
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
check("no lines until Route Mode picks a page", RouteMap.Plan() == nil)
GatherRoute:SetPage("herb")
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

-- The minimap ring: hollow, round, and the line stops at its edge.
do
    local ring = RouteMap.Ring(0, 0, 9, RouteMap.RING_PIECES)
    local round = #ring == RouteMap.RING_PIECES
    for _, piece in ipairs(ring) do
        if math.abs(math.sqrt(piece[1] ^ 2 + piece[2] ^ 2) - 9) > 0.001 then round = false end
    end
    check("the stop ring is round pieces at its radius", round)
    local ex, ey = RouteMap.ShortenTo(0, 0, 100, 0, 9)
    check("the line stops at the ring's edge", math.abs(ex - 91) < 0.001 and ey == 0)
    local sx, sy = RouteMap.ShortenTo(0, 0, 5, 0, 9)
    check("a line shorter than the ring stays put", sx == 0 and sy == 0)
    check("the ring leaves room for the blip", RouteMap.RING_AHEAD >= 6 and RouteMap.RING_NEXT > RouteMap.RING_AHEAD)
end

local ahead = RouteMap.Ahead({ stops = { { n = 1 }, { n = 2 }, { n = 3 }, { n = 4 } }, nextStop = { n = 4 } })
check("the minimap looks ahead and wraps", #ahead == 3 and ahead[1].n == 4 and ahead[2].n == 1)

-- Reaching a stop -------------------------------------------------------------
do
    local picks = {
        { spot = { x = 0.9, y = 0.1 }, back = true },
        { spot = { x = 0.12, y = 0.1 }, back = true },
        { spot = { x = 0.11, y = 0.1 }, back = false, at = clock + 900 },
        { spot = { x = 0.1, y = 0.1 }, back = true, done = true },
    }
    check("smart pathing picks the nearest stop that is up",
        GatherRoute.PickNext(picks, 1, 0.1, 0.1, clock) == picks[2])
    check("away from the zone the first stop up is next",
        GatherRoute.PickNext(picks, nil, nil, nil, clock) == picks[1])

    check("a dot only where something is up", RouteMap.ShowsDot({ back = true }) == true
        and RouteMap.ShowsDot({ back = false }) == false
        and RouteMap.ShowsDot({ back = true, done = true }) == false
        and RouteMap.ShowsDot({ back = true, resting = true }) == false)

    GatherRoute.cooldown = {}
    GatherRoute.order, GatherRoute.cache = nil, nil
    GatherRoute:Changed()
    GatherRoute:Start()
    local first = GatherRoute:Plan().nextStop.spot
    check("the route aims at its next stop", GatherRoute.run and GatherRoute.run.aimed == first)
    here[1], here[2], here[3] = first.map, first.x, first.y
    GatherRoute:Look()
    check("reaching a stop points to the next", GatherRoute.run.aimed ~= first, tostring(GatherRoute.run.aimed))
    check("the stop reached rests", GatherRoute.Resting(first, clock) ~= nil)

    -- A new loop never sends you back to a stop still resting.
    GatherRoute.run.visited, GatherRoute.run.picked = {}, {}
    GatherRoute.cache = nil
    local plan2 = GatherRoute:Plan()
    check("a resting stop is not next", plan2.nextStop and plan2.nextStop.spot ~= first)
    local restingStop
    for _, stop in ipairs(plan2.stops) do if stop.spot == first then restingStop = stop end end
    check("a resting stop shows no dot", restingStop and not RouteMap.ShowsDot(restingStop))

    -- A gathered stop with no grow-back time learned still waits.
    local other = plan2.nextStop.spot
    other.last = clock
    GatherRoute:Look()
    check("a gathered stop rests", GatherRoute.Resting(other, clock) ~= nil
        and GatherRoute.Resting(other, clock) >= clock + GatherRoute.COOLDOWN)

    -- A herb picked out of order, even one the game names another way at
    -- that place, puts the stop there on its rest and the route moves on.
    GatherRoute.cache = nil
    local plan3 = GatherRoute:Plan()
    local away
    for _, stop in ipairs(plan3.stops) do
        if not stop.done and not stop.next and stop.spot ~= first and stop.spot ~= other then away = stop.spot end
    end
    check("a stop is left to pick out of order", away ~= nil)
    if away then
        local spots = ns.Gathering:Spots()
        spots[#spots + 1] = { map = away.map, x = away.x + 0.002, y = away.y, node = "Another Herb",
            kind = away.kind, gathers = 1, first = clock, last = clock }
        ns.Gathering:SpotsChanged()
        GatherRoute:Look()
        check("a herb picked out of order rests its stop", GatherRoute.Resting(away, clock) ~= nil)
        check("and counts as picked", GatherRoute.run.visited[away] and GatherRoute.run.picked[away])
        GatherRoute.cache = nil
        local plan4 = GatherRoute:Plan()
        check("the picked stop is not next", plan4.nextStop == nil or plan4.nextStop.spot ~= away)
        table.remove(spots)
        ns.Gathering:SpotsChanged()
    end
    check("a far gather is not a pick", GatherRoute.PickedNear({ map = 1, x = 0.1, y = 0.1, kind = "herb" },
        { { map = 1, x = 0.3, y = 0.1, kind = "herb" } }) == false)
    check("ore picked near a herb stop is not its pick", GatherRoute.PickedNear({ map = 1, x = 0.1, y = 0.1, kind = "herb" },
        { { map = 1, x = 0.1, y = 0.1, kind = "ore" } }) == false)

    -- From a distance: the stop the arrow points at counts once you come
    -- within REACH yards, after walking in from farther out.
    check("the reach is about 30 yards", GatherRoute.REACH == 30 and GatherRoute.ARRIVED < GatherRoute.REACH)
    do
        local run = { aimed = "a" }
        check("a stop aimed while you stand near it needs you close", GatherRoute.Reach(run, "a") == GatherRoute.ARRIVED)
        run.cameFrom = "a"
        check("walked in from afar, it counts at 30 yards", GatherRoute.Reach(run, "a") == GatherRoute.REACH)
        check("a stop you pass on the way still needs you close", GatherRoute.Reach(run, "b") == GatherRoute.ARRIVED)
    end
    GatherRoute.cooldown = {}
    GatherRoute.run.visited, GatherRoute.run.picked = {}, {}
    GatherRoute.order, GatherRoute.cache = nil, nil
    GatherRoute:Advance()
    local aimed = GatherRoute.run.aimed
    check("a stop is aimed for the reach test", aimed ~= nil)
    if aimed then
        here[1], here[2], here[3] = aimed.map, aimed.x + 0.1, aimed.y -- 100 yards off
        GatherRoute:Look()
        check("100 yards off, the stop still waits", GatherRoute.run.aimed == aimed)
        here[2] = aimed.x + 0.025 -- 25 yards off
        GatherRoute:Look()
        check("25 yards off, the route moves on", GatherRoute.run.aimed ~= aimed and GatherRoute.run.visited[aimed])
        check("the stop seen from afar rests", GatherRoute.Resting(aimed, clock) ~= nil)
        check("and isn't marked picked", not GatherRoute.run.picked[aimed])
    end
    check("a pick 25 yards from the aimed stop moves it on",
        GatherRoute.PickedNear({ map = 1, x = 0.1, y = 0.1, kind = "herb" },
            { { map = 1, x = 0.125, y = 0.1, kind = "herb" } }, GatherRoute.REACH) == true)
    check("but isn't a pick of a stop it isn't aimed at",
        GatherRoute.PickedNear({ map = 1, x = 0.1, y = 0.1, kind = "herb" },
            { { map = 1, x = 0.125, y = 0.1, kind = "herb" } }) == false)

    clock = clock + GatherRoute.COOLDOWN + 1
    check("the rest ends after its window", GatherRoute.Resting(first, clock) == nil)
    GatherRoute:Stop()
    here[1], here[2], here[3] = 1, 0.1, 0.1
end

GatherRoute:SetOn(false)
-- Skin spots: your own skins, joined when close, capped.
do
    ns.db.skinSpots = nil
    here[1], here[2], here[3] = 1, 0.5, 0.5
    local first = GatherRoute:NoteSkin("Test Wolf")
    here[2] = 0.51 -- 10 yards on a 1000 yard map
    local again = GatherRoute:NoteSkin("Test Wolf")
    check("a close skin joins its spot", first == again and first.gathers == 2 and #ns.db.skinSpots == 1)
    here[2] = 0.6
    GatherRoute:NoteSkin("Test Wolf")
    check("a far skin makes a new spot", #ns.db.skinSpots == 2)
    GatherRoute:NoteSkin("Test Bear")
    check("another mob makes its own spot", #ns.db.skinSpots == 3)
    local keep = GatherRoute.MAX_SKIN_SPOTS
    GatherRoute.MAX_SKIN_SPOTS = 3
    here[2] = 0.9
    GatherRoute:NoteSkin("Test Cat")
    check("skin spots are capped", #ns.db.skinSpots == 3)
    GatherRoute.MAX_SKIN_SPOTS = keep
    skills.Skinning = 100
    GatherRoute:SetPage(nil)
    check("skins stay off the herb route", not GatherRoute.Kinds().skin)
    GatherRoute:SetPage("skin")
    check("the Leather page takes only skins", GatherRoute.Kinds().skin and not GatherRoute.Kinds().herb)
    skills.Skinning = nil
    check("no Skinning, no skin route", not GatherRoute.Kinds().skin)
    GatherRoute:SetPage(nil)
    ns.db.skinSpots = nil
    here[1], here[2], here[3] = 1, 0.1, 0.1
end

GatherRoute:SetPage("herb")
check("a page set before turning off", GatherRoute.page == "herb")
GatherRoute:SetOn(true)
GatherRoute:SetOn(false)
check("off again draws nothing", RouteMap.Plan() == nil and GrindingUI.OffersRouteMode("herbs") == false
    and GatherRoute.page == nil)
check("off saves false", ns.db.gatherRoute == false)

suite.done()
