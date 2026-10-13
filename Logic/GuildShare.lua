-- Blackthornes Farmer -- Logic/GuildShare.lua
-- Kills, drop rates, gathering and fishing shared with guildmates who use
-- Farmer.
--
-- Asked 2026-10-13 by the owner, off by default. It is the account sharing
-- of Logic/Share.lua with a different way of finding partners: instead of
-- names typed in Settings, a guildmate is anyone heard on the guild's addon
-- channel, which only members of the guild can send on.
--
--   * Now and then (and soon after login) each side says hello to the guild:
--     one short message with its Farmer id (`Transfer:SourceId`) and a hash
--     of everything it would share. Someone new to a side gets a hello back,
--     at most one a minute, so the two always know each other.
--   * A hello whose hash differs from the last one fully taken starts the
--     same whispered conversation as account sharing (manifest, want,
--     records), one guildmate at a time, each at most every half hour.
--   * Counts are taken the same way: only the rise over what that Farmer has
--     given before (`shareIn["guild:<id>"]`, `kind = "guild"`), only the
--     sender's own (nothing is passed on), never twice for one account
--     however many characters it has, and never from a guildmate who is
--     also the other account named in Settings.
--
-- What is different from account sharing, because a guild is not you:
--   * Records also have to look like play (`GuildShare.Plausible`: no tally
--     past Transfer.MAX_COUNT, no drop record with far more items than
--     corpses).
--   * At most MAX_GUILDMATES guildmates are kept, so a big guild cannot grow
--     the saved data without end.
--   * Everything taken from the guild can be taken back out:
--     `/farm share guild forget confirm` subtracts exactly the ledgers and
--     turns guild sharing off.
--
-- Saved, account wide, never renamed: `shareGuild` (on or off) and the
-- ledgers in `shareIn` above (`top` there is the hash last taken in full).

local _, ns = ...
local L = ns.L

local GuildShare = ns.NewModule("GuildShare")

local Comm = ns.Comm
local Share = ns.Share

GuildShare.HELLO_SECONDS = 1800   -- a hello to the guild every half hour
GuildShare.FIRST_HELLO = 30       -- and this long after login
GuildShare.ANSWER_GAP = 60        -- at most one hello back a minute
GuildShare.SYNC_GAP = 1800        -- one guildmate synced at most this often
GuildShare.SYNC_TIMEOUT = 180     -- a sync left this long is given up
GuildShare.CONFIRM_AFTER = 30     -- quiet this long after records: compare again
GuildShare.MAX_GUILDMATES = 20

GuildShare.byId = {}       -- Farmer id -> state
GuildShare.bySender = {}   -- name key of the character playing -> state
GuildShare.queue = {}
GuildShare.me = { key = "guild-hello", name = "" }

function GuildShare:On()
    return ns.db ~= nil and ns.db.shareGuild == true
end

local function InGuild()
    local ok, inGuild = pcall(IsInGuild)
    return ok and inGuild == true
end

local function ValidId(id)
    return type(id) == "string" and #id >= 6 and #id <= 16 and id:match("^%x+$") ~= nil
end

local function Ledgers()
    return type(ns.db) == "table" and type(ns.db.shareIn) == "table" and ns.db.shareIn or {}
end

--- The ledger a guildmate's counts go in: an earlier import from the same
--- Farmer keeps its own, so nothing it gave is counted again.
function GuildShare.LedgerKey(id)
    local import = "import:" .. id
    if type(Ledgers()[import]) == "table" then return import end
    return "guild:" .. id
end

--- How many guildmates are kept: their ledgers, and the ones heard this
--- session whose ledger is not made yet.
local function Guildmates()
    local count = 0
    for _, held in pairs(Ledgers()) do
        if type(held) == "table" and held.kind == "guild" then count = count + 1 end
    end
    for _, state in pairs(GuildShare.byId) do
        if type(Ledgers()[state.key]) ~= "table" then count = count + 1 end
    end
    return count
end

--- True when `id` is the other account named in Settings: its counts come
--- by whisper already.
local function LinkedAccount(id)
    for _, held in pairs(Ledgers()) do
        if type(held) == "table" and held.kind == nil and held.account == id then return true end
    end
    return false
end

--- A guildmate's record has to look like play.
function GuildShare.Plausible(section, record)
    local Transfer = ns.Transfer
    local _, biggest = Transfer.Scan(section.spec, record, nil)
    if biggest > Transfer.MAX_COUNT then return false end
    return Transfer.Plausible(section, record)
end

--------------------------------------------------------------------------------
-- Hellos
--------------------------------------------------------------------------------

--- Say to the guild who this Farmer is and what it has.
function GuildShare:Hello()
    if not self:On() or not InGuild() or self.building then return end
    self.building = true
    self.helloAt = time()
    Share:Build(self.me, function(manifest)
        self.building = nil
        if not self:On() or not InGuild() then return end
        local top = Comm.Hash(ns.Serialize.EncodeCanonical(manifest))
        Comm:Send("G", ns.Transfer:SourceId() .. ":" .. top, "GUILD")
    end)
end

--- Someone new was heard: say hello back soon, unless one just went out.
function GuildShare:AnswerSoon()
    local now = time()
    if self.answerAt and now - self.answerAt < self.ANSWER_GAP then return end
    if self.helloAt and now - self.helloAt < 20 then return end
    self.answerAt = now
    C_Timer.After(3 + math.random() * 10, function() GuildShare:Hello() end)
end

function GuildShare:OnHello(sender, body, channel)
    if channel ~= "GUILD" or not self:On() or Comm.IsMe(sender) then return end
    local id, top = (body or ""):match("^(%x+):(%w+)$")
    if not ValidId(id) or #top > 12 then return end
    if id == ns.Transfer:SourceId() or LinkedAccount(id) then return end
    local senderKey = Comm.NameKey(sender)
    if not senderKey then return end

    local state = self.byId[id]
    local new = state == nil
    if new then
        local key = GuildShare.LedgerKey(id)
        if type(Ledgers()[key]) ~= "table" and Guildmates() >= self.MAX_GUILDMATES then return end
        state = { key = key, id = id, guild = true, kind = "guild", check = GuildShare.Plausible }
        self.byId[id] = state
    end

    -- The character playing on that account now.
    if state.senderKey and state.senderKey ~= senderKey then self.bySender[state.senderKey] = nil end
    local other = self.bySender[senderKey]
    if other and other ~= state then other.senderKey = nil end
    state.name, state.senderKey = sender, senderKey
    self.bySender[senderKey] = state
    state.online, state.heardAt, state.top = true, time(), top

    if new then self:AnswerSoon() end
    local held = Ledgers()[state.key]
    if not (type(held) == "table" and held.top == top) then self:Want(state) end
end

--------------------------------------------------------------------------------
-- Syncing, one guildmate at a time
--------------------------------------------------------------------------------

function GuildShare:Want(state)
    if state.queued or self.current == state then return end
    if state.syncedAt and time() - state.syncedAt < self.SYNC_GAP then return end
    state.queued = true
    self.queue[#self.queue + 1] = state
    -- A moment's wait, so their own answer to a hello comes in first.
    C_Timer.After(5 + math.random() * 10, function() GuildShare:Next() end)
end

function GuildShare:Finish(state)
    if self.current == state then self.current = nil end
end

function GuildShare:Next()
    if not self:On() then return end
    local current = self.current
    if current then
        if current.online and time() - (current.syncStart or 0) < self.SYNC_TIMEOUT then return end
        self:Finish(current)
    end

    local state
    repeat
        state = table.remove(self.queue, 1)
        if state then state.queued = nil end
    until not state or state.online
    if not state then return end

    self.current, state.syncStart, state.syncedAt = state, time(), time()
    Share:SendManifest(state)
    C_Timer.After(self.SYNC_TIMEOUT + 1, function() GuildShare:Next() end)
end

--- Their manifest was compared with what is held (Share:OnManifest). Nothing
--- wanted: everything they announced is in, and the next one may go.
function GuildShare:Compared(state, wanted)
    if wanted > 0 then return end
    local held = Ledgers()[state.key]
    if type(held) == "table" and state.top then held.top = state.top end
    if self.current == state then
        self:Finish(state)
        self:Next()
    end
end

--- Records came in. Once they stop, ask for their manifest again (a hello
--- is always answered with one), which also says whether everything arrived.
function GuildShare:Received(state)
    state.lastRecordAt = time()
    if state.confirming then return end
    state.confirming = true
    local function Confirm()
        if time() - (state.lastRecordAt or 0) < self.CONFIRM_AFTER - 1 then
            C_Timer.After(self.CONFIRM_AFTER, Confirm)
            return
        end
        state.confirming = nil
        if self:On() and state.online and self.current == state then Share:Hello(state.name) end
    end
    C_Timer.After(self.CONFIRM_AFTER, Confirm)
end

--- A whisper from a guildmate: their state, or nil.
function GuildShare:PartnerFor(sender)
    if not self:On() then return nil end
    local key = Comm.NameKey(sender)
    return key and self.bySender[key] or nil
end

function GuildShare:OnOffline(key)
    local state = self.bySender[key]
    if not state then return end
    state.online = false
    if self.current == state then
        self:Finish(state)
        self:Next()
    end
end

--------------------------------------------------------------------------------
-- Settings
--------------------------------------------------------------------------------

--- Start or stop to match the setting; Share:Apply calls it.
function GuildShare:Apply()
    if self:On() then
        if not self.ticker and type(C_Timer) == "table" then
            self.ticker = C_Timer.NewTicker(self.HELLO_SECONDS, function() GuildShare:Hello() end)
            C_Timer.After(self.FIRST_HELLO, function() GuildShare:Hello() end)
        end
    else
        if self.ticker then
            pcall(self.ticker.Cancel, self.ticker)
            self.ticker = nil
        end
        for _, state in pairs(self.byId) do
            state.online, state.queued = false, nil
        end
        self.queue, self.current = {}, nil
    end
end

function GuildShare:SetOn(on)
    ns.db.shareGuild = on == true
    Share:Apply()
end

--- Take back out everything taken from the guild, and turn it off.
-- `done(records)`, or `done(nil, "busy")` while a text is being taken in or
-- out (Logic/Transfer.lua); what was not reached yet stays for a second try.
function GuildShare:Forget(done)
    self:SetOn(false)
    local keys = {}
    for key, held in pairs(Ledgers()) do
        if type(held) == "table" and held.kind == "guild" then keys[#keys + 1] = key end
    end
    local total = 0
    local function Step(index)
        local key = keys[index]
        if not key then
            self.byId, self.bySender = {}, {}
            return done(total)
        end
        ns.Transfer:RemoveLedger(key, "guild", function(count, why)
            if why == "busy" then return done(nil, why) end
            total = total + (count or 0)
            Step(index + 1)
        end)
    end
    Step(1)
end

--- How many guildmates were heard this session, and records taken from the
--- guild in all.
function GuildShare:Counts()
    local heard = 0
    for _, state in pairs(self.byId) do
        if state.heardAt then heard = heard + 1 end
    end
    local records = 0
    for key, held in pairs(Ledgers()) do
        if type(held) == "table" and held.kind == "guild" then records = records + Share:CountTaken(key) end
    end
    return heard, records
end

function GuildShare:Describe()
    if not self:On() then return L["Guild sharing is off."] end
    if not InGuild() then return L["Guild sharing is on, but this character is not in a guild."] end
    local heard, records = self:Counts()
    return L.Format("Guild sharing is on. Guildmates with Farmer heard this session: %d. Records taken from your guild: %d.",
        heard, records)
end

function GuildShare:Command(text)
    local word, rest = (text or ""):match("^(%S*)%s*(.-)%s*$")
    word = (word or ""):lower()
    if word == "on" or word == "off" then
        self:SetOn(word == "on")
        ns.Print(word == "on" and L["sharing with your guild is on"] or L["sharing with your guild is off"])
    elseif word == "forget" then
        if (rest or ""):lower() ~= "confirm" then
            ns.Print(L["This takes everything your guild gave back out of your counts and turns guild sharing off. Type /farm share guild forget confirm to do it."])
            return
        end
        self:Forget(function(count)
            if not count then
                ns.Print(L["Data is being taken in or out right now. Guild sharing is off; try forget again in a moment."])
                return
            end
            ns.Print(L.Format("Took back out what your guild gave, from %d records. Guild sharing is off.", count))
        end)
    else
        ns.Print(self:Describe())
    end
end

function GuildShare:OnEnable()
    Comm:On("G", function(...) GuildShare:OnHello(...) end)
    -- Share:OnEnable ran first (the TOC's order) and called Apply before this
    -- module had its handler; this starts the hellos if it is on.
    self:Apply()
end
