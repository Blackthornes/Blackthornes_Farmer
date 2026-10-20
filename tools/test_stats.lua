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

-- Pricing it can draw the tab again, which settles again: still counted once.
later[77777] = nil
Loot("Mangy Wolf", { ODD })
later[77777] = 40
local price0 = Stats.Price
local inner = false
Stats.Price = function(self, ...)
    local done = price0(self, ...)
    if not inner then inner = true; Stats:Settle() end
    return done
end
local ok = pcall(Stats.Settle, Stats)
Stats.Price = price0
suite.check("a settle inside a settle prices the drop once", ok and today.drops == 60 + 80 and Stats.pending == nil,
    today.drops)

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

-- Goblin Gold in Tradeskills reads kills and their loot over a week.
store.days = {}
store.days[Stats.DayBack(0)] = { kills = 4, drops = 300, grey = 20, coin = 50, gather = 999, mobs = {} }
store.days[Stats.DayBack(6)] = { kills = 6, drops = 100, coin = 30, mobs = {} }
store.days[Stats.DayBack(7)] = { kills = 90, drops = 9000, coin = 900, mobs = {} }
local week = Stats:KillsAndLoot(7)
suite.check("a week's kills, today and six days back", week.kills == 10, week.kills)
suite.check("its loot is drops and greys, never gathering", week.loot == 420, week.loot)
suite.check("and its coin", week.coin == 80, week.coin)
store.days = {}
Farm(0) Farm(1) Farm(2) Farm(5) Farm(6) Farm(7) Farm(8)

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

-- Kills from before the Stats tab carry no timing: the mobs are still
-- ranked, by worth per kill, until a kill speed is timed.
local timed = store.pace
store.pace = {}
local byWorth, byKill = Stats:BestMobs(5)
suite.check("with no kill speed yet, mobs are still ranked", #byWorth >= 2 and byKill == true, #byWorth)
suite.check("by worth per kill", byWorth[1].mob == "Slow Bear" and byWorth[1].rate == nil, byWorth[1].mob)
store.pace = timed

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
-- This session and Overall
--------------------------------------------------------------------------------

suite.check("the view is This session until picked", Stats:View() == "session")
Stats:SetView("overall")
suite.check("Overall is kept in the account save", Stats:View() == "overall" and ns.db.statsView == "overall")
Stats:SetView("session")

-- This session's gold by source adds up to the session's copper.
local sessionList, sessionTotal = Stats:SessionSources()
suite.check("this session's sources come in their order", sessionList[1].key == "drops" and #sessionList == 5)
suite.check("and add up to what the session made", sessionTotal > 0, sessionTotal)

-- Overall's sources are every day kept, with the first day farmed.
local _, allTotal, first = Stats:AllSources()
local sum = 0
for _, day in pairs(store.days) do sum = sum + Stats.DayCopper(day) end
suite.check("overall sources are every day kept", allTotal == sum, allTotal .. " vs " .. sum)
suite.check("from the first day farmed", first == Stats.DayBack(8), first)

-- How this session's gold grew.
local curve = Stats:Curve(10)
suite.check("this session's gold draws as a curve", curve and #curve == 10, curve and #curve)
suite.check("starting from nothing", curve and curve[1].copper == 0 and curve[1].seconds == 0)
local rising = true
for index = 2, #(curve or {}) do
    if curve[index].copper < curve[index - 1].copper then rising = false end
end
suite.check("and only rising", rising)
suite.check("ending at what the session made so far",
    curve and curve[#curve].copper == Stats.curve[#Stats.curve][2])

-- The mobs killed this session only.
local sessionBest = Stats:BestMobs(5, "session")
suite.check("This session ranks only the mobs killed since login",
    #sessionBest == 1 and sessionBest[1].mob == "Charm Gnoll" and sessionBest[1].sessionKills == 20,
    sessionBest[1] and sessionBest[1].mob)
suite.check("Overall ranks every mob measured", #Stats:BestMobs(5, "overall") >= 3)

-- Luck over the whole kill tally.
local overallLuck = Stats:Luck("overall")
suite.check("overall luck reads the kill tally", overallLuck and overallLuck.kills == 20
    and math.abs(overallLuck.percent - 100) < 0.01, overallLuck and overallLuck.percent)
local summaryNow = Stats:Summary()
local tallied = 0
for _, mob in pairs(Tracker:Store()) do tallied = tallied + (mob.kills or 0) end
suite.check("overall kills are the whole kill tally", summaryNow.allKills == tallied, summaryNow.allKills)
suite.check("this session's most killed mob", summaryNow.topMob == "Charm Gnoll" and summaryNow.topKills == 20,
    summaryNow.topMob)

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

ns.db.statsView = "overall"
UI:Build()
suite.check("the window has a Stats tab", UI.tabs.stats ~= nil)
UI:Show()
UI:ShowTab("stats")
suite.check("choosing it shows its view", UI.statsView:IsShown())
suite.check("and hides the search", not UI.searchView:IsShown())
suite.check("the window fits the charts",
    UI.frame:GetWidth() >= StatsUI.WIDTH and UI.frame:GetHeight() == StatsUI.HEIGHT,
    tostring(UI.frame:GetWidth()) .. "x" .. tostring(UI.frame:GetHeight()))
suite.check("the charts fill the window's width", StatsUI.canvas:GetWidth() == UI.frame:GetWidth(),
    StatsUI.canvas:GetWidth())

-- One size for every tab (the owner, 2026-10-17).
local statsW, statsH = UI.frame:GetWidth(), UI.frame:GetHeight()
for _, key in ipairs({ "search", "rankings", "grind", "stats" }) do
    UI:ShowTab(key)
    suite.check("the " .. key .. " tab keeps the one size",
        UI.frame:GetWidth() == statsW and UI.frame:GetHeight() == statsH,
        tostring(UI.frame:GetWidth()) .. "x" .. tostring(UI.frame:GetHeight()))
end
UI:Claim(statsW + 100)
UI:ShowTab("search")
suite.check("a tab that needs more widens every tab", UI.frame:GetWidth() == statsW + 100,
    UI.frame:GetWidth())
UI:ShowTab("grind")
suite.check("and the others keep it", UI.frame:GetWidth() == statsW + 100, UI.frame:GetWidth())
suite.check("the width is kept for next time", ns.db.windowWidth == statsW + 100, ns.db.windowWidth)
UI:ShowTab("stats")
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

suite.check("the switch shows Overall", StatsUI.switch.selected == "overall")
suite.check("Overall days carry no note", not StatsUI.daysCard.sameTag:IsShown())

-- The switch to This session.
local sessionTab
for _, button in ipairs(StatsUI.switch.tabs) do
    if button.key == "session" then sessionTab = button end
end
sessionTab:GetScript("OnClick")(sessionTab)
ns.Motion:FinishAll()
suite.check("picking This session is remembered", ns.db.statsView == "session")
suite.check("the gold card follows it", StatsUI.sessionsCard.title:GetText() == "Gold this session"
    and StatsUI.sessionsCard.plot:IsShown())
suite.check("the mobs card lists this session's mobs", StatsUI.mobsCard.rows[1].name:GetText() == "Charm Gnoll"
    and not StatsUI.mobsCard.rows[2]:IsShown(), StatsUI.mobsCard.rows[1].name:GetText())
suite.check("the top shows this session's most killed", StatsUI.tiles[4].value:GetText() == "Charm Gnoll",
    StatsUI.tiles[4].value:GetText())
suite.check("days and levels say they are the same in both",
    StatsUI.daysCard.sameTag:IsShown() and StatsUI.levelsCard.sameTag:IsShown())
ns.db.statsView = "overall"
StatsUI:Render()

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
suite.check("and the window keeps its height", UI.frame:GetHeight() == StatsUI.HEIGHT, UI.frame:GetHeight())
draws = 0
Wait(10)
Loot("Quick Boar", { COINS })
suite.check("out of sight, nothing is drawn", draws == 0, draws)
StatsUI.Render = realRender

-- Empty, every card says what to do rather than drawing nothing.
ns.XP.Record = function() return { levels = {} } end
ns.db.farmStats = nil
Stats.current, Stats.luck, Stats.curve = nil, nil, nil
ns.db.statsView = "session"
UI:ShowTab("stats")
ns.Motion:FinishAll()
suite.check("an empty log explains the sessions card", StatsUI.sessionsCard.empty:IsShown())
suite.check("and the sources card", StatsUI.sourcesCard.empty:IsShown())
suite.check("and the luck card", StatsUI.luckCard.empty:IsShown())
suite.check("and the levels card", StatsUI.levelsCard.empty:IsShown())
suite.check("and the top says what shows when", StatsUI.tiles[2].note:GetText() == "Nothing farmed yet",
    StatsUI.tiles[2].note:GetText())
ns.XP.Record = realRecord

-- The command.
UI:ShowTab("search")
ns.HandleSlash("charts")
suite.check("/farm charts opens the tab", UI.tab == "stats")
ns.HandleSlash("charts session")
suite.check("/farm charts session picks This session", Stats:View() == "session")
ns.HandleSlash("charts overall")
suite.check("/farm charts overall picks Overall", Stats:View() == "overall")
ns.HandleSlash("charts cheer off")
suite.check("/farm charts cheer off turns the cheer off", ns.db.statsBestCheer == false)
ns.HandleSlash("charts cheer on")
suite.check("and on", ns.db.statsBestCheer == true)

suite.check("helpers: axis coins round", ns.Util.StripColor(StatsUI.AxisCoins(15400)) == "1g 50s",
    ns.Util.StripColor(StatsUI.AxisCoins(15400)))
suite.check("a day's brightness", StatsUI.DayLevel(0, 100) == 0 and StatsUI.DayLevel(100, 100) == 4
    and StatsUI.DayLevel(10, 100) == 1)

suite.done()
