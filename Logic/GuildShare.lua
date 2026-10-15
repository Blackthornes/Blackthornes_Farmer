-- Blackthornes Farmer -- Logic/GuildShare.lua
-- Drop rates shared with guildmates who use Farmer.
--
-- Asked 2026-10-13 by the owner, off by default. It is the account sharing
-- of Logic/Share.lua with a different way of finding partners: instead of
-- names typed in Settings, a guildmate is anyone heard on the guild's addon
-- channel, which only members of the guild can send on.
--
--   * Now and then (and soon after login) each side says hello to the guild:
--     one short message with its Farmer id (`Transfer:SourceId`) and a hash
--     of what it would share. Someone new to a side gets a hello back, at
--     most one a minute, so the two always know each other.
--   * A hello whose hash differs from the last one fully taken starts the
--     same whispered conversation as account sharing (manifest, want,
--     records), one guildmate at a time, each at most every half hour.
--   * Only drop records go ("h"), and only the sender's own: what came from
--     the guild is never sent on.
--
-- What is different from account sharing, because a guild is not you:
--   * A guildmate's counts never join the player's own. Kills, loot, the
--     session, Rankings, the tooltip's kill count and everything earned by
--     killing stay the player's alone. They are kept apart, in `guildDrops`
--     (shaped as Harvest's records) with their ledgers in `guildIn`, and only
--     the drop rates they make show: as rows in the database marked "guild"
--     (only where nothing measured on Forever stands, and only from
--     MIN_SAMPLE corpses). A mob's loot table no longer shows them before
--     the player's own rates (the owner, 2026-10-15); GuildShare:RateFor
--     is kept for whatever reads it.
--   * Records also have to look like play (`GuildShare.Plausible`).
--   * At most MAX_GUILDMATES guildmates are kept.
--   * Turned off, the guild's rows leave the database (the data is kept);
--     `/farm share guild forget confirm` deletes it and turns sharing off.
--
-- Saved, account wide, never renamed: `shareGuild` (on or off),
-- `guildDrops` and `guildIn` (`top` there is the hash last taken in full).

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
GuildShare.me = { key = "guild-hello", name = "", sections = { h = true } }
GuildShare.shown = {}       -- record key -> { corpses, rows } put in the database

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

-- A guildmate's rate is shown from this many corpses, as the player's own.
GuildShare.MIN_SAMPLE = 20
GuildShare.PUBLISH_SLICE = 100   -- records put in the database a frame

--- The guild's drop records, as Harvest's: [mob|zone|location] = record.
local function Drops(create)
    if type(ns.db) ~= "table" then return nil end
    if type(ns.db.guildDrops) ~= "table" then
        if not create then return nil end
        ns.db.guildDrops = {}
    end
    return ns.db.guildDrops
end

--- What was heard from and taken from each guildmate.
local function Ledgers()
    if type(ns.db) ~= "table" then return {} end
    if type(ns.db.guildIn) ~= "table" then ns.db.guildIn = {} end
    return ns.db.guildIn
end

--- The other account's ledgers, from account sharing.
local function AccountLedgers()
    return type(ns.db) == "table" and type(ns.db.shareIn) == "table" and ns.db.shareIn or {}
end

function GuildShare.LedgerKey(id)
    return "guild:" .. id
end

--- How many guildmates are kept: their ledgers, and the ones heard this
--- session whose ledger is not made yet.
local function Guildmates()
    local count = 0
    for _, held in pairs(Ledgers()) do
        if type(held) == "table" then count = count + 1 end
    end
    for _, state in pairs(GuildShare.byId) do
        if type(Ledgers()[state.key]) ~= "table" then count = count + 1 end
    end
    return count
end

--- True when `id` is the other account named in Settings: its counts come
--- by whisper already.
local function LinkedAccount(id)
    for _, held in pairs(AccountLedgers()) do
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
        state = {
            key = key, id = id, guild = true, check = GuildShare.Plausible,
            sections = { h = true },
            store = function(section, create) return section == "h" and Drops(create) or nil end,
            book = Ledgers,
        }
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
    self:PublishSoon()
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
-- What the guild's records show: rows in the database, and loot table rates
--------------------------------------------------------------------------------

--- A record that can give a rate: a named mob with enough corpses.
local function Usable(record)
    return type(record) == "table" and type(record.mob) == "string"
        and not record.mob:match("^Creature #%d+$")
        and type(record.zone) == "string" and record.zone ~= ""
        and type(record.corpses) == "number" and record.corpses >= GuildShare.MIN_SAMPLE
        and type(record.items) == "table"
end

local function Coords(record)
    local coords = record.coords
    if type(coords) ~= "table" then return nil end
    local x, y = tonumber(coords[1]), tonumber(coords[2])
    if not (x and y and x >= 0 and x <= 100 and y >= 0 and y <= 100) then return nil end
    return { x, y }
end

--- Take one record's rows back out of the database.
local function Hide(entry)
    local DB = ns.DB
    for index = #entry.rows, 1, -1 do
        local row = entry.rows[index]
        DB:RemoveSource(row.item, row.source)
        if row.item.guildOnly and #row.item.sources == 0 then DB:RemoveItem(row.item) end
    end
end

--- Put one record's rates in the database: a row per item it dropped, where
--- no row measured on Forever stands for the same spot.
local function Show(record, byID)
    local DB = ns.DB
    local rows = {}
    for name, entry in pairs(record.items) do
        local corpses = type(entry) == "table" and tonumber(entry.corpses) or 0
        local chance = corpses / record.corpses * 100
        local nodeOnly = ns.Gathering ~= nil and ns.Gathering.IsNodeOnly(name)
        if type(name) == "string" and name ~= "" and chance > 0 and chance <= 100 and not nodeOnly then
            local item = DB.items[name:lower()] or (tonumber(entry.id) and byID[tonumber(entry.id)])
            if not item then
                item = DB:RegisterItem({ name = name, id = tonumber(entry.id) })
                if item then item.guildOnly = true end
            end
            local source = item and DB:AddSource(item, {
                name = record.mob,
                zone = record.zone,
                location = type(record.location) == "string" and record.location ~= "" and record.location or nil,
                coords = Coords(record),
                minLevel = tonumber(record.minLevel),
                maxLevel = tonumber(record.maxLevel),
                chance = chance,
                provenance = "guild",
            })
            if source then
                rows[#rows + 1] = { item = item, source = source }
            elseif item and item.guildOnly and #item.sources == 0 then
                DB:RemoveItem(item)
            end
        end
    end
    return rows
end

--- Bring the database's guild rows up to date, a few records a frame: only
--- the records that changed since last time are touched.
function GuildShare:Publish()
    if not ns.DB then return end
    if self.publishing then
        self.publishAgain = true
        return
    end
    local drops = self:On() and Drops() or {}
    local todo = {}
    for key, entry in pairs(self.shown) do
        local record = drops[key]
        if not (Usable(record) and record.corpses == entry.corpses) then todo[#todo + 1] = key end
    end
    for key, record in pairs(drops) do
        if not self.shown[key] and Usable(record) then todo[#todo + 1] = key end
    end
    if #todo == 0 then return end

    self.publishing = true
    local index = 1
    local function Step()
        local byID = ns.DB:ByID()
        local stop = math.min(#todo, index + self.PUBLISH_SLICE - 1)
        while index <= stop do
            local key = todo[index]
            index = index + 1
            local entry = self.shown[key]
            if entry then
                pcall(Hide, entry)
                self.shown[key] = nil
            end
            local record = self:On() and Drops() and Drops()[key]
            if Usable(record) then
                local ok, rows = pcall(Show, record, byID)
                self.shown[key] = { corpses = record.corpses, rows = ok and rows or {} }
            end
        end
        if index <= #todo then
            C_Timer.After(0, Step)
            return
        end
        self.publishing = nil
        if ns.UI and ns.UI.RefreshActive then pcall(ns.UI.RefreshActive, ns.UI) end
        if ns.LootTableUI and ns.LootTableUI.Refresh then pcall(ns.LootTableUI.Refresh, ns.LootTableUI) end
        if self.publishAgain then
            self.publishAgain = nil
            self:Publish()
        end
    end
    Step()
end

--- Once records stop arriving for a moment.
function GuildShare:PublishSoon()
    if self.publishQueued then return end
    self.publishQueued = true
    C_Timer.After(2, function()
        GuildShare.publishQueued = nil
        GuildShare:Publish()
    end)
end

--- The guild's drop rate for `itemName` off `mob`, all its places together:
--- the percentage and how many corpses it is from, or nil below MIN_SAMPLE.
function GuildShare:RateFor(mob, itemName)
    if not self:On() then return nil end
    local drops = Drops()
    if not drops or type(mob) ~= "string" or type(itemName) ~= "string" then return nil end
    local corpses, dropped = 0, 0
    for _, record in pairs(drops) do
        if type(record) == "table" and record.mob == mob and type(record.corpses) == "number" then
            corpses = corpses + record.corpses
            local entry = type(record.items) == "table" and record.items[itemName]
            if type(entry) == "table" then dropped = dropped + (tonumber(entry.corpses) or 0) end
        end
    end
    if corpses < self.MIN_SAMPLE then return nil end
    return math.min(100, dropped / corpses * 100), corpses
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
    -- On, the guild's rows go in; off, they come out (the data is kept).
    self:Publish()
end

function GuildShare:SetOn(on)
    ns.db.shareGuild = on == true
    Share:Apply()
end

--- Delete everything taken from the guild, and turn it off. The player's
--- own counts were never touched, so nothing of theirs changes.
-- @return how many records were deleted
function GuildShare:Forget()
    local drops = Drops()
    local count = 0
    for _ in pairs(drops or {}) do count = count + 1 end
    self:SetOn(false)
    ns.db.guildDrops, ns.db.guildIn = {}, {}
    self.byId, self.bySender = {}, {}
    self:Publish()
    return count
end

--- How many guildmates were heard this session, and drop records taken
--- from the guild in all.
function GuildShare:Counts()
    local heard = 0
    for _, state in pairs(self.byId) do
        if state.heardAt then heard = heard + 1 end
    end
    local records = 0
    for _ in pairs(Drops() or {}) do records = records + 1 end
    return heard, records
end

function GuildShare:Describe()
    if not self:On() then return L["Guild sharing is off."] end
    if not InGuild() then return L["Guild sharing is on, but this character is not in a guild."] end
    local heard, records = self:Counts()
    return L.Format("Guild sharing is on. Guildmates with Farmer heard this session: %d. Mobs with drops from your guild: %d.",
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
            ns.Print(L["This deletes the drop rates your guild gave and turns guild sharing off. Your own kills and loot stay as they are. Type /farm share guild forget confirm to do it."])
            return
        end
        local count = self:Forget()
        ns.Print(L.Format("Deleted your guild's drops for %d mobs. Guild sharing is off.", count))
    else
        ns.Print(self:Describe())
    end
end

function GuildShare:OnEnable()
    Comm:On("G", function(...) GuildShare:OnHello(...) end)
    -- Share:OnEnable ran first (the TOC's order) and called Apply before this
    -- module had its handler; this starts the hellos and shows the guild's
    -- rows if it is on.
    self:Apply()
end
