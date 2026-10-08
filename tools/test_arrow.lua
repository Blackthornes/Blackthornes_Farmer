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
suite.check("and says why", resting and Arrow.Note(resting, wall):find("may not be back", 1, true) ~= nil)
ns.db.gathering.spots[2].last = wall - 3600

-- Standing on it.
env.world.position = { 0.502, 0.50 }
clock = clock + Arrow.REFRESH
state = Arrow:State(clock)
suite.check("close enough is there", state.mode == "arrived" and state.distance == "You're there",
    state.mode .. " " .. tostring(state.yards))
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
suite.check("the distance under it", ArrowUI.distance:GetText() == "150 yd", ArrowUI.distance:GetText())

local turned
ArrowUI.arrow.SetRotation = function(_, value) turned = value end
ArrowUI.shownTurn = nil
ArrowUI:Draw(true)
suite.check("the arrow is turned", near(turned, -math.pi / 2), turned)

suite.check("wide enough for its words",
    frame:GetWidth() >= ns.Theme.TextWidth("small", ArrowUI.place:GetText()))

-- Right-click on the dial: the next place.
ArrowUI:OnClick("RightButton")
suite.check("right-click on the dial steps on", Arrow.index == 2, Arrow.index)
-- A drag is not a click.
frame:GetScript("OnDragStart")(frame)
frame:GetScript("OnDragStop")(frame)
local before = Arrow:Goal()
frame:GetScript("OnMouseUp")(frame, "LeftButton")
suite.check("letting go after a drag changes nothing", Arrow:Goal() == before)

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

suite.done()
