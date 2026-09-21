-- Blackthornes Farmer -- Logic/Harvest.lua
-- Record what actually drops, as you play.
--
-- Every fact this addon ships was copied from Classic and is a guess about
-- Forever. The client already knows the truth at the moment you loot a corpse:
-- which mob it was, its level, the zone, the subzone, where you are standing,
-- and what was inside. Count corpses looted and count the ones that held the
-- item, and that is a real drop rate, measured here rather than assumed.
--
-- Nothing is sent anywhere. It accumulates in memory, and `/farm export` hands
-- it back as a data file to paste into the repository.
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

    if type(x) ~= "number" or type(y) ~= "number" then return nil end
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

    local gotName, name = pcall(UnitName, "target")
    if not gotName or not name or name == "" then return nil end

    -- Players and their corpses are not farming spots.
    if UnitIsPlayer then
        local gotPlayer, isPlayer = pcall(UnitIsPlayer, "target")
        if gotPlayer and isPlayer then return nil end
    end

    local level
    if UnitLevel then
        local gotLevel, unitLevel = pcall(UnitLevel, "target")
        -- -1 is the client's way of saying "higher than you can tell".
        if gotLevel and type(unitLevel) == "number" and unitLevel > 0 then
            level = unitLevel
        end
    end

    return name, level
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

--- One looted corpse: the denominator of every rate this module reports.
function Harvest:RecordCorpse()
    if not self.enabled then return end

    local caps = self:Capabilities()
    if not caps.usable then return end

    -- Fishing pools and containers are not mobs.
    if caps.fishingLoot then
        local ok, fishing = pcall(IsFishingLoot)
        if ok and fishing then return end
    end

    local mob, level = self:LootSource()
    if not mob then
        self.skipped = (self.skipped or 0) + 1
        return
    end

    local zone = caps.realZone and GetRealZoneText() or nil
    local location = caps.subZone and GetSubZoneText() or nil

    if location == "" then location = nil end

    local record = self:GetRecord(mob, level, zone, location)
    record.corpses = record.corpses + 1

    if not record.coords then
        local x, y = self:PlayerPosition()
        if x then record.coords = { x, y } end
    end

    -- An item in two slots of one corpse is one corpse that held it, not two.
    local seenHere = {}

    local gotCount, count = pcall(GetNumLootItems)
    if not gotCount or not count then return end

    for slot = 1, count do
        local ok, _, name, quantity = pcall(GetLootSlotInfo, slot)

        if ok and name and name ~= "" then
            local entry = record.items[name]

            if not entry then
                entry = { name = name, count = 0, corpses = 0 }
                record.items[name] = entry
            end

            entry.count = entry.count + (quantity or 1)

            if not seenHere[name] then
                seenHere[name] = true
                entry.corpses = entry.corpses + 1
            end

            if not entry.id and caps.lootSlotLink then
                local gotLink, link = pcall(GetLootSlotLink, slot)
                if gotLink and link then
                    entry.id = tonumber(link:match("item:(%d+)"))
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
    self.skipped = 0
    self.dirty = true
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

    if #items == 0 then
        return "-- Nothing harvested yet. Go and kill something."
    end

    local out = {
        "-- Harvested on WoW: Forever by Blackthornes Farmer.",
        ("-- %d mobs, %d corpses looted."):format(self:CountMobs(), self:CountCorpses()),
        "--",
    }

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

    return table.concat(out, "\n")
end

--------------------------------------------------------------------------------
-- Saved variables
--
-- This client is reported to write saved variables at logout without reading
-- them back. If that holds, what follows is simply never restored and the
-- export window is the only way out -- which is why the export window, not the
-- saved file, is the supported path. If it does read them back, a session
-- picks up where the last one left off for free.
--------------------------------------------------------------------------------

function Harvest:Restore()
    if not (ns.db and type(ns.db.harvest) == "table") then return 0 end

    local restored = 0

    for key, record in pairs(ns.db.harvest) do
        if type(record) == "table" and record.mob and record.corpses then
            self.records[key] = record
            restored = restored + 1
        end
    end

    return restored
end

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
end

function Harvest:OnEnable()
    local caps = self:Capabilities()

    if not caps.usable then
        ns.Debug("this client does not expose the loot API; harvesting is off")
        self.enabled = false
        return
    end

    ns.RegisterEvent(self, "LOOT_OPENED", function() Harvest:RecordCorpse() end)

    -- Written on the way out, which is the one moment the client is known to
    -- save. Persisting on every corpse would be a lot of churn for no gain.
    ns.RegisterEvent(self, "PLAYER_LOGOUT", function() Harvest:Persist() end)
end

--------------------------------------------------------------------------------
-- Commands
--------------------------------------------------------------------------------

ns.RegisterCommand("harvest", "what you have recorded as you played", function(rest)
    local argument = Util.Trim(rest):lower()

    if argument == "reset" then
        ns.Harvest:Reset()
        ns.Print("harvest cleared.")
        return
    end

    if argument == "off" then
        ns.Harvest.enabled = false
        ns.Print("harvesting paused. /farm harvest on to resume.")
        return
    end

    if argument == "on" then
        ns.Harvest.enabled = true
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
