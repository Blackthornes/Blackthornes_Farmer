-- Blackthornes Farmer -- Logic/XP.lua
-- What the XP bar knows (the owner asked 2026-10-13 for an XP bar in the
-- house style that does more than show a number): how far into the level
-- you are, what this session has earned and how fast, what finished quests
-- in the log are worth, how many more of the mob you are fighting would
-- finish the level, rested XP, and how long the level took.
--
-- Everything is read from the client inside a pcall (instances hand out
-- secret values), and nothing is read on a timer: XP, quest log and kill
-- events mark what moved, and the bar asks again only when it draws.
--
-- The level cap is the client's own (GetMaxLevelForPlayerExpansion, then
-- GetMaxPlayerLevel, then MAX_PLAYER_LEVEL), else 60: Forever's beta stops at
-- 30, and the owner said (2026-10-13) leveling goes to 60 at release.
--
-- Saved, per character by GUID, in the account save as
-- `xpProgress[guid]` (never rename it): played time and time on this level
-- as last read from the game, how long each level took, the XP and play time
-- of past sessions (for "your usual pace"), and the session running at the
-- last logout, picked up again after a /reload.

local _, ns = ...
local L = ns.L

local XP = ns.NewModule("XP")

-- Classic's XP from each level to the next. The client says only the level
-- you are on (UnitXPMax), so the levels after it are estimated from these,
-- scaled by how far Forever's number for this level is from Classic's.
XP.TABLE = {
    400, 900, 1400, 2100, 2800, 3600, 4500, 5400, 6500, 7600,
    8800, 10100, 11400, 12900, 14400, 16000, 17700, 19400, 21300, 23200,
    25200, 27300, 29400, 31700, 34000, 36400, 38900, 41400, 44300, 47400,
    50800, 54500, 58600, 62800, 67100, 71600, 76100, 80800, 85700, 90700,
    95800, 101000, 106300, 111800, 117500, 123200, 129100, 135100, 141200, 147500,
    153900, 160400, 167100, 173900, 180800, 187900, 195000, 202300, 209800,
}

-- The cap when the client will not say.
XP.CAP = 60
-- Kills no more than this many seconds apart make a streak, as the kills
-- panel's do.
XP.STREAK_GAP = 60
-- Seconds of a session before its pace is worth showing.
XP.PACE_MIN = 120
-- Seconds of past sessions before "your usual pace" is believed.
XP.USUAL_MIN = 1800
-- A session this much faster than usual gets the gold pace.
XP.AHEAD = 1.15
-- A session picked up again after a /reload, if it ended no longer ago.
XP.RESUME = 15 * 60
-- Seconds after a burst of quest log events before the log is read.
XP.SETTLE = 0.5
-- Quests under way shown on the hover card.
XP.NEAR = 3

XP.session = nil
XP.mobs = {}
XP.version = 0

--------------------------------------------------------------------------------
-- Reading the client
--------------------------------------------------------------------------------

--- A plain number from a client value, or nil (a secret value raises when
--- touched, so the copy is made in a pcall).
function XP.Number(value)
    if type(value) ~= "number" then return nil end
    local ok, copy = pcall(function() return value + 0 end)
    if not ok or type(copy) ~= "number" or copy ~= copy then return nil end
    return copy
end

local function Call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, value = pcall(fn, ...)
    if not ok then return nil end
    return XP.Number(value)
end

local function Now()
    return Call(_G.GetTime) or 0
end

local function Clock()
    return Call(_G.time) or 0
end

--- The level cap: the client's, else 60.
function XP.MaxLevel()
    for _, fn in ipairs({ _G.GetMaxLevelForPlayerExpansion, _G.GetMaxPlayerLevel }) do
        local cap = Call(fn)
        if cap and cap >= 10 and cap <= 100 then return math.floor(cap) end
    end
    local cap = XP.Number(_G.MAX_PLAYER_LEVEL)
    if cap and cap >= 10 and cap <= 100 then return math.floor(cap) end
    return XP.CAP
end

--- The level, XP into it, XP the level needs and rested XP; nil while the
--- client will not say.
function XP.Read()
    local level = Call(_G.UnitLevel, "player")
    local current = Call(_G.UnitXP, "player")
    local most = Call(_G.UnitXPMax, "player")
    if not (level and current and most and most > 0) then return nil end
    local rested = Call(_G.GetXPExhaustion) or 0
    return { level = level, xp = current, max = most, rested = math.max(0, rested) }
end

--- Whether there is any XP to earn: under the cap, and XP not turned off.
function XP.Earning(state)
    state = state or XP.Read()
    if not state then return false end
    if type(_G.IsXPUserDisabled) == "function" then
        local ok, off = pcall(_G.IsXPUserDisabled)
        if ok and off == true then return false end
    end
    return state.level < XP.MaxLevel()
end

--- XP from `level` to the next: Classic's, scaled to this client by the
--- level you are on.
function XP.Needed(level, state)
    local classic = XP.TABLE[level]
    if not classic then return nil end
    state = state or XP.Read()
    local scale = 1
    if state and XP.TABLE[state.level] then scale = state.max / XP.TABLE[state.level] end
    return math.floor(classic * scale + 0.5)
end

--------------------------------------------------------------------------------
-- What is kept, per character
--------------------------------------------------------------------------------

function XP:Owner()
    return ns.Goals and ns.Goals:Owner() or nil
end

--- This character's saved record, made when first needed; nil while the
--- client will not say who is playing.
function XP:Record()
    local guid = self:Owner()
    if not (guid and ns.db) then return nil end
    if type(ns.db.xpProgress) ~= "table" then ns.db.xpProgress = {} end
    local record = ns.db.xpProgress[guid]
    if type(record) ~= "table" then
        record = {}
        ns.db.xpProgress[guid] = record
    end
    if type(record.levels) ~= "table" then record.levels = {} end
    return record
end

--------------------------------------------------------------------------------
-- Played time
--------------------------------------------------------------------------------

--- Played time and time on this level, in seconds, as of now; nil until the
--- game has said once (TIME_PLAYED_MSG).
function XP:Played()
    local base = self.played
    if not base then return nil end
    local since = math.max(0, Now() - base.at)
    return base.total + since, base.level + since
end

--- The game says how long this character has played.
function XP:TimePlayed(total, level)
    total, level = XP.Number(total), XP.Number(level)
    if not (total and level) then return end
    local state = XP.Read()
    self.played = { total = total, level = level, at = Now(), of = state and state.level }
    self:Changed()
end

--- Kept at logout, and read back at login, so the game need not be asked
--- (asking prints the played time in chat).
function XP:SavePlayed()
    local record = self:Record()
    local total, level = self:Played()
    if not (record and total) then return end
    record.played, record.levelPlayed = math.floor(total), math.floor(level)
    record.playedLevel = self.played.of
end

function XP:LoadPlayed()
    local record = self:Record()
    local state = XP.Read()
    if not (record and state) then return false end
    local total, level = XP.Number(record.played), XP.Number(record.levelPlayed)
    if total and level and record.playedLevel == state.level then
        self.played = { total = total, level = level, at = Now(), of = state.level }
        return true
    end
    return false
end

--------------------------------------------------------------------------------
-- The session
--------------------------------------------------------------------------------

local function NewSession(state)
    return {
        started = Now(),
        level = state and state.level, xp = state and state.xp,
        gained = 0, kills = 0, killXP = 0, quests = 0, questXP = 0,
        banked = 0, bankedTime = 0,
    }
end

--- Seconds this session has run.
function XP:Seconds()
    local session = self.session
    if not session then return 0 end
    return math.max(0, Now() - session.started)
end

--- XP an hour this session, once it has run PACE_MIN seconds; else nil.
function XP:Rate()
    local seconds = self:Seconds()
    local session = self.session
    if not session or seconds < XP.PACE_MIN or session.gained <= 0 then return nil end
    return session.gained / seconds * 3600
end

--- XP an hour over past sessions, nil until there are USUAL_MIN seconds.
function XP:UsualRate()
    local record = self:Record()
    if not record then return nil end
    local gained, seconds = XP.Number(record.paceXP) or 0, XP.Number(record.paceSeconds) or 0
    if seconds < XP.USUAL_MIN or gained <= 0 then return nil end
    return gained / seconds * 3600
end

--- How much faster this session runs than usual, as a fraction (0.22 for
--- 22%), when it is AHEAD or more; else nil.
function XP:Ahead()
    local rate, usual = self:Rate(), self:UsualRate()
    if not (rate and usual and self:Seconds() >= 600) then return nil end
    if rate < usual * XP.AHEAD then return nil end
    return rate / usual - 1
end

--- Put this session's XP and time into the record's pace, the part not put
--- in before.
function XP:Bank()
    local record, session = self:Record(), self.session
    if not (record and session) then return end
    local seconds = self:Seconds()
    record.paceXP = (XP.Number(record.paceXP) or 0) + math.max(0, session.gained - session.banked)
    record.paceSeconds = (XP.Number(record.paceSeconds) or 0) + math.max(0, seconds - session.bankedTime)
    session.banked, session.bankedTime = session.gained, seconds
end

--- Kept at logout (a /reload too), so a /reload goes on with the session.
function XP:SaveSession()
    local record, session = self:Record(), self.session
    if not (record and session) then return end
    self:Bank()
    record.session = {
        at = Clock(), seconds = self:Seconds(), level = session.level, xp = session.xp,
        gained = session.gained, kills = session.kills, killXP = session.killXP,
        quests = session.quests, questXP = session.questXP,
        banked = session.banked, bankedTime = session.bankedTime,
    }
end

--- The session kept at the last logout, when that was a moment ago.
function XP:ResumeSession(state)
    local record = self:Record()
    local saved = record and record.session
    if type(saved) ~= "table" then return nil end
    local at, seconds = XP.Number(saved.at), XP.Number(saved.seconds)
    if not (at and seconds) or Clock() - at > XP.RESUME or Clock() < at then return nil end

    local session = NewSession(state)
    session.started = Now() - seconds
    for _, key in ipairs({ "level", "xp", "gained", "kills", "killXP", "quests", "questXP", "banked", "bankedTime" }) do
        session[key] = XP.Number(saved[key]) or session[key]
    end
    return session
end

--------------------------------------------------------------------------------
-- XP coming in
--------------------------------------------------------------------------------

--- A Lua pattern for one of the game's chat lines: each %s and %d (and
--- their numbered forms) becomes a capture; the order they come in is
--- returned too, since a translation can swap them.
function XP.Pattern(format)
    if type(format) ~= "string" or format == "" then return nil end
    local out, order, index = {}, {}, 1
    local position = 0
    while index <= #format do
        local char = format:sub(index, index)
        if char == "%" then
            local number, kind, after = format:match("^%%(%d*)%$?([sd])()", index)
            if kind then
                position = position + 1
                order[#order + 1] = tonumber(number) or position
                out[#out + 1] = kind == "d" and "([%d%.,]+)" or "(.-)"
                index = after
            elseif format:sub(index + 1, index + 1) == "%" then
                out[#out + 1] = "%%"
                index = index + 2
            else
                out[#out + 1] = "%%"
                index = index + 1
            end
        else
            out[#out + 1] = char:find("[%^%$%(%)%.%[%]%*%+%-%?]") and ("%" .. char) or char
            index = index + 1
        end
    end
    return "^" .. table.concat(out), order
end

local KILL_ENGLISH = "%s dies, you gain %d experience."

--- The mob and XP from a kill's chat line, or nil.
function XP.ParseKill(message)
    local formats = { _G.COMBATLOG_XPGAIN_FIRSTPERSON, KILL_ENGLISH }
    for _, format in ipairs(formats) do
        local pattern, order = XP.Pattern(format)
        if pattern then
            local ok, a, b = pcall(string.match, message, pattern)
            if ok and a and b then
                local values = {}
                values[order[1] or 1], values[order[2] or 2] = a, b
                local name, amount = values[1], values[2]
                amount = tonumber((tostring(amount):gsub("[^%d]", "")))
                if type(name) == "string" and name ~= "" and amount and amount > 0 then
                    return name, amount
                end
            end
        end
    end
    return nil
end

--- Tell the bar something moved.
function XP:Changed(kind, amount, extra)
    self.version = self.version + 1
    local ui = ns.XPBarUI
    if ui and ui.Changed then
        local ok, err = pcall(ui.Changed, ui, kind, amount, extra)
        if not ok then ns.Debug("xp bar:", tostring(err)) end
    end
end

--- A kill's XP, from its chat line.
function XP:Killed(name, amount)
    local session = self.session
    if not session then return end
    session.kills = session.kills + 1
    session.killXP = session.killXP + amount

    local mob = self.mobs[name]
    if not mob then
        mob = { xp = 0, kills = 0 }
        self.mobs[name] = mob
    end
    mob.xp, mob.kills = mob.xp + amount, mob.kills + 1
    self.lastMob = name

    local now = Now()
    local streak = self.streak
    if streak and now - streak.at <= XP.STREAK_GAP then
        streak.count, streak.xp, streak.at = streak.count + 1, streak.xp + amount, now
    else
        self.streak = { count = 1, xp = amount, at = now }
    end

    self:Changed("kill", amount)
end

--- The kill streak running now, or nil once STREAK_GAP has passed.
function XP:Streak()
    local streak = self.streak
    if not streak or Now() - streak.at > XP.STREAK_GAP then return nil end
    return streak
end

--- A quest handed in, with the XP the game says it gave.
function XP:TurnedIn(amount)
    amount = XP.Number(amount)
    self.questsStale = true
    if not (self.session and amount and amount > 0) then return end
    self.session.quests = self.session.quests + 1
    self.session.questXP = self.session.questXP + amount
    self:Changed("quest", amount)
end

--- The game says XP moved: what was gained since the last look goes on the
--- session, and a tenth of the level crossed is passed on for the chime.
function XP:Update()
    local state = XP.Read()
    if not state then return end
    local last = self.last
    self.last = state
    if not self.session then self.session = NewSession(state) end
    if not last then
        self:Changed()
        return
    end

    local gained = 0
    if state.level == last.level then
        gained = state.xp - last.xp
    elseif state.level > last.level then
        gained = math.max(0, last.max - last.xp) + state.xp
    end
    if gained > 0 then self.session.gained = self.session.gained + gained end

    local tick
    if state.level == last.level and state.xp > last.xp then
        local before = math.floor(last.xp / last.max * 10)
        local after = math.floor(state.xp / state.max * 10)
        if after > before and after < 10 then tick = after end
    end
    self:Changed(tick and "tick" or nil, tick)
end

--- A new level: how long the last one took is kept, and the bar cheers.
function XP:LevelUp(level, talents)
    level = XP.Number(level)
    if not level then return end
    local record = self:Record()
    local _, took = self:Played()
    local info = { level = level, talents = XP.Number(talents), took = took }

    if record and took and self.played and self.played.of == level - 1 then
        record.levels[level - 1] = math.floor(took)
        info.since = XP.FastestSince(record.levels, level - 1)
    end
    if self.played then
        self.played.total = self.played.total + math.max(0, Now() - self.played.at)
        self.played.level, self.played.at, self.played.of = 0, Now(), level
    end

    info.milestone = level % 10 == 0 or level >= XP.MaxLevel()
    info.cap = level >= XP.MaxLevel()
    if info.cap and record then
        local total = self:Played()
        info.total = total
        local best, bestLevel
        for which, seconds in pairs(record.levels) do
            seconds = XP.Number(seconds)
            if seconds and which >= 10 and (not best or seconds < best) then best, bestLevel = seconds, which end
        end
        info.fastest, info.fastestLevel = best, bestLevel
    end

    self:Changed("level", level, info)
end

--- How the level just done compares: "fastest" when it beat every level
--- kept before it (with at least two kept), the level last beaten when that
--- was a while back, else nil.
function XP.FastestSince(levels, level)
    local took = XP.Number(levels[level])
    if not took then return nil end
    local earlier = 0
    for which = level - 1, 1, -1 do
        local seconds = XP.Number(levels[which])
        if seconds then
            earlier = earlier + 1
            if seconds <= took then
                if which < level - 2 then return { since = which + 1 } end
                return nil
            end
        end
    end
    if earlier >= 2 then return { fastest = true } end
    return nil
end

--------------------------------------------------------------------------------
-- The quest log
--------------------------------------------------------------------------------

local function Field(object, key)
    if type(object) ~= "table" then return nil end
    local ok, value = pcall(function() return object[key] end)
    if ok then return value end
    return nil
end

local function Text(value)
    if type(value) ~= "string" then return nil end
    local ok, copy = pcall(function() return value .. "" end)
    return ok and copy or nil
end

--- XP a quest in the log gives, or 0.
local function RewardXP(questID)
    return Call(_G.GetQuestLogRewardXP, questID) or 0
end

--- Finished quests (ready to hand in) and quests under way, with their XP.
--- Read only when the log moved since the last read.
function XP:Quests()
    if self.quests and not self.questsStale then return self.quests end
    self.questsStale = false

    local found = { ready = {}, readyXP = 0, near = {} }
    self.quests = found

    local log = _G.C_QuestLog
    local count, info = Field(log, "GetNumQuestLogEntries"), Field(log, "GetInfo")
    local complete, objectives = Field(log, "IsComplete"), Field(log, "GetQuestObjectives")
    if type(count) ~= "function" or type(info) ~= "function" then return found end

    local entries = Call(count) or 0
    for index = 1, entries do
        local ok, entry = pcall(info, index)
        local questID = ok and type(entry) == "table" and not entry.isHeader and XP.Number(entry.questID)
        if questID then
            local title = Text(entry.title) or "?"
            local xp = RewardXP(questID)
            local done = false
            if type(complete) == "function" then
                local got, value = pcall(complete, questID)
                done = got and value == true
            end
            if done then
                found.ready[#found.ready + 1] = { title = title, xp = xp }
                found.readyXP = found.readyXP + xp
            elseif xp > 0 and type(objectives) == "function" then
                local got, list = pcall(objectives, questID)
                local have, need, lines = 0, 0, {}
                for _, objective in ipairs(got and type(list) == "table" and list or {}) do
                    local fulfilled = type(objective) == "table" and XP.Number(objective.numFulfilled)
                    local required = type(objective) == "table" and XP.Number(objective.numRequired)
                    if fulfilled and required and required > 0 then
                        have, need = have + math.min(fulfilled, required), need + required
                        local text = Text(objective.text)
                        if text and fulfilled < required then lines[#lines + 1] = text end
                    end
                end
                if need > 0 and have > 0 then
                    found.near[#found.near + 1] = { title = title, xp = xp, share = have / need, lines = lines }
                end
            end
        end
    end

    table.sort(found.near, function(a, b)
        if a.share ~= b.share then return a.share > b.share end
        return a.xp > b.xp
    end)
    while #found.near > XP.NEAR do table.remove(found.near) end
    return found
end

--- The quest log moved: read it again, a moment after the burst.
function XP:QuestLogChanged()
    self.questsStale = true
    if self.questTimer then return end
    if not (C_Timer and C_Timer.After) then
        self:Changed("quests")
        return
    end
    self.questTimer = true
    C_Timer.After(XP.SETTLE, function()
        XP.questTimer = nil
        XP:Changed("quests")
    end)
end

--------------------------------------------------------------------------------
-- Working it out
--------------------------------------------------------------------------------

--- Everything the bar and its card show, worked out from what is read now.
function XP:Summary()
    local state = XP.Read()
    if not state then return nil end
    local session = self.session or NewSession(state)
    local quests = self:Quests()
    local left = math.max(0, state.max - state.xp)

    local out = {
        level = state.level, xp = state.xp, max = state.max, rested = state.rested,
        left = left, share = state.xp / state.max, cap = XP.MaxLevel(),
        session = session, rate = self:Rate(), usual = self:UsualRate(), ahead = self:Ahead(),
        ready = quests.ready, readyXP = quests.readyXP, near = quests.near,
        streak = self:Streak(),
    }
    out.inReach = left > 0 and quests.readyXP >= left

    -- Where the session started on this bar: its start when still on this
    -- level, else the bar's start.
    if session.level == state.level and session.xp then
        out.sessionFrom = math.min(state.xp, session.xp) / state.max
    else
        out.sessionFrom = 0
    end

    out.played, out.levelPlayed = self:Played()

    local pace = out.rate or out.usual
    if pace and pace > 0 then out.toLevel = left / pace * 3600 end

    local mob = self.lastMob and self.mobs[self.lastMob]
    if mob and mob.kills > 0 then
        local each = mob.xp / mob.kills
        out.mob = { name = self.lastMob, each = math.floor(each + 0.5),
            kills = math.ceil(left / each) }
        if quests.readyXP > 0 and quests.readyXP < left then
            out.mob.after = math.ceil((left - quests.readyXP) / each)
        end
        local seconds = self:Seconds()
        if session.kills >= 3 and seconds > 0 then
            local perKill = seconds / session.kills
            out.mob.seconds = (out.mob.after or out.mob.kills) * perKill
        end
    end

    -- To the cap: the rest of this level and every level after it, at the
    -- usual pace (else this session's).
    if state.level < out.cap then
        local total = left
        for level = state.level + 1, out.cap - 1 do
            total = total + (XP.Needed(level, state) or 0)
        end
        out.toCapXP = total
        local usual = out.usual or out.rate
        if usual and usual > 0 then out.toCap = total / usual * 3600 end
    end
    return out
end

--------------------------------------------------------------------------------
-- Words
--------------------------------------------------------------------------------

--- "1d 5h 12m", "13h 50m", "33m"; "under a minute" for less.
function XP.Duration(seconds)
    seconds = math.floor(tonumber(seconds) or 0)
    if seconds < 60 then return L["under a minute"] end
    local days = math.floor(seconds / 86400)
    local hours = math.floor(seconds % 86400 / 3600)
    local minutes = math.floor(seconds % 3600 / 60)
    if days > 0 then return L.Format("%dd %dh %dm", days, hours, minutes) end
    if hours > 0 then return L.Format("%dh %dm", hours, minutes) end
    return L.Format("%dm", minutes)
end

--- 14981 as "14,981".
function XP.Comma(value)
    local text = tostring(math.floor((tonumber(value) or 0) + 0.5))
    local sign, digits = text:match("^(-?)(%d+)$")
    if not digits then return text end
    local out = digits:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
    return sign .. out
end


--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

function XP:Start()
    if self.started then return end
    local state = XP.Read()
    if not state or not self:Owner() then return end
    self.started = true
    self.last = state
    self.session = self:ResumeSession(state) or NewSession(state)
    if not self:LoadPlayed() and type(_G.RequestTimePlayed) == "function" then
        -- Once for a character Farmer has not timed yet (or that levelled
        -- while it was off); the game prints the played time in chat then.
        pcall(_G.RequestTimePlayed)
    end
    self:Changed()
end

function XP:OnEnable()
    ns.RegisterEvent(self, "PLAYER_ENTERING_WORLD", function() XP:Start() end)
    ns.RegisterPlayerEvent(self, "PLAYER_XP_UPDATE", function(_, _, unit)
        if unit == nil or unit == "player" then XP:Update() end
    end)
    ns.RegisterEvent(self, "UPDATE_EXHAUSTION", function() XP:Changed() end)
    ns.RegisterEvent(self, "PLAYER_UPDATE_RESTING", function() XP:Changed() end)
    ns.RegisterEvent(self, "PLAYER_LEVEL_UP", function(_, _, level, _, _, talents)
        XP:LevelUp(level, talents)
    end)
    ns.RegisterEvent(self, "TIME_PLAYED_MSG", function(_, _, total, level) XP:TimePlayed(total, level) end)
    ns.RegisterEvent(self, "CHAT_MSG_COMBAT_XP_GAIN", function(_, _, message)
        local name, amount = XP.ParseKill(message)
        if name then XP:Killed(name, amount) end
    end)
    ns.RegisterEvent(self, "QUEST_TURNED_IN", function(_, _, _, xp) XP:TurnedIn(xp) end)
    ns.RegisterEvent(self, "QUEST_LOG_UPDATE", function() XP:QuestLogChanged() end)
    ns.RegisterEvent(self, "PLAYER_LOGOUT", function()
        XP:SavePlayed()
        XP:SaveSession()
    end)
end
