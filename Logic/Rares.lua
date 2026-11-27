-- Blackthornes Farmer -- Logic/Rares.lua
-- Forever's rare mobs and treasure chests (Data/Data_Rares.lua): where they
-- stand and what they can give, for the Grind tab's Rares and Treasures
-- views (UI/RaresView.lua) and their map pins (UI/RarePins.lua).
--
-- "Last seen" and "Killed" come from your own play only: a rare you target,
-- hover or see the nameplate of is seen, one you loot is killed, a chest you
-- loot is opened. Saved account wide in `rareLog` (never rename it):
-- { seen = { [mob ID] = time }, killed = { ... }, opened = { [object ID] = time } }.
-- No drop rates ever show: what a rare drops and how often stays yours to find.
--
-- "Rare Seen Sound:" (rareSound, off unless ticked) plays a sound when you
-- see a rare, once in SOUND_GAP seconds for each; it asks ns.Muted() first.

local _, ns = ...
local L = ns.L

local Rares = ns.NewModule("Rares")

-- A rare seen again within this many seconds plays no second sound.
Rares.SOUND_GAP = 300
-- The raid warning sound.
Rares.SOUND = 8959
-- Rares within this many levels of yours sort first.
Rares.NEAR = 4

local function Clock()
    if type(time) ~= "function" then return 0 end
    local ok, now = pcall(time)
    return ok and tonumber(now) or 0
end
Rares.Clock = Clock

--------------------------------------------------------------------------------
-- The data
--------------------------------------------------------------------------------

--- { kind = "rare" or "treasure", id, name, low, high, spots, items, more,
--- zone } for each row, built once. A spot is { map, x, y, zone }.
function Rares:Entries(kind)
    self.built = self.built or {}
    if self.built[kind] then return self.built[kind] end
    local data = ns.RareData or {}
    local zones = ns.Spots and ns.Spots.MAP_ZONES or {}
    local list, byID = {}, {}
    for _, row in ipairs((kind == "rare" and data.rares or data.treasures) or {}) do
        local entry = { kind = kind, id = row[1], spots = {} }
        local spots
        if kind == "rare" then
            entry.name, entry.low, entry.high = row[2], row[3], row[4]
            if entry.low == 0 then entry.low, entry.high = nil, nil end
            spots, entry.items, entry.more = row[5], row[6], row[7] and true or nil
        else
            entry.name = row[2] or nil
            spots, entry.items = row[3], row[4]
        end
        for _, spot in ipairs(spots or {}) do
            local zone = zones[spot[1]]
            if zone then entry.spots[#entry.spots + 1] = { map = spot[1], x = spot[2], y = spot[3], zone = zone } end
        end
        if entry.spots[1] then
            entry.zone = entry.spots[1].zone
            list[#list + 1] = entry
            byID[entry.id] = entry
        end
    end
    self.built[kind] = list
    self.byID = self.byID or {}
    self.byID[kind] = byID
    return list
end

function Rares:Get(kind, id)
    self:Entries(kind)
    return self.byID[kind][id]
end

--- Is `entry` found in `zone` (English)?
function Rares.InZone(entry, zone)
    for _, spot in ipairs(entry.spots) do
        if spot.zone == zone then return true end
    end
    return false
end

--- The spots of `entry` in `zone`, else all of them.
function Rares.SpotsIn(entry, zone)
    local out = {}
    for _, spot in ipairs(entry.spots) do
        if spot.zone == zone then out[#out + 1] = spot end
    end
    return out[1] and out or entry.spots
end

--- An item's name: the client's (in its language) when it has seen it,
--- else the shipped English one. With its quality colour when known.
function Rares.ItemName(id)
    local name, quality
    if type(GetItemInfo) == "function" then
        local ok, n, _, q = pcall(GetItemInfo, id)
        if ok and type(n) == "string" and n ~= "" then name, quality = n, q end
    end
    name = name or (ns.RareData and ns.RareData.items and ns.RareData.items[id])
    if not name then return nil end
    if type(quality) == "number" and type(ITEM_QUALITY_COLORS) == "table" and ITEM_QUALITY_COLORS[quality] then
        local color = ITEM_QUALITY_COLORS[quality]
        local ok, hex = pcall(function() return color.hex end)
        if ok and type(hex) == "string" then return hex .. name .. "|r", name end
    end
    return name, name
end

--- "Boahn's Fang, Brambleweed Leggings", or "a Forever drop" when it gives
--- only items with no name yet.
function Rares.ItemsText(entry, most)
    local names = {}
    for _, id in ipairs(entry.items or {}) do
        local shown = Rares.ItemName(id)
        if shown then names[#names + 1] = shown end
        if most and #names >= most then break end
    end
    if #names == 0 then return entry.more and L["a Forever drop"] or "" end
    return table.concat(names, ", ")
end

--- The name shown for `entry`: a chest with no name is a Treasure.
function Rares.Name(entry)
    return entry.name or L["Treasure"]
end

--------------------------------------------------------------------------------
-- The lists
--------------------------------------------------------------------------------

--- Your zone (English) and level.
function Rares.Here()
    local player = ns.Spots and ns.Spots:Player() or {}
    return player.zone and ns.Spots.ZoneOf(player.zone) or nil, player.level
end

--- How far a rare's levels are from yours.
function Rares.LevelGap(entry, level)
    if not (level and entry.low) then return 99 end
    if level < entry.low then return entry.low - level end
    if level > entry.high then return level - entry.high end
    return 0
end

--- The entries of `kind` to list, and whether they are all in `zone`:
--- the zone's when it has any, else every one (rares near your level
--- first; chests by zone).
function Rares:List(kind, zone, level, mapID, x, y)
    local all = self:Entries(kind)
    local list = {}
    if zone then
        for _, entry in ipairs(all) do
            if Rares.InZone(entry, zone) then list[#list + 1] = entry end
        end
    end
    local here = #list > 0
    if not here then
        for _, entry in ipairs(all) do list[#list + 1] = entry end
    end
    local function Away(entry)
        if not (mapID and x and y) then return 1e9 end
        local best = 1e9
        for _, spot in ipairs(entry.spots) do
            if spot.map == mapID then
                local dx, dy = spot.x / 100 - x, spot.y / 100 - y
                best = math.min(best, dx * dx + dy * dy)
            end
        end
        return best
    end
    local keys = {}
    for _, entry in ipairs(list) do
        keys[entry] = { gap = Rares.LevelGap(entry, level), away = Away(entry), name = Rares.Name(entry) }
    end
    table.sort(list, function(a, b)
        local ka, kb = keys[a], keys[b]
        if kind == "rare" then
            local na, nb = ka.gap <= Rares.NEAR, kb.gap <= Rares.NEAR
            if na ~= nb then return na end
            if not here and ka.gap ~= kb.gap then return ka.gap < kb.gap end
            if (a.low or 0) ~= (b.low or 0) then return (a.low or 0) < (b.low or 0) end
        else
            if ka.away ~= kb.away then return ka.away < kb.away end
            if not here and a.zone ~= b.zone then return a.zone < b.zone end
        end
        if ka.name ~= kb.name then return ka.name < kb.name end
        return a.id < b.id
    end)
    return list, here
end

--------------------------------------------------------------------------------
-- What you saw, killed and opened
--------------------------------------------------------------------------------

function Rares.Log()
    local db = ns.db
    if type(db) ~= "table" then return nil end
    if type(db.rareLog) ~= "table" then db.rareLog = {} end
    local log = db.rareLog
    for _, key in ipairs({ "seen", "killed", "opened" }) do
        if type(log[key]) ~= "table" then log[key] = {} end
    end
    return log
end

--- "today", "yesterday", "3 days ago": calendar days, stepped from noon
--- (Util.Noon), so a kill last night seen this morning was yesterday.
function Rares.When(stamp, now)
    now = now or Clock()
    local days = math.floor(math.max(0, now - stamp) / 86400 + 0.5)
    local Noon = ns.Util and ns.Util.Noon
    if Noon then days = math.max(0, math.floor((Noon(now) - Noon(stamp)) / 86400 + 0.5)) end
    if days == 0 then return L["today"] end
    if days == 1 then return L["yesterday"] end
    return L.Format("%d days ago", days)
end

--- "Killed 2 days ago", "Seen today" or "Never seen" (a chest: "Opened
--- today" or "Never opened"), and its colour key.
function Rares.SeenText(entry, now)
    local log = Rares.Log()
    if entry.kind == "treasure" then
        local opened = log and log.opened[entry.id]
        if opened then return L.Format("Opened %s", Rares.When(opened, now)), "text" end
        return L["Never opened"], "muted"
    end
    local killed = log and log.killed[entry.id]
    local seen = log and log.seen[entry.id]
    if killed and (not seen or killed >= seen) then
        return L.Format("Killed %s", Rares.When(killed, now)), "text"
    end
    if seen then return L.Format("Seen %s", Rares.When(seen, now)), "good" end
    return L["Never seen"], "muted"
end

--- The hover's last line: "You killed it 2 days ago."
function Rares.TipText(entry, now)
    local log = Rares.Log()
    if entry.kind == "treasure" then
        local opened = log and log.opened[entry.id]
        return opened and L.Format("You opened it %s.", Rares.When(opened, now)) or nil
    end
    local killed = log and log.killed[entry.id]
    local seen = log and log.seen[entry.id]
    if killed and (not seen or killed >= seen) then return L.Format("You killed it %s.", Rares.When(killed, now)) end
    if seen then return L.Format("You saw it %s.", Rares.When(seen, now)) end
    return nil
end

Rares.version = 0

local function Changed()
    Rares.version = Rares.version + 1
    if Rares.onChange then pcall(Rares.onChange) end
end

--- A mob ID in a guid, if it is a rare we list.
function Rares:RareOf(guid)
    local id = ns.Harvest and ns.Harvest.NpcID(guid)
    return id and self:Get("rare", id) or nil
end

--- A rare was in sight: note it, and play the sound when ticked.
function Rares:NoteSeen(guid, now)
    local entry = self:RareOf(guid)
    local log = entry and Rares.Log()
    if not log then return false end
    now = now or Clock()
    local last = log.seen[entry.id]
    log.seen[entry.id] = now
    if not last or now - last >= Rares.SOUND_GAP then
        Rares.PlaySeen()
    end
    if not last or Rares.When(last, now) ~= Rares.When(now, now) then Changed() end
    return true
end

--- A rare you looted.
function Rares:NoteKill(guid, now)
    local entry = self:RareOf(guid)
    local log = entry and Rares.Log()
    if not log then return false end
    log.killed[entry.id] = now or Clock()
    Changed()
    return true
end

--- A chest you looted, by its guid ("GameObject-0-...-180523-...").
function Rares:NoteOpened(guid, now)
    if type(guid) ~= "string" then return false end
    local kind, id = guid:match("^(%a+)%-[^%-]+%-[^%-]+%-[^%-]+%-[^%-]+%-(%d+)%-")
    if kind ~= "GameObject" then return false end
    local entry = self:Get("treasure", tonumber(id))
    local log = entry and Rares.Log()
    if not log then return false end
    log.opened[entry.id] = now or Clock()
    Changed()
    return true
end

--- Read the guid of `unit` and note a rare. Every read guarded: a dungeon
--- hands out guids that raise when touched.
function Rares:NoteUnit(unit)
    if type(UnitGUID) ~= "function" then return false end
    local ok, guid = pcall(UnitGUID, unit)
    -- Joining a secret guid works and gives a secret back, so that is no
    -- test; Readable asks the game whether it is secret.
    local text = ok and ns.Harvest and ns.Harvest.Readable(guid) or nil
    if not text then return false end
    return self:NoteSeen(text)
end

--------------------------------------------------------------------------------
-- Settings: all off unless ticked
--------------------------------------------------------------------------------

function Rares.PinsOn(kind)
    local db = ns.db
    if type(db) ~= "table" then return false end
    if kind == "treasure" then return db.treasurePins == true end
    return db.rarePins == true
end

function Rares:SetPins(kind, on)
    ns.db[kind == "treasure" and "treasurePins" or "rarePins"] = on and true or nil
    Changed()
end

function Rares.SoundOn()
    return type(ns.db) == "table" and ns.db.rareSound == true
end

function Rares:SetSound(on)
    ns.db.rareSound = on and true or nil
end

function Rares.PlaySeen(force)
    if not (force or Rares.SoundOn()) then return false end
    if ns.Muted and ns.Muted() then return false end
    if type(PlaySound) ~= "function" then return false end
    local ok = pcall(PlaySound, Rares.SOUND, "Master")
    return ok
end

--------------------------------------------------------------------------------
-- Show the Way
--------------------------------------------------------------------------------

--- The arrow follows `entry`'s spots, nearest first, as a camp.
function Rares:Camp(entry, zone)
    local mobs = {}
    for _, spot in ipairs(Rares.SpotsIn(entry, zone)) do
        mobs[#mobs + 1] = { name = Rares.Name(entry), zone = spot.zone, coords = { spot.x, spot.y },
            minLevel = entry.low, maxLevel = entry.high }
    end
    return { zone = mobs[1].zone, label = Rares.Name(entry), mobs = mobs, coords = mobs[1].coords, rare = entry }
end

function Rares:ShowWay(entry, zone)
    if type(entry) ~= "table" or not entry.spots[1] then return false end
    return ns.Arrow:Grind(self:Camp(entry, zone))
end

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------

function Rares:OnEnable()
    ns.RegisterEvent(self, "PLAYER_TARGET_CHANGED", function() Rares:NoteUnit("target") end)
    ns.RegisterEvent(self, "UPDATE_MOUSEOVER_UNIT", function() Rares:NoteUnit("mouseover") end)
    ns.RegisterEvent(self, "NAME_PLATE_UNIT_ADDED", function(_, _, unit)
        if type(unit) == "string" then Rares:NoteUnit(unit) end
    end)
    -- A chest you loot: the loot window's sources name it.
    ns.OnLootWindow(self, function()
        if not ns.Harvest then return end
        for _, guid in ipairs(ns.Harvest:LootSources()) do
            if Rares:NoteOpened(guid) then return end
        end
    end)
end
