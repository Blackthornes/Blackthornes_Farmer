-- The goal arrow: which way to walk to the nearest place to gather a goal.
--
-- What matters: it is off until turned on, and the switch is shared by
-- /farm arrow and the settings page; it follows this character's open goals
-- and steps through them; your own gathered spots come first, nearest first,
-- with one just picked sent to the back; it turns the right way for where you
-- face; close enough is "You're there"; a zone with no spot points at its
-- middle, the zone you are in says so, and the other continent gets no
-- arrow; a client without world coordinates still points within the map you
-- are on; an unreadable facing or position breaks nothing; and inside a
-- dungeon it hides.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("arrow")

local clock, wall = 100, 1000000

local ns = env.Load({ ui = true })
local Arrow, ArrowUI = ns.Arrow, ns.ArrowUI

_G.GetTime = function() return clock end
_G.time = function() return wall end
_G.C_Item = { GetItemCount = function() return 12 end }
_G.IsInInstance = function() return false, "none" end

local facing = 0
_G.GetPlayerFacing = function() return facing end

-- Two zones of the Eastern Kingdoms side by side, and Durotar across the sea.
-- World coordinates: north runs up the map, west runs left.
local MAPS = {
    [37] = { name = "Elwynn Forest", mapType = 3, parentMapID = 13, continent = 0,
        top = 0, left = 0, width = 3000, height = 2000 },
    [52] = { name = "Westfall", mapType = 3, parentMapID = 13, continent = 0,
        top = -1500, left = 2600, width = 2500, height = 1700 },
    [13] = { name = "Eastern Kingdoms", mapType = 2, parentMapID = 947 },
    [1] = { name = "Durotar", mapType = 3, parentMapID = 12, continent = 1,
        top = 0, left = 0, width = 2000, height = 2000 },
    [12] = { name = "Kalimdor", mapType = 2, parentMapID = 947 },
    [947] = { name = "Azeroth", mapType = 1 },
}

_G.CreateVector2D = function(x, y) return { x = x, y = y } end

local function WorldPos(mapID, vector)
    local map = MAPS[mapID]
    if not (map and map.width) then return nil end
    local north = map.top - vector.y * map.height
    local west = map.left - vector.x * map.width
    return map.continent, { GetXY = function() return north, west end }
end

local C_Map = _G.C_Map
C_Map.GetMapInfo = function(mapID)
    local map = MAPS[mapID]
    if not map then return nil end
    return { name = map.name, mapType = map.mapType, parentMapID = map.parentMapID, mapID = mapID }
end
C_Map.GetMapChildrenInfo = function(mapID)
    local children = {}
    for id, map in pairs(MAPS) do
        if map.parentMapID == mapID then
            children[#children + 1] = { name = map.name, mapType = map.mapType, mapID = id }
        end
    end
    return children
end
C_Map.GetWorldPosFromMapPos = WorldPos
C_Map.GetMapWorldSize = function(mapID)
    local map = MAPS[mapID]
    if map and map.width then return map.width, map.height end
    return nil
end

env.world.zone = "Elwynn Forest"
env.world.subZone = ""
env.world.mapID = 37
env.world.position = { 0.45, 0.50 }

for _, module in ipairs(ns.moduleOrder) do
    if module.OnEnable then module:OnEnable() end
end

local function near(a, b) return a and b and math.abs(a - b) < 0.01 end

--------------------------------------------------------------------------------
-- Off until asked for
--------------------------------------------------------------------------------

suite.check("off by default", ns.db.arrowShown == false and Arrow:State(clock).mode == "off")

ns.HandleSlash("arrow")
suite.check("/farm arrow turns it on", Arrow.IsOn())
suite.check("with no goal it says so", Arrow:State(clock).mode == "none", Arrow:State(clock).mode)

--------------------------------------------------------------------------------
-- Goals: this character's open ones
--------------------------------------------------------------------------------

ns.db.goals = { list = {
    { item = "Copper Ore", target = 40, have = 12 },
    { item = "Linen Cloth", target = 60, have = 8 },
    { item = "Silk Cloth", target = 20, have = 20, done = true },
    { item = "Wool Cloth", target = 20, have = 0, owner = "Ana-Elsewhere" },
}, today = {} }

suite.check("follows the first open goal", Arrow:Goal().item == "Copper Ore")
suite.check("next goal steps on", Arrow:NextGoal().item == "Linen Cloth")
suite.check("and round, past the finished one and another character's",
    Arrow:NextGoal().item == "Copper Ore")
suite.check("a finished goal cannot be followed", not Arrow:Follow("Silk Cloth"))
suite.check("nor someone else's", not Arrow:Follow("Wool Cloth"))
suite.check("an open one can", Arrow:Follow("Linen Cloth") and Arrow:Goal().item == "Linen Cloth")
Arrow:Follow("Copper Ore")

--------------------------------------------------------------------------------
-- Your own spots, nearest first
--------------------------------------------------------------------------------

ns.db.gathering = {
    nodes = {
        ["Elwynn Forest||Copper Vein"] = { zone = "Elwynn Forest", location = "", node = "Copper Vein",
            kind = "ore", gathers = 4, items = { ["Copper Ore"] = { gathers = 4, count = 8 } } },
    },
    spots = {
        { map = 37, x = 0.80, y = 0.50, node = "Copper Vein", kind = "ore", gathers = 1, last = wall - 3600 },
        { map = 37, x = 0.50, y = 0.50, node = "Copper Vein", kind = "ore", gathers = 3, last = wall - 3600 },
        { map = 37, x = 0.20, y = 0.50, node = "Peacebloom", kind = "herb", gathers = 2, last = wall - 3600 },
    },
}
Arrow:Changed(true)

local state = Arrow:State(clock)
suite.check("points", state.mode == "point", state.mode)
suite.check("at the nearest of your spots", state.target and state.target.yours
    and near(state.target.x, 0.50), state.target and state.target.x)
suite.check("150 yards east", near(state.yards, 150), state.yards)
suite.check("a node that never gave copper is not a copper spot", (function()
    for _, target in ipairs(Arrow.targets) do
        if target.name == "Peacebloom" then return false end
    end
    return true
end)())
suite.check("the distance reads in yards", state.distance == "150 yd", state.distance)
suite.check("and says it is yours", state.note:find("your own spot", 1, true) ~= nil, state.note)

-- Facing north, east is a quarter turn clockwise; facing west it is behind.
suite.check("facing north, it turns right", near(state.turn, -math.pi / 2), state.turn)
facing = math.pi / 2
state = Arrow:State(clock)
suite.check("facing west, it points behind", near(math.abs(state.turn), math.pi), state.turn)
facing = 0

-- Picked a minute ago: not grown back, so the other one first.
ns.db.gathering.spots[2].last = wall - 60
clock = clock + Arrow.REFRESH
state = Arrow:State(clock)
suite.check("a spot just picked goes to the back", near(state.target.x, 0.80), state.target.x)
local resting
for _, target in ipairs(Arrow.targets) do
    if target.resting then resting = target end
end
suite.check("and says why", resting and Arrow.Note(resting, wall):find("might not have grown back", 1, true) ~= nil)

-- The Where? ranking lists the vein too, at the spot you first took it:
-- that copy is your spot again, not a second place that never rests.
local vein = ns.db.gathering.nodes["Elwynn Forest||Copper Vein"]
vein.coords = { 50, 50 }
Arrow:Changed()
clock = clock + Arrow.REFRESH
state = Arrow:State(clock)
suite.check("your vein ranked again is not a second place", near(state.target.x, 0.80), state.target.x)
local copies = 0
for _, target in ipairs(Arrow.targets) do
    if target.exact and near(target.x, 0.50) and near(target.y, 0.50) then copies = copies + 1 end
end
suite.check("so it is listed once", copies == 1, copies)
vein.coords = nil
Arrow:Changed()
ns.db.gathering.spots[2].last = wall - 3600

-- Walking about only measures again: the places themselves are worked out
-- once until a gather, the loot recorded, or your zone changes them.
do
    local realFor, asked = ns.Spots.For, 0
    ns.Spots.For = function(...) asked = asked + 1 return realFor(...) end
    Arrow:Changed()
    for _ = 1, 3 do
        clock = clock + Arrow.REFRESH
        Arrow:State(clock)
    end
    suite.check("the ranking is not redone on every refresh", asked == 1, asked)
    ns.Gathering:SpotsChanged()
    clock = clock + Arrow.REFRESH
    Arrow:State(clock)
    suite.check("but is after a gather", asked == 2, asked)
    ns.Harvest.changes = (ns.Harvest.changes or 0) + 1
    clock = clock + Arrow.REFRESH
    Arrow:State(clock)
    suite.check("and after loot is recorded", asked == 3, asked)
    ns.Spots.For = realFor
end

-- Standing on it.
env.world.position = { 0.502, 0.50 }
clock = clock + Arrow.REFRESH
state = Arrow:State(clock)
suite.check("close enough is there", state.mode == "arrived" and state.distance == "You're there",
    state.mode .. " " .. tostring(state.yards))

-- Reached but not gathered (the node may not be up yet): on to the next,
-- and not back to it while it counts as checked.
clock = clock + Arrow.REFRESH
state = Arrow:State(clock)
suite.check("a spot reached sends the arrow on to the next", near(state.target.x, 0.80), state.target.x)
env.world.position = { 0.60, 0.50 }
clock = clock + Arrow.REFRESH
state = Arrow:State(clock)
suite.check("and it does not go back to it", near(state.target.x, 0.80), state.target.x)
wall = wall + Arrow.CHECKED + 1
clock = clock + Arrow.REFRESH
state = Arrow:State(clock)
suite.check("a while later it counts again", near(state.target.x, 0.50), state.target.x)

-- Picked the far one with a right-click and reached it: the pick is let go,
-- and the arrow follows the nearest spot not yet checked.
Arrow.checked = {}
env.world.position = { 0.45, 0.50 }
clock = clock + Arrow.REFRESH
Arrow:State(clock)
for index, target in ipairs(Arrow.targets) do
    if near(target.x, 0.80) then Arrow.index, Arrow.choice = index, Arrow.Key(target) end
end
env.world.position = { 0.798, 0.50 }
clock = clock + Arrow.REFRESH
Arrow:State(clock)
clock = clock + Arrow.REFRESH
state = Arrow:State(clock)
suite.check("reaching the spot picked lets the pick go", Arrow.choice == nil)
suite.check("and the arrow points on from there", near(state.target.x, 0.50) and state.index == 1,
    state.target.x)
Arrow.checked = {}
env.world.position = { 0.45, 0.50 }

--------------------------------------------------------------------------------
-- Stepping through places
--------------------------------------------------------------------------------

clock = clock + Arrow.REFRESH
state = Arrow:State(clock)
local second = Arrow:NextSpot()
suite.check("right-click steps to the next place", second and second ~= state.target)
clock = clock + Arrow.REFRESH
state = Arrow:State(clock)
suite.check("and stays there as the list is redone", state.index == 2, state.index)
Arrow:Follow("Copper Ore")
state = Arrow:State(clock)
suite.check("choosing the goal again starts at the nearest", state.index == 1, state.index)

--------------------------------------------------------------------------------
-- Zones without a spot, and the other continent
--------------------------------------------------------------------------------

local byZone = {}
for _, target in ipairs(Arrow.targets) do
    if not target.gathers then byZone[target.zone] = target end
end

local westfall = byZone["Westfall"]
suite.check("a zone next door points at its middle", westfall and westfall.area and westfall.yards ~= nil)
suite.check("and says so", westfall and Arrow.Note(westfall):find("somewhere in Westfall", 1, true) ~= nil)
suite.check("the zone you are in has nothing to point at",
    byZone["Elwynn Forest"] and byZone["Elwynn Forest"].here == true)
local durotar = byZone["Durotar"]
suite.check("the other continent gets no arrow", durotar and durotar.far == true)
suite.check("only the boat", durotar and Arrow.Note(durotar):find("boat or zeppelin", 1, true) ~= nil)
suite.check("own spots come before the zones", Arrow.targets[1].yours and Arrow.targets[2].yours)

-- Picked from the Where? panel: that place first.
Arrow:Aim("Copper Ore", { name = "Copper Vein", zone = "Westfall" })
state = Arrow:State(clock)
suite.check("a place picked in the Where? panel goes first",
    state.target.zone == "Westfall" and state.mode == "point", state.target.zone)
suite.check("with its zone in the distance", state.distance:find("^Westfall, ") ~= nil, state.distance)
Arrow:Follow("Copper Ore")

-- A saved farm's Zone and Mob: that mob first, even on another continent
-- or past the places the list keeps, and the rest kept to its zone.
Arrow:Aim("Copper Ore", { name = "Saved Farm Mob", zone = "Durotar" }, true)
state = Arrow:State(clock)
suite.check("a saved farm's mob goes first, though far down the list",
    Arrow.targets[1].name == "Saved Farm Mob" and Arrow.targets[1].zone == "Durotar", Arrow.targets[1].name)
suite.check("the arrow follows it", state.target == Arrow.targets[1])
local onlyDurotar = true
for _, target in ipairs(Arrow.targets) do
    if target.zone ~= "Durotar" and not Arrow:InZone(target, "Durotar", nil) then onlyDurotar = false end
end
suite.check("and the places after it stay in its zone", onlyDurotar and Arrow.pinnedZone == "Durotar")
Arrow:NextSpot()
Arrow:State(clock)
suite.check("moving on lets the mob go but keeps the zone", Arrow.pinned == nil and Arrow.pinnedZone == "Durotar")
Arrow:Follow("Copper Ore")
suite.check("a Where? pick keeps no zone", (function()
    Arrow:Aim("Copper Ore", { name = "Copper Vein", zone = "Westfall" })
    return Arrow.pinnedZone == nil
end)())
Arrow:Follow("Copper Ore")

-- A saved farm on Any Mob: only places in its zone, and moving on stays there.
Arrow:AimZone("Copper Ore", "Westfall")
state = Arrow:State(clock)
local onlyWestfall = #Arrow.targets > 0
for _, target in ipairs(Arrow.targets) do
    if not Arrow:InZone(target, "Westfall", nil) and target.zone ~= "Westfall" then onlyWestfall = false end
end
suite.check("a whole zone farm keeps to its zone", onlyWestfall and state.target.zone == "Westfall", state.target.zone)
Arrow:NextSpot()
state = Arrow:State(clock)
suite.check("and moving on stays there", state.target.zone == "Westfall", state.target.zone)
Arrow:AimZone("Copper Ore", "Nowhere Vale")
Arrow:State(clock)
suite.check("a zone with no place keeps every place", #Arrow.targets > 1)
Arrow:Follow("Copper Ore")
suite.check("following again lets the zone go", Arrow.pinnedZone == nil)

--------------------------------------------------------------------------------
-- What the client will not say
--------------------------------------------------------------------------------

_G.GetPlayerFacing = function() return env.Secret("facing") end
local ok, err = pcall(Arrow.State, Arrow, clock + 10)
suite.check("a secret facing breaks nothing", ok, err)
state = Arrow:State(clock + 10)
suite.check("and it points north-up instead", near(state.turn, state.bearing), state.turn)
_G.GetPlayerFacing = function() return facing end

-- No world coordinates: the map you are on still works, others do not.
C_Map.GetWorldPosFromMapPos = nil
Arrow:Changed(true)
state = Arrow:State(clock + 20)
suite.check("without world coordinates, your map still points", state.mode == "point"
    and near(state.yards, 150), state.mode .. " " .. tostring(state.yards))
suite.check("but another zone cannot be measured",
    Arrow.Offset(Arrow:Here(), 52, 0.5, 0.5) == nil)
C_Map.GetWorldPosFromMapPos = WorldPos

-- No position at all.
env.world.position = nil
Arrow:Changed(true)
state = Arrow:State(clock + 30)
suite.check("no position, it says it cannot see you", state.mode == "blind", state.mode)
env.world.position = { 0.45, 0.50 }

-- Inside a dungeon it hides.
_G.IsInInstance = function() return true, "party" end
suite.check("inside a dungeon it hides", Arrow:State(clock).mode == "inside")
_G.IsInInstance = function() return false, "none" end

--------------------------------------------------------------------------------
-- The dial
--------------------------------------------------------------------------------

ArrowUI:Refresh()
local frame = ArrowUI.frame
suite.check("the dial shows", frame and frame:IsShown())
suite.check("the goal on its plate", ArrowUI.title:GetText() == "Copper Ore  12 / 40", ArrowUI.title:GetText())
suite.check("and never the words Goal arrow", ArrowUI.title:GetText() ~= "Goal arrow")
suite.check("the distance under it", ArrowUI.distance:GetText() == "150 yd", ArrowUI.distance:GetText())

local rotation
ArrowUI.chevron.SetRotation = function(_, angle) rotation = angle end
ArrowUI.shownTurn, ArrowUI.shownFrame = nil, nil
ArrowUI:Draw(true)
suite.check("the arrow is turned", near(ArrowUI.shownTurn, -math.pi / 2), ArrowUI.shownTurn)
-- A quarter turn right is step 135 of 180, turned flat with SetRotation.
suite.check("the chevron is on the step for that turn", ArrowUI.shownFrame == 135, ArrowUI.shownFrame)
suite.check("turned flat to it", rotation and near(rotation, 1.5 * math.pi), rotation)
suite.check("steps wrap round both ways", ArrowUI.FrameFor(0) == 0 and ArrowUI.FrameFor(2 * math.pi) == 0
    and ArrowUI.FrameFor(-2 * math.pi / 180) == 179 and ArrowUI.FrameFor(math.pi) == 90)
rotation = nil
ArrowUI:Turn(ArrowUI.shownTurn)
suite.check("the same step touches nothing", rotation == nil)
suite.check("the chevron shows while it points", ArrowUI.chevron:IsShown() and not ArrowUI.check:IsShown()
    and not ArrowUI.dot:IsShown())

-- The slim pill: no plate, no old dial art, two lines only.
suite.check("no plate or ring left", ArrowUI.plate == nil and ArrowUI.ring == nil and ArrowUI.arrow == nil)
suite.check("no place or note lines", ArrowUI.place == nil and ArrowUI.note == nil)
suite.check("a slim pill", frame:GetHeight() <= 30 and frame:GetWidth() >= 140 and frame:GetWidth() <= 300,
    tostring(frame:GetWidth()) .. " x " .. tostring(frame:GetHeight()))
suite.check("the step box hangs under the pill", ArrowUI.dial == frame)
for _, path in ipairs({ "Pill", "PillEdge", "Well", "WellEdge", "Chevron", "ChevronGlow", "Dot", "Check" }) do
    local handle = io.open((rawget(_G, "lfs_cwd") or ".") .. "/Media/Arrow/" .. path .. ".tga", "rb")
    suite.check("art " .. path .. " is there", handle ~= nil)
    if handle then handle:close() end
end
for _, path in ipairs({ "Blade", "BladeGlow", "Ring" }) do
    local handle = io.open((rawget(_G, "lfs_cwd") or ".") .. "/Media/Arrow/" .. path .. ".tga", "rb")
    suite.check("old art " .. path .. " is gone", handle == nil)
    if handle then handle:close() end
end

suite.check("wide enough for its words",
    frame:GetWidth() >= ns.Theme.TextWidth("small", ArrowUI.title:GetText()))

-- The dial takes no clicks and shows no tooltip: it only moves and closes.
suite.check("no click on the dial", frame:GetScript("OnMouseUp") == nil and ArrowUI.OnClick == nil)
suite.check("no tooltip on the dial", frame:GetScript("OnEnter") == nil and ArrowUI.ShowTooltip == nil)
suite.check("it still drags", frame:GetScript("OnDragStart") ~= nil and frame:GetScript("OnDragStop") ~= nil)
Arrow:NextSpot()
suite.check("the next place is still there to step to", Arrow.index == 2, Arrow.index)
frame:GetScript("OnDragStart")(frame)
frame:GetScript("OnDragStop")(frame)
suite.check("a drag changes nothing it points at", Arrow.index == 2, Arrow.index)

-- No open goal left: it steps out of the way, still on for the next one.
local savedList = ns.db.goals.list
ns.db.goals.list = { { item = "Copper Ore", target = 40, have = 40, done = true } }
ArrowUI:Draw()
suite.check("with no open goal it hides", Arrow.IsOn() and not frame:IsShown())
ns.db.goals.list = savedList
ArrowUI:Draw()
suite.check("and comes back with one", frame:IsShown())

-- The red gem turns it off.
suite.check("it has a close gem", ArrowUI.close ~= nil)
local gemPoint = ArrowUI.close._point or {}
suite.check("at the pill's right end, inside it",
    gemPoint[1] == "RIGHT" and gemPoint[2] == frame and gemPoint[3] == "RIGHT", tostring(gemPoint[1]))
ArrowUI.close:GetScript("OnClick")(ArrowUI.close)
suite.check("the close gem turns it off", not Arrow.IsOn() and not frame:IsShown())
ns.HandleSlash("arrow on")

ns.HandleSlash("arrow off")
ArrowUI:Draw()
suite.check("off hides it", not Arrow.IsOn() and not frame:IsShown())

ns.HandleSlash("arrow linen cloth")
suite.check("/farm arrow <goal> follows it and turns it on",
    Arrow.IsOn() and Arrow:Goal().item == "Linen Cloth")

local okCheck, errCheck = pcall(ns.HandleSlash, "arrow check")
suite.check("/farm arrow check runs", okCheck, errCheck)

ns.db.arrowX, ns.db.arrowY = 300, 400
ns.HandleSlash("arrow reset")
suite.check("reset puts it back", ns.db.arrowX == nil and ns.db.arrowY == nil)

--------------------------------------------------------------------------------
-- TomTom: its arrow instead of the dial, when it is installed
--------------------------------------------------------------------------------

do
    local TomTom = ns.TomTom
    Arrow:Follow("Copper Ore")
    ArrowUI:Draw(true)
    suite.check("without TomTom the dial shows", frame:IsShown() and TomTom.uid == nil)
    suite.check("the switch is on unless unticked", TomTom.IsOn())

    -- A TomTom keeping its waypoints, as the real one's calls take them.
    local points, nextUid = {}, 0
    _G.TomTom = {
        AddWaypoint = function(self, map, x, y, opts)
            nextUid = nextUid + 1
            local uid = { map, x, y, title = opts and opts.title }
            points[uid] = opts
            return uid
        end,
        RemoveWaypoint = function(self, uid) points[uid] = nil end,
    }
    local function Count()
        local count = 0
        for _ in pairs(points) do count = count + 1 end
        return count
    end

    ArrowUI:Draw(true)
    suite.check("with TomTom the dial hides", not frame:IsShown())
    suite.check("and TomTom gets one waypoint", Count() == 1, Count())
    local uid = TomTom.uid
    suite.check("at the dial's place", uid and uid[1] == 37 and near(uid[2], 0.50) and near(uid[3], 0.50))
    suite.check("named for the goal", uid and uid.title == "Copper Ore: Copper Vein", uid and uid.title)
    suite.check("on TomTom's arrow, not saved in its list",
        points[uid].crazy == true and points[uid].persistent == false)
    suite.check("this arrow still holds the screen over the others", _G.BlackthornesArrows.wants.Farmer)
    suite.check("outside a route TomTom's minimap pin shows", points[uid].minimap == true)

    -- While a Gather Route runs, TomTom's pin stays off the minimap so the
    -- herb's blip under it shows; its arrow and world map pin stay.
    do
        local route = ns.GatherRoute
        local hadRun = route.run
        route.run = { map = 37, visited = {}, picked = {}, started = 0 }
        ArrowUI:Draw(true)
        local routeUid = TomTom.uid
        suite.check("on a route TomTom gets the place again", routeUid ~= nil and routeUid ~= uid and Count() == 1)
        suite.check("on a route TomTom's pin stays off the minimap", routeUid and points[routeUid].minimap == false
            and points[routeUid].world == true and points[routeUid].crazy == true)
        route.run = hadRun
        ArrowUI:Draw(true)
        uid = TomTom.uid
        suite.check("after the route the minimap pin comes back", uid and points[uid].minimap == true and Count() == 1)
    end

    ArrowUI:Draw(true)
    suite.check("drawn again, the same waypoint stays", TomTom.uid == uid and Count() == 1)

    -- TomTom clears a waypoint on arrival (or the player removes it): the
    -- dial comes back rather than leaving nothing pointing the way.
    _G.TomTom.IsValidWaypoint = function(self, id) return points[id] ~= nil end
    points[uid] = nil
    ArrowUI:Draw(true)
    suite.check("a waypoint TomTom dropped brings the dial back", frame:IsShown() and Count() == 0)
    ArrowUI:Draw(true)
    suite.check("and it is not put back on TomTom for the same place", frame:IsShown() and Count() == 0)
    _G.TomTom.IsValidWaypoint = nil
    -- The arrow turned off and on again means try TomTom again.
    Arrow:SetOn(false)
    Arrow:SetOn(true)
    ArrowUI:Draw(true)
    uid = TomTom.uid
    suite.check("a fresh waypoint once the arrow is turned off and on", not frame:IsShown() and Count() == 1)

    Arrow:NextSpot()
    ArrowUI:Draw(true)
    suite.check("the next place swaps it", TomTom.uid ~= uid and Count() == 1, Count())

    -- The other continent: TomTom cannot point, so the dial says so.
    Arrow:Aim("Copper Ore", { name = "Copper Vein", zone = "Durotar" })
    ArrowUI:Draw(true)
    suite.check("a place TomTom cannot point at goes back to the dial",
        ArrowUI.state.mode == "far" and frame:IsShown() and Count() == 0, ArrowUI.state.mode)
    Arrow:Follow("Copper Ore")
    ArrowUI:Draw(true)
    suite.check("and back to TomTom after", not frame:IsShown() and Count() == 1)

    -- The goal finished: the waypoint goes.
    local savedGoals = ns.db.goals.list
    ns.db.goals.list = { { item = "Copper Ore", target = 40, have = 40, done = true } }
    ArrowUI:Draw(true)
    suite.check("a finished goal takes its waypoint away", Count() == 0 and TomTom.uid == nil)
    ns.db.goals.list = savedGoals
    ArrowUI:Draw(true)

    -- Another Blackthornes arrow aimed later: TomTom's goes too.
    local shared = _G.BlackthornesArrows
    shared.wants.Pets, shared.claims.Pets = true, 1e12
    ArrowUI:Draw(true)
    suite.check("another addon's arrow aimed later takes it away", Count() == 0)
    shared.wants.Pets, shared.claims.Pets = nil, nil
    ArrowUI:Draw(true)
    suite.check("and it comes back once that one is put away", Count() == 1)

    -- Unticked: the dial, and no waypoint.
    ns.HandleSlash("arrow tomtom off")
    ArrowUI:Draw(true)
    suite.check("/farm arrow tomtom off: the dial again", ns.db.useTomTom == false
        and frame:IsShown() and Count() == 0)
    ns.HandleSlash("arrow tomtom on")
    ArrowUI:Draw(true)
    suite.check("and on: TomTom again", not frame:IsShown() and Count() == 1)

    ns.HandleSlash("arrow off")
    suite.check("the arrow off takes the waypoint away", Count() == 0)
    ns.HandleSlash("arrow on")
    ArrowUI:Draw(true)

    -- A TomTom that will not take it, or raises: the dial, and no error.
    _G.TomTom.AddWaypoint = function() error("different version") end
    TomTom:Clear()
    Arrow:NextSpot()
    local okDraw = pcall(ArrowUI.Draw, ArrowUI, true)
    suite.check("a TomTom that raises falls back to the dial", okDraw and frame:IsShown())
    _G.TomTom = { AddWaypoint = "no" }
    Arrow:NextSpot()
    ArrowUI:Draw(true)
    suite.check("so does one without the calls", frame:IsShown() and not TomTom.Installed())

    local okCheckTT, errTT = pcall(ns.HandleSlash, "arrow check")
    suite.check("/farm arrow check says what TomTom does", okCheckTT, errTT)
    _G.TomTom = nil
    TomTom.refused = nil
end

--------------------------------------------------------------------------------
-- One Blackthornes arrow at a time (the same lines are in all three addons)
--------------------------------------------------------------------------------

do
    _G.BlackthornesArrows = nil
    local ui = ArrowUI
    suite.check("alone, it always shows", ui.Wins(true))
    local shared = _G.BlackthornesArrows
    shared.wants.Pets = true
    shared.claims.Pets = 1e9
    suite.check("another addon's arrow aimed later wins", not ui.Wins(true))
    shared.claims.Pets = -1
    ui:Claim()
    suite.check("aiming this one again wins it back", ui.Wins(true))
    shared.claims.Pets = 1e9
    shared.wants.Pets = nil
    suite.check("the other put away, this one shows", ui.Wins(true))
    ui.Wins(false)
    suite.check("off, it stops wanting", next(shared.wants) == nil)
    _G.BlackthornesArrows = nil
end

--------------------------------------------------------------------------------
-- A grinding camp (the Grind tab)
--------------------------------------------------------------------------------

do
    env.world.zone = "Elwynn Forest"
    env.world.mapID = 37
    env.world.position = { 0.45, 0.50 }
    Arrow:SetOn(true)
    local camp = { zone = "Elwynn Forest", label = "Test Camp", count = 3, mobs = {
        { name = "Far Bandit", zone = "Elwynn Forest", coords = { 85, 50 }, minLevel = 5, maxLevel = 6 },
        { name = "Near Bandit", zone = "Elwynn Forest", coords = { 50, 50 }, minLevel = 5, maxLevel = 6 },
        { name = "Lost Bandit", zone = "Elwynn Forest", minLevel = 5, maxLevel = 6 },
    } }
    suite.check("a camp can be followed", Arrow:Grind(camp))
    local grind = Arrow:State(clock + 50)
    suite.check("it points", grind.mode == "point", grind.mode)
    suite.check("at the nearest of the camp's mobs", grind.target and grind.target.name == "Near Bandit",
        grind.target and grind.target.name)
    suite.check("the plate names the camp", grind.goal and grind.goal.grind == camp
        and grind.goal.item == "Elwynn Forest, Test Camp")
    suite.check("a mob with no spot of its own is the zone, named for the camp",
        Arrow.targets[3] and Arrow.targets[3].here and Arrow.targets[3].name == "Test Camp")
    suite.check("right-click steps to the next mob", Arrow:NextSpot().name == "Far Bandit")
    local okDraw, errDraw = pcall(ArrowUI.Draw, ArrowUI, true)
    suite.check("the dial draws it", okDraw, errDraw)
    suite.check("with the camp on its plate", ArrowUI.title:GetText() == "Grind: Elwynn Forest, Test Camp",
        ArrowUI.title:GetText())
    Arrow:NextGoal()
    suite.check("the next goal goes back to the goals", Arrow.grind == nil)
end

-- A node from the Grind tab: its spots are nodes, so a spot
-- reached and empty moves the arrow on to the next.
do
    env.world.position = { 0.45, 0.50 }
    local camp = ns.GrindGather.NodeCamp({ name = "Silverleaf", zone = "Elwynn Forest",
        spotList = { { 50, 50, map = 37 }, { 70, 50, map = 37 } } })
    suite.check("a node camp's spots are nodes", camp.mobs[1].kind == "node")
    Arrow:Grind(camp)
    clock = clock + 100
    local grind = Arrow:State(clock)
    suite.check("it points at the nearest spot", grind.target and near(grind.target.x, 0.50),
        grind.target and grind.target.x)
    env.world.position = { 0.502, 0.50 }
    clock = clock + Arrow.REFRESH
    grind = Arrow:State(clock)
    suite.check("standing on it is there, at a node's reach", grind.mode == "arrived", grind.mode)
    clock = clock + Arrow.REFRESH
    grind = Arrow:State(clock)
    suite.check("then it points at the next spot", grind.target and near(grind.target.x, 0.70),
        grind.target and grind.target.x)
    Arrow:StopGrind()
    Arrow.checked = {}
    env.world.position = { 0.45, 0.50 }
end

-- Farmer's XP bar comes up after the arrow: the arrow hears it being built
-- and shown (no timer), moves below it, the whole pill, and leaves a spot
-- clear of it alone.
do
    local frame = ArrowUI:Build()
    frame:Show()
    local rects = {
        [frame] = { 700, 950, 150, 26 },
    }
    for part, rect in pairs(rects) do
        part.GetRect = function() return rect[1], rect[2], rect[3], rect[4] end
        part.IsShown = function() return true end
    end
    if ArrowUI.close then
        ArrowUI.close.GetRect = function() return 830, 956, 14, 14 end
        ArrowUI.close.IsShown = function() return true end
    end

    local hooksBefore = _G.hooksecurefunc
    _G.hooksecurefunc = function(t, name, fn)
        local original = t[name]
        t[name] = function(...)
            local a, b = original(...)
            fn(...)
            return a, b
        end
    end
    local scripts = {}
    local bar = CreateFrame("Frame")
    bar.IsShown = function() return true end
    bar.GetRect = function() return 600, 1000, 400, 40 end
    bar.HookScript = function(_, script, fn) scripts[script] = fn end
    local xp = {}
    function xp:Build() self.frame = bar; return bar end
    local saved = _G.BlackthornesFarmer.XPBarUI
    _G.BlackthornesFarmer.XPBarUI = xp
    ArrowUI.watchingBar, ArrowUI.watchedBar = nil, nil
    frame._point = { "CENTER", UIParent, "BOTTOMLEFT", 775, 925 }

    ArrowUI:AvoidXPBar()
    suite.check("with no bar yet the arrow waits for Farmer to build one", xp.frame == nil)
    xp:Build()
    suite.check("then it listens to the bar", scripts.OnShow ~= nil and scripts.OnSizeChanged ~= nil)
    local point = frame._point
    suite.check("a spot clear of the bar stays", point[1] == "CENTER" and point[4] == 775, point[1])

    rects[frame][2] = 985
    scripts.OnSizeChanged(bar)
    point = frame._point
    suite.check("the pill's edge on the bar is enough to move it below",
        point[1] == "TOP" and point[2] == bar and point[3] == "BOTTOM", point[1])

    bar.IsShown = function() return false end
    local savedX, savedY = ns.db.arrowX, ns.db.arrowY
    ns.db.arrowX, ns.db.arrowY = 775, 925
    scripts.OnHide(bar)
    point = frame._point
    suite.check("the bar hiding puts the arrow back on its saved spot",
        point[1] == "CENTER" and point[4] == 775 and point[5] == 925, point[1])
    ns.db.arrowX, ns.db.arrowY = savedX, savedY

    _G.BlackthornesFarmer.XPBarUI = saved
    _G.hooksecurefunc = hooksBefore
    ArrowUI.watchingBar, ArrowUI.watchedBar = nil, nil
end

--------------------------------------------------------------------------------
-- The pill's three looks: pointing (above), there, and can't point
--------------------------------------------------------------------------------

do
    local realState = Arrow.State
    local goal = { item = "Copper Ore", have = 12, target = 40 }
    local tints = {}
    for _, texture in ipairs(ArrowUI.edge) do
        texture.SetVertexColor = function(_, r, g, b) tints[texture] = { r, g, b } end
    end
    local function EdgeIs(color)
        local tint = tints[ArrowUI.edge[2]]
        return tint and near(tint[1], color[1]) and near(tint[2], color[2]) and near(tint[3], color[3])
    end

    -- Pointing first, so each look below is a change.
    Arrow.State = function() return { mode = "point", goal = goal, distance = "150 yd", turn = 0 } end
    ArrowUI:Draw(true)
    Arrow.State = function() return { mode = "arrived", goal = goal, distance = "You're there" } end
    ArrowUI:Draw(true)
    suite.check("there: a green check in the well", ArrowUI.check:IsShown() and not ArrowUI.chevron:IsShown()
        and not ArrowUI.dot:IsShown())
    suite.check("there: the edge turns green", EdgeIs(ArrowUI.COLORS.edgeThere))
    suite.check("there: You're there under the goal", ArrowUI.distance:GetText() == "You're there"
        and ArrowUI.title:GetText() == "Copper Ore  12 / 40", ArrowUI.distance:GetText())

    local trip = { index = 1, count = 3, plan = { steps = { {}, {}, {} } } }
    Arrow.State = function() return { mode = "trip", goal = goal, trip = trip, distance = "" } end
    ArrowUI:Draw(true)
    suite.check("can't point: a dot in the well", ArrowUI.dot:IsShown() and not ArrowUI.chevron:IsShown()
        and not ArrowUI.check:IsShown())
    suite.check("can't point: the edge is gold again", EdgeIs(ArrowUI.COLORS.edge))
    suite.check("can't point: the step under the goal", ArrowUI.distance:GetText() == "Step 1 of 3",
        ArrowUI.distance:GetText())
    suite.check("no ? mark any more", ArrowUI.mark == nil)

    -- The dot pulses on Full and holds still otherwise.
    local alphas = {}
    ArrowUI.dot.SetAlpha = function(_, alpha) alphas[#alphas + 1] = alpha end
    local level = ns.Motion.Level
    ns.Motion.Level = function() return "full" end
    ArrowUI:Breathe(0.1)
    ArrowUI:Breathe(0.5)
    suite.check("on Full the dot pulses", #alphas == 2 and not near(alphas[1], alphas[2]))
    ns.Motion.Level = function() return "subtle" end
    alphas = {}
    ArrowUI:Breathe(0.1)
    ArrowUI:Breathe(0.5)
    suite.check("on Subtle it holds still", #alphas == 2 and near(alphas[1], alphas[2]))
    ns.Motion.Level = level

    Arrow.State = realState
    ArrowUI:Draw(true)
end

--------------------------------------------------------------------------------
-- Standing still, the dial is read about twice a second, not 33 times
-- (each read made new tables and words; memory climbed while idle in town)
--------------------------------------------------------------------------------

do
    local realDraw, realFrame, draws = ArrowUI.Draw, ArrowUI.frame, 0
    local realMoving, realFacing = rawget(_G, "IsPlayerMoving"), rawget(_G, "GetPlayerFacing")
    local moving, facing = false, 1.25
    _G.IsPlayerMoving = function() return moving end
    _G.GetPlayerFacing = function() return facing end
    ArrowUI.frame = { IsShown = function() return false end }
    ArrowUI.Draw = function() draws = draws + 1 end
    ArrowUI.since, ArrowUI.restFor, ArrowUI.settled = 0, 0, false
    for _ = 1, 100 do ArrowUI:Step(0.03) end
    suite.check("standing still it looks about twice a second", draws >= 4 and draws <= 9, draws)
    draws = 0
    facing = 2.5
    ArrowUI:Step(0.03)
    suite.check("turning shows at once", draws == 1, draws)
    draws, moving = 0, true
    for _ = 1, 10 do ArrowUI:Step(0.03) end
    suite.check("walking keeps up every step", draws == 10, draws)
    draws, moving = 0, false
    ArrowUI.Draw = function(self) draws = draws + 1; self.drawnKey = tostring(draws) end
    for _ = 1, 10 do ArrowUI:Step(0.03) end
    suite.check("words still changing keep up every step", draws == 10, draws)
    draws = 0
    _G.IsPlayerMoving = function() error("secret") end
    ArrowUI.Draw = function() draws = draws + 1 end
    for _ = 1, 10 do ArrowUI:Step(0.03) end
    suite.check("a client that won't say keeps up every step", draws == 10, draws)
    _G.IsPlayerMoving, _G.GetPlayerFacing = realMoving, realFacing
    ArrowUI.Draw, ArrowUI.frame = realDraw, realFrame
    ArrowUI.settled, ArrowUI.drawnKey, ArrowUI.drawnFacing = nil, nil, nil
end


suite.done()
