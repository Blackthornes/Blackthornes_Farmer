-- Blackthornes Farmer -- Logic/Pace.lua
-- How long it takes you to farm one of an item (the owner said yes,
-- 2026-10-15, from a mockup of craft or farm in Tradeskills).
--
-- Tradeskills' Your time view weighs farming a craft's materials against
-- selling them as they are and against buying them. It asks here, inside a
-- pcall and read only:
--
--     _G.BlackthornesFarmer.Pace:ForItem(item)   -- item ID or name
--
-- and gets the fastest way you farm it, from your own play only:
--
--     { seconds (for one), kind ("kill", "skin" or "gather"), source (the mob
--       or node), zone (gathers only), samples (kills, skins or gathers
--       behind it), perAction (items one kill, skin or gather gives you) }
--
-- or nil and { samples } when nothing you farm has enough behind it yet
-- (samples the most any one source has, 0 when nothing of yours gave it).
-- It never raises and never writes.
--
-- Where the numbers come from, all recorded already:
--
-- - kills: the kill tally (Tracker, items per kill once MIN_SAMPLE kills)
--   and the seconds a kill takes you (Stats:SecondsPerKill, the mob's own
--   pace only, never your average over every mob);
-- - skins: what your skins of a mob gave (GrindGather's skinLog) at that
--   mob's own kill pace;
-- - gathers: the time between gathers in one zone and what they gave
--   (GrindGather's gathering.pace).
--
-- Guild data never reaches any of these, nor a database drop rate: a pace
-- is only ever your own. Hidden items and sources are left out.
--
-- Tradeskills asks once per material of every craft it lists, so the
-- sources are laid out once as a lookup by item name and built again only
-- after KEEP seconds.

local _, ns = ...

local Pace = ns.NewModule("Pace")

-- Kills, skins or gathers of one source before its pace is used.
Pace.MIN_SAMPLE = 20
-- Gathering time counted before a node's pace is used.
Pace.MIN_SECONDS = 60
-- How long the lookup is kept.
Pace.KEEP = 30

local function Number(value)
    return type(value) == "number" and value or tonumber(value)
end

local function Clock()
    return type(GetTime) == "function" and GetTime() or 0
end

local function Hidden(kind, name)
    local DB = ns.DB
    if not DB then return false end
    if kind == "item" then return DB.IsHiddenItem and DB:IsHiddenItem(name) or false end
    return DB.IsHiddenSource and DB:IsHiddenSource(name) or false
end

--- Lay out every source of yours by item name (lower case): { best = the
--- fastest with enough behind it, samples = the most any source has }.
function Pace:Build()
    local byName = {}
    local function Note(itemName, samples, candidate)
        if type(itemName) ~= "string" or itemName == "" or Hidden("item", itemName) then return end
        local key = itemName:lower()
        local entry = byName[key]
        if not entry then
            entry = { samples = 0 }
            byName[key] = entry
        end
        if samples > entry.samples then entry.samples = samples end
        if candidate and candidate.seconds and candidate.seconds > 0
            and (not entry.best or candidate.seconds < entry.best.seconds) then
            entry.best = candidate
        end
    end

    local Tracker, Stats = ns.Tracker, ns.Stats
    local minimum = Pace.MIN_SAMPLE

    -- Kills
    if Tracker and Stats then
        for mobName, mob in pairs(Tracker:Store()) do
            if type(mobName) == "string" and type(mob) == "table" and not Hidden("source", mobName) then
                local kills = Number(mob.kills) or 0
                local seconds, own = nil, false
                if kills >= minimum then seconds, own = Stats:SecondsPerKill(mobName) end
                if not own then seconds = nil end
                for itemName, corpses in pairs(type(mob.items) == "table" and mob.items or {}) do
                    corpses = Number(corpses) or 0
                    local candidate
                    if seconds and corpses > 0 then
                        local perKill = corpses / kills * Tracker:StackSize(mobName, itemName)
                        if perKill > 0 then
                            candidate = { seconds = seconds / perKill, kind = "kill", source = mobName,
                                samples = kills, perAction = perKill }
                        end
                    end
                    Note(itemName, corpses > 0 and kills or 0, candidate)
                end
            end
        end
    end

    -- Skins, at the mob's own kill pace
    local skinLog = ns.db and ns.db.skinLog
    if Stats and type(skinLog) == "table" then
        for mobName, entry in pairs(skinLog) do
            if type(mobName) == "string" and type(entry) == "table" and not Hidden("source", mobName) then
                local skins = Number(entry.skins) or 0
                local seconds, own = nil, false
                if skins >= minimum then seconds, own = Stats:SecondsPerKill(mobName) end
                if not own then seconds = nil end
                for itemName, count in pairs(type(entry.items) == "table" and entry.items or {}) do
                    count = Number(count) or 0
                    local candidate
                    if seconds and count > 0 then
                        local perSkin = count / skins
                        candidate = { seconds = seconds / perSkin, kind = "skin", source = mobName,
                            samples = skins, perAction = perSkin }
                    end
                    Note(itemName, skins, candidate)
                end
            end
        end
    end

    -- Gathers
    local gathering = ns.db and ns.db.gathering
    local paces = type(gathering) == "table" and gathering.pace
    if type(paces) == "table" then
        for key, entry in pairs(paces) do
            if type(key) == "string" and type(entry) == "table" then
                local zone, node = key:match("^(.-)|(.*)$")
                if node and not Hidden("source", node) then
                    local gathers = Number(entry.gathers) or 0
                    local seconds = Number(entry.seconds) or 0
                    local ready = gathers >= minimum and seconds >= Pace.MIN_SECONDS
                    for itemName, count in pairs(type(entry.items) == "table" and entry.items or {}) do
                        count = Number(count) or 0
                        local candidate
                        if ready and count > 0 then
                            candidate = { seconds = seconds / count, kind = "gather", source = node,
                                zone = zone, samples = gathers, perAction = count / gathers }
                        end
                        Note(itemName, gathers, candidate)
                    end
                end
            end
        end
    end

    return byName
end

function Pace:Lookup()
    local now = Clock()
    if self.lookup and self.builtAt and now - self.builtAt < Pace.KEEP and now >= self.builtAt then
        return self.lookup
    end
    self.lookup, self.builtAt = self:Build(), now
    return self.lookup
end

--- Forget the lookup, so the next question builds it again.
function Pace:Forget()
    self.lookup, self.builtAt = nil, nil
end

--- The names an item goes by: the client's (what loot is recorded under)
--- and the data's (English).
local function Names(item)
    local names = {}
    local id = Number(item)
    if id then
        local client = ns.Butler and ns.Butler.NameOf and ns.Butler:NameOf(id)
        if client then names[#names + 1] = client end
        local data = ns.DB and ns.DB.ByID and ns.DB:ByID()[id]
        if data and data.name then names[#names + 1] = data.name end
    elseif type(item) == "string" and item ~= "" then
        names[1] = item
        local data = ns.DB and ns.DB.GetItem and ns.DB:GetItem(item)
        if data and data.name then names[#names + 1] = data.name end
    end
    return names
end

local function Copy(best)
    local copy = {}
    for key, value in pairs(best) do copy[key] = value end
    return copy
end

--- The fastest way you farm `item`, or nil and { samples }. Never raises.
function Pace:ForItem(item)
    local ok, best, samples = pcall(function()
        local lookup = self:Lookup()
        local found, most = nil, 0
        for _, name in ipairs(Names(item)) do
            local entry = lookup[name:lower()]
            if entry then
                if entry.samples > most then most = entry.samples end
                if entry.best and (not found or entry.best.seconds < found.seconds) then
                    found = entry.best
                end
            end
        end
        return found, most
    end)
    if not ok then return nil, { samples = 0 } end
    if best then return Copy(best) end
    return nil, { samples = samples or 0 }
end
