-- Blackthornes Farmer -- Logic/Transfer.lua
-- Handing your counts to another player as text to copy, and taking theirs
-- in (asked 2026-10-11 by a player, agreed by the owner).
--
-- An addon cannot read or write files, so the way across is a string: you
-- press Give, copy it, send it any way you like; they paste it into Take,
-- see what it would add and press Apply.
--
-- It counts the same way account sharing does (Logic/Share.lua): the string
-- carries only what is yours (your totals less everything you have taken
-- from anyone), and the receiver adds only the rise over the most it has
-- ever taken from that string's source, kept in shareIn["import:<id>"]. So
-- the same string twice adds nothing, a newer string from the same source
-- adds only what grew, and nothing taken in is ever passed on. Removing an
-- import takes its counts back out, because the ledger says exactly what it
-- added.
--
-- The text is only ever read as data (Core/Serialize.lua never runs code),
-- every record goes through Share.CleanRecord and the key check, and
-- numbers and shapes that no real play makes are refused.

local _, ns = ...

local Transfer = ns.NewModule("Transfer")

local Share = ns.Share
local Serialize = ns.Serialize
local Comm = ns.Comm
local Parts = Share.Parts
local SECTIONS, BY_KEY, KEYS = Parts.SECTIONS, Parts.BY_KEY, Parts.KEYS

Transfer.PREFIX = "BFR1"
-- Raw (before base 64) bytes in one part, so a part is about 200,000
-- characters. A big collection comes as several parts, each complete in
-- itself, taken in any order.
Transfer.PART_RAW = 150000
Transfer.MAX_TEXT = 300000
Transfer.MAX_RECORDS = 20000     -- per section, per part
Transfer.MAX_COUNT = 1e8         -- no real tally reaches this
Transfer.MAX_PER_CORPSE = 1000   -- items in a drop record, per corpse
Transfer.STEP = 24000            -- bytes of text worked per frame

local CHARS = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local ENCODE, DECODE = {}, {}
for i = 1, #CHARS do
    local c = CHARS:sub(i, i)
    ENCODE[i - 1] = c
    DECODE[c] = i - 1
end

--------------------------------------------------------------------------------
-- Stepping
--------------------------------------------------------------------------------

--- Call `each(item)` for `count` steps, `per` a frame, waiting out combat.
local function Steps(count, per, each, done)
    local index = 1
    local function Step()
        if Parts.InCombat() then C_Timer.After(2, Step) return end
        local stop = math.min(count, index + per - 1)
        while index <= stop do
            each(index)
            index = index + 1
        end
        if index <= count then C_Timer.After(0, Step) else done() end
    end
    Step()
end

--- Rolling checksum, the same sum as Comm.Hash but carried between frames.
local function Roll(hash, text)
    for i = 1, #text do hash = (hash * 33 + text:byte(i)) % 4294967296 end
    return hash
end

local function Encode64(text, done)
    local pieces, groups = {}, math.ceil(#text / 3)
    local per = math.floor(Transfer.STEP / 3)
    local steps = math.ceil(groups / per)
    Steps(steps, 1, function(step)
        local out = {}
        for g = (step - 1) * per, math.min(groups, step * per) - 1 do
            local a, b, c = text:byte(g * 3 + 1, g * 3 + 3)
            local n = a * 65536 + (b or 0) * 256 + (c or 0)
            local d1 = math.floor(n / 262144)
            local d2 = math.floor(n / 4096) % 64
            local d3 = math.floor(n / 64) % 64
            local d4 = n % 64
            out[#out + 1] = ENCODE[d1] .. ENCODE[d2] .. (b and ENCODE[d3] or "=") .. (c and ENCODE[d4] or "=")
        end
        pieces[#pieces + 1] = table.concat(out)
    end, function() done(table.concat(pieces)) end)
end

--- Text from base 64, checked as it goes.
local function Decode64(text, done)
    if #text % 4 ~= 0 then done(nil) return end
    local pieces, groups = {}, #text / 4
    local per = math.floor(Transfer.STEP / 3)
    local steps = math.ceil(groups / per)
    local bad = false
    Steps(steps, 1, function(step)
        if bad then return end
        local out = {}
        for g = (step - 1) * per, math.min(groups, step * per) - 1 do
            local a, b, c, d = text:sub(g * 4 + 1, g * 4 + 4):match("^(.)(.)(.)(.)$")
            local v1, v2 = DECODE[a], DECODE[b]
            local v3 = c == "=" and 0 or DECODE[c]
            local v4 = d == "=" and 0 or DECODE[d]
            if not (v1 and v2 and v3 and v4) or (c == "=" and d ~= "=") or (g < groups - 1 and (c == "=" or d == "=")) then
                bad = true
                return
            end
            local n = v1 * 262144 + v2 * 4096 + v3 * 64 + v4
            local piece = string.char(math.floor(n / 65536))
            if c ~= "=" then piece = piece .. string.char(math.floor(n / 256) % 256) end
            if d ~= "=" then piece = piece .. string.char(n % 256) end
            out[#out + 1] = piece
        end
        pieces[#pieces + 1] = table.concat(out)
    end, function() done((not bad) and table.concat(pieces) or nil) end)
end
Transfer.Encode64, Transfer.Decode64 = Encode64, Decode64

--------------------------------------------------------------------------------
-- Counting
--------------------------------------------------------------------------------

--- How much of a checked record is new over `credit` (what was already taken
--- from this source), and the biggest count in it.
local function Scan(spec, record, credit)
    local rise, biggest = 0, 0
    credit = type(credit) == "table" and credit or {}

    for field in pairs(spec.add or {}) do
        local value = record[field]
        if value then
            if value > biggest then biggest = value end
            local seen = tonumber(credit[field]) or 0
            if value > seen then rise = rise + (value - seen) end
        end
    end
    for field, sub in pairs(spec.maps or {}) do
        local map = record[field]
        if type(map) == "table" then
            local held = type(credit[field]) == "table" and credit[field] or {}
            for name, entry in pairs(map) do
                if sub == "count" then
                    if entry > biggest then biggest = entry end
                    local seen = tonumber(held[name]) or 0
                    if entry > seen then rise = rise + (entry - seen) end
                else
                    local r, b = Scan(sub, entry, held[name])
                    rise = rise + r
                    if b > biggest then biggest = b end
                end
            end
        end
    end
    return rise, biggest
end

--- A drop record whose items outnumber its corpses a thousand to one is not
--- play. Only the drop section can say.
local function Plausible(section, record)
    if section.key ~= "h" then return true end
    local limit = Transfer.MAX_PER_CORPSE * math.max(tonumber(record.corpses) or 0, 1)
    for _, item in pairs(record.items or {}) do
        if (item.count or 0) > limit then return false end
    end
    return true
end

local function Subtract(spec, record, credit)
    for field in pairs(spec.add or {}) do
        local taken = tonumber(credit[field])
        if taken and tonumber(record[field]) then record[field] = math.max(0, record[field] - taken) end
    end
    for field, sub in pairs(spec.maps or {}) do
        local map, held = record[field], credit[field]
        if type(map) == "table" and type(held) == "table" then
            for name, taken in pairs(held) do
                if sub == "count" then
                    if tonumber(map[name]) and tonumber(taken) then
                        map[name] = math.max(0, map[name] - taken)
                        if map[name] == 0 then map[name] = nil end
                    end
                elseif type(map[name]) == "table" and type(taken) == "table" then
                    Subtract(sub, map[name], taken)
                end
            end
        end
    end
end

--- True when nothing of the record's counts is left.
local function Empty(spec, record)
    for field in pairs(spec.add or {}) do
        if (tonumber(record[field]) or 0) > 0 then return false end
    end
    for field, sub in pairs(spec.maps or {}) do
        local map = record[field]
        if type(map) == "table" then
            for _, entry in pairs(map) do
                if sub == "count" then
                    if (tonumber(entry) or 0) > 0 then return false end
                elseif type(entry) == "table" and not Empty(sub, entry) then
                    return false
                end
            end
        end
    end
    return true
end

--------------------------------------------------------------------------------
-- Giving
--------------------------------------------------------------------------------

--- This Farmer's own id, made once and kept: it names the source of every
--- string it hands out, so a receiver can tell a newer one from a repeat.
function Transfer:SourceId()
    local db = ns.db
    if type(db.exportId) ~= "string" or not db.exportId:match("^%x+$") or #db.exportId < 6 then
        local id = {}
        for i = 1, 12 do id[i] = ("%x"):format(math.random(0, 15)) end
        db.exportId = table.concat(id)
    end
    return db.exportId
end

--- Build the strings to hand over: a list of parts, each a line of text.
-- `done(parts)` or `done(nil, why)`. Never in combat, a few at a frame.
function Transfer:Make(done)
    if self.making then return done(nil, "already making one") end
    self.making = true
    local function Finish(parts, why)
        self.making = nil
        done(parts, why)
    end

    local jobs = {}
    for _, section in ipairs(SECTIONS) do
        local store = Share.Store(section.key)
        if type(store) == "table" then
            for key in pairs(store) do
                if type(key) == "string" then jobs[#jobs + 1] = { section = section, key = key } end
            end
        end
    end

    local entries = {}
    Steps(#jobs, Share.SLICE, function(index)
        local job = jobs[index]
        local store = Share.Store(job.section.key)
        local data = store and store[job.key]
        if type(data) ~= "table" then return end
        local ok, out, any = pcall(Share.Export, job.section.spec, data, Parts.CreditsFor(job.section, job.key))
        if ok and any then
            entries[#entries + 1] = { s = job.section.key, k = job.key, d = out,
                size = #Serialize.Encode(out) + #job.key + 12 }
        end
    end, function()
        if #entries == 0 then return Finish(nil, "nothing of yours to give yet") end

        -- Split into parts of about PART_RAW bytes.
        local bins, current, bytes = {}, {}, 0
        for _, entry in ipairs(entries) do
            if bytes + entry.size > Transfer.PART_RAW and #current > 0 then
                bins[#bins + 1] = current
                current, bytes = {}, 0
            end
            current[#current + 1] = entry
            bytes = bytes + entry.size
        end
        bins[#bins + 1] = current

        local id, at = self:SourceId(), time()
        local parts = {}
        local function Next(n)
            if n > #bins then return Finish(parts) end
            local payload = { v = 1, id = id, at = at, s = { h = {}, g = {}, f = {}, k = {} } }
            for _, entry in ipairs(bins[n]) do payload.s[entry.s][entry.k] = entry.d end
            Encode64(Serialize.Encode(payload), function(b64)
                local sum, pos = 5381, 1
                -- Checksummed a frame's worth at a time.
                local steps = math.ceil(#b64 / Transfer.STEP)
                Steps(steps, 1, function()
                    sum = Roll(sum, b64:sub(pos, pos + Transfer.STEP - 1))
                    pos = pos + Transfer.STEP
                end, function()
                    parts[n] = ("%s:%s:%d/%d:%s:%s"):format(Transfer.PREFIX, id, n, #bins, Comm.ToBase36(sum), b64)
                    Next(n + 1)
                end)
            end)
        end
        Next(1)
    end)
end

--------------------------------------------------------------------------------
-- Taking
--------------------------------------------------------------------------------

local function ShortDate(at)
    local ok, text = pcall(date, "%d %b %Y", at)
    return ok and text or "an unknown date"
end

function Transfer.LedgerKey(id) return "import:" .. id end

--- Read, check and measure a pasted string without changing anything.
-- `done(plan)` or `done(nil, why)`. A plan: { id, part, of, at, list, sections
-- = { [key] = { records, new, rise } }, skipped }.
function Transfer:Parse(text, done)
    if type(text) ~= "string" then return done(nil, "Nothing pasted.") end
    text = text:gsub("%s+", "")
    if text == "" then return done(nil, "Nothing pasted.") end
    if #text > Transfer.MAX_TEXT then return done(nil, "That is too long to be one of ours.") end

    local id, n, of, sum, body = text:match("^" .. Transfer.PREFIX .. ":(%x+):(%d+)/(%d+):(%w+):([A-Za-z0-9+/=]+)$")
    if not id then return done(nil, "That does not look like a Farmer data string. Copy the whole line, from BFR1 to the end.") end
    n, of = tonumber(n), tonumber(of)
    if #id < 6 or #id > 16 or not (n and of and n >= 1 and n <= of and of <= 100) then
        return done(nil, "That string is damaged.")
    end
    if id == self:SourceId() then
        return done(nil, "That is your own data. There is nothing to take.")
    end

    -- Checksum first: a half-copied string stops here.
    local hash, pos = 5381, 1
    Steps(math.ceil(#body / Transfer.STEP), 1, function()
        hash = Roll(hash, body:sub(pos, pos + Transfer.STEP - 1))
        pos = pos + Transfer.STEP
    end, function()
        if Comm.ToBase36(hash) ~= sum then
            return done(nil, "Part of the string was lost in copying. Copy it again, the whole line.")
        end
        Decode64(body, function(raw)
            if not raw then return done(nil, "That string is damaged.") end
            local ok, payload = Serialize.Decode(raw)
            if not (ok and type(payload) == "table" and payload.v == 1 and payload.id == id
                and type(payload.s) == "table") then
                return done(nil, "That string is from a version of Farmer this one cannot read.")
            end
            self:Measure(payload, id, n, of, done)
        end)
    end)
end

function Transfer:Measure(payload, id, n, of, done)
    local held = ns.db.shareIn and ns.db.shareIn[Transfer.LedgerKey(id)]
    local credit = type(held) == "table" and type(held.credit) == "table" and held.credit or {}

    local plan = { id = id, part = n, of = of, at = tonumber(payload.at), list = {}, sections = {}, skipped = 0 }
    local candidates = {}
    for _, section in ipairs(SECTIONS) do
        plan.sections[section.key] = { records = 0, new = 0, rise = 0 }
        local source = payload.s[section.key]
        if type(source) == "table" then
            local count = 0
            for key, record in pairs(source) do
                if type(key) == "string" then
                    count = count + 1
                    if count <= Transfer.MAX_RECORDS then
                        candidates[#candidates + 1] = { section = section, key = key, record = record }
                    else
                        plan.skipped = plan.skipped + 1
                    end
                end
            end
        end
    end

    Steps(#candidates, Share.SLICE, function(index)
        local c = candidates[index]
        local section, key = c.section, c.key
        local record = Parts.CleanRecord(section.spec, c.record)
        local good = record and #key >= 1 and #key <= 3 * Parts.MAX_STRING + 2
            and not (section.key == "k" and key:find("|", 1, true))
            and KEYS[section.key](record, key) == key
            and Plausible(section, record)
        local rise, biggest
        if good then
            local sectionCredit = type(credit[section.key]) == "table" and credit[section.key] or {}
            rise, biggest = Scan(section.spec, record, sectionCredit[key])
            good = biggest <= Transfer.MAX_COUNT
        end
        if not good then plan.skipped = plan.skipped + 1 return end

        local totals = plan.sections[section.key]
        totals.records = totals.records + 1
        totals.rise = totals.rise + rise
        local store = Share.Store(section.key)
        if not (type(store) == "table" and store[key] ~= nil) then totals.new = totals.new + 1 end
        if rise > 0 or not (type(store) == "table" and store[key] ~= nil) then
            plan.list[#plan.list + 1] = { section = section, key = key, record = record }
        end
    end, function() done(plan) end)
end

--- What a plan would do, in words.
function Transfer.Describe(plan)
    local lines, total = {}, 0
    for _, section in ipairs(SECTIONS) do
        local t = plan.sections[section.key]
        if t and t.records > 0 then
            total = total + t.rise
            lines[#lines + 1] = ("%s: %d record%s (%d new), %d count%s to add"):format(
                section.what, t.records, t.records == 1 and "" or "s", t.new, t.rise, t.rise == 1 and "" or "s")
        end
    end
    local head = ("From %s, %s%s."):format(
        plan.at and ("data made " .. ShortDate(plan.at)) or "an unknown date",
        plan.of > 1 and ("part %d of %d"):format(plan.part, plan.of) or "all of it", "")
    if #lines == 0 then lines[1] = "Nothing in it could be read." end
    if total == 0 and #plan.list == 0 then lines[#lines + 1] = "You already have all of this. Nothing new to add." end
    if plan.skipped > 0 then
        lines[#lines + 1] = ("%d record%s did not look right and will be left out."):format(
            plan.skipped, plan.skipped == 1 and "" or "s")
    end
    return head .. "\n" .. table.concat(lines, "\n"), total
end

--- Take a measured plan in. `done(records)`.
function Transfer:Apply(plan, done)
    if self.applying then return done(0) end
    self.applying = true

    local state = { key = Transfer.LedgerKey(plan.id), name = "Imported " .. plan.id }
    local held = Share:Held(state)
    held.kind = "import"
    held.at = time()
    held.madeAt = plan.at

    local taken = 0
    Steps(#plan.list, Share.SLICE, function(index)
        local item = plan.list[index]
        local section, key, record = item.section, item.key, item.record
        local store = Share.Store(section.key, true)
        if type(store) ~= "table" then return end
        local credit = held.credit[section.key]
        if credit[key] == nil then
            local count = 0
            for _ in pairs(credit) do count = count + 1 end
            if count >= Transfer.MAX_RECORDS * 2 then return end
        end
        if type(credit[key]) ~= "table" then credit[key] = {} end
        local own = Parts.OwnRecord(section, store, key, record)
        Share.Merge(section.spec, own, record, credit[key])
        taken = taken + 1
    end, function()
        self.applying = nil
        Share:Changed()
        done(taken)
    end)
end

--- The imports on record, newest first: { { id, at, records } }.
function Transfer:List()
    local list = {}
    for key, held in pairs(ns.db and ns.db.shareIn or {}) do
        if type(held) == "table" and held.kind == "import" and type(key) == "string" then
            local records = 0
            for _, section in ipairs(SECTIONS) do
                for _ in pairs(type(held.credit) == "table" and type(held.credit[section.key]) == "table"
                    and held.credit[section.key] or {}) do records = records + 1 end
            end
            list[#list + 1] = { id = key:gsub("^import:", ""), key = key, at = tonumber(held.at) or 0,
                madeAt = tonumber(held.madeAt), records = records }
        end
    end
    table.sort(list, function(a, b) return a.at > b.at end)
    return list
end

--- Take everything an import added back out, exactly as the ledger has it.
-- `done(records)`.
function Transfer:Remove(id, done)
    local key = Transfer.LedgerKey(id)
    local held = ns.db.shareIn and ns.db.shareIn[key]
    if not (type(held) == "table" and held.kind == "import" and type(held.credit) == "table") then
        return done(0)
    end

    local jobs = {}
    for _, section in ipairs(SECTIONS) do
        for recordKey, credit in pairs(type(held.credit[section.key]) == "table" and held.credit[section.key] or {}) do
            jobs[#jobs + 1] = { section = section, key = recordKey, credit = credit }
        end
    end

    Steps(#jobs, Share.SLICE, function(index)
        local job = jobs[index]
        local store = Share.Store(job.section.key)
        local own = type(store) == "table" and store[job.key]
        if type(own) ~= "table" or type(job.credit) ~= "table" then return end
        Subtract(job.section.spec, own, job.credit)
        if Empty(job.section.spec, own) then store[job.key] = nil end
    end, function()
        ns.db.shareIn[key] = nil
        Share:Changed()
        done(#jobs)
    end)
end

--------------------------------------------------------------------------------
-- Commands
--------------------------------------------------------------------------------

--- Make the strings and show them, selected and ready to copy.
function Transfer:Give()
    if not ns.UI then return end
    ns.Print("making your data string...")
    self:Make(function(parts, why)
        if not parts then ns.Print(why or "could not make one") return end
        local index = 1
        local function Show()
            local title = #parts > 1 and ("Give my data, part %d of %d"):format(index, #parts) or "Give my data"
            ns.UI:ShowExport(parts[index], title, #parts > 1 and {
                index = index, count = #parts,
                step = function(delta)
                    index = math.max(1, math.min(#parts, index + delta))
                    Show()
                end,
            } or nil)
        end
        Show()
    end)
end

ns.RegisterCommand("give", "make your counts into text to copy and send to another player",
    function() Transfer:Give() end)
ns.RegisterCommand("take", "take another player's counts in: paste what they sent you",
    function()
        if ns.UI and ns.UI.ShowImport then ns.UI:ShowImport() end
    end)
