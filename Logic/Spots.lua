-- Blackthornes Farmer -- Logic/Spots.lua
-- The best places near you to farm something (Trent, 2026-09-27: "a button
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
    ["Razorfen Kraul"] = "The Barrens", ["Razorfen Downs"] = "Thousand Needles",
    ["Gnomeregan"] = "Dun Morogh", ["Scarlet Monastery"] = "Tirisfal Glades",
    ["Uldaman"] = "Badlands", ["Zul'Farrak"] = "Tanaris", ["Maraudon"] = "Desolace",
    ["Sunken Temple"] = "Swamp of Sorrows", ["The Temple of Atal'Hakkar"] = "Swamp of Sorrows",
    ["Blackrock Depths"] = "Searing Gorge", ["Blackrock Spire"] = "Burning Steppes",
    ["Dire Maul"] = "Feralas", ["Scholomance"] = "Western Plaguelands",
    ["Stratholme"] = "Eastern Plaguelands",
}

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
    return INSIDE[place] or place
end

function Spots.Continent(zone)
    zone = Spots.ZoneOf(zone)
    if not zone or not BORDERS[zone] then return nil end
    return KALIMDOR[zone] and "Kalimdor" or "Eastern Kingdoms"
end

--- How many zones apart `from` and `to` are, crossing borders. Nil when
--- either is not on the map.
function Spots.Hops(from, to)
    from, to = Spots.ZoneOf(from), Spots.ZoneOf(to)
    if not (from and to and BORDERS[from] and BORDERS[to]) then return nil end
    if from == to then return 0 end

    if Spots.Continent(from) ~= Spots.Continent(to) then return OTHER_CONTINENT end

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
    return UNKNOWN_HOPS
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

--- Where you are and your level, either nil when the client will not say.
function Spots:Player()
    local zone = ns.Harvest.Readable(Read(GetRealZoneText))
    if zone == "" then zone = nil end

    local level = ns.Harvest.ReadableNumber(Read(UnitLevel, "player"))
    if level and level <= 0 then level = nil end

    return { zone = zone, level = level }
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

--- Why a spot is where it is, in a few words.
function Spots.DistanceText(hops, zone)
    -- A spot recorded where the zone could not be read (inside an
    -- instance) says nothing, rather than "in many places".
    if type(zone) ~= "string" then return "" end
    if not Spots.ZoneOf(zone) then return "in many places" end
    if hops == nil then return "" end
    if hops == 0 then return "you are here" end
    if hops == 1 then return "next zone over" end
    if hops >= OTHER_CONTINENT then return "other continent" end
    return ("%d zones away"):format(hops)
end

function Spots:Score(spot, player)
    local hops
    if type(spot.zone) ~= "string" then
        -- Where it is was never read: it ranks as far as an unknown place,
        -- never as near as "any coastline".
        hops = nil
    elseif not Spots.ZoneOf(spot.zone) then
        hops = ANYWHERE_HOPS
    elseif player.zone then
        hops = Spots.Hops(player.zone, spot.zone)
    end
    spot.hops = hops

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

    local distance = Spots.DistanceText(spot.hops, spot.zone)
    if distance ~= "" then text = text .. ", " .. distance end
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

    if type(spot.zone) ~= "string" or self:Player().zone ~= spot.zone then return false end

    local mapID = ZoneMapID(spot.zone)
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
        marked and Util.Colored("good", "  (pinned on your map)") or ""))
    return marked
end

--------------------------------------------------------------------------------
-- Command
--------------------------------------------------------------------------------

ns.RegisterCommand("where", "the best places near you to farm an item: /farm where copper ore", function(rest)
    local name = ns.Goals and ns.Goals:ResolveItem(rest) or Util.Trim(rest)
    if not name or name == "" then
        ns.Print("name an item: /farm where copper ore")
        return
    end

    if ns.GoalsUI and ns.GoalsUI.OpenSpots then
        ns.GoalsUI:OpenSpots(name)
        return
    end

    local spots = Spots:For(name)
    if #spots == 0 then
        ns.Print(("no places known for %s yet."):format(name))
        return
    end
    for index, spot in ipairs(spots) do
        ns.PrintRaw(("  %d. %s"):format(index, Spots:Line(spot)))
    end
end)
