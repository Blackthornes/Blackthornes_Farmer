-- Blackthornes Farmer -- Logic/Value.lua
-- What a kill is worth, priced by Blackthornes Tradeskills.
--
-- Tradeskills scans the auction house and keeps a market value per item for
-- your realm and faction. When both addons are loaded, this reads those prices
-- -- read only, straight from Tradeskills in game, nothing copied or written
-- -- and turns a mob's drops into one number: copper per kill.
--
--   per kill = coin per kill
--            + for each item: (how many dropped / kills) x unit price
--
-- A unit price is the auction market value, or what a vendor pays if that is
-- more (nobody sells grey scraps on the auction house for less than the
-- vendor gives). A grey item is only ever its vendor price, whatever the
-- auction house says. Without Tradeskills only the vendor price is known, and
-- the value says so.
--
-- Where the numbers come from, best first:
--   1. your own tally, once a mob has MIN_KILLS kills -- measured amounts and
--      coin, the real thing;
--   2. the database's drop rates for that mob -- one of each item at its
--      rate, no coin, so an underestimate, and labelled as one.
-- Below that there is no value at all. A price times a guessed rate is a
-- guess with a gold sign on it.

local _, ns = ...

local Value = ns.NewModule("Value")

local Util = ns.Util

--------------------------------------------------------------------------------
-- Prices
--------------------------------------------------------------------------------

--- Tradeskills' price module, if it is loaded and looks like we expect.
function Value:Prices()
    local ts = _G.BlackthornesTS
    if type(ts) ~= "table" then return nil end

    local prices = ts.Prices
    if type(prices) ~= "table" or type(prices.GetValue) ~= "function" then return nil end

    return prices
end

function Value:HasAuctionPrices()
    return self:Prices() ~= nil
end

--- What a vendor pays for one, from the client's item info.
function Value:VendorPrice(itemID)
    local getInfo = (C_Item and C_Item.GetItemInfo) or _G.GetItemInfo
    if type(getInfo) ~= "function" then return nil end

    local ok, sellPrice = pcall(function()
        return select(11, getInfo(itemID))
    end)
    if not ok then return nil end

    local copper = ns.Harvest.ReadableNumber(sellPrice)
    if copper and copper > 0 then return copper end

    return nil
end

--- Tradeskills' market value for one, in copper.
function Value:AuctionPrice(itemID)
    local prices = self:Prices()
    if not prices then return nil end

    local ok, copper = pcall(prices.GetValue, prices, itemID)
    if not ok then return nil end

    copper = ns.Harvest.ReadableNumber(copper)
    if copper and copper > 0 then return copper end

    return nil
end

--- True for a grey (poor quality) item: from the client's item info, else
--- from the colour of a loot link we have seen for it.
function Value:IsPoor(itemID)
    local getInfo = (C_Item and C_Item.GetItemInfo) or _G.GetItemInfo
    if type(getInfo) == "function" then
        local ok, quality = pcall(function()
            return select(3, getInfo(itemID))
        end)
        quality = ok and ns.Harvest.ReadableNumber(quality) or nil
        if quality then return quality == 0 end
    end

    -- Item info not cached yet: a grey loot link says the same thing.
    local grey = ns.Tracker and ns.Tracker.QUALITY and ns.Tracker.QUALITY[0]
    if grey and ns.Tracker.Looks then
        for _, look in pairs(ns.Tracker:Looks()) do
            if type(look) == "table" and look.id == itemID and look.color == grey then
                return true
            end
        end
    end

    return false
end

--- One unit's worth and where the number came from ("auction" or "vendor").
-- A grey item is only ever worth what a vendor pays (Trent, 2026-09-25): the
-- auction house is no price for vendor trash, whatever a scan once saw.
function Value:UnitPrice(itemID)
    if not itemID then return nil end

    local vendor = self:VendorPrice(itemID)
    if self:IsPoor(itemID) then
        if vendor then return vendor, "vendor" end
        return nil
    end

    local auction = self:AuctionPrice(itemID)

    if auction and (not vendor or auction >= vendor) then return auction, "auction" end
    if vendor then return vendor, "vendor" end

    return nil
end

--- The item id for a name: from the loot link, else the database.
function Value:ItemID(name)
    local look = ns.Tracker and ns.Tracker:LookOf(name)
    if look and look.id then return look.id end

    local item = ns.DB and ns.DB:GetItem(name)
    if item and item.id then return item.id end

    return nil
end

--------------------------------------------------------------------------------
-- A mob's worth
--------------------------------------------------------------------------------

--- Copper per kill from your own tally, or nil below MIN_KILLS.
-- Returns value, details: { basis = "tally", kills, copper, priced = {...},
-- unpriced = {...} } where each priced entry is { name, perKill, unit, from }.
function Value:FromTally(mobName)
    local Tracker = ns.Tracker
    local mob = Tracker and Tracker:Store()[mobName]
    if type(mob) ~= "table" then return nil end

    local kills = tonumber(mob.kills) or 0
    if kills < Tracker.MIN_KILLS then return nil end

    local details = { basis = "tally", kills = kills, priced = {}, unpriced = {} }

    -- Coin over the kills that recorded it; items as how often each drops
    -- (every kill counts) times how many come at once (from the kills that
    -- recorded amounts). Old tallies with neither get no coin and one each.
    local coin = Tracker:CoinPerKill(mobName) or 0
    local total = coin

    details.coin = coin

    for name, corpses in pairs(type(mob.items) == "table" and mob.items or {}) do
        local perCorpse = Tracker:StackSize(mobName, name)
        local unit, from = self:UnitPrice(self:ItemID(name))

        if unit then
            local perKill = (tonumber(corpses) or 0) / kills * perCorpse * unit
            total = total + perKill
            details.priced[#details.priced + 1] =
                { name = name, perKill = perKill, unit = unit, from = from }
        else
            details.unpriced[#details.unpriced + 1] = name
        end
    end

    -- Nothing priced and no coin is not "worth nothing": it is unknown.
    if #details.priced == 0 and coin == 0 then return nil end

    table.sort(details.priced, function(a, b) return a.perKill > b.perKill end)
    table.sort(details.unpriced)

    return total, details
end

--- Copper per kill from the database's drop rates for this mob, or nil when
--- none of its drops has both a rate and a price.
function Value:FromDatabase(mobName)
    if not (ns.DB and mobName) then return nil end

    local details = { basis = "database", priced = {}, unpriced = {}, coin = 0 }
    local total, seen = 0, {}

    for item in ns.DB:Iterate() do
        for _, source in ipairs(item.sources or {}) do
            if source.name == mobName and source.chance and not seen[item.name] then
                seen[item.name] = true

                local unit, from = self:UnitPrice(item.id or self:ItemID(item.name))

                if unit then
                    local perKill = source.chance / 100 * unit
                    total = total + perKill
                    details.priced[#details.priced + 1] =
                        { name = item.name, perKill = perKill, unit = unit, from = from }
                else
                    details.unpriced[#details.unpriced + 1] = item.name
                end
            end
        end
    end

    if #details.priced == 0 then return nil end

    table.sort(details.priced, function(a, b) return a.perKill > b.perKill end)
    table.sort(details.unpriced)

    return total, details
end

--- The best value we have for a mob: your tally first, then the database.
function Value:ForMob(mobName)
    local value, details = self:FromTally(mobName)
    if value then return value, details end

    return self:FromDatabase(mobName)
end

--------------------------------------------------------------------------------
-- This session's haul
--------------------------------------------------------------------------------

--- What everything gathered this session is worth, in copper: the coin off
--- your kills, plus every item looted, fished up or gathered times its unit
--- price.
-- Returns total, details { coin, priced = count, unpriced = { names } }, or
-- nil when nothing has been gathered yet. Items with no price are left out of
-- the total and listed, never guessed.
function Value:Session()
    local Tracker, Fishing, Gathering = ns.Tracker, ns.Fishing, ns.Gathering

    local counts = {}
    for name, count in pairs(Tracker and Tracker.sessionLoot or {}) do
        counts[name] = (counts[name] or 0) + count
    end
    for name, count in pairs(Fishing and Fishing.sessionCatch or {}) do
        counts[name] = (counts[name] or 0) + count
    end
    for name, count in pairs(Gathering and Gathering.sessionItems or {}) do
        counts[name] = (counts[name] or 0) + count
    end

    local coin = Tracker and tonumber(Tracker.sessionCopper) or 0
    local details = { coin = coin, priced = 0, unpriced = {} }
    local total = coin

    for name, count in pairs(counts) do
        local unit = self:UnitPrice(self:ItemID(name))
        if unit then
            total = total + count * unit
            details.priced = details.priced + 1
        else
            details.unpriced[#details.unpriced + 1] = name
        end
    end

    if details.priced == 0 and coin == 0 and #details.unpriced == 0 then return nil end

    table.sort(details.unpriced)

    return total, details
end

--------------------------------------------------------------------------------
-- Showing it
--------------------------------------------------------------------------------

--- "1g 2s 3c", dropping empty units; "0c" for nothing.
function Value.Money(copper)
    copper = math.floor((tonumber(copper) or 0) + 0.5)

    local gold = math.floor(copper / 10000)
    local silver = math.floor(copper % 10000 / 100)
    local rest = copper % 100

    local parts = {}
    if gold > 0 then parts[#parts + 1] = gold .. "g" end
    if silver > 0 then parts[#parts + 1] = silver .. "s" end

    -- Past a gold, copper is noise: "1g 3c" said it and "1g 2s 3c" did not.
    if gold == 0 and (rest > 0 or #parts == 0) then parts[#parts + 1] = rest .. "c" end

    return table.concat(parts, " ")
end

--- What the prices are, in a few words, for the end of a value line.
function Value:PriceNote(details)
    local auction = false
    for _, entry in ipairs(details.priced) do
        if entry.from == "auction" then auction = true end
    end

    local note = auction and "auction prices" or "vendor prices"
    if details.basis == "database" then note = note .. ", database rates" end

    return note
end

ns.RegisterCommand("value", "what a mob is worth per kill, from Tradeskills prices", function(rest)
    local wanted = Util.Trim(rest or "")
    local mobName = ns.Tracker:ResolveMob(wanted) or (wanted ~= "" and wanted) or nil

    if not mobName then
        ns.Print("name a mob: /farm value <mob>.")
        return
    end

    local value, details = Value:ForMob(mobName)

    if not value then
        local summary = ns.Tracker:Summary(mobName)
        if summary and not summary.rated then
            ns.Print(("%s: %d more kills before it has a value."):format(mobName, summary.needed))
        else
            ns.Print(("%s: no drop rates with prices to value it by yet."):format(mobName))
        end
        return
    end

    ns.Print(("%s: about %s a kill %s"):format(
        Util.Colored("accent", mobName),
        Util.Colored("good", Value.Money(value)),
        Util.Colored("muted", ("(%s)"):format(Value:PriceNote(details)))))

    if details.coin and details.coin > 0 then
        ns.PrintRaw(("  coin  %s"):format(Util.Colored("muted", Value.Money(details.coin))))
    end

    for index = 1, math.min(#details.priced, 6) do
        local entry = details.priced[index]
        ns.PrintRaw(("  %s  %s"):format(entry.name,
            Util.Colored("muted", Value.Money(entry.perKill))))
    end

    if #details.unpriced > 0 then
        ns.PrintRaw(Util.Colored("muted", ("  no price yet: %s"):format(
            table.concat(details.unpriced, ", "))))
    end

    if not Value:HasAuctionPrices() then
        ns.PrintRaw(Util.Colored("muted",
            "  Blackthornes Tradeskills is not loaded, so these are vendor prices."))
    end
end)
