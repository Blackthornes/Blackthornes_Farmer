-- The bug pass of 2026-11-26.
--
-- What matters: a level up moves Rankings' "Near my level" band at once,
-- though the game still gives the old level for a moment; a saved farm's
-- last run is told in calendar days ("Yesterday" for any time yesterday);
-- and the Stats tab's days step back one calendar day each, on a day the
-- clocks change too.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("bugpass3")

local ns = env.Load({ ui = true })

--------------------------------------------------------------------------------
-- 1. Near my level right after a level up
--------------------------------------------------------------------------------

local Rankings = ns.Rankings
local gameLevel = 25
_G.UnitLevel = function(unit)
    if unit == "player" then return gameLevel end
    return 0
end

Rankings:OnEnable()
local fire = ns.eventFrame:GetScript("OnEvent")

suite.check("the level is the game's", Rankings.PlayerLevel() == 25, Rankings.PlayerLevel())

-- The game sends the event with the new level while UnitLevel still gives
-- the old one.
fire(ns.eventFrame, "PLAYER_LEVEL_UP", 26, 10, 5, 1)
suite.check("a level up counts before the game catches up", Rankings.PlayerLevel() == 26,
    Rankings.PlayerLevel())

ns.db.rankingsNearLevel = true
local entry = { minLevel = 28, maxLevel = 28 }
suite.check("a mob 2 above the new level is near", Rankings:NearYou(entry) == true)
ns.db.rankingsNearLevel = nil

gameLevel = 26
suite.check("the same once the game catches up", Rankings.PlayerLevel() == 26)
gameLevel = 27
suite.check("the game's level wins when it is higher", Rankings.PlayerLevel() == 27)

-- A level the game won't let us read is still no level.
fire(ns.eventFrame, "PLAYER_LEVEL_UP", env.Secret("number"))
suite.check("an unreadable level up changes nothing", Rankings.PlayerLevel() == 27,
    Rankings.PlayerLevel())
_G.UnitLevel = function() error("secret value") end
suite.check("an unreadable level is still no level", Rankings.PlayerLevel() == nil)
_G.UnitLevel = function(unit) return unit == "player" and gameLevel or 0 end

--------------------------------------------------------------------------------
-- 2. A saved farm's last run, in calendar days
--------------------------------------------------------------------------------

local F = ns.SavedFarms
local function At(day, hour)
    return os.time({ year = 2026, month = 11, day = day, hour = hour, min = 0, sec = 0 })
end

suite.check("this morning, seen tonight, is Today", F.When(At(26, 1), At(26, 23)) == "Today")
suite.check("yesterday morning, seen tonight, is Yesterday",
    F.When(At(25, 1), At(26, 23)) == "Yesterday", F.When(At(25, 1), At(26, 23)))
suite.check("late last night, seen just after midnight, is Yesterday",
    F.When(At(25, 23), At(26, 1)) == "Yesterday")
suite.check("late two nights ago, seen just after midnight, is 2 days ago",
    F.When(At(24, 23), At(26, 1)) == "2 days ago", F.When(At(24, 23), At(26, 1)))
suite.check("six mornings ago, seen tonight, is 6 days ago",
    F.When(At(20, 1), At(26, 23)) == "6 days ago", F.When(At(20, 1), At(26, 23)))
suite.check("seven days back is Last week", F.When(At(19, 12), At(26, 12)) == "Last week")
suite.check("never run is Never", F.When(nil) == "Never")

--------------------------------------------------------------------------------
-- 3. Days step back one calendar day, when the clocks change too
--------------------------------------------------------------------------------

local Stats = ns.Stats

-- A wall clock that goes back an hour at SWITCH (autumn), so that day is
-- 25 hours long. Read as the game's date() reads it.
local SWITCH = os.time({ year = 2026, month = 11, day = 1, hour = 2, min = 0, sec = 0 })
local zoneNow = os.time() - os.time(os.date("!*t"))
local realDate = _G.date
_G.date = function(format, at)
    at = at or os.time()
    local shift = at >= SWITCH and -3600 or 0
    return os.date("!" .. format, at + zoneNow + shift)
end

-- 23:30 on the long day, by that clock.
local late = os.time({ year = 2026, month = 11, day = 1, hour = 23, min = 30, sec = 0 }) + 3600
suite.check("the test clock reads the long day", Stats.DayKey(late) == "2026-11-01", Stats.DayKey(late))
suite.check("today is today", Stats.DayBack(0, late) == "2026-11-01")
suite.check("one day back is yesterday, late on a 25 hour day",
    Stats.DayBack(1, late) == "2026-10-31", Stats.DayBack(1, late))
suite.check("two days back is the day before", Stats.DayBack(2, late) == "2026-10-30")

local store = Stats:Store()
local kept = store.days
store.days = {
    ["2026-11-01"] = { kills = 4, drops = 100, coin = 10, mobs = {} },
    ["2026-10-31"] = { kills = 6, drops = 300, coin = 30, mobs = {} },
}
local week = Stats:KillsAndLoot(2, late)
suite.check("two days count each day once", week.kills == 10 and week.loot == 400 and week.coin == 40,
    week.kills)
local run = Stats:Streak(late)
suite.check("two days in a row are a run of 2", run == 2, run)
store.days = kept

-- The short day in spring: the hour after midnight the next day.
local SPRING = os.time({ year = 2026, month = 3, day = 8, hour = 2, min = 0, sec = 0 })
_G.date = function(format, at)
    at = at or os.time()
    local shift = at >= SPRING and 3600 or 0
    return os.date("!" .. format, at + zoneNow + shift)
end
local early = os.time({ year = 2026, month = 3, day = 9, hour = 0, min = 30, sec = 0 }) - 3600
suite.check("the test clock reads the day after the short day", Stats.DayKey(early) == "2026-03-09",
    Stats.DayKey(early))
suite.check("one day back is the short day", Stats.DayBack(1, early) == "2026-03-08",
    Stats.DayBack(1, early))
suite.check("two days back is the day before it", Stats.DayBack(2, early) == "2026-03-07")

_G.date = realDate

suite.done()
