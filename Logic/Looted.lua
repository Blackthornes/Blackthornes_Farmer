-- Blackthornes Farmer -- Logic/Looted.lua
-- Has the player looted, gathered or fished this item themselves?
--
-- Asked by Blackthornes Tradeskills (2026-10-16): its Profit by method puts
-- an auction sale with no known cost under "Other sales". An item you got
-- from your own play goes under "Farmed" instead. Tradeskills calls,
-- inside a pcall, read only:
--
--   _G.BlackthornesFarmer.Looted:Has(item)   -- item ID or name; true or false
--
-- Read from the player's own records only: the loot harvest
-- (`Harvest.records`), `gathering.nodes` and `fishing.spots`. Never the
-- shipped data and never the guild's (`guildDrops`). Nothing is saved.
-- The lookup is laid out once and again only when a corpse, a gather or a
-- cast is recorded, at most every `GAP` seconds.

local _, ns = ...

local Looted = ns.NewModule("Looted")

Looted.GAP = 30

local built

local function Now()
    return type(GetTime) == "function" and GetTime() or 0
end

local function Version()
    return ("%d:%d:%d"):format(
        ns.Harvest and tonumber(ns.Harvest.changes) or 0,
        ns.Gathering and tonumber(ns.Gathering.clock) or 0,
        ns.Fishing and tonumber(ns.Fishing.clock) or 0)
end

local function Note(found, name, entry)
    if type(name) == "string" and name ~= "" then found.names[name:lower()] = true end
    local id = type(entry) == "table" and tonumber(entry.id)
    if id then found.ids[id] = true end
end

--- The lookup: { names = { [lower name] = true }, ids = { [id] = true } }.
function Looted:Build()
    local key = Version()
    if built and (built.key == key or Now() - built.at < self.GAP) then return built end

    local found = { names = {}, ids = {}, key = key, at = Now() }
    local Harvest = ns.Harvest

    for _, record in pairs(Harvest and type(Harvest.records) == "table" and Harvest.records or {}) do
        if type(record) == "table" and type(record.items) == "table" then
            -- Random suffixes count as their item, and under their own name.
            for name, entry in pairs(record.items) do Note(found, name, entry) end
            local ok, grouped = pcall(function() return Harvest.GroupedItems and Harvest:GroupedItems(record) end)
            if ok and type(grouped) == "table" then
                for name, entry in pairs(grouped) do Note(found, name, entry) end
            end
        end
    end

    local gathering = ns.db and type(ns.db.gathering) == "table" and ns.db.gathering.nodes
    for _, node in pairs(type(gathering) == "table" and gathering or {}) do
        if type(node) == "table" and type(node.items) == "table" then
            for name, entry in pairs(node.items) do Note(found, name, entry) end
        end
    end

    local fishing = ns.db and type(ns.db.fishing) == "table" and ns.db.fishing.spots
    for _, spot in pairs(type(fishing) == "table" and fishing or {}) do
        if type(spot) == "table" and type(spot.items) == "table" then
            for name, entry in pairs(spot.items) do Note(found, name, entry) end
        end
    end

    built = found
    return found
end

function Looted:Forget()
    built = nil
end

local function ClientName(id)
    if type(C_Item) == "table" and type(C_Item.GetItemNameByID) == "function" then
        local ok, name = pcall(C_Item.GetItemNameByID, id)
        if ok and type(name) == "string" and name ~= "" then return name end
    end
    return nil
end

--- True when the player's own loot, gathering or fishing has the item.
--- Never raises.
function Looted:Has(item)
    local ok, answer = pcall(function()
        local found = self:Build()
        local id = tonumber(item)
        if id then
            if found.ids[id] then return true end
            local name = ClientName(id)
            return type(name) == "string" and found.names[name:lower()] == true
        end
        return type(item) == "string" and found.names[item:lower()] == true
    end)
    return ok and answer == true
end
