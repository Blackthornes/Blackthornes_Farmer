-- Blackthornes Farmer -- Logic/DisenchantFarm.lua
-- Which mobs to farm for an enchanting material (the owner said build it,
-- 2026-10-16, after a player asked where to get Large Radiant Shards).
--
-- Tradeskills' Disenchanting tab has a Find a material view. It knows what
-- each item breaks into, and Farmer knows what your kills dropped, so its
-- "Farm and break" row asks here, inside a pcall and read only:
--
--     _G.BlackthornesFarmer.DisenchantFarm:Best(gives, max)
--       -- gives(itemID): how many of the material breaking one gives on
--       --   average (0 or nil for none); asked once per item, in a pcall
--       -- { { mob, zone, shownZone, kills, perKill, seconds, perHour,
--       --     items = { { id, name, corpses } } } }, best first, at most max
--     _G.BlackthornesFarmer.DisenchantFarm:DroppedBy(itemID)
--       -- the mob that dropped it most for you, or nil
--     _G.BlackthornesFarmer.DisenchantFarm:Show(mob)
--       -- opens the mob's loot table; true when it opened
--
-- Only your own loot records (Logic/Harvest.lua), never the shipped data or
-- the guild's, and a mob only once MIN_SAMPLE corpses are behind it. The
-- seconds a kill takes are the mob's own pace (Stats:SecondsPerKill), never
-- your average. Hidden mobs and items are left out. Nothing is written.
--
-- It walks every record once a call, so Tradeskills asks only while its view
-- shows and keeps the answer a while.

local _, ns = ...

local DisenchantFarm = ns.NewModule("DisenchantFarm")

-- Corpses of a mob before it is listed.
DisenchantFarm.MIN_SAMPLE = 20
-- Listed at most, when the caller gives no number.
DisenchantFarm.MOST = 5

local function Number(value)
    return type(value) == "number" and value or tonumber(value)
end

local function HiddenSource(name)
    local DB = ns.DB
    return DB and DB.IsHiddenSource and DB:IsHiddenSource(name) or false
end

local function HiddenItem(name)
    local DB = ns.DB
    return DB and DB.IsHiddenItem and DB:IsHiddenItem(name) or false
end

--- An item's ID, from the record or the client by name.
local function ItemID(entry, name)
    local id = Number(entry.id)
    if id then return id end
    if C_Item and C_Item.GetItemInfoInstant then
        local ok, found = pcall(C_Item.GetItemInfoInstant, name)
        if ok and type(found) == "number" then return found end
    end
    if type(GetItemInfoInstant) == "function" then
        local ok, found = pcall(GetItemInfoInstant, name)
        if ok and type(found) == "number" then return found end
    end
    return nil
end

--- Every mob of yours, its records put together by name and zone:
--- { [key] = { mob, zone, corpses, items = { [id] = { id, name, corpses } } } }
local function Mobs()
    local Harvest = ns.Harvest
    local mobs = {}
    if not (Harvest and type(Harvest.records) == "table") then return mobs end

    for _, record in pairs(Harvest.records) do
        local mob = type(record) == "table" and record.mob
        local corpses = type(record) == "table" and Number(record.corpses) or 0
        if type(mob) == "string" and corpses > 0 and not HiddenSource(mob) then
            local zone = type(record.zone) == "string" and record.zone or ""
            local key = mob .. "\t" .. zone
            local into = mobs[key]
            if not into then
                into = { mob = mob, zone = zone, corpses = 0, items = {} }
                mobs[key] = into
            end
            into.corpses = into.corpses + corpses

            local items = Harvest.GroupedItems and Harvest:GroupedItems(record) or record.items
            for name, entry in pairs(type(items) == "table" and items or {}) do
                if type(entry) == "table" and type(name) == "string" and not HiddenItem(name) then
                    local id = ItemID(entry, name)
                    if id then
                        local item = into.items[id]
                        if not item then
                            item = { id = id, name = name, corpses = 0 }
                            into.items[id] = item
                        end
                        item.corpses = item.corpses + (Number(entry.corpses) or 0)
                    end
                end
            end
        end
    end

    return mobs
end

--- The mobs that give the most of a material a kill, from what they dropped
--- for you and what `gives` says breaking each item gives. Never raises.
function DisenchantFarm:Best(gives, max)
    if type(gives) ~= "function" then return {} end
    max = Number(max) or DisenchantFarm.MOST

    local ok, list = pcall(function()
        local asked = {}
        local function Gives(id)
            local known = asked[id]
            if known == nil then
                local fine, amount = pcall(gives, id)
                known = fine and Number(amount) or 0
                if known < 0 then known = 0 end
                asked[id] = known
            end
            return known
        end

        local found = {}
        for _, mob in pairs(Mobs()) do
            if mob.corpses >= DisenchantFarm.MIN_SAMPLE then
                local total, items = 0, {}
                for id, item in pairs(mob.items) do
                    local each = item.corpses > 0 and Gives(id) or 0
                    if each > 0 then
                        total = total + item.corpses * each
                        items[#items + 1] = { id = id, name = item.name, corpses = item.corpses, gives = each }
                    end
                end

                if total > 0 then
                    table.sort(items, function(a, b)
                        local left, right = a.corpses * a.gives, b.corpses * b.gives
                        if left ~= right then return left > right end
                        return a.name < b.name
                    end)
                    for index = #items, 4, -1 do items[index] = nil end
                    for _, item in ipairs(items) do item.gives = nil end

                    local perKill = total / mob.corpses
                    local seconds, own
                    if ns.Stats and ns.Stats.SecondsPerKill then
                        seconds, own = ns.Stats:SecondsPerKill(mob.mob)
                    end
                    if not own then seconds = nil end

                    local zone = mob.zone ~= "" and mob.zone or nil
                    local shownZone = zone
                    if zone and ns.Spots and ns.Spots.Show then
                        local fine, shown = pcall(ns.Spots.Show, zone)
                        if fine and type(shown) == "string" then shownZone = shown end
                    end

                    found[#found + 1] = {
                        mob = mob.mob,
                        zone = zone,
                        shownZone = shownZone,
                        kills = mob.corpses,
                        perKill = perKill,
                        seconds = seconds,
                        perHour = seconds and seconds > 0 and perKill * 3600 / seconds or nil,
                        items = items,
                    }
                end
            end
        end

        table.sort(found, function(a, b)
            if a.perKill ~= b.perKill then return a.perKill > b.perKill end
            if a.kills ~= b.kills then return a.kills > b.kills end
            return a.mob < b.mob
        end)
        for index = #found, max + 1, -1 do found[index] = nil end
        return found
    end)

    if not ok or type(list) ~= "table" then return {} end
    return list
end

--- The mob that dropped this item most for you, or nil. Never raises.
function DisenchantFarm:DroppedBy(itemID)
    itemID = Number(itemID)
    if not itemID then return nil end

    local ok, mob = pcall(function()
        local best, most
        for _, entry in pairs(Mobs()) do
            local item = entry.items[itemID]
            if item and item.corpses > 0 and (not most or item.corpses > most) then
                best, most = entry.mob, item.corpses
            end
        end
        return best
    end)
    return ok and mob or nil
end

--- Open a mob's loot table. Never raises.
function DisenchantFarm:Show(mob)
    local LootTableUI = ns.LootTableUI
    if type(mob) ~= "string" or not (LootTableUI and LootTableUI.Show) then return false end
    local ok, shown = pcall(LootTableUI.Show, LootTableUI, mob)
    return ok and shown == true
end
