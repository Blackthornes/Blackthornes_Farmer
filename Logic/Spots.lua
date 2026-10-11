-- Blackthornes Farmer -- Logic/Spots.lua
-- The best places near you to farm something (2026-09-27: "a button
-- to the goal that allows the player to click and find the best place to farm
-- each goal near me").
--
-- Every place the addon knows for the item is ranked:
--
--   * Distance. Zones are a map of which borders which, so "near" is how
--     many zones you would cross: 0 where you stand, 1 next door. The other
--     continent is far whatever the count. Dungeons and capitals count as
--     the zone they sit in.
--   * Level. A spot whose level band starts above you is dangerous, more so
--     the further above. Below you is fine: quicker kills, safer nodes.
--   * The rate, where there is one: a 40% drop beats a 5% one next door.
--   * Your own record. A mob you have tallied, or a node you have gathered
--     that item from, is known to work on Forever and gets a push up, with
--     what you measured shown beside it.
--
-- Only data the addon already holds is used. The player's zone and level are
-- read inside a pcall; in an instance the client may refuse either, and the
-- ranking then leaves distance or level out rather than guessing.

local _, ns = ...
local L = ns.L

local Spots = ns.NewModule("Spots")

local Util = ns.Util

-- Which zone borders which. Travel by boat or flight is not a border.
local BORDERS = {
    -- Eastern Kingdoms
    ["Elwynn Forest"] = { "Westfall", "Duskwood", "Redridge Mountains" },
    ["Westfall"] = { "Elwynn Forest", "Duskwood" },
    ["Duskwood"] = { "Elwynn Forest", "Westfall", "Redridge Mountains", "Deadwind Pass", "Stranglethorn Vale" },
    ["Redridge Mountains"] = { "Elwynn Forest", "Duskwood", "Burning Steppes" },
    ["Stranglethorn Vale"] = { "Duskwood" },
    ["Deadwind Pass"] = { "Duskwood", "Swamp of Sorrows" },
    ["Swamp of Sorrows"] = { "Deadwind Pass", "Blasted Lands" },
    ["Blasted Lands"] = { "Swamp of Sorrows" },
    ["Burning Steppes"] = { "Redridge Mountains", "Searing Gorge" },
    ["Searing Gorge"] = { "Burning Steppes", "Badlands" },
    ["Badlands"] = { "Searing Gorge", "Loch Modan" },
    ["Loch Modan"] = { "Badlands", "Dun Morogh", "Wetlands" },
    ["Dun Morogh"] = { "Loch Modan" },
    ["Wetlands"] = { "Loch Modan", "Arathi Highlands" },
    ["Arathi Highlands"] = { "Wetlands", "Hillsbrad Foothills", "The Hinterlands" },
    ["Hillsbrad Foothills"] = { "Arathi Highlands", "Alterac Mountains", "Silverpine Forest", "The Hinterlands" },
    ["Alterac Mountains"] = { "Hillsbrad Foothills", "Silverpine Forest", "Western Plaguelands" },
    ["Silverpine Forest"] = { "Tirisfal Glades", "Hillsbrad Foothills", "Alterac Mountains" },
    ["Tirisfal Glades"] = { "Silverpine Forest", "Western Plaguelands" },
    ["Western Plaguelands"] = { "Tirisfal Glades", "Eastern Plaguelands", "Alterac Mountains", "The Hinterlands" },
    ["Eastern Plaguelands"] = { "Western Plaguelands" },
    ["The Hinterlands"] = { "Hillsbrad Foothills", "Arathi Highlands", "Western Plaguelands" },

    -- Kalimdor
    ["Teldrassil"] = {},
    ["Darkshore"] = { "Ashenvale" },
    ["Ashenvale"] = { "Darkshore", "Felwood", "Azshara", "Stonetalon Mountains", "The Barrens" },
    ["Felwood"] = { "Ashenvale", "Winterspring", "Moonglade" },
    ["Winterspring"] = { "Felwood", "Moonglade" },
    ["Moonglade"] = { "Felwood", "Winterspring" },
    ["Azshara"] = { "Ashenvale" },
    ["Stonetalon Mountains"] = { "Ashenvale", "Desolace", "The Barrens" },
    ["Desolace"] = { "Stonetalon Mountains", "Feralas" },
    ["Feralas"] = { "Desolace", "Thousand Needles" },
    ["The Barrens"] = { "Ashenvale", "Stonetalon Mountains", "Durotar", "Mulgore", "Dustwallow Marsh", "Thousand Needles" },
    ["Durotar"] = { "The Barrens" },
    ["Mulgore"] = { "The Barrens" },
    ["Dustwallow Marsh"] = { "The Barrens" },
    ["Thousand Needles"] = { "The Barrens", "Feralas", "Tanaris" },
    ["Tanaris"] = { "Thousand Needles", "Un'Goro Crater" },
    ["Un'Goro Crater"] = { "Tanaris", "Silithus" },
    ["Silithus"] = { "Un'Goro Crater" },
}

Spots.BORDERS = BORDERS

local KALIMDOR = {
    ["Teldrassil"] = true, ["Darkshore"] = true, ["Ashenvale"] = true, ["Felwood"] = true,
    ["Winterspring"] = true, ["Moonglade"] = true, ["Azshara"] = true,
    ["Stonetalon Mountains"] = true, ["Desolace"] = true, ["Feralas"] = true,
    ["The Barrens"] = true, ["Durotar"] = true, ["Mulgore"] = true,
    ["Dustwallow Marsh"] = true, ["Thousand Needles"] = true, ["Tanaris"] = true,
    ["Un'Goro Crater"] = true, ["Silithus"] = true,
}

-- Places inside a zone: dungeons and capitals count as the zone around them.
local INSIDE = {
    ["Stormwind City"] = "Elwynn Forest", ["Ironforge"] = "Dun Morogh",
    ["Undercity"] = "Tirisfal Glades", ["Orgrimmar"] = "Durotar",
    ["Thunder Bluff"] = "Mulgore", ["Darnassus"] = "Teldrassil",
    ["The Deadmines"] = "Westfall", ["The Stockade"] = "Elwynn Forest",
    ["Shadowfang Keep"] = "Silverpine Forest", ["Blackfathom Deeps"] = "Ashenvale",
    ["Ragefire Chasm"] = "Durotar", ["Wailing Caverns"] = "The Barrens",
    -- Forever's own name for it, read inside: the harvest recorded it so.
    ["The Wailing Caverns"] = "The Barrens",
    ["Razorfen Kraul"] = "The Barrens", ["Razorfen Downs"] = "Thousand Needles",
    ["Gnomeregan"] = "Dun Morogh", ["Scarlet Monastery"] = "Tirisfal Glades",
    ["Uldaman"] = "Badlands", ["Zul'Farrak"] = "Tanaris", ["Maraudon"] = "Desolace",
    ["Sunken Temple"] = "Swamp of Sorrows", ["The Temple of Atal'Hakkar"] = "Swamp of Sorrows",
    ["Blackrock Depths"] = "Searing Gorge", ["Blackrock Spire"] = "Burning Steppes",
    ["Dire Maul"] = "Feralas", ["Scholomance"] = "Western Plaguelands",
    ["Stratholme"] = "Eastern Plaguelands",
}

-- Each zone's map ID, as Classic numbers its maps (Elwynn Forest 1429), for
-- a client that names its zones in another language: there GetRealZoneText
-- says "Wald von Elwynn", and the zone is told by the map you are on (or
-- one it sits inside) instead. On an English client the names match and
-- these are never read. Forever's own numbers are not confirmed, so a map
-- whose ID is not here leaves the client's name as it was.
Spots.ZONE_MAPS = {
    ["Durotar"] = 1411, ["Mulgore"] = 1412, ["The Barrens"] = 1413,
    ["Alterac Mountains"] = 1416, ["Arathi Highlands"] = 1417, ["Badlands"] = 1418,
    ["Blasted Lands"] = 1419, ["Tirisfal Glades"] = 1420, ["Silverpine Forest"] = 1421,
    ["Western Plaguelands"] = 1422, ["Eastern Plaguelands"] = 1423, ["Hillsbrad Foothills"] = 1424,
    ["The Hinterlands"] = 1425, ["Dun Morogh"] = 1426, ["Searing Gorge"] = 1427,
    ["Burning Steppes"] = 1428, ["Elwynn Forest"] = 1429, ["Deadwind Pass"] = 1430,
    ["Duskwood"] = 1431, ["Loch Modan"] = 1432, ["Redridge Mountains"] = 1433,
    ["Stranglethorn Vale"] = 1434, ["Swamp of Sorrows"] = 1435, ["Westfall"] = 1436,
    ["Wetlands"] = 1437, ["Teldrassil"] = 1438, ["Darkshore"] = 1439, ["Ashenvale"] = 1440,
    ["Thousand Needles"] = 1441, ["Stonetalon Mountains"] = 1442, ["Desolace"] = 1443,
    ["Feralas"] = 1444, ["Dustwallow Marsh"] = 1445, ["Tanaris"] = 1446, ["Azshara"] = 1447,
    ["Felwood"] = 1448, ["Un'Goro Crater"] = 1449, ["Moonglade"] = 1450, ["Silithus"] = 1451,
    ["Winterspring"] = 1452, ["Stormwind City"] = 1453, ["Orgrimmar"] = 1454,
    ["Ironforge"] = 1455, ["Thunder Bluff"] = 1456, ["Darnassus"] = 1457, ["Undercity"] = 1458,
}
Spots.MAP_ZONES = {}
for zone, mapID in pairs(Spots.ZONE_MAPS) do Spots.MAP_ZONES[mapID] = zone end

-- What the client called a zone the map then named, this session:
-- ["Wald von Elwynn"] = "Elwynn Forest". Your own records keep the client's
-- name, so this lets them count where they are too.
Spots.clientZones = {}

-- Any zone at all ("any coastline"): near, but never "you are here".
local ANYWHERE_HOPS = 1

-- A place the map does not know, or the player's own zone unreadable.
local UNKNOWN_HOPS = 4

-- The other continent: a boat or a long flight away.
local OTHER_CONTINENT = 8

-- How much each thing weighs. Lower scores rank higher.
local PER_HOP = 10
local PER_LEVEL_ABOVE = 6
local RATE_WEIGHT = 0.25
local YOURS_BONUS = 8
local FOREVER_BONUS = 3
-- A node or herb your gathering skill cannot take yet, or a profession you
-- do not have: as far down as six zones away, so it still shows, last
-- (the owner, 2026-10-11: send the player only where they can gather).
local SKILL_SHORT = 60
-- The gathering skills read for that (Spots:Player).
Spots.GATHERING = { "Mining", "Herbalism", "Skinning" }

-- The most places shown.
Spots.MAX = 6

--------------------------------------------------------------------------------
-- The map
--------------------------------------------------------------------------------

--- The zone `place` is in: itself for a zone, the zone around it for a
--- dungeon or capital, nil when it is not one place ("any coastline").
function Spots.ZoneOf(place)
    if type(place) ~= "string" then return nil end
    if place:lower():find("^any ") then return nil end
    place = Spots.English(place)
    return INSIDE[place] or place
end

--- `zone` by the English name the data uses, where this session has seen
--- the client call it something else; else as it is.
function Spots.English(zone)
    return Spots.clientZones[zone] or zone
end

--- Is `zone` a place the map knows by its English name?
function Spots.Known(zone)
    return BORDERS[zone] ~= nil or INSIDE[zone] ~= nil
end

function Spots.Continent(zone)
    zone = Spots.ZoneOf(zone)
    if not zone or not BORDERS[zone] then return nil end
    return KALIMDOR[zone] and "Kalimdor" or "Eastern Kingdoms"
end

--- How many zones apart `from` and `to` are, crossing borders. Nil when
--- either is not on the map.
--
-- When the way is not over borders, the count is only a weight for the
-- ranking, so a second answer says how you get there: "other continent" or
-- "by boat". A walk of eight zones is not the other continent.
function Spots.Hops(from, to)
    from, to = Spots.ZoneOf(from), Spots.ZoneOf(to)
    if not (from and to and BORDERS[from] and BORDERS[to]) then return nil end
    if from == to then return 0 end

    if Spots.Continent(from) ~= Spots.Continent(to) then return OTHER_CONTINENT, "other continent" end

    local seen = { [from] = true }
    local frontier = { from }
    local hops = 0

    while #frontier > 0 do
        hops = hops + 1
        local next_ = {}
        for _, zone in ipairs(frontier) do
            for _, near in ipairs(BORDERS[zone] or {}) do
                if near == to then return hops end
                if not seen[near] then
                    seen[near] = true
                    next_[#next_ + 1] = near
                end
            end
        end
        frontier = next_
    end

    -- Same continent, no road on this map (Teldrassil): a boat away.
    return UNKNOWN_HOPS, "by boat"
end

--------------------------------------------------------------------------------
-- The player
--------------------------------------------------------------------------------

local function Read(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, value = pcall(fn, ...)
    if not ok then return nil end
    return value
end

--- The English name of the zone the map you are on is in, by map ID: that
--- map or one it sits inside. Nil when none is in Spots.ZONE_MAPS.
function Spots.ZoneFromMap()
    if not (type(C_Map) == "table" and type(C_Map.GetBestMapForUnit) == "function") then return nil end
    local mapID = ns.Harvest.ReadableNumber(Read(C_Map.GetBestMapForUnit, "player"))
    for _ = 1, 8 do
        if not mapID or mapID <= 0 then return nil end
        if Spots.MAP_ZONES[mapID] then return Spots.MAP_ZONES[mapID] end
        if type(C_Map.GetMapInfo) ~= "function" then return nil end
        local info = Read(C_Map.GetMapInfo, mapID)
        if type(info) ~= "table" then return nil end
        local ok, parent = pcall(function() return info.parentMapID end)
        mapID = ok and ns.Harvest.ReadableNumber(parent) or nil
    end
    return nil
end

--- Where you are and your level, either nil when the client will not say.
--
-- The zone is the English name the data uses. A client in another language
-- names it in its own, and then the map ID says which zone it is.
function Spots:Player()
    local zone = ns.Harvest.Readable(Read(GetRealZoneText))
    if zone == "" then zone = nil end
    if zone and not Spots.Known(zone) and not Util.EnglishClient() then
        local english = Spots.clientZones[zone] or Spots.ZoneFromMap()
        if english then
            Spots.clientZones[zone] = english
            zone = english
        end
    end

    local level = ns.Harvest.ReadableNumber(Read(UnitLevel, "player"))
    if level and level <= 0 then level = nil end

    return { zone = zone, level = level, skills = Spots.Skills() }
end

--- Your skill in each gathering profession, as { Mining = 80, ... } with a
--- profession you lack left out, or nil when the client will not say.
--
-- Read the way Fishing:Skill reads fishing: a retail engine through
-- GetProfessions, a classic one through the skill lines. Forever is the
-- first with the content of the second, so both are tried. Kept for
-- SKILLS_KEEP seconds, since a tooltip asks each time it shows.
Spots.SKILLS_KEEP = 10

function Spots.ForgetSkills()
    Spots.skillsAt, Spots.skillsKept = nil, nil
end

function Spots.Skills()
    local now = type(GetTime) == "function" and GetTime() or nil
    if now and Spots.skillsAt and now - Spots.skillsAt < Spots.SKILLS_KEEP then
        return Spots.skillsKept or nil
    end
    local gathering = Spots.ReadSkills()
    Spots.skillsAt, Spots.skillsKept = now, gathering or false
    return gathering
end

function Spots.ReadSkills()
    local skills, read = {}, false

    if type(GetProfessions) == "function" and type(GetProfessionInfo) == "function" then
        local ok, first, second = pcall(GetProfessions)
        if ok then
            read = true
            for _, index in ipairs({ ns.Harvest.ReadableNumber(first) or false,
                ns.Harvest.ReadableNumber(second) or false }) do
                if index then
                    local got, name, _, rank = pcall(GetProfessionInfo, index)
                    name = got and ns.Harvest.Readable(name) or nil
                    rank = got and ns.Harvest.ReadableNumber(rank) or nil
                    if name and rank then skills[name] = rank end
                end
            end
        end
    end

    if not next(skills) and type(GetNumSkillLines) == "function" and type(GetSkillLineInfo) == "function" then
        local ok, lines = pcall(GetNumSkillLines)
        local count = ok and ns.Harvest.ReadableNumber(lines) or nil
        if count and count > 0 then read = true end
        for index = 1, count or 0 do
            local gotLine, lineName, isHeader, _, rank = pcall(GetSkillLineInfo, index)
            local name = gotLine and not isHeader and ns.Harvest.Readable(lineName) or nil
            local value = gotLine and ns.Harvest.ReadableNumber(rank) or nil
            if name and value then skills[name] = value end
        end
    end

    if not read then return nil end
    -- Kept by the English name, whatever the client calls the skill.
    local gathering = {}
    for name, rank in pairs(skills) do
        local english = ns.Gathering.SkillOf(name, Spots.GATHERING)
        if english and (name == english or gathering[english] == nil) then gathering[english] = rank end
    end
    return gathering
end

--- What a spot's "Mining 65" asks of you: the profession, the skill it
--- needs, and what you have (nil when you lack the profession). Nil when
--- the spot needs no gathering skill, or your skills could not be read.
function Spots.SkillNeed(spot, player)
    if type(spot.requires) ~= "string" or not (player and player.skills) then return nil end
    local profession, needed = spot.requires:match("^(%a+) (%d+)$")
    needed = tonumber(needed)
    if not (profession and needed) then return nil end
    local known = false
    for _, name in ipairs(Spots.GATHERING) do
        if name == profession then known = true break end
    end
    if not known then return nil end
    return profession, needed, player.skills[profession]
end

--- "needs 125, you have 80" or "needs Mining", or nil when you can gather it.
function Spots.SkillShortText(spot)
    local short = spot.skillShort
    if not short then return nil end
    if short.have then return L.Format("needs %d, you have %d", short.needed, short.have) end
    -- The profession is kept by its English name; only the words shown change.
    local shown = ({ Mining = L["Mining"], Herbalism = L["Herbalism"], Skinning = L["Skinning"] })[short.profession]
    return L.Format("needs %s", shown or short.profession)
end

--------------------------------------------------------------------------------
-- Candidates
--------------------------------------------------------------------------------

local function Key(name, zone)
    return ((name or "?") .. "|" .. (zone or "?")):lower()
end

--- Every place known for `item`: the database's, merged with what you have
--- recorded yourself.
function Spots:Candidates(itemName)
    local list, byKey = {}, {}

    local function Add(spot)
        local key = Key(spot.name, spot.zone)
        local existing = byKey[key]
        if existing then
            -- Your record fills in what the database left out.
            existing.yours = existing.yours or spot.yours
            existing.measured = existing.measured or spot.measured
            existing.minLevel = existing.minLevel or spot.minLevel
            existing.maxLevel = existing.maxLevel or spot.maxLevel
            existing.coords = existing.coords or spot.coords
            existing.location = existing.location or spot.location
            return
        end
        byKey[key] = spot
        list[#list + 1] = spot
    end

    local item = ns.DB:GetItem(itemName)
    for _, source in ipairs(item and item.sources or {}) do
        Add({
            name = source.name or ns.DB:KindLabel(source.kind),
            kind = source.kind,
            zone = source.zone,
            location = source.location,
            coords = source.coords,
            minLevel = source.minLevel,
            maxLevel = source.maxLevel,
            chance = source.chance,
            requires = source.requires,
            forever = source.provenance == "forever",
        })
    end

    -- Mobs you have tallied that dropped it.
    if ns.Harvest and ns.Harvest.ForItem then
        local ok, rows = pcall(ns.Harvest.ForItem, ns.Harvest, itemName)
        for _, row in ipairs(ok and rows or {}) do
            local record = row.record
            Add({
                name = record.mob,
                kind = "mob",
                zone = record.zone,
                location = record.location,
                -- Where you stood at its first corpse, in percent, the
                -- same as the database's: the arrow and the map pin use it.
                coords = type(record.coords) == "table" and tonumber(record.coords[1])
                    and tonumber(record.coords[2]) and record.coords or nil,
                minLevel = record.minLevel,
                maxLevel = record.maxLevel,
                yours = { kills = record.corpses, got = row.entry.corpses },
                measured = record.corpses >= 20 and row.chance or nil,
                forever = true,
            })
        end
    end

    -- Nodes you have gathered it from.
    if ns.Gathering and ns.Gathering.Store then
        local ok, nodes = pcall(ns.Gathering.Store, ns.Gathering)
        for _, node in pairs(ok and nodes or {}) do
            local got = type(node) == "table" and type(node.items) == "table" and node.items[itemName]
            if got and (tonumber(got.gathers) or 0) > 0 then
                Add({
                    name = node.node,
                    kind = node.kind or "node",
                    zone = node.zone,
                    location = node.location,
                    coords = node.coords,
                    yours = { gathers = node.gathers, got = got.count },
                    forever = true,
                })
            end
        end
    end

    return list
end

--------------------------------------------------------------------------------
-- Ranking
--------------------------------------------------------------------------------

--- Why a spot is where it is, in a few words. `travel` is how Hops said the
--- way goes when it is not over borders (spot.travel after Score).
function Spots.DistanceText(hops, zone, travel)
    -- A spot recorded where the zone could not be read (inside an
    -- instance) says nothing, rather than "in many places".
    if type(zone) ~= "string" then return "" end
    if not Spots.ZoneOf(zone) then return L["in many places"] end
    if hops == nil then return "" end
    -- `travel` stays English (Arrow reads it); only the words shown change.
    if travel == "by boat" then return L["by boat"] end
    if travel == "other continent" then return L["other continent"] end
    if travel then return travel end
    if hops == 0 then return L["you are here"] end
    if hops == 1 then return L["next zone over"] end
    return L.Format("%d zones away", hops)
end

function Spots:Score(spot, player)
    local hops, travel
    if type(spot.zone) ~= "string" then
        -- Where it is was never read: it ranks as far as an unknown place,
        -- never as near as "any coastline".
        hops = nil
    elseif not Spots.ZoneOf(spot.zone) then
        hops = ANYWHERE_HOPS
    elseif player.zone then
        hops, travel = Spots.Hops(player.zone, spot.zone)
    end
    spot.hops, spot.travel = hops, travel

    local score = (hops or UNKNOWN_HOPS) * PER_HOP

    if player.level and spot.minLevel then
        local above = spot.minLevel - player.level
        -- A couple of levels over is fine; more starts to cost.
        if above > 2 then score = score + (above - 2) * PER_LEVEL_ABOVE end
        spot.danger = above > 2 and above or nil
    end

    local rate = spot.measured or spot.chance
    if rate then score = score - rate * RATE_WEIGHT end

    if spot.yours then score = score - YOURS_BONUS end
    if spot.forever then score = score - FOREVER_BONUS end

    -- A node your skill cannot take yet still shows, last, saying why.
    local profession, needed, have = Spots.SkillNeed(spot, player)
    if profession and (not have or have < needed) then
        spot.skillShort = { profession = profession, needed = needed, have = have }
        score = score + SKILL_SHORT
    else
        spot.skillShort = nil
    end

    spot.score = score
    return score
end

--- The best places to farm `itemName` from where you are, best first, and
--- the player they were ranked for.
function Spots:For(itemName, player)
    player = player or self:Player()

    local spots = self:Candidates(itemName)
    for _, spot in ipairs(spots) do self:Score(spot, player) end

    table.sort(spots, function(a, b)
        if a.score ~= b.score then return a.score < b.score end
        if (a.minLevel or 0) ~= (b.minLevel or 0) then return (a.minLevel or 0) < (b.minLevel or 0) end
        return Key(a.name, a.zone) < Key(b.name, b.zone)
    end)

    local best = {}
    for index = 1, math.min(Spots.MAX, #spots) do best[index] = spots[index] end
    return best, player
end

--- One spot as a chat line: "Copper Vein, Westfall (10-20), next zone over".
function Spots:Line(spot)
    local parts = { Util.Colored("accent", spot.name or "?"), spot.zone or "?" }
    if spot.location then parts[#parts] = parts[#parts] .. ", " .. spot.location end

    local text = parts[1] .. ", " .. parts[2]
    if spot.minLevel then
        text = text .. (" (%s)"):format(ns.Search:LevelText(spot))
    end
    if spot.coords then
        text = text .. ("  %.1f, %.1f"):format(spot.coords[1], spot.coords[2])
    end

    local distance = Spots.DistanceText(spot.hops, spot.zone, spot.travel)
    if distance ~= "" then text = text .. ", " .. distance end
    local short = Spots.SkillShortText(spot)
    if short then text = text .. ", " .. Util.Colored("warn", short) end
    return text
end

--------------------------------------------------------------------------------
-- Marking a spot
--------------------------------------------------------------------------------

--- The map id of `zone`, found from the map you are on: that map, or one it
--- sits inside (a cave or a mine can have a map of its own). When no map on
--- the way up carries the zone's name, the map you are on, as before: the
--- zone was already matched by name (Mark), and a map name Forever spells
--- differently must not stop the pin. Nil only when the client will not say.
local function ZoneMapID(zone)
    local here = ns.Harvest.ReadableNumber(Read(C_Map.GetBestMapForUnit, "player"))
    if not here then return nil end
    local mapID = here

    -- A client that cannot name its maps: the map you are on is the best
    -- there is.
    if type(C_Map.GetMapInfo) ~= "function" then return here end

    for _ = 1, 8 do
        local info = Read(C_Map.GetMapInfo, mapID)
        if type(info) ~= "table" then return here end

        local ok, name, parent = pcall(function() return info.name, info.parentMapID end)
        if not ok then return here end
        if ns.Harvest.Readable(name) == zone then return mapID end
        -- A client in another language: the zone's map by its ID.
        if Spots.ZONE_MAPS[zone] == mapID and not Util.EnglishClient() then return mapID end

        mapID = ns.Harvest.ReadableNumber(parent)
        if not mapID or mapID <= 0 then return here end
    end

    return here
end

--- Put the map's pin on a spot. Only for one in the zone you are standing in
--- with coordinates, where the zone's map id comes live from the client
--- rather than from a table that may not match Forever. True if placed.
--
-- "Here" for the ranking takes in a dungeon or a capital inside the zone,
-- but their coordinates are on maps of their own: a pin is only put down
-- when the spot's zone is the very zone you are in.
function Spots:Mark(spot)
    if not (spot and spot.coords and spot.hops == 0) then return false end
    if not (type(C_Map) == "table" and type(C_Map.SetUserWaypoint) == "function") then return false end
    if not (type(UiMapPoint) == "table" and type(UiMapPoint.CreateFromCoordinates) == "function") then
        return false
    end

    if type(spot.zone) ~= "string" then return false end
    -- Your own records keep the client's name for the zone.
    local zone = Spots.English(spot.zone)
    if self:Player().zone ~= zone then return false end

    local mapID = ZoneMapID(zone)
    if not mapID then return false end

    local ok = pcall(function()
        local point = UiMapPoint.CreateFromCoordinates(mapID, spot.coords[1] / 100, spot.coords[2] / 100)
        C_Map.SetUserWaypoint(point)
        if type(C_SuperTrack) == "table" and type(C_SuperTrack.SetSuperTrackedUserWaypoint) == "function" then
            C_SuperTrack.SetSuperTrackedUserWaypoint(true)
        end
    end)
    return ok
end

--- Print a spot and pin it on the map where that can be done.
function Spots:Share(itemName, spot)
    local marked = self:Mark(spot)
    ns.Print(("%s: %s%s"):format(Util.Colored("accent", itemName), self:Line(spot),
        marked and Util.Colored("good", L["  (pinned on your map)"]) or ""))
    return marked
end

--------------------------------------------------------------------------------
-- Command
--------------------------------------------------------------------------------

ns.RegisterCommand("where", L["the best places near you to farm an item: /farm where copper ore"], function(rest)
    local name = ns.Goals and ns.Goals:ResolveItem(rest) or Util.Trim(rest)
    if not name or name == "" then
        ns.Print(L["name an item: /farm where copper ore"])
        return
    end

    if ns.GoalsUI and ns.GoalsUI.OpenSpots then
        ns.GoalsUI:OpenSpots(name)
        return
    end

    local spots = Spots:For(name)
    if #spots == 0 then
        ns.Print(L.Format("no places known for %s yet.", name))
        return
    end
    for index, spot in ipairs(spots) do
        ns.PrintRaw(("  %d. %s"):format(index, Spots:Line(spot)))
    end
end)
