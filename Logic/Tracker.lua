-- Blackthornes Farmer -- Logic/Tracker.lua
-- A running tally of what you kill, and what they drop.
--
-- The harvester keeps the evidence for the data files. This is the view from
-- the saddle: loot a corpse and you see how many of that mob you have killed,
-- and once there are enough of them to mean something, how often each item
-- has turned up.
--
-- A kill is a corpse you opened. That is the only kill this addon can see with
-- its contents attached, and a drop rate needs both halves. One corpse opened
-- twice -- skinned after looting, or come back to for what was left -- is still
-- one kill, which is why each corpse is remembered by its guid for the session.
-- A corpse you only skinned shows none of its drops, so it is no kill; its
-- leather still counts in the session's loot.
--
-- Below MIN_KILLS the panel shows counts, never percentages: three drops in
-- five kills is not a 60% drop rate, it is five kills.
--
-- Each kill also notes where it happened, subzone and zone, so a mob found in
-- three places says which one you actually farm it in. Kills from before this
-- was kept have no place and are counted as such, never guessed at.
--
-- Reporting to chat is off unless asked for, and it goes to your own chat
-- window only. Nothing is ever said on a channel anyone else can read.

local _, ns = ...
local L = ns.L

local Tracker = ns.NewModule("Tracker")

local Util = ns.Util

-- The harvester's export threshold, for the same reason.
local MIN_KILLS = 20

-- How many items a chat report names before it stops.
local REPORT_ITEMS = 4

Tracker.MIN_KILLS = MIN_KILLS

-- The kill that makes you a mob's champion (the owner, 2026-10-13): a
-- fanfare with Whitemane's "Arise, my champion!".
local CHAMPION_KILLS = 100
Tracker.CHAMPION_KILLS = CHAMPION_KILLS
-- The 1000th takes over the screen, and the mob is shown in legendary
-- orange from then on (2026-10-13, kept quiet like the 100th).
local BANE_KILLS = 1000
Tracker.BANE_KILLS = BANE_KILLS

-- This session only: kills per mob, and every corpse opened, by guid, with the
-- items already counted from it.
Tracker.session = {}
Tracker.corpses = {}

-- Corpses whose drops an area loot took with another's, by guid, this
-- session: skinning one later is not a kill of its own.
Tracker.areaLooted = {}

-- Also this session only: how much of each item came off corpses (your kills,
-- the rest of an area loot, corpses you only skinned), and the order mobs
-- were last killed in, so the panel can put the latest on top.
Tracker.sessionLoot = {}
-- Which mobs each item came from this session: sessionFrom[item][mob] = how
-- many. The panel's Loot tab lists them under the item.
Tracker.sessionFrom = {}
Tracker.sessionCopper = 0
Tracker.recent = {}
Tracker.clock = 0

-- Kill streak (2026-09-26): kills with no more than STREAK_GAP seconds
-- between them. `streak` is the one running, `bestStreak` this session's best.
local STREAK_GAP = 60
Tracker.STREAK_GAP = STREAK_GAP
Tracker.streak = 0
Tracker.bestStreak = 0
Tracker.streakAt = nil

--------------------------------------------------------------------------------
-- The tally
--------------------------------------------------------------------------------

--- Every mob's tally, kept in saved variables from one session to the next.
function Tracker:Store()
    local db = ns.db

    if type(db.tracker) ~= "table" then db.tracker = {} end
    if type(db.tracker.mobs) ~= "table" then db.tracker.mobs = {} end

    return db.tracker.mobs
end

function Tracker:GetMob(name)
    local mobs = self:Store()
    local mob = mobs[name]

    if type(mob) ~= "table" then
        mob = {}
        mobs[name] = mob
    end

    mob.kills = tonumber(mob.kills) or 0
    if type(mob.items) ~= "table" then mob.items = {} end

    -- Coin and amounts, with how many kills and corpses they were counted
    -- over. A kill's worth needs amounts, not just how often something drops,
    -- and an average is only right over the kills that recorded it.
    --
    -- Coin and amounts were first kept without that count, so they were
    -- divided by every kill, including all the ones from before: coin per
    -- kill came out a fraction of the real thing. A tally from then has no
    -- `coinKills`; its coin and amounts are set aside under old* rather than
    -- deleted, and counting starts clean from this kill.
    if mob.coinKills == nil then
        if (tonumber(mob.copper) or 0) > 0 then
            mob.oldCopper = (tonumber(mob.oldCopper) or 0) + tonumber(mob.copper)
        end
        if type(mob.qty) == "table" and next(mob.qty) then mob.oldQty = mob.qty end

        mob.copper = 0
        mob.qty = {}
        mob.stacks = {}
        mob.coinKills = 0
    end

    if type(mob.qty) ~= "table" then mob.qty = {} end
    if type(mob.stacks) ~= "table" then mob.stacks = {} end
    mob.copper = tonumber(mob.copper) or 0
    mob.coinKills = tonumber(mob.coinKills) or 0

    -- Kills by where they happened: "The Sepulcher, Silverpine Forest" = 12.
    if type(mob.places) ~= "table" then mob.places = {} end

    return mob
end

--- "The Sepulcher, Silverpine Forest", or the zone alone outside any subzone.
-- Nil when the client would not name the zone.
function Tracker.PlaceName(zone, location)
    if type(zone) ~= "string" or zone == "" then return nil end
    if type(location) ~= "string" or location == "" or location == zone then
        return zone
    end
    return location .. ", " .. zone
end

--- Count one opened corpse. Returns true if it was a new kill.
--
-- `guid` may be nil -- the client can refuse it inside an instance -- and then
-- the corpse cannot be recognised a second time, so every opening counts. That
-- over-counts a corpse you come back to, which is the lesser harm next to
-- dropping it. A window from your own Skinning cast on a corpse never opened
-- is not a kill at all (see OnLoot).
--
-- `place` is where it was killed (see PlaceName), or nil if the client would
-- not say; such a kill still counts, it just has no place.
--
-- `haul` is what LootedItems found beside this corpse's own loot: the rest of
-- an area loot window, and how much of this corpse's is locked. `skinning`
-- says the window came from your own Skinning cast.
function Tracker:Record(mobName, guid, items, quantities, copper, place, haul, skinning)
    local mob = self:GetMob(mobName)
    local corpse = guid and self.corpses[guid]
    local newKill = not corpse

    if newKill then
        corpse = {}
        if guid then self.corpses[guid] = corpse end

        mob.kills = mob.kills + 1
        self.session[mobName] = (self.session[mobName] or 0) + 1

        -- Coin is taken on the first opening; a second window on the same
        -- corpse is skinning or leftovers, never more coin. A kill with none
        -- still counts toward the average: that is what "per kill" means.
        mob.copper = mob.copper + (tonumber(copper) or 0)
        mob.coinKills = mob.coinKills + 1
        self.sessionCopper = self.sessionCopper + (tonumber(copper) or 0)

        -- The Stats tab's log (Logic/Stats.lua): the kill with the corpse's
        -- own drops (skinning aside), and its coin.
        if ns.Stats then
            ns.Stats:Kill(mobName, not skinning and items or nil, quantities)
            ns.Stats:Coin(copper)
        end

        -- Small cheers (Logic/Moments.lua): a lucky or long-awaited drop,
        -- or the best corpse of this mob yet. Never allowed to cost a kill.
        if ns.Moments and not skinning then
            local ok, err = pcall(ns.Moments.Kill, ns.Moments, mobName, mob, items, quantities, copper)
            if not ok then ns.Debug("moments:", tostring(err)) end
        end

        -- Area loot: the other corpses' part of the window is not this kill's
        -- drop, so the tally never sees it, but it is in your bags all the
        -- same, so the session's loot and coin take it.
        self:AddHaul(mobName, haul)

        if place then
            mob.places[place] = (tonumber(mob.places[place]) or 0) + 1
        end

        self:NoteStreak()
    end

    -- An item counts once per corpse, however many slots or visits it took.
    -- Leftovers seen again on a return visit add nothing to the loot total
    -- either: they were counted the first time the window showed them.
    --
    -- Skinning is not a return visit. A corpse is only skinned once it is
    -- empty, so everything the skinning window gives is new, even an item
    -- the corpse already gave (Ruined Leather Scraps looted, then skinned).
    -- Its amount counts; the corpse still held the item once.
    local locked = haul and haul.locked or {}
    for _, name in ipairs(items or {}) do
        local fresh = not corpse[name]
        if fresh or skinning then
            local quantity = quantities and quantities[name] or 1

            if fresh then
                corpse[name] = true
                mob.items[name] = (tonumber(mob.items[name]) or 0) + 1
                mob.stacks[name] = (tonumber(mob.stacks[name]) or 0) + 1
            end
            mob.qty[name] = (tonumber(mob.qty[name]) or 0) + quantity

            -- A locked slot (a roll, or the master looter's to give) still
            -- dropped, so the tally has it, but it is not yours unless you
            -- win it, so the session's loot leaves it out.
            local yours = quantity - (tonumber(locked[name]) or 0)
            if yours > 0 then
                if ns.Stats then ns.Stats:Loot("drops", name, yours) end
                self.sessionLoot[name] = (self.sessionLoot[name] or 0) + yours
                self.sessionFrom[name] = self.sessionFrom[name] or {}
                self.sessionFrom[name][mobName] = (self.sessionFrom[name][mobName] or 0) + yours
            end
        end
    end

    self.current = mobName
    self.clock = self.clock + 1
    self.recent[mobName] = self.clock

    -- Whichever you did last goes on top of the panel: this, or fishing.
    ns.lastLoot = "kill"

    if ns.TrackerUI then
        ns.TrackerUI:Refresh()
    end

    if newKill and ns.db.trackerReport then
        self:Report(mobName)
    end

    -- The kill that unlocks drop rates gets a fanfare.
    if newKill and mob.kills == MIN_KILLS then
        self:Celebrate(mobName)
    elseif newKill and mob.kills == CHAMPION_KILLS then
        self:Champion(mobName)
    elseif newKill and mob.kills == BANE_KILLS then
        self:Bane(mobName)
    end

    -- A kill that moves the mob up your top 15 gets a pop-up, a second
    -- later and never in a fight (Logic/RankUp.lua).
    if newKill and ns.RankUp then
        ns.RankUp:Killed(mobName)
    end

    return newKill
end

--- Loot that is yours but no kill's to tally: the rest of an area loot
--- window, or a corpse you only skinned. It goes into the session's loot and
--- coin under `mobName`, the corpse you opened, since the client names no
--- other.
function Tracker:AddHaul(mobName, haul)
    if type(haul) ~= "table" then return end

    for name, count in pairs(type(haul.items) == "table" and haul.items or {}) do
        if ns.Stats then ns.Stats:Loot("drops", name, count) end
        self.sessionLoot[name] = (self.sessionLoot[name] or 0) + count
        self.sessionFrom[name] = self.sessionFrom[name] or {}
        self.sessionFrom[name][mobName] = (self.sessionFrom[name][mobName] or 0) + count
    end

    self.sessionCopper = self.sessionCopper + (tonumber(haul.copper) or 0)
    if ns.Stats then ns.Stats:Coin(haul.copper) end
end

--- A corpse skinned without being opened first. What it gave is yours, so
--- the session's loot takes it; the kill tally never hears of it.
function Tracker:Skinned(mobName, items, quantities, haul)
    haul = haul or { items = {}, copper = 0, locked = {} }

    for _, name in ipairs(items or {}) do
        local yours = (quantities and quantities[name] or 1) - (tonumber(haul.locked[name]) or 0)
        if yours > 0 then haul.items[name] = (haul.items[name] or 0) + yours end
    end
    self:AddHaul(mobName, haul)

    if ns.TrackerUI then
        ns.TrackerUI:Refresh()
    end

    return false
end

--- Is the open loot window from your own Skinning cast? Gathering watches the
--- cast. Without it, every window counts the way it always has.
function Tracker.Skinning()
    local Gathering = ns.Gathering
    return (Gathering and Gathering.IsSkinning and Gathering:IsSkinning()) and true or false
end

--- One mob's tally, items best-seen first.
function Tracker:Summary(mobName)
    local mob = mobName and self:Store()[mobName]
    if type(mob) ~= "table" then return nil end

    local kills = tonumber(mob.kills) or 0
    local items = {}

    -- Skinning left out ("Hide skinning") and items on the hide list
    -- (DB:HidesItem) are not among the drops shown. They stay in the tally.
    local DB = ns.DB

    for name, corpses in pairs(type(mob.items) == "table" and mob.items or {}) do
        corpses = tonumber(corpses) or 0
        if not (DB and DB:HidesItem(name)) then
            items[#items + 1] = {
                name = name,
                corpses = corpses,
                chance = kills > 0 and math.min(100, corpses / kills * 100) or 0,
            }
        end
    end

    table.sort(items, function(a, b)
        if a.corpses ~= b.corpses then return a.corpses > b.corpses end
        return a.name < b.name
    end)

    local places, unplaced = self:Places(mobName)

    return {
        mob = mobName,
        kills = kills,
        session = self.session[mobName] or 0,
        rated = kills >= MIN_KILLS,
        needed = math.max(0, MIN_KILLS - kills),
        items = items,
        places = places,
        unplaced = unplaced,
    }
end

--- Where a mob has been killed, most kills first: { name, kills }. Second,
--- how many of its kills have no place: from before places were kept, or
--- killed where the client would not name the zone.
function Tracker:Places(mobName)
    local mob = mobName and self:Store()[mobName]
    if type(mob) ~= "table" then return {}, 0 end

    local places, placed = {}, 0

    for name, kills in pairs(type(mob.places) == "table" and mob.places or {}) do
        kills = tonumber(kills) or 0
        if kills > 0 then
            places[#places + 1] = { name = name, kills = kills }
            placed = placed + kills
        end
    end

    table.sort(places, function(a, b)
        if a.kills ~= b.kills then return a.kills > b.kills end
        return a.name < b.name
    end)

    return places, math.max(0, (tonumber(mob.kills) or 0) - placed)
end

--- "The Sepulcher, Silverpine Forest (12); Silverpine Forest (3)": the first
--- `limit` places, "+2 more" after them. Nil for a mob with no place yet.
function Tracker.PlacesText(places, limit)
    if type(places) ~= "table" or #places == 0 then return nil end

    limit = limit or #places
    local parts = {}

    for index = 1, math.min(#places, limit) do
        local place = places[index]
        parts[#parts + 1] = #places == 1 and place.name
            or ("%s (%d)"):format(place.name, place.kills)
    end

    if #places > limit then
        parts[#parts + 1] = L.Format("+%d more", #places - limit)
    end

    -- Semicolons, since a place name has a comma of its own.
    return table.concat(parts, "; ")
end

--- Average coin per kill, over the kills that recorded coin; nil before any.
function Tracker:CoinPerKill(mobName)
    local mob = mobName and self:Store()[mobName]
    if type(mob) ~= "table" then return nil end

    local kills = tonumber(mob.coinKills) or 0
    if kills <= 0 then return nil end

    return (tonumber(mob.copper) or 0) / kills
end

--- How many of an item one corpse that held it gave, on average. 1 for an
--- item whose amounts were never recorded.
function Tracker:StackSize(mobName, itemName)
    local mob = mobName and self:Store()[mobName]
    if type(mob) ~= "table" or mob.coinKills == nil then return 1 end

    local qty = type(mob.qty) == "table" and tonumber(mob.qty[itemName])
    local corpses = type(mob.stacks) == "table" and tonumber(mob.stacks[itemName])
    if not (qty and corpses and corpses > 0) then return 1 end

    return qty / corpses
end

--- A mob's whole loot table: its summary, with how many of each item it has
--- given in all and its coin per kill. Nil for a mob never killed.
--
-- Each item gains `perCorpse`, its average stack, and `amount`: corpses that
-- held it times that.
-- `coinPerKill` is nil until a kill has recorded coin.
function Tracker:LootTable(mobName)
    local summary = self:Summary(mobName)
    if not summary then return nil end

    for _, item in ipairs(summary.items) do
        item.perCorpse = self:StackSize(mobName, item.name)
        item.amount = math.floor(item.corpses * item.perCorpse + 0.5)
    end

    summary.coinPerKill = self:CoinPerKill(mobName)
    summary.coinKills = tonumber(self:Store()[mobName].coinKills) or 0

    return summary
end

--- Every mob killed this session, most recent first, as summaries.
function Tracker:SessionMobs()
    local mobs = {}

    for name in pairs(self.session) do
        -- A mob on the hide list is not on the panel (DB:IsHiddenSource).
        local summary = not (ns.DB and ns.DB:IsHiddenSource(name)) and self:Summary(name)
        if summary then mobs[#mobs + 1] = summary end
    end

    table.sort(mobs, function(a, b)
        return (self.recent[a.mob] or 0) > (self.recent[b.mob] or 0)
    end)

    return mobs
end

--- Is the item named `name` counted in what the panel shows? Not while
--- it is left out: skinning hidden, or on the hide list (DB:HidesItem).
--- The session's counts keep it either way.
function Tracker.Counts(name)
    local DB = ns.DB
    return not (DB and DB.HidesItem and DB:HidesItem(name))
end

--- This session's loot, most first: { name, count }.
function Tracker:SessionLoot()
    local loot = {}

    for name, count in pairs(self.sessionLoot) do
        if Tracker.Counts(name) then loot[#loot + 1] = { name = name, count = count } end
    end

    table.sort(loot, function(a, b)
        if a.count ~= b.count then return a.count > b.count end
        return a.name < b.name
    end)

    return loot
end

--- This session's kills, all mobs together.
function Tracker:SessionKills()
    local total = 0
    for _, kills in pairs(self.session) do total = total + kills end
    return total
end

--- "43%", "7.5%", "<1%": whole numbers once they are big enough not to care.
function Tracker.FormatChance(chance)
    if chance > 0 and chance < 1 then return "<1%" end
    if chance < 10 then
        return (("%.1f"):format(chance):gsub("%.0$", "")) .. "%"
    end
    return ("%d%%"):format(math.floor(chance + 0.5))
end

--- A mob named loosely, the way a person types it: exact, then a prefix.
function Tracker:ResolveMob(text)
    text = Util.Trim(text):lower()
    if text == "" then return self.current end

    local prefix

    for name in pairs(self:Store()) do
        local lowered = name:lower()
        if lowered == text then return name end
        if lowered:sub(1, #text) == text and (not prefix or name < prefix) then
            prefix = name
        end
    end

    return prefix
end

function Tracker:Reset()
    -- Shared and imported counts went with the records: their ledgers too.
    if ns.Share and ns.Share.ForgetSection then ns.Share:ForgetSection("k") end
    -- The kills go; what each item looks like (its id, colour and icon, read
    -- off loot links) stays. Prices, grey detection and the fishing and
    -- gathering values all lean on it, and none of it is a tally.
    local old = ns.db.tracker
    local looks = type(old) == "table" and type(old.looks) == "table" and old.looks or nil
    ns.db.tracker = looks and { looks = looks } or nil
    -- Kills since each drop and each mob's best corpse go with the kills.
    ns.db.dropWaits = nil
    ns.db.bestCorpses = nil
    if ns.Moments then ns.Moments.bestDrop = nil end
    self.session = {}
    self.corpses = {}
    self.areaLooted = {}
    self.sessionLoot = {}
    self.sessionFrom = {}
    self.sessionCopper = 0
    self.recent = {}
    self.current = nil
    self.streak = 0
    self.bestStreak = 0
    self.streakAt = nil

    if ns.TrackerUI then
        if ns.TrackerUI.ResetState then ns.TrackerUI:ResetState() end
        ns.TrackerUI:Refresh()
    end
end

--- The game's clock, in seconds. Nil where there is none (the tests).
local function Now()
    if type(GetTime) ~= "function" then return nil end
    local ok, now = pcall(GetTime)
    return ok and type(now) == "number" and now or nil
end

--- A new kill: the streak goes on if the last kill was recent, else starts
--- again at one.
function Tracker:NoteStreak(now)
    now = now or Now()

    if now and self.streakAt and now - self.streakAt <= STREAK_GAP then
        self.streak = self.streak + 1
    else
        self.streak = 1
    end

    self.streakAt = now
    self.bestStreak = math.max(self.bestStreak, self.streak)

    -- The panel only redraws when something happens, so ask it to look
    -- again once the gap has passed, when the streak has run out.
    if now and C_Timer and type(C_Timer.After) == "function" then
        pcall(C_Timer.After, STREAK_GAP + 1, function()
            if ns.TrackerUI and Tracker:Streak() == 0 then ns.TrackerUI:Refresh() end
        end)
    end
end

--- The streak running now: zero once STREAK_GAP has passed since the last kill.
function Tracker:Streak(now)
    now = now or Now()
    if now and self.streakAt and now - self.streakAt > STREAK_GAP then return 0 end
    return self.streak
end

--------------------------------------------------------------------------------
-- Reading the loot window
--------------------------------------------------------------------------------

--- The corpse's guid, if the client will say. Read, not compared, like every
--- other value off this client.
function Tracker:CorpseID()
    return ns.Harvest:CorpseID()
end

--------------------------------------------------------------------------------
-- How an item looks
--
-- The panel draws each item with its icon and in its quality colour, the way
-- the bags do. Both come off the loot window the first time an item is seen
-- and are kept, so the panel can draw them long after the window closed.
--------------------------------------------------------------------------------

-- Quality colours, for links that name a quality rather than spell a colour.
local QUALITY = {
    [0] = "ff9d9d9d", [1] = "ffffffff", [2] = "ff1eff00", [3] = "ff0070dd",
    [4] = "ffa335ee", [5] = "ffff8000", [6] = "ffe6cc80",
}

Tracker.QUALITY = QUALITY

function Tracker:Looks()
    local db = ns.db
    if type(db.tracker) ~= "table" then db.tracker = {} end
    if type(db.tracker.looks) ~= "table" then db.tracker.looks = {} end
    return db.tracker.looks
end

--- An icon as the client gives it: a file id (a number) or a texture path.
local function ReadableIcon(value)
    return ns.Harvest.ReadableNumber(value) or ns.Harvest.Readable(value)
end

--- "ff1eff00" out of an item link, whichever way the link spells its colour.
function Tracker.LinkColor(link)
    if type(link) ~= "string" then return nil end

    local hex = link:match("^|c(%x%x%x%x%x%x%x%x)")
    if hex then return hex:lower() end

    -- Newer clients write |cnIQ2:...| and leave the colour to the client.
    local quality = tonumber(link:match("^|cnIQ(%d)"))
    if quality then return QUALITY[quality] end

    return nil
end

function Tracker:NoteLook(slot, name, icon)
    local looks = self:Looks()
    local look = looks[name]

    if type(look) ~= "table" then
        look = {}
        looks[name] = look
    end

    look.icon = look.icon or ReadableIcon(icon)

    if (not look.color or not look.id) and GetLootSlotLink then
        local ok, link = pcall(GetLootSlotLink, slot)
        local text = ok and ns.Harvest.Readable(link) or nil
        local color, id = look.color, look.id

        look.color = look.color or Tracker.LinkColor(text)

        -- The item id is what prices are kept by.
        if not look.id and text then
            look.id = tonumber(text:match("item:(%d+)"))
        end
        -- Counted so a reader that indexes the looks (Value.GreyLinks)
        -- knows to walk them again; only when something was learned, since
        -- a link the client keeps hidden (in a dungeon) teaches nothing and
        -- walking every look again on each such loot is a hitch.
        if look.color ~= color or look.id ~= id then
            self.looksVersion = (self.looksVersion or 0) + 1
        end
    end
end

function Tracker:LookOf(name)
    local look = self:Looks()[name]
    if type(look) ~= "table" then return {} end
    return look
end

--- Copper in a coin slot's name: "1 Gold 2 Silver 3 Copper" is 10203.
-- Nil for anything that is not plainly coin. The coin words are the
-- client's too (Harvest.CoinValue: "1 Gold 2 Silber 3 Kupfer").

function Tracker.CoinCopper(name)
    if not ns.Harvest:NameLooksLikeMoney(name) then return nil end

    local copper = 0
    for amount, unit in name:gmatch("(%d+)%s+(%a+)") do
        copper = copper + tonumber(amount) * (ns.Harvest.CoinValue(unit) or 0)
    end

    return copper
end

--- Is a loot slot locked? Only a plain true says so. Anything else, a value
--- the client will not let us read included, reads as no, which is how every
--- slot was read before this was asked.
local function IsLocked(value)
    if type(value) ~= "boolean" then return false end
    local ok, locked = pcall(function() return value == true end)
    return ok and locked == true
end

--- The items in the open loot window, each once, coins left out, and how
--- many of each (two slots of one item add up). Third: the coin, in copper.
--- Fourth, the haul: what else the window means for the session (below).
-- `anySource` takes every slot: a node or a catch is looted with whatever
-- happens to be targeted, so the corpse check below would throw it all away.
--
-- With area loot one window holds several corpses' drops. Only the one you
-- opened is this kill's, but the rest goes into your bags all the same:
-- `haul.items` and `haul.copper` are that rest, for the session's totals.
-- A slot the client shows locked (an item being rolled for, or waiting on the
-- master looter) still dropped, so it stays in this kill's items, but it may
-- never be yours: `haul.locked[name]` is how many of this corpse's are, and
-- nothing locked goes into `haul.items`.
function Tracker:LootedItems(anySource)
    local names, quantities, copper = {}, {}, 0
    local haul = { items = {}, copper = 0, locked = {} }

    local gotCount, lootCount = pcall(GetNumLootItems)
    local count = gotCount and ns.Harvest.ReadableNumber(lootCount) or nil
    if not count then return names, quantities, copper, haul end

    -- What other corpses already counted still hold: no part of the haul.
    local counted = anySource and {} or self:CountedShares(count)

    for slot = 1, count do
        local ok, slotIcon, slotName, slotQuantity, _, _, slotLocked = pcall(GetLootSlotInfo, slot)
        local text = ok and ns.Harvest.Readable(slotName) or nil
        local whole = ok and ns.Harvest.ReadableNumber(slotQuantity) or nil

        -- Area loot: another corpse's drop is not this kill's.
        local ours, share = true, nil
        if not anySource then ours, share = ns.Harvest:SlotIsTargets(slot) end
        local name = ours and text or nil

        if text and ns.Harvest:IsMoney(slot, text) then
            -- With area loot the name holds every corpse's coin; the share
            -- is this corpse's, in copper.
            local all = Tracker.CoinCopper(text) or 0
            local own = 0
            if name then
                own = share and ns.Harvest.ReadableNumber(share) or all
                copper = copper + own
            end
            haul.copper = haul.copper + math.max(0, all - own - (counted[slot] or 0))
        elseif text then
            local own = share or whole or 1
            local locked = IsLocked(slotLocked)

            if name then
                if not quantities[name] then
                    names[#names + 1] = name
                    quantities[name] = 0
                    self:NoteLook(slot, name, slotIcon)
                end

                quantities[name] = quantities[name] + own
                if locked then haul.locked[name] = (haul.locked[name] or 0) + own end
            end

            -- What is left of the slot came off the other corpses.
            local rest = (whole or 1) - (name and own or 0) - (counted[slot] or 0)
            if rest > 0 and not locked then
                if not name then self:NoteLook(slot, text, slotIcon) end
                haul.items[text] = (haul.items[text] or 0) + rest
            end
        end
    end

    return names, quantities, copper, haul
end

--- For each loot slot, how much of it belongs to corpses other than the one
--- opened that this session already counted: opened, or shown in an earlier
--- window's area loot. With full bags their leftovers come round again in
--- the next corpse's window, and the haul took them a second time. A slot
--- whose sources will not be read has none (as before).
function Tracker:CountedShares(count)
    local shares = {}
    if type(GetLootSourceInfo) ~= "function" then return shares end

    local Harvest = ns.Harvest
    local own = Harvest:CorpseID()

    for slot = 1, count do
        local ok, sources = pcall(function() return { GetLootSourceInfo(slot) } end)
        for index = 1, ok and #sources or 0, 2 do
            local guid = Harvest.Readable(sources[index])
            if guid and guid ~= own and (self.corpses[guid] or self.areaLooted[guid]) then
                shares[slot] = (shares[slot] or 0) + (Harvest.ReadableNumber(sources[index + 1]) or 0)
            end
        end
    end

    return shares
end

--- Is the corpse being skinned, never opened before, your own kill that
--- dropped nothing? Only when the client plainly says the kill was yours
--- (UnitIsTapDenied answers false on the corpse), no earlier area loot
--- took its drops, and this session saw it alive: a corpse looted before a
--- /reload looks unopened, and its skin would be a second kill.
--- Anything unreadable answers no, as it always did.
function Tracker:EmptyOwnKill(guid, unit)
    if not (guid and unit) or self.areaLooted[guid] then return false end
    if not ns.Harvest:SeenAlive(guid) then return false end
    if type(UnitIsTapDenied) ~= "function" then return false end

    local ok, denied = pcall(UnitIsTapDenied, unit)
    if not ok then return false end
    local readable, mine = pcall(function() return denied == false end)
    return readable and mine == true
end

function Tracker:OnLoot()
    local caps = ns.Harvest:Capabilities()
    if not caps.usable then return end

    -- Fishing pools, herbs and veins are not kills.
    if ns.Harvest:IsNodeLoot() then return end

    -- Same rule as the harvester: if the target is not plainly the corpse,
    -- count nothing rather than count it against the wrong mob.
    local mobName, _, guid, unit = ns.Harvest:Corpse()
    if not mobName then return end

    local items, quantities, copper, haul = self:LootedItems()
    local skinning = Tracker.Skinning()
    -- What a skin gives is noted as skinned, so "Hide skinning" leaves it
    -- out even where the data lists it only as a drop.
    if skinning and ns.DB and ns.DB.NoteSkinned then ns.DB:NoteSkinned(items) end
    -- And kept by mob, for what a skin is worth on the Grind tab.
    if skinning and ns.GrindGather then ns.GrindGather:NoteSkin(mobName, guid, items, quantities) end

    -- With area loot this window took the other corpses' drops too. Each of
    -- them is remembered, so skinning one later is not taken for a kill
    -- whose drops nobody counted (EmptyOwnKill).
    for _, source in ipairs(ns.Harvest:LootSources()) do
        if source ~= guid then self.areaLooted[source] = true end
    end

    -- A corpse skinned without being opened first this session (another
    -- player's kill, or one an area loot already emptied) shows none of
    -- what it dropped. Counted as a kill, its leather alone would pull every
    -- other drop's rate down, so it is not one; the leather is yours, so the
    -- session's loot takes it.
    --
    -- Your own kill that dropped nothing is the exception (2026-10-05: a
    -- Savannah Huntress killed, skinned and never on the Farm tab). An empty
    -- corpse opens no loot window, so skinning is the first the addon hears
    -- of it, and it is a kill like any other: one with no drops, which is
    -- what a drop rate has to count.
    if skinning and not (guid and self.corpses[guid]) then
        if not self:EmptyOwnKill(guid, unit) then
            return self:Skinned(mobName, items, quantities, haul)
        end
    end

    -- A corpse whose loot showed in another corpse's window (area loot) was
    -- counted there: its drops went into the session's loot, and it is no
    -- kill of its own. Full bags leave it holding what could not be taken,
    -- and opening it after other loot counted it again as a new kill with
    -- new drops (2026-10-13). Nothing it shows is new.
    if guid and not self.corpses[guid] and self.areaLooted[guid] then return false end

    local place = Tracker.PlaceName(ns.Harvest:Where())

    return self:Record(mobName, guid, items, quantities, copper, place, haul, skinning)
end

--------------------------------------------------------------------------------
-- Chat
--------------------------------------------------------------------------------

--- The one line a kill reports, or nil if the mob has no tally.
function Tracker:ReportLine(mobName)
    local summary = self:Summary(mobName)
    if not summary then return nil end

    local line = L.Format("%s: kill %d (%d this session)",
        Util.Colored("accent", summary.mob), summary.kills, summary.session)

    if not summary.rated then
        return line .. Util.Colored("muted",
            L.Format(", %d more for drop rates.", summary.needed))
    end

    if #summary.items == 0 then
        return line .. Util.Colored("muted", L[", nothing dropped yet."])
    end

    local parts = {}

    for index = 1, math.min(#summary.items, REPORT_ITEMS) do
        local item = summary.items[index]
        parts[#parts + 1] = ("%s %s"):format(item.name,
            Util.Colored("good", Tracker.FormatChance(item.chance)))
    end

    return line .. ". " .. table.concat(parts, ", ")
end

function Tracker:Report(mobName)
    local line = self:ReportLine(mobName)
    if line then ns.Print(line) end
end

--- Inside a dungeon, raid, battleground or arena? Read like any other client
-- value; when the client will not say, assume yes.
function Tracker.InInstance()
    if type(IsInInstance) ~= "function" then return false end
    local ok, inside = pcall(IsInInstance)
    if not ok then return true end
    local readable, answer = pcall(function() return inside == true or inside == 1 end)
    if not readable then return true end
    return answer == true
end

-- Sounds to try for the fanfare, best first: the achievement toast, then the
-- level-up chime, which every client has. Ids, since this client's SOUNDKIT
-- names are not known. Our own fanfare (below) goes ahead of both.
local FANFARE = { 12891, 888 }

-- The addon's own sounds (picked 2026-09-26), in Media/Sounds.
-- Made for this addon, so they are ours to ship. The game only finds a file
-- added since it started after a full restart; until then these fail and the
-- built-in sounds play instead.
local MEDIA = [[Interface\AddOns\Blackthornes_Farmer\Media\Sounds\]]

Tracker.SOUNDS = {
    unlock = MEDIA .. "drop-rates-unlocked.ogg",
    rare = MEDIA .. "rare-drop.ogg",
    -- A mob climbs your top 15 (2026-10-13), UI/RankUp.lua.
    rankup = MEDIA .. "rank-up.ogg",
    -- An auction scan puts a new mob first (2026-10-14), Logic/TopFarm.lua.
    topfarm = MEDIA .. "top-farm.ogg",
}

--- Play one of the addon's sound files. True if the client says it will.
function Tracker.PlayFile(path)
    if type(PlaySoundFile) ~= "function" then return false end

    local ok, willPlay = pcall(PlaySoundFile, path, "Master")
    return (ok and willPlay) and true or false
end

--- Drop rates just unlocked for `mobName`: a sound, a line in your own chat
--- and the banner. Nothing is said in public: the /emote it once sent went
--- (the owner, 2026-10-13), after Forever blocked it as "ADDON BLOCKED" at a
--- fishing spot's 20th cast. `/farm celebrate off` turns it all off.
function Tracker:Celebrate(mobName)
    if ns.db.trackerCelebrate == false then return end

    local summary = self:Summary(mobName)
    if not summary then return end

    local line = L.Format("Drop rates unlocked for %s after %d kills.",
        Util.Colored("accent", summary.mob), summary.kills)

    local best = summary.items[1]
    if best then
        line = line .. L.Format(" Best drop: %s %s.", best.name,
            Util.Colored("good", Tracker.FormatChance(best.chance)))
    else
        line = line .. L[" Nothing has dropped yet."]
    end

    self:Fanfare(line,
        { title = L["DROP RATES UNLOCKED"], subject = L.Format("%s  |  %d kills", summary.mob, summary.kills),
            key = "mob:" .. summary.mob })
end

--- The 100th kill of `mobName`: a line in your own chat, the banner and
--- Whitemane's "Arise, my champion!" (the fanfare's sound with voice lines
--- off). Follows /farm celebrate, like the 20th.
function Tracker:Champion(mobName)
    if ns.db.trackerCelebrate == false then return end

    local summary = self:Summary(mobName)
    if not summary then return end

    self:Fanfare(L.Format("%d kills of %s! You're its champion now.", summary.kills,
            Util.Colored("accent", summary.mob)),
        { title = L["CHAMPION"], subject = L.Format("%s  |  %d kills", summary.mob, summary.kills),
            key = "mob:" .. summary.mob, champion = true },
        "champion")
end

--- The 1000th kill's show, played once with no kill, as ChampionPreview:
--- nothing counted, saved or changed; the panel's first mob shows in
--- legendary orange until the next /reload, from memory alone.
function Tracker:BanePreview()
    local UI = ns.TrackerUI
    local first = self:SessionMobs()[1]
    local mobName = first and first.mob or L["Training Dummy"]

    if first and UI then
        UI.banePreview = mobName
        if UI.frame and UI.frame:IsShown() then pcall(UI.Refresh, UI) end
    end
    if ns.TrackerFX then ns.TrackerFX.saidAt.bane = nil end

    self:Bane(mobName, true)
end

--- The 1000th kill of a mob: the screen dims behind "BANE OF THE ...",
--- gold rays turning behind it, and Ragnaros's "DIE, INSECT!" (the fanfare's
--- sound with voice lines off). Follows /farm celebrate, like the 20th.
function Tracker:Bane(mobName, preview)
    if not preview and ns.db.trackerCelebrate == false then return end

    local summary = self:Summary(mobName)
    local name = summary and summary.mob or mobName
    local kills = math.max(BANE_KILLS, summary and summary.kills or 0)

    self:Fanfare(L.Format("%d kills of %s! You're the bane of its kind now.", kills,
            Util.Colored("accent", name)),
        { title = L["BANE OF ITS KIND"], subject = L.Format("%s  |  %d kills", name, kills),
            key = "mob:" .. name, bane = true, mob = name, kills = kills },
        "bane")
end

--- The 100th kill's show, played once with no kill, to try it out
--- (2026-10-13, the owner's test): a typed word on /farm celebrate that no
--- help or Settings names, as the reward itself is kept quiet. Nothing is
--- counted, saved or changed; the crown shows on the panel's first mob
--- until the next /reload, from memory alone.
function Tracker:ChampionPreview()
    local UI = ns.TrackerUI
    if not (UI and UI.frame and UI.frame:IsShown()) then
        ns.Print(L["open the kills panel first, then try again."])
        return
    end

    local first = self:SessionMobs()[1]
    local mobName = first and first.mob or L["Training Dummy"]
    local kills = math.max(CHAMPION_KILLS, first and first.kills or 0)

    if first then
        UI.crownPreview = mobName
        pcall(UI.Refresh, UI)
    end
    -- The voice line waits a while between plays; a test plays it now.
    if ns.TrackerFX then ns.TrackerFX.saidAt.champion = nil end

    self:Fanfare(L.Format("%d kills of %s! You're its champion now.", kills,
            Util.Colored("accent", mobName)),
        { title = L["CHAMPION"], subject = L.Format("%s  |  %d kills", mobName, kills),
            key = "mob:" .. mobName, champion = true },
        "champion")
end

--- The fanfare itself: `line` in your own chat, the sound, and `banner`
--- ({ title, subject, key }) across the top of the panel, or `voice` (a
--- TrackerFX.VOICE line) in place of the sound. Fishing and
--- gathering use it too, when a spot's catch rates unlock at 20 casts or a
--- node's gather rates at 20 gathers. The caller checks /farm celebrate.
--- It never sends chat: Forever blocks that from a loot event.
function Tracker:Fanfare(line, banner, voice)
    ns.PrintRaw(("|c%sBlackthornes Farmer:|r %s"):format(ns.COLORS.accent, line))

    if banner and ns.TrackerFX then
        local ok, err = pcall(ns.TrackerFX.Unlocked, ns.TrackerFX, banner)
        if not ok then ns.Debug("unlock banner:", tostring(err)) end
    end

    -- A voice line, when one is given and voice lines are on, in place of
    -- the sound.
    if voice and ns.TrackerFX and ns.TrackerFX:Say(voice) then return end

    if Tracker.PlayFile(Tracker.SOUNDS.unlock) then return end

    if type(PlaySound) == "function" then
        for _, sound in ipairs(FANFARE) do
            -- A sound the client does not have answers nil, a refused one
            -- false; either way the next one is tried.
            local ok, willPlay = pcall(PlaySound, sound, "Master")
            if ok and willPlay then break end
        end
    end
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

function Tracker:OnEnable()
    if not ns.Harvest:Capabilities().usable then return end

    ns.OnLootWindow(self, function() Tracker:OnLoot() end)
end

--------------------------------------------------------------------------------
-- Commands
--------------------------------------------------------------------------------

ns.RegisterCommand("tracker", L["show or hide the kill and loot panel (clear: empty what it shows, tallies kept; keep on/off: keep what it shows between sessions; group on/off: move it aside in a party or raid; size: small, normal, large or a percent)"], function(rest)
    local argument = Util.Trim(rest):lower()

    -- What the panel shows starts empty each session unless kept
    -- (Logic/Session.lua). Clearing empties only the view; every tally stays.
    local keep = argument:match("^keep%s*(%a*)$")
    if keep then
        local on
        if keep == "on" then on = true
        elseif keep == "off" then on = false
        else on = not (ns.Session and ns.Session.KeepOn()) end
        ns.db.keepPanel = on
        ns.Print(on
            and L["the kill and loot panel now keeps what it shows between sessions."]
            or L["the kill and loot panel now starts empty each session. Your kill tallies and drop rates are kept."])
        return
    end

    if argument == "clear" then
        if ns.Session then ns.Session:Clear() end
        ns.Print(L["kill and loot panel cleared. Your kill tallies and drop rates are kept."])
        return
    end

    if argument == "reset" then
        ns.Print(L["this clears every kill tally, for good. Type /farm tracker reset confirm to do it."])
        return
    end

    if argument == "reset confirm" then
        Tracker:Reset()
        ns.Print(L["kill tallies cleared."])
        return
    end

    -- How big the panel is drawn, as its gold corner grip and Settings'
    -- Kill tally size do (UI/Tracker.lua).
    local size = argument:match("^size%s*(.-)$")
    if size then
        local TrackerUI = ns.TrackerUI
        if not TrackerUI then return end
        local percent = TrackerUI.ParseSize(size)
        if not percent then
            ns.Print(L.Format("the kill and loot panel is at %s. /farm tracker size small, normal, large or a percent from %d%% to %d%% changes it, or drag the gold corner beside its bottom right.",
                TrackerUI.ScaleText(TrackerUI:DrawnPercent()), TrackerUI.SCALE_MIN, TrackerUI.SCALE_MAX))
            return
        end
        TrackerUI:Build()
        ns.Print(L.Format("kill and loot panel size: %s.", TrackerUI.ScaleText(TrackerUI:SetScalePercent(percent))))
        return
    end

    local group = argument:match("^group%s*(%a*)$")
    if group then
        local on
        if group == "on" then on = true
        elseif group == "off" then on = false
        else on = ns.db.trackerDodgeGroup == false end

        if ns.TrackerUI then ns.TrackerUI:SetDodgeGroup(on)
        else ns.db.trackerDodgeGroup = on end

        ns.Print(on
            and L["in a group, the panel moves aside from the party and raid frames."]
            or L["the panel stays put in a group. /farm tracker group on to move it aside."])
        return
    end

    if argument == "on" then
        ns.db.trackerHidden = false
    elseif argument == "off" then
        ns.db.trackerHidden = true
    else
        ns.db.trackerHidden = not ns.db.trackerHidden
    end

    if ns.TrackerUI then ns.TrackerUI:Refresh() end

    if ns.db.trackerHidden then
        ns.Print(L["kill and loot panel hidden. /farm tracker brings it back."])
    else
        ns.Print(L["kill and loot panel shown. /farm tracker hides it."])
    end
end)

ns.RegisterCommand("report", L["report each kill's tally in chat (on/off)"], function(rest)
    local argument = Util.Trim(rest):lower()

    if argument == "on" then
        ns.db.trackerReport = true
    elseif argument == "off" then
        ns.db.trackerReport = false
    else
        ns.db.trackerReport = not ns.db.trackerReport
    end

    if ns.db.trackerReport then
        ns.Print(L["reporting each kill in chat. Only you can see it. /farm report off to stop."])
    else
        ns.Print(L["kill reports off."])
    end
end)

ns.RegisterCommand("celebrate", L["sound and cheer at a mob's 20th kill, a fishing spot's 20th cast or a node's 20th gather (on/off)"],
    function(rest)
        local argument = Util.Trim(rest):lower()

        if argument == "champion" then return Tracker:ChampionPreview() end
        if argument == "bane" then return Tracker:BanePreview() end

        if argument == "on" then
            ns.db.trackerCelebrate = true
        elseif argument == "off" then
            ns.db.trackerCelebrate = false
        else
            ns.db.trackerCelebrate = ns.db.trackerCelebrate == false
        end

        ns.Print(ns.db.trackerCelebrate
            and L["a fanfare when rates unlock at 20 kills, casts or gathers. /farm celebrate off to stop."]
            or L["no fanfare when rates unlock. /farm celebrate on to bring it back."])
    end)

ns.RegisterCommand("kills", L["a mob's kill tally and drop rates"], function(rest)
    local mobName = Tracker:ResolveMob(rest or "")
    local summary = mobName and Tracker:Summary(mobName)

    if not summary then
        local wanted = Util.Trim(rest or "")
        if wanted == "" then
            ns.Print(L["nothing killed yet. Loot something and try again."])
        else
            ns.Print(L.Format("no kills of %s yet.", wanted))
        end
        return
    end

    ns.Print(Tracker:ReportLine(mobName))

    local where = Tracker.PlacesText(summary.places)
    if where then
        ns.PrintRaw(L.Format("  killed at %s", Util.Colored("muted", where)))
    end
    if summary.unplaced > 0 and #summary.places > 0 then
        ns.PrintRaw(Util.Colored("muted", L.Format("  %s with no place.",
            Util.Plural(summary.unplaced, L["kill"], L["kills"]))))
    end

    -- The chat line names the top few; this names them all.
    if summary.rated and #summary.items > REPORT_ITEMS then
        for index = REPORT_ITEMS + 1, #summary.items do
            local item = summary.items[index]
            ns.PrintRaw(("  %s %s"):format(item.name,
                Util.Colored("muted", Tracker.FormatChance(item.chance))))
        end
    elseif not summary.rated then
        for _, item in ipairs(summary.items) do
            ns.PrintRaw(("  %s %s"):format(item.name,
                Util.Colored("muted", L.Format("%d of %d", item.corpses, summary.kills))))
        end
    end
end)
