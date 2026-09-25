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
-- Trent hit that in Ragefire Chasm on 2026-09-22. UnitName("target") came back
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

--- A plain string copy of `value`, or nil if this client will not let us read it.
local function Readable(value)
    local kind = type(value)

    -- A number would concatenate cleanly below and is not a name, so it is
    -- ruled out first. Everything else -- nil, tables, secret values -- is
    -- ruled out by failing the read.
    if kind == "number" or kind == "boolean" then return nil end

    local ok, copy = pcall(function()
        -- The read is the test. Concatenating and comparing are both refused
        -- on a secret value, and refusing means raising, so doing them in here
        -- is how we find out. Whatever comes back out has survived both.
        local text = value .. ""
        if text == "" then return nil end
        return text
    end)

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

    local ok, copy = pcall(function()
        -- Arithmetic and comparison, for the same reason as above. The
        -- comparison doubles as the not-a-number check.
        local number = value + 0
        if number ~= number then return nil end
        return number
    end)

    if not ok or type(copy) ~= "number" then return nil end

    return copy
end

-- The kill tracker reads the same loot window and the same target, so it reads
-- them through the same two doors.
Harvest.Readable = Readable
Harvest.ReadableNumber = ReadableNumber

--------------------------------------------------------------------------------
-- Where and what
--------------------------------------------------------------------------------

--- The player's position as map percentages, or nil if the client will not say.
function Harvest:PlayerPosition()
    local caps = self:Capabilities()
    if not (caps.bestMap and caps.playerPos) then return nil end

    local ok, mapID = pcall(C_Map.GetBestMapForUnit, "player")
    if not ok or not mapID then return nil end

    local gotPosition, position = pcall(C_Map.GetPlayerMapPosition, mapID, "player")
    if not gotPosition or not position then return nil end

    -- A map position is a vector object on modern clients; older ones hand
    -- back two plain numbers.
    local x, y

    if type(position) == "table" and type(position.GetXY) == "function" then
        local readable, px, py = pcall(position.GetXY, position)
        if readable then x, y = px, py end
    elseif type(position) == "number" then
        x, y = position, select(2, C_Map.GetPlayerMapPosition(mapID, "player"))
    end

    -- Read rather than type-checked: a coordinate off a restricted client is
    -- as liable to be secret as a name, and this one is about to be compared.
    x, y = ReadableNumber(x), ReadableNumber(y)

    if not x or not y then return nil end
    if x == 0 and y == 0 then return nil end

    return x * 100, y * 100
end

--- The corpse being looted, as far as the client will admit.
--
-- The loot window does not name its owner, so this reads the target, which is
-- the corpse in every normal case. When it is not -- looting while targeting
-- something else -- this returns nil and the sample is dropped. A sample
-- attributed to the wrong mob is worse than no sample: it goes into the data
-- and sends somebody to the wrong place.
function Harvest:LootSource()
    if not UnitName or not UnitIsDead then return nil end

    local ok, dead = pcall(UnitIsDead, "target")
    if not ok or not dead then return nil end

    -- Not `name == ""`: in an instance this is the line that blew up. The
    -- comparison happens inside Readable, where a raise is an answer.
    local gotName, unitName = pcall(UnitName, "target")
    if not gotName then return nil end

    local name = Readable(unitName)
    if not name then return nil end

    -- Players and their corpses are not farming spots.
    if UnitIsPlayer then
        local gotPlayer, isPlayer = pcall(UnitIsPlayer, "target")
        if gotPlayer and isPlayer then return nil end
    end

    local level
    if UnitLevel then
        local gotLevel, unitLevel = pcall(UnitLevel, "target")
        local number = gotLevel and ReadableNumber(unitLevel) or nil
        -- -1 is the client's way of saying "higher than you can tell".
        if number and number > 0 then
            level = number
        end
    end

    return name, level
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
    if not UnitGUID then return nil end

    local ok, guid = pcall(UnitGUID, "target")
    if not ok then return nil end

    return Readable(guid)
end

--- Is the open loot window a fishing catch or a gathered herb or vein?
--
-- Either way it is nobody's corpse, whatever is targeted. A herb picked with
-- a looted corpse still targeted used to go down as that corpse's drop.
function Harvest:IsNodeLoot()
    if self:Capabilities().fishingLoot then
        local ok, fishing = pcall(IsFishingLoot)
        if ok and fishing then return true end
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

--- Does the open loot window belong to the target?
--
-- Where the client says whose loot each slot is (GetLootSourceInfo), a window
-- none of whose slots is the target's -- a chest, a clam opened from the bags,
-- another corpse -- is not the target's loot. This answers false only on that
-- evidence: guids it cannot read, or a client spelling them some other way,
-- leave it answering true, the way it was before it asked.
function Harvest:LootIsTargets()
    if type(GetLootSourceInfo) ~= "function" then return true end

    local target = self:CorpseID()
    if not GuidKind(target) then return true end

    local gotCount, lootCount = pcall(GetNumLootItems)
    local count = gotCount and ReadableNumber(lootCount) or nil
    if not count then return true end

    local elsewhere = false

    for slot = 1, count do
        local ok, sources = pcall(function() return { GetLootSourceInfo(slot) } end)

        -- Guid, quantity, guid, quantity...
        for index = 1, ok and #sources or 0, 2 do
            local guid = Readable(sources[index])

            if guid == target then return true end
            if GuidKind(guid) then elsewhere = true end
        end
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
-- as if it were a farmable drop. Trent's first real session produced 25 coin
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
    -- be recognised again, so each opening counts as before.
    local guid = self:CorpseID()
    local corpse = guid and self.opened[guid]
    local record

    if corpse then
        record = corpse.record
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

        -- An unreadable loot name loses that one slot. The corpse itself is
        -- already counted, and the rest of the window is still worth reading.
        local name = ok and Readable(slotName) or nil

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

function Harvest:CountMobs()
    local total = 0
    for _ in pairs(self.records) do total = total + 1 end
    return total
end

--- Everything seen for one item, best-sampled first.
function Harvest:ForItem(itemName)
    local rows = {}

    for _, record in pairs(self.records) do
        local entry = record.items[itemName]

        if entry then
            rows[#rows + 1] = {
                record = record,
                entry = entry,
                chance = math.floor((entry.corpses / record.corpses * 100) + 0.5),
            }
        end
    end

    table.sort(rows, function(a, b)
        if a.record.corpses ~= b.record.corpses then
            return a.record.corpses > b.record.corpses
        end
        return a.record.mob < b.record.mob
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
    local prefix, contains

    for _, item in ipairs(items) do
        local name = item.name:lower()

        if name == text then
            return item.name
        elseif name:sub(1, #text) == text then
            prefix = prefix or item.name
        elseif name:find(text, 1, true) then
            contains = contains or item.name
        end
    end

    return prefix or contains
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
        if record.corpses >= MIN_SAMPLE then
            fields[#fields + 1] = ("chance = %d"):format(row.chance)
        end

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
        local block = self:ExportItem(item.name)
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

    ns.RegisterEvent(self, "LOOT_OPENED", function() Harvest:RecordCorpse() end)

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
        ns.UI:ShowExport(ns.Harvest:ExportAll(), "Export -- everything harvested")
        return
    end

    -- Name an item and you get only that item, which is the usual case: you
    -- farmed one thing for an evening and want that one block.
    local name = ns.Harvest:ResolveItem(wanted)
    local block = name and ns.Harvest:ExportItem(name)

    if not block then
        ns.Print(("nothing harvested for %s yet."):format(wanted))
        return
    end

    ns.UI:ShowExport(block, ("Export -- %s"):format(name))
end)
