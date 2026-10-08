-- Blackthornes Farmer -- Logic/Arrow.lua
-- The goal arrow: which way to walk to the nearest place to gather a goal
-- (2026-10-08: "point someone to the nearest place to gather something they
-- have set as a goal").
--
-- Where it points, best first:
--
--   * A spot you gathered the item at yourself (the map markers' spots,
--     Logic/Gathering.lua), nearest first. Exact to a few yards. One you
--     picked in the last few minutes goes to the back: it has not grown
--     back yet.
--   * A place the data has a spot for (a mob's coordinates from Forever
--     loot), nearest first.
--   * A zone the data names with no spot in it: the arrow points at the
--     middle of that zone, and says so. In that zone already, there is
--     nothing to point at, so it says the item is about this zone.
--   * Anywhere on the other continent: no arrow, only the place and "take
--     the boat or zeppelin".
--
-- The places come from the goal's Where? ranking (Logic/Spots.lua), so the
-- arrow and the panel never disagree about what is worth farming.
--
-- Direction and distance are worked out from the game's world coordinates
-- (C_Map.GetWorldPosFromMapPos), which run across every zone of a continent
-- in yards, so a spot two zones away gets a straight line. A client without
-- them still gets an arrow to spots on the map you are on, measured with the
-- map's size. Everything the client is asked is read-only and inside a
-- pcall; inside a dungeon, where the game keeps your position to itself, the
-- arrow is hidden.

local _, ns = ...

local Arrow = ns.NewModule("Arrow")

local Util = ns.Util

-- How close counts as there, in yards. A node is a point; a mob's spot is the
-- middle of where it walks.
local ARRIVED_NODE = 12
local ARRIVED_MOB = 35

-- What counts as a node rather than something that walks about.
local NODE_KINDS = { node = true, herb = true, ore = true }

-- A spot you gathered this long ago or less (seconds) has not grown back.
local RESTING = 3 * 60

-- At most this many places to step through with a right-click.
local MAX_TARGETS = 10

-- How often the list of places is worked out again while you move, seconds.
-- Pointing and distance are redone every frame the dial draws.
Arrow.REFRESH = 2

Arrow.ARRIVED_NODE = ARRIVED_NODE
Arrow.ARRIVED_MOB = ARRIVED_MOB
Arrow.RESTING = RESTING

-- Map types, as the client numbers them (Enum.UIMapType).
local CONTINENT = 2
local ZONE = 3

local Readable = function(value) return ns.Harvest.Readable(value) end
local Number = function(value) return ns.Harvest.ReadableNumber(value) end

local function Read(fn, ...)
    if type(fn) ~= "function" then return nil end
    local result = { pcall(fn, ...) }
    if not result[1] then return nil end
    return unpack(result, 2)
end

local function Map() return type(_G.C_Map) == "table" and _G.C_Map or nil end

--------------------------------------------------------------------------------
-- Switches and saved state
--------------------------------------------------------------------------------

function Arrow.IsOn()
    return ns.db ~= nil and ns.db.arrowShown == true
end

function Arrow:SetOn(on)
    ns.db.arrowShown = on and true or false
    self:Changed(true)
end

--- Which goal each character's arrow follows, by item name.
function Arrow:FollowStore()
    if type(ns.db.arrowFollow) ~= "table" then ns.db.arrowFollow = {} end
    return ns.db.arrowFollow
end

--- The goals the arrow can follow: this character's, not yet finished.
function Arrow:OpenGoals()
    local open = {}
    for _, goal in ipairs(ns.Goals:List()) do
        if type(goal.item) == "string" and not goal.done then open[#open + 1] = goal end
    end
    return open
end

--- The goal the arrow follows: the one picked, while it is still open, else
--- the first open one. Nil with none.
function Arrow:Goal()
    local open = self:OpenGoals()
    local owner = ns.Goals:Owner() or "?"
    local wanted = self:FollowStore()[owner]

    if type(wanted) == "string" then
        for _, goal in ipairs(open) do
            if goal.item:lower() == wanted:lower() then return goal end
        end
    end

    return open[1]
end

--- Follow the goal for `item`. False when there is no open goal for it.
function Arrow:Follow(item)
    local goal = type(item) == "string" and ns.Goals:Find(item)
    if not goal or goal.done then return false end

    self:FollowStore()[ns.Goals:Owner() or "?"] = goal.item
    self.pinned = nil
    self.choice = nil
    self.index = 1
    self:Changed(true)
    return true
end

--- Point at one place from the Where? panel: the goal for `item`, with
--- `spot` first in the list.
function Arrow:Aim(item, spot)
    if not self:Follow(item) then return false end
    if type(spot) == "table" then
        self.pinned = { name = spot.name, zone = spot.zone }
    end
    if not Arrow.IsOn() then
        self:SetOn(true)
        ns.Print("goal arrow on. /farm arrow off, or the settings page, hides it.")
    end
    self:Changed(true)
    return true
end

--- The next open goal along.
function Arrow:NextGoal()
    local open = self:OpenGoals()
    if #open == 0 then return nil end

    local current = self:Goal()
    local at = 1
    for index, goal in ipairs(open) do
        if goal == current then at = index end
    end

    local nextGoal = open[at % #open + 1]
    self:Follow(nextGoal.item)
    return nextGoal
end

--- The next place for the same goal.
function Arrow:NextSpot()
    local count = #(self.targets or {})
    if count == 0 then return nil end
    self.pinned = nil
    self.index = (self.index or 1) % count + 1
    local target = self.targets[self.index]
    self.choice = Arrow.Key(target)
    return target
end

--- What tells one place from another across a fresh list.
function Arrow.Key(target)
    return ("%s|%s|%s|%s|%s"):format(target.name or "?", target.zone or "?",
        tostring(target.map), tostring(target.x), tostring(target.y))
end

--- Something the arrow shows changed: work it out again on the next draw.
function Arrow:Changed(reset)
    self.listedAt = nil
    if reset then self.stamp, self.choice = nil, nil end
    if ns.ArrowUI and ns.ArrowUI.Refresh then ns.ArrowUI:Refresh() end
end

--------------------------------------------------------------------------------
-- Where you are
--------------------------------------------------------------------------------

local function MapInfo(mapID)
    local map = Map()
    if not (map and mapID) then return nil end
    local info = Read(map.GetMapInfo, mapID)
    if type(info) ~= "table" then return nil end

    local ok, name, kind, parent = pcall(function()
        return info.name, info.mapType, info.parentMapID
    end)
    if not ok then return nil end
    return { name = Readable(name), mapType = Number(kind), parent = Number(parent) }
end

Arrow.MapInfo = MapInfo

--- A point on a map as world coordinates: continent, north, west (yards).
--- Nil when the client will not say.
function Arrow.WorldPos(mapID, x, y)
    local map = Map()
    if not (map and mapID and x and y) then return nil end
    if type(map.GetWorldPosFromMapPos) ~= "function" or type(CreateVector2D) ~= "function" then
        return nil
    end

    local ok, continent, position = pcall(map.GetWorldPosFromMapPos, mapID, CreateVector2D(x, y))
    if not ok or type(position) ~= "table" then return nil end

    local read, north, west = pcall(position.GetXY, position)
    if not read then return nil end

    continent, north, west = Number(continent), Number(north), Number(west)
    if not (continent and north and west) then return nil end
    return continent, north, west
end

--- Which way you face, radians anticlockwise from north. Nil if not read.
function Arrow.Facing()
    if type(GetPlayerFacing) ~= "function" then return nil end
    local ok, facing = pcall(GetPlayerFacing)
    return ok and Number(facing) or nil
end

--- Where you stand: { map, x, y, continent, north, west, zone }, or nil
--- when the client will not say (inside an instance, usually).
function Arrow:Here()
    local mapID, x, y = ns.Harvest:PlayerMapPosition()
    if not mapID then return nil end

    local here = { map = mapID, x = x, y = y }
    here.continent, here.north, here.west = Arrow.WorldPos(mapID, x, y)
    here.zone = ns.Spots:Player().zone
    return here
end

--------------------------------------------------------------------------------
-- Zones as maps
--------------------------------------------------------------------------------

Arrow.zoneMaps = {}

--- The continent map the map `mapID` sits on, or nil.
function Arrow.ContinentOf(mapID)
    for _ = 1, 8 do
        local info = MapInfo(mapID)
        if not info then return nil end
        if info.mapType == CONTINENT then return mapID end
        if not info.parent or info.parent <= 0 then return nil end
        mapID = info.parent
    end
    return nil
end

--- The map ID of the zone named `zone`, looked up on the continent you are
--- on: the client's own map list, never a table typed here, so a map
--- Forever numbers differently still works. Nil when it is not on this
--- continent or the client cannot list maps.
function Arrow:ZoneMap(zone, here)
    if type(zone) ~= "string" or not (here and here.map) then return nil end

    -- The map you are on, when it is that zone.
    local info = MapInfo(here.map)
    if info and info.name == zone then return here.map end

    local continent = Arrow.ContinentOf(here.map)
    if not continent then return nil end

    local key = continent .. "|" .. zone
    local kept = self.zoneMaps[key]
    if kept ~= nil then return kept or nil end

    local found = false
    local map = Map()
    local children = map and Read(map.GetMapChildrenInfo, continent, nil, true)
    if type(children) == "table" then
        for _, child in ipairs(children) do
            local ok, name, kind, id = pcall(function()
                return child.name, child.mapType, child.mapID
            end)
            if ok and Readable(name) == zone then
                id, kind = Number(id), Number(kind)
                -- A zone beats a cave or a district that shares its name.
                if id and (kind == ZONE or not found) then found = id end
                if kind == ZONE then break end
            end
        end
    end

    self.zoneMaps[key] = found
    return found or nil
end

--------------------------------------------------------------------------------
-- Measuring
--------------------------------------------------------------------------------

--- Yards north and west from `here` to a point `x`, `y` on map `mapID`, or
--- nil when the two cannot be put on one grid.
function Arrow.Offset(here, mapID, x, y)
    if not (here and mapID and x and y) then return nil end

    if here.continent then
        local continent, north, west = Arrow.WorldPos(mapID, x, y)
        if continent and continent == here.continent then
            return north - here.north, west - here.west
        end
        if continent then return nil end
    end

    -- No world coordinates: only the map you are on can be measured.
    if mapID ~= here.map then return nil end
    local width, height = ns.Gathering.MapSize(mapID)
    if not (width and height) then return nil end

    -- Map x runs east, map y runs south.
    return (here.y - y) * height, (here.x - x) * width
end

--- How far, in yards, and which way: radians anticlockwise from north.
function Arrow.Measure(north, west)
    return math.sqrt(north * north + west * west), math.atan2(west, north)
end

--- Which way the arrow turns on screen: the bearing less your facing,
--- anticlockwise, as a texture's rotation reads it. North up without a
--- facing.
function Arrow.Turn(bearing, facing)
    local turn = bearing - (facing or 0)
    -- Kept between -pi and pi.
    while turn > math.pi do turn = turn - 2 * math.pi end
    while turn < -math.pi do turn = turn + 2 * math.pi end
    return turn
end

local COMPASS = { "north", "northwest", "west", "southwest", "south", "southeast", "east", "northeast" }

--- A bearing as a word: "northwest".
function Arrow.Compass(bearing)
    local step = math.floor((bearing / (math.pi / 4)) + 0.5) % 8
    return COMPASS[step + 1]
end

--------------------------------------------------------------------------------
-- The places
--------------------------------------------------------------------------------

--- Node names you have gathered `item` from.
local function NodesFor(item)
    local names = {}
    local ok, nodes = pcall(ns.Gathering.Store, ns.Gathering)
    for _, node in pairs(ok and nodes or {}) do
        local got = type(node) == "table" and type(node.items) == "table" and node.items[item]
        if got and (tonumber(got.gathers) or 0) > 0 and type(node.node) == "string" then
            names[node.node] = true
        end
    end
    return names
end

--- Every place to point at for `item`, from `here`, best first.
--
-- Each is { name, zone, map, x, y, kind, yours, exact, area, here, far,
-- yards, bearing, resting, ... }.
function Arrow:Targets(item, here)
    local now = ns.Gathering.Clock() or 0
    local exact, areas, far = {}, {}, {}

    -- Your own spots.
    local nodes = NodesFor(item)
    if next(nodes) then
        for _, spot in ipairs(ns.Gathering:Spots()) do
            local x, y = tonumber(spot.x), tonumber(spot.y)
            if type(spot) == "table" and nodes[spot.node] and x and y and spot.map then
                local target = {
                    name = spot.node, kind = spot.kind or "node", map = spot.map, x = x, y = y,
                    yours = true, exact = true, gathers = tonumber(spot.gathers) or 1,
                    last = tonumber(spot.last),
                }
                local last = target.last
                target.resting = last and now - last < RESTING and now - last >= 0 or nil
                local north, west = Arrow.Offset(here, spot.map, x, y)
                if north then
                    target.yards, target.bearing = Arrow.Measure(north, west)
                    exact[#exact + 1] = target
                end
            end
        end
    end

    -- The places the Where? ranking gives.
    local player = ns.Spots:Player()
    if here and here.zone then player.zone = here.zone end
    local ok, ranked = pcall(ns.Spots.For, ns.Spots, item, player)

    for rank, spot in ipairs(ok and ranked or {}) do
        local zone = ns.Spots.ZoneOf(spot.zone)
        local target = {
            name = spot.name, zone = spot.zone, location = spot.location, kind = spot.kind,
            chance = spot.chance, measured = spot.measured, yours = spot.yours and true or nil,
            minLevel = spot.minLevel, maxLevel = spot.maxLevel, hops = spot.hops,
            travel = spot.travel, rank = rank, forever = spot.forever,
        }

        local mapID = zone and self:ZoneMap(zone, here)
        -- Coordinates in a dungeon or capital are on a map of its own, so
        -- only a spot out in its zone is a point.
        local coords = type(spot.coords) == "table" and spot.zone == zone
            and tonumber(spot.coords[1]) and tonumber(spot.coords[2])

        if mapID and coords then
            target.map, target.x, target.y = mapID, spot.coords[1] / 100, spot.coords[2] / 100
            local north, west = Arrow.Offset(here, mapID, target.x, target.y)
            if north then
                target.exact = true
                target.yards, target.bearing = Arrow.Measure(north, west)
                exact[#exact + 1] = target
            else
                target.far = true
                far[#far + 1] = target
            end
        elseif mapID and here and zone == ns.Spots.ZoneOf(here.zone) then
            -- About the zone you are in: nothing to point at.
            target.map, target.here = mapID, true
            areas[#areas + 1] = target
        elseif mapID then
            -- Somewhere in a zone on this continent: its middle.
            target.map, target.x, target.y, target.area = mapID, 0.5, 0.5, true
            local north, west = Arrow.Offset(here, mapID, 0.5, 0.5)
            if north then target.yards, target.bearing = Arrow.Measure(north, west) end
            areas[#areas + 1] = target
        else
            target.far = true
            far[#far + 1] = target
        end
    end

    -- Nearest first, with a spot that has not grown back after the rest.
    table.sort(exact, function(a, b)
        if (a.resting and true or false) ~= (b.resting and true or false) then return not a.resting end
        return a.yards < b.yards
    end)

    local list = {}
    local function Add(group)
        for _, target in ipairs(group) do
            if #list < MAX_TARGETS then list[#list + 1] = target end
        end
    end
    Add(exact)
    Add(areas)
    Add(far)

    -- A place picked from the Where? panel goes first.
    if self.pinned then
        for index, target in ipairs(list) do
            if target.name == self.pinned.name and target.zone == self.pinned.zone then
                table.remove(list, index)
                table.insert(list, 1, target)
                break
            end
        end
    end

    return list
end

--------------------------------------------------------------------------------
-- What the dial shows
--------------------------------------------------------------------------------

--- Rounded yards: "8 yd", "140 yd", "1,250 yd".
function Arrow.Yards(yards)
    local whole = math.floor(yards + 0.5)
    if whole >= 1000 then
        return ("%d,%03d yd"):format(math.floor(whole / 1000), whole % 1000)
    end
    if whole >= 100 then whole = math.floor(whole / 10 + 0.5) * 10 end
    return ("%d yd"):format(whole)
end

--- "2 min ago", "40s ago".
local function Ago(seconds)
    if seconds < 60 then return ("%ds ago"):format(math.max(0, math.floor(seconds))) end
    return ("%d min ago"):format(math.floor(seconds / 60))
end

--- The note under a place: why it is there, in the dial's words.
function Arrow.Note(target, now)
    if target.yours and target.gathers then
        if target.resting and target.last and now then
            return ("picked %s, may not be back yet"):format(Ago(now - target.last)), "muted"
        end
        return target.gathers == 1 and "your own spot" or
            ("your own spot, gathered %d times"):format(target.gathers), "good"
    end
    if target.far then
        return target.travel == "by boat" and "take the boat"
            or "other continent: take the boat or zeppelin", "muted"
    end
    if target.here then return "about this zone, no one spot", "accent" end
    if target.area then return "somewhere in " .. (target.zone or "this zone"), "accent" end

    local rate = target.measured or target.chance
    if rate and ns.Tracker and ns.Tracker.FormatChance then
        return ("%s drop"):format(ns.Tracker.FormatChance(rate)), target.forever and "good" or "muted"
    end
    return "", "muted"
end

--- Where a place is, in a line: "Copper Vein", "Defias Looter, Westfall".
function Arrow.Place(target, here)
    local name = target.name or "?"
    if target.zone and not (here and target.zone == here.zone) then
        return name .. ", " .. target.zone
    end
    if target.location then return name .. ", " .. target.location end
    return name
end

--- Everything the dial needs for this moment:
---   { mode, goal, target, index, count, turn, yards, distance, place, note,
---     noteColor }
--- `mode` is "off", "inside", "none" (no goal), "blind" (no position),
--- "nowhere" (no places known), "point", "arrived", "here" or "far".
function Arrow:State(clock)
    if not Arrow.IsOn() then return { mode = "off" } end
    if ns.Tracker and ns.Tracker.InInstance and ns.Tracker.InInstance() then
        return { mode = "inside" }
    end

    local goal = self:Goal()
    if not goal then return { mode = "none" } end

    local here = self:Here()
    local state = { goal = goal }

    -- The list of places is worked out again now and then as you move, or
    -- at once for a new goal. A place picked with a right-click stays
    -- picked while it is still listed; otherwise the nearest is shown.
    clock = clock or 0
    if self.stamp ~= goal.item or not self.listedAt or clock - self.listedAt >= Arrow.REFRESH
        or clock < self.listedAt then
        if self.stamp ~= goal.item then self.choice = nil end
        self.targets = self:Targets(goal.item, here)
        self.listedAt = clock
        self.stamp = goal.item

        self.index = 1
        if self.choice then
            local found = false
            for index, target in ipairs(self.targets) do
                if Arrow.Key(target) == self.choice then
                    self.index, found = index, true
                    break
                end
            end
            if not found then self.choice = nil end
        end
    end

    if not here then
        state.mode = "blind"
        return state
    end

    local targets = self.targets or {}
    state.count = #targets
    if #targets == 0 then
        state.mode = "nowhere"
        return state
    end

    if (self.index or 1) > #targets then self.index = 1 end
    state.index = self.index or 1
    local target = targets[state.index]
    state.target = target
    state.place = Arrow.Place(target, here)
    state.note, state.noteColor = Arrow.Note(target, ns.Gathering.Clock())

    if target.far then
        state.mode = "far"
        state.distance = target.zone or "far away"
        return state
    end

    if target.here then
        state.mode = "here"
        state.distance = "In " .. (target.zone or "this zone")
        return state
    end

    -- Measured again for this frame.
    local north, west = Arrow.Offset(here, target.map, target.x, target.y)
    if not north then
        state.mode = "far"
        state.distance = target.zone or "far away"
        return state
    end

    local yards, bearing = Arrow.Measure(north, west)
    state.yards = yards
    state.bearing = bearing
    state.turn = Arrow.Turn(bearing, Arrow.Facing())
    state.facing = Arrow.Facing() ~= nil

    local reach = NODE_KINDS[target.kind or ""] and ARRIVED_NODE or ARRIVED_MOB
    if not target.area and yards <= reach then
        state.mode = "arrived"
        state.distance = "You're there"
        return state
    end

    state.mode = "point"
    if target.area then
        state.distance = ("%s, %s"):format(target.zone or "?", Arrow.Yards(yards))
    else
        state.distance = Arrow.Yards(yards)
    end
    return state
end

--------------------------------------------------------------------------------
-- Checking what the client allows
--------------------------------------------------------------------------------

local function YesNo(ok) return ok and Util.Colored("good", "yes") or Util.Colored("warn", "no") end

--- /farm arrow check: what the arrow can read here, line by line.
function Arrow:Check()
    ns.Print("goal arrow check:")

    local mapID, x, y = ns.Harvest:PlayerMapPosition()
    ns.PrintRaw(("  map position: %s%s"):format(YesNo(mapID),
        mapID and (" (map %d, %.1f, %.1f)"):format(mapID, x * 100, y * 100) or ""))

    local facing = Arrow.Facing()
    ns.PrintRaw(("  facing: %s%s"):format(YesNo(facing),
        facing and (" (%.2f, %s)"):format(facing, Arrow.Compass(facing)) or ""))

    local continent, north, west = Arrow.WorldPos(mapID, x, y)
    ns.PrintRaw(("  world position: %s%s"):format(YesNo(continent),
        continent and (" (continent %d, %.0f, %.0f)"):format(continent, north, west)
        or ", so it only points within the map you are on"))

    local width, height
    if mapID then width, height = ns.Gathering.MapSize(mapID) end
    ns.PrintRaw(("  map size: %s%s"):format(YesNo(width),
        width and (" (%.0f by %.0f yards)"):format(width, height) or ""))

    local continentMap = mapID and Arrow.ContinentOf(mapID)
    ns.PrintRaw(("  continent map: %s%s"):format(YesNo(continentMap),
        continentMap and (" (map %d)"):format(continentMap) or ", so zones elsewhere cannot be found"))

    local inside = ns.Tracker and ns.Tracker.InInstance and ns.Tracker.InInstance()
    ns.PrintRaw(("  in an instance: %s"):format(inside and "yes, so the arrow hides" or "no"))

    local state = self:State(GetTime and GetTime() or 0)
    if state.goal then
        local target = state.target
        ns.PrintRaw(("  following: %s%s"):format(Util.Colored("accent", state.goal.item),
            target and (", %s, %s"):format(target.name or "?", state.distance or "") or ", nowhere known"))
    elseif state.mode == "none" then
        ns.PrintRaw("  following: no open goal. /farm goal Copper Ore 40 sets one.")
    end
end

--------------------------------------------------------------------------------
-- Commands
--------------------------------------------------------------------------------

local function Status()
    if Arrow.IsOn() then
        local goal = Arrow:Goal()
        if goal then
            ns.Print(("goal arrow on, following %s. Click it for the next goal, right-click for "
                .. "the next place."):format(Util.Colored("accent", goal.item)))
        else
            ns.Print("goal arrow on. It shows once you set a goal: /farm goal Copper Ore 40.")
        end
    else
        ns.Print("goal arrow off. /farm arrow on shows it.")
    end
end

ns.RegisterCommand("arrow", "an arrow to the nearest place to gather a goal (on, off, next, check, <goal>)", function(rest)
    local argument = Util.Trim(rest)
    local word = argument:lower()

    if word == "" then
        Arrow:SetOn(not Arrow.IsOn())
        Status()
    elseif word == "on" or word == "off" then
        Arrow:SetOn(word == "on")
        Status()
    elseif word == "next" then
        local target = Arrow:NextSpot()
        if target then
            ns.Print(("pointing at %s."):format(Util.Colored("accent", Arrow.Place(target))))
        else
            ns.Print("no other place known for that goal.")
        end
    elseif word == "check" then
        Arrow:Check()
    elseif word == "reset" then
        if ns.ArrowUI and ns.ArrowUI.ResetPosition then ns.ArrowUI:ResetPosition() end
        ns.Print("goal arrow put back where it started.")
    else
        local name = ns.Goals:ResolveItem(argument) or argument
        if Arrow:Follow(name) then
            if not Arrow.IsOn() then Arrow:SetOn(true) end
            ns.Print(("goal arrow following %s."):format(Util.Colored("accent", Arrow:Goal().item)))
        else
            ns.Print(("no open goal for %s. /farm goal %s 20 sets one."):format(argument, argument))
        end
    end
end)
