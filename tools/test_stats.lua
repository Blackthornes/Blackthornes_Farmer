-- The Stats tab: the log it keeps as you play (Logic/Stats.lua) and the
-- tab that draws it (UI/Stats.lua).
--
-- What matters: loot, coin and kills land under the right day and source,
-- worth what they were worth when looted; only farming time counts (a long
-- gap is a break); an item with no price waits and is priced later; hidden
-- items stay out; the charts' numbers (sessions, usual pace, best mobs,
-- luck, days in a row, levels) add up; a best session is cheered once and
-- only when the setting allows; old days and short sessions are let go;
-- and the tab draws only while it is on screen.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("stats")

local ns = env.Load({ ui = true })
local Stats, StatsUI, Tracker, UI = ns.Stats, ns.StatsUI, ns.Tracker, ns.UI

suite.check("the module is loaded", Stats ~= nil and StatsUI ~= nil)

-- A clock the test moves, and a calendar on it.
local clock, wall = 1000, 1760000000   -- mid October 2026
_G.GetTime = function() return clock end
_G.time = function() return wall end
_G.date = function(format, at) return os.date(format, at or wall) end
local function Wait(seconds)
    clock = clock + seconds
    wall = wall + seconds
end

-- Prices: a fang 50c at auction, scraps 5c, a grey tooth 3c at vendor only,
-- a herb 20c, a fish 8c. Item 77777 has no price until told.
local AUCTION = { [5637] = 50, [2934] = 5, [2447] = 20, [6291] = 8 }
local VENDOR = { [5637] = 10, [2934] = 2, [3300] = 3 }
local QUALITY = { [3300] = 0 }
local later = {}
_G.C_Item = {
    GetItemInfo = function(id)
        return "item", nil, QUALITY[id] or 1, 1, 1, "", "", 1, "", "", VENDOR[id] or later[id] or 0
    end,
}
_G.BlackthornesTS = { Prices = { GetValue = function(_, id) return AUCTION[id] end } }

local serial = 0
local function Loot(mob, items)
    serial = serial + 1
    env.world.target = { name = mob, level = 8, dead = true, guid = "S-" .. serial }
    env.world.loot = items
    Tracker:OnLoot()
end

local FANG = { name = "Large Fang", id = 5637 }
local SCRAPS = { name = "Ruined Leather Scraps", id = 2934, quantity = 2 }
local TOOTH = { name = "Chipped Tooth", id = 3300 }
local COINS = { name = "12 Copper", money = true }
local ODD = { name = "Odd Trinket", id = 77777 }

--------------------------------------------------------------------------------
-- The log
--------------------------------------------------------------------------------

Loot("Mangy Wolf", { COINS, FANG })
Wait(30)
Loot("Mangy Wolf", { COINS, SCRAPS, TOOTH })

local store = ns.db.farmStats
suite.check("the log is kept in the account save", type(store) == "table" and type(store.days) == "table")
local today = store.days[Stats.DayKey()]
suite.check("today has a line", type(today) == "table")
suite.check("both kills are counted", today.kills == 2, today.kills)
suite.check("and by mob", today.mobs["Mangy Wolf"] == 2)
suite.check("coin goes under coin", today.coin == 24, today.coin)
suite.check("loot is worth its auction price when looted", today.drops == 50 + 2 * 5, today.drops)
suite.check("a grey goes under greys, at vendor", today.grey == 3, today.grey)
suite.check("the time between the loots is farming time", today.seconds == 30, today.seconds)
local session = Stats.current
suite.check("this login is a session", session ~= nil and store.sessions[#store.sessions] == session)
suite.check("which adds up the same copper", session.copper == 24 + 60 + 3, session.copper)

Wait(Stats.BREAK + 10)
Loot("Mangy Wolf", { COINS })
suite.check("a long gap is a break and adds no time", today.seconds == 30, today.seconds)

-- Gathering and fishing go under their own sources.
Wait(20)
ns.Stats:Loot("gather", "Peacebloom", 3)
suite.check("gathering goes under gathering", today.gather == 60 and Stats.pending == nil, today.gather)
Stats:Loot("fish", "Raw Brilliant Smallfish", 2)
suite.check("fish go under fishing", today.fish == 16, today.fish)

-- An item the client has not priced yet.
Wait(10)
Loot("Mangy Wolf", { ODD })
suite.check("an unpriced drop waits", Stats.pending ~= nil)
later[77777] = 40
Stats:Settle()
suite.check("and counts once it has a price", today.drops == 60 + 40, today.drops)

-- Hidden items never count.
ns.DB:Hide("item", "Large Fang")
local before = today.drops
Wait(10)
Loot("Mangy Wolf", { FANG })
suite.check("a hidden item adds nothing", today.drops == before, today.drops)
ns.DB:Unhide("item", "Large Fang")

local sources, total = Stats:Sources(7)
suite.check("the sources come in their order", sources[1].key == "drops" and sources[5].key == "grey")
suite.check("and add up", total == today.drops + today.coin + today.gather + today.fish + today.grey, total)

--------------------------------------------------------------------------------
-- Sessions, the usual pace and the best one
--------------------------------------------------------------------------------

-- Three earlier sessions of an hour each, at 1g, 2g and 1g 50s an hour.
local current = Stats.current
store.sessions = {
    { day = "2026-10-01", at = 1, seconds = 3600, copper = 10000, kills = 100 },
    { day = "2026-10-02", at = 2, seconds = 3600, copper = 20000, kills = 100 },
    { day = "2026-10-03", at = 3, seconds = 3600, copper = 15000, kills = 100 },
    { day = "2026-10-04", at = 4, seconds = 60, copper = 999, kills = 1 },
    current,
}
local usual = Stats:Usual()
suite.check("your usual is the earlier sessions by time", math.abs(usual - 15000) < 0.01, usual)
local series = Stats:Series(20)
suite.check("a session too short is not charted", #series == 3, #series)

ns.Print = (function(real) return function(text, ...)
    env.chat[#env.chat + 1] = text
end end)(ns.Print)

local played = {}
Tracker.PlayFile = function(path) played[#played + 1] = path return true end

current.seconds, current.copper, current.cheered = 1000, 1000, nil
env.chat = {}
Stats:CheckBest()
suite.check("a session short of the time is never the best yet", not current.cheered)

current.seconds, current.copper = Stats.BEST_AFTER, 30000 * Stats.BEST_AFTER / 3600
Stats:CheckBest()
suite.check("beating every session is cheered", current.cheered == true and #env.chat == 1, #env.chat)
suite.check("with the rank-up chime", played[1] == Tracker.SOUNDS.rankup)
Stats:CheckBest()
suite.check("once a session", #env.chat == 1, #env.chat)

current.cheered = nil
ns.db.statsBestCheer = false
env.chat, played = {}, {}
Stats:CheckBest()
suite.check("turned off, it says nothing", #env.chat == 0 and #played == 0)
ns.db.statsBestCheer = nil

local summary = Stats:Summary()
suite.check("this session's rate is shown", summary.rate and math.abs(summary.rate - 30000) < 0.01, summary.rate)
suite.check("against your usual", summary.change and math.abs(summary.change - 100) < 0.01, summary.change)

--------------------------------------------------------------------------------
-- Days in a row
--------------------------------------------------------------------------------

store.days = {}
local function Farm(back, kills)
    store.days[Stats.DayBack(back)] = { kills = kills or 1, mobs = {}, coin = 10 }
end
Farm(0) Farm(1) Farm(2) Farm(5) Farm(6) Farm(7) Farm(8)
local run, longest = Stats:Streak()
suite.check("days in a row count back from today", run == 3, run)
suite.check("and the longest run is kept", longest == 4, longest)
store.days[Stats.DayBack(0)] = nil
run = Stats:Streak()
suite.check("today not farmed yet keeps yesterday's run", run == 2, run)

local days = Stats:Days(70)
suite.check("the calendar is ten weeks, today last", #days == 70 and days[70].key == Stats.DayBack(0))

-- Pruning: a day past the keep and short sessions go.
store.days["2000-01-01"] = { kills = 1, mobs = {} }
Stats:Prune()
suite.check("old days are let go", store.days["2000-01-01"] == nil)
suite.check("days kept are left", store.days[Stats.DayBack(1)] ~= nil)
local short = false
for _, entry in ipairs(store.sessions) do
    if entry ~= Stats.current and (entry.seconds or 0) < Stats.SESSION_MIN then short = true end
end
suite.check("short sessions are let go, this one kept", not short and store.sessions[#store.sessions] == Stats.current)

--------------------------------------------------------------------------------
-- Best mobs, at your pace
--------------------------------------------------------------------------------

store.pace = {}
Stats.lastKillAt = nil
for _ = 1, 20 do
    Wait(15)
    Loot("Quick Boar", { COINS, FANG })
end
for _ = 1, 20 do
    Wait(60)
    Loot("Slow Bear", { COINS, FANG, FANG })
end
local pace = store.pace["Quick Boar"]
suite.check("each kill teaches its mob's pace", pace and pace.kills >= 19, pace and pace.kills)
local seconds, own = Stats:SecondsPerKill("Quick Boar")
suite.check("a mob's own pace", own and math.abs(seconds - 15) < 0.5, seconds)

local best = Stats:BestMobs(5)
local names = {}
for _, entry in ipairs(best) do names[#names + 1] = entry.mob end
suite.check("best mobs are by gold an hour, not per kill",
    names[1] == "Quick Boar", table.concat(names, ", "))
suite.check("gold an hour is worth per kill times kills an hour",
    math.abs(best[1].rate - best[1].perKill * 3600 / best[1].seconds) < 0.01)

--------------------------------------------------------------------------------
-- Luck
--------------------------------------------------------------------------------

ns.DB:RegisterItem({ name = "Lucky Charm", id = 99501, category = "misc",
    sources = { { name = "Charm Gnoll", zone = "Nowhere", minLevel = 5, chance = 10 } } })
AUCTION[99501] = 100
Stats.luck = nil
suite.check("no luck before enough kills", Stats:Luck() == nil)
for index = 1, 20 do
    Wait(10)
    Loot("Charm Gnoll", { COINS, index <= 4 and { name = "Lucky Charm", id = 99501 } or nil })
end
local luck = Stats:Luck()
suite.check("luck is worked out from the drop rates", luck ~= nil)
-- 20 kills at 10% is 2 expected; 4 dropped.
suite.check("twice the expected drops is 100% luckier",
    luck and math.abs(luck.percent - 100) < 0.01, luck and luck.percent)
suite.check("over the kills of rated mobs", luck and luck.kills == 20, luck and luck.kills)
suite.check("with the item listed", luck and luck.rows[1] and luck.rows[1].name == "Lucky Charm"
    and luck.rows[1].got == 4 and math.abs(luck.rows[1].expected - 2) < 0.01)
suite.check("words for it", StatsUI.LuckWords(100) == "100% luckier" and StatsUI.LuckWords(-20) == "20% less lucky"
    and StatsUI.LuckWords(2) == "Right on the odds")

--------------------------------------------------------------------------------
-- Levels
--------------------------------------------------------------------------------

local record = { levels = { [5] = 1200, [6] = 900, [7] = 2400 } }
local realRecord = ns.XP.Record
ns.XP.Record = function() return record end
local levels = Stats:Levels(15)
suite.check("levels come from the XP bar's record, in order",
    #levels == 3 and levels[1].level == 5 and levels[3].level == 7)
suite.check("the fastest is marked", levels[2].fastest == true and not levels[1].fastest)

--------------------------------------------------------------------------------
-- The tab
--------------------------------------------------------------------------------

UI:Build()
suite.check("the window has a Stats tab", UI.tabs.stats ~= nil)
UI:Show()
UI:ShowTab("stats")
suite.check("choosing it shows its view", UI.statsView:IsShown())
suite.check("and hides the search", not UI.searchView:IsShown())
suite.check("the window grows to fit the charts",
    UI.frame:GetWidth() == StatsUI.WIDTH and UI.frame:GetHeight() == StatsUI.HEIGHT,
    tostring(UI.frame:GetWidth()) .. "x" .. tostring(UI.frame:GetHeight()))
ns.Motion:FinishAll()
suite.check("it is remembered", ns.db.lastTab == "stats")

suite.check("the session card draws the line", StatsUI.sessionsCard.plot:IsShown())
suite.check("the mobs card lists the best", StatsUI.mobsCard.rows[1]:IsShown()
    and StatsUI.mobsCard.rows[1].name:GetText() == "Quick Boar", StatsUI.mobsCard.rows[1].name:GetText())
suite.check("the luck card says how lucky", StatsUI.luckCard.headline:GetText() == "100% luckier",
    StatsUI.luckCard.headline:GetText())
suite.check("the levels card names the fastest", StatsUI.levelsCard.headline:GetText():find("level 6", 1, true) ~= nil,
    StatsUI.levelsCard.headline:GetText())
suite.check("the top shows days in a row", StatsUI.tiles[4].value:GetText() == tostring(Stats:Streak()))

-- A click on a mob opens its loot table.
local opened
local realShow = ns.LootTableUI.Show
ns.LootTableUI.Show = function(_, mob) opened = mob end
StatsUI.mobsCard.rows[1]:GetScript("OnClick")(StatsUI.mobsCard.rows[1])
ns.LootTableUI.Show = realShow
suite.check("clicking a best mob opens its loot table", opened == "Quick Boar", opened)

-- Something moved while it shows: drawn again once.
local draws = 0
local realRender = StatsUI.Render
StatsUI.Render = function(self, ...) draws = draws + 1 return realRender(self, ...) end
Wait(10)
Loot("Quick Boar", { COINS })
suite.check("a loot while it shows draws it again", draws >= 1, draws)

UI:ShowTab("search")
suite.check("another tab hides it", not UI.statsView:IsShown())
suite.check("and the window is its usual height again", UI.frame:GetHeight() == 458, UI.frame:GetHeight())
draws = 0
Wait(10)
Loot("Quick Boar", { COINS })
suite.check("out of sight, nothing is drawn", draws == 0, draws)
StatsUI.Render = realRender

-- Empty, every card says what to do rather than drawing nothing.
ns.XP.Record = function() return { levels = {} } end
ns.db.farmStats = nil
Stats.current, Stats.luck = nil, nil
UI:ShowTab("stats")
ns.Motion:FinishAll()
suite.check("an empty log explains the sessions card", StatsUI.sessionsCard.empty:IsShown())
suite.check("and the sources card", StatsUI.sourcesCard.empty:IsShown())
suite.check("and the luck card", StatsUI.luckCard.empty:IsShown())
suite.check("and the levels card", StatsUI.levelsCard.empty:IsShown())
ns.XP.Record = realRecord

-- The command.
UI:ShowTab("search")
ns.HandleSlash("charts")
suite.check("/farm charts opens the tab", UI.tab == "stats")
ns.HandleSlash("charts cheer off")
suite.check("/farm charts cheer off turns the cheer off", ns.db.statsBestCheer == false)
ns.HandleSlash("charts cheer on")
suite.check("and on", ns.db.statsBestCheer == true)

suite.check("helpers: axis coins round", ns.Util.StripColor(StatsUI.AxisCoins(15400)) == "1g 50s",
    ns.Util.StripColor(StatsUI.AxisCoins(15400)))
suite.check("a day's brightness", StatsUI.DayLevel(0, 100) == 0 and StatsUI.DayLevel(100, 100) == 4
    and StatsUI.DayLevel(10, 100) == 1)

suite.done()
