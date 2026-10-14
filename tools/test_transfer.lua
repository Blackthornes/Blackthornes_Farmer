-- Handing counts to another player as text, and taking theirs in
-- (Logic/Transfer.lua, asked 2026-10-11).
--
-- What matters: the text round-trips; the same text twice adds nothing and a
-- newer one adds only what grew; what was taken in is never handed on; a
-- damaged, forged or oddly shaped string is refused or trimmed, never run;
-- nothing changes before Apply; and Remove takes back exactly what an import
-- added, leaving your own counts alone.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("transfer")

local ns = env.Load()
local Share, Transfer, Serialize, Comm = ns.Share, ns.Transfer, ns.Serialize, ns.Comm

suite.check("the module is loaded", Transfer ~= nil)

_G.time = _G.time or function() return 1000000 end
_G.date = _G.date or function() return "11 Oct" end
_G.InCombatLockdown = function() return false end

--------------------------------------------------------------------------------
-- Two players
--------------------------------------------------------------------------------

local function Player()
    local db = {}
    for key, value in pairs(ns.DEFAULTS) do db[key] = value end
    db.tracker = { mobs = {} }
    db.gathering = { nodes = {}, spots = {} }
    db.fishing = { spots = {} }
    return { db = db, records = {} }
end
local ana, bob = Player(), Player()
local function Switch(p)
    ns.db = p.db
    ns.Harvest.records = p.records
    p.db.harvest = p.records
end

local function Tally(kills, copper, items)
    return { kills = kills, copper = copper, coinKills = kills, items = items or {}, qty = {}, stacks = {}, places = {} }
end
local function Wolf(corpses, pelts)
    return {
        mob = "Wolf", zone = "Elwynn Forest", location = "Northshire", minLevel = 1, maxLevel = 3,
        corpses = corpses, coords = { 0.4, 0.5 },
        items = { ["Wolf Pelt"] = { name = "Wolf Pelt", count = pelts, corpses = corpses, id = 1 } },
    }
end
local WOLF = "Wolf|Elwynn Forest|Northshire"

Switch(ana)
ana.records[WOLF] = Wolf(30, 12)
ana.db.tracker.mobs.Wolf = Tally(40, 4000, { Pelt = 8 })
ana.db.gathering.nodes["Elwynn Forest|Northshire|Peacebloom"] = {
    zone = "Elwynn Forest", location = "Northshire", node = "Peacebloom", kind = "herb",
    gathers = 7, items = { Peacebloom = { gathers = 7, count = 9, id = 2447 } },
}
Switch(bob)
bob.records[WOLF] = Wolf(20, 5)
bob.db.tracker.mobs.Wolf = Tally(25, 2500)
bob.records["Boar|Westfall|"] = { mob = "Boar", zone = "Westfall", location = "", corpses = 4, items = {} }

local function Give()
    local out, why
    Transfer:Make(function(parts, reason) out, why = parts, reason end)
    return out, why
end
local function Read(text)
    local plan, why
    Transfer:Parse(text, function(p, w) plan, why = p, w end)
    return plan, why
end
local function Take(text)
    local plan, why = Read(text)
    if not plan then return nil, why end
    local taken
    Transfer:Apply(plan, function(n) taken = n end)
    return taken, plan
end

--------------------------------------------------------------------------------
-- The text itself
--------------------------------------------------------------------------------

do
    local samples = { "a", "ab", "abc", "abcd", "", ("x"):rep(100000), "t\0\1\2\255\254|\n" }
    local good = true
    for _, sample in ipairs(samples) do
        local back
        Transfer.Encode64(sample, function(b64) Transfer.Decode64(b64, function(text) back = text end) end)
        if back ~= sample then good = false end
    end
    suite.check("base 64 round-trips every length, a long run and odd bytes", good)

    local bad
    Transfer.Decode64("ab*d", function(text) bad = text end)
    suite.check("a character outside base 64 is refused", bad == nil)
    Transfer.Decode64("abc", function(text) bad = text end)
    suite.check("so is a length that cannot be", bad == nil)
end

--------------------------------------------------------------------------------
-- Giving and taking
--------------------------------------------------------------------------------

Switch(ana)
local parts, why = Give()
suite.check("a string is made", parts and #parts == 1, why)
local anaText = parts[1]
suite.check("one line, in our format", not anaText:find("[%s|]") and anaText:match("^BFR1:%x+:1/1:%w+:") ~= nil)
suite.check("no character name or setting is in it", not anaText:find("Ana", 1, true) and not anaText:find("shareNames", 1, true))

Switch(bob)
do
    local before = bob.records[WOLF].corpses
    local plan = Read(anaText)
    suite.check("it reads", plan ~= nil)
    suite.check("reading changes nothing", bob.records[WOLF].corpses == before and bob.db.shareIn == nil)
    local text = Transfer.Describe(plan)
    suite.check("the preview says what it would add", text:find("drop rates", 1, true) and text:find("kills", 1, true)
        and text:find("gathering", 1, true), text)
    suite.check("with counts to add", plan.sections.h.rise > 0 and plan.sections.k.rise > 0 and plan.sections.g.new == 1)

    local taken = Take(anaText)
    suite.check("applied", taken == 3, taken)
    suite.check("drop rates add up", bob.records[WOLF].corpses == 50 and bob.records[WOLF].items["Wolf Pelt"].count == 17,
        bob.records[WOLF].corpses)
    suite.check("kills add up", bob.db.tracker.mobs.Wolf.kills == 65 and bob.db.tracker.mobs.Wolf.copper == 6500)
    suite.check("a new record comes in whole", bob.db.gathering.nodes["Elwynn Forest|Northshire|Peacebloom"].gathers == 7)
    suite.check("and Bob's own records are still there", bob.records["Boar|Westfall|"].corpses == 4)

    local again = Read(anaText)
    suite.check("the same text again has nothing new", #again.list == 0 and Transfer.Describe(again):find("Nothing new", 1, true))
    Take(anaText)
    suite.check("so applying it again adds nothing", bob.records[WOLF].corpses == 50 and bob.db.tracker.mobs.Wolf.kills == 65)
end

-- Ana plays on, and gives again.
Switch(ana)
ana.records[WOLF].corpses = 35
ana.records[WOLF].items["Wolf Pelt"].count = 14
ana.db.tracker.mobs.Wolf.kills = 44
local newer = Give()[1]
Switch(bob)
do
    Take(newer)
    suite.check("a newer string adds only what grew", bob.records[WOLF].corpses == 55 and bob.records[WOLF].items["Wolf Pelt"].count == 19
        and bob.db.tracker.mobs.Wolf.kills == 69, bob.records[WOLF].corpses)
    Take(anaText)
    suite.check("and the older one after it adds nothing", bob.records[WOLF].corpses == 55)
end

do
    -- What Bob took from Ana is not Bob's to hand on.
    local out = Give()[1]
    local plan
    Switch(ana)
    plan = Read(out)
    local wolfRise = 0
    for _, item in ipairs(plan.list) do
        if item.key == WOLF then wolfRise = item.record.corpses end
    end
    suite.check("the Wolf corpses in it are Bob's 20, not Ana's 35", wolfRise == 20, wolfRise)
    suite.check("and Ana's own are not changed by reading it", ana.records[WOLF].corpses == 35)
end

Switch(ana)
suite.check("a player's own string is refused", select(2, Read(anaText)) ~= nil and Read(anaText) == nil)

--------------------------------------------------------------------------------
-- Damaged and forged
--------------------------------------------------------------------------------

Switch(bob)
do
    local _, w1 = Read("hello")
    suite.check("plain text is not taken", w1 ~= nil)
    local _, w2 = Read("")
    suite.check("nor nothing", w2 ~= nil)
    local cut = anaText:sub(1, #anaText - 9)
    local plan, w3 = Read(cut)
    suite.check("a half-copied string is caught", plan == nil and w3 ~= nil, w3)
    local flipped = anaText:gsub(":(%w+):", function(c) return ":" .. c .. "x:" end, 2)
    suite.check("a changed checksum is caught", Read(flipped) == nil)
    suite.check("a string with line breaks from chat still reads", Read(anaText:sub(1, 40) .. "\n" .. anaText:sub(41)) ~= nil)
    suite.check("too long is refused", Read(("A"):rep(Transfer.MAX_TEXT + 10)) == nil)
end

--- A string made by hand, signed correctly, around any payload.
local function Forge(payload, id)
    local raw = type(payload) == "string" and payload or Serialize.Encode(payload)
    local b64
    Transfer.Encode64(raw, function(text) b64 = text end)
    local hash = 5381
    for i = 1, #b64 do hash = (hash * 33 + b64:byte(i)) % 4294967296 end
    return ("BFR1:%s:1/1:%s:%s"):format(id or "abcdef123456", Comm.ToBase36(hash), b64)
end

do
    local plan = Read(Forge({ v = 1, id = "abcdef123456", at = 1, s = {
        h = {
            [WOLF] = Wolf(10, 4),
            ["Rat|Elwynn Forest|"] = { mob = "Rat", zone = "Elwynn Forest", location = "", corpses = 1e9, items = {} },
            ["Bear|Elwynn Forest|"] = { mob = "Bear", zone = "Elwynn Forest", location = "", corpses = 2,
                items = { Fur = { name = "Fur", count = 90000, corpses = 2 } } },
            ["Wrong key"] = Wolf(5, 1),
            [42] = { mob = "Number key" },
        },
        k = { ["a|b"] = Tally(5, 5), Fox = Tally(3, 30) },
        zzz = { Evil = { kills = 1 } },
    } }))
    suite.check("a forged string is read, trimmed", plan ~= nil)
    local keys = {}
    for _, item in ipairs(plan.list) do keys[item.key] = true end
    suite.check("the good records are kept", keys[WOLF] and keys.Fox)
    suite.check("an absurd count is refused", not keys["Rat|Elwynn Forest|"])
    suite.check("so are far too many drops for the corpses", not keys["Bear|Elwynn Forest|"])
    suite.check("a record under the wrong key is refused", not keys["Wrong key"])
    suite.check("a kill key with a pipe is refused", not keys["a|b"])
    suite.check("they are counted as left out", plan.skipped == 4, plan.skipped)
    suite.check("an unknown section is ignored", not keys.Evil)
end

do
    local plan, why = Read(Forge("return os.execute('x')"))
    suite.check("text that is not data is never run, only refused", plan == nil and why ~= nil)
    local plan2 = Read(Forge({ v = 2, id = "abcdef123456", s = {} }))
    suite.check("a version we do not know is refused", plan2 == nil)
    local plan3 = Read(Forge({ v = 1, id = "999999999999", s = {} }))
    suite.check("an id that disagrees with the header is refused", plan3 == nil)
end

do
    -- Too many records in one section are cut.
    local saved = Transfer.MAX_RECORDS
    Transfer.MAX_RECORDS = 3
    local many = {}
    for i = 1, 8 do many["Mob" .. i] = Tally(i, i) end
    local plan = Read(Forge({ v = 1, id = "fedcba654321", at = 1, s = { k = many } }, "fedcba654321"))
    suite.check("a flood of records is cut short", plan and #plan.list == 3 and plan.skipped == 5, plan and plan.skipped)
    Transfer.MAX_RECORDS = saved
end

--------------------------------------------------------------------------------
-- Taking it back out
--------------------------------------------------------------------------------

Switch(bob)
do
    local list = Transfer:List()
    suite.check("the import is listed", #list == 1 and list[1].records >= 3, #list)
    local removed
    Transfer:Remove(list[1].id, function(n) removed = n end)
    suite.check("removing runs", removed and removed > 0)
    suite.check("Bob's own drop counts are back", bob.records[WOLF].corpses == 20 and bob.records[WOLF].items["Wolf Pelt"].count == 5,
        bob.records[WOLF].corpses)
    suite.check("and his own kills", bob.db.tracker.mobs.Wolf.kills == 25 and bob.db.tracker.mobs.Wolf.copper == 2500)
    suite.check("a record only the import made is gone", bob.db.gathering.nodes["Elwynn Forest|Northshire|Peacebloom"] == nil)
    suite.check("the Boar he had is untouched", bob.records["Boar|Westfall|"].corpses == 4)
    suite.check("the ledger is gone", #Transfer:List() == 0)

    Take(anaText)
    suite.check("the same string can be taken again afterwards", bob.records[WOLF].corpses == 50, bob.records[WOLF].corpses)
end

-- A reset, then his own play, then Remove: his new counts are never touched.
Switch(bob)
do
    ns.Harvest:Reset()
    bob.records = ns.Harvest.records
    bob.records[WOLF] = Wolf(30, 8)
    local list = Transfer:List()
    if list[1] then Transfer:Remove(list[1].id, function() end) end
    suite.check("removing an import after a reset leaves his own new counts",
        bob.records[WOLF] and bob.records[WOLF].corpses == 30, bob.records[WOLF] and bob.records[WOLF].corpses)
end

--------------------------------------------------------------------------------
-- A big collection comes in parts
--------------------------------------------------------------------------------

do
    Switch(ana)
    local saved = Transfer.PART_RAW
    Transfer.PART_RAW = 600
    for i = 1, 30 do ana.db.tracker.mobs["Beast" .. i] = Tally(i, i * 10) end
    local many = Give()
    Transfer.PART_RAW = saved
    suite.check("a big collection comes as several parts", #many > 2, #many)

    local carol = Player()
    Switch(carol)
    local total = 0
    for i = #many, 1, -1 do
        local taken = Take(many[i])
        total = total + (taken or 0)
    end
    suite.check("each part is complete in itself and any order works", carol.db.tracker.mobs.Beast30 and carol.db.tracker.mobs.Beast30.kills == 30
        and carol.db.tracker.mobs.Beast7.kills == 7 and carol.db.tracker.mobs.Wolf.kills == 44, total)
    suite.check("every part and record counted once", Transfer:List()[1].records == total, total)
end

--------------------------------------------------------------------------------
-- Nothing to give
--------------------------------------------------------------------------------

do
    local empty = Player()
    Switch(empty)
    local out, reason = Give()
    suite.check("nothing to give says so", out == nil and reason ~= nil)
end
