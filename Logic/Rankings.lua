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

local Rankings = ns.NewModule("Rankings")

-- Kinds whose `name` is a creature. A node or a school has no kill to value.
local CREATURE_KINDS = { mob = true, skinning = true }

--- Every mob name the database gives a drop rate for.
local function RatedMobs(names)
    for item in ns.DB:Iterate() do
        for _, source in ipairs(item.sources or {}) do
            if source.name and source.chance and CREATURE_KINDS[source.kind or "mob"] then
                names[source.name] = true
            end
        end
    end
end

--- Where the database puts a mob and at what level: the lowest band first,
--- as the search lists it. Nil when the database does not know the mob.
function Rankings:Spot(mobName)
    local best

    for item in ns.DB:Iterate() do
        for _, source in ipairs(item.sources or {}) do
            if source.name == mobName and CREATURE_KINDS[source.kind or "mob"]
                and (not best or (source.minLevel or 0) < (best.minLevel or 0)) then
                best = source
            end
        end
    end

    return best
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
        entry.where = landmark and (spot.zone .. ", " .. landmark) or spot.zone
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
        local entry = self:Entry(name)
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

ns.RegisterCommand("rankings", "mobs ranked by what a kill is worth", function()
    ns.UI:Show()
    ns.UI:ShowTab("rankings")
end)

-- The short form, kept out of the help list so it is not there twice.
ns.commands.rank = ns.commands.rankings
