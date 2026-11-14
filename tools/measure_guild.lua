-- Counts how big the guild's ledgers are in a Farmer save. Read only: it
-- loads the save into a table of its own and changes nothing.
--
--   lua5.1 tools/measure_guild.lua <path to Blackthornes_Farmer.lua>
--
-- Prints, for guildDrops and each ledger in guildIn, how many records and
-- how many numbers it holds, so we can see whether the ledgers are worth
-- a smaller shape before anything is changed.

local path = arg and arg[1]
if not path then
    print("usage: lua5.1 tools/measure_guild.lua <Blackthornes_Farmer.lua>")
    os.exit(1)
end

local chunk, err = loadfile(path)
if not chunk then print(err) os.exit(1) end
local saved = {}
setfenv(chunk, saved)
local ok, why = pcall(chunk)
if not ok then print(why) os.exit(1) end

local db = saved.BlackthornesFarmerDB
if type(db) ~= "table" then print("no BlackthornesFarmerDB in that file") os.exit(1) end

-- Tables and numbers below a value, counted all the way down.
local function Count(value)
    local tables, numbers, strings = 0, 0, 0
    local function Walk(v)
        if type(v) == "table" then
            tables = tables + 1
            for k, sub in pairs(v) do
                if type(k) == "string" then strings = strings + 1 end
                Walk(sub)
            end
        elseif type(v) == "number" then
            numbers = numbers + 1
        elseif type(v) == "string" then
            strings = strings + 1
        end
    end
    Walk(value)
    return tables, numbers, strings
end

local function Records(value)
    local n = 0
    if type(value) == "table" then for _ in pairs(value) do n = n + 1 end end
    return n
end

local t, n, s = Count(db.guildDrops)
print(("guildDrops: %d records, %d tables, %d numbers, %d strings"):format(
    Records(db.guildDrops), t, n, s))

local all = { 0, 0, 0 }
local ledgers = 0
for key, held in pairs(type(db.guildIn) == "table" and db.guildIn or {}) do
    ledgers = ledgers + 1
    local credit = type(held) == "table" and held.credit or nil
    local hashes = type(held) == "table" and held.hashes or nil
    local ct, cn, cs = Count(credit)
    local ht, hn, hs = Count(hashes)
    all[1], all[2], all[3] = all[1] + ct + ht, all[2] + cn + hn, all[3] + cs + hs
    print(("  %s: %d drop records in credit (%d tables, %d numbers), %d hashes"):format(
        tostring(key):sub(1, 16), Records(type(credit) == "table" and credit.h), ct, cn,
        Records(type(hashes) == "table" and hashes.h)))
end
print(("guildIn: %d ledgers, %d tables, %d numbers, %d strings"):format(
    ledgers, all[1], all[2], all[3]))
