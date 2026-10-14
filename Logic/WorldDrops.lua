-- Blackthornes Farmer -- Logic/WorldDrops.lua
-- How often green, blue, purple and orange gear drops, by the mob's level.
--
-- The owner asked (2026-10-13) whether the farm data could tell the chance
-- of a world drop, then for it in the kills panel, Rankings, the mob tooltip
-- and the search. It is worked out from the harvest, corpses opened and what
-- each held (Logic/Harvest.lua), never from anywhere else:
--
--   * Only gear counts: weapons and armour (the client's item class 2 or 4,
--     read with GetItemInfoInstant, which needs no item cache). A green gem
--     or recipe is not a world drop of gear.
--   * Quality is the colour of the item's loot link, kept by the kills panel
--     (Tracker:Looks), else what the client says for the item ID.
--   * Mobs are grouped by level, five levels a band, from the level the
--     record was taken at. A dungeon record has no level and is left out:
--     its bosses have their own loot.
--
-- The shipped harvest carries the same counts from the owner's own kills
-- (DB:WorldDrops, written by the import beside the creature types), so a
-- new player sees chances from the start. A band uses whichever has more
-- kills, the player's own or the shipped ones, never the two added, since
-- the owner's own save holds the shipped kills too.
--
-- Smooth play: nothing here runs on a timer. A record's sum is kept until
-- its corpse count moves, and the bands are summed again only when a view
-- asks after a kill (Harvest.changes) or a minute has gone by (a merge from
-- sharing or an import does not tell us).

local _, ns = ...
local L = ns.L

local WorldDrops = ns.NewModule("WorldDrops")

WorldDrops.BAND = 5

-- A band's chance shows from this many kills, so it never guesses from a
-- handful.
WorldDrops.MIN_KILLS = 200

-- Kept bands are summed again after this long, in case sharing or an import
-- added kills without a corpse being opened here.
WorldDrops.KEEP_FOR = 60

-- Green, blue, purple, orange.
WorldDrops.QUALITIES = { 2, 3, 4, 5 }

local QUALITY_OF_COLOR = {}
for quality, color in pairs(ns.Tracker and ns.Tracker.QUALITY or {}) do
    QUALITY_OF_COLOR[color] = quality
end

local GEAR_CLASSES = { [2] = true, [4] = true }

--------------------------------------------------------------------------------
-- One item
--------------------------------------------------------------------------------

-- [itemID] = true or false, once the client has said.
local gear = {}

--- Is this a weapon or armour? Nil when the client will not say.
function WorldDrops.IsGear(itemID)
    itemID = tonumber(itemID)
    if not itemID then return nil end
    if gear[itemID] ~= nil then return gear[itemID] end

    local instant = (C_Item and C_Item.GetItemInfoInstant) or _G.GetItemInfoInstant
    if type(instant) ~= "function" then return nil end

    local ok, id, _, _, _, _, classID = pcall(instant, itemID)
    if not ok or id == nil then return nil end
    classID = tonumber(classID)
    if not classID then return nil end

    gear[itemID] = GEAR_CLASSES[classID] == true
    return gear[itemID]
end

function WorldDrops.ForgetGear()
    gear = {}
end

--- An item's quality, 0 to 5, from its loot link's colour, else the client.
function WorldDrops.QualityOf(itemID, name)
    local looks = ns.db and type(ns.db.tracker) == "table" and ns.db.tracker.looks
    local look = type(looks) == "table" and name and looks[name]
    if type(look) == "table" and type(look.color) == "string" then
        local quality = QUALITY_OF_COLOR[look.color:lower()]
        if quality then return quality end
    end

    itemID = tonumber(itemID)
    if not itemID then return nil end

    local byID = C_Item and C_Item.GetItemQualityByID
    if type(byID) == "function" then
        local ok, quality = pcall(byID, itemID)
        if ok and type(quality) == "number" then return quality end
    end
    return nil
end

--- The item ID a harvest entry carries, else the one its loot link gave.
local function ItemIDOf(name, entry)
    local id = tonumber(type(entry) == "table" and entry.id)
    if id then return id end
    local looks = ns.db and type(ns.db.tracker) == "table" and ns.db.tracker.looks
    local look = type(looks) == "table" and looks[name]
    return type(look) == "table" and tonumber(look.id) or nil
end

--- Green or better gear: its quality, else nil.
function WorldDrops.WorldQuality(itemID, name)
    local quality = WorldDrops.QualityOf(itemID, name)
    if not quality or quality < 2 then return nil end
    if WorldDrops.IsGear(itemID) ~= true then return nil end
    return math.min(quality, 5)
end

--------------------------------------------------------------------------------
-- Bands
--------------------------------------------------------------------------------

function WorldDrops.Band(level)
    level = tonumber(level)
    if not level or level < 1 then return nil end
    return math.floor(level / WorldDrops.BAND) * WorldDrops.BAND
end

--- A dungeon, raid or city: a boss's own loot, or no world mobs at all.
--- Some dungeon records carry a level (the target was readable), so the
--- zone is what tells.
function WorldDrops.Inside(zone)
    local inside = ns.Spots and ns.Spots.INSIDE
    if type(inside) ~= "table" or type(zone) ~= "string" then return false end
    if inside[zone] then return true end
    local english = ns.Spots.English and ns.Spots.English(zone)
    return english ~= nil and inside[english] ~= nil
end

--- The band a harvest record counts in, or nil when it does not count.
function WorldDrops.RecordBand(record)
    if WorldDrops.Inside(record.zone) then return nil end
    return WorldDrops.Band(record.minLevel)
end

function WorldDrops.BandLabel(band)
    if band == 0 then return L.Format("Levels %d-%d", 1, WorldDrops.BAND - 1) end
    return L.Format("Levels %d-%d", band, band + WorldDrops.BAND - 1)
end

local function NewBand(band)
    return { band = band, kills = 0, drops = { [2] = 0, [3] = 0, [4] = 0, [5] = 0 },
        value = 0, priced = 0, best = nil }
end

-- [record] = what it adds, kept while its corpse count stands.
local recordSums = setmetatable({}, { __mode = "k" })

--- What one harvest record adds: its band, kills and world drops.
function WorldDrops:RecordSum(record)
    if type(record) ~= "table" then return nil end
    local corpses = tonumber(record.corpses) or 0
    local kept = recordSums[record]
    if kept and kept.corpses == corpses and not kept.unsure then return kept end

    local sum = { corpses = corpses, band = WorldDrops.RecordBand(record),
        drops = {}, items = {} }

    for name, entry in pairs(type(record.items) == "table" and record.items or {}) do
        local id = ItemIDOf(name, entry)
        local quality = id and WorldDrops.WorldQuality(id, name)
        if quality then
            local n = tonumber(entry.corpses) or 0
            sum.drops[quality] = (sum.drops[quality] or 0) + n
            sum.items[#sum.items + 1] = { id = id, name = name, quality = quality,
                corpses = n, count = tonumber(entry.count) or n }
        elseif id and (WorldDrops.IsGear(id) == nil or WorldDrops.QualityOf(id, name) == nil) then
            -- The client has not said yet: ask again next time.
            sum.unsure = true
        end
    end

    recordSums[record] = sum
    return sum
end

--- The player's own bands, from the harvest.
function WorldDrops:Own()
    local bands = {}
    local records = ns.Harvest and ns.Harvest.records or {}

    for _, record in pairs(records) do
        local sum = self:RecordSum(record)
        if sum and sum.band and sum.corpses > 0 then
            local band = bands[sum.band] or NewBand(sum.band)
            bands[sum.band] = band
            band.kills = band.kills + sum.corpses
            for quality, n in pairs(sum.drops) do
                band.drops[quality] = band.drops[quality] + n
            end
            for _, item in ipairs(sum.items) do
                if item.quality == 2 then
                    local price = ns.Value and ns.Value:UnitPrice(item.id)
                    if price and price > 0 then
                        band.value = band.value + price * item.count
                        band.priced = band.priced + item.count
                    end
                end
                if not band.best or item.quality > band.best.quality then band.best = item end
            end
        end
    end

    return bands
end

--- The shipped bands, from the owner's kills (DB:WorldDrops).
function WorldDrops:Shipped()
    local data = ns.DB and ns.DB.worldDrops
    local bands = {}
    if type(data) ~= "table" then return bands end

    for key, count in pairs(type(data.kills) == "table" and data.kills or {}) do
        local band, kills = tonumber(key), tonumber(count)
        if band and kills and kills > 0 then
            bands[band] = NewBand(band)
            bands[band].kills = kills
            bands[band].shipped = true
        end
    end

    for _, row in ipairs(type(data.drops) == "table" and data.drops or {}) do
        local band, id, quality, n = tonumber(row[1]), tonumber(row[2]), tonumber(row[3]), tonumber(row[4])
        local entry = band and bands[band]
        if entry and id and quality and quality >= 2 and n and WorldDrops.IsGear(id) == true then
            quality = math.min(quality, 5)
            entry.drops[quality] = entry.drops[quality] + n
            if quality == 2 then
                local price = ns.Value and ns.Value:UnitPrice(id)
                if price and price > 0 then
                    entry.value = entry.value + price * n
                    entry.priced = entry.priced + n
                end
            end
            if not entry.best or quality > entry.best.quality then
                entry.best = { id = id, quality = quality }
            end
        end
    end

    return bands
end

local kept

--- Every band with kills, lowest first: the player's own where they have
--- killed more there than the shipped data has, else the shipped ones.
function WorldDrops:Bands()
    local changes = ns.Harvest and ns.Harvest.changes or 0
    local now = type(GetTime) == "function" and GetTime() or 0
    if kept and kept.changes == changes and now - kept.at < WorldDrops.KEEP_FOR then
        return kept.list, kept.byBand
    end

    local own, shipped = self:Own(), self:Shipped()
    local byBand, list = {}, {}
    for band, entry in pairs(shipped) do byBand[band] = entry end
    for band, entry in pairs(own) do
        if not byBand[band] or entry.kills >= byBand[band].kills then byBand[band] = entry end
    end
    for _, entry in pairs(byBand) do list[#list + 1] = entry end
    table.sort(list, function(a, b) return a.band < b.band end)

    kept = { changes = changes, at = now, list = list, byBand = byBand }
    return list, byBand
end

-- [mob] = { changes, level, had }, so an open card asks once per kill.
-- Declared before Forget, which empties it (it wrote a global before).
local mobInfo = {}

function WorldDrops.Forget()
    kept = nil
    mobInfo = {}
end

--- Enough kills in this band to say a chance?
function WorldDrops.Measured(entry)
    return type(entry) == "table" and entry.kills >= WorldDrops.MIN_KILLS
end

--- "1 in 25" for `drops` in `kills`.
function WorldDrops.OneIn(kills, drops)
    if not drops or drops <= 0 then return nil end
    return math.max(1, math.floor(kills / drops + 0.5))
end

--- The band for a mob of this level, or nil.
function WorldDrops:ForLevel(level)
    local band = WorldDrops.Band(level)
    if not band then return nil end
    local _, byBand = self:Bands()
    return byBand[band]
end

--- "1 in 25 kills" for green gear at this level, or nil while there are too
--- few kills to say or none has dropped.
function WorldDrops:GreenText(level)
    local entry = self:ForLevel(level)
    if not WorldDrops.Measured(entry) then return nil end
    local one = WorldDrops.OneIn(entry.kills, entry.drops[2])
    if not one then return nil end
    return L.Format("1 in %d kills", one), entry
end

--- What green gear adds to a kill in this band, in copper, or nil.
function WorldDrops.GreenWorth(entry)
    if not WorldDrops.Measured(entry) or entry.drops[2] == 0 or entry.priced == 0 then return nil end
    -- The greens priced stand for all of them.
    local each = entry.value / entry.priced
    return math.floor(each * entry.drops[2] / entry.kills + 0.5)
end

--------------------------------------------------------------------------------
-- Mobs
--------------------------------------------------------------------------------

--- A mob's level as the harvest last saw it, highest record first.
function WorldDrops:MobLevel(mob)
    local level
    for _, record in pairs(ns.Harvest and ns.Harvest.records or {}) do
        if record.mob == mob and WorldDrops.RecordBand(record) then
            level = math.max(level or 0, tonumber(record.minLevel))
        end
    end
    if level then return level end
    local shipped = ns.DB and ns.DB.worldDrops and ns.DB.worldDrops.mobs
    local row = type(shipped) == "table" and shipped[mob]
    return type(row) == "table" and tonumber(row[1]) or nil
end

--- How many of each quality you have had from this mob: { [2] = n, ... }.
function WorldDrops:Had(mob)
    local had = { [2] = 0, [3] = 0, [4] = 0, [5] = 0 }
    for _, record in pairs(ns.Harvest and ns.Harvest.records or {}) do
        if record.mob == mob then
            local sum = self:RecordSum(record)
            for quality, n in pairs(sum and sum.drops or {}) do
                had[quality] = had[quality] + n
            end
        end
    end
    return had
end


--- A mob's level and what you have had from it, kept until the next corpse.
function WorldDrops:MobInfo(mob)
    local changes = ns.Harvest and ns.Harvest.changes or 0
    local info = mobInfo[mob]
    if info and info.changes == changes then return info end
    info = { changes = changes, level = self:MobLevel(mob), had = self:Had(mob) }
    mobInfo[mob] = info
    return info
end

local HAD_COLORS = { [2] = "ff1eff00", [3] = "ff0070dd", [4] = "ffa335ee", [5] = "ffff8000" }
local function HadWords(quality, n)
    if quality == 2 then return L.Format("%d green", n) end
    if quality == 3 then return L.Format("%d blue", n) end
    if quality == 4 then return L.Format("%d purple", n) end
    return L.Format("%d orange", n)
end

--- "2 green  1 blue" in their colours: green always, the rest once had.
function WorldDrops.HadText(had)
    local parts = {}
    for _, quality in ipairs(WorldDrops.QUALITIES) do
        local n = type(had) == "table" and had[quality] or 0
        if quality == 2 or n > 0 then
            parts[#parts + 1] = ("|c%s%s|r"):format(HAD_COLORS[quality], HadWords(quality, n))
        end
    end
    return table.concat(parts, "  ")
end

--- The two lines under an open mob in the kills panel, or nil: the chance of
--- green gear at its level and what you have had from it.
function WorldDrops:CardLines(mob)
    if not mob or not self:IsEnabled() then return nil end
    local info = self:MobInfo(mob)
    if not info.level then return nil end
    local chance = self:GreenText(info.level)
    if not chance then return nil end
    return {
        label = L.Format("World drops, level %d", info.level),
        chance = chance,
        had = WorldDrops.HadText(info.had),
    }
end

--- The mobs that have dropped the most green gear or better, most first:
--- { name, zone, location, minLevel, maxLevel, kills, drops }. Your own
--- kills of a mob stand when there are more of them than shipped.
function WorldDrops:BestMobs(max)
    local mobs = {}

    local data = ns.DB and ns.DB.worldDrops
    local shipped = type(data) == "table" and type(data.mobs) == "table" and data.mobs or {}
    for name, row in pairs(shipped) do
        if type(row) == "table" and tonumber(row[3]) then
            mobs[name] = { name = name, minLevel = tonumber(row[1]), maxLevel = tonumber(row[2]),
                kills = tonumber(row[3]), zone = row[4], location = row[5], drops = 0 }
        end
    end
    for _, row in ipairs(type(data) == "table" and type(data.drops) == "table" and data.drops or {}) do
        local mob = mobs[row[5]]
        if mob and WorldDrops.IsGear(row[2]) == true and (tonumber(row[3]) or 0) >= 2 then
            mob.drops = mob.drops + (tonumber(row[4]) or 0)
        end
    end

    local own = {}
    for _, record in pairs(ns.Harvest and ns.Harvest.records or {}) do
        local sum = self:RecordSum(record)
        if sum and sum.band and record.mob then
            local mob = own[record.mob] or { name = record.mob, kills = 0, drops = 0 }
            own[record.mob] = mob
            mob.kills = mob.kills + sum.corpses
            for _, n in pairs(sum.drops) do mob.drops = mob.drops + n end
            -- The spot it was killed most at names where to go.
            if not mob.best or sum.corpses > mob.best then
                mob.best = sum.corpses
                mob.zone, mob.location = record.zone, record.location
                mob.minLevel, mob.maxLevel = tonumber(record.minLevel), tonumber(record.maxLevel)
            end
        end
    end
    for name, mob in pairs(own) do
        if not mobs[name] or mob.kills >= mobs[name].kills then mobs[name] = mob end
    end

    local list = {}
    for _, mob in pairs(mobs) do
        local hidden = ns.DB and ns.DB.IsHiddenSource and ns.DB:IsHiddenSource(mob.name)
        if mob.drops > 0 and mob.zone and not hidden then list[#list + 1] = mob end
    end
    table.sort(list, function(a, b)
        if a.drops ~= b.drops then return a.drops > b.drops end
        if a.kills ~= b.kills then return a.kills < b.kills end
        return a.name < b.name
    end)
    while max and #list > max do table.remove(list) end
    return list
end

--------------------------------------------------------------------------------
-- The search: "greens", "world drops"
--------------------------------------------------------------------------------

local SEARCH_WORDS = { "greens", "green gear", "green items", "world drop", "world drops",
    "blues", "epics", "weltdrops", "grüne" }

function WorldDrops.IsQuery(query)
    query = type(query) == "string" and query:lower():gsub("^%s+", ""):gsub("%s+$", "") or ""
    if query == "" then return false end
    for _, word in ipairs(SEARCH_WORDS) do
        if query == word then return true end
    end
    local translated = L["greens"]
    return translated ~= "greens" and query == translated:lower()
end

--- A search result, shaped like an item from the database, whose spots are
--- the mobs best for green gear, each with its chance.
function WorldDrops:SearchItem()
    local sources = {}
    for _, mob in ipairs(self:BestMobs(15)) do
        sources[#sources + 1] = { kind = "mob", name = mob.name, zone = mob.zone,
            location = mob.location, minLevel = mob.minLevel or 1,
            maxLevel = mob.maxLevel or mob.minLevel,
            chance = math.floor(mob.drops / mob.kills * 1000 + 0.5) / 10,
            dropText = L.Format("%1$d in %2$d", mob.drops, mob.kills),
            provenance = "forever" }
    end
    if #sources == 0 then return nil end
    return { name = L["Green gear and better"], category = L["World drops"],
        aliases = {}, sources = sources, worldDrops = true, keepOrder = true }
end

--------------------------------------------------------------------------------
-- The shipped counts (tools/harvest_import.py)
--------------------------------------------------------------------------------

local DB = ns.DB

--- Hand the shipped counts in. Called from the end of Data/Data_Harvested.lua.
function DB:WorldDrops(data)
    if type(data) == "table" then self.worldDrops = data end
    WorldDrops.Forget()
end

local function Quote(text)
    return '"' .. tostring(text):gsub("\\", "\\\\"):gsub('"', '\\"') .. '"'
end

--- The block the harvest export writes: kills by band, every green or better
--- item by band with its corpses and mob, and those mobs. Quality comes from
--- the loot links kept in the save; whether it is gear is left to the game.
function WorldDrops:ExportBlock()
    local kills, drops, mobs = {}, {}, {}

    for _, record in pairs(ns.Harvest and ns.Harvest.records or {}) do
        local band = WorldDrops.RecordBand(record)
        local corpses = tonumber(record.corpses) or 0
        if band and corpses > 0 and record.mob and not ns.Harvest.Unnamed(record) then
            kills[band] = (kills[band] or 0) + corpses
            for name, entry in pairs(type(record.items) == "table" and record.items or {}) do
                local id = ItemIDOf(name, entry)
                local quality = id and WorldDrops.QualityOf(id, name)
                if quality and quality >= 2 then
                    drops[#drops + 1] = { band, id, math.min(quality, 5),
                        tonumber(entry.corpses) or 0, record.mob }
                    local mob = mobs[record.mob]
                    if not mob or corpses > mob.most then
                        mobs[record.mob] = { most = corpses,
                            minLevel = tonumber(record.minLevel), maxLevel = tonumber(record.maxLevel) or tonumber(record.minLevel),
                            zone = record.zone, location = record.location, kills = mob and mob.kills or 0 }
                    end
                end
            end
        end
    end

    if #drops == 0 then return nil end

    -- A mob's kills are every record of it, wherever it was killed.
    for _, record in pairs(ns.Harvest.records) do
        local mob = record.mob and mobs[record.mob]
        if mob and WorldDrops.RecordBand(record) then
            mob.kills = mob.kills + (tonumber(record.corpses) or 0)
        end
    end

    table.sort(drops, function(a, b)
        if a[1] ~= b[1] then return a[1] < b[1] end
        if a[5] ~= b[5] then return a[5] < b[5] end
        return a[2] < b[2]
    end)

    -- Guarded, because Equipment's and Pets' tools read this file with a DB
    -- that has only RegisterItem.
    local out = { "if DB.WorldDrops then DB:WorldDrops({", "    kills = {" }
    local bands = {}
    for band in pairs(kills) do bands[#bands + 1] = band end
    table.sort(bands)
    for _, band in ipairs(bands) do
        out[#out + 1] = ("        [%d] = %d,"):format(band, kills[band])
    end
    out[#out + 1] = "    },"
    out[#out + 1] = "    -- band, item ID, quality, corpses that held it, mob"
    out[#out + 1] = "    drops = {"
    for _, row in ipairs(drops) do
        out[#out + 1] = ("        { %d, %d, %d, %d, %s },"):format(row[1], row[2], row[3], row[4], Quote(row[5]))
    end
    out[#out + 1] = "    },"
    out[#out + 1] = "    -- lowest level, highest level, kills, zone, where in it"
    out[#out + 1] = "    mobs = {"
    local names = {}
    for name in pairs(mobs) do names[#names + 1] = name end
    table.sort(names)
    for _, name in ipairs(names) do
        local mob = mobs[name]
        out[#out + 1] = ("        [%s] = { %d, %d, %d, %s%s },"):format(Quote(name),
            mob.minLevel or 0, mob.maxLevel or mob.minLevel or 0, mob.kills, Quote(mob.zone or "?"),
            mob.location and (", " .. Quote(mob.location)) or "")
    end
    out[#out + 1] = "    },"
    out[#out + 1] = "}) end"
    return table.concat(out, "\n")
end

--------------------------------------------------------------------------------
-- Turning it on and off, and the chat command
--------------------------------------------------------------------------------

function WorldDrops:IsEnabled()
    return not (ns.db and ns.db.worldDrops == false)
end

function WorldDrops:SetEnabled(on)
    ns.db.worldDrops = on and true or false
    if ns.TrackerUI and ns.TrackerUI.Refresh then pcall(ns.TrackerUI.Refresh, ns.TrackerUI) end
    if ns.RankingsUI and ns.RankingsUI.Refresh then pcall(ns.RankingsUI.Refresh, ns.RankingsUI) end
    if ns.KillTooltip and ns.KillTooltip.ForgetKept then ns.KillTooltip.ForgetKept() end
end

local function QualityName(quality)
    if quality == 3 then return L["Blue"] end
    if quality == 4 then return L["Purple"] end
    return L["Orange"]
end

--- The bands as chat lines.
function WorldDrops:Lines()
    local lines = {}
    for _, entry in ipairs((self:Bands())) do
        local label = WorldDrops.BandLabel(entry.band)
        if not WorldDrops.Measured(entry) then
            lines[#lines + 1] = L.Format("%1$s: %2$d kills, too few to say yet", label, entry.kills)
        else
            local one = WorldDrops.OneIn(entry.kills, entry.drops[2])
            lines[#lines + 1] = one
                and L.Format("%1$s: green gear 1 in %2$d kills (%3$d in %4$d)", label, one, entry.drops[2], entry.kills)
                or L.Format("%1$s: no green gear in %2$d kills", label, entry.kills)
            for _, quality in ipairs({ 3, 4, 5 }) do
                if entry.drops[quality] > 0 then
                    lines[#lines + 1] = "   " .. L.Format("%1$s: %2$d in %3$d kills",
                        QualityName(quality), entry.drops[quality], entry.kills)
                end
            end
        end
    end
    if #lines == 0 then lines[1] = L["No kills with a level yet."] end
    return lines
end

ns.RegisterCommand("worlddrops", L["world drop chances by mob level, or turn them on or off"], function(arg)
    arg = (arg or ""):lower()
    if arg == "on" or arg == "off" then
        WorldDrops:SetEnabled(arg == "on")
        ns.Print(WorldDrops:IsEnabled() and L["world drop chances on."] or L["world drop chances off."])
        if ns.SettingsUI then ns.SettingsUI:Refresh() end
        return
    end
    ns.Print(L["World drops, green gear and better, by mob level:"])
    for _, line in ipairs(WorldDrops:Lines()) do ns.Print("  " .. line) end
end)
