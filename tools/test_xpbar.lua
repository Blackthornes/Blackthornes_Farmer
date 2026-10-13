-- The XP bar (Logic/XP.lua, UI/XPBar.lua).
--
-- What matters: XP gained is counted across a level-up; a kill's chat line
-- gives the mob and its XP, and from it how many more kills finish the
-- level; finished quests in the log add up, and when they cover the rest of
-- the level the bar says so; the cap is the client's, else 60; a tenth of
-- the level crossed chimes once, and not when the chime is off; the time a
-- level took is kept by GUID and a fast one is cheered; the bar hides at the
-- cap and when turned off; the game's bar is made see-through, never
-- hidden, and put back; a /reload goes on with the session; and the command
-- writes the same keys as Settings.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("xpbar")

local now, clock = 1000, 50000
local realTime = _G.time

-- The player's XP, as the client gives it.
local player = { level = 20, xp = 1000, max = 23200, rested = 0 }
local function Client()
    _G.UnitLevel = function(unit)
        if unit == "player" then return player.level end
        return env.world.target and env.world.target.level or 0
    end
    _G.UnitXP = function() return player.xp end
    _G.UnitXPMax = function() return player.max end
    _G.GetXPExhaustion = function() return player.rested > 0 and player.rested or nil end
    _G.GetMaxLevelForPlayerExpansion = nil
    _G.GetMaxPlayerLevel = nil
    _G.MAX_PLAYER_LEVEL = nil
    _G.IsXPUserDisabled = nil
    _G.RequestTimePlayed = nil
    _G.COMBATLOG_XPGAIN_FIRSTPERSON = "%s dies, you gain %d experience."
    _G.C_QuestLog = nil
end

local ns = env.Load({ ui = true })
Client()
_G.GetTime = function() return now end
_G.time = function() return clock end
local XP, Bar = ns.XP, ns.XPBarUI

local sounds = {}
_G.PlaySoundFile = function(path) sounds[#sounds + 1] = path; return true end

for _, module in ipairs(ns.moduleOrder) do
    if module.OnEnable then module:OnEnable() end
end
local handler = _G.BlackthornesFarmerEventFrame:GetScript("OnEvent")
local function Fire(event, ...) handler(_G.BlackthornesFarmerEventFrame, event, ...) end
local run = SlashCmdList["BLACKTHORNESFARMER"]

local function Chimes()
    local count = 0
    for _, path in ipairs(sounds) do
        if path:find("xp%-tick") then count = count + 1 end
    end
    return count
end

--------------------------------------------------------------------------------
-- The cap
--------------------------------------------------------------------------------

suite.check("the cap is 60 when the client will not say", XP.MaxLevel() == 60, XP.MaxLevel())
_G.GetMaxPlayerLevel = function() return 30 end
suite.check("the client's cap wins", XP.MaxLevel() == 30, XP.MaxLevel())
_G.GetMaxLevelForPlayerExpansion = function() error("secret") end
suite.check("a cap that raises falls through", XP.MaxLevel() == 30, XP.MaxLevel())
_G.GetMaxPlayerLevel = nil
_G.GetMaxLevelForPlayerExpansion = nil
_G.MAX_PLAYER_LEVEL = 60
suite.check("the game's constant counts too", XP.MaxLevel() == 60, XP.MaxLevel())

--------------------------------------------------------------------------------
-- Start and gains
--------------------------------------------------------------------------------

Fire("PLAYER_ENTERING_WORLD")
suite.check("XP starts at login", XP.started == true)
suite.check("the bar shows", Bar.frame ~= nil and Bar.frame:IsShown())
suite.check("it has a session", XP.session and XP.session.gained == 0)

player.xp = 1500
Fire("PLAYER_XP_UPDATE", "player")
suite.check("XP gained is counted", XP.session.gained == 500, XP.session.gained)

-- 2320 is a tenth of 23200; crossing it chimes once.
player.xp = 2400
Fire("PLAYER_XP_UPDATE", "player")
suite.check("a tenth crossed chimes", Chimes() == 1, Chimes())
player.xp = 2500
Fire("PLAYER_XP_UPDATE", "player")
suite.check("no second chime inside the same tenth", Chimes() == 1, Chimes())

run("xpbar chime off")
suite.check("the chime command writes the setting", ns.db.xpBarChime == false)
player.xp = 4700
Fire("PLAYER_XP_UPDATE", "player")
suite.check("no chime while it is off", Chimes() == 1, Chimes())
run("xpbar chime on")
suite.check("the chime is on again", Bar.ChimeOn())

--------------------------------------------------------------------------------
-- Kills
--------------------------------------------------------------------------------

local name, amount = XP.ParseKill("Dalaran Apprentice dies, you gain 300 experience.")
suite.check("a kill line gives the mob", name == "Dalaran Apprentice", name)
suite.check("and its XP", amount == 300, amount)
local _, big = XP.ParseKill("Ogre dies, you gain 1,250 experience.")
suite.check("a number with a comma reads whole", big == 1250, big)
suite.check("another line gives nothing", XP.ParseKill("You receive loot: Linen Cloth.") == nil)

-- A client in another language swaps the order.
_G.COMBATLOG_XPGAIN_FIRSTPERSON = "Ihr erhaltet %2$d Erfahrung, weil %1$s stirbt."
local swapped, swappedXP = XP.ParseKill("Ihr erhaltet 120 Erfahrung, weil Gnoll stirbt.")
suite.check("a translated line in another order", swapped == "Gnoll" and swappedXP == 120,
    tostring(swapped) .. " " .. tostring(swappedXP))
_G.COMBATLOG_XPGAIN_FIRSTPERSON = "%s dies, you gain %d experience."

for _ = 1, 3 do
    now = now + 20
    Fire("CHAT_MSG_COMBAT_XP_GAIN", "Dalaran Apprentice dies, you gain 300 experience.")
end
local summary = XP:Summary()
suite.check("kills are counted", XP.session.kills == 3, XP.session.kills)
suite.check("the mob's XP each", summary.mob and summary.mob.each == 300, summary.mob and summary.mob.each)
local left = player.max - player.xp
suite.check("kills to finish the level", summary.mob.kills == math.ceil(left / 300), summary.mob.kills)
suite.check("a streak of three", summary.streak and summary.streak.count == 3)
now = now + XP.STREAK_GAP + 1
suite.check("the streak ends after a pause", XP:Streak() == nil)

--------------------------------------------------------------------------------
-- Quests
--------------------------------------------------------------------------------

local log = {
    { questID = 11, title = "Done One", done = true, xp = 4000 },
    { questID = 12, title = "Done Two", done = true, xp = 3000 },
    { questID = 13, title = "Half Way", xp = 2000, have = 4, need = 8 },
    { isHeader = true, title = "Silverpine Forest" },
}
_G.C_QuestLog = {
    GetNumQuestLogEntries = function() return #log end,
    GetInfo = function(index) return log[index] end,
    IsComplete = function(id)
        for _, quest in ipairs(log) do if quest.questID == id then return quest.done == true end end
        return false
    end,
    GetQuestObjectives = function(id)
        for _, quest in ipairs(log) do
            if quest.questID == id and quest.need then
                return { { text = "Gnolls slain", numFulfilled = quest.have, numRequired = quest.need } }
            end
        end
        return {}
    end,
}
_G.GetQuestLogRewardXP = function(id)
    for _, quest in ipairs(log) do if quest.questID == id then return quest.xp end end
    return 0
end

Fire("QUEST_LOG_UPDATE")
summary = XP:Summary()
suite.check("finished quests add up", summary.readyXP == 7000, summary.readyXP)
suite.check("a quest under way is listed", #summary.near == 1 and summary.near[1].share == 0.5)
suite.check("not in reach yet", summary.inReach == false)
suite.check("kills after the hand-in", summary.mob.after == math.ceil((left - 7000) / 300), summary.mob.after)

log[1].xp = 20000
Fire("QUEST_LOG_UPDATE")
summary = XP:Summary()
suite.check("the level is in reach", summary.inReach == true)
Bar:Refresh()
local topRight = Bar.labels.topRight:GetText() or ""
suite.check("the bar says to hand in", topRight:find("Hand in your quests to level up", 1, true) ~= nil, topRight)

Fire("QUEST_TURNED_IN", 11, 4000)
suite.check("a hand-in counts on the session", XP.session.quests == 1 and XP.session.questXP == 4000)

--------------------------------------------------------------------------------
-- Played time and levels
--------------------------------------------------------------------------------

Fire("TIME_PLAYED_MSG", 90000, 3000)
local total, level = XP:Played()
suite.check("played time read", total == 90000 and level == 3000, tostring(total) .. " " .. tostring(level))

local guid = ns.Goals:Owner()
local record = ns.db.xpProgress[guid]
suite.check("kept by the character's GUID", type(record) == "table" and guid:find("^Player%-"), guid)
record.levels[17], record.levels[18], record.levels[19] = 4000, 5000, 6000

local cheered
local cheer = Bar.Cheer
Bar.Cheer = function(_, info) cheered = info end

now = now + 600
player.level, player.xp, player.max = 21, 200, 25200
Fire("PLAYER_XP_UPDATE", "player")
Fire("PLAYER_LEVEL_UP", 21, 0, 0, 1)
suite.check("the level's time is kept", record.levels[20] == 3600, record.levels[20])
suite.check("the cheer came", cheered and cheered.level == 21)
suite.check("the fastest level", cheered.since and cheered.since.fastest == true)
suite.check("21 is no milestone", cheered.milestone == false)
local _, onLevel = XP:Played()
suite.check("time on the new level starts at nought", onLevel == 0, onLevel)

suite.check("gains across a level count", XP.session.gained > 0)

-- A slow level after a run of fast ones says nothing; a level that beats
-- the last few but not one long ago names it.
local since = XP.FastestSince({ [10] = 500, [11] = 900, [12] = 950, [13] = 990, [14] = 800 }, 14)
suite.check("fastest since level 11", since and since.since == 11, since and since.since)
suite.check("a slow level says nothing", XP.FastestSince({ [10] = 500, [11] = 900 }, 11) == nil)

Bar.Cheer = cheer
run("xpbar cheer off")
cheered = nil
Bar.Cheer = function(_, info) cheered = info end
Fire("PLAYER_LEVEL_UP", 22)
suite.check("no cheer while it is off", cheered == nil)
run("xpbar cheer on")
Bar.Cheer = cheer

local milestone
Bar.Cheer = function(_, info) milestone = info end
Fire("PLAYER_LEVEL_UP", 30)
suite.check("30 is a milestone", milestone and milestone.milestone == true)
suite.check("30 is no cap at 60", milestone.cap == false)
Bar.Cheer = cheer

--------------------------------------------------------------------------------
-- To the cap
--------------------------------------------------------------------------------

player.level, player.xp, player.max = 58, 0, 202300
summary = XP:Summary()
suite.check("XP to the cap counts 58 and 59", summary.toCapXP == 202300 + 209800, summary.toCapXP)

player.level = 60
Bar:Refresh()
suite.check("not earning at the cap", XP.Earning() == false)
suite.check("the bar hides at the cap", not Bar.frame:IsShown())
player.level, player.xp, player.max = 22, 100, 27300
Bar:Refresh()
suite.check("back under the cap it shows", Bar.frame:IsShown())

_G.IsXPUserDisabled = function() return true end
Bar:Refresh()
suite.check("XP turned off hides it", not Bar.frame:IsShown())
_G.IsXPUserDisabled = nil

--------------------------------------------------------------------------------
-- On and off, and the game's bar
--------------------------------------------------------------------------------

run("xpbar off")
suite.check("off writes xpBar", ns.db.xpBar == false)
suite.check("off hides the bar", not Bar.frame:IsShown())
run("xpbar on")
suite.check("on shows it", ns.db.xpBar == true and Bar.frame:IsShown())

local hidden = false
local game = env.Stub({ _alpha = 1 })
game.Hide = function() hidden = true end
game.SetAlpha = function(self, alpha) self._alpha = alpha end
game.GetAlpha = function(self) return self._alpha end
_G.MainStatusTrackingBarContainer = game

run("xpbar game hide")
suite.check("game hide writes the setting", ns.db.xpBarHideGame == true)
suite.check("the game's bar is see-through", game._alpha == 0, game._alpha)
suite.check("it is never hidden", hidden == false)
run("xpbar game show")
suite.check("game show puts it back", game._alpha == 1 and ns.db.xpBarHideGame == false, game._alpha)
_G.MainStatusTrackingBarContainer = nil

--------------------------------------------------------------------------------
-- A /reload goes on with the session
--------------------------------------------------------------------------------

local gained = XP.session.gained
Fire("PLAYER_LOGOUT")
suite.check("the session is kept at logout", record.session and record.session.gained == gained)
suite.check("the pace is banked", (record.paceXP or 0) >= gained)

clock = clock + 30
XP.started, XP.session = nil, nil
Fire("PLAYER_ENTERING_WORLD")
suite.check("a reload goes on with it", XP.session and XP.session.gained == gained, XP.session and XP.session.gained)

Fire("PLAYER_LOGOUT")
clock = clock + XP.RESUME + 60
XP.started, XP.session = nil, nil
Fire("PLAYER_ENTERING_WORLD")
suite.check("a long break starts a new session", XP.session.gained == 0, XP.session.gained)
suite.check("played time comes back without asking the game", XP:Played() ~= nil)

--------------------------------------------------------------------------------
-- Spells at the trainer, from Butler or Equipment
--------------------------------------------------------------------------------

suite.check("no sister, no training", Bar.Training() == nil)

local plan = { ready = { {}, {}, {} }, cost = 12000, unknown = 0 }
_G.BlackthornesEquipment = { ClassTraining = {
    IsOn = function() return true end,
    Plan = function() return plan end,
} }
local training = Bar.Training()
suite.check("Equipment's plan is read", training and training.count == 3 and training.cost == 12000)

local shown = { level = 23 }
Bar:Cheer(shown)
suite.check("the cheer gets the training row", shown.training and shown.training.count == 3)
local rows = Bar.CheerLines(shown)
local found
for _, row in ipairs(rows) do
    if row[1] == "New spells at your trainer" then found = row[2] end
end
suite.check("the row names count and cost", found and found:find("3 for", 1, true) and found:find("1g", 1, true), found)
Bar:HideCheer()

plan.unknown = 1
suite.check("a cost with unpriced spells is left out", Bar.Training().cost == 0)
plan.ready = {}
suite.check("nothing to train, no row", Bar.Training() == nil)

_G.BlackthornesEquipment.ClassTraining.IsOn = function() return false end
plan.ready = { {} }
suite.check("class training turned off there, no row", Bar.Training() == nil)

_G.BlackthornesEquipment = { ClassTraining = { Plan = function() error("broken") end } }
suite.check("a sister that raises gives nothing", Bar.Training() == nil)
_G.BlackthornesEquipment = nil

--------------------------------------------------------------------------------
-- Words
--------------------------------------------------------------------------------

suite.check("hours and minutes", XP.Duration(49800) == "13h 50m", XP.Duration(49800))
suite.check("days", XP.Duration(86400 + 3600 + 60) == "1d 1h 1m", XP.Duration(90060))
suite.check("under a minute", XP.Duration(20) == "under a minute")
suite.check("commas", XP.Comma(1234567) == "1,234,567", XP.Comma(1234567))

_G.time = realTime
suite.done()
