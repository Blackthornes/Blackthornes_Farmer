-- Sharing kills, drop rates and gathering with guildmates.
--
-- What matters: it is off until ticked, guildmates who ticked it get each
-- other's counts and one who did not is left alone, nothing is counted
-- twice (not on a repeat, not through a third guildmate, not for a second
-- character of one account, not for the other account already named),
-- nothing that does not look like play is taken, a whisper from anyone not
-- heard on the guild channel is ignored, and forgetting takes back out
-- exactly what the guild gave. Played as three accounts over a pretend chat.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("guildshare")

local ns = env.Load()
local Share, GuildShare, Comm = ns.Share, ns.GuildShare, ns.Comm

suite.check("the module is loaded", GuildShare ~= nil)
Share:OnEnable()
GuildShare:OnEnable()

suite.check("guild sharing is off by default", ns.db.shareGuild == false and not GuildShare:On())
suite.check("so nothing is listening", not Comm.listening)
suite.check("and it says so", GuildShare:Describe() == "Guild sharing is off.", GuildShare:Describe())

--------------------------------------------------------------------------------
-- A pretend guild
--------------------------------------------------------------------------------

local function Tally(kills, copper, items)
    return { kills = kills, copper = copper, coinKills = kills, items = items or {}, qty = {}, stacks = {}, places = {} }
end

-- Module state each account keeps for itself while the test swaps them.
local KEPT = {
    { Share, "partners" }, { GuildShare, "byId" }, { GuildShare, "bySender" }, { GuildShare, "queue" },
    { GuildShare, "current" }, { GuildShare, "helloAt" }, { GuildShare, "answerAt" },
    { GuildShare, "building" }, { GuildShare, "ticker" }, { GuildShare, "me" },
}

local function Account(name, db, records)
    if not db then
        db = {}
        for key, value in pairs(ns.DEFAULTS) do db[key] = value end
        db.tracker = { mobs = {} }
        db.gathering = { nodes = {}, spots = {} }
        db.fishing = { spots = {} }
    end
    local kept = {
        partners = {}, byId = {}, bySender = {}, queue = {},
        me = { key = "guild-hello", name = "" },
    }
    return { name = name, db = db, records = records or {}, online = true, kept = kept }
end

local ana, bob, cid = Account("Ana Smith"), Account("Bob Smith"), Account("Cid Smith")
-- A second character of Ana's account: the same saved data.
local ann = Account("Ann Smith", ana.db, ana.records)
ann.online = false
local accounts = { ana, bob, cid, ann }
local byName = {}
for _, account in ipairs(accounts) do byName[account.name] = account end
local current

local function Switch(account)
    if current then
        for _, pair in ipairs(KEPT) do current.kept[pair[2]] = pair[1][pair[2]] end
    end
    current = account
    for _, pair in ipairs(KEPT) do pair[1][pair[2]] = account.kept[pair[2]] end
    ns.db = account.db
    ns.Harvest.records = account.records
    account.db.harvest = account.records
end

local outbox, timers = {}, {}
local clock = 0
_G.UnitName = function(unit)
    if unit == "player" then return (current.name:match("^(%S+)")) end
    return nil
end
_G.UnitSurname = function() return "Smith" end
_G.IsInGuild = function() return true end
_G.GetTime = function() return clock end
_G.time = function() return 1000000 + math.floor(clock) end
_G.InCombatLockdown = function() return false end
_G.C_ChatInfo = {
    RegisterAddonMessagePrefix = function() return true end,
    SendAddonMessage = function(prefix, text, channel, target)
        outbox[#outbox + 1] = { from = current, prefix = prefix, text = text, channel = channel, target = target }
        return 0
    end,
}
_G.C_Timer = {
    After = function(_, fn) timers[#timers + 1] = { fn = fn, account = current } end,
    NewTicker = function() return { Cancel = function() end } end,
}

local guildSent = 0

--- Let time pass until everything is quiet. A guild message reaches every
--- other account online; a whisper only its target, if online.
local function Settle()
    for _ = 1, 6000 do
        clock = clock + 5
        local moved = false

        local due = timers
        timers = {}
        for _, timer in ipairs(due) do
            Switch(timer.account)
            if timer.account.online then timer.fn() end
            moved = true
        end

        for _, account in ipairs(accounts) do
            Switch(account)
            if account.online and Comm:Pending() > 0 then Comm:Pump() moved = true end
        end

        local mail = outbox
        outbox = {}
        for _, message in ipairs(mail) do
            if message.channel == "GUILD" then
                guildSent = guildSent + 1
                for _, to in ipairs(accounts) do
                    if to.online and to ~= message.from then
                        Switch(to)
                        Comm:CHAT_MSG_ADDON(nil, message.prefix, message.text, message.channel, message.from.name)
                    end
                end
            else
                local to = byName[message.target]
                if to and to.online then
                    Switch(to)
                    Comm:CHAT_MSG_ADDON(nil, message.prefix, message.text, message.channel, message.from.name)
                end
            end
            moved = true
        end

        if not moved and #timers == 0 and #outbox == 0 then return end
    end
    error("guild sharing never settled")
end

--- Half an hour on, and everyone online says hello, as the ticker would.
local function HalfHour()
    clock = clock + GuildShare.SYNC_GAP + 1
    for _, account in ipairs(accounts) do
        if account.online then Switch(account) GuildShare:Hello() end
    end
    Settle()
end

local function Wolf(corpses, pelts)
    return {
        mob = "Wolf", zone = "Elwynn Forest", location = "Northshire", minLevel = 1, maxLevel = 3,
        corpses = corpses, coords = { 0.4, 0.5 },
        items = { ["Wolf Pelt"] = { name = "Wolf Pelt", count = pelts, corpses = pelts, id = 1 } },
    }
end
local WOLF = "Wolf|Elwynn Forest|Northshire"

ana.records[WOLF] = Wolf(30, 12)
bob.records[WOLF] = Wolf(20, 5)
cid.records[WOLF] = Wolf(10, 2)
ana.db.tracker.mobs.Wolf = Tally(40, 4000)
bob.db.tracker.mobs.Wolf = Tally(25, 2500)
cid.db.tracker.mobs.Rat = Tally(9, 90)
bob.db.gathering.nodes["Elwynn Forest|Northshire|Peacebloom"] = {
    zone = "Elwynn Forest", location = "Northshire", node = "Peacebloom", kind = "herb",
    gathers = 7, items = { Peacebloom = { gathers = 7, count = 9, id = 2447 } },
}

for _, account in ipairs(accounts) do Switch(account) Share:Apply() end
Settle()
suite.check("off everywhere, nothing goes to the guild", guildSent == 0, guildSent)

local function Check(label, ok, detail) suite.check(label, ok, detail) end

-- Ana and Bob tick it; Cid does not.
Switch(ana) GuildShare:SetOn(true)
Check("on, it listens", Comm.listening == true)
Switch(bob) GuildShare:SetOn(true)
Settle()

Switch(ana)
Check("Ana has Bob's corpses", ana.records[WOLF].corpses == 50, ana.records[WOLF].corpses)
Check("and his drops", ana.records[WOLF].items["Wolf Pelt"].count == 17, ana.records[WOLF].items["Wolf Pelt"].count)
Check("and his kills", ana.db.tracker.mobs.Wolf.kills == 65, ana.db.tracker.mobs.Wolf.kills)
Check("and his gathering", ana.db.gathering.nodes["Elwynn Forest|Northshire|Peacebloom"]
    and ana.db.gathering.nodes["Elwynn Forest|Northshire|Peacebloom"].gathers == 7)
Check("and says how much came from the guild", GuildShare:Describe():find("heard this session: 1", 1, true) ~= nil,
    GuildShare:Describe())
Switch(bob)
Check("Bob has Ana's corpses", bob.records[WOLF].corpses == 50, bob.records[WOLF].corpses)
Check("and her kills", bob.db.tracker.mobs.Wolf.kills == 65, bob.db.tracker.mobs.Wolf.kills)
Check("the ledger is the guild's", (function()
    for key, held in pairs(bob.db.shareIn or {}) do
        if key:find("^guild:") and held.kind == "guild" then return true end
    end
end)())

Switch(cid)
Check("Cid, who did not tick it, got nothing", cid.records[WOLF].corpses == 10 and cid.db.tracker.mobs.Wolf == nil)
Check("and gave nothing", ana.db.tracker.mobs.Rat == nil and bob.db.tracker.mobs.Rat == nil)

-- Hearing it all again adds nothing.
HalfHour()
HalfHour()
Check("syncing again counts nothing twice", ana.records[WOLF].corpses == 50 and bob.records[WOLF].corpses == 50
    and ana.db.tracker.mobs.Wolf.kills == 65 and bob.db.tracker.mobs.Wolf.kills == 65)

-- New kills reach the other side once.
ana.db.tracker.mobs.Wolf.kills = ana.db.tracker.mobs.Wolf.kills + 5
ana.db.tracker.mobs.Wolf.coinKills = ana.db.tracker.mobs.Wolf.coinKills + 5
ana.records[WOLF].corpses = ana.records[WOLF].corpses + 5
HalfHour()
Check("a new kill reaches a guildmate", bob.db.tracker.mobs.Wolf.kills == 70 and bob.records[WOLF].corpses == 55,
    bob.db.tracker.mobs.Wolf.kills)
Check("without coming back round", ana.db.tracker.mobs.Wolf.kills == 70 and ana.records[WOLF].corpses == 55,
    ana.db.tracker.mobs.Wolf.kills)

-- Cid ticks it: he gets each guildmate's own counts, once.
Switch(cid) GuildShare:SetOn(true)
Settle()
HalfHour()
Check("Cid has everyone's corpses", cid.records[WOLF].corpses == 65, cid.records[WOLF].corpses)
Check("Ana has Cid's too, and Bob's only once", ana.records[WOLF].corpses == 65, ana.records[WOLF].corpses)
Check("and Bob", bob.records[WOLF].corpses == 65, bob.records[WOLF].corpses)
Check("and Cid's rats", ana.db.tracker.mobs.Rat and ana.db.tracker.mobs.Rat.kills == 9)

-- Ana logs onto her other character: the same account, so nothing new.
ana.online, ann.online = false, true
Switch(bob) GuildShare:OnOffline("ana smith")
HalfHour()
Check("another character of the same account adds nothing", bob.records[WOLF].corpses == 65
    and bob.db.tracker.mobs.Wolf.kills == 70, bob.records[WOLF].corpses)
Switch(bob)
local ledgers = 0
for _, held in pairs(bob.db.shareIn or {}) do
    if held.kind == "guild" then ledgers = ledgers + 1 end
end
Check("and keeps one ledger per account", ledgers == 2, ledgers)
Check("whispers to the character now playing", GuildShare.bySender["ann smith"] ~= nil
    and GuildShare.bySender["ana smith"] == nil)
ana.online, ann.online = true, false

-- Only what came in on the guild channel is heard.
Switch(bob)
local before = bob.records[WOLF].corpses
Share:OnRecords("Eve Smith", { { s = "h", k = WOLF, h = "x", d = Wolf(999, 1) } }, "WHISPER")
Check("a whisper from someone never heard in the guild is not taken", bob.records[WOLF].corpses == before)
GuildShare:OnHello("Eve Smith", "abcdef123456:zz", "WHISPER")
Check("a hello that was not on the guild channel is ignored", GuildShare.byId["abcdef123456"] == nil)
GuildShare:OnHello("Eve Smith", "not an id:zz", "GUILD")
Check("a hello that does not read is ignored", GuildShare.bySender["eve smith"] == nil)

-- The other account already named in Settings is not taken again.
bob.db.shareIn["dee smith"] = { name = "Dee Smith", account = "0123456789ab", hashes = {}, credit = {} }
GuildShare:OnHello("Dee Smith", "0123456789ab:zz", "GUILD")
Check("a guildmate who is your other account is left to account sharing", GuildShare.byId["0123456789ab"] == nil)
bob.db.shareIn["dee smith"] = nil

-- Counts that are not play are refused.
do
    local state = GuildShare.bySender["cid smith"]
    local silly = Wolf(1, 5000)
    local ok, why = Share:Accept(state, { s = "h", k = WOLF, h = "q", d = silly })
    Check("a drop record with far more items than corpses is refused", not ok and why == "not plausible", why)
    local huge = { s = "k", k = "Wolf", h = "q", d = Tally(2e9 - 1, 0) }
    ok, why = Share:Accept(state, huge)
    Check("so is a tally no one could reach", not ok and why == "not plausible", why)
    Check("and nothing changed", bob.records[WOLF].corpses == before)
end

-- A big guild cannot grow the save without end.
do
    local limit = GuildShare.MAX_GUILDMATES
    GuildShare.MAX_GUILDMATES = 2
    GuildShare:OnHello("Fay Smith", "fedcba987654:zz", "GUILD")
    Check("past the most guildmates kept, a new one is not taken on", GuildShare.byId["fedcba987654"] == nil)
    GuildShare.MAX_GUILDMATES = limit
end

-- A guildmate's text taken in earlier keeps its one ledger.
do
    Check("a guildmate keeps the ledger of an earlier import", (function()
        bob.db.shareIn["import:aaaaaa"] = { kind = "import", credit = {}, hashes = {} }
        local key = GuildShare.LedgerKey("aaaaaa")
        bob.db.shareIn["import:aaaaaa"] = nil
        return key == "import:aaaaaa"
    end)())
    local anaId = ana.db.exportId
    Check("and a text from a guildmate goes in their guild ledger", ns.Transfer.LedgerKey(anaId) == "guild:" .. anaId,
        ns.Transfer.LedgerKey(anaId))
end

-- Forgetting takes the guild's counts back out, and only theirs.
do
    Switch(bob)
    local done
    GuildShare:Forget(function(count) done = count end)
    Settle()
    Switch(bob)
    Check("forget finishes", done and done > 0, done)
    Check("and turns it off", ns.db.shareGuild == false and not GuildShare:On())
    Check("Bob is back to his own corpses", bob.records[WOLF].corpses == 20, bob.records[WOLF].corpses)
    Check("and his own drops", bob.records[WOLF].items["Wolf Pelt"].count == 5, bob.records[WOLF].items["Wolf Pelt"].count)
    Check("and his own kills", bob.db.tracker.mobs.Wolf.kills == 25, bob.db.tracker.mobs.Wolf.kills)
    Check("a mob only the guild killed is gone", bob.db.tracker.mobs.Rat == nil)
    Check("his own gathering is kept", bob.db.gathering.nodes["Elwynn Forest|Northshire|Peacebloom"].gathers == 7)
    Check("no guild ledger is left", (function()
        for _, held in pairs(bob.db.shareIn or {}) do
            if held.kind == "guild" then return false end
        end
        return true
    end)())
end

-- The typed command.
do
    Switch(cid)
    local printed = {}
    local print = ns.Print
    ns.Print = function(text) printed[#printed + 1] = text end
    ns.HandleSlash("share guild off")
    Check("/farm share guild off turns it off", ns.db.shareGuild == false)
    ns.HandleSlash("share guild on")
    Check("and on", ns.db.shareGuild == true)
    local corpses = cid.records[WOLF].corpses
    ns.HandleSlash("share guild forget")
    Check("forget without confirm only explains", ns.db.shareGuild == true and cid.records[WOLF].corpses == corpses)
    ns.Print = print
end

-- A save from before this existed loads with it off.
do
    local old = { windowScale = 120, shareIn = { ["bob smith"] = { name = "Bob Smith", credit = {}, hashes = {} } } }
    _G.BlackthornesFarmerDB = old
    ns.LoadSavedVariables()
    Check("an old save loads with guild sharing off", old.shareGuild == false)
    Check("and its ledgers are kept", old.shareIn["bob smith"].name == "Bob Smith")
end

suite.done()
