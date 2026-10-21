-- Blackthornes Farmer -- Logic/Travel.lua
-- Trips for the arrow (the owner, 2026-10-21: "guide players outside of
-- current zones and across continents"). A place in another zone or on the
-- other continent gets a way there, step by step, and the arrow points at
-- the next stop instead of straight over mountains and sea.
--
-- The travel map:
--
--   * Flight masters and the flights between them, from the Forever client's
--     game tables (Data/Travel.lua, tools/make_travel.py). Only your side's,
--     and only flights this character knows: read at a flight master when
--     its map opens (TAXIMAP_OPENED), kept per character by GUID in
--     `travelFlights[guid] = { [node] = true }`. Never one it has not seen.
--   * Boats and zeppelins between docks (Data/Travel.lua), your side's.
--   * Your Hearthstone, once the spot it lands on has been seen: kept,
--     account wide, by the inn's name in `travelHearth[bind]`.
--   * Walking between any two stops on one continent. When the walk passes
--     through other zones, the arrow aims at the spot you crossed that
--     border before (`travelCrossings["From|To"]`, account wide, learned as
--     you walk), else at the nearest edge of the next zone, "toward NAME".
--     Never a made up spot.
--
-- The quickest way is a shortest-path search over that map, cost in
-- seconds. The plan is worked out again only when it could have changed (a
-- new place, a zone change, a landing, a flight learned) or every REPLAN
-- seconds, never mid flight, never in a fight. The steps already behind you
-- are counted so "Step 2 of 3" holds as you go.
--
-- The same file goes in every Blackthornes addon with an arrow; each copy
-- signs up in `_G.BlackthornesTravel` and the one with the highest
-- FILE_VERSION plans for all of them. A fix to it belongs in all of them.
--
-- Saved, never renamed: `arrowRoute` (off unless ticked), `travelFlights`,
-- `travelCrossings`, `travelHearth`. Nothing is shared with anyone.

local _, ns = ...
local L = ns.L

local Travel = ns.NewModule("Travel")

Travel.FILE_VERSION = 1

-- Rough speeds and waits, yards a second and seconds.
Travel.WALK_SPEED = 8
Travel.WALK_DETOUR = 1.25
Travel.FLIGHT_SPEED = 32
Travel.FLIGHT_DETOUR = 1.3
Travel.FLIGHT_WAIT = 20
Travel.RIDE_COST = { boat = 300, zeppelin = 240 }
Travel.HEARTH_COST = 40

-- How near a stop counts as there, yards.
Travel.AT_STOP = 30

-- Seconds between plans while nothing happened.
Travel.REPLAN = 15

-- Hearthstone: the item and the spell it casts.
Travel.HEARTHSTONE = 6948
Travel.HEARTH_SPELL = 8690

-- A crossing keeps the average of at most this many walks.
Travel.CROSSING_KEEP = 20

local DATA = ns.TRAVEL_DATA or { flights = {}, paths = {}, docks = {}, rides = {} }
Travel.DATA = DATA

local Readable = function(value) return ns.Harvest.Readable(value) end
local Number = function(value) return ns.Harvest.ReadableNumber(value) end

local function Read(fn, ...)
    if type(fn) ~= "function" then return nil end
    local result = { pcall(fn, ...) }
    if not result[1] then return nil end
    return unpack(result, 2)
end

local function Clock()
    return type(GetTime) == "function" and (Read(GetTime) or 0) or 0
end

--------------------------------------------------------------------------------
-- One planner for every addon
--------------------------------------------------------------------------------

local shared = _G.BlackthornesTravel
if type(shared) ~= "table" then
    shared = { copies = {} }
    _G.BlackthornesTravel = shared
end
shared.copies = type(shared.copies) == "table" and shared.copies or {}
shared.copies["Blackthornes_Farmer"] = { version = Travel.FILE_VERSION, module = Travel }

--- The copy that plans: the highest FILE_VERSION, Farmer's on a tie.
function Travel.Planner()
    local best
    for addon, copy in pairs(shared.copies) do
        if type(copy) == "table" and type(copy.module) == "table" then
            if not best or (copy.version or 0) > (best.version or 0)
                or ((copy.version or 0) == (best.version or 0) and addon == "Blackthornes_Farmer") then
                best = copy
            end
        end
    end
    return best and best.module or Travel
end

--------------------------------------------------------------------------------
-- Switches and what you have learned
--------------------------------------------------------------------------------

function Travel.IsOn()
    return ns.db ~= nil and ns.db.arrowRoute == true
end

function Travel:SetOn(on)
    ns.db.arrowRoute = on and true or false
    self:Forget()
    if ns.Arrow and ns.Arrow.Changed then ns.Arrow:Changed() end
end

local function Store(key)
    if type(ns.db[key]) ~= "table" then ns.db[key] = {} end
    return ns.db[key]
end

--- The flights this character knows: { [node] = true }, or nil while the
--- client will not say who is playing.
function Travel:KnownFlights()
    local guid = ns.Goals and ns.Goals:Owner()
    if not guid then return nil end
    local all = Store("travelFlights")
    if type(all[guid]) ~= "table" then all[guid] = {} end
    return all[guid]
end

--- "A", "H", or nil while the client will not say.
function Travel.Side()
    if type(UnitFactionGroup) ~= "function" then return nil end
    local faction = Readable(Read(UnitFactionGroup, "player"))
    if faction == "Alliance" then return "A" end
    if faction == "Horde" then return "H" end
    return nil
end

local function SideAllows(rowSide, side)
    if rowSide == "AH" then return true end
    return side ~= nil and rowSide == side
end

--- Reads the flight master's map: the flights it shows as known.
function Travel:ReadFlightMap()
    local known = self:KnownFlights()
    if not known then return 0 end
    local added = 0

    local taxi = _G.C_TaxiMap
    local mapID = ns.Harvest and ns.Harvest.PlayerMapPosition and ns.Harvest:PlayerMapPosition()
    local nodes = taxi and mapID and Read(taxi.GetAllTaxiNodes, mapID)
    if type(nodes) == "table" then
        for _, node in ipairs(nodes) do
            local ok, id, state = pcall(function() return node.nodeID, node.state end)
            id, state = ok and Number(id), ok and Number(state)
            -- Current (0) or reachable (1); unreachable (2) is not known.
            if id and DATA.flights[id] and (state == 0 or state == 1) and not known[id] then
                known[id], added = true, added + 1
            end
        end
    elseif type(NumTaxiNodes) == "function" then
        -- An older client: by name, English only.
        local byName = {}
        for id, row in pairs(DATA.flights) do byName[row[1]] = id end
        for index = 1, Number(Read(NumTaxiNodes)) or 0 do
            local kind = Readable(Read(TaxiNodeGetType, index))
            local id = byName[Readable(Read(TaxiNodeName, index)) or ""]
            if id and (kind == "CURRENT" or kind == "REACHABLE") and not known[id] then
                known[id], added = true, added + 1
            end
        end
    end
    if added > 0 then self:Forget() end
    return added
end

--- Keeps where you crossed from one zone into the next, on foot.
function Travel:NoteCrossing(from, to, here)
    if not (from and to and from ~= to and here and here.continent) then return end
    local borders = ns.Spots.BORDERS
    local near = false
    for _, zone in ipairs(borders[from] or {}) do
        if zone == to then near = true end
    end
    if not near then return end

    local crossings = Store("travelCrossings")
    local key = from .. "|" .. to
    local kept = crossings[key]
    if type(kept) ~= "table" or kept[1] ~= here.continent then
        crossings[key] = { here.continent, math.floor(here.north + 0.5), math.floor(here.west + 0.5), 1 }
        return
    end
    local count = math.min((tonumber(kept[4]) or 1), Travel.CROSSING_KEEP)
    kept[2] = math.floor((kept[2] * count + here.north) / (count + 1) + 0.5)
    kept[3] = math.floor((kept[3] * count + here.west) / (count + 1) + 0.5)
    kept[4] = count + 1
end

--- The spot you crossed from `from` into `to` before: continent, north, west.
function Travel:Crossing(from, to)
    local kept = type(ns.db.travelCrossings) == "table" and ns.db.travelCrossings[from .. "|" .. to]
    if type(kept) ~= "table" then return nil end
    return tonumber(kept[1]), tonumber(kept[2]), tonumber(kept[3])
end

--- Where your Hearthstone takes you, when that spot has been seen and it is
--- ready: { continent, north, west, zone, name }, or nil.
function Travel:Hearth()
    local bind = type(GetBindLocation) == "function" and Readable(Read(GetBindLocation))
    local kept = bind and type(ns.db.travelHearth) == "table" and ns.db.travelHearth[bind]
    if type(kept) ~= "table" then return nil end

    local count = Number(Read(_G.GetItemCount or (_G.C_Item and _G.C_Item.GetItemCount), Travel.HEARTHSTONE))
    if not count or count < 1 then return nil end
    local getCooldown = (_G.C_Container and _G.C_Container.GetItemCooldown) or _G.GetItemCooldown
    local start, duration = Read(getCooldown, Travel.HEARTHSTONE)
    start, duration = Number(start) or 0, Number(duration) or 0
    if start > 0 and duration > 2 and start + duration - Clock() > 1 then return nil end

    return { continent = kept[1], north = kept[2], west = kept[3], zone = kept[4], name = bind }
end

--------------------------------------------------------------------------------
-- The plan
--------------------------------------------------------------------------------

local function Distance(a, b)
    local north, west = a.north - b.north, a.west - b.west
    return math.sqrt(north * north + west * west)
end

local function WalkCost(a, b)
    return Distance(a, b) * Travel.WALK_DETOUR / Travel.WALK_SPEED
end

--- A flight master's name as players say it: "Stormwind", not
--- "Stormwind, Elwynn".
function Travel.ShortName(name)
    return (type(name) == "string" and name:match("^([^,]+)")) or name
end

--- The stops this character can use: flight masters it knows, docks of its
--- side. Each { key, kind, name, continent, north, west, zone, node, dock }.
function Travel:Stops(side, known)
    local stops = {}
    for id, row in pairs(DATA.flights or {}) do
        if known and known[id] and SideAllows(row[2], side) then
            stops["f" .. id] = {
                key = "f" .. id, kind = "flight", node = id, name = Travel.ShortName(row[1]),
                continent = row[3], north = row[4], west = row[5], zone = row[6],
            }
        end
    end
    for key, row in pairs(DATA.docks or {}) do
        stops["d" .. key] = {
            key = "d" .. key, kind = "dock", dock = key, name = row[1],
            continent = row[2], north = row[3], west = row[4], zone = row[5],
        }
    end
    return stops
end

--- The rides between stops: { [from] = { { to, kind, cost }, ... } }.
function Travel:Rides(stops, side)
    local rides = {}
    local function Add(from, to, kind, cost)
        if not (stops[from] and stops[to]) then return end
        rides[from] = rides[from] or {}
        table.insert(rides[from], { to = to, kind = kind, cost = cost })
    end

    local paths = DATA.paths or {}
    for index = 1, #paths - 1, 2 do
        local from, to = "f" .. paths[index], "f" .. paths[index + 1]
        if stops[from] and stops[to] then
            local cost = Distance(stops[from], stops[to]) * Travel.FLIGHT_DETOUR / Travel.FLIGHT_SPEED
            Add(from, to, "fly", cost)
        end
    end
    for _, ride in ipairs(DATA.rides or {}) do
        if SideAllows(ride[4], side) then
            local cost = Travel.RIDE_COST[ride[3]] or 300
            Add("d" .. ride[1], "d" .. ride[2], ride[3], cost)
            Add("d" .. ride[2], "d" .. ride[1], ride[3], cost)
        end
    end
    return rides
end

--- The quickest way from `from` to `to` (each { continent, north, west,
--- zone }): a list of legs { kind, from, to, cost }, kind "walk", "fly",
--- "boat", "zeppelin" or "hearth", and the whole cost in seconds. Nil when
--- there is no way the character can take.
function Travel:Search(from, to, side, known, hearth)
    local stops = self:Stops(side, known)
    stops.start = { key = "start", kind = "start", continent = from.continent, north = from.north, west = from.west, zone = from.zone }
    stops.goal = { key = "goal", kind = "goal", continent = to.continent, north = to.north, west = to.west, zone = to.zone, name = to.name }
    if hearth then
        stops.hearth = { key = "hearth", kind = "hearth", continent = hearth.continent, north = hearth.north,
            west = hearth.west, zone = hearth.zone, name = hearth.name }
    end
    local rides = self:Rides(stops, side)
    if hearth then rides.start = { { to = "hearth", kind = "hearth", cost = Travel.HEARTH_COST } } end

    local cost, back, how, done = { start = 0 }, {}, {}, {}
    while true do
        local current, best
        for key, value in pairs(cost) do
            if not done[key] and (not best or value < best) then current, best = key, value end
        end
        if not current or current == "goal" then break end
        done[current] = true
        local stop = stops[current]

        local function Relax(key, kind, extra)
            local total = best + extra
            if not done[key] and (cost[key] == nil or total < cost[key]) then
                cost[key], back[key], how[key] = total, current, kind
            end
        end

        for key, other in pairs(stops) do
            if key ~= current and key ~= "start" and key ~= "hearth" and other.continent == stop.continent then
                Relax(key, "walk", WalkCost(stop, other))
            end
        end
        for _, ride in ipairs(rides[current] or {}) do Relax(ride.to, ride.kind, ride.cost) end
    end

    if cost.goal == nil then return nil end
    local legs, key = {}, "goal"
    while key ~= "start" do
        table.insert(legs, 1, { kind = how[key], from = stops[back[key]], to = stops[key] })
        key = back[key]
    end
    return legs, cost.goal
end

--- Legs as the steps a player reads. A walk to a stop folds into the ride
--- that leaves from it, flights in a row are one flight, and only the last
--- walk is a step of its own.
function Travel.Steps(legs)
    local steps = {}
    for _, leg in ipairs(legs or {}) do
        local last = steps[#steps]
        if leg.kind == "walk" then
            if leg.to.kind == "goal" then
                table.insert(steps, { kind = "walk", to = leg.to, from = leg.from })
            end
        elseif leg.kind == "fly" and last and last.kind == "fly" and last.to == leg.from then
            last.to = leg.to
        else
            table.insert(steps, { kind = leg.kind, from = leg.from, to = leg.to })
        end
    end
    return steps
end

--- The zones a walk on one continent passes through, in order, by the zone
--- borders (Spots.BORDERS); nil when the borders do not join them.
function Travel.ZonePath(from, to)
    local borders = ns.Spots.BORDERS
    if not (from and to and borders[from] and borders[to]) then return nil end
    if from == to then return { from } end
    local back, queue, head = { [from] = false }, { from }, 1
    while queue[head] do
        local zone = queue[head]
        head = head + 1
        for _, near in ipairs(borders[zone] or {}) do
            if back[near] == nil then
                back[near] = zone
                if near == to then
                    local path = { to }
                    local step = zone
                    while step do
                        table.insert(path, 1, step)
                        step = back[step] or nil
                    end
                    return path
                end
                table.insert(queue, near)
            end
        end
    end
    return nil
end

--- A place as world coordinates: { continent, north, west, zone, name }.
function Travel:WorldOf(target)
    if type(target) ~= "table" then return nil end
    local zone = ns.Spots.ZoneOf(target.zone)
    local continent, north, west
    if target.map and target.x and target.y then
        continent, north, west = ns.Arrow.WorldPos(target.map, target.x, target.y)
    end
    if not continent and zone then
        local mapID = ns.Spots.ZONE_MAPS[zone]
        local coords = type(target.coords) == "table" and target.coords
        local x = coords and tonumber(coords[1]) and coords[1] / 100 or 0.5
        local y = coords and tonumber(coords[2]) and coords[2] / 100 or 0.5
        if mapID then continent, north, west = ns.Arrow.WorldPos(mapID, x, y) end
    end
    if not continent then return nil end
    return { continent = continent, north = north, west = west, zone = zone, name = target.name }
end

--- Whether a place is worth a trip: on the other continent, or a walk that
--- passes through another zone first.
function Travel.WorthATrip(here, place)
    if not (here and place and here.continent) then return false end
    if place.continent ~= here.continent then return true end
    local path = Travel.ZonePath(ns.Spots.ZoneOf(here.zone), place.zone)
    return path ~= nil and #path >= 3
end

function Travel:Forget()
    self.plan = nil
end

--- Stop on the card: no trip for this place; the arrow points straight
--- again until it is aimed somewhere else.
function Travel:StopTrip()
    local planner = Travel.Planner()
    if planner ~= self then return planner:StopTrip() end
    self.stopped = self.plan and self.plan.key or self.lastKey
    self.plan = nil
    if ns.Arrow and ns.Arrow.Changed then ns.Arrow:Changed() end
end

--- Works out the plan for `target` from `here` when it is due. Keeps the
--- steps already behind you counted.
function Travel:Plan(target, here, clock)
    local place = self:WorldOf(target)
    if not place then self.plan = nil return nil end
    local key = ns.Arrow.Key(target)

    local plan = self.plan
    if plan and plan.key ~= key then plan = nil end
    if plan and plan.frozen then return plan end
    if plan and not self.due and clock - (plan.at or 0) < Travel.REPLAN and clock >= (plan.at or 0) then
        return plan
    end
    self.due = false

    if not Travel.WorthATrip(here, place) then
        self.plan = nil
        return nil
    end

    local legs, cost = self:Search(here, place, Travel.Side(), self:KnownFlights() or {}, self:Hearth())
    local steps = Travel.Steps(legs)
    if not legs or #steps == 0 then
        self.plan = nil
        return nil
    end
    local done, behind = 0, {}
    if plan then
        done = math.max(0, (plan.done or 0) + (#plan.steps - #steps))
        for _, step in ipairs(plan.behind or {}) do behind[#behind + 1] = step end
        -- The steps that dropped off the front are behind you now.
        for index = 1, math.min(done - (plan.done or 0), #plan.steps) do
            behind[#behind + 1] = plan.steps[index]
        end
        while #behind > done do table.remove(behind, 1) end
    end
    local previous = plan and plan.steps[1]
    self.plan = { key = key, place = place, steps = steps, cost = cost, done = done, behind = behind, at = clock }
    if previous and done > (plan.done or 0) and self.OnNext then self:OnNext(steps[1]) end
    return self.plan
end

--------------------------------------------------------------------------------
-- What the arrow shows for a step
--------------------------------------------------------------------------------

--- Where the arrow aims for walking toward `goal` from `here`: the goal, or
--- the way into the next zone when the walk passes through others first.
--- Returns continent, north, west and the zone it heads toward (or nil).
function Travel:Toward(here, goal)
    if here.continent ~= goal.continent then return nil end
    local path = Travel.ZonePath(ns.Spots.ZoneOf(here.zone), goal.zone)
    if not path or #path < 3 then return goal.continent, goal.north, goal.west, nil end

    local nextZone = path[2]
    local continent, north, west = self:Crossing(path[1], nextZone)
    if continent == here.continent then return continent, north, west, nextZone end

    -- The nearest edge of the next zone's map.
    local mapID = ns.Spots.ZONE_MAPS[nextZone]
    if mapID then
        local c1, n1, w1 = ns.Arrow.WorldPos(mapID, 0, 0)
        local c2, n2, w2 = ns.Arrow.WorldPos(mapID, 1, 1)
        if c1 == here.continent and c2 == here.continent then
            local north = math.max(math.min(n1, n2), math.min(math.max(n1, n2), here.north))
            local west = math.max(math.min(w1, w2), math.min(math.max(w1, w2), here.west))
            return c1, north, west, nextZone
        end
    end
    return goal.continent, goal.north, goal.west, nil
end

--- The step's words: the line ("Take the boat to Theramore") and the small
--- line under it, without the distance.
function Travel.StepWords(step, atStop, onTaxi)
    local to = step.to and Travel.ShortName(step.to.name) or "?"
    if step.kind == "fly" then
        if onTaxi then return L.Format("Fly to %s", to), "" end
        return L.Format("Fly to %s", to), L["Talk to the flight master"]
    elseif step.kind == "boat" then
        if atStop then return L.Format("Wait here for the boat to %s", to), L["Get on when it stops"] end
        return L.Format("Take the boat to %s", to), ""
    elseif step.kind == "zeppelin" then
        if atStop then return L.Format("Wait here for the zeppelin to %s", to), L["Get on when it stops"] end
        return L.Format("Take the zeppelin to %s", to), ""
    elseif step.kind == "hearth" then
        return L["Use your Hearthstone"], L.Format("It takes you to %s", to)
    end
    return L.Format("Walk to %s", to), ""
end

--- Everything the arrow needs while a trip is on: { index, count, line,
--- small, continent, north, west, toward, step, plan }, or nil when the
--- arrow should point as it always has.
function Travel:Use(target, here, clock)
    if not Travel.IsOn() or not (here and here.continent) then return nil end
    local planner = Travel.Planner()
    if planner ~= self then return planner:Use(target, here, clock) end

    local key = ns.Arrow.Key(target)
    self.lastKey = key
    if self.stopped then
        if self.stopped == key then return nil end
        self.stopped = nil
    end

    local onTaxi = type(UnitOnTaxi) == "function" and Read(UnitOnTaxi, "player") == true
    if self.plan then self.plan.frozen = onTaxi or nil end
    local inFight = type(InCombatLockdown) == "function" and Read(InCombatLockdown) == true
    local plan = (inFight and self.plan and self.plan.key == key) and self.plan
        or self:Plan(target, here, clock or Clock())
    if not plan then return nil end

    local step = plan.steps[1]
    local trip = { index = plan.done + 1, count = plan.done + #plan.steps, step = step, plan = plan, onTaxi = onTaxi }

    local aim = step.kind == "walk" and step.to or step.from
    if step.kind == "hearth" then aim = nil end
    local atStop = false
    if aim then
        local continent, north, west, toward = self:Toward(here, aim)
        trip.continent, trip.north, trip.west, trip.toward = continent, north, west, toward
        if continent == here.continent and not toward then
            atStop = Distance(here, aim) <= Travel.AT_STOP
        end
    end
    trip.line, trip.small = Travel.StepWords(step, atStop and step.kind ~= "walk", onTaxi)
    if trip.toward then
        local toward = L.Format("toward %s", ns.Spots.Show(trip.toward))
        trip.small = trip.small ~= "" and (trip.small .. ", " .. toward) or toward
    end
    trip.atStop = atStop
    return trip
end

--- Minutes the rest of the trip takes, about.
function Travel.Minutes(plan)
    return math.max(1, math.floor(((plan and plan.cost) or 0) / 60 + 0.5))
end

--- "Next: Take the boat to Theramore." once a step is behind you.
function Travel:OnNext(step)
    if not step then return end
    local line = Travel.StepWords(step, false, false)
    ns.Print(L.Format("Next: %s.", line))
end

--------------------------------------------------------------------------------
-- Watching for what changes a plan
--------------------------------------------------------------------------------

function Travel:Due()
    self.due = true
    if ns.ArrowUI and ns.ArrowUI.Refresh then ns.ArrowUI:Refresh() end
end

function Travel:OnZoneChanged()
    local here = ns.Arrow and ns.Arrow:Here()
    local zone = here and ns.Spots.ZoneOf(here.zone)
    local onTaxi = type(UnitOnTaxi) == "function" and Read(UnitOnTaxi, "player") == true
    local inside = ns.Tracker and ns.Tracker.InInstance and ns.Tracker.InInstance()
    if zone and self.lastZone and zone ~= self.lastZone and not onTaxi and not inside and not self.hearthing then
        self:NoteCrossing(self.lastZone, zone, here)
    end
    if zone then self.lastZone = zone end

    if self.hearthing and here and here.continent and Clock() - self.hearthing.at < 60 then
        local saved = Store("travelHearth")
        saved[self.hearthing.bind] = { here.continent, math.floor(here.north + 0.5), math.floor(here.west + 0.5), zone }
    end
    self.hearthing = nil
    self:Due()
end

function Travel:OnEnable()
    ns.RegisterEvent(self, "TAXIMAP_OPENED", function() Travel:ReadFlightMap() end)
    ns.RegisterEvent(self, "ZONE_CHANGED_NEW_AREA", function()
        if C_Timer and C_Timer.After then
            C_Timer.After(1, function() Travel:OnZoneChanged() end)
        else
            Travel:OnZoneChanged()
        end
    end)
    ns.RegisterEvent(self, "PLAYER_CONTROL_GAINED", function() Travel:Due() end)
    ns.RegisterEvent(self, "PLAYER_ENTERING_WORLD", function()
        if C_Timer and C_Timer.After then
            C_Timer.After(2, function() Travel:OnZoneChanged() end)
        end
    end)
    local register = ns.RegisterPlayerEvent or ns.RegisterEvent
    register(self, "UNIT_SPELLCAST_SUCCEEDED", function(_, _, unit, _, spellID)
        if unit ~= "player" or Number(spellID) ~= Travel.HEARTH_SPELL then return end
        local bind = type(GetBindLocation) == "function" and Readable(Read(GetBindLocation))
        if bind then Travel.hearthing = { bind = bind, at = Clock() } end
    end)
end
