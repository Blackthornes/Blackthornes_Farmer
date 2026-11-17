-- Blackthornes Farmer -- Logic/SessionTimer.lua
-- The session timer: a clock for one run, with Start, Pause and Stop.
--
-- The owner said build it (2026-11-15, from a mockup), optional in Settings:
-- "Session Timer:" on the Kills page (`sessionTimer`, off unless ticked) and
-- "Pause When Away:" under it (`sessionTimerAutoPause`, on unless unticked).
-- Never rename either. Off, nothing here runs and the Kills & Loot panel is
-- as it always was.
--
-- The clock has three states: ready (nothing timed yet), timing and paused.
-- Paused time is left out of Per hour, but loot taken while paused still
-- counts. With Pause When Away on, a flight, a loading screen or going away
-- pauses it by itself, and coming back resumes it, but only a pause it made
-- by itself: a pause you pressed waits for you.
--
-- Stop opens the Your Run card (UI/Recap.lua) with "Time paused:", then the
-- clock goes back to ready. The panel's counts stay.
--
-- With the panel kept between sessions (`keepPanel`), Logic/Session.lua
-- carries the clock through a /reload or relog (`saved.timer`).

local _, ns = ...
local L = ns.L

local SessionTimer = ns.NewModule("SessionTimer")

SessionTimer.TICK = 1          -- seconds between clock redraws while timing
SessionTimer.TAXI_LOOK = 0.5   -- seconds after losing control to look for a flight

-- The note under a pause it made by itself, by reason. A pause you pressed
-- and a loading screen show none.
SessionTimer.NOTES = {
    fly = "Paused while you fly.",
    away = "Paused while you're away.",
}

SessionTimer.state = "ready"
SessionTimer.timed = 0         -- seconds timed before `started`
SessionTimer.paused = 0        -- seconds paused before `pausedAt`

local function Now()
    if type(GetTime) ~= "function" then return 0 end
    local ok, now = pcall(GetTime)
    return ok and type(now) == "number" and now or 0
end

local function Number(value)
    value = tonumber(value)
    if not value or value ~= value or value < 0 or value == math.huge then return nil end
    return value
end

--------------------------------------------------------------------------------
-- Settings
--------------------------------------------------------------------------------

--- Whether the timer is on (off unless ticked).
function SessionTimer.On()
    return ns.db ~= nil and ns.db.sessionTimer == true
end

--- Whether it pauses by itself on flights, loading screens and away (on
--- unless unticked).
function SessionTimer.AutoOn()
    return ns.db ~= nil and ns.db.sessionTimerAutoPause ~= false
end

function SessionTimer:SetOn(on)
    if not ns.db then return end
    ns.db.sessionTimer = on and true or nil
    if not on then self:Reset() end
    self:Changed()
end

function SessionTimer:SetAutoPause(on)
    if not ns.db then return end
    ns.db.sessionTimerAutoPause = on and true or false
    if not on and self.state == "paused" and self.auto then
        self:Resume()
    end
    self:Changed()
end

--------------------------------------------------------------------------------
-- The clock
--------------------------------------------------------------------------------

--- Seconds timed so far, paused time left out.
function SessionTimer:Seconds()
    local seconds = self.timed or 0
    if self.state == "timing" and self.started then
        seconds = seconds + math.max(0, Now() - self.started)
    end
    return seconds
end

--- Seconds spent paused so far.
function SessionTimer:PausedSeconds()
    local seconds = self.paused or 0
    if self.state == "paused" and self.pausedAt then
        seconds = seconds + math.max(0, Now() - self.pausedAt)
    end
    return seconds
end

--- The panel's gathered value and kills now.
local function Haul()
    local copper = ns.Value and ns.Value.Session and ns.Value:Session() or 0
    local kills = ns.Tracker and ns.Tracker.SessionKills and ns.Tracker:SessionKills() or 0
    return tonumber(copper) or 0, tonumber(kills) or 0
end

--- What this run gathered: the panel's value and kills less what it had at
--- Start, never below nothing (a Clear panel mid-run starts it at zero).
function SessionTimer:Gained()
    local copper, kills = Haul()
    return math.max(0, copper - (self.startCopper or 0)), math.max(0, kills - (self.startKills or 0))
end

--- Copper an hour for this run, or nil until `after` seconds are timed.
function SessionTimer:PerHour(after)
    if self.state == "ready" then return nil end
    local seconds = self:Seconds()
    if seconds <= 0 or seconds < (after or 0) then return nil end
    local copper = self:Gained()
    return copper / seconds * 3600
end

--- The note under a pause, or nil.
function SessionTimer:Note()
    if self.state ~= "paused" then return nil end
    if self.reason == "fly" then return L["Paused while you fly."] end
    if self.reason == "away" then return L["Paused while you're away."] end
    return nil
end

function SessionTimer:Start()
    if not self.On() then return false end
    if self.state == "paused" then return self:Resume() end
    if self.state == "timing" then return false end
    self.state = "timing"
    self.timed, self.paused = 0, 0
    self.started, self.pausedAt = Now(), nil
    self.reason, self.auto = nil, nil
    self.startCopper, self.startKills = Haul()
    self:Changed()
    return true
end

function SessionTimer:Pause(reason, auto)
    if self.state ~= "timing" then return false end
    self.timed = self:Seconds()
    self.started = nil
    self.state = "paused"
    self.pausedAt = Now()
    self.reason = reason
    self.auto = auto and true or nil
    self:Changed()
    return true
end

function SessionTimer:Resume()
    if self.state ~= "paused" then return false end
    self.paused = self:PausedSeconds()
    self.pausedAt = nil
    self.state = "timing"
    self.started = Now()
    self.reason, self.auto = nil, nil
    self:Changed()
    return true
end

--- Back to ready, nothing kept.
function SessionTimer:Reset()
    self.state = "ready"
    self.timed, self.paused = 0, 0
    self.started, self.pausedAt = nil, nil
    self.reason, self.auto = nil, nil
    self.startCopper, self.startKills = nil, nil
end

--- How the run went, for the Your Run card.
function SessionTimer:Summary()
    local copper, kills = self:Gained()
    local seconds = self:Seconds()
    local summary = { kills = kills, copper = copper, seconds = seconds,
        paused = self:PausedSeconds() }
    summary.rate = seconds > 0 and copper / seconds * 3600 or 0
    local usual = ns.Stats and ns.Stats.Usual and ns.Stats:Usual()
    if type(usual) == "number" and usual > 0 and seconds > 0 then
        summary.usual = usual
        summary.change = math.floor((summary.rate / usual - 1) * 100 + 0.5)
    end
    return summary
end

--- End the run: show how it went, then go back to ready.
function SessionTimer:Stop()
    if self.state == "ready" then return false end
    local summary = self:Summary()
    self:Reset()
    local RecapUI = ns.RecapUI
    if RecapUI and RecapUI.Show then pcall(RecapUI.Show, RecapUI, summary, L["YOUR RUN"]) end
    self:Changed()
    return true, summary
end

--- Clear panel empties the counts, so the run's start points go to zero.
function SessionTimer:Cleared()
    if self.state == "ready" then return end
    self.startCopper, self.startKills = 0, 0
end

--------------------------------------------------------------------------------
-- Kept through a /reload (Logic/Session.lua)
--------------------------------------------------------------------------------

function SessionTimer:Snapshot()
    if self.state == "ready" then return nil end
    return { state = self.state, timed = self:Seconds(), paused = self:PausedSeconds(),
        reason = self.reason, auto = self.auto, startCopper = self.startCopper,
        startKills = self.startKills }
end

function SessionTimer:Restore(saved)
    if type(saved) ~= "table" or not self.On() then return false end
    if saved.state ~= "timing" and saved.state ~= "paused" then return false end
    self.state = saved.state
    self.timed = Number(saved.timed) or 0
    self.paused = Number(saved.paused) or 0
    self.startCopper = Number(saved.startCopper) or 0
    self.startKills = Number(saved.startKills) or 0
    if self.state == "timing" then
        self.started, self.pausedAt = Now(), nil
        self.reason, self.auto = nil, nil
    else
        self.started, self.pausedAt = nil, Now()
        self.reason = self.NOTES[saved.reason or ""] and saved.reason or nil
        self.auto = saved.auto == true or nil
    end
    self:Changed()
    return true
end

--------------------------------------------------------------------------------
-- Pause When Away
--------------------------------------------------------------------------------

--- Asks the client a yes or no question: true, false, or nil for "don't
--- know". In PvP the client can hand back a secret answer, and comparing
--- one raises, so the answer is only looked at inside the pcall and a
--- secret one is "don't know".
local function Ask(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, answer = pcall(function(...)
        local value = fn(...)
        local isSecret = _G.issecretvalue
        if type(isSecret) == "function" and isSecret(value) then return nil end
        if value == true then return true end
        if value == false or value == nil then return false end
        return nil
    end, ...)
    if ok then return answer end
    return nil
end
SessionTimer.Ask = Ask

--- Pauses for `reason` by itself, only while timing.
function SessionTimer:AutoPause(reason)
    if not (self.On() and self.AutoOn()) then return false end
    if self.state == "timing" then return self:Pause(reason, true) end
    -- Already paused by itself: a new reason replaces the old (a flight
    -- into a loading screen keeps saying where you were).
    if self.state == "paused" and self.auto and reason and reason ~= "loading" then
        self.reason = reason
        self:Changed()
    end
    return false
end

--- Resumes a pause it made by itself, once nothing still holds it.
function SessionTimer:AutoResume()
    if self.state ~= "paused" or not self.auto then return false end
    if self.loading then return false end
    if Ask(UnitOnTaxi, "player") then
        if self.reason ~= "fly" then self.reason = "fly"; self:Changed() end
        return false
    end
    if Ask(UnitIsAFK, "player") then
        if self.reason ~= "away" then self.reason = "away"; self:Changed() end
        return false
    end
    return self:Resume()
end

function SessionTimer:OnEvent(event)
    if event == "LOADING_SCREEN_ENABLED" then
        self.loading = true
        self:AutoPause("loading")
    elseif event == "LOADING_SCREEN_DISABLED" then
        self.loading = nil
        self:AutoResume()
    elseif event == "PLAYER_ENTERING_WORLD" then
        self.loading = nil
        self:AutoResume()
    elseif event == "PLAYER_CONTROL_LOST" then
        local look = function()
            if Ask(UnitOnTaxi, "player") then self:AutoPause("fly") end
        end
        if C_Timer and type(C_Timer.After) == "function" then
            pcall(C_Timer.After, self.TAXI_LOOK, look)
        else
            look()
        end
    elseif event == "PLAYER_CONTROL_GAINED" then
        if self.reason == "fly" then
            local look = function()
                if Ask(UnitOnTaxi, "player") == false then self:AutoResume() end
            end
            if C_Timer and type(C_Timer.After) == "function" then
                pcall(C_Timer.After, self.TAXI_LOOK, look)
            else
                look()
            end
        end
    elseif event == "PLAYER_FLAGS_CHANGED" then
        local away = Ask(UnitIsAFK, "player")
        if away then
            self:AutoPause("away")
        elseif away == false and self.reason == "away" then
            self:AutoResume()
        end
    end
end

--------------------------------------------------------------------------------
-- Redraws
--------------------------------------------------------------------------------

--- Something moved: redraw the strip and the panel, and run the clock's
--- ticker only while timing and shown.
function SessionTimer:Changed()
    local TrackerUI = ns.TrackerUI
    if TrackerUI and TrackerUI.frame and TrackerUI.Refresh then pcall(TrackerUI.Refresh, TrackerUI) end
    self:Watch()
end

function SessionTimer:Watch()
    local want = self.On() and self.state == "timing"
    if want and not self.ticker and C_Timer and type(C_Timer.NewTicker) == "function" then
        local ok, ticker = pcall(C_Timer.NewTicker, self.TICK, function() SessionTimer:Tick() end)
        if ok then self.ticker = ticker end
    elseif not want and self.ticker then
        pcall(self.ticker.Cancel, self.ticker)
        self.ticker = nil
    end
end

--- Once a second while timing: only the clock's words move, and only while
--- the panel shows.
function SessionTimer:Tick()
    local UI = ns.SessionTimerUI
    if UI and UI.Tick then UI:Tick() end
end

function SessionTimer:OnEnable()
    for _, event in ipairs({ "LOADING_SCREEN_ENABLED", "LOADING_SCREEN_DISABLED",
        "PLAYER_ENTERING_WORLD", "PLAYER_CONTROL_LOST", "PLAYER_CONTROL_GAINED",
        "PLAYER_FLAGS_CHANGED" }) do
        ns.RegisterEvent(self, event, function(_, name) SessionTimer:OnEvent(name or event) end)
    end
end

--------------------------------------------------------------------------------
-- /farm timer [on|off|start|pause|stop]
--------------------------------------------------------------------------------


local function Say(word)
    ns.Print(L["Session Timer:"] .. " " .. word)
end

ns.RegisterCommand("timer", L["the session timer on Kills & Loot (on, off, start, pause, stop)"], function(rest)
    local argument = ns.Util.Trim(rest or ""):lower()
    if argument == "on" or argument == "off" or argument == "" then
        local on = argument == "on" or (argument == "" and not SessionTimer.On())
        SessionTimer:SetOn(on)
        Say(on and L["On"] or L["Off"])
        if ns.SettingsUI and ns.SettingsUI.Refresh then pcall(ns.SettingsUI.Refresh, ns.SettingsUI) end
        return
    end
    if not SessionTimer.On() then
        Say(L["Off"])
        return
    end
    if argument == "start" then
        SessionTimer:Start()
    elseif argument == "pause" then
        SessionTimer:Pause()
    elseif argument == "stop" then
        SessionTimer:Stop()
        return
    end
    local tag = { ready = L["Ready"], timing = L["Timing"], paused = L["Paused"] }
    Say(tag[SessionTimer.state] or L["Ready"])
end)
