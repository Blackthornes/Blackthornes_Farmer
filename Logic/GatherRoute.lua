local _, ns = ...
local L = ns.L

-- Gather Route (the owner said build it, 2026-11-15, from a mockup whose words he
-- approved): the Grind tab's Route view joins the herb and ore spots you
-- gathered yourself into one short loop, spots that should be back first,
-- and the arrow walks you round it. Only your own spots (Gathering:Spots),
-- only for gathering skills this character knows, never shipped or guild
-- data. Saved: the four settings, gatherRoute (on unless unticked, saved false),
-- gatherRouteZoneOnly, gatherRouteDraw and gatherRouteKinds; Route Mode's
-- tick on the Herbs, Ore and Leather pages (grindRouteMode, by page, off
-- unless ticked); and where you skinned (skinSpots), for Leather's route.

local GatherRoute = ns.NewModule("GatherRoute")

GatherRoute.MIN_SPOTS = 5       -- a zone needs this many spots for a route
GatherRoute.MAX_STOPS = 40      -- the nearest this many make the loop
GatherRoute.RUN_SPEED = 7       -- yards a second, running
GatherRoute.GATHER_SECONDS = 3  -- a gather, a stop
GatherRoute.ARRIVED = 12        -- yards: a stop you reach counts as checked
GatherRoute.REACH = 90          -- yards: the stop the arrow points at counts once you're this close (a node shows on the minimap well before you stand on it)
GatherRoute.LOOK = 1            -- seconds between looks while a route runs
GatherRoute.PASSES = 4          -- 2-opt passes over the loop
GatherRoute.COOLDOWN = 300      -- seconds a reached stop waits when its grow-back time isn't learned

-- Kinds of spot, the skill each needs and the tick that shows it.
GatherRoute.KINDS = {
    herb = { skill = "Herbalism", tick = "herbs", done = L["Picked"] },
    ore = { skill = "Mining", tick = "ore", done = L["Mined"] },
    skin = { skill = "Skinning", tick = "skins", done = L["Skinned"] },
}

-- The Grind page each kind's Route Mode tick sits on, and back.
GatherRoute.PAGES = { herbs = "herb", ore = "ore", skinning = "skin" }

GatherRoute.SKIN_JOIN = 30      -- yards: a skin this close to a spot of that mob joins it
GatherRoute.MAX_SKIN_SPOTS = 500

-- The kind the Grind page shows the route for (herb, ore or skin), or nil
-- for every ticked kind.
GatherRoute.page = nil

GatherRoute.version = 0

local function Clock() return ns.Gathering.Clock() end

local function Number(value)
    return ns.Harvest.ReadableNumber(value)
end

--------------------------------------------------------------------------------
-- Settings
--------------------------------------------------------------------------------

function GatherRoute.IsOn()
    return not (ns.db and ns.db.gatherRoute == false)
end

function GatherRoute:SetOn(on)
    if on then ns.db.gatherRoute = nil else ns.db.gatherRoute = false end
    if not on then
        self:Stop()
        self.page = nil
    end
    self:Changed()
    -- Route Mode's tick comes or goes on the Grind tab.
    local grind = ns.GrindingUI
    if grind and grind.view then
        pcall(grind.LayoutChips, grind)
        pcall(grind.Refresh, grind)
    end
end

--- Current Zone Only: on unless unticked.
function GatherRoute.ZoneOnly()
    return not (ns.db and ns.db.gatherRouteZoneOnly == false)
end

function GatherRoute:SetZoneOnly(on)
    if on then ns.db.gatherRouteZoneOnly = nil else ns.db.gatherRouteZoneOnly = false end
    self:Changed()
end

--- Draw on Maps: on unless unticked.
function GatherRoute.DrawsOnMaps()
    return not (ns.db and ns.db.gatherRouteDraw == false)
end

function GatherRoute:SetDraw(on)
    if on then ns.db.gatherRouteDraw = nil else ns.db.gatherRouteDraw = false end
    self:Changed()
end

--- Herbs and Ore on unless unticked, Skins off unless ticked.
function GatherRoute.Ticked(tick)
    local kinds = ns.db and type(ns.db.gatherRouteKinds) == "table" and ns.db.gatherRouteKinds
    local value = nil
    if kinds then value = kinds[tick] end
    if tick == "skins" then return value == true end
    return value ~= false
end

function GatherRoute:SetTicked(tick, on)
    if type(ns.db.gatherRouteKinds) ~= "table" then ns.db.gatherRouteKinds = {} end
    if tick == "skins" then
        ns.db.gatherRouteKinds[tick] = on and true or nil
    else
        if on then ns.db.gatherRouteKinds[tick] = nil else ns.db.gatherRouteKinds[tick] = false end
    end
    if next(ns.db.gatherRouteKinds) == nil then ns.db.gatherRouteKinds = nil end
    self:Changed()
end

--- Route Mode on the Grind page `gives` (herbs, ore or skinning): off
--- unless ticked, kept for each page.
function GatherRoute.RouteMode(gives)
    local modes = ns.db and type(ns.db.grindRouteMode) == "table" and ns.db.grindRouteMode
    return GatherRoute.PAGES[gives] ~= nil and modes and modes[gives] == true or false
end

function GatherRoute:SetRouteMode(gives, on)
    if not GatherRoute.PAGES[gives] then return end
    if type(ns.db.grindRouteMode) ~= "table" then ns.db.grindRouteMode = {} end
    ns.db.grindRouteMode[gives] = on and true or nil
    if next(ns.db.grindRouteMode) == nil then ns.db.grindRouteMode = nil end
    -- Unticked on the page the route follows: the route ends and leaves
    -- the maps.
    if not on and self.page == GatherRoute.PAGES[gives] then
        self:Stop()
        self.page = nil
    end
    self:Changed()
end

--- Leveling Mode on the Grind page `gives`: spots that still give skill
--- come first. Off unless ticked, kept for each page.
function GatherRoute.Leveling(gives)
    local modes = ns.db and type(ns.db.grindRouteLeveling) == "table" and ns.db.grindRouteLeveling
    return GatherRoute.PAGES[gives] ~= nil and modes and modes[gives] == true or false
end

function GatherRoute:SetLeveling(gives, on)
    if not GatherRoute.PAGES[gives] then return end
    if type(ns.db.grindRouteLeveling) ~= "table" then ns.db.grindRouteLeveling = {} end
    ns.db.grindRouteLeveling[gives] = on and true or nil
    if next(ns.db.grindRouteLeveling) == nil then ns.db.grindRouteLeveling = nil end
    self.order = nil
    self:Changed()
    if self.run then self:Aim(self:Plan()) end
end

--- The Grind page the route follows ("herbs", "ore", "skinning"), or nil.
function GatherRoute.PageGives()
    local page = GatherRoute.page
    if not page then return nil end
    for gives, kind in pairs(GatherRoute.PAGES) do
        if kind == page then return gives end
    end
    return nil
end

--- Leveling Mode for the page the route follows.
function GatherRoute.LevelingOn()
    local gives = GatherRoute.PageGives()
    return gives ~= nil and GatherRoute.Leveling(gives)
end

--- The route follows one kind of spot (herb, ore or skin), or every ticked
--- kind with nil.
function GatherRoute:SetPage(kind)
    if kind ~= nil and not GatherRoute.KINDS[kind] then kind = nil end
    if self.page == kind then return end
    if self.run then self:Stop() end
    self.page = kind
    self:Changed()
end

--- Tell what draws the route that it moved: the map lines and the Route
--- Window. Each is read in a pcall, so one never stops the other.
function GatherRoute.Tell()
    if ns.RouteMap and ns.RouteMap.Refresh then pcall(ns.RouteMap.Refresh, ns.RouteMap) end
    if ns.RouteWindow and ns.RouteWindow.Refresh then pcall(ns.RouteWindow.Refresh, ns.RouteWindow) end
end

function GatherRoute:Changed()
    GatherRoute.version = GatherRoute.version + 1
    self.cache = nil
    GatherRoute.Tell()
end

--------------------------------------------------------------------------------
-- What you know
--------------------------------------------------------------------------------

--- The gathering skills playing: { Herbalism = 142, ... }, and whether the
--- client said at all. A client that won't say lets every kind through.
function GatherRoute.Skills()
    local skills = ns.Spots.Skills()
    if type(skills) ~= "table" then return nil, false end
    return skills, true
end

--- Which kinds of spot a route takes: { herb = true, ore = true }.
function GatherRoute.Kinds()
    local skills, read = GatherRoute.Skills()
    local kinds = {}
    local page = GatherRoute.page
    if page then
        local info = GatherRoute.KINDS[page]
        if info and (not read or skills[info.skill]) then kinds[page] = true end
        return kinds
    end
    for kind, info in pairs(GatherRoute.KINDS) do
        if GatherRoute.Ticked(info.tick) and (not read or skills[info.skill]) then
            kinds[kind] = true
        end
    end
    return kinds
end

--- Does this character know Skinning? (Skins shows only then.)
function GatherRoute.KnowsSkinning()
    local skills, read = GatherRoute.Skills()
    return read and skills.Skinning ~= nil or false
end

--------------------------------------------------------------------------------
-- Zones
--------------------------------------------------------------------------------

--- The English zone a map ID is, or nil.
function GatherRoute.ZoneOf(mapID)
    local zone = ns.Spots.MAP_ZONES and ns.Spots.MAP_ZONES[mapID]
    if zone then return zone end
    if type(C_Map) == "table" and type(C_Map.GetMapInfo) == "function" then
        local ok, info = pcall(C_Map.GetMapInfo, mapID)
        if ok and type(info) == "table" and type(info.name) == "string" then
            return ns.Spots.English(info.name) or info.name
        end
    end
    return nil
end

--- Where you stand: map ID, x, y (0 to 1), or nil.
function GatherRoute.Here()
    local ok, map, x, y = pcall(ns.Harvest.PlayerMapPosition, ns.Harvest)
    if not ok then return nil end
    return Number(map), Number(x), Number(y)
end

--- Yards between two points on one map; map units when its size is not known.
function GatherRoute.Yards(mapID, ax, ay, bx, by)
    local width, height = ns.Gathering.MapSize(mapID)
    if width then
        local dx, dy = (ax - bx) * width, (ay - by) * height
        return math.sqrt(dx * dx + dy * dy), true
    end
    local dx, dy = ax - bx, ay - by
    return math.sqrt(dx * dx + dy * dy) * 1000, false
end

--- Where you skinned: { { map, x, y, node = mob, kind = "skin", gathers,
--- first, last } }, kept apart from your herb and ore spots so skins never
--- push them out.
function GatherRoute.SkinSpots()
    local db = ns.db
    if type(db.skinSpots) ~= "table" then db.skinSpots = {} end
    return db.skinSpots
end

--- A skin of `mob` where you stand, from GrindGather:NoteSkin: joins a spot
--- of that mob close by, else a new one. Only your own play.
function GatherRoute:NoteSkin(mob)
    if type(mob) ~= "string" or mob == "" or not ns.db then return end
    local map, x, y = GatherRoute.Here()
    if not (map and x and y) then return end
    local spots = GatherRoute.SkinSpots()
    local now = Clock()
    for _, spot in ipairs(spots) do
        if type(spot) == "table" and spot.map == map and spot.node == mob
            and Number(spot.x) and Number(spot.y)
            and GatherRoute.Yards(map, x, y, spot.x, spot.y) <= GatherRoute.SKIN_JOIN then
            spot.gathers = (Number(spot.gathers) or 1) + 1
            spot.last = now or spot.last
            ns.Gathering.spotsVersion = (ns.Gathering.spotsVersion or 0) + 1
            return spot
        end
    end
    local spot = { map = map, x = x, y = y, node = mob, kind = "skin", gathers = 1, first = now, last = now }
    spots[#spots + 1] = spot
    while #spots > GatherRoute.MAX_SKIN_SPOTS do
        local oldest, at = 1, math.huge
        for index, candidate in ipairs(spots) do
            local when = type(candidate) == "table" and Number(candidate.last) or 0
            if when < at then oldest, at = index, when end
        end
        table.remove(spots, oldest)
    end
    ns.Gathering.spotsVersion = (ns.Gathering.spotsVersion or 0) + 1
    return spot
end

--- Your spots for a route, by map ID: { [map] = { spot, ... } }.
function GatherRoute:SpotsByMap(kinds)
    local byMap = {}
    local function Add(spot)
        if type(spot) == "table" and kinds[spot.kind] and Number(spot.map)
            and Number(spot.x) and Number(spot.y)
            and not (ns.DB.HidesSource and ns.DB:HidesSource(spot.node)) then
            local list = byMap[spot.map]
            if not list then list = {}; byMap[spot.map] = list end
            list[#list + 1] = spot
        end
    end
    for _, spot in ipairs(ns.Gathering:Spots()) do Add(spot) end
    if kinds.skin and ns.db and type(ns.db.skinSpots) == "table" then
        for _, spot in ipairs(ns.db.skinSpots) do Add(spot) end
    end
    return byMap
end

--- What a gather of `node` in `zone` is worth, from your own pace, or nil.
function GatherRoute.WorthEach(zone, node)
    local pace = ns.db and ns.db.gathering and ns.db.gathering.pace
    local entry = type(pace) == "table" and pace[zone .. "|" .. tostring(node)]
    if type(entry) ~= "table" then return nil end
    local gathers = Number(entry.gathers)
    if not gathers or gathers <= 0 then return nil end
    local copper, priced = ns.GrindGather.Worth(entry.items)
    if not priced then return nil end
    return copper / gathers
end

--- Gold an hour from your own gathers in `zone` of nodes in `nodes`, or nil
--- while too little is behind it.
function GatherRoute.ZoneHour(zone, nodes)
    local pace = ns.db and ns.db.gathering and ns.db.gathering.pace
    if type(pace) ~= "table" then return nil end
    local seconds, copper, priced = 0, 0, false
    local prefix = zone .. "|"
    for key, entry in pairs(pace) do
        if type(key) == "string" and key:sub(1, #prefix) == prefix and type(entry) == "table" then
            local node = key:sub(#prefix + 1)
            if not nodes or nodes[node] then
                seconds = seconds + (Number(entry.seconds) or 0)
                local worth, any = ns.GrindGather.Worth(entry.items)
                if any then copper, priced = copper + worth, true end
            end
        end
    end
    if not priced or seconds < ns.GrindGather.MIN_SECONDS then return nil end
    return math.floor(copper / seconds * 3600 + 0.5)
end

--- Skins ticked: gold an hour from skinning the best mob you skinned that
--- you killed in `zone`, at your own kill pace, or nil.
function GatherRoute.SkinHour(zone)
    local log = ns.db and ns.db.skinLog
    if type(log) ~= "table" or not ns.Tracker or not ns.Stats then return nil end
    local best
    for mob in pairs(log) do
        local worth = ns.GrindGather:SkinWorth(mob)
        if worth then
            local here = false
            local ok, places = pcall(ns.Tracker.Places, ns.Tracker, mob)
            for _, place in ipairs(ok and places or {}) do
                if ns.Tracker.PlaceZone(place.name) == zone then here = true end
            end
            local okPace, seconds = pcall(ns.Stats.SecondsPerKill, ns.Stats, mob)
            if here and okPace and Number(seconds) and seconds > 0 then
                local hour = math.floor(worth * 3600 / seconds + 0.5)
                if not best or hour > best then best = hour end
            end
        end
    end
    return best
end

--------------------------------------------------------------------------------
-- The loop
--------------------------------------------------------------------------------

--- Is a spot's node back (or not known to be growing back)? Second, when
--- it should be back.
function GatherRoute.IsBack(spot, now)
    local ok, at = pcall(ns.Respawn.BackAt, ns.Respawn, spot)
    at = ok and Number(at) or nil
    if not at or not now then return true, nil end
    return at <= now, at
end

-- Stops you reached or gathered rest until they should be back, kept for the
-- session by place (spot tables are laid out again as spots move), so the
-- arrow never sends you back to a node still growing.
GatherRoute.cooldown = {}

function GatherRoute.SpotKey(spot)
    return table.concat({ tostring(spot.map), tostring(spot.x), tostring(spot.y), tostring(spot.node) }, "|")
end

--- When a stop reached or gathered at `now` should be back.
function GatherRoute.RestUntil(spot, now, gathered)
    if gathered then
        local ok, at = pcall(ns.Respawn.BackAt, ns.Respawn, spot)
        at = ok and Number(at) or nil
        if at and at > now then return at end
    end
    local seconds
    local ok, estimate = pcall(ns.Respawn.Estimate, ns.Respawn, spot.map, spot.node)
    if ok and type(estimate) == "table" then seconds = Number(estimate.seconds) end
    return now + (seconds or GatherRoute.COOLDOWN)
end

function GatherRoute:Rest(spot, now, gathered)
    if not now then return end
    local key = GatherRoute.SpotKey(spot)
    local untilAt = GatherRoute.RestUntil(spot, now, gathered)
    local had = GatherRoute.cooldown[key]
    if not had or untilAt > had then GatherRoute.cooldown[key] = untilAt end
end

--- The time a stop rests until, or nil once it may be up again.
function GatherRoute.Resting(spot, now)
    local untilAt = GatherRoute.cooldown[GatherRoute.SpotKey(spot)]
    if untilAt and now and untilAt > now then return untilAt end
    return nil
end

--- Order `spots` into a short path from (x, y): nearest each time, then
--- 2-opt. Up spots first, then the ones still growing back.
function GatherRoute.Order(mapID, spots, x, y, now)
    local up, waiting = {}, {}
    for _, spot in ipairs(spots) do
        if GatherRoute.IsBack(spot, now) then up[#up + 1] = spot else waiting[#waiting + 1] = spot end
    end

    local function Dist(a, b)
        return (GatherRoute.Yards(mapID, a.x, a.y, b.x, b.y))
    end

    local function Nearest(list, from)
        local path, left = {}, {}
        for i, spot in ipairs(list) do left[i] = spot end
        local at = from
        while #left > 0 do
            local best, bestYards = 1, math.huge
            for i, spot in ipairs(left) do
                local yards = Dist(at, spot)
                if yards < bestYards then best, bestYards = i, yards end
            end
            at = table.remove(left, best)
            path[#path + 1] = at
        end
        return path
    end

    -- 2-opt on an open path that starts at `from`.
    local function Untangle(path, from)
        local n = #path
        if n < 3 then return path end
        for _ = 1, GatherRoute.PASSES do
            local better = false
            for i = 1, n - 2 do
                local a = i == 1 and from or path[i - 1]
                local b = path[i]
                for j = i + 1, n - 1 do
                    local c, d = path[j], path[j + 1]
                    if Dist(a, b) + Dist(c, d) > Dist(a, c) + Dist(b, d) + 0.01 then
                        local lo, hi = i, j
                        while lo < hi do
                            path[lo], path[hi] = path[hi], path[lo]
                            lo, hi = lo + 1, hi - 1
                        end
                        b = path[i]
                        better = true
                    end
                end
            end
            if not better then break end
        end
        return path
    end

    local start = { x = x or (spots[1] and spots[1].x) or 0.5, y = y or (spots[1] and spots[1].y) or 0.5 }
    local first = Untangle(Nearest(up, start), start)
    local tail = first[#first] or start
    local second = Untangle(Nearest(waiting, tail), tail)
    for _, spot in ipairs(second) do first[#first + 1] = spot end
    return first
end

--- The nearest MAX_STOPS of `spots` to (x, y).
local function Nearest(mapID, spots, x, y)
    if #spots <= GatherRoute.MAX_STOPS or not (x and y) then
        local list = {}
        for i = 1, math.min(#spots, GatherRoute.MAX_STOPS) do list[i] = spots[i] end
        return list
    end
    local sorted = {}
    for i, spot in ipairs(spots) do
        sorted[i] = { spot = spot, yards = (GatherRoute.Yards(mapID, x, y, spot.x, spot.y)) }
    end
    table.sort(sorted, function(a, b) return a.yards < b.yards end)
    local list = {}
    for i = 1, GatherRoute.MAX_STOPS do list[i] = sorted[i].spot end
    return list
end

--------------------------------------------------------------------------------
-- The plan
--------------------------------------------------------------------------------

--- Every zone you could route, best first: { zone, map, spots, hour }.
function GatherRoute:Zones(byMap)
    local zones = {}
    local page = GatherRoute.page
    local skins
    if page then skins = page == "skin" else skins = GatherRoute.Ticked("skins") and GatherRoute.KnowsSkinning() end
    for map, spots in pairs(byMap) do
        local zone = GatherRoute.ZoneOf(map)
        if zone and #spots >= GatherRoute.MIN_SPOTS then
            local nodes, gathered = {}, false
            for _, spot in ipairs(spots) do
                if spot.kind ~= "skin" then nodes[spot.node] = true; gathered = true end
            end
            local hour = gathered and GatherRoute.ZoneHour(zone, nodes) or nil
            if skins then
                local skin = GatherRoute.SkinHour(zone)
                if skin then hour = (hour or 0) + skin end
            end
            zones[#zones + 1] = { zone = zone, map = map, spots = #spots, hour = hour }
        end
    end
    table.sort(zones, function(a, b)
        if (a.hour or -1) ~= (b.hour or -1) then return (a.hour or -1) > (b.hour or -1) end
        if a.spots ~= b.spots then return a.spots > b.spots end
        return a.zone < b.zone
    end)
    return zones
end

local function Stamp()
    return table.concat({
        tostring(ns.Gathering.spotsVersion or 0), tostring(GatherRoute.version),
        tostring(ns.GrindGather.paceVersion or 0), tostring(ns.DB.hiddenVersion or 0),
    }, "|")
end

--- The stop to go to next: of those not done, the one you can be gathering
--- soonest, the walk there from where you stand against when it should be
--- back; ties keep the loop's order. Away from the route's zone, the first
--- one up in the loop, else the one back soonest.
function GatherRoute.PickNext(stops, map, x, y, now)
    local best, bestScore
    local here = map and x and y and now
    for _, stop in ipairs(stops) do
        if not stop.done then
            local score
            if here then
                local walk = GatherRoute.Yards(map, x, y, stop.spot.x, stop.spot.y) / GatherRoute.RUN_SPEED
                score = math.max(stop.back and now or (stop.at or now), now + walk)
            elseif stop.back then
                score = -math.huge
            else
                score = stop.at or math.huge
            end
            if not bestScore or score < bestScore then best, bestScore = stop, score end
        end
    end
    return best
end

--- What the Route view shows. Laid out again when your spots, the settings
--- or the zone you stand in move, or once a second while it runs.
--- { zone, map, here (map you stand on), spotsHere, stops = { { spot, n,
--- yards, status, back, done, next } }, best, loopSeconds, loopWorth,
--- needs (spots still to gather here) }
function GatherRoute:Plan()
    local map, x, y = GatherRoute.Here()
    local now = Clock()
    local stamp = Stamp() .. "|" .. tostring(map)
    local cache = self.cache
    if cache and cache.stamp == stamp and cache.at and now and now - cache.at < GatherRoute.LOOK then
        return cache.plan
    end

    local kinds = GatherRoute.Kinds()
    local byMap = self:SpotsByMap(kinds)
    local zones = self:Zones(byMap)
    local plan = {
        here = map, hereZone = map and GatherRoute.ZoneOf(map) or nil,
        spotsHere = map and byMap[map] and #byMap[map] or 0,
        kinds = kinds, stops = {}, zones = zones,
    }

    -- The zone the route is for: where you stand, or with Current Zone Only
    -- unticked the best zone you know.
    local routeMap = map
    if not GatherRoute.ZoneOnly() and zones[1] then routeMap = zones[1].map end
    plan.map = routeMap
    plan.zone = routeMap and GatherRoute.ZoneOf(routeMap) or plan.hereZone

    for _, entry in ipairs(zones) do
        if entry.map ~= map then plan.best = entry; break end
    end
    if plan.best and zones[1] and zones[1].map == map then plan.best = nil end

    local spots = routeMap and byMap[routeMap] or {}
    plan.spotsZone = #spots
    if #spots < GatherRoute.MIN_SPOTS then
        plan.needs = GatherRoute.MIN_SPOTS
        self.cache = { stamp = stamp, at = now, plan = plan }
        return plan
    end

    local fromX, fromY = nil, nil
    if routeMap == map then fromX, fromY = x, y end
    local order = self:Kept(routeMap, spots, fromX, fromY, now)
    local tiers
    if GatherRoute.LevelingOn() then
        order, tiers = GatherRoute.ByTier(order)
        plan.leveling = true
    end

    local run = self.run
    local walked, previous = 0, fromX and { x = fromX, y = fromY } or nil
    local worth = 0
    for n, spot in ipairs(order) do
        local stop = { spot = spot, n = n, tier = tiers and tiers[spot] or nil }
        stop.done = run and run.map == routeMap and run.visited[spot] or false
        if stop.done and run.picked[spot] then stop.picked = true end
        local back, at = GatherRoute.IsBack(spot, now)
        local resting = GatherRoute.Resting(spot, now)
        if resting then
            back = false
            if not at or resting > at then at = resting end
            stop.resting = true
        end
        stop.back = back
        stop.at = at
        if previous then
            stop.leg = (GatherRoute.Yards(routeMap, previous.x, previous.y, spot.x, spot.y))
            walked = walked + stop.leg
        end
        if fromX then
            stop.yards = math.floor(GatherRoute.Yards(routeMap, fromX, fromY, spot.x, spot.y) + 0.5)
        end
        local each
        if spot.kind == "skin" then
            local ok, skin = pcall(ns.GrindGather.SkinWorth, ns.GrindGather, spot.node)
            each = ok and Number(skin) or nil
        else
            each = GatherRoute.WorthEach(plan.zone or "", spot.node)
        end
        if each then worth = worth + each end
        previous = spot
        plan.stops[n] = stop
    end
    local pick = GatherRoute.PickNext(GatherRoute.BestTier(plan.stops), routeMap, fromX, fromY, now)
    if pick then pick.next, plan.nextStop = true, pick end

    -- Back to the start closes the loop.
    local first, last = order[1], order[#order]
    if first and last and first ~= last then
        walked = walked + (GatherRoute.Yards(routeMap, last.x, last.y, first.x, first.y))
    end
    plan.loopSeconds = walked / GatherRoute.RUN_SPEED + #order * GatherRoute.GATHER_SECONDS
    plan.loopWorth = worth > 0 and math.floor(worth + 0.5) or nil

    self.cache = { stamp = stamp, at = now, plan = plan }
    return plan
end

--------------------------------------------------------------------------------
-- Leveling Mode
--------------------------------------------------------------------------------

-- 1 orange, 2 yellow, 3 green, 4 grey: the skill colour a spot gathers in.
GatherRoute.TIER_COLORS = { "orange", "yellow", "green", "grey" }

--- The skill colour of a stop in Leveling Mode ({ r, g, b }), or nil.
function GatherRoute.TierColor(stop)
    if type(stop) ~= "table" or not stop.tier then return nil end
    local name = GatherRoute.TIER_COLORS[stop.tier]
    local colors = ns.NodeSparkle and ns.NodeSparkle.COLORS
    local color = name and type(colors) == "table" and colors[name]
    if type(color) ~= "table" then return nil end
    return color
end

local skinLevels, skinLevelsAt

--- The lowest level you saw a mob at, from your own loot records.
function GatherRoute.SkinLevel(mob)
    local harvest = ns.Harvest
    if not (harvest and type(mob) == "string") then return nil end
    local stamp = harvest.changes or 0
    if not skinLevels or skinLevelsAt ~= stamp then
        skinLevels, skinLevelsAt = {}, stamp
        for _, record in pairs(harvest.records or {}) do
            if type(record) == "table" and type(record.mob) == "string" then
                local level = Number(record.minLevel)
                if level and (not skinLevels[record.mob] or level < skinLevels[record.mob]) then
                    skinLevels[record.mob] = level
                end
            end
        end
    end
    return skinLevels[mob]
end

--- The skill a spot needs, or nil when nothing says.
function GatherRoute.Need(spot)
    if type(spot) ~= "table" then return nil end
    if spot.kind == "skin" then
        local level = GatherRoute.SkinLevel(spot.node)
        return level and ns.Grinding and ns.Grinding.SkinSkill(level) or nil
    end
    local sparkle = ns.NodeSparkle
    if not (sparkle and sparkle.NodeNeeds) then return nil end
    local ok, _, need = pcall(sparkle.NodeNeeds, sparkle, spot.node)
    return ok and Number(need) or nil
end

--- Which colour a spot gathers in at `skill`: 1 orange, 2 yellow, 3 green
--- (also when its need isn't known), 4 grey (nothing to learn, or out of
--- reach).
function GatherRoute.Tier(spot, skill)
    local need = GatherRoute.Need(spot)
    skill = Number(skill)
    if not (need and skill) then return 3 end
    local over = skill - need
    if over < 0 then return 4 end
    if over < ns.GatherToCap.SURE_FOR then return 1 end
    if over < 50 then return 2 end
    if over < ns.GatherToCap.GREY_AT then return 3 end
    return 4
end

--- The loop sorted orange first, grey last, keeping the loop's order inside
--- each colour. Gives the new list and each spot's tier.
function GatherRoute.ByTier(order)
    local skills = GatherRoute.Skills()
    local tiers, list = {}, {}
    for index, spot in ipairs(order) do
        local info = GatherRoute.KINDS[spot.kind]
        local skill = type(skills) == "table" and info and skills[info.skill] or nil
        tiers[spot] = GatherRoute.Tier(spot, skill)
        list[index] = spot
    end
    local place = {}
    for index, spot in ipairs(order) do place[spot] = index end
    table.sort(list, function(a, b)
        if tiers[a] ~= tiers[b] then return tiers[a] < tiers[b] end
        return place[a] < place[b]
    end)
    return list, tiers
end

--- The stops still to do in the best colour left; all of them without
--- Leveling Mode.
function GatherRoute.BestTier(stops)
    local best
    for _, stop in ipairs(stops) do
        if not stop.done and stop.tier and (not best or stop.tier < best) then best = stop.tier end
    end
    if not best then return stops end
    local out = {}
    for _, stop in ipairs(stops) do
        if not stop.done and stop.tier == best then out[#out + 1] = stop end
    end
    return out
end

--- When to train: { skill, cap, rank, english, at (at the cap), near } for
--- the page's skill within 5 of its cap, else nil.
function GatherRoute.TrainInfo()
    local info = GatherRoute.page and GatherRoute.KINDS[GatherRoute.page]
    if not info then return nil end
    local skill, cap = ns.GatherToCap.ReadSkill(info.skill)
    if not (skill and cap) then return nil end
    local rank = ns.GatherToCap.NextRank(cap)
    if not rank or skill < cap - 5 then return nil end
    return { skill = skill, cap = cap, rank = rank.key, english = info.skill, at = skill >= cap }
end

--- The train line's words and colour key, or nil.
function GatherRoute.TrainText()
    local train = GatherRoute.TrainInfo()
    if not train then return nil end
    local rank = ns.GatherToCap.RankLabel(train.rank)
    local skill = ns.GatherToCap.SkillLabel(train.english)
    if train.at then
        return L.Format("You've hit %d. Train %s %s at a trainer to get more skill.", train.cap, rank, skill), "loss"
    end
    return L.Format("Train %s %s to keep going. Your skill stops at %d.", rank, skill, train.cap), "warn"
end

--- "Stop 3 of 14. One loop: about 6 min.", or with Leveling Mode
--- "Herbalism 72 / 75. Stop 1 of 14."
function GatherRoute.FootText(plan)
    if not (plan and plan.nextStop and plan.stops and #plan.stops > 0) then return "" end
    local n, total = plan.nextStop.n, #plan.stops
    local info = plan.leveling and GatherRoute.page and GatherRoute.KINDS[GatherRoute.page]
    if info then
        local skill, cap = ns.GatherToCap.ReadSkill(info.skill)
        if skill and cap then
            return L.Format("%s %d / %d. Stop %d of %d.", ns.GatherToCap.SkillLabel(info.skill), skill, cap, n, total)
        end
    end
    return L.Format("Stop %d of %d. One loop: about %s.", n, total, ns.Respawn.Duration(plan.loopSeconds or 0))
end

--- The order for a map, kept until Redo Route, the spots or the settings
--- move, so the rows don't jump about as you walk.
function GatherRoute:Kept(map, spots, x, y, now)
    local key = table.concat({ tostring(map), Stamp() }, "|")
    local kept = self.order
    if kept and kept.key == key then return kept.list end
    local list = GatherRoute.Order(map, Nearest(map, spots, x, y), x, y, now)
    self.order = { key = key, list = list }
    return list
end

--- Lay the loop out again from where you stand.
function GatherRoute:Redo()
    self.order, self.cache = nil, nil
    if self.run then
        self.run.visited, self.run.picked = {}, {}
        self.run.started = Clock()
    end
    local plan = self:Plan()
    if self.run then self:Aim(plan) end
    GatherRoute.Tell()
    return plan
end

--------------------------------------------------------------------------------
-- Walking it
--------------------------------------------------------------------------------

function GatherRoute.Running()
    return GatherRoute.run ~= nil
end

--- A one stop camp for the arrow.
function GatherRoute.Camp(zone, spot)
    local coords = { spot.x * 100, spot.y * 100, map = spot.map }
    return {
        zone = zone, label = spot.node, route = true,
        mobs = { { name = spot.node, zone = zone, coords = coords, kind = "node" } },
        count = 1, coords = coords,
    }
end

--- Point the arrow at the plan's next stop.
function GatherRoute:Aim(plan)
    plan = plan or self:Plan()
    local stop = plan and plan.nextStop
    if not (stop and plan.zone) then return false end
    local camp = GatherRoute.Camp(plan.zone, stop.spot)
    self.camp = camp
    if self.run then self.run.aimed = stop.spot end
    return ns.Arrow:Grind(camp)
end

--- Show the Way to another zone: the arrow to the nearest of your spots
--- there (the first when you stand elsewhere).
function GatherRoute:ShowZone(entry)
    if type(entry) ~= "table" or not entry.map then return false end
    local byMap = self:SpotsByMap(GatherRoute.Kinds())
    local spots = byMap[entry.map]
    if not spots or #spots == 0 then return false end
    local map, x, y = GatherRoute.Here()
    local pick = spots[1]
    if map == entry.map and x and y then
        local best
        for _, spot in ipairs(spots) do
            local yards = GatherRoute.Yards(map, x, y, spot.x, spot.y)
            if not best or yards < best then best, pick = yards, spot end
        end
    end
    local zone = entry.zone or GatherRoute.ZoneOf(entry.map)
    if not zone then return false end
    return ns.Arrow:Grind(GatherRoute.Camp(zone, pick))
end

--- Start Route: the arrow leads you stop to stop.
function GatherRoute:Start()
    local plan = self:Plan()
    if not (plan and plan.nextStop) then return false end
    self.run = { map = plan.map, visited = {}, picked = {}, started = Clock() }
    self.cache = nil
    local ok = self:Aim(self:Plan())
    self:Watch(true)
    GatherRoute.Tell()
    return ok
end

function GatherRoute:Stop()
    local had = self.run ~= nil
    self.run = nil
    self:Watch(false)
    if had and ns.Arrow.grind and ns.Arrow.grind == self.camp then ns.Arrow:StopGrind() end
    self.camp, self.cache = nil, nil
    GatherRoute.Tell()
    return had
end

--- Skip Stop: on to the one after.
function GatherRoute:Skip()
    local plan = self:Plan()
    local stop = plan and plan.nextStop
    if not stop then return false end
    if not self.run then return self:Start() end
    self.run.visited[stop.spot] = true
    return self:Advance()
end

--- After a stop: aim at the next, or start the loop again.
function GatherRoute:Advance()
    self.cache = nil
    local plan = self:Plan()
    local left = false
    for _, stop in ipairs(plan.stops) do
        if not stop.done then left = true end
    end
    if not left then
        self.run.visited, self.run.picked = {}, {}
        self.run.started = Clock()
        self.order, self.cache = nil, nil
        plan = self:Plan()
    end
    self:Aim(plan)
    GatherRoute.Tell()
    return true
end

--- Yards within which a gather counts for a stop of the same kind, though
--- the game named the node another way (a herb spot can grow another herb).
GatherRoute.PICK_NEAR = 15

--- Your gathers on the route's map since `started`, looked for only when
--- your spots changed: { spot, ... }.
function GatherRoute:FreshGathers(run, started)
    local stamp = Stamp() .. "|" .. tostring(started)
    if run.freshStamp == stamp then return run.fresh or {} end
    run.freshStamp = stamp
    local fresh = {}
    local byMap = self:SpotsByMap(GatherRoute.Kinds())
    for _, spot in ipairs(byMap[run.map] or {}) do
        local last = Number(spot.last)
        if last and last >= started then fresh[#fresh + 1] = spot end
    end
    run.fresh = fresh
    return fresh
end

--- True when one of the `fresh` gathers is the same kind and within
--- PICK_NEAR yards of `spot`: picked, out of order or under another name.
function GatherRoute.PickedNear(spot, fresh, within)
    within = within or GatherRoute.PICK_NEAR
    for _, gathered in ipairs(fresh or {}) do
        if gathered ~= spot and gathered.kind == spot.kind and gathered.map == spot.map
            and (GatherRoute.Yards(spot.map, spot.x, spot.y, gathered.x, gathered.y) or math.huge) <= within then
            return true
        end
    end
    return false
end

--- How close counts as reaching `spot`: REACH for the stop the arrow points
--- at, once you were farther than that from it since it was aimed (so a stop
--- that comes next while you already stand near it is never skipped unseen);
--- ARRIVED for the rest, so passing a stop on the way doesn't check it.
function GatherRoute.Reach(run, spot)
    if run and spot and run.aimed == spot and run.cameFrom == spot then return GatherRoute.REACH end
    return GatherRoute.ARRIVED
end

--- One look while a route runs: a stop you picked (in order or not, or a
--- different herb grown at its place), or came within its reach of, is
--- done and rests until it should be back. Picking a node of its kind near
--- the stop the arrow points at moves on too.
function GatherRoute:Look()
    local run = self.run
    if not run then return end
    -- The arrow taken over by something else ends the route.
    if self.camp and ns.Arrow.grind ~= self.camp then
        self:Stop()
        return
    end
    local map, x, y = GatherRoute.Here()
    local started = run.started or 0
    local now = Clock()
    local moved = false
    local fresh = self:FreshGathers(run, started)
    local aimed = run.aimed
    for _, spot in ipairs(self.order and self.order.list or {}) do
        if not run.visited[spot] then
            local last = Number(spot.last)
            local yards = (map == spot.map and x and y) and GatherRoute.Yards(map, x, y, spot.x, spot.y) or nil
            if spot == aimed and yards and yards > GatherRoute.REACH then run.cameFrom = spot end
            if (last and last >= started) or GatherRoute.PickedNear(spot, fresh) then
                run.visited[spot], run.picked[spot] = true, true
                self:Rest(spot, now, true)
                moved = true
            elseif spot == aimed and GatherRoute.PickedNear(spot, fresh, GatherRoute.REACH) then
                -- You picked another node close by: this one was taken or
                -- gone, so on to the next.
                run.visited[spot] = true
                self:Rest(spot, now, false)
                moved = true
            elseif yards and yards <= GatherRoute.Reach(run, spot) then
                -- Reached, gathered or not: on to the next, and this one
                -- rests until it should be back.
                run.visited[spot] = true
                self:Rest(spot, now, false)
                moved = true
            end
        end
    end
    if moved then
        self:Advance()
        return
    end
    -- The plan picks the next stop again as you move, so it can move on
    -- before the aimed stop is reached. The Route list and the minimap show
    -- the plan's pick; the arrow follows it too (Trent, 2026-11-26).
    local plan = self:Plan()
    local stop = plan and plan.nextStop
    if stop and stop.spot ~= run.aimed then
        self:Aim(plan)
        GatherRoute.Tell()
    end
end

function GatherRoute:Watch(on)
    if self.ticker then
        pcall(self.ticker.Cancel, self.ticker)
        self.ticker = nil
    end
    if on and type(C_Timer) == "table" and type(C_Timer.NewTicker) == "function" then
        self.ticker = C_Timer.NewTicker(GatherRoute.LOOK, function() GatherRoute:Look() end)
    end
end

--------------------------------------------------------------------------------
-- Words
--------------------------------------------------------------------------------

--- A stop's status: its words and colour key.
function GatherRoute.Status(stop, now)
    if stop.done then
        if stop.picked then
            local info = GatherRoute.KINDS[stop.spot.kind]
            return info and info.done or L["Picked"], "good"
        end
        return L["Checked"], "muted"
    end
    if stop.next then return L["Go here next"], "accentHi" end
    if stop.tier == 4 then return L["No skill here"], "muted" end
    if stop.back or not stop.at or not now then return L["Should be up"], "text" end
    return L.Format("Back in %s", ns.Respawn.Duration(stop.at - now)), "muted"
end

--- "Herbalism 142 · Mining 118 · Skinning 130"
function GatherRoute.SkillLine()
    local skills = GatherRoute.Skills()
    if type(skills) ~= "table" then return "" end
    local parts = {}
    local words = { Herbalism = L["Herbalism"], Mining = L["Mining"], Skinning = L["Skinning"] }
    for _, name in ipairs({ "Herbalism", "Mining", "Skinning" }) do
        local skill = Number(skills[name])
        if skill then
            parts[#parts + 1] = ("%s %d"):format(words[name], skill)
        end
    end
    return table.concat(parts, " · ")
end

--------------------------------------------------------------------------------
-- /farm route
--------------------------------------------------------------------------------

ns.RegisterCommand("route", L["Gather Route on the Grind tab: on or off"], function(rest)
    local word = (rest or ""):lower():match("^%s*(%S*)")
    if word == "on" or word == "off" then
        GatherRoute:SetOn(word == "on")
    elseif word == "" then
        GatherRoute:SetOn(not GatherRoute.IsOn())
    end
    if GatherRoute.IsOn() then
        ns.Print(L["Gather Route is on. Tick Route Mode on the Grind tab."])
    else
        ns.Print(L["Gather Route is off."])
    end
    if ns.GrindingUI and ns.GrindingUI.Refresh then pcall(ns.GrindingUI.Refresh, ns.GrindingUI) end
end)
