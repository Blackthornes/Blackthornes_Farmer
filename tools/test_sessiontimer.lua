-- The session timer on Kills & Loot (2026-11-15, off unless ticked).
--
-- What matters: with the box unticked nothing changes and the strip takes no
-- room; Start, Pause, Resume and Stop move the clock as the buttons say;
-- paused time stays out of the clock and the hour, while loot taken paused
-- still counts; it pauses by itself on a flight, a loading screen or away,
-- and only those pauses resume by themselves; a /reload keeps the clock; and
-- /farm timer and the Settings rows work.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("sessiontimer")

local clock = 1000
local copper, kills = 0, 0
local onTaxi, afk = false, false

local function Login(saved)
    local ns = env.Load({ ui = true })
    _G.GetTime = function() return clock end
    _G.UnitOnTaxi = function() return onTaxi end
    _G.UnitIsAFK = function() return afk end
    _G.BlackthornesFarmerDB = saved or {}
    ns.LoadSavedVariables()
    for _, module in ipairs(ns.moduleOrder) do
        if module.OnEnable then module:OnEnable() end
    end
    ns.Value.Session = function() return copper end
    ns.Tracker.SessionKills = function() return kills end
    return ns
end

local ns = Login()
local T, UI = ns.SessionTimer, ns.SessionTimerUI

-- Off by default.
suite.check("off unless ticked", T.On() == false)
suite.check("Pause When Away on unless unticked", T.AutoOn() == true)
suite.check("strip takes no room while off", UI:Height() == 0)
suite.check("strip needs no width while off", UI.Needs() == 0)
suite.check("Start does nothing while off", T:Start() == false and T.state == "ready")

-- The words and looks.
suite.check("clock always shows the hour", UI.Clock(0) == "0:00:00" and UI.Clock(2535) == "0:42:15")
suite.check("clock handles junk", UI.Clock(nil) == "0:00:00" and UI.Clock(-5) == "0:00:00")
local ready, timing, paused = UI.Looks("ready"), UI.Looks("timing"), UI.Looks("paused")
suite.check("ready: Start gold, the rest dim",
    ready.start == "gold" and ready.pause == "dim" and ready.stop == "dim")
suite.check("timing: Pause gold, Start dim, Stop plain",
    timing.start == "dim" and timing.pause == "gold" and timing.stop == "plain")
suite.check("paused: Resume gold, Pause dim, Stop plain",
    paused.start == "gold" and paused.pause == "dim" and paused.stop == "plain")
suite.check("Start reads Resume while paused",
    UI.StartWord("paused") == "Resume" and UI.StartWord("ready") == "Start")

-- Turned on.
T:SetOn(true)
suite.check("ticked saves sessionTimer", ns.db.sessionTimer == true and T.On())
suite.check("strip has room once on", UI:Height() > 0 and UI.Needs() > 0)

copper, kills = 500, 2
suite.check("Start starts", T:Start() == true and T.state == "timing")
suite.check("a second Start does nothing", T:Start() == false)
clock = clock + 600
copper, kills = 2500, 6
suite.check("clock counts while timing", T:Seconds() == 600)
local gained, killed = T:Gained()
suite.check("only loot since Start counts", gained == 2000 and killed == 4)
suite.check("per hour from the run", math.abs(T:PerHour() - 12000) < 0.01)

suite.check("Pause pauses", T:Pause() == true and T.state == "paused")
suite.check("a hand pause shows no note", T:Note() == nil)
local tall = UI:Height()
clock = clock + 300
copper = 4500 -- looted while paused
suite.check("paused time is left out of the clock", T:Seconds() == 600)
suite.check("paused time is counted on its own", T:PausedSeconds() == 300)
suite.check("loot taken paused still counts", (T:Gained()) == 4000)
suite.check("per hour leaves the pause out", math.abs(T:PerHour() - 24000) < 0.01)

suite.check("Start while paused resumes", T:Start() == true and T.state == "timing")
clock = clock + 60
suite.check("clock goes on after resume", T:Seconds() == 660 and T:PausedSeconds() == 300)

-- Pausing by itself.
afk = true
T:OnEvent("PLAYER_FLAGS_CHANGED")
suite.check("away pauses by itself", T.state == "paused" and T.auto == true)
suite.check("the note says you're away", T:Note() == "Paused while you're away.")
suite.check("the note makes the strip taller", UI:Height() > tall)
afk = false
T:OnEvent("PLAYER_FLAGS_CHANGED")
suite.check("back from away resumes", T.state == "timing")

onTaxi = true
T:OnEvent("PLAYER_CONTROL_LOST")
suite.check("a flight pauses by itself", T.state == "paused" and T.reason == "fly")
suite.check("the note says you fly", T:Note() == "Paused while you fly.")
T:OnEvent("LOADING_SCREEN_ENABLED")
suite.check("a loading screen keeps the flight note", T.reason == "fly")
T:OnEvent("LOADING_SCREEN_DISABLED")
suite.check("still flying, still paused", T.state == "paused")
onTaxi = false
T:OnEvent("PLAYER_CONTROL_GAINED")
suite.check("landing resumes", T.state == "timing")

T:OnEvent("LOADING_SCREEN_ENABLED")
suite.check("a loading screen pauses", T.state == "paused")
T:OnEvent("LOADING_SCREEN_DISABLED")
suite.check("and resumes after", T.state == "timing")

T:Pause()
afk = false
T:OnEvent("PLAYER_ENTERING_WORLD")
suite.check("a hand pause never resumes by itself", T.state == "paused")
T:Resume()

T:SetAutoPause(false)
suite.check("unticked saves false", ns.db.sessionTimerAutoPause == false)
afk = true
T:OnEvent("PLAYER_FLAGS_CHANGED")
suite.check("no pause by itself while unticked", T.state == "timing")
afk = false
T:SetAutoPause(true)

-- Kept through a /reload.
T:Pause()
clock = clock + 30
local snap = T:Snapshot()
suite.check("a snapshot keeps the clock", snap and snap.state == "paused" and snap.timed == T:Seconds())
local seconds = T:Seconds()
T:Reset()
suite.check("restore brings it back", T:Restore(snap) == true and T.state == "paused"
    and T:Seconds() == seconds)
suite.check("restore refuses junk", T:Restore({ state = "nope" }) == false)
suite.check("ready keeps nothing", (function() local s = T.state; T:Reset(); local r = T:Snapshot(); T:Restore(snap); return r == nil end)())

-- Clear panel mid-run.
T:Resume()
T:Cleared()
copper, kills = 300, 1
suite.check("Clear panel starts the run's loot at zero", (T:Gained()) == 300)

-- Stop.
local shown
ns.RecapUI = ns.RecapUI or {}
local oldShow = ns.RecapUI.Show
ns.RecapUI.Show = function(_, summary, title) shown = { summary = summary, title = title } end
local stopped, summary = T:Stop()
suite.check("Stop ends the run", stopped == true and T.state == "ready")
suite.check("Stop shows Your Run with the time paused",
    shown and shown.title == "YOUR RUN" and shown.summary.paused > 0)
suite.check("Stop on ready does nothing", T:Stop() == false)
ns.RecapUI.Show = oldShow

-- Turned off mid-run goes back to ready.
T:Start()
T:SetOn(false)
suite.check("off resets the clock", T.state == "ready" and ns.db.sessionTimer == nil)

-- /farm timer.
local command = ns.commands.timer
suite.check("/farm timer is a command", command ~= nil)
command.fn("on")
suite.check("/farm timer on", T.On())
command.fn("start")
suite.check("/farm timer start", T.state == "timing")
command.fn("pause")
suite.check("/farm timer pause", T.state == "paused")
command.fn("stop")
suite.check("/farm timer stop", T.state == "ready")
command.fn("off")
suite.check("/farm timer off", not T.On())

-- Settings.
ns.SettingsUI:Show()
local controls = ns.SettingsUI.controls
suite.check("Settings has the Session Timer box, unticked",
    controls.sessionTimer ~= nil and not controls.sessionTimer:GetChecked())
suite.check("Settings has Pause When Away, ticked",
    controls.sessionTimerAutoPause ~= nil and controls.sessionTimerAutoPause:GetChecked())

suite.done()
