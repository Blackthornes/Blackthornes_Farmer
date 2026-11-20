-- Fishing schools told apart by the game, not by their English names.
--
-- A player's screenshot (2026-11-16) showed schools not being found. Schools
-- were known only by English name endings and only when moused over just
-- before the cast, so a German client, a new Forever school name or a cast
-- with no look first all landed in open water. The loot window names where
-- the catch came from: the school itself, or the bobber in open water. The
-- bobber is new each cast, so one object owning two casts' catch is a
-- school, known by its entry ID from then on in every language.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("fishschools")

local clock = 100
local ns = env.Load({ ui = true })
local Fishing = ns.Fishing

_G.GetTime = function() return clock end
_G.GetPlayerFacing = function() return 1.0 end

local tooltipShown
local tooltip = { text = nil }
_G.GameTooltip.HookScript = function(_, script, fn)
    if script == "OnShow" then tooltipShown = fn end
end
_G.GameTooltip.GetUnit = function() return nil end
_G.GameTooltip.GetItem = function() return nil end
_G.GameTooltipTextLeft1 = { GetText = function() return tooltip.text end }

ns.Harvest:OnEnable()
ns.Tracker:OnEnable()
Fishing:OnEnable()

local fire = ns.eventFrame:GetScript("OnEvent")

local source
_G.GetLootSourceInfo = function() if source then return source, 1 end end

local function Hover(name)
    tooltip.text = name
    tooltipShown(_G.GameTooltip)
end

local bobbers = 0
local function Bobber()
    bobbers = bobbers + 1
    return ("GameObject-0-1-0-0-35591-%010X"):format(bobbers)
end
local POOL = "GameObject-0-1-0-0-180582-00000000AA"
local POOL2 = "GameObject-0-1-0-0-180582-00000000BB"

local function CastAndCatch(from, item, look)
    clock = clock + 20
    if look then Hover(look) end
    fire(ns.eventFrame, "UNIT_SPELLCAST_CHANNEL_START", "player", "Cast-1", 7620)
    source = from
    env.world.fishing = true
    env.world.target = nil
    env.world.loot = { item }
    fire(ns.eventFrame, "LOOT_OPENED")
    fire(ns.eventFrame, "LOOT_CLOSED")
    env.world.fishing = false
    source = nil
end

local OILY = { name = "Oily Blackmouth", id = 6358 }
local SMALLFISH = { name = "Raw Brilliant Smallfish", id = 6291 }

env.world.zone = "Westfall"
env.world.subZone = "The Dagger Hills"

local function Casts(school)
    local spot = Fishing:Summary(Fishing.SpotKey("Westfall", "The Dagger Hills", school))
    return spot and spot.casts or 0
end

-- The owner (2026-11-20): "fished lots of schools and it doesn't detect it
-- even with mouse over it". His save had learned no school at all: on his
-- client a school's catch comes off the bobber too. Until the game has shown
-- once that a school hands out its own catch, the bobber says nothing, and
-- the school you moused over is the school.
CastAndCatch(Bobber(), OILY, "Sagefish School")
suite.check("a moused-over school counts though the catch came off the bobber",
    Casts("Sagefish School") == 1, Casts("Sagefish School"))
-- A recast from a key, standing still, with no second look.
tooltip.text = nil
clock = clock + 60
CastAndCatch(Bobber(), OILY)
suite.check("so does the recast into it", Casts("Sagefish School") == 2, Casts("Sagefish School"))
suite.check("and no bobber was learned as a school", next(Fishing:SchoolStore()) == nil)

-- The check tells what the game said, cast by cast, and is kept to read.
_G.UnitGUID = function(unit) if unit == "softinteract" then return "GameObject-0-1-0-0-35591-00000000F1" end end
_G.UnitName = function(unit) if unit == "softinteract" then return "Fishing Bobber" end end
CastAndCatch(Bobber(), OILY, "Sagefish School")
local okCheck = pcall(ns.KeepCheck, "fishing check", Fishing.Check, Fishing)
local probe = ns.db.lastProbe
local last = probe and probe.lines and probe.lines[#probe.lines] or ""
suite.check("the fishing check runs and is kept", okCheck and probe.check == "fishing check")
suite.check("it names what was looked at, the interact target and the loot's source",
    last:find("looked at Sagefish School", 1, true) and last:find("Fishing Bobber (GameObject 35591)", 1, true)
        and last:find("loot from [GameObject 35591]", 1, true), last)
_G.UnitGUID = function() return env.Secret("guid") end
suite.check("a secret interact target raises nothing", pcall(CastAndCatch, Bobber(), OILY, "Sagefish School"))
_G.UnitGUID, _G.UnitName = nil, nil

-- A German client: the school's name matches no English ending.
CastAndCatch(POOL, OILY, "Ölige Schwarzmaulschule")
CastAndCatch(POOL, OILY, "Ölige Schwarzmaulschule")
suite.check("the second cast goes to it by the client's name",
    Casts("Ölige Schwarzmaulschule") == 1, Casts("Ölige Schwarzmaulschule"))
suite.check("one object owning two casts' catch is a school",
    Fishing:SchoolStore()[180582] == "Ölige Schwarzmaulschule", Fishing:SchoolStore()[180582])

-- No look at all: a known school is found by its ID.
tooltip.text = nil
clock = clock + 60
CastAndCatch(POOL, OILY)
suite.check("a known school needs no look first", Casts("Ölige Schwarzmaulschule") == 2)

-- Another school of the same kind, never seen, still known on its first cast.
CastAndCatch(POOL2, OILY)
suite.check("a school of a known kind counts from its first cast",
    Casts("Ölige Schwarzmaulschule") == 3)

-- The name now counts in the client's language for the sparkles and the hover.
suite.check("the learned name is a school", Fishing.IsSchool("Ölige Schwarzmaulschule"))
suite.check("the object is a school", Fishing.IsSchoolObject(POOL2))
suite.check("the bobber is not", not Fishing.IsSchoolObject(Bobber()))

-- A catch off the bobber is open water, even right after a school.
local open = Casts(nil)
CastAndCatch(Bobber(), SMALLFISH)
CastAndCatch(Bobber(), SMALLFISH)
suite.check("a catch off the bobber is open water",
    Casts(nil) == open + 2 and Casts("Ölige Schwarzmaulschule") == 3)

-- Bobbers are new each cast, so they are never learned as a school, even
-- when their ID is not the one we expect.
local odd = 0
local function OddBobber()
    odd = odd + 1
    return ("GameObject-0-1-0-0-99999-%010X"):format(odd)
end
CastAndCatch(OddBobber(), SMALLFISH)
CastAndCatch(OddBobber(), SMALLFISH)
suite.check("a new object each cast is never a school", Fishing:SchoolStore()[99999] == nil)

-- An English school moused over teaches its ID on the second cast.
env.world.zone = "Westfall"
CastAndCatch("GameObject-0-1-0-0-180657-00000000CC", OILY, "Firefin Snapper School")
CastAndCatch("GameObject-0-1-0-0-180657-00000000CC", OILY, "Firefin Snapper School")
suite.check("an English school keeps its English name",
    Fishing:SchoolStore()[180657] == "Firefin Snapper School")

-- Nothing named it: the stand-in name, shown in the client's words.
CastAndCatch("GameObject-0-1-0-0-500001-00000000DD", OILY)
CastAndCatch("GameObject-0-1-0-0-500001-00000000DD", OILY)
suite.check("an unnamed school gets the stand-in name",
    Fishing:SchoolStore()[500001] == Fishing.SCHOOL)
suite.check("which shows as a fishing school", Fishing.ShowName(Fishing.SCHOOL) == "fishing school")
-- A real name later takes its place.
CastAndCatch("GameObject-0-1-0-0-500001-00000000EE", OILY, "Neue Schule")
suite.check("a real name replaces the stand-in", Fishing:SchoolStore()[500001] == "Neue Schule")

-- The sparkles call a learned school a school by its guid.
if ns.NodeSparkle and ns.NodeSparkle.Kind then
    suite.check("the sparkle knows the school in any language",
        ns.NodeSparkle:Kind("Irgendwas", POOL2) == "school")
end

-- A client that will not say where loot came from keeps the old way.
_G.GetLootSourceInfo = nil
CastAndCatch(nil, OILY, "Oily Blackmouth School")
suite.check("no loot sources: a moused-over school still counts",
    Casts("Oily Blackmouth School") == 1)

-- Secret values raise nothing.
_G.GetLootSourceInfo = function() return env.Secret("guid"), 1 end
suite.check("a secret loot source raises nothing", pcall(CastAndCatch, nil, SMALLFISH))

suite.done()
