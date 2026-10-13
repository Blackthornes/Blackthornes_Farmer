-- Blackthornes Farmer -- Logic/Stats.lua
-- What the Stats tab draws (UI/Stats.lua): your farming over days and
-- sessions, kept as you play.
--
-- The owner asked (2026-10-13) for a tab that is only charts, for players
-- who like their numbers. Most of what it shows is already kept (the kill
-- tally, Rankings' worth per kill, the XP bar's time per level). What was
-- not kept is anything over time, so this file keeps a small log, account
-- wide, in `farmStats` (never rename it or its fields):
--
--   days[YYYY-MM-DD] = { drops, coin, gather, fish, grey, kills, seconds,
--                        mobs = { [mob] = kills } }
--   sessions = { { day, at, seconds, copper, kills }, ... }  newest last
--   pace[mob] = { kills, seconds }   how long a kill of it takes you
--
-- Copper is what each thing was worth when it was looted (Value:UnitPrice:
-- greys at vendor, the rest the best of auction and vendor), coin as it
-- came. An item with no price yet waits in memory and is priced on the next
-- draw or at logout. Time is farming time: the gaps between one loot and
-- the next, a gap of BREAK seconds or more being a break and left out, so
-- a session's gold an hour is not watered down by standing in town.
--
-- Nothing is added up while playing beyond a few numbers a loot; the
-- charts are worked out only while the tab draws. Old days go after
-- KEEP_DAYS, old sessions past KEEP_SESSIONS.
--
-- Guild shared drops never come here: only what you loot yourself.

local _, ns = ...
local L = ns.L

local Stats = ns.NewModule("Stats")

Stats.BREAK = 300            -- seconds without a loot that count as a break
Stats.PACE_GAP = 120         -- kills further apart than this teach no pace
Stats.PACE_MIN = 8           -- kills of a mob before its own pace is used
Stats.SESSION_MIN = 300      -- farming seconds before a session is charted
Stats.BEST_AFTER = 900       -- and before it can be your best
Stats.BEST_AGAINST = 3       -- sessions charted before a best is cheered
Stats.KEEP_DAYS = 100
Stats.KEEP_SESSIONS = 30
Stats.LUCK_MIN_KILLS = 10

-- Where gold comes from, in the order the chart stacks them.
Stats.SOURCES = { "drops", "coin", "gather", "fish", "grey" }

-- Kinds of source a kill can be measured against.
local CREATURE_KINDS = { mob = true }

Stats.version = 0

--------------------------------------------------------------------------------
-- The clock
--------------------------------------------------------------------------------

local function Now()
    if type(GetTime) ~= "function" then return nil end
    local ok, now = pcall(GetTime)
    return ok and type(now) == "number" and now or nil
end

local function Clock()
    local fn = _G.time or (os and os.time)
    if type(fn) ~= "function" then return nil end
    local ok, now = pcall(fn)
    return ok and type(now) == "number" and now or nil
end
Stats.Clock = Clock

--- The day `at` (wall clock seconds, now when nil) falls on: "2026-10-13".
function Stats.DayKey(at)
    local fn = _G.date or (os and os.date)
    at = at or Clock()
    if type(fn) ~= "function" or not at then return nil end
    local ok, key = pcall(fn, "%Y-%m-%d", at)
    return ok and type(key) == "string" and key or nil
end

--- The day `back` days before today (0 for today).
function Stats.DayBack(back, now)
    now = now or Clock()
    if not now then return nil end
    return Stats.DayKey(now - (back or 0) * 86400)
end

local function Number(value)
    value = tonumber(value)
    if not value or value ~= value or value == math.huge or value == -math.huge then return nil end
    return value
end

--------------------------------------------------------------------------------
-- The save
--------------------------------------------------------------------------------

function Stats:Store()
    if not ns.db then return nil end
    local store = ns.db.farmStats
    if type(store) ~= "table" then
        store = {}
        ns.db.farmStats = store
    end
    if type(store.days) ~= "table" then store.days = {} end
    if type(store.sessions) ~= "table" then store.sessions = {} end
    if type(store.pace) ~= "table" then store.pace = {} end
    return store
end

--- Today's line, made when first needed.
function Stats:Day(key)
    local store = self:Store()
    key = key or Stats.DayKey()
    if not (store and key) then return nil end
    local day = store.days[key]
    if type(day) ~= "table" then
        day = {}
        store.days[key] = day
    end
    if type(day.mobs) ~= "table" then day.mobs = {} end
    return day
end

--- This login's session, made at its first loot, so a login spent in town
--- leaves no empty session behind.
function Stats:Session()
    if self.current then return self.current end
    local store = self:Store()
    if not store then return nil end
    local session = { day = Stats.DayKey(), at = Clock(), seconds = 0, copper = 0, kills = 0 }
    store.sessions[#store.sessions + 1] = session
    self.current = session
    return session
end

local function Add(into, key, amount)
    into[key] = (Number(into[key]) or 0) + amount
end

--- Days past KEEP_DAYS, sessions past KEEP_SESSIONS and sessions too short
--- to chart go. Run once at login; never touches anything else.
function Stats:Prune()
    local store = self:Store()
    if not store then return end

    local oldest = Stats.DayBack(Stats.KEEP_DAYS)
    if oldest then
        for key in pairs(store.days) do
            if type(key) ~= "string" or key < oldest then store.days[key] = nil end
        end
    end

    local kept = {}
    for _, session in ipairs(store.sessions) do
        if type(session) == "table" and session ~= self.current
            and (Number(session.seconds) or 0) >= Stats.SESSION_MIN then
            kept[#kept + 1] = session
        end
    end
    while #kept > Stats.KEEP_SESSIONS do table.remove(kept, 1) end
    if self.current then kept[#kept + 1] = self.current end
    store.sessions = kept
end

--------------------------------------------------------------------------------
-- What happens while you play
--------------------------------------------------------------------------------

--- A loot of any kind moved the farming clock: the gap since the last one
--- is farming time unless it was a break.
function Stats:Tick()
    local now = Now()
    if not now then return end
    local last = self.lastAt
    self.lastAt = now
    if not last then return end
    local gap = now - last
    if gap <= 0 or gap >= Stats.BREAK then return end

    local session, day = self:Session(), self:Day()
    if session then Add(session, "seconds", gap) end
    if day then Add(day, "seconds", gap) end
end

--- Copper earned from `source` ("drops", "coin", ...).
function Stats:Earn(source, copper)
    copper = Number(copper)
    if not copper or copper <= 0 then return end
    local session, day = self:Session(), self:Day()
    if session then Add(session, "copper", copper) end
    if day then Add(day, source, copper) end
    self.version = self.version + 1
    self:CheckBest()
    self:Changed()
end

--- An item looted, fished or gathered. Priced now when it can be, else it
--- waits for a price (an item the client has not loaded yet).
function Stats:Loot(kind, name, count)
    count = Number(count)
    if type(name) ~= "string" or not count or count <= 0 then return end
    if ns.DB and ns.DB.HidesItem and ns.DB:HidesItem(name) then return end
    self:Tick()
    if not self:Price(kind, name, count) then
        self.pending = self.pending or {}
        local key = kind .. "\0" .. name
        local entry = self.pending[key]
        if not entry then
            entry = { kind = kind, name = name, count = 0, day = Stats.DayKey() }
            self.pending[key] = entry
        end
        entry.count = entry.count + count
    end
end

--- What `count` of `name` is worth, put down under its source. False when
--- it has no price yet.
function Stats:Price(kind, name, count, dayKey)
    local Value = ns.Value
    if not Value then return false end
    local id = Value:ItemID(name)
    local unit = id and Value:UnitPrice(id)
    if not unit then return false end
    local source = kind
    local poor, sure = Value:IsPoor(id)
    if poor and sure then source = "grey" end

    if dayKey and dayKey ~= Stats.DayKey() then
        -- Priced late, on another day: it belongs to the day it was looted.
        local day = self:Day(dayKey)
        if day then Add(day, source, unit * count) end
        if self.current then Add(self.current, "copper", unit * count) end
        self.version = self.version + 1
        return true
    end
    self:Earn(source, unit * count)
    return true
end

--- Items that were waiting for a price, priced now if they can be.
function Stats:Settle()
    if not self.pending then return end
    for key, entry in pairs(self.pending) do
        if self:Price(entry.kind, entry.name, entry.count, entry.day) then
            self.pending[key] = nil
        end
    end
    if not next(self.pending) then self.pending = nil end
end

--- Coin off a corpse.
function Stats:Coin(copper)
    copper = Number(copper)
    if not copper or copper <= 0 then return end
    self:Tick()
    self:Earn("coin", copper)
end

--- A kill you looted. `items` and `quantities` are the corpse's own (not
--- the rest of an area loot), for this login's luck.
function Stats:Kill(mobName, items, quantities)
    if type(mobName) ~= "string" then return end
    self:Tick()

    local session, day = self:Session(), self:Day()
    if session then Add(session, "kills", 1) end
    if day then
        Add(day, "kills", 1)
        Add(day.mobs, mobName, 1)
    end

    -- How long a kill of it takes you: the time since the kill before,
    -- when that was close enough to be the same run.
    local now = Now()
    local store = self:Store()
    if now and store and self.lastKillAt then
        local gap = now - self.lastKillAt
        if gap > 0 and gap <= Stats.PACE_GAP then
            local pace = store.pace[mobName]
            if type(pace) ~= "table" then
                pace = { kills = 0, seconds = 0 }
                store.pace[mobName] = pace
            end
            Add(pace, "kills", 1)
            Add(pace, "seconds", gap)
        end
    end
    self.lastKillAt = now

    -- This login's drops, for luck.
    self.luck = self.luck or {}
    local mob = self.luck[mobName]
    if not mob then
        mob = { kills = 0, items = {} }
        self.luck[mobName] = mob
    end
    mob.kills = mob.kills + 1
    for _, name in ipairs(type(items) == "table" and items or {}) do
        local quantity = Number(quantities and quantities[name]) or 1
        mob.items[name] = (mob.items[name] or 0) + quantity
    end

    self.version = self.version + 1
    self:Changed()
end

--- Tell the tab something moved; it draws again a moment later, only while
--- it is on screen.
function Stats:Changed()
    if ns.StatsUI and ns.StatsUI.Changed then ns.StatsUI:Changed() end
end

--------------------------------------------------------------------------------
-- Sessions
--------------------------------------------------------------------------------

--- Copper an hour for a session, or nil while it is too short to say.
function Stats.Rate(session, least)
    if type(session) ~= "table" then return nil end
    local seconds = Number(session.seconds) or 0
    if seconds < (least or Stats.SESSION_MIN) then return nil end
    return (Number(session.copper) or 0) / seconds * 3600
end

--- The sessions worth charting, oldest first, the one playing last when it
--- is long enough: { { rate, day, at, current } }, at most `count`.
function Stats:Series(count)
    local store = self:Store()
    local series = {}
    if not store then return series end
    for _, session in ipairs(store.sessions) do
        local rate = Stats.Rate(session)
        if rate then
            series[#series + 1] = { rate = rate, day = session.day, at = session.at,
                seconds = session.seconds, current = session == self.current }
        end
    end
    count = count or 20
    while #series > count do table.remove(series, 1) end
    return series
end

--- Your usual gold an hour: every charted session before this one, by the
--- time spent. Nil with none.
function Stats:Usual()
    local store = self:Store()
    if not store then return nil end
    local copper, seconds = 0, 0
    for _, session in ipairs(store.sessions) do
        if session ~= self.current and Stats.Rate(session) then
            copper = copper + (Number(session.copper) or 0)
            seconds = seconds + (Number(session.seconds) or 0)
        end
    end
    if seconds <= 0 then return nil end
    return copper / seconds * 3600
end

--- The best charted session before this one, and its rate.
function Stats:Best(exceptCurrent)
    local store = self:Store()
    if not store then return nil end
    local best, bestRate, counted = nil, nil, 0
    for _, session in ipairs(store.sessions) do
        local rate = Stats.Rate(session)
        if rate and not (exceptCurrent and session == self.current) then
            counted = counted + 1
            if not bestRate or rate > bestRate then best, bestRate = session, rate end
        end
    end
    return best, bestRate, counted
end

--- Once a session: when it passes every one before it, a line in chat and
--- the rank-up chime ("Best session cheer", `statsBestCheer`, on unless
--- unticked; never rename it).
function Stats:CheckBest()
    local session = self.current
    if not session or session.cheered then return end
    local rate = Stats.Rate(session, Stats.BEST_AFTER)
    if not rate then return end
    local _, bestRate, counted = self:Best(true)
    if not bestRate or counted < Stats.BEST_AGAINST or rate <= bestRate then return end

    session.cheered = true
    if ns.db and ns.db.statsBestCheer == false then return end
    ns.Print(L.Format("Your best gold an hour yet: %s.", ns.Value.Coins(rate)))
    if ns.Tracker and ns.Tracker.PlayFile and ns.Tracker.SOUNDS then
        ns.Tracker.PlayFile(ns.Tracker.SOUNDS.rankup)
    end
    if ns.StatsUI and ns.StatsUI.Best then pcall(ns.StatsUI.Best, ns.StatsUI) end
end

--------------------------------------------------------------------------------
-- Days
--------------------------------------------------------------------------------

local function DayCopper(day)
    if type(day) ~= "table" then return 0 end
    local total = 0
    for _, source in ipairs(Stats.SOURCES) do total = total + (Number(day[source]) or 0) end
    return total
end
Stats.DayCopper = DayCopper

local function Farmed(day)
    return type(day) == "table" and ((Number(day.kills) or 0) > 0 or DayCopper(day) > 0)
end

--- The last `count` days, today last: { key, copper, kills, seconds, top,
--- topKills, sources }.
function Stats:Days(count, now)
    local store = self:Store()
    local list = {}
    now = now or Clock()
    for back = count - 1, 0, -1 do
        local key = Stats.DayBack(back, now)
        local day = store and key and store.days[key]
        local entry = { key = key, copper = DayCopper(day), kills = Number(day and day.kills) or 0,
            seconds = Number(day and day.seconds) or 0, day = day }
        if type(day) == "table" and type(day.mobs) == "table" then
            for mob, kills in pairs(day.mobs) do
                kills = Number(kills) or 0
                if not entry.topKills or kills > entry.topKills
                    or (kills == entry.topKills and mob < entry.top) then
                    entry.top, entry.topKills = mob, kills
                end
            end
        end
        list[#list + 1] = entry
    end
    return list
end

--- Gold by source over the last `count` days: { { key, copper } } in
--- SOURCES order, and the total.
function Stats:Sources(count)
    local totals = {}
    for _, source in ipairs(Stats.SOURCES) do totals[source] = 0 end
    for _, entry in ipairs(self:Days(count or 7)) do
        if entry.day then
            for _, source in ipairs(Stats.SOURCES) do
                totals[source] = totals[source] + (Number(entry.day[source]) or 0)
            end
        end
    end
    local list, total = {}, 0
    for _, source in ipairs(Stats.SOURCES) do
        list[#list + 1] = { key = source, copper = totals[source] }
        total = total + totals[source]
    end
    return list, total
end

--- Days in a row you farmed, counting back from today (or from yesterday
--- while today has nothing yet), and the longest run kept.
function Stats:Streak(now)
    local store = self:Store()
    if not store then return 0, 0 end
    now = now or Clock()

    local run, back = 0, 0
    if not Farmed(store.days[Stats.DayBack(0, now) or ""]) then back = 1 end
    while Farmed(store.days[Stats.DayBack(back, now) or ""]) do
        run = run + 1
        back = back + 1
    end

    local keys = {}
    for key, day in pairs(store.days) do
        if type(key) == "string" and Farmed(day) then keys[#keys + 1] = key end
    end
    table.sort(keys)

    -- A run is days one after another; read each day's next day off the clock.
    local longest, length, previous = 0, 0, nil
    local index = {}
    for i = 0, Stats.KEEP_DAYS + 1 do
        local key = Stats.DayBack(i, now)
        if key then index[key] = i end
    end
    for _, key in ipairs(keys) do
        local at = index[key]
        if at and previous and previous - at == 1 then
            length = length + 1
        else
            length = 1
        end
        previous = at
        if length > longest then longest = length end
    end
    return run, math.max(longest, run)
end

--- The top of the tab: this session, the week and the run of days.
function Stats:Summary()
    local summary = {}
    local session = self.current
    summary.rate = Stats.Rate(session)
    summary.sessionSeconds = session and Number(session.seconds) or 0
    summary.usual = self:Usual()
    if summary.rate and summary.usual and summary.usual > 0 then
        summary.change = (summary.rate / summary.usual - 1) * 100
    end

    local copper, seconds, kills = 0, 0, 0
    for _, entry in ipairs(self:Days(7)) do
        copper = copper + entry.copper
        seconds = seconds + entry.seconds
        kills = kills + entry.kills
    end
    summary.week, summary.weekSeconds, summary.weekKills = copper, seconds, kills
    if seconds >= 60 then summary.killsPerHour = kills / seconds * 3600 end

    summary.streak, summary.longest = self:Streak()
    return summary
end

--------------------------------------------------------------------------------
-- Your best mobs for gold
--------------------------------------------------------------------------------

--- Seconds a kill of `mobName` takes you: its own pace once it has
--- PACE_MIN kills, else your pace over every mob. Second value: true when
--- it is the mob's own.
function Stats:SecondsPerKill(mobName)
    local store = self:Store()
    if not store then return nil end
    local pace = store.pace[mobName]
    if type(pace) == "table" and (Number(pace.kills) or 0) >= Stats.PACE_MIN then
        return math.max(5, (Number(pace.seconds) or 0) / pace.kills), true
    end
    local kills, seconds = 0, 0
    for _, entry in pairs(store.pace) do
        if type(entry) == "table" then
            kills = kills + (Number(entry.kills) or 0)
            seconds = seconds + (Number(entry.seconds) or 0)
        end
    end
    if kills < Stats.PACE_MIN then return nil end
    return math.max(5, seconds / kills), false
end

--- Mobs you have killed enough to measure, by gold an hour at your kill
--- speed: { { mob, rate, perKill, seconds, own } }, best first, at most
--- `count`.
function Stats:BestMobs(count)
    local list = {}
    local Tracker, Value = ns.Tracker, ns.Value
    if not (Tracker and Value) then return list end
    for name, mob in pairs(Tracker:Store()) do
        if type(name) == "string" and type(mob) == "table"
            and (Number(mob.kills) or 0) >= Tracker.MIN_KILLS
            and not (ns.DB and ns.DB:IsHiddenSource(name)) then
            local perKill = Value:FromTally(name)
            local seconds, own = self:SecondsPerKill(name)
            if perKill and perKill > 0 and seconds then
                list[#list + 1] = { mob = name, perKill = perKill, seconds = seconds, own = own,
                    rate = perKill * 3600 / seconds }
            end
        end
    end
    table.sort(list, function(a, b)
        if a.rate ~= b.rate then return a.rate > b.rate end
        return a.mob < b.mob
    end)
    count = count or 5
    while #list > count do table.remove(list) end
    return list
end

--------------------------------------------------------------------------------
-- Luck
--------------------------------------------------------------------------------

--- This login's drops against the drop rates: { percent, kills, rows =
--- { { name, got, expected, color } } }, percent by worth (an item with no
--- price is listed but left out of it). Nil until LUCK_MIN_KILLS kills of
--- mobs the data has rates for.
function Stats:Luck()
    if not (self.luck and ns.DB and ns.Value) then return nil end
    local Value, Tracker = ns.Value, ns.Tracker
    local items, kills = {}, 0

    for mobName, mob in pairs(self.luck) do
        local rated = false
        local seen = {}
        for _, entry in ipairs(ns.DB:ByName()[mobName] or {}) do
            local item, source = entry.item, entry.source
            if source.chance and CREATURE_KINDS[source.kind or "mob"] and not seen[item.name]
                and not ns.DB:HidesItem(item.name) then
                seen[item.name] = true
                rated = true
                local stack = Tracker and Tracker:StackSize(mobName, item.name) or 1
                local row = items[item.name]
                if not row then
                    row = { name = item.name, got = 0, expected = 0, id = item.id }
                    items[item.name] = row
                end
                row.expected = row.expected + mob.kills * source.chance / 100 * (Number(stack) or 1)
                row.got = row.got + (mob.items[item.name] or 0)
            end
        end
        if rated then kills = kills + mob.kills end
    end
    if kills < Stats.LUCK_MIN_KILLS then return nil end

    local got, expected, rows = 0, 0, {}
    for _, row in pairs(items) do
        local unit = Value:UnitPrice(row.id or Value:ItemID(row.name))
        row.unit = unit
        row.worth = unit and row.expected * unit or 0
        if unit then
            got = got + row.got * unit
            expected = expected + row.expected * unit
        end
        local look = Tracker and Tracker:LookOf(row.name)
        row.color = look and look.color
        rows[#rows + 1] = row
    end
    if expected <= 0 then return nil end

    table.sort(rows, function(a, b)
        if a.worth ~= b.worth then return a.worth > b.worth end
        if a.expected ~= b.expected then return a.expected > b.expected end
        return a.name < b.name
    end)
    while #rows > 3 do table.remove(rows) end

    return { percent = (got / expected - 1) * 100, kills = kills, rows = rows }
end

--------------------------------------------------------------------------------
-- Levels
--------------------------------------------------------------------------------

--- How long each level took this character, from the XP bar's record: the
--- last `count` levels kept, { { level, seconds, fastest } }, oldest first.
function Stats:Levels(count)
    local record = ns.XP and ns.XP.Record and ns.XP:Record()
    local list = {}
    if not (record and type(record.levels) == "table") then return list end
    for level, seconds in pairs(record.levels) do
        level, seconds = Number(level), Number(seconds)
        if level and seconds and seconds > 0 then
            list[#list + 1] = { level = level, seconds = seconds }
        end
    end
    table.sort(list, function(a, b) return a.level < b.level end)
    count = count or 15
    while #list > count do table.remove(list, 1) end
    if #list >= 2 then
        local fastest
        for _, entry in ipairs(list) do
            if not fastest or entry.seconds < fastest.seconds then fastest = entry end
        end
        fastest.fastest = true
    end
    return list
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

function Stats:OnEnable()
    self:Prune()
    ns.RegisterEvent(self, "PLAYER_LOGOUT", function() Stats:Settle() end)
end

ns.RegisterCommand("charts", L["the Stats tab: your farming in charts (cheer on|off)"], function(rest)
    local word, value = (rest or ""):lower():match("^(%S*)%s*(%S*)")
    if word == "cheer" then
        local on
        if value == "on" then on = true elseif value == "off" then on = false
        else on = ns.db.statsBestCheer == false end
        ns.db.statsBestCheer = on
        ns.Print(on and L["Best session cheer is on."] or L["Best session cheer is off."])
        if ns.SettingsUI and ns.SettingsUI.Refresh then pcall(ns.SettingsUI.Refresh, ns.SettingsUI) end
        return
    end
    ns.UI:Show()
    ns.UI:ShowTab("stats")
end)
