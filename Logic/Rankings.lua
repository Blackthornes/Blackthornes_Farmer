-- Blackthornes Farmer -- Logic/Rankings.lua
-- Every mob we can put a value on, best first: what is worth farming?
--
-- The worth of a kill is Value:ForMob's number, nothing new. What this adds is
-- the ordering, and keeping two kinds of number apart that must never be
-- ranked against each other:
--
--   measured   your own tally, MIN_KILLS kills or more, coin included;
--   estimate   the database's drop rates, one of each item, no coin.
--
-- An estimate leaves coin out and assumes one of each drop, so it runs low; put
-- in one list with measured values it would sink below mobs that are worth
-- less. So each is ranked on its own, measured first.
--
-- A mob you have killed but not enough times to value, and with no estimate
-- either, is not ranked at all. It is listed with how many kills it still
-- needs, since that is the way onto the board.

local _, ns = ...
local L = ns.L

local Rankings = ns.NewModule("Rankings")

-- Kinds whose `name` is a creature. A node or a school has no kill to value.
local CREATURE_KINDS = { mob = true, skinning = true }

--- Every mob name the database gives a drop rate for.
local function RatedMobs(names)
    for name, entries in pairs(ns.DB:ByName()) do
        for _, entry in ipairs(entries) do
            local source = entry.source
            if source.chance and CREATURE_KINDS[source.kind or "mob"] then
                names[name] = true
                break
            end
        end
    end
end

--- Where the database puts a mob and at what level: the lowest band first,
--- as the search lists it. Nil when the database does not know the mob.
function Rankings:Spot(mobName)
    local best

    for _, entry in ipairs(ns.DB:ByName()[mobName] or {}) do
        local source = entry.source
        if CREATURE_KINDS[source.kind or "mob"]
            and (not best or (source.minLevel or 0) < (best.minLevel or 0)) then
            best = source
        end
    end

    return best
end

--------------------------------------------------------------------------------
-- Outside dungeons only
--------------------------------------------------------------------------------

-- The owner asked (2026-10-14) for a tick box on Rankings that leaves out mobs
-- found only in dungeons. Off unless ticked, kept in `rankingsOutside`
-- (account wide, never rename it). The rank-up pop-up and the top farm
-- alert after an auction scan rank the same board, so they follow it too.

--- Moves whenever the tick box does, so what was laid out for the other
--- answer is laid out again (RankUp).
Rankings.outsideVersion = 0

function Rankings.OutsideOnly()
    return ns.db ~= nil and ns.db.rankingsOutside == true
end

function Rankings:SetOutsideOnly(on)
    if not ns.db then return end
    on = on and true or false
    if (ns.db.rankingsOutside == true) == on then return end
    ns.db.rankingsOutside = on
    self.outsideVersion = self.outsideVersion + 1
    -- The rank-up order sees the version move and is laid out again.
    if ns.RankingsUI then ns.RankingsUI:Refresh() end
end

--- The zone part of a kill's place, "The Sepulcher, Silverpine Forest":
--- the zone the client named (GetRealZoneText), which inside a dungeon is
--- the dungeon.
local function PlaceZone(place)
    if type(place) ~= "string" then return nil end
    return place:match(".*, (.+)$") or place
end

--- Is a database row for a mob inside a dungeon? A row from Classic's data
--- names the dungeon as its subzone ("The Deadmines" in Westfall). A row
--- recorded in game has the dungeon as its zone; its subzone is the open
--- world's when the zone is not (Ruins of Lordaeron in Tirisfal Glades).
local function SourceInside(source)
    local Spots = ns.Spots
    if Spots.IsInstance(source.zone) then return true end
    return (source.provenance or "classic") == "classic" and Spots.IsInstance(source.location)
end

--- Is `mobName` found only in dungeons and raids? Told by where your kills
--- of it were (every kill with a place inside one), else by where the
--- database puts it (every place inside one). A mob neither tells about,
--- killed before places were kept and not in the data, counts as outside.
function Rankings:InDungeon(mobName)
    local Spots = ns.Spots
    local places = ns.Tracker:Places(mobName)
    if #places > 0 then
        for _, place in ipairs(places) do
            if not Spots.IsInstance(PlaceZone(place.name)) then return false end
        end
        return true
    end

    local any = false
    for _, entry in ipairs(ns.DB:ByName()[mobName] or {}) do
        local source = entry.source
        if CREATURE_KINDS[source.kind or "mob"] then
            if not SourceInside(source) then return false end
            any = true
        end
    end
    return any
end

--- Is `mobName` left off the board? Hidden, or in a dungeon while the tick
--- box says outside only.
function Rankings:LeftOut(mobName)
    if ns.DB:IsHiddenSource(mobName) then return true end
    return self.OutsideOnly() and self:InDungeon(mobName)
end

--- One entry for a mob, or nil when it is on no list.
function Rankings:Entry(mobName)
    local value, details = ns.Value:ForMob(mobName)
    local summary = ns.Tracker:Summary(mobName)
    local spot = self:Spot(mobName)

    local entry = {
        mob = mobName,
        value = value,
        details = details,
        kills = summary and summary.kills or 0,
        needed = summary and summary.needed or 0,
        spot = spot,
        level = spot and ns.Search:LevelText(spot) or nil,
    }

    -- Where you farm it beats where the database says it lives.
    local places = summary and summary.places
    if places and places[1] then
        entry.where = places[1].name
    elseif spot then
        local landmark = ns.DB:WhereText(spot)
        local zone = ns.Spots.Show(spot.zone)
        entry.where = landmark and (zone .. ", " .. landmark) or zone
    end

    if value then
        entry.group = details.basis == "tally" and "measured" or "estimate"
        entry.best = details.priced[1]
    elseif summary and summary.kills > 0 then
        -- Enough kills but nothing priced: it waits on prices, not kills.
        entry.group = "pending"
        entry.unpriced = summary.rated
    else
        return nil
    end

    return entry
end

--- The board: { measured = {...}, estimate = {...}, pending = {...} }, each
--- entry { mob, value, details, kills, needed, where, level, best, rank }.
-- Measured and estimates are ranked by worth per kill; pending by how close
-- each is to MIN_KILLS.
function Rankings:Build()
    local names = {}

    for name in pairs(ns.Tracker:Store()) do
        if type(name) == "string" then names[name] = true end
    end
    RatedMobs(names)

    local board = { measured = {}, estimate = {}, pending = {} }

    for name in pairs(names) do
        -- A mob on the hide list is not ranked (DB:IsHiddenSource), nor a
        -- dungeon's with "Outside dungeons only" ticked.
        local entry = not self:LeftOut(name) and self:Entry(name)
        if entry then
            local list = board[entry.group]
            list[#list + 1] = entry
        end
    end

    local function ByValue(a, b)
        if a.value ~= b.value then return a.value > b.value end
        return a.mob < b.mob
    end

    table.sort(board.measured, ByValue)
    table.sort(board.estimate, ByValue)
    table.sort(board.pending, function(a, b)
        if a.needed ~= b.needed then return a.needed < b.needed end
        return a.mob < b.mob
    end)

    for _, group in ipairs({ "measured", "estimate" }) do
        for rank, entry in ipairs(board[group]) do
            entry.rank = rank
        end
    end

    return board
end

ns.RegisterCommand("rankings", L["mobs ranked by what a kill is worth, or only those outside dungeons"], function(arg)
    local word, value = (arg or ""):lower():match("^(%S*)%s*(%S*)")
    if word == "outside" then
        if value == "on" or value == "off" then
            Rankings:SetOutsideOnly(value == "on")
        else
            Rankings:SetOutsideOnly(not Rankings.OutsideOnly())
        end
        ns.Print(Rankings.OutsideOnly() and L["Rankings show only mobs outside dungeons."]
            or L["Rankings show mobs from dungeons too."])
        if ns.SettingsUI then ns.SettingsUI:Refresh() end
        return
    end
    ns.UI:Show()
    ns.UI:ShowTab("rankings")
end)

-- The short form, kept out of the help list so it is not there twice.
ns.commands.rank = ns.commands.rankings
