-- Blackthornes Farmer -- Logic/GatherToCap.lua
-- Gather to cap, on the Grind tab's Ore, Herbs and Leather views (the owner
-- approved the mockup, 2026-10-20): a path from your skill to the cap, one
-- stop per node (or, for Skinning, per band of mob levels), each with the
-- best zone for it and the skill it covers.
--
-- A stop runs from its node's skill to the next stop's (the last to TOP).
-- The data's skill for a node wins over the ladder's below. The zone for a
-- stop is the one where you mapped the most spots of that node, else the
-- data's zone nearest your level among those you can reach, else the
-- lowest. "About N more gathers" uses Classic's skill-up chance: a node
-- gives a point for sure until you are SURE_FOR points over the skill it
-- needs, then the chance falls in a straight line to nothing at GREY_AT
-- over it (Chance, Gathers).
--
-- Only your own play and the shipped data are read: your mapped spots
-- (gathering.spots), your gathering pace (gathering.pace) and your skins
-- (skinLog); guild data never reaches it. Hidden nodes and items are left
-- out. Nothing is saved, and nothing runs on a timer: the Grind tab asks
-- when it draws, and the path is laid out again only when your skill, your
-- cap, your level, your spots or gathers, or the hide list move (Key).

local _, ns = ...
local L = ns.L

local GatherToCap = ns.NewModule("GatherToCap")

GatherToCap.TOP = 300
-- A point for sure until this far over the node's skill...
GatherToCap.SURE_FOR = 25
-- ...then none at this far over it.
GatherToCap.GREY_AT = 100
-- The chance never counts as lower than this, so an estimate stays finite.
GatherToCap.MIN_CHANCE = 0.05
-- A zone this many levels over yours is still in reach.
GatherToCap.REACH = 5
-- A typical hour of gathering, for worth where you have no pace of your
-- own: gathers an hour, and how many of the main item each gives.
GatherToCap.TYPICAL_GATHERS = 40
GatherToCap.TYPICAL_YIELD = 2
-- A goal asks for at least this many.
GatherToCap.MIN_GOAL = 20

-- The ranks you train, the skill each is trained at and the cap it gives.
GatherToCap.RANKS = {
    { key = "Apprentice", at = 1, cap = 75 },
    { key = "Journeyman", at = 50, cap = 150 },
    { key = "Expert", at = 125, cap = 225 },
    { key = "Artisan", at = 200, cap = 300 },
}

-- Classic's ladders: each node, the skill it needs and what it gives most.
-- Silver, gold and truesilver are left out: too rare to level on.
GatherToCap.LADDERS = {
    Mining = {
        { node = "Copper Vein", item = "Copper Ore", skill = 1 },
        { node = "Tin Vein", item = "Tin Ore", skill = 65 },
        { node = "Iron Deposit", item = "Iron Ore", skill = 125 },
        { node = "Mithril Deposit", item = "Mithril Ore", skill = 175 },
        { node = "Small Thorium Vein", item = "Thorium Ore", skill = 245 },
        { node = "Rich Thorium Vein", item = "Thorium Ore", skill = 275 },
    },
    Herbalism = {
        { node = "Peacebloom", item = "Peacebloom", skill = 1 },
        { node = "Mageroyal", item = "Mageroyal", skill = 50 },
        { node = "Briarthorn", item = "Briarthorn", skill = 70 },
        { node = "Bruiseweed", item = "Bruiseweed", skill = 100 },
        { node = "Kingsblood", item = "Kingsblood", skill = 125 },
        { node = "Liferoot", item = "Liferoot", skill = 150 },
        { node = "Fadeleaf", item = "Fadeleaf", skill = 160 },
        { node = "Goldthorn", item = "Goldthorn", skill = 170 },
        { node = "Khadgar's Whisker", item = "Khadgar's Whisker", skill = 185 },
        { node = "Purple Lotus", item = "Purple Lotus", skill = 210 },
        { node = "Sungrass", item = "Sungrass", skill = 230 },
        { node = "Golden Sansam", item = "Golden Sansam", skill = 260 },
        { node = "Dreamfoil", item = "Dreamfoil", skill = 270 },
        { node = "Mountain Silversage", item = "Mountain Silversage", skill = 280 },
    },
    -- Skinning goes by the level of the beasts (Grinding.SkinSkill): a stop
    -- a band of levels, with the leather it gives most.
    Skinning = {
        { skill = 1, low = 1, high = 15, item = "Light Leather" },
        { skill = 50, low = 15, high = 20, item = "Light Leather" },
        { skill = 100, low = 20, high = 30, item = "Medium Leather" },
        { skill = 150, low = 30, high = 40, item = "Heavy Leather" },
        { skill = 200, low = 40, high = 50, item = "Thick Leather" },
        { skill = 250, low = 50, high = 60, item = "Rugged Leather" },
    },
}

-- The Grind tab's views, by its gives key.
GatherToCap.VIEWS = {
    ore = { skill = "Mining", gathering = "ore", data = "ore" },
    herbs = { skill = "Herbalism", gathering = "herb", data = "herbs" },
    skinning = { skill = "Skinning" },
}

local function Number(value)
    return ns.Harvest and ns.Harvest.ReadableNumber(value) or tonumber(value)
end

--------------------------------------------------------------------------------
-- Your skill
--------------------------------------------------------------------------------

--- Your skill and cap in `english` ("Mining"), or nil when you lack it or
--- the client will not say. Read in a pcall, every call.
function GatherToCap.ReadSkill(english)
    local function Match(name)
        name = ns.Harvest.Readable(name)
        return name and ns.Gathering.SkillOf(name, { english }) == english
    end

    if type(GetProfessions) == "function" and type(GetProfessionInfo) == "function" then
        local ok, first, second = pcall(GetProfessions)
        if ok then
            for _, index in ipairs({ Number(first) or false, Number(second) or false }) do
                if index then
                    local got, name, _, rank, most = pcall(GetProfessionInfo, index)
                    if got and Match(name) then
                        local skill = Number(rank)
                        if skill then return skill, Number(most) end
                    end
                end
            end
        end
    end

    if type(GetNumSkillLines) == "function" and type(GetSkillLineInfo) == "function" then
        local ok, lines = pcall(GetNumSkillLines)
        for index = 1, ok and Number(lines) or 0 do
            local got, name, header, _, rank, _, _, most = pcall(GetSkillLineInfo, index)
            if got and not header and Match(name) then
                local skill = Number(rank)
                if skill then return skill, Number(most) end
            end
        end
    end
    return nil
end

--- The rank you train next for a cap over `most`, or nil at the top.
function GatherToCap.NextRank(most)
    if not most then return nil end
    for _, rank in ipairs(GatherToCap.RANKS) do
        if rank.cap > most then return rank end
    end
    return nil
end

--- The rank's name as players read it.
function GatherToCap.RankLabel(key)
    local words = { Apprentice = L["Apprentice"], Journeyman = L["Journeyman"], Expert = L["Expert"],
        Artisan = L["Artisan"] }
    return words[key] or key
end

--- The profession's name as players read it.
function GatherToCap.SkillLabel(english)
    local words = { Mining = L["Mining"], Herbalism = L["Herbalism"], Skinning = L["Skinning"] }
    return words[english] or english
end

--------------------------------------------------------------------------------
-- How many gathers
--------------------------------------------------------------------------------

--- The chance one gather at `skill` of a node needing `need` gives a point.
function GatherToCap.Chance(skill, need)
    local over = skill - (need or 1)
    if over < GatherToCap.SURE_FOR then return 1 end
    local chance = (GatherToCap.GREY_AT - over) / (GatherToCap.GREY_AT - GatherToCap.SURE_FOR)
    return math.max(GatherToCap.MIN_CHANCE, chance)
end

--- About how many gathers of a node needing `need` take you from `from` to
--- `to`: one over the chance, for each point.
function GatherToCap.Gathers(from, to, need)
    local total = 0
    for skill = from, to - 1 do total = total + 1 / GatherToCap.Chance(skill, need) end
    return math.ceil(total - 1e-9)
end

--------------------------------------------------------------------------------
-- The stops
--------------------------------------------------------------------------------

local function ItemID(name)
    local item = name and ns.DB:GetItem(name)
    return item and item.id or nil
end

local function Price(id)
    if not id then return nil end
    local ok, price = pcall(ns.Value.UnitPrice, ns.Value, id)
    if ok and type(price) == "number" and price > 0 then return price end
    return nil
end

--- Your mapped spots of `kind` as { ["zone|node"] = { count, list } }.
local function OwnSpots(kind)
    local found = {}
    local gathering = ns.db and type(ns.db.gathering) == "table" and ns.db.gathering
    local spots = gathering and type(gathering.spots) == "table" and gathering.spots or {}
    for _, spot in ipairs(spots) do
        local zone = type(spot) == "table" and ns.Spots.MAP_ZONES[spot.map]
        if zone and type(spot.node) == "string" and (spot.kind == nil or spot.kind == kind) then
            local key = ns.GrindGather.Key(zone, spot.node)
            local entry = found[key]
            if not entry then
                entry = { count = 0, list = {} }
                found[key] = entry
            end
            entry.count = entry.count + 1
            if tonumber(spot.x) and tonumber(spot.y) then
                entry.list[#entry.list + 1] = { spot.x * 100, spot.y * 100, map = spot.map }
            end
        end
    end
    return found
end

--- What an hour of `node` in `zone` is worth: your own pace there once it
--- is long enough, else the main item at a typical pace; nil when unknown.
local function HourWorth(zone, node, itemID)
    local pace = ns.db and type(ns.db.gathering) == "table" and type(ns.db.gathering.pace) == "table"
        and ns.db.gathering.pace[ns.GrindGather.Key(zone, node)]
    local seconds = type(pace) == "table" and tonumber(pace.seconds) or 0
    if seconds >= ns.GrindGather.MIN_SECONDS then
        local copper, priced = ns.GrindGather.Worth(pace.items)
        if priced then return math.floor(copper * 3600 / seconds + 0.5), true end
    end
    local price = Price(itemID)
    if price then
        return math.floor(price * GatherToCap.TYPICAL_YIELD * GatherToCap.TYPICAL_GATHERS + 0.5), false
    end
    return nil
end

--- Of `zones` ({ zone, minLevel, maxLevel }), the one for a player of `level`.
function GatherToCap.PickZone(zones, level)
    local best, bestFar
    for _, zone in ipairs(zones) do
        local low = zone.minLevel
        if level and low and low <= level + GatherToCap.REACH then
            local middle = (low + (zone.maxLevel or low)) / 2
            local far = math.abs(middle - level)
            if not best or far < bestFar then best, bestFar = zone, far end
        end
    end
    if best then return best end
    for _, zone in ipairs(zones) do
        if not best or (zone.minLevel or 0) < (best.minLevel or 0) then best = zone end
    end
    return best
end

--- The node stops for Mining or Herbalism.
local function NodeStops(spec, level)
    local zonesOf, skillOf = {}, {}
    for _, row in ipairs(ns.GrindGather:DataRows(spec.data)) do
        local list = zonesOf[row.node]
        if not list then
            list = {}
            zonesOf[row.node] = list
        end
        local seen = false
        for _, each in ipairs(list) do if each.zone == row.zone then seen = true end end
        if not seen then
            list[#list + 1] = { zone = row.zone, minLevel = row.minLevel, maxLevel = row.maxLevel }
        end
        if row.skill then skillOf[row.node] = math.min(skillOf[row.node] or row.skill, row.skill) end
    end
    local own = OwnSpots(spec.gathering)

    local stops = {}
    for _, step in ipairs(GatherToCap.LADDERS[spec.skill]) do
        local node = step.node
        if not ns.DB:HidesSource(node) and not ns.DB:IsHiddenItem(step.item) then
            -- Where you mapped the most.
            local mine, mineCount
            for key, entry in pairs(own) do
                local zone, name = key:match("^(.-)|(.*)$")
                if name == node and (not mine or entry.count > mineCount
                    or (entry.count == mineCount and zone < mine)) then
                    mine, mineCount = zone, entry.count
                end
            end
            local data = zonesOf[node] or {}
            local pick
            if mine then
                pick = { zone = mine }
                for _, each in ipairs(data) do
                    if each.zone == mine then pick = each end
                end
            else
                pick = GatherToCap.PickZone(data, level)
            end
            if pick then
                local spots = own[ns.GrindGather.Key(pick.zone, node)]
                local itemID = ItemID(step.item)
                stops[#stops + 1] = {
                    node = node, item = step.item, itemID = itemID,
                    skill = skillOf[node] or step.skill,
                    zone = pick.zone, minLevel = pick.minLevel, maxLevel = pick.maxLevel,
                    spots = spots and spots.count or 0, spotList = spots and spots.list or {},
                }
                stops[#stops].perHour, stops[#stops].own = HourWorth(pick.zone, node, itemID)
            end
        end
    end
    return stops
end

--- The beast stops for Skinning: in each band, the camp with the beast you
--- skinned most, else the first the Grind tab would list.
local function SkinStops()
    local stops = {}
    for _, step in ipairs(GatherToCap.LADDERS.Skinning) do
        local ok, camps = pcall(ns.Grinding.Camps, ns.Grinding,
            { low = step.low, high = step.high, type = false, gives = "skinning" })
        local bestCamp, bestMob, bestSkins = nil, nil, -1
        for _, camp in ipairs(ok and camps or {}) do
            for _, mob in ipairs(camp.mobs) do
                if not ns.DB:HidesSource(mob.name) then
                    local entry = ns.GrindGather:Skins(mob.name)
                    local skins = entry and entry.skins or 0
                    if skins > bestSkins then bestCamp, bestMob, bestSkins = camp, mob, skins end
                end
            end
        end
        if bestCamp and not ns.DB:IsHiddenItem(step.item) then
            local itemID = ItemID(step.item)
            local perHour
            local skin = ns.GrindGather:SkinWorth(bestMob.name)
            local seconds = ns.Stats and ns.Stats.SecondsPerKill and ns.Stats:SecondsPerKill(bestMob.name)
            if skin and seconds then perHour = math.floor(skin * 3600 / seconds + 0.5) end
            stops[#stops + 1] = {
                node = bestMob.name, item = step.item, itemID = itemID, skill = step.skill,
                need = ns.GrindingUI and ns.GrindingUI.SkinNeed and ns.GrindingUI.SkinNeed(bestMob)
                    or ns.Grinding.SkinSkill(bestMob.minLevel),
                zone = bestCamp.zone, minLevel = bestCamp.minLevel, maxLevel = bestCamp.maxLevel,
                camp = bestCamp, spots = 0, spotList = {}, perHour = perHour, own = perHour ~= nil,
            }
        end
    end
    return stops
end

--- What moves the path: your skill and cap, your level, your spots and
--- gathers, the hide list and the data.
function GatherToCap:Key(view, skill, most, level)
    local gathering = ns.db and type(ns.db.gathering) == "table" and ns.db.gathering or {}
    local spots = type(gathering.spots) == "table" and #gathering.spots or 0
    return table.concat({ view, skill or "", most or "", level or "", spots,
        ns.GrindGather.paceVersion or 0, ns.DB.hiddenVersion or 0, ns.DB:CountSources() }, ":")
end

--- The path for the Grind tab's view `view` ("ore", "herbs", "skinning"):
--- { english, skill, most, stops, current } or nil when you lack the
--- profession. Each stop is { node, item, itemID, skill, from, to, zone,
--- minLevel, maxLevel, spots, spotList, perHour, own, state ("done", "now",
--- "later"), gathers (now only), train (a rank, or nil), camp (Skinning) }.
function GatherToCap:Path(view)
    local spec = GatherToCap.VIEWS[view or ""]
    if not spec then return nil end
    local skill, most = GatherToCap.ReadSkill(spec.skill)
    if not skill then return nil end
    local player = ns.Spots:Player()
    local level = player and player.level

    local key = self:Key(view, skill, most, level)
    self.kept = self.kept or {}
    local kept = self.kept[view]
    if kept and kept.key == key then return kept.path end

    local stops = spec.skill == "Skinning" and SkinStops() or NodeStops(spec, level)
    table.sort(stops, function(a, b)
        if a.skill ~= b.skill then return a.skill < b.skill end
        return a.node < b.node
    end)

    local nextRank = GatherToCap.NextRank(most)
    local current
    for index, stop in ipairs(stops) do
        stop.from = stop.skill
        stop.to = stops[index + 1] and stops[index + 1].skill or GatherToCap.TOP
        if stop.to <= stop.from then stop.to = stop.from + 1 end
        if stop.to <= skill then
            stop.state = "done"
        elseif not current and stop.from <= skill then
            stop.state = "now"
            current = index
            stop.gathers = GatherToCap.Gathers(math.max(skill, stop.from), stop.to, stop.need or stop.skill)
        else
            stop.state = "later"
        end
        if stop.state ~= "done" and most and stop.to > most and nextRank then
            stop.train = nextRank
        end
    end
    -- Short of the first stop's skill: the first one is where to start.
    if not current then
        for index, stop in ipairs(stops) do
            if stop.state == "later" then
                stop.state, current = "now", index
                stop.gathers = GatherToCap.Gathers(stop.from, stop.to, stop.need or stop.skill)
                break
            end
        end
    end

    local path = { english = spec.skill, skill = skill, most = most, stops = stops, current = current }
    self.kept[view] = { key = key, path = path }
    return path
end

--- The stops a path shows: the last one done, the one you are on and up
--- to `later` after it.
function GatherToCap.Shown(path, later)
    local shown = {}
    if not path then return shown end
    local lastDone
    for index, stop in ipairs(path.stops) do
        if stop.state == "done" then lastDone = index end
    end
    if lastDone then shown[#shown + 1] = path.stops[lastDone] end
    local count = 0
    for _, stop in ipairs(path.stops) do
        if stop.state == "now" then shown[#shown + 1] = stop end
        if stop.state == "later" and count < (later or 3) then
            shown[#shown + 1] = stop
            count = count + 1
        end
    end
    return shown
end

--------------------------------------------------------------------------------
-- What a click does
--------------------------------------------------------------------------------

--- Point the arrow at a stop: your spots there (Skinning: its camp).
function GatherToCap:ShowTheWay(stop)
    if not stop then return false end
    local camp = stop.camp or ns.GrindGather.NodeCamp({ name = stop.node, zone = stop.zone,
        spotList = stop.spotList })
    if not stop.camp then camp.label = stop.node end
    ns.Arrow:Grind(camp)
    ns.Print(L.Format("%s in %s", ns.Util.Colored("accent", stop.node), ns.Spots.Show(stop.zone)))
    return true
end

--- Make a goal for the stop's main item: what you have and as many more
--- as the stop's gathers, at least MIN_GOAL; then open the goals panel.
function GatherToCap:SetGoal(stop)
    if not (stop and stop.item) then return nil end
    local ok, have = pcall(ns.Goals.Have, ns.Goals, stop.item, stop.itemID)
    have = ok and tonumber(have) or 0
    local more = math.max(GatherToCap.MIN_GOAL, stop.gathers or 0)
    local goal, why = ns.Goals:Set(stop.item, have + more)
    if not goal then
        if why then ns.Print(why) end
        return nil, why
    end
    ns.Print(L.Format("goal set: %s %s. You have %d, %d to go.",
        ns.Util.Colored("good", tostring(goal.target)), ns.Util.ColorItemOr("accent", goal.item),
        goal.have or 0, math.max(0, goal.target - (goal.have or 0))))
    if ns.GoalsUI and ns.GoalsUI.Show then ns.GoalsUI:Show() end
    return goal
end
