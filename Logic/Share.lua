-- Blackthornes Farmer -- Logic/Share.lua
-- Kills, drop rates, gathering and fishing shared with your other account.
--
-- Asked 2026-10-11 (a viewer's question on stream, the owner agreeing): WoW
-- keeps each account's saved data apart, so Farmer on one account could not
-- see what Farmer on the other had measured. This is the same pairing as
-- Tradeskills' account link (Logic/AccountLink.lua): each side names a
-- character on the other account in Settings > Sharing, and while both are
-- logged in they whisper each other. Off until ticked and a name is typed.
--
-- What is shared is counts only: the loot harvest (corpses and what they
-- held), the lifetime kill tally, nodes gathered and spots fished. Not
-- goals, settings or positions.
--
-- How two accounts' counts add up without ever counting one twice:
--   * Each side sends only what it counted ITSELF: its totals less what it
--     has already taken from partners. So a count goes round no loop, and
--     with three accounts nothing is passed on.
--   * The other side adds only what is new since it last heard: for every
--     number it keeps the largest value seen from that partner
--     (`shareIn[partner].credit`), and adds the difference. A message heard
--     twice adds nothing the second time; a partner whose counts went down
--     (a reset) adds nothing until they pass what was already taken.
--   * Taken counts are merged into the ordinary tables, so Rankings, the
--     tooltip and the drop rates just work. They cannot be taken back out.
--
-- What keeps it safe, as in Tradeskills:
--   * Only whispers, only from a name this side typed, and only after that
--     side typed this one (a hello from anyone else gets no answer).
--   * Every field is whitelisted and checked for its type and size; strings
--     lose their "|" (no colour, link or texture codes from someone else).
--   * Nothing is run, and nothing is relayed.
--
-- Saved, account wide, never renamed: `shareData` (on or off), `shareNames`
-- (the other account's characters, full names, comma apart) and `shareIn`
-- (`[partner] = { name, hashes, credit }`: what was heard and taken).
--
-- Smooth play: the lists are cut into frame-sized slices, nothing runs in
-- combat, and what is sent goes out a batch at a time as the pacing allows.

local _, ns = ...

local Share = ns.NewModule("Share")

local Comm = ns.Comm
local Serialize = ns.Serialize

Share.CHECK_SECONDS = 600
-- Records worked per frame when lists are built, and sent per message.
Share.SLICE = 30
Share.BATCH = 5
-- The most one section's manifest lists, and the most records a partner may
-- have us holding for one section.
Share.MAX_MANIFEST = 2500
Share.MAX_HELD = 6000
Share.MAX_WANT = 3000

local MAX_STRING = 120
local MAX_MAP = 400
local MAX_NUMBER = 2 ^ 31

--------------------------------------------------------------------------------
-- What is shared
--------------------------------------------------------------------------------

local function Set(list)
    local set = {}
    for _, name in ipairs(list) do set[name] = true end
    return set
end

-- Each record's fields: strings and fill numbers are taken only when the
-- field is empty, `add` numbers are added, `min` and `max` widen. A map's
-- value is "count" (a number to add) or the spec of its entries.
local ITEM_DROP = { strings = Set { "name" }, add = Set { "count", "corpses" }, fill = Set { "id" } }
local ITEM_NODE = { add = Set { "gathers", "count" }, fill = Set { "id" } }
local ITEM_CAST = { add = Set { "casts", "count" }, fill = Set { "id" } }

local SECTIONS = {
    { key = "h", what = "drop rates",
      spec = { strings = Set { "mob", "zone", "location" }, add = Set { "corpses" },
               min = Set { "minLevel" }, max = Set { "maxLevel" }, fill = Set { "npc" },
               coords = true, maps = { items = ITEM_DROP } } },
    { key = "g", what = "gathering",
      spec = { strings = Set { "zone", "location", "node", "kind" }, add = Set { "gathers" },
               coords = true, maps = { items = ITEM_NODE } } },
    { key = "f", what = "fishing",
      spec = { strings = Set { "zone", "location", "school" }, add = Set { "casts" },
               min = Set { "minSkill" }, max = Set { "maxSkill" },
               coords = true, maps = { items = ITEM_CAST } } },
    { key = "k", what = "kills",
      spec = { add = Set { "kills", "copper", "coinKills" },
               maps = { items = "count", qty = "count", stacks = "count", places = "count" } } },
}
Share.SECTIONS = SECTIONS

local BY_KEY = {}
for _, section in ipairs(SECTIONS) do BY_KEY[section.key] = section end

--- The saved table a section lives in; made if `create`.
function Share.Store(key, create)
    local db = ns.db
    if type(db) ~= "table" then return nil end

    if key == "h" then
        local records = ns.Harvest and ns.Harvest.records
        if type(records) ~= "table" and create then records = {} end
        return records
    elseif key == "g" then
        if create and ns.Gathering then return ns.Gathering:Store() end
        return type(db.gathering) == "table" and db.gathering.nodes or nil
    elseif key == "f" then
        if create and ns.Fishing then return ns.Fishing:Store() end
        return type(db.fishing) == "table" and db.fishing.spots or nil
    elseif key == "k" then
        if create and ns.Tracker then return ns.Tracker:Store() end
        return type(db.tracker) == "table" and db.tracker.mobs or nil
    end
end

--- What a record's key must be, from its own fields: a record sent under any
--- other key is not taken, so nothing lands where the addon never looks.
local KEYS = {
    h = function(record) return record.mob and ("%s|%s|%s"):format(record.mob, record.zone or "?", record.location or "") end,
    g = function(record) return ("%s|%s|%s"):format(record.zone or "?", record.location or "", record.node or "?") end,
    f = function(record) return ("%s|%s|%s"):format(record.zone or "?", record.location or "", record.school or "") end,
    k = function(_, key) return key end,
}

--------------------------------------------------------------------------------
-- Checking what arrives
--------------------------------------------------------------------------------

local function CleanString(value)
    if type(value) ~= "string" then return nil end
    value = value:gsub("|", "")
    if value == "" or #value > MAX_STRING then return nil end
    return value
end

local function CleanNumber(value)
    if type(value) ~= "number" or value ~= value then return nil end
    if value < 0 or value > MAX_NUMBER then return nil end
    return value
end

local function CleanCoords(value)
    if type(value) ~= "table" then return nil end
    local x, y = value[1], value[2]
    if type(x) ~= "number" or type(y) ~= "number" or x ~= x or y ~= y then return nil end
    if math.abs(x) > 1e6 or math.abs(y) > 1e6 then return nil end
    return { x, y }
end

local function CleanRecord(spec, value)
    if type(value) ~= "table" then return nil end
    local out = {}

    for field in pairs(spec.strings or {}) do
        local text = CleanString(value[field])
        if text then out[field] = text end
    end
    for _, group in ipairs { spec.add or {}, spec.min or {}, spec.max or {}, spec.fill or {} } do
        for field in pairs(group) do
            local number = CleanNumber(value[field])
            if number then out[field] = number end
        end
    end
    if spec.coords then out.coords = CleanCoords(value.coords) end

    for field, sub in pairs(spec.maps or {}) do
        local map = value[field]
        if type(map) == "table" then
            local clean, count = {}, 0
            for name, entry in pairs(map) do
                local key = count < MAX_MAP and CleanString(name)
                if key then
                    local cleaned
                    if sub == "count" then cleaned = CleanNumber(entry) else cleaned = CleanRecord(sub, entry) end
                    if cleaned ~= nil then
                        clean[key] = cleaned
                        count = count + 1
                    end
                end
            end
            out[field] = clean
        end
    end
    return out
end
Share.CleanRecord = CleanRecord

--------------------------------------------------------------------------------
-- Taking a partner's counts
--------------------------------------------------------------------------------

--- Add what is new in `inn` (a checked record) to `own`, keeping in `credit`
--- the most of each number ever taken.
-- @return true when a count went up
local function Merge(spec, own, inn, credit)
    local added = false

    for field in pairs(spec.add or {}) do
        local value = inn[field]
        if value then
            local seen = credit[field] or 0
            if value > seen then
                own[field] = (tonumber(own[field]) or 0) + (value - seen)
                credit[field] = value
                added = true
            end
        end
    end
    for field in pairs(spec.min or {}) do
        if inn[field] then own[field] = math.min(tonumber(own[field]) or inn[field], inn[field]) end
    end
    for field in pairs(spec.max or {}) do
        if inn[field] then own[field] = math.max(tonumber(own[field]) or inn[field], inn[field]) end
    end
    for field in pairs(spec.fill or {}) do
        if own[field] == nil and inn[field] then own[field] = inn[field] end
    end
    for field in pairs(spec.strings or {}) do
        if own[field] == nil and inn[field] then own[field] = inn[field] end
    end
    if spec.coords and own.coords == nil and inn.coords then own.coords = inn.coords end

    for field, sub in pairs(spec.maps or {}) do
        local map = inn[field]
        if map then
            if type(own[field]) ~= "table" then own[field] = {} end
            if type(credit[field]) ~= "table" then credit[field] = {} end
            for name, entry in pairs(map) do
                if sub == "count" then
                    local seen = credit[field][name] or 0
                    if entry > seen then
                        own[field][name] = (tonumber(own[field][name]) or 0) + (entry - seen)
                        credit[field][name] = entry
                        added = true
                    end
                else
                    if type(own[field][name]) ~= "table" then own[field][name] = {} end
                    if type(credit[field][name]) ~= "table" then credit[field][name] = {} end
                    if Merge(sub, own[field][name], entry, credit[field][name]) then added = true end
                end
            end
        end
    end
    return added
end
Share.Merge = Merge

--- The record to take counts into, made if it is new. A kill tally goes
--- through the tracker, which sets a tally from before coin was counted
--- over kills aside first, so merged kills never skew an old average.
local function OwnRecord(section, store, key, record)
    local own = store[key]
    if section.key == "k" and ns.Tracker then
        return ns.Tracker:GetMob(key)
    end
    if type(own) ~= "table" then
        own = {}
        for field in pairs(section.spec.strings or {}) do own[field] = record[field] end
        for field in pairs(section.spec.add or {}) do own[field] = 0 end
        for field in pairs(section.spec.maps or {}) do own[field] = {} end
        store[key] = own
    end
    return own
end

--------------------------------------------------------------------------------
-- What this side sends
--------------------------------------------------------------------------------

--- This side's own counts for one record: the totals less everything taken
--- from partners (`credits`, one per partner, any may be nil).
-- @return the record to send, and whether any count of it is this side's own
local function Export(spec, data, credits)
    local out, any = {}, false

    for _, group in ipairs { spec.strings or {}, spec.min or {}, spec.max or {}, spec.fill or {} } do
        for field in pairs(group) do
            if data[field] ~= nil then out[field] = data[field] end
        end
    end
    if spec.coords and type(data.coords) == "table" then
        out.coords = { data.coords[1], data.coords[2] }
    end

    for field in pairs(spec.add or {}) do
        local value = tonumber(data[field])
        if value then
            for _, credit in ipairs(credits) do value = value - (tonumber(credit[field]) or 0) end
            if value > 0 then out[field] = value any = true else out[field] = 0 end
        end
    end

    for field, sub in pairs(spec.maps or {}) do
        local map = data[field]
        if type(map) == "table" then
            local sent = {}
            for name, entry in pairs(map) do
                if type(name) == "string" then
                    if sub == "count" then
                        local value = tonumber(entry)
                        if value then
                            for _, credit in ipairs(credits) do
                                local taken = type(credit[field]) == "table" and tonumber(credit[field][name])
                                value = value - (taken or 0)
                            end
                            if value > 0 then sent[name] = value any = true end
                        end
                    elseif type(entry) == "table" then
                        local subs = {}
                        for _, credit in ipairs(credits) do
                            local held = type(credit[field]) == "table" and credit[field][name]
                            if type(held) == "table" then subs[#subs + 1] = held end
                        end
                        local record, subAny = Export(sub, entry, subs)
                        if subAny then sent[name] = record any = true end
                    end
                end
            end
            out[field] = sent
        end
    end
    return out, any
end
Share.Export = Export

--------------------------------------------------------------------------------
-- Partners
--------------------------------------------------------------------------------

Share.partners = {}   -- name key -> { name, online, heardAt, manifestAt, ... }

function Share:Enabled()
    return ns.db ~= nil and ns.db.shareData == true and #self:GetPartners() > 0
end

--- The names typed in Settings, as { key = "ana smith", name = "Ana Smith" }.
function Share:GetPartners()
    local list, seen = {}, {}
    local text = ns.db and ns.db.shareNames
    if type(text) ~= "string" then return list end

    for part in text:gmatch("[^,;]+") do
        local name = part:gsub("^%s+", ""):gsub("%s+$", "")
        local key = Comm.NameKey(name)
        if key and not seen[key] and #name <= 48 then
            seen[key] = true
            list[#list + 1] = { key = key, name = name }
        end
    end
    return list
end

--- The partner a sender is, or nil for anyone else.
function Share:PartnerFor(sender)
    if not self:Enabled() then return nil end
    local key = Comm.NameKey(sender)
    if not key or Comm.IsMe(sender) then return nil end
    for _, partner in ipairs(self:GetPartners()) do
        if partner.key == key then
            local state = self.partners[key]
            if not state then
                state = { name = partner.name, key = key }
                self.partners[key] = state
            end
            state.name = partner.name
            return state
        end
    end
    return nil
end

--- What was heard from and taken from a partner, made if new.
function Share:Held(state)
    if type(ns.db.shareIn) ~= "table" then ns.db.shareIn = {} end
    local held = ns.db.shareIn[state.key]
    if type(held) ~= "table" then
        held = {}
        ns.db.shareIn[state.key] = held
    end
    held.name = state.name
    if type(held.hashes) ~= "table" then held.hashes = {} end
    if type(held.credit) ~= "table" then held.credit = {} end
    for _, section in ipairs(SECTIONS) do
        if type(held.hashes[section.key]) ~= "table" then held.hashes[section.key] = {} end
        if type(held.credit[section.key]) ~= "table" then held.credit[section.key] = {} end
    end
    return held
end

--- Every partner's taken counts for one record, to be left out of what is
--- sent. Includes partners no longer named: taken is taken.
local function CreditsFor(section, key)
    local list = {}
    for _, held in pairs(ns.db.shareIn or {}) do
        local taken = type(held) == "table" and type(held.credit) == "table"
            and type(held.credit[section.key]) == "table" and held.credit[section.key][key]
        if type(taken) == "table" then list[#list + 1] = taken end
    end
    return list
end

local function InCombat()
    local ok, inCombat = pcall(InCombatLockdown)
    return ok and inCombat == true
end

--- Work through `list` a few at a time, a frame apart, then call `done`.
-- Waits out combat.
local function Slices(list, each, done)
    local index = 1
    local function Step()
        if InCombat() then C_Timer.After(2, Step) return end
        local stop = math.min(#list, index + Share.SLICE - 1)
        while index <= stop do
            pcall(each, list[index])
            index = index + 1
        end
        if index <= #list then C_Timer.After(0, Step) else done() end
    end
    Step()
end

--- What is this side's own, as { [section] = { [short key] = short hash } },
--- with the full keys kept in `state.keys` to look records up again.
function Share:Build(state, done)
    if state.building then
        state.building[#state.building + 1] = done
        return
    end
    state.building = { done }

    local manifest, keys, jobs = {}, {}, {}
    for _, section in ipairs(SECTIONS) do
        manifest[section.key], keys[section.key] = {}, {}
        local store = Share.Store(section.key)
        if type(store) == "table" then
            for key in pairs(store) do
                if type(key) == "string" then jobs[#jobs + 1] = { section = section, key = key } end
            end
        end
    end

    local counts = {}
    Slices(jobs, function(job)
        local section, key = job.section, job.key
        local store = Share.Store(section.key)
        local data = store and store[key]
        if type(data) ~= "table" then return end
        if (counts[section.key] or 0) >= Share.MAX_MANIFEST then return end

        local out, any = Export(section.spec, data, CreditsFor(section, key))
        if not any then return end
        local short = Comm.Hash(key)
        manifest[section.key][short] = Comm.Hash(Serialize.EncodeCanonical(out))
        keys[section.key][short] = key
        counts[section.key] = (counts[section.key] or 0) + 1
    end, function()
        state.keys = keys
        local waiting = state.building
        state.building = nil
        for _, fn in ipairs(waiting) do pcall(fn, manifest) end
    end)
end

--------------------------------------------------------------------------------
-- The conversation
--------------------------------------------------------------------------------
-- H hello, A hello back: the other side is there and paired.
-- M (table) manifest: [section] = { [short key] = hash of its own counts }.
-- W (table) want: [section] = { short key, ... } whose hash differs from the
--   copy held.
-- C (table) records: { { s = section, k = key, h = hash, d = record }, ... }.

local function Whisper(kind, text, target)
    return Comm:Send(kind, text, "WHISPER", target)
end

function Share:Hello(name)
    Whisper("H", ns.VERSION or "", name)
end

function Share:SendManifest(state)
    state.manifestAt = time()
    self:Build(state, function(manifest)
        if self:Enabled() then Comm:SendTable("M", manifest, "WHISPER", state.name) end
    end)
end

--- Say hello to every partner not yet heard from, and tell the ones who are
--- what this side has. Called now and then, and by Sync now.
function Share:Check()
    if not self:Enabled() then return end
    for _, partner in ipairs(self:GetPartners()) do
        local state = self.partners[partner.key] or { name = partner.name, key = partner.key }
        self.partners[partner.key] = state
        state.name = partner.name
        if state.online then
            -- Not on top of a transfer still going out: the partner asks
            -- again for whatever has not come.
            if Comm:Pending() == 0 and not (state.todo and #state.todo > 0) then
                self:SendManifest(state)
            end
        else
            self:Hello(partner.name)
        end
    end
end

function Share:OnHello(sender, _, channel, isReply)
    if channel ~= "WHISPER" then return end
    local state = self:PartnerFor(sender)
    if not state then return end

    state.online, state.heardAt = true, time()
    if not isReply then Whisper("A", ns.VERSION or "", state.name) end
    self:SendManifest(state)
end

function Share:OnManifest(sender, manifest, channel)
    if channel ~= "WHISPER" then return end
    local state = self:PartnerFor(sender)
    if not state then return end
    state.online, state.heardAt = true, time()

    -- Either side's check syncs both ways: answered with this side's own,
    -- unless one went out a moment ago (which is what stops the two
    -- answering each other for ever).
    if not state.manifestAt or time() - state.manifestAt > 60 then self:SendManifest(state) end

    local held = self:Held(state)
    local want, total = {}, 0
    for _, section in ipairs(SECTIONS) do
        local listed = type(manifest[section.key]) == "table" and manifest[section.key] or {}
        local mine = held.hashes[section.key]
        local asked = {}
        for short, hash in pairs(listed) do
            if type(short) == "string" and #short <= 12 and type(hash) == "string" and #hash <= 12
                and mine[short] ~= hash and total < Share.MAX_WANT then
                asked[#asked + 1] = short
                total = total + 1
            end
        end
        if #asked > 0 then want[section.key] = asked end
    end
    if total > 0 then Comm:SendTable("W", want, "WHISPER", state.name) end
end

function Share:OnWant(sender, want, channel)
    if channel ~= "WHISPER" then return end
    local state = self:PartnerFor(sender)
    if not state then return end

    local function Serve()
        local todo = {}
        for _, section in ipairs(SECTIONS) do
            local asked = want[section.key]
            local known = state.keys and state.keys[section.key]
            if type(asked) == "table" and known then
                for _, short in ipairs(asked) do
                    local key = type(short) == "string" and known[short]
                    if key and #todo < Share.MAX_WANT then todo[#todo + 1] = { section = section, key = key } end
                end
            end
        end
        state.todo = todo
        self:Serve(state)
    end

    if state.keys then Serve() else self:Build(state, Serve) end
end

--- Send what was asked for, a batch at a time as the pacing frees up.
function Share:Serve(state)
    if state.serving then return end
    state.serving = true

    local function Step()
        local todo = state.todo
        if not todo or #todo == 0 or not self:Enabled() then
            state.serving = false
            return
        end
        if Comm:Pending() > 12 or InCombat() then C_Timer.After(2, Step) return end

        local batch = {}
        while #todo > 0 and #batch < Share.BATCH do
            local job = table.remove(todo, 1)
            local store = Share.Store(job.section.key)
            local data = store and store[job.key]
            if type(data) == "table" then
                local out, any = Export(job.section.spec, data, CreditsFor(job.section, job.key))
                if any then
                    local hash = Comm.Hash(Serialize.EncodeCanonical(out))
                    batch[#batch + 1] = { s = job.section.key, k = job.key, h = hash, d = out }
                end
            end
        end
        if #batch > 0 then
            Comm:SendTable("C", batch, "WHISPER", state.name)
            state.sentAt = time()
        end
        C_Timer.After(0.5, Step)
    end
    Step()
end

--- Take one record a partner sent.
-- @return true, or nil and why it was refused
function Share:Accept(state, entry)
    if type(entry) ~= "table" then return nil, "not a record" end
    local section = type(entry.s) == "string" and BY_KEY[entry.s]
    if not section then return nil, "unknown kind" end

    -- A record's key joins its fields with "|", so it keeps them; it must
    -- then be exactly what the record's own fields make (below).
    local key = type(entry.k) == "string" and #entry.k >= 1 and #entry.k <= 3 * MAX_STRING + 2 and entry.k or nil
    if key and section.key == "k" and key:find("|", 1, true) then key = nil end
    local hash = type(entry.h) == "string" and #entry.h <= 12 and entry.h or nil
    local record = CleanRecord(section.spec, entry.d)
    if not (key and hash and record) then return nil, "unreadable" end
    if KEYS[section.key](record, key) ~= key then return nil, "wrong key" end

    local store = Share.Store(section.key, true)
    if type(store) ~= "table" then return nil, "no saved data" end

    local held = self:Held(state)
    local credit = held.credit[section.key]
    if credit[key] == nil then
        local count = 0
        for _ in pairs(credit) do count = count + 1 end
        if count >= Share.MAX_HELD then return nil, "too many" end
    end
    if type(credit[key]) ~= "table" then credit[key] = {} end

    local own = OwnRecord(section, store, key, record)
    Merge(section.spec, own, record, credit[key])
    held.hashes[section.key][Comm.Hash(key)] = hash
    held.at = time()
    return true
end

function Share:OnRecords(sender, batch, channel)
    if channel ~= "WHISPER" then return end
    local state = self:PartnerFor(sender)
    if not state then return end

    local taken = 0
    for index, entry in ipairs(batch) do
        if index > Share.BATCH * 4 then break end
        local ok, why = self:Accept(state, entry)
        if ok then taken = taken + 1 else ns.Debug("share: a record from", tostring(sender), "was not taken:", tostring(why)) end
    end
    if taken > 0 then
        state.receivedAt = time()
        self.taken = (self.taken or 0) + taken
        self:Changed()
    end
end

--- Windows showing counts catch up, once after a burst of records.
function Share:Changed()
    if self.refreshing then return end
    self.refreshing = true
    C_Timer.After(1, function()
        self.refreshing = nil
        if ns.TrackerUI and ns.TrackerUI.Refresh then pcall(ns.TrackerUI.Refresh, ns.TrackerUI) end
        if ns.UI and ns.UI.RefreshActive then pcall(ns.UI.RefreshActive, ns.UI) end
    end)
end

function Share:OnOffline(key)
    local state = self.partners[key]
    if state then state.online = false end
end

--------------------------------------------------------------------------------
-- Status, for Settings and /farm share
--------------------------------------------------------------------------------

--- How many records each partner's counts are held in: { [section] = n }.
function Share:CountTaken(key)
    local held = ns.db and ns.db.shareIn and ns.db.shareIn[key]
    local counts, total = {}, 0
    if type(held) == "table" and type(held.credit) == "table" then
        for _, section in ipairs(SECTIONS) do
            local n = 0
            for _ in pairs(type(held.credit[section.key]) == "table" and held.credit[section.key] or {}) do n = n + 1 end
            counts[section.key] = n
            total = total + n
        end
    end
    return total, counts
end

function Share:Describe()
    if not ns.db then return "" end
    local partners = self:GetPartners()
    if ns.db.shareData ~= true then return "Sharing is off." end
    if #partners == 0 then return "Sharing is on, but no character of your other account is named." end

    local parts = {}
    for _, partner in ipairs(partners) do
        local state = self.partners[partner.key] or {}
        local total = self:CountTaken(partner.key)
        parts[#parts + 1] = ("%s: %s, %d record%s taken"):format(
            partner.name, state.online and "online" or "not heard from this session",
            total, total == 1 and "" or "s")
    end
    local pending = Comm:Pending()
    if pending > 0 then
        parts[#parts + 1] = ("%d message%s waiting to go"):format(pending, pending == 1 and "" or "s")
    end
    return table.concat(parts, ".  ") .. "."
end

--------------------------------------------------------------------------------
-- Settings
--------------------------------------------------------------------------------

--- Start or stop listening to match the settings.
function Share:Apply()
    if self:Enabled() then
        Comm:Start()
        if not self.started then
            self.started = true
            C_Timer.After(20, function() Share:Check() end)
        end
    else
        Comm:Stop()
        for _, state in pairs(self.partners) do state.online = false end
    end
end

function Share:SetEnabled(on)
    ns.db.shareData = on == true
    self:Apply()
    if on then self:Check() end
end

function Share:SetNames(text)
    text = (text or ""):gsub("^%s+", ""):gsub("%s+$", "")
    ns.db.shareNames = text
    self:Apply()
    self:Check()
end

function Share:OnEnable()
    Comm:On("H", function(sender, body, channel) Share:OnHello(sender, body, channel, false) end)
    Comm:On("A", function(sender, body, channel) Share:OnHello(sender, body, channel, true) end)
    Comm:OnTable("M", function(...) Share:OnManifest(...) end)
    Comm:OnTable("W", function(...) Share:OnWant(...) end)
    Comm:OnTable("C", function(...) Share:OnRecords(...) end)
    Comm.onOffline = function(key) Share:OnOffline(key) end

    self:Apply()
    -- Now and then; nothing happens while sharing is off.
    self.ticker = C_Timer.NewTicker(self.CHECK_SECONDS, function() Share:Check() end)
end

ns.RegisterCommand("share", "share kills, drop rates and gathering with your other account: on, off, with <names>, sync",
    function(args)
        local word, rest = (args or ""):match("^(%S*)%s*(.-)%s*$")
        word = (word or ""):lower()

        if word == "on" or word == "off" then
            Share:SetEnabled(word == "on")
            ns.Print(word == "on" and "sharing with your other account is on" or "sharing with your other account is off")
        elseif word == "with" then
            Share:SetNames(rest)
            ns.Print(rest ~= "" and ("sharing with: " .. rest) or "no character named to share with")
        elseif word == "sync" then
            Share:Check()
            ns.Print(Share:Enabled() and "asked your other account for anything new" or "sharing is off, or no character is named")
        else
            ns.Print(Share:Describe())
        end
    end)
