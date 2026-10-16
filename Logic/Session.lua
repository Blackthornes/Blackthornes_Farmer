-- Blackthornes Farmer -- Logic/Session.lua
-- What the kills and loot panel shows, kept from one session to the next.
--
-- The tallies (every mob's kills and drops, every fishing spot and node) have
-- always been saved. The panel's own view was not: the kills, loot, coin and
-- gathered value of "this session" lived in memory, so a /reload or a relog
-- emptied it. The owner asked (2026-10-11) for it to stay, per character,
-- until the player clears it, then (2026-10-13) for the panel to start empty
-- each session again. So the panel starts empty at every login and /reload,
-- and keeping it is a choice: "Keep between sessions" on the Kill tally page
-- (`keepPanel`, account wide, off unless ticked; never rename it) and
-- `/farm tracker keep`. Unticked, nothing is read or written here, and a run
-- saved while it was ticked is left in the save untouched; the next logout
-- with it ticked writes over it before any login could read it.
--
-- So at logout (which a /reload is too) the panel's counts are put in the
-- account save under the character's GUID, `panelSessions[guid]`, and at
-- login they are read back. Never rename it. Nothing is written while
-- playing: the tables are handed over as they are, once, on the way out, so
-- a loot costs nothing more than it did.
--
-- What is kept: Tracker's, Fishing's and Gathering's session counts, the
-- order things were last done in, the coin, the best streak, which you did
-- last, and how long the run has been timed (for gold per hour, counted in
-- play time, so a night logged out is not an hour of earning). What is not:
-- the corpses opened, by guid, and the running streak, which only mean
-- something within one session.
--
-- Clear panel (`Session:Clear`, the panel's Clear button, Settings and
-- `/farm tracker clear`) empties the view alone: every tally, rate and
-- ranking stays.
--
-- A character whose GUID the client will not read (logged in inside a
-- dungeon) keeps nothing and is given nothing: one character's run never
-- lands on another (see "One key per character" in CLAUDE.md).

local _, ns = ...

local Session = ns.NewModule("Session")

-- Each module's session fields: counts by name, counts by name by name (the
-- Loot tab's "from" lists), the order last done in, and plain numbers.
Session.FIELDS = {
    Tracker = {
        -- sessionZones: kills by zone's key, for a name split by zone.
        counts = { "session", "sessionLoot", "sessionZones" },
        nested = { "sessionFrom" },
        recent = "recent",
        numbers = { "sessionCopper" },
        best = "bestStreak",
    },
    Fishing = {
        counts = { "session", "sessionCatch" },
        nested = {},
        recent = "recent",
        numbers = { "sessionCasts" },
    },
    Gathering = {
        counts = { "session", "sessionItems" },
        nested = { "sessionFrom" },
        recent = "recent",
        numbers = { "sessionGathers" },
    },
}

local ORDER = { "Tracker", "Fishing", "Gathering" }
Session.ORDER = ORDER

local LAST_LOOT = { kill = true, fishing = true, gathering = true }

--- The client's clock in seconds, or nil.
local function Now()
    if type(GetTime) ~= "function" then return nil end
    local ok, now = pcall(GetTime)
    return ok and type(now) == "number" and now or nil
end

--- Wall-clock seconds, for when a run was saved.
local function Clock()
    if type(time) ~= "function" then return nil end
    local ok, now = pcall(time)
    return ok and type(now) == "number" and now or nil
end

--- Whether the panel is kept from one session to the next (off by default).
function Session.KeepOn()
    return ns.db ~= nil and ns.db.keepPanel == true
end

--- The character playing, by GUID, or nil while the client will not say.
function Session:Owner()
    return ns.Goals and ns.Goals:Owner() or nil
end

function Session:Store()
    if type(ns.db.panelSessions) ~= "table" then ns.db.panelSessions = {} end
    return ns.db.panelSessions
end

--- A count read from the save: a whole, finite number above zero, or nil.
local function Count(value)
    value = tonumber(value)
    if not value or value ~= value or value <= 0 or value == math.huge then return nil end
    return value
end

--- Adds `from`'s counts into `into`, skipping anything that is not a count.
local function AddCounts(into, from)
    if type(from) ~= "table" then return end
    for name, value in pairs(from) do
        local count = type(name) == "string" and Count(value)
        if count then into[name] = (tonumber(into[name]) or 0) + count end
    end
end

--------------------------------------------------------------------------------
-- Is there anything to keep?
--------------------------------------------------------------------------------

--- Whether the panel shows anything at all.
function Session:HasAny()
    for _, name in ipairs(ORDER) do
        local module = ns[name]
        local fields = self.FIELDS[name]
        if module then
            for _, key in ipairs(fields.counts) do
                if type(module[key]) == "table" and next(module[key]) then return true end
            end
            for _, key in ipairs(fields.numbers) do
                if (tonumber(module[key]) or 0) > 0 then return true end
            end
        end
    end
    return false
end

--------------------------------------------------------------------------------
-- Saving and reading back
--------------------------------------------------------------------------------

--- How long the per-hour clock has run, in seconds, or nil when it is not.
function Session:Played()
    local TrackerUI = ns.TrackerUI
    local started = TrackerUI and TrackerUI.startedAt
    local now = Now()
    if type(started) ~= "number" or not now or now < started then return nil end
    return now - started
end

--- The panel's counts, as they go in the save.
function Session:Snapshot()
    local saved = { at = Clock(), played = self:Played(), lastLoot = ns.lastLoot }

    for _, name in ipairs(ORDER) do
        local module = ns[name]
        local fields = self.FIELDS[name]
        if module then
            local part = { clock = tonumber(module.clock) or 0 }
            for _, key in ipairs(fields.counts) do part[key] = module[key] end
            for _, key in ipairs(fields.nested) do part[key] = module[key] end
            for _, key in ipairs(fields.numbers) do part[key] = tonumber(module[key]) or 0 end
            part[fields.recent] = module[fields.recent]
            if fields.best then part[fields.best] = tonumber(module[fields.best]) or 0 end
            if name == "Tracker" then part.current = module.current end
            saved[name:lower()] = part
        end
    end

    return saved
end

--- At logout: keep the panel's counts under this character. An empty panel
--- (cleared, or nothing done) leaves nothing behind.
function Session:Save()
    local owner = self:Owner()
    if not owner then return false end

    local store = self:Store()
    if self:HasAny() then
        store[owner] = self:Snapshot()
    else
        store[owner] = nil
    end
    return true
end

--- Adds a saved part into one module's session. Live counts (anything done
--- before the GUID could be read) are kept, the saved ones added to them,
--- and the saved order goes before the live one.
local function Merge(module, fields, part)
    if type(part) ~= "table" then return end

    for _, key in ipairs(fields.counts) do
        if type(module[key]) ~= "table" then module[key] = {} end
        AddCounts(module[key], part[key])
    end

    for _, key in ipairs(fields.nested) do
        if type(module[key]) ~= "table" then module[key] = {} end
        if type(part[key]) == "table" then
            for item, from in pairs(part[key]) do
                if type(item) == "string" and type(from) == "table" then
                    module[key][item] = module[key][item] or {}
                    AddCounts(module[key][item], from)
                end
            end
        end
    end

    for _, key in ipairs(fields.numbers) do
        module[key] = (tonumber(module[key]) or 0) + (Count(part[key]) or 0)
    end

    -- The order things were last done in: saved first, then whatever this
    -- session did, shifted past them.
    local clock = Count(part.clock) or 0
    local recent = type(module[fields.recent]) == "table" and module[fields.recent] or {}
    local merged = {}
    if type(part[fields.recent]) == "table" then
        for name, at in pairs(part[fields.recent]) do
            local tick = type(name) == "string" and Count(at)
            if tick then merged[name] = math.min(tick, clock) end
        end
    end
    for name, at in pairs(recent) do merged[name] = (tonumber(at) or 0) + clock end
    module[fields.recent] = merged
    module.clock = (tonumber(module.clock) or 0) + clock

    if fields.best then
        module[fields.best] = math.max(tonumber(module[fields.best]) or 0, Count(part[fields.best]) or 0)
    end
end

--- At login: put this character's saved run back on the panel, once.
function Session:Restore()
    if self.restored then return true end

    local owner = self:Owner()
    if not owner then return false end
    self.restored = true

    -- Each session starts empty unless the player keeps the panel.
    if not self.KeepOn() then return true end

    local saved = self:Store()[owner]
    if type(saved) ~= "table" then return true end

    local hadTracker = ns.Tracker and ns.Tracker.current

    for _, name in ipairs(ORDER) do
        local module = ns[name]
        if module then Merge(module, self.FIELDS[name], saved[name:lower()]) end
    end

    local tracker = saved.tracker
    if ns.Tracker and not hadTracker and type(tracker) == "table"
        and type(tracker.current) == "string" and ns.Tracker.session[tracker.current] then
        ns.Tracker.current = tracker.current
    end

    if ns.lastLoot == nil and LAST_LOOT[saved.lastLoot] then ns.lastLoot = saved.lastLoot end

    -- The per-hour clock goes on from where it stopped.
    local played = Count(saved.played)
    local now = Now()
    local TrackerUI = ns.TrackerUI
    if played and now and TrackerUI then
        TrackerUI.startedAt = (TrackerUI.startedAt or now) - played
    end

    -- Drawn as it was: none of this is new loot, so no effects for it.
    if ns.TrackerFX and ns.TrackerFX.Rebase then ns.TrackerFX:Rebase() end
    if TrackerUI and TrackerUI.Refresh then TrackerUI:Refresh() end
    return true
end

--------------------------------------------------------------------------------
-- Clear panel
--------------------------------------------------------------------------------

--- Empties what the panel shows, and only that: every tally stays. The
--- corpses already opened are still known, so one opened again is no new
--- kill.
function Session:Clear()
    for _, name in ipairs(ORDER) do
        local module = ns[name]
        local fields = self.FIELDS[name]
        if module then
            for _, key in ipairs(fields.counts) do module[key] = {} end
            for _, key in ipairs(fields.nested) do module[key] = {} end
            for _, key in ipairs(fields.numbers) do module[key] = 0 end
            module[fields.recent] = {}
            module.clock = 0
            if fields.best then module[fields.best] = 0 end
        end
    end

    local Tracker = ns.Tracker
    if Tracker then
        Tracker.current = nil
        Tracker.currentKey = nil
        Tracker.streak = 0
        Tracker.streakAt = nil
    end
    ns.lastLoot = nil

    local owner = self:Owner()
    if owner and type(ns.db.panelSessions) == "table" then ns.db.panelSessions[owner] = nil end

    local TrackerUI = ns.TrackerUI
    if TrackerUI then
        if TrackerUI.ResetState then TrackerUI:ResetState() end
        TrackerUI.startedAt = nil
    end
    if ns.TrackerFX and ns.TrackerFX.Rebase then ns.TrackerFX:Rebase() end
    if TrackerUI and TrackerUI.Refresh then TrackerUI:Refresh() end
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

function Session:OnEnable()
    -- Before the panel is first drawn when the GUID is there at login; else
    -- on the next loading screen that lets it be read.
    self:Restore()
    if not self.restored then
        -- Left registered once done: taking a handler out while the event
        -- runs would skip the next module's.
        ns.RegisterEvent(self, "PLAYER_ENTERING_WORLD", function()
            if not Session.restored then Session:Restore() end
        end)
    end

    -- A reload logs out too. Not restored means the GUID was never read, so
    -- there is nothing of this character's to write over. Not kept means the
    -- save is left as it is.
    ns.RegisterEvent(self, "PLAYER_LOGOUT", function()
        if Session.restored and Session.KeepOn() then Session:Save() end
    end)
end
