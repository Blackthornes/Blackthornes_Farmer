-- Blackthornes Farmer -- Logic/Harvest.lua
-- Record what actually drops, as you play.
--
-- Every fact this addon ships was copied from Classic and is a guess about
-- Forever. The client already knows the truth at the moment you loot a corpse:
-- which mob it was, its level, the zone, the subzone, where you are standing,
-- and what was inside. Count corpses looted and count the ones that held the
-- item, and that is a real drop rate, measured here rather than assumed.
--
-- Nothing is sent anywhere. It accumulates in SavedVariables from one session
-- to the next, and `/farm export` or tools/harvest_import.py hands it back as a
-- data file for the repository.
--
-- Nothing about this client's loot API is documented, so every call is behind
-- a capability check and the module degrades to doing less rather than
-- erroring. A missed sample is a missed sample; a Lua error mid-raid is not.

local _, ns = ...

local Harvest = ns.NewModule("Harvest")

local Util = ns.Util

-- Below this many corpses a percentage is noise, so the export omits the rate
-- and says how thin the sample was instead of inventing confidence.
local MIN_SAMPLE = 20

Harvest.records = {}
Harvest.enabled = true

-- Every corpse opened this session, by guid: which record it went into and
-- which items were already counted from it. See RecordCorpse.
Harvest.opened = {}

--------------------------------------------------------------------------------
-- Client capabilities
--------------------------------------------------------------------------------

local function Has(name)
    local path, object = name, _G
    local namespace, method = name:match("^([%w_]+)%.([%w_]+)$")

    if namespace then
        object = _G[namespace]
        if type(object) ~= "table" then return false end
        path = method
    end

    return type(object[path]) == "function"
end

function Harvest:Capabilities()
    if self.caps then return self.caps end

    self.caps = {
        lootSlotInfo = Has("GetLootSlotInfo"),
        lootSlotLink = Has("GetLootSlotLink"),
        lootSlotType = Has("GetLootSlotType"),
        numLootItems = Has("GetNumLootItems"),
        fishingLoot  = Has("IsFishingLoot"),
        bestMap      = Has("C_Map.GetBestMapForUnit"),
        playerPos    = Has("C_Map.GetPlayerMapPosition"),
        realZone     = Has("GetRealZoneText"),
        subZone      = Has("GetSubZoneText"),
    }

    self.caps.usable = self.caps.numLootItems and self.caps.lootSlotInfo
    return self.caps
end

--------------------------------------------------------------------------------
-- Values the client will not let us read
--
-- Forever inherited retail's secret values along with the instance rules that
-- go with them: inside a dungeon the client may hand an addon a name, a level
-- or a quantity that it is not willing to have inspected. The value looks
-- ordinary -- type() answers "string" -- but comparing, concatenating or
-- formatting it raises on the spot, and it raises in this addon's own stack
-- frame, because the execution reading it is tainted by this addon.
--
-- Seen in Ragefire Chasm on 2026-09-22. UnitName("target") came back
-- clean from its pcall and `name == ""` two lines later was the error. The
-- pcall around the call never had a chance: nothing was wrong with the call.
--
-- So nothing that came out of the client is touched outside a pcall. Every
-- such value goes through one of these two, where the reading itself is what
-- happens inside the pcall, and callers get back either an ordinary Lua value
-- or nil. An unreadable name costs a corpse, which is the trade this module
-- makes everywhere else already: a sample attributed to the wrong mob is worse
-- than no sample.
--------------------------------------------------------------------------------

-- The reads themselves, kept out here so each call passes them to pcall
-- rather than making a new function every time: these run on every event.
local function CopyText(value)
    -- The read is the test. Concatenating and comparing are both refused
    -- on a secret value, and refusing means raising, so doing them in here
    -- is how we find out. Whatever comes back out has survived both.
    local text = value .. ""
    if text == "" then return nil end
    return text
end

local function CopyNumber(value)
    -- Arithmetic and comparison, for the same reason as above. The
    -- comparison doubles as the not-a-number check.
    local number = value + 0
    if number ~= number then return nil end
    return number
end

--- A plain string copy of `value`, or nil if this client will not let us read it.
local function Readable(value)
    local kind = type(value)

    -- A number would concatenate cleanly below and is not a name, so it is
    -- ruled out first. Everything else -- nil, tables, secret values -- is
    -- ruled out by failing the read.
    if kind == "number" or kind == "boolean" then return nil end

    local ok, copy = pcall(CopyText, value)

    -- type() answers safely for a secret value and for nil alike, which is why
    -- the check out here is a type check and not a comparison.
    if not ok or type(copy) ~= "string" then return nil end

    return copy
end

--- `value` as a plain number, or nil if this client will not let us read it.
local function ReadableNumber(value)
    local kind = type(value)

    -- "12" would coerce to 12 in the arithmetic below, and a level that
    -- arrived as text is not one this module should be believing.
    if kind == "string" or kind == "boolean" then return nil end

    local ok, copy = pcall(CopyNumber, value)

    if not ok or type(copy) ~= "number" then return nil end

    return copy
end

-- The kill tracker reads the same loot window and the same target, so it reads
-- them through the same two doors.
Harvest.Readable = Readable
Harvest.ReadableNumber = ReadableNumber

--- Is the tooltip showing a unit or an item, rather than a world object such
--- as a school or a herb?
--
-- Older clients ask the tooltip itself (GetUnit, GetItem); the retail engine
-- moved both to TooltipUtil. Whichever this client has is asked, so a mob
-- called "... Swarm" cannot pass for a fishing school, and a mob under the
-- mouse is never remembered as the node about to be picked.
-- Is there a value at all? type() is the one thing a secret value answers,
-- so this never touches the value itself. `name ~= nil` looked harmless, but
-- on a mob in a dungeon the name is secret and the comparison raised, once
-- per hook, every time the tooltip showed a mob.
local function Present(value)
    return type(value) ~= "nil"
end

--- A drop rate as the export writes it, or nil to leave the field out. The
--- data refuses 0, so a rare drop is kept to a decimal place, and one too rare
--- to show at all is listed without a rate.
function Harvest.ExportChance(percent)
    if type(percent) ~= "number" or percent ~= percent then return nil end
    if percent >= 99.95 then return "chance = 100" end
    if percent >= 0.95 then return ("chance = %d"):format(math.floor(percent + 0.5)) end
    if percent >= 0.05 then return ("chance = %.1f"):format(percent) end
    return nil
end

function Harvest.TooltipShowsUnitOrItem(tooltip)
    if type(tooltip) ~= "table" then return false end

    for _, method in ipairs({ "GetUnit", "GetItem" }) do
        if type(tooltip[method]) == "function" then
            local ok, name = pcall(tooltip[method], tooltip)
            if ok and Present(name) then return true end
        end
    end

    local util = _G.TooltipUtil
    if type(util) == "table" then
        for _, method in ipairs({ "GetDisplayedUnit", "GetDisplayedItem" }) do
            if type(util[method]) == "function" then
                local ok, name = pcall(util[method], tooltip)
                if ok and Present(name) then return true end
            end
        end
    end

    return false
end

--------------------------------------------------------------------------------
-- Where and what
--------------------------------------------------------------------------------

--- The player's position as map percentages, or nil if the client will not say.
--- Where the player stands on the map the client is showing them in:
--- mapID, x, y, with x and y as fractions of that map (0 to 1). Nil when the
--- client will not say, which inside an instance it usually will not.
function Harvest:PlayerMapPosition()
    local caps = self:Capabilities()
    if not (caps.bestMap and caps.playerPos) then return nil end

    local ok, mapID = pcall(C_Map.GetBestMapForUnit, "player")
    mapID = ok and ReadableNumber(mapID) or nil
    if not mapID then return nil end

    local gotPosition, position = pcall(C_Map.GetPlayerMapPosition, mapID, "player")
    if not gotPosition or not position then return nil end

    -- A map position is a vector object on modern clients; older ones hand
    -- back two plain numbers.
    local x, y

    if type(position) == "table" and type(position.GetXY) == "function" then
        local readable, px, py = pcall(position.GetXY, position)
        if readable then x, y = px, py end
    elseif type(position) == "number" then
        local readable, _, py = pcall(C_Map.GetPlayerMapPosition, mapID, "player")
        if readable then x, y = position, py end
    end

    -- Read rather than type-checked: a coordinate off a restricted client is
    -- as liable to be secret as a name, and this one is about to be compared.
    x, y = ReadableNumber(x), ReadableNumber(y)

    if not x or not y then return nil end
    if x == 0 and y == 0 then return nil end

    return mapID, x, y
end

--- The player's map coordinates in percent, as the game shows them: 45.2, 68.0.
function Harvest:PlayerPosition()
    local mapID, x, y = self:PlayerMapPosition()
    if not mapID then return nil end

    return x * 100, y * 100
end

--- The corpse being looted, as far as the client will admit.
--
-- The loot window does not name its owner. The target is the corpse in the
-- usual case, so that is asked first. But plenty of players loot without
-- targeting the corpse: the interact key, a right-click on a corpse with
-- another mob targeted, auto loot with the target already cleared. Waiting
-- for the target counted none of those (a player's report, 2026-10-05: the
-- kills panel stayed empty), so when the target is not the corpse, the
-- window's own sources are asked whose loot it is (GetLootSourceInfo), and
-- the corpse is the one of them the client names under the mouse or the
-- interact key, or one this addon saw alive by that same guid (NoteUnit).
--
-- Every way in matches by guid, so nothing is guessed: a window whose
-- sources cannot be read, or whose mob was never seen, is still dropped. A
-- sample attributed to the wrong mob is worse than no sample: it goes into
-- the data and sends somebody to the wrong place.
--
-- Returns the name, the level (nil when unknown), the guid (nil when the
-- client will not give one) and the unit token the corpse is ("target",
-- "mouseover", "softinteract"; nil when it was only known by its guid).
function Harvest:Corpse()
    local name, level, guid = self:UnitCorpse("target")
    if name and self:LootIsFrom(guid) then return name, level, guid, "target" end

    local sources = self:LootSources()
    if #sources == 0 then return nil end

    local listed = {}
    for _, source in ipairs(sources) do listed[source] = true end

    for _, unit in ipairs(Harvest.CORPSE_UNITS) do
        local unitName, unitLevel, unitGuid = self:UnitCorpse(unit)
        if unitName and unitGuid and listed[unitGuid] then
            return unitName, unitLevel, unitGuid, unit
        end
    end

    for _, source in ipairs(sources) do
        local known = self:KnownUnit(source)
        if known then return known.name, known.level, source end
    end

    return nil
end

-- Units that can be the corpse when the target is not: the one under the
-- mouse (a right-click loot) and the interact key's (soft interact).
Harvest.CORPSE_UNITS = { "softinteract", "mouseover" }

--- A dead mob in `unit`, as name, level and guid; nil for anything else.
-- Not `name == ""`: in an instance that comparison is the line that blew
-- up. Comparisons happen inside Readable, where a raise is an answer.
function Harvest:UnitCorpse(unit)
    if not UnitName or not UnitIsDead then return nil end

    local ok, dead = pcall(UnitIsDead, unit)
    if not ok then return nil end
    local plain, isDead = pcall(function() return dead == true or dead == 1 end)
    if not plain or not isDead then return nil end

    local gotName, unitName = pcall(UnitName, unit)
    if not gotName then return nil end

    local name = Readable(unitName)
    if not name then return nil end

    -- Players and their corpses are not farming spots.
    if UnitIsPlayer then
        local gotPlayer, isPlayer = pcall(UnitIsPlayer, unit)
        if gotPlayer then
            local readable, player = pcall(function() return isPlayer == true or isPlayer == 1 end)
            if not readable or player then return nil end
        end
    end

    local level
    if UnitLevel then
        local gotLevel, unitLevel = pcall(UnitLevel, unit)
        local number = gotLevel and ReadableNumber(unitLevel) or nil
        -- -1 is the client's way of saying "higher than you can tell".
        if number and number > 0 then
            level = number
        end
    end

    local guid
    if UnitGUID then
        local gotGuid, unitGuid = pcall(UnitGUID, unit)
        if gotGuid then guid = Readable(unitGuid) end
    end

    return name, level, guid
end

function Harvest:LootSource()
    local name, level = self:Corpse()
    return name, level
end

--------------------------------------------------------------------------------
-- Mobs seen alive
--
-- A guid names no mob by itself, so the mobs you meet are remembered by guid
-- as the client shows them: your target, the mob under the mouse, nameplates
-- coming into view, the interact key's unit. A corpse looted without being
-- targeted is then recognised by the guid the loot window gives for it.
-- Memory only, and kept short: two lots of SEEN_LIMIT at most.
--------------------------------------------------------------------------------

local SEEN_LIMIT = 300

Harvest.seen, Harvest.seenOld, Harvest.seenCount = {}, {}, 0

function Harvest:NoteUnit(unit)
    if not UnitGUID or not UnitName then return end

    local gotGuid, unitGuid = pcall(UnitGUID, unit)
    local guid = gotGuid and Readable(unitGuid) or nil
    if not guid or not guid:match("^Creature%-") and not guid:match("^Vehicle%-") then return end

    local gotName, unitName = pcall(UnitName, unit)
    local name = gotName and Readable(unitName) or nil
    if not name then return end

    local level
    if UnitLevel then
        local gotLevel, unitLevel = pcall(UnitLevel, unit)
        local number = gotLevel and ReadableNumber(unitLevel) or nil
        if number and number > 0 then level = number end
    end

    -- Seen alive this session: once it is, it stays so after it dies.
    local known = self:KnownUnit(guid)
    local alive = known and known.alive or false
    if not alive and UnitIsDead then
        local gotDead, dead = pcall(UnitIsDead, unit)
        local readable, living = pcall(function() return gotDead and dead == false end)
        alive = readable and living == true
    end

    if not self.seen[guid] then
        self.seenCount = self.seenCount + 1
        if self.seenCount > SEEN_LIMIT then
            self.seenOld, self.seen, self.seenCount = self.seen, {}, 1
        end
    end
    self.seen[guid] = { name = name, level = level, alive = alive or nil }
end

function Harvest:KnownUnit(guid)
    if type(guid) ~= "string" then return nil end
    return self.seen[guid] or self.seenOld[guid]
end

--- Did this session see the mob alive? A corpse it never saw alive may be
--- one looted before a /reload, which the addon cannot tell from new.
function Harvest:SeenAlive(guid)
    local known = self:KnownUnit(guid)
    return known ~= nil and known.alive == true
end

--- Where you are standing: the zone, and the subzone if you are in one.
-- Either is nil when the client will not say.
function Harvest:Where()
    local caps = self:Capabilities()
    local zone, location

    if caps.realZone then
        local gotZone, zoneText = pcall(GetRealZoneText)
        if gotZone then zone = Readable(zoneText) end
    end

    if caps.subZone then
        -- Readable answers nil for the empty string a mob outside any
        -- subzone comes back with, which is what this wants anyway.
        local gotSub, subText = pcall(GetSubZoneText)
        if gotSub then location = Readable(subText) end
    end

    return zone, location
end

--- The corpse's guid, if the client will say. Read, not compared.
function Harvest:CorpseID()
    local name, _, guid = self:Corpse()
    if name then return guid end

    if not UnitGUID then return nil end
    local ok, target = pcall(UnitGUID, "target")
    if not ok then return nil end
    return Readable(target)
end

--- Is the open loot window a fishing catch or a gathered herb or vein?
--
-- Either way it is nobody's corpse, whatever is targeted. A herb picked with
-- a looted corpse still targeted used to go down as that corpse's drop.
function Harvest:IsNodeLoot()
    if self:Capabilities().fishingLoot then
        local ok, fishing = pcall(IsFishingLoot)
        if ok then
            -- Read before it is believed, as Fishing:IsCatch does.
            local readable, answer = pcall(function() return fishing == true or fishing == 1 end)
            if readable and answer == true then return true end
        end
    end

    return ns.Gathering ~= nil and ns.Gathering:IsGathering()
end

-- A guid the client spells "Creature-0-...", "GameObject-0-...": the kinds
-- that can own a loot window.
local GUID_KIND = {
    Creature = true, Vehicle = true, Pet = true, Player = true,
    GameObject = true, Item = true,
}

local function GuidKind(guid)
    local kind = type(guid) == "string" and guid:match("^(%a+)%-") or nil
    return kind and GUID_KIND[kind] and kind or nil
end

--- Every guid the open loot window names as a source, each once, in slot
--- order: the corpses (and chests, and nodes) its loot came off. Empty when
--- the client will not say.
function Harvest:LootSources()
    -- While one loot window is being read every reader asks this many times
    -- over (once per slot, and again per corpse check), and nothing in the
    -- window can change in between, so the first answer serves the rest.
    local reading = self.lootReading
    if reading and reading.sources then return reading.sources end

    local list, seen = {}, {}
    if reading then reading.sources = list end
    if type(GetLootSourceInfo) ~= "function" then return list end

    local gotCount, lootCount = pcall(GetNumLootItems)
    local count = gotCount and ReadableNumber(lootCount) or nil
    if not count then return list end

    for slot = 1, count do
        local ok, sources = pcall(function() return { GetLootSourceInfo(slot) } end)

        -- Guid, quantity, guid, quantity...
        for index = 1, ok and #sources or 0, 2 do
            local guid = Readable(sources[index])
            if GuidKind(guid) and not seen[guid] then
                seen[guid] = true
                list[#list + 1] = guid
            end
        end
    end

    return list
end

--- Does the open loot window belong to `guid`?
--
-- Where the client says whose loot each slot is (GetLootSourceInfo), a window
-- none of whose slots is that unit's -- a chest, a clam opened from the bags,
-- another corpse -- is not its loot. This answers false only on that
-- evidence: guids it cannot read, or a client spelling them some other way,
-- leave it answering true, the way it was before it asked.
function Harvest:LootIsFrom(guid)
    if not GuidKind(guid) then return true end

    local sources = self:LootSources()
    if #sources == 0 then return true end

    for _, source in ipairs(sources) do
        if source == guid then return true end
    end
    return false
end

--- Does the open loot window belong to the corpse being looted? Corpse()
--- only names one it does, so this is whether there is one.
function Harvest:LootIsTargets()
    return (self:Corpse()) ~= nil
end

--- Whether loot slot `slot` came off the corpse you target, and if the
--- client says so, how many of it came off that corpse.
--
-- With area loot one window holds several corpses' drops. Counting them all
-- against the one you clicked would make it look like it dropped three
-- times as much, so a slot whose sources are readable and are all other
-- corpses is left out. Anything unreadable counts, as before: this only
-- ever takes away what the client plainly says is someone else's.
function Harvest:SlotIsTargets(slot)
    if type(GetLootSourceInfo) ~= "function" then return true end

    local target = self:CorpseID()
    if not GuidKind(target) then return true end

    local ok, sources = pcall(function() return { GetLootSourceInfo(slot) } end)
    if not ok then return true end

    local elsewhere = false
    for index = 1, #sources, 2 do
        local guid = Readable(sources[index])
        if guid == target then return true, ReadableNumber(sources[index + 1]) end
        if GuidKind(guid) then elsewhere = true end
    end

    return not elsewhere
end

--------------------------------------------------------------------------------
-- Recording
--------------------------------------------------------------------------------

local function RecordKey(mob, zone, location)
    return ("%s|%s|%s"):format(mob, zone or "?", location or "")
end

function Harvest:GetRecord(mob, level, zone, location)
    local key = RecordKey(mob, zone, location)
    local record = self.records[key]

    if not record then
        record = {
            mob = mob,
            zone = zone,
            location = location,
            minLevel = level,
            maxLevel = level,
            corpses = 0,
            items = {},
        }
        self.records[key] = record
    end

    -- A mob type spans a level band; widen it as we meet the edges.
    if level then
        record.minLevel = math.min(record.minLevel or level, level)
        record.maxLevel = math.max(record.maxLevel or level, level)
    end

    return record
end

--- Is this loot slot money rather than an item?
--
-- A loot window lists coins in a slot like anything else, and GetLootSlotInfo
-- hands back a name for it -- "23 Copper" -- which went straight into the data
-- as if it were a farmable drop. The first real session produced 25 coin
-- entries out of 53.
--
-- Two ways of telling. GetLootSlotType says so outright and is authoritative
-- where it exists, which on this client is not yet known. Failing that, the
-- name reads as coins -- a weaker test, because a real item could in principle
-- be named that way, and the reason NameLooksLikeMoney is as strict as it is.
--
-- A third test suggests itself and is deliberately not used: money has no item
-- link. That is true of coins, but it is equally true of any item the link
-- call happens to fail for, and it deleted Silver Bar the first time it was
-- tried. Dropping a real drop is worse than keeping a coin.
local COIN = { Copper = true, Silver = true, Gold = true }

function Harvest:IsMoney(slot, name)
    local caps = self:Capabilities()

    -- Pruning old data has no slot to ask about: the loot window is long
    -- closed. Both slot tests would then be asking about slot nil, and the
    -- link test in particular would answer "no link, so money" for every item
    -- in the database. Skip to the name.
    if slot == nil then return self:NameLooksLikeMoney(name) end

    if caps.lootSlotType then
        local ok, slotType = pcall(GetLootSlotType, slot)
        -- Read before it is compared, like everything else off this client.
        local kind = ok and ReadableNumber(slotType) or nil

        -- LOOT_SLOT_MONEY is 2 on every client that defines it; the constant
        -- itself may not exist here, so compare to both.
        if kind then
            if kind == (LOOT_SLOT_MONEY or 2) then return true end
            if kind == (LOOT_SLOT_ITEM or 1) then return false end
        end
    end

    return self:NameLooksLikeMoney(name)
end

--- "23 Copper", "1 Gold 2 Silver 3 Copper" -- and nothing else.
--
-- Every part of the name has to be a number followed by a coin, with nothing
-- left over, so "Copper Ore" and "10 Pound Sledge" are safely items.
function Harvest:NameLooksLikeMoney(name)
    if type(name) ~= "string" or name == "" then return false end

    local words, coins = 0, 0

    for _, unit in name:gmatch("(%d+)%s+(%a+)") do
        words = words + 1
        if COIN[unit] then coins = coins + 1 end
    end

    if words == 0 or words ~= coins then return false end

    return (name:gsub("%d+%s+%a+%s*", "")) == ""
end

--- One looted corpse: the denominator of every rate this module reports.
function Harvest:RecordCorpse()
    if not self.enabled then return end

    local caps = self:Capabilities()
    if not caps.usable then return end

    -- Fishing pools, herbs and veins are not mobs.
    if self:IsNodeLoot() then return end

    local mob, level = self:LootSource()
    local _, _, sourceGuid, unit = self:Corpse()
    if not mob or not self:LootIsTargets() then
        self.skipped = (self.skipped or 0) + 1
        return
    end

    -- One corpse opened twice is one corpse. Skinning opens a second loot
    -- window on a corpse already looted, and so does coming back for what
    -- was left; counting each as a corpse would halve every other item's
    -- rate on anything you skin. What the second opening finds -- the leather
    -- -- is still a drop from that corpse and is counted, once.
    --
    -- Without a readable guid (an instance can refuse it) the corpse cannot
    -- be recognised again, so each opening counts as before, apart from a
    -- skinning one, which never starts a corpse (next).
    --
    -- A corpse first opened by skinning is no sample at all: it is another
    -- player's kill, one whose drops an area loot already took with another
    -- corpse's, or one looted before a /reload. Its drops are not in this
    -- window, so counting it would add a corpse that held nothing.
    --
    -- Your own kill that dropped nothing is the exception, as in the kill
    -- tally (Tracker:EmptyOwnKill): it opens no window until the skin, and a
    -- rate has to count the corpses that held nothing.
    local guid = self:CorpseID()
    local corpse = guid and self.opened[guid]
    local record

    if corpse then
        record = corpse.record
    elseif ns.Gathering ~= nil and ns.Gathering:IsSkinning()
        and not (guid and guid == sourceGuid and ns.Tracker
            and ns.Tracker:EmptyOwnKill(guid, unit)) then
        self.skipped = (self.skipped or 0) + 1
        return
    else
        local zone, location = self:Where()

        record = self:GetRecord(mob, level, zone, location)
        record.corpses = record.corpses + 1

        if not record.coords then
            local x, y = self:PlayerPosition()
            if x then record.coords = { x, y } end
        end

        corpse = { record = record, items = {} }
        if guid then self.opened[guid] = corpse end
    end

    -- An item in two slots of one corpse is one corpse that held it, not two.
    -- `counted` spans every opening of this corpse; `seenHere` only this one,
    -- so two slots of the same item now still add up, while leftovers seen
    -- again on a return visit add nothing.
    local counted = corpse.items
    local seenHere = {}

    local gotCount, lootCount = pcall(GetNumLootItems)
    local count = gotCount and ReadableNumber(lootCount) or nil
    if not count then return end

    for slot = 1, count do
        local ok, _, slotName, quantity = pcall(GetLootSlotInfo, slot)

        -- Another corpse's drop in the same window (area loot) is not this
        -- one's; where the client gives this corpse's share, that is it.
        local ours, share = self:SlotIsTargets(slot)
        if share then quantity = share end

        -- An unreadable loot name loses that one slot. The corpse itself is
        -- already counted, and the rest of the window is still worth reading.
        local name = ours and ok and Readable(slotName) or nil

        local already = name and counted[name] and not seenHere[name]

        if name and not already and not self:IsMoney(slot, name) then
            local entry = record.items[name]

            if not entry then
                entry = { name = name, count = 0, corpses = 0 }
                record.items[name] = entry
            end

            entry.count = entry.count + (ReadableNumber(quantity) or 1)

            if not seenHere[name] then
                seenHere[name] = true
                counted[name] = true
                entry.corpses = entry.corpses + 1
            end

            if not entry.id and caps.lootSlotLink then
                local gotLink, link = pcall(GetLootSlotLink, slot)
                -- The link comes from the same restricted source as the name,
                -- so it is read the same way before anything matches on it.
                local text = gotLink and Readable(link) or nil
                if text then
                    entry.id = tonumber(text:match("item:(%d+)"))
                end
            end
        end
    end

    self.dirty = true
end

--------------------------------------------------------------------------------
-- Reading it back
--------------------------------------------------------------------------------

function Harvest:CountCorpses()
    local total = 0
    for _, record in pairs(self.records) do
        total = total + record.corpses
    end
    return total
end

--- How many mobs, by name. A mob looted in two places keeps a record for
--- each, but it is still one mob.
function Harvest:CountMobs()
    local seen, total = {}, 0
    for _, record in pairs(self.records) do
        if not seen[record.mob] then
            seen[record.mob] = true
            total = total + 1
        end
    end
    return total
end

--- Everything seen for one item, best-sampled first.
function Harvest:ForItem(itemName)
    local rows = {}

    for _, record in pairs(self.records) do
        local entry = record.items[itemName]

        if entry then
            -- Not rounded: one in 300 is a third of a percent, not 0. Shown
            -- through Tracker.FormatChance, which says "<1%".
            rows[#rows + 1] = {
                record = record,
                entry = entry,
                chance = entry.corpses / record.corpses * 100,
            }
        end
    end

    table.sort(rows, function(a, b)
        if a.record.corpses ~= b.record.corpses then
            return a.record.corpses > b.record.corpses
        end
        if a.record.mob ~= b.record.mob then return a.record.mob < b.record.mob end
        -- One mob in two places with as many corpses each: the same order
        -- every time, so an export does not shuffle its rows.
        if (a.record.zone or "") ~= (b.record.zone or "") then
            return (a.record.zone or "") < (b.record.zone or "")
        end
        return (a.record.location or "") < (b.record.location or "")
    end)

    return rows
end

--- The harvested item a typed name means.
--
-- Exact first, then a prefix, then anything containing it, so "wool" finds
-- Wool Cloth without "cloth" silently picking whichever cloth sorts first.
-- Returns nil rather than guessing when more than one item matches loosely.
function Harvest:ResolveItem(text)
    text = tostring(text or ""):lower()
    if text == "" then return nil end

    local items = self:Items()
    local prefixes, contains = {}, {}

    for _, item in ipairs(items) do
        local name = item.name:lower()

        if name == text then
            return item.name
        elseif name:sub(1, #text) == text then
            prefixes[#prefixes + 1] = item.name
        elseif name:find(text, 1, true) then
            contains[#contains + 1] = item.name
        end
    end

    if #prefixes == 1 then return prefixes[1] end
    if #prefixes == 0 and #contains == 1 then return contains[1] end

    -- More than one fits: say which, rather than picking one.
    local candidates = #prefixes > 0 and prefixes or contains
    if #candidates > 1 then
        table.sort(candidates)
        return nil, candidates
    end
    return nil
end

--- Every item seen, with how many corpses back each one.
function Harvest:Items()
    local items, order = {}, {}

    for _, record in pairs(self.records) do
        for name, entry in pairs(record.items) do
            if not items[name] then
                items[name] = { name = name, corpses = 0, count = 0 }
                order[#order + 1] = items[name]
            end

            items[name].corpses = items[name].corpses + entry.corpses
            items[name].count = items[name].count + entry.count
        end
    end

    table.sort(order, function(a, b)
        if a.count ~= b.count then return a.count > b.count end
        return a.name < b.name
    end)

    return order
end

function Harvest:Reset()
    self.records = {}
    self.opened = {}
    self.skipped = 0
    self.dirty = true
    self:Persist()
end

--------------------------------------------------------------------------------
-- Export
--------------------------------------------------------------------------------

local function Escape(text)
    return (tostring(text):gsub("\\", "\\\\"):gsub('"', '\\"'))
end

--- One item as a data-file entry, ready to paste into Data/.
--
-- Rows come out marked provenance = "forever": they were measured on this
-- client, which is exactly what that marker is for.
function Harvest:ExportItem(itemName)
    local rows = self:ForItem(itemName)
    if #rows == 0 then return nil end

    local out = {}
    local id

    for _, row in ipairs(rows) do
        id = id or row.entry.id
    end

    out[#out + 1] = "DB:RegisterItem({"
    out[#out + 1] = ('    name = "%s",'):format(Escape(itemName))

    if id then
        out[#out + 1] = ("    id = %d,"):format(id)
    end

    out[#out + 1] = "    sources = {"

    for _, row in ipairs(rows) do
        local record = row.record
        local fields = {}

        fields[#fields + 1] = ('name = "%s"'):format(Escape(record.mob))
        fields[#fields + 1] = ('zone = "%s"'):format(Escape(record.zone or "?"))

        if record.location then
            fields[#fields + 1] = ('location = "%s"'):format(Escape(record.location))
        end

        if record.coords then
            fields[#fields + 1] = ("coords = { %.1f, %.1f }")
                :format(record.coords[1], record.coords[2])
        end

        if record.minLevel then
            fields[#fields + 1] = ("minLevel = %d"):format(record.minLevel)
            fields[#fields + 1] = ("maxLevel = %d"):format(record.maxLevel or record.minLevel)
        end

        -- A rate off five corpses is a number pretending to be evidence.
        local chance = record.corpses >= MIN_SAMPLE
            and Harvest.ExportChance(row.entry.corpses / record.corpses * 100)
        if chance then fields[#fields + 1] = chance end

        fields[#fields + 1] = 'provenance = "forever"'

        out[#out + 1] = ("        { %s },"):format(table.concat(fields, ", "))

        if record.corpses >= MIN_SAMPLE then
            out[#out + 1] = ("            -- %d of %d corpses"):format(
                row.entry.corpses, record.corpses)
        else
            out[#out + 1] = ("            -- %d of %d corpses: too few for a rate")
                :format(row.entry.corpses, record.corpses)
        end
    end

    out[#out + 1] = "    },"
    out[#out + 1] = "})"

    return table.concat(out, "\n")
end

--- Everything harvested, as one pasteable block.
--
-- `opts.generated` says this is being written to a file by a tool rather than
-- copied out of the window by hand, which changes only the header: one tells
-- you what to do with it, the other tells the next reader not to hand-edit it.
function Harvest:ExportAll(opts)
    opts = opts or {}

    local items = self:Items()

    -- Catches go in the same file, as fishing rows (Logic/Fishing.lua).
    local fishing = ns.Fishing and ns.Fishing:ExportBlocks()

    if #items == 0 and not fishing then
        return "-- Nothing harvested yet. Go and kill something."
    end

    local out = {
        "-- Harvested on WoW: Forever by Blackthornes Farmer.",
        ("-- %d mobs, %d corpses looted."):format(self:CountMobs(), self:CountCorpses()),
    }

    -- Its own line, so tools/harvest_import.py can check casts never shrink
    -- the way it checks corpses.
    if fishing then
        out[#out + 1] = ("-- %d fishing casts."):format(ns.Fishing:CountCasts())
    end

    out[#out + 1] = "--"

    if opts.generated then
        out[#out + 1] = "-- Generated by tools/harvest_import.py from your SavedVariables."
        out[#out + 1] = "-- Do not edit by hand: the next import overwrites this file."
    else
        out[#out + 1] = "-- Paste into a file under Data/ and add it to the .toc."
    end

    out[#out + 1] = ""
    out[#out + 1] = "local _, ns = ..."
    out[#out + 1] = ""
    out[#out + 1] = "local DB = ns.DB"
    out[#out + 1] = ""

    for _, item in ipairs(items) do
        -- Herbs and ore count per node, never as a mob's drop. One the seed
        -- data knows only from nodes was picked with a corpse targeted, by a
        -- version before Logic/Gathering.lua, and stays out of the data.
        local nodeOnly = ns.Gathering ~= nil and ns.Gathering.IsNodeOnly(item.name)
        local block = not nodeOnly and self:ExportItem(item.name)
        if block then
            out[#out + 1] = block
            out[#out + 1] = ""
        end
    end

    if fishing then
        out[#out + 1] = "-- Fishing"
        out[#out + 1] = ""
        out[#out + 1] = fishing
    end

    return table.concat(out, "\n")
end

--------------------------------------------------------------------------------
-- Saved variables
--
-- The harvest lives in SavedVariables and keeps growing from one session to
-- the next: Restore reads it at login, and ns.db.harvest is the very table
-- RecordCorpse adds to, so whatever the client writes -- at logout, at /reload
-- -- is the whole total, not one session of it.
--
-- Until the Forever patch of 2026-09-24 the client never read saved variables
-- back, and the running total had to be kept outside the game by the import
-- tool. What it had gathered by then arrives once, from
-- Data/Harvest_Carryover.lua; see ApplyCarryover.
--------------------------------------------------------------------------------

--- Drop coin entries an older version recorded as items.
--
-- Slot numbers are long gone by the time this runs, so it can only go on the
-- name -- which is what IsMoney falls back to anyway.
function Harvest:PruneMoney()
    local dropped = 0

    for _, record in pairs(self.records) do
        for name in pairs(record.items) do
            if self:IsMoney(nil, name) then
                record.items[name] = nil
                dropped = dropped + 1
            end
        end
    end

    return dropped
end

--- Add one spot's record into this harvest, as if its corpses were looted here.
--
-- The same rules tools/harvest_import.py used to merge sessions with: corpse
-- and item counts add up, the level band widens to cover both, and the first
-- coordinates seen for a camp are kept. The incoming record is copied, never
-- shared, so the carryover table itself is left exactly as shipped.
function Harvest:MergeRecord(key, incoming)
    if type(incoming) ~= "table" or not incoming.mob then return end

    local existing = self.records[key]

    if not existing then
        existing = {
            mob = incoming.mob,
            zone = incoming.zone,
            location = incoming.location,
            corpses = 0,
            items = {},
        }
        self.records[key] = existing
    end

    existing.corpses = (existing.corpses or 0) + (incoming.corpses or 0)

    if not existing.coords and type(incoming.coords) == "table" then
        existing.coords = { incoming.coords[1], incoming.coords[2] }
    end

    for _, field in ipairs({ "minLevel", "maxLevel" }) do
        local theirs = incoming[field]
        if theirs then
            local mine = existing[field]
            local pick = field == "minLevel" and math.min or math.max
            existing[field] = mine and pick(mine, theirs) or theirs
        end
    end

    for name, arriving in pairs(incoming.items or {}) do
        local held = existing.items[name]

        if not held then
            held = { name = arriving.name or name, count = 0, corpses = 0 }
            existing.items[name] = held
        end

        held.count = held.count + (arriving.count or 0)
        held.corpses = held.corpses + (arriving.corpses or 0)
        held.id = held.id or arriving.id
    end
end

--- Fold in what was harvested before saved variables worked, exactly once.
--
-- The save is stamped with the carryover's id in the same step, so the next
-- login finds the stamp and adds nothing. If the client ever stops reading
-- saved variables back again, the stamp is lost along with the harvest and
-- the carryover comes back in on its own, which is the right answer then too.
function Harvest:ApplyCarryover()
    local carryover = ns.HarvestCarryover

    if type(carryover) ~= "table" or type(carryover.records) ~= "table" then
        return 0
    end

    if ns.db.harvestCarryover == carryover.id then return 0 end

    local added = 0

    for key, record in pairs(carryover.records) do
        self:MergeRecord(key, record)
        added = added + (record.corpses or 0)
    end

    ns.db.harvestCarryover = carryover.id

    return added
end

--- Load the saved harvest. Returns how many spots came back.
function Harvest:Restore()
    if not ns.db then return 0 end

    local restored = 0

    if type(ns.db.harvest) == "table" then
        for key, record in pairs(ns.db.harvest) do
            if type(record) == "table" and record.mob and record.corpses then
                self.records[key] = record
                restored = restored + 1
            end
        end
    end

    -- Versions before 2026-09-21 recorded coins as items.
    self:PruneMoney()

    self.carriedOver = self:ApplyCarryover()

    -- Left behind by the version that worked around the client bug. Nothing
    -- reads it any more.
    ns.db.harvestRestored = nil

    self:Persist()

    return restored
end

--- Point the saved harvest at the live one.
--
-- They are the same table from here on, so everything looted is already in
-- what the client writes, whenever it writes it.
function Harvest:Persist()
    if not ns.db then return end
    ns.db.harvest = self.records
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

function Harvest:OnInitialize()
    local restored = self:Restore()

    if restored > 0 then
        ns.Debug(("restored %d harvested mobs"):format(restored))
    end

    if (self.carriedOver or 0) > 0 then
        ns.Print(("added %d corpses harvested before saved data worked. "
            .. "/farm harvest shows the total."):format(self.carriedOver))
    end
end

function Harvest:OnEnable()
    local caps = self:Capabilities()

    if not caps.usable then
        ns.Debug("this client does not expose the loot API; harvesting is off")
        self.enabled = false
        return
    end

    -- Paused on purpose, from the settings page or /farm harvest off.
    if ns.db and ns.db.harvestPaused then
        self.enabled = false
    end

    ns.OnLootWindow(self, function() Harvest:RecordCorpse() end)

    -- The mobs you meet, so a corpse looted untargeted is still known.
    ns.RegisterEvent(self, "PLAYER_TARGET_CHANGED", function() Harvest:NoteUnit("target") end)
    ns.RegisterEvent(self, "UPDATE_MOUSEOVER_UNIT", function() Harvest:NoteUnit("mouseover") end)
    ns.RegisterEvent(self, "PLAYER_SOFT_ENEMY_CHANGED", function() Harvest:NoteUnit("softenemy") end)
    ns.RegisterEvent(self, "PLAYER_SOFT_INTERACT_CHANGED", function() Harvest:NoteUnit("softinteract") end)
    ns.RegisterEvent(self, "NAME_PLATE_UNIT_ADDED", function(_, _, unit)
        if type(unit) == "string" then Harvest:NoteUnit(unit) end
    end)

    -- ns.db.harvest already is the live table, so this only matters if
    -- something replaced one or the other. Cheap insurance at the one moment
    -- the client is certain to save.
    ns.RegisterEvent(self, "PLAYER_LOGOUT", function() Harvest:Persist() end)
end

--------------------------------------------------------------------------------
-- Commands
--------------------------------------------------------------------------------

ns.RegisterCommand("harvest", "what you have recorded as you played", function(rest)
    local argument = Util.Trim(rest):lower()

    -- The harvest is the whole history now, not one session, and a reset is
    -- saved at the next logout like anything else. So it takes two words.
    if argument == "reset" then
        ns.Print(("this deletes all %s you have recorded, for good. "
            .. "Type /farm harvest reset confirm to do it."):format(
            Util.Plural(ns.Harvest:CountCorpses(), "corpse")))
        return
    end

    if argument == "reset confirm" then
        ns.Harvest:Reset()
        ns.Print("harvest cleared.")
        return
    end

    if argument == "off" then
        ns.Harvest.enabled = false
        ns.db.harvestPaused = true
        ns.Print("harvesting paused. /farm harvest on to resume.")
        return
    end

    if argument == "on" then
        ns.db.harvestPaused = false
        ns.Harvest.enabled = ns.Harvest:Capabilities().usable and true or false
        ns.Print("harvesting on.")
        return
    end

    local corpses = ns.Harvest:CountCorpses()

    if corpses == 0 then
        if not ns.Harvest:Capabilities().usable then
            ns.Print("this client does not expose the loot API, so nothing is being recorded.")
        else
            ns.Print("nothing recorded yet. Loot some corpses and check back.")
        end
        return
    end

    ns.Print(("%s looted across %s:"):format(
        Util.Plural(corpses, "corpse"), Util.Plural(ns.Harvest:CountMobs(), "mob")))

    local items = ns.Harvest:Items()

    for index = 1, math.min(#items, 12) do
        local item = items[index]
        ns.PrintRaw(("  %s %s  %s"):format(
            Util.Colored("accent", tostring(item.count)),
            item.name,
            Util.Colored("muted", ("from %s"):format(Util.Plural(item.corpses, "corpse")))))
    end

    if #items > 12 then
        ns.PrintRaw(Util.Colored("muted", ("  ... and %d more items"):format(#items - 12)))
    end

    ns.PrintRaw(Util.Colored("muted", "  /farm export to get it as a data file."))
end)

ns.RegisterCommand("export", "hand back what you harvested, ready to paste", function(rest)
    local wanted = ns.Util.Trim(rest or "")

    if wanted == "" then
        ns.UI:ShowExport(ns.Harvest:ExportAll(), "Export: everything harvested")
        return
    end

    -- Name an item and you get only that item, which is the usual case: you
    -- farmed one thing for an evening and want that one block.
    local name, candidates = ns.Harvest:ResolveItem(wanted)
    -- A herb or ore credited to a mob stays out, as in ExportAll.
    local nodeOnly = name and ns.Gathering ~= nil and ns.Gathering.IsNodeOnly(name)
    local block = name and not nodeOnly and ns.Harvest:ExportItem(name)

    if candidates then
        local shown, more = {}, #candidates - 8
        for index = 1, math.min(8, #candidates) do shown[index] = candidates[index] end
        local list = table.concat(shown, ", ")
        if more > 0 then list = ("%s and %d more"):format(list, more) end
        ns.Print(("%s could be %s. Type more of the name."):format(wanted, list))
        return
    end

    if nodeOnly then
        ns.Print(("%s comes from nodes, not mobs, so it is never exported."):format(name))
        return
    end

    if not block then
        ns.Print(("nothing harvested for %s yet."):format(wanted))
        return
    end

    ns.UI:ShowExport(block, ("Export: %s"):format(name))
end)
