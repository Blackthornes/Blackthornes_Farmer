-- The arrow's way there (Logic/Travel.lua, UI/TravelCard.lua,
-- UI/TravelMap.lua).
--
-- What matters: it is off until ticked; across the sea it takes the
-- quickest way the character can (a flight it knows, then the boat of its
-- side, then a walk), never a flight it has not learned or the other side's
-- boat; the steps read as players say them and their numbers hold as you
-- go, the ones behind you kept for the card; on a flight the plan stays as
-- it is; Stop ends the trip for that place only; a walk through other zones
-- aims at the spot you crossed before; and the card and the map line follow
-- the steps still ahead.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("travel")

local clock = 100
local ns = env.Load({ ui = true })
local Travel, TravelCard, TravelMap = ns.Travel, ns.TravelCard, ns.TravelMap

_G.GetTime = function() return clock end
local faction = "Alliance"
_G.UnitFactionGroup = function() return faction end
local onTaxi = false
_G.UnitOnTaxi = function() return onTaxi end
_G.InCombatLockdown = function() return false end

local printed = {}
local print = ns.Print
ns.Print = function(text, ...) printed[#printed + 1] = tostring(text) return print(text, ...) end

-- A small world: Stormwind and Menethil on one side of the sea, Theramore
-- on the other.
local DATA = Travel.DATA
DATA.flights = {
    [1] = { "Stormwind, Elwynn", "A", 0, 0, -200, "Elwynn" },
    [2] = { "Menethil Harbor, Wetlands", "A", 0, 3000, 1000, "Wetlands" },
    [3] = { "Booty Bay, Stranglethorn", "H", 0, -3000, 500, "Stranglethorn" },
}
DATA.paths = { 1, 2, 2, 1, 2, 3 }
DATA.docks = {
    menethil = { "Menethil Harbor", 0, 3050, 1000, "Wetlands" },
    theramore = { "Theramore", 1, -3000, -3000, "Dustwallow Marsh" },
}
DATA.rides = { { "menethil", "theramore", "boat", "A" } }

local start = { continent = 0, north = 0, west = 0, zone = "Elwynn Forest" }
local goal = { continent = 1, north = -3200, west = -3000, zone = "Dustwallow Marsh", name = "Mirefin camp" }

--------------------------------------------------------------------------------
-- The quickest way
--------------------------------------------------------------------------------

local legs, cost = Travel:Search(start, goal, "A", { [1] = true, [2] = true })
local steps = Travel.Steps(legs)
suite.check("across the sea there is a way", legs ~= nil and cost > 0)
suite.check("fly, boat, then walk", #steps == 3 and steps[1].kind == "fly" and steps[2].kind == "boat"
    and steps[3].kind == "walk", #steps)
suite.check("the flight goes to Menethil", steps[1].to.name == "Menethil Harbor")

local walked = Travel.Steps((Travel:Search(start, goal, "A", {})))
suite.check("no flight learned: walk to the dock, then the boat",
    #walked == 2 and walked[1].kind == "boat", #walked)
local slower = select(2, Travel:Search(start, goal, "A", {}))
suite.check("and that takes longer", slower > cost)

suite.check("the other side's boat is never taken", Travel:Search(start, goal, "H", { [1] = true }) == nil)
suite.check("nor the other side's flight master",
    not Travel:Stops("A", { [3] = true })["f3"])

local hearth = { continent = 1, north = -3100, west = -3000, zone = "Dustwallow Marsh", name = "Theramore" }
local quick = Travel.Steps((Travel:Search(start, goal, "A", { [1] = true, [2] = true }, hearth)))
suite.check("a Hearthstone landing near the place wins", quick[1].kind == "hearth" and #quick == 2)

--------------------------------------------------------------------------------
-- The words
--------------------------------------------------------------------------------

suite.check("flight masters by their short name", Travel.ShortName("Stormwind, Elwynn") == "Stormwind")
local line, small = Travel.StepWords(steps[1])
suite.check("a flight", line == "Fly to Menethil Harbor" and small == "Talk to the flight master", line)
line, small = Travel.StepWords(steps[2], true)
suite.check("on the dock", line == "Wait here for the boat to Theramore" and small == "Get on when it stops", line)
line = Travel.StepWords(quick[1])
suite.check("the Hearthstone", line == "Use your Hearthstone")

--------------------------------------------------------------------------------
-- A trip as you go
--------------------------------------------------------------------------------

Travel.WorldOf = function(_, target) return target.place end
local target = { name = "Mirefin camp", zone = "Dustwallow Marsh", place = goal }
ns.db.travelFlights = { [UnitGUID("player")] = { [1] = true, [2] = true } }

suite.check("off unless ticked", Travel:Use(target, start, clock) == nil)
ns.db.arrowRoute = true

local trip = Travel:Use(target, start, clock)
suite.check("step 1 of 3", trip and trip.index == 1 and trip.count == 3, trip and trip.count)
suite.check("the arrow aims at the flight master", trip.north == 0 and trip.west == -200)

clock = clock + 1
local dock = { continent = 0, north = 3040, west = 1000, zone = "Wetlands" }
Travel.due = true
trip = Travel:Use(target, dock, clock)
suite.check("landed: step 2 of 3", trip.index == 2 and trip.count == 3, trip.index .. "/" .. trip.count)
suite.check("the flight is behind you", #trip.plan.behind == 1 and trip.plan.behind[1].kind == "fly")
suite.check("standing on the dock", trip.atStop and trip.line == "Wait here for the boat to Theramore", trip.line)
suite.check("chat says what's next", printed[#printed] and printed[#printed]:find("Theramore") ~= nil,
    printed[#printed])

local rows = TravelCard.Rows(trip.plan)
suite.check("the card: done, now, then the rest", #rows == 3 and rows[1].done and rows[2].now
    and not rows[3].now, #rows)
suite.check("numbered from the start", rows[1].title:find("^1%. ") and rows[2].title:find("^2%. "))
suite.check("about how long", TravelCard.TimeText(trip.plan):find("minute") ~= nil)

local mapLegs = TravelMap.Legs(trip.plan, dock)
suite.check("the map line: to the boat, the boat, the walk",
    #mapLegs == 3 and mapLegs[2].kind == "boat" and mapLegs[3].kind == "walk", #mapLegs)
suite.check("a boat is dashed", #TravelMap.Pieces("boat", 0, 0, 1, 0) > 5)
suite.check("a walk is one line", #TravelMap.Pieces("walk", 0, 0, 1, 0) == 1)

-- On the boat: the plan holds, whatever is due.
onTaxi = true
clock = clock + 100
Travel.due = true
local held = Travel:Use(target, { continent = 0, north = 0, west = 0, zone = "Wetlands" }, clock)
suite.check("on a ride the plan stays", held.index == 2 and held.plan == trip.plan)
onTaxi = false

--------------------------------------------------------------------------------
-- Stop
--------------------------------------------------------------------------------

Travel:StopTrip()
suite.check("Stop ends the trip", Travel:Use(target, dock, clock) == nil)
local other = { name = "Mudrock camp", zone = "Dustwallow Marsh", place = goal }
suite.check("a new place has a trip again", Travel:Use(other, dock, clock) ~= nil)

--------------------------------------------------------------------------------
-- Walking through other zones
--------------------------------------------------------------------------------

suite.check("next door is no trip", not Travel.WorthATrip(start,
    { continent = 0, north = -100, west = 0, zone = "Duskwood" }))
suite.check("two zones over is", Travel.WorthATrip(start,
    { continent = 0, north = -3000, west = 0, zone = "Stranglethorn Vale" }))

Travel:NoteCrossing("Elwynn Forest", "Duskwood", { continent = 0, north = -900, west = 40 })
local _, north, west, toward = Travel:Toward(start,
    { continent = 0, north = -3000, west = 0, zone = "Stranglethorn Vale" })
suite.check("aims at where you crossed before", north == -900 and west == 40 and toward == "Duskwood",
    tostring(north) .. "," .. tostring(toward))
Travel:NoteCrossing("Elwynn Forest", "Duskwood", { continent = 0, north = -1000, west = 40 })
suite.check("and keeps the average of the walks", ns.db.travelCrossings["Elwynn Forest|Duskwood"][2] == -950)
Travel:NoteCrossing("Elwynn Forest", "Tanaris", { continent = 0, north = 0, west = 0 })
suite.check("zones that don't touch keep nothing", ns.db.travelCrossings["Elwynn Forest|Tanaris"] == nil)

suite.done()
