-- Blackthornes Farmer -- Logic/GrindGather.lua
-- The Grind tab's Leather, Ore and Herbs views (the owner said yes,
-- 2026-10-14, from a mockup).
--
-- Ore and Herbs list zones and the nodes in them rather than mobs: the skill
-- each node needs and what it gives (the data), how often you gathered it
-- there, the spots you marked and how long it takes to grow back (your own
-- gathering, Logic/Gathering.lua and Logic/Respawn.lua), what one gather is
-- worth (what yours gave, at today's prices) and what an hour of it is
-- worth. Leather lists Grind's camps of skinnable beasts (Logic/Grinding.lua)
-- with the skill each needs and what a skin is worth.
--
-- Two small records are new, both account wide, both only your own play
-- (guild and shared data never reach them), both never renamed:
--
-- - `gathering.pace[zone|node]` = { seconds, gathers, items = { [name] =
--   count } }: the time spent getting each gather (the gap since the one
--   before, in the same zone, when it is under BREAK) and what they gave.
--   "An hour" is that worth over that time, once MIN_SECONDS are counted.
-- - `skinLog[mob]` = { skins, items = { [name] = count } }: each skin's
--   window, once a corpse, so a skin's worth is what your skins gave.
--
-- Nothing is worked out on a timer: the views ask when they draw.

local _, ns = ...
local L = ns.L

local GrindGather = ns.NewModule("GrindGather")

-- A gap longer than this between two gathers is a break, not travel.
GrindGather.BREAK = 300
-- Time counted before "an hour" is shown.
GrindGather.MIN_SECONDS = 600
-- Spots handed to the arrow for one node.
GrindGather.MAX_SPOTS = 8

-- The views, by the Grind tab's gives key: the data's category, the node
-- kinds of its sources, Gathering's kind and the skill.
GrindGather.VIEWS = {
    ore = { category = "Mining", gathering = "ore", skill = "Mining" },
    herbs = { category = "Herbalism", gathering = "herb", skill = "Herbalism" },
}
local NODE_SOURCE = { node = true, herb = true }

local function Clock()
    return type(GetTime) == "function" and GetTime() or nil
end

local function Key(zone, node)
    return ("%s|%s"):format(zone or "?", node or "?")
end
GrindGather.Key = Key

--- A "Mining 65" in the data as a number, or nil.
function GrindGather.SkillNumber(requires)
    if type(requires) ~= "string" then return nil end
    return tonumber(requires:match("(%d+)%s*$"))
end

--- The skill playing has in `name` ("Mining"), or nil when the client
--- will not say or you lack it; and whether the skills were read at all.
function GrindGather.PlayerSkill(name)
    local skills = ns.Spots.Skills()
    if type(skills) ~= "table" then return nil, false end
    return skills[name], true
end

--------------------------------------------------------------------------------
-- The pace of your gathering
--------------------------------------------------------------------------------

function GrindGather:PaceStore()
    local db = ns.db
    if type(db.gathering) ~= "table" then db.gathering = {} end
    if type(db.gathering.pace) ~= "table" then db.gathering.pace = {} end
    return db.gathering.pace
end

--- One gather, from Gathering:Record. `items` are names, `quantities` how
--- many of each.
function GrindGather:NoteGather(zone, node, items, quantities, now)
    if type(zone) ~= "string" or type(node) ~= "string" or node == "" then return end
    zone = ns.Spots.English(zone) or zone
    now = now or Clock()
    -- Moves with every gather, so what reads the pace knows to look again.
    GrindGather.paceVersion = (GrindGather.paceVersion or 0) + 1

    local store = self:PaceStore()
    local key = Key(zone, node)
    local entry = store[key]
    if type(entry) ~= "table" then
        entry = {}
        store[key] = entry
    end
    entry.seconds = tonumber(entry.seconds) or 0
    entry.gathers = (tonumber(entry.gathers) or 0) + 1
    if type(entry.items) ~= "table" then entry.items = {} end

    local last = self.lastGather
    if now and last and last.zone == zone then
        local gap = now - last.at
        if gap > 0 and gap < GrindGather.BREAK then entry.seconds = entry.seconds + gap end
    end
    if now then self.lastGather = { zone = zone, at = now } end

    for _, name in ipairs(items or {}) do
        local count = quantities and tonumber(quantities[name]) or 1
        entry.items[name] = (tonumber(entry.items[name]) or 0) + count
    end
end

--------------------------------------------------------------------------------
-- Skins
--------------------------------------------------------------------------------

function GrindGather:SkinStore()
    local db = ns.db
    if type(db.skinLog) ~= "table" then db.skinLog = {} end
    return db.skinLog
end

--- A skin's loot window on `mob`, from Tracker:OnLoot. Once a corpse.
function GrindGather:NoteSkin(mob, guid, items, quantities)
    if type(mob) ~= "string" or mob == "" then return end
    if ns.db.harvestPaused then return end
    self.skinned = self.skinned or {}
    if guid then
        if self.skinned[guid] then return end
        self.skinned[guid] = true
    end

    GrindGather.paceVersion = (GrindGather.paceVersion or 0) + 1
    local store = self:SkinStore()
    local entry = store[mob]
    if type(entry) ~= "table" then
        entry = {}
        store[mob] = entry
    end
    entry.skins = (tonumber(entry.skins) or 0) + 1
    if type(entry.items) ~= "table" then entry.items = {} end
    for _, name in ipairs(items or {}) do
        local count = quantities and tonumber(quantities[name]) or 1
        entry.items[name] = (tonumber(entry.items[name]) or 0) + count
    end
end

--- What your skins of `mob` gave: { skins, items } or nil.
function GrindGather:Skins(mob)
    local entry = ns.db and type(ns.db.skinLog) == "table" and ns.db.skinLog[mob]
    if type(entry) ~= "table" or not tonumber(entry.skins) or entry.skins <= 0 then return nil end
    return entry
end

--------------------------------------------------------------------------------
-- Prices
--------------------------------------------------------------------------------

local function ItemID(name, id)
    if tonumber(id) then return tonumber(id) end
    local item = ns.DB:GetItem(name)
    return item and item.id or nil
end

--- What `items` ({ [name] = count }) are worth in copper, and whether any
--- of them had a price.
function GrindGather.Worth(items, ids)
    local copper, priced = 0, false
    for name, count in pairs(items or {}) do
        local amount = type(count) == "table" and tonumber(count.count) or tonumber(count)
        local id = ItemID(name, type(count) == "table" and count.id or (ids and ids[name]))
        local ok, price = pcall(ns.Value.UnitPrice, ns.Value, id)
        if ok and type(price) == "number" and amount then
            copper = copper + price * amount
            priced = true
        end
    end
    return copper, priced
end

--- What one skin of `mob` is worth, or nil.
function GrindGather:SkinWorth(mob)
    local entry = self:Skins(mob)
    if not entry then return nil end
    local copper, priced = GrindGather.Worth(entry.items)
    if not priced then return nil end
    return math.floor(copper / entry.skins + 0.5), entry.skins
end

--------------------------------------------------------------------------------
-- The zones and their nodes
--------------------------------------------------------------------------------

--- The data's node rows for `view`: { zone, node, item, skill, minLevel,
--- maxLevel }, kept until the data or the hide list moves.
function GrindGather:DataRows(view)
    local spec = GrindGather.VIEWS[view]
    if not spec then return {} end
    local stamp = ("%d:%d"):format(ns.DB:CountSources(), ns.DB.hiddenVersion or 0)
    self.dataRows = self.dataRows or {}
    local kept = self.dataRows[view]
    if kept and kept.stamp == stamp then return kept.rows end

    local rows = {}
    for item in ns.DB:Iterate() do
        if item.category == spec.category and not ns.DB:IsHiddenItem(item.name) then
            for _, source in ipairs(item.sources or {}) do
                local nodeName = source.name or item.name
                if NODE_SOURCE[source.kind or ""] and type(source.zone) == "string"
                    and type(nodeName) == "string" and not ns.DB:IsHiddenSource(nodeName) then
                    rows[#rows + 1] = { zone = source.zone, node = nodeName, item = item.name,
                        skill = GrindGather.SkillNumber(source.requires),
                        minLevel = source.minLevel, maxLevel = source.maxLevel }
                end
            end
        end
    end
    self.dataRows[view] = { stamp = stamp, rows = rows }
    return rows
end

--- The zones for `view` ("ore" or "herbs") in the level band low..high.
--- Each is { zone, minLevel, maxLevel, nodes, count, gathers, hops,
--- travel }; each node { name, zone, skill, gives, gathers, spots, spotList,
--- respawn, perGather, perHour, forever }. Your own zones come first by
--- what the Sort menu asks, then the rest.
function GrindGather:Zones(view, low, high)
    local spec = GrindGather.VIEWS[view]
    if not spec then return {} end

    local zones, byZone = {}, {}
    local function Zone(name)
        local zone = byZone[name]
        if not zone then
            zone = { zone = name, nodes = {}, byNode = {}, gathers = 0 }
            byZone[name] = zone
            zones[#zones + 1] = zone
        end
        return zone
    end
    local function Node(zone, name)
        local node = zone.byNode[name]
        if not node then
            node = { name = name, zone = zone.zone, gives = {}, gathers = 0, spots = 0, spotList = {} }
            zone.byNode[name] = node
            zone.nodes[#zone.nodes + 1] = node
        end
        return node
    end

    -- The data: which zones have the node, the zone's levels, the skill.
    -- Laid out once per view until the data or the hide list moves.
    for _, row in ipairs(self:DataRows(view)) do
        local zone = Zone(row.zone)
        if row.minLevel then
            zone.minLevel = math.min(zone.minLevel or row.minLevel, row.minLevel)
            zone.maxLevel = math.max(zone.maxLevel or row.minLevel, row.maxLevel or row.minLevel)
        end
        local node = Node(zone, row.node)
        if row.skill then node.skill = math.min(node.skill or row.skill, row.skill) end
        node.gives[row.item] = true
    end

    -- Your own gathers.
    local Gathering = ns.Gathering
    local own = ns.db and type(ns.db.gathering) == "table" and type(ns.db.gathering.nodes) == "table"
        and ns.db.gathering.nodes or {}
    for _, entry in pairs(own) do
        if type(entry) == "table" and entry.kind == spec.gathering and type(entry.zone) == "string"
            and type(entry.node) == "string" and not ns.DB:IsHiddenSource(entry.node) then
            local zone = Zone(ns.Spots.English(entry.zone) or entry.zone)
            local node = Node(zone, entry.node)
            local gathers = tonumber(entry.gathers) or 0
            node.gathers = node.gathers + gathers
            zone.gathers = zone.gathers + gathers
            node.forever = true
            node.yield = node.yield or {}
            for name, item in pairs(type(entry.items) == "table" and entry.items or {}) do
                if type(item) == "table" then
                    node.gives[name] = true
                    local kept = node.yield[name] or { count = 0 }
                    kept.count = kept.count + (tonumber(item.count) or 0)
                    kept.id = kept.id or item.id
                    node.yield[name] = kept
                end
            end
        end
    end

    -- Your map spots, and how long each node takes to grow back.
    local spots = Gathering and ns.db and type(ns.db.gathering) == "table"
        and type(ns.db.gathering.spots) == "table" and ns.db.gathering.spots or {}
    local asked = {}
    for _, spot in ipairs(spots) do
        local zoneName = type(spot) == "table" and ns.Spots.MAP_ZONES[spot.map]
        local zone = zoneName and byZone[zoneName]
        local node = zone and type(spot.node) == "string" and zone.byNode[spot.node]
        if node and (spot.kind == nil or spot.kind == spec.gathering) then
            node.spots = node.spots + 1
            if tonumber(spot.x) and tonumber(spot.y) then
                node.spotList[#node.spotList + 1] = { spot.x * 100, spot.y * 100, map = spot.map }
            end
            -- One estimate a map and node, however many spots share them.
            local learnKey = tostring(spot.map) .. "|" .. spot.node
            if node.respawn == nil and ns.Respawn and not asked[learnKey] then
                asked[learnKey] = true
                local estimate = ns.Respawn:Estimate(spot.map, spot.node)
                if estimate.seconds then node.respawn = estimate.seconds end
            end
        end
    end

    -- Worth: a gather from your own yield, an hour from your pace.
    local pace = ns.db and type(ns.db.gathering) == "table" and type(ns.db.gathering.pace) == "table"
        and ns.db.gathering.pace or {}
    for _, zone in ipairs(zones) do
        for _, node in ipairs(zone.nodes) do
            if node.yield and node.gathers > 0 then
                local copper, priced = GrindGather.Worth(node.yield)
                if priced then node.perGather = math.floor(copper / node.gathers + 0.5) end
            end
            local entry = pace[Key(zone.zone, node.name)]
            local seconds = type(entry) == "table" and tonumber(entry.seconds) or 0
            if seconds >= GrindGather.MIN_SECONDS then
                local copper, priced = GrindGather.Worth(entry.items)
                if priced then node.perHour = math.floor(copper * 3600 / seconds + 0.5) end
            end
            local names = {}
            for name in pairs(node.gives) do names[#names + 1] = name end
            table.sort(names)
            node.givesList = names
        end
    end

    -- In the band (any overlap), or a zone you gathered in whose band the
    -- data does not know.
    local player = ns.Spots:Player()
    local shown = {}
    for _, zone in ipairs(zones) do
        local inBand
        if zone.minLevel then
            inBand = zone.minLevel <= high and (zone.maxLevel or zone.minLevel) >= low
        else
            inBand = zone.gathers > 0
        end
        if inBand and #zone.nodes > 0 then
            table.sort(zone.nodes, function(a, b)
                if (a.skill or 0) ~= (b.skill or 0) then return (a.skill or 0) < (b.skill or 0) end
                return a.name < b.name
            end)
            zone.count = #zone.nodes
            zone.byNode = nil
            if ns.Spots.ZoneOf(zone.zone) and player.zone then
                zone.hops, zone.travel = ns.Spots.Hops(player.zone, zone.zone)
            end
            shown[#shown + 1] = zone
        end
    end

    local order = ns.Grinding.Sort()
    local FAR = 99
    table.sort(shown, function(a, b)
        local hopsA, hopsB = a.hops or FAR, b.hops or FAR
        if order == "nearest" and hopsA ~= hopsB then return hopsA < hopsB end
        if order == "level" or order == "levelnear" then
            local minA, minB = a.minLevel or 0, b.minLevel or 0
            if minA ~= minB then return minA < minB end
            if order == "levelnear" and hopsA ~= hopsB then return hopsA < hopsB end
        end
        if a.gathers ~= b.gathers then return a.gathers > b.gathers end
        if a.count ~= b.count then return a.count > b.count end
        if hopsA ~= hopsB then return hopsA < hopsB end
        return a.zone < b.zone
    end)

    return shown
end

--- A node as a camp the arrow follows: its spots, nearest first. Only
--- MAX_SPOTS go to the arrow, so with more than that the ones on the map
--- you stand on are taken by distance (the oldest ones first used to win,
--- and could leave out the spot beside you).
function GrindGather.NodeCamp(node)
    local list = {}
    for index, coords in ipairs(node.spotList or {}) do list[index] = coords end
    if #list > GrindGather.MAX_SPOTS and ns.Harvest and ns.Harvest.PlayerMapPosition then
        local ok, mapID, x, y = pcall(ns.Harvest.PlayerMapPosition, ns.Harvest)
        if ok and mapID and x and y then
            local px, py = x * 100, y * 100
            local function Far(coords)
                if coords.map ~= mapID then return math.huge end
                local dx, dy = coords[1] - px, coords[2] - py
                return dx * dx + dy * dy
            end
            for index, coords in ipairs(list) do list[index] = { coords = coords, far = Far(coords), at = index } end
            table.sort(list, function(a, b)
                if a.far ~= b.far then return a.far < b.far end
                return a.at < b.at
            end)
            for index, entry in ipairs(list) do list[index] = entry.coords end
        end
    end

    local mobs = {}
    for index, coords in ipairs(list) do
        if index > GrindGather.MAX_SPOTS then break end
        mobs[#mobs + 1] = { name = node.name, zone = node.zone, coords = coords }
    end
    if #mobs == 0 then mobs[1] = { name = node.name, zone = node.zone } end
    return { zone = node.zone, label = node.name, mobs = mobs, count = #mobs,
        coords = mobs[1].coords }
end

--- "Copper Vein in The Barrens: 63 gathers, 22 spots" for chat.
function GrindGather.NodeLine(node)
    local parts = {}
    if node.gathers > 0 then parts[#parts + 1] = ns.Util.Plural(node.gathers, L["gather"], L["gathers"]) end
    if node.spots > 0 then parts[#parts + 1] = ns.Util.Plural(node.spots, L["spot"], L["spots"]) end
    local text = L.Format("%s in %s", ns.Util.Colored("accent", node.name), ns.Spots.Show(node.zone))
    if #parts > 0 then text = text .. ": " .. table.concat(parts, ", ") end
    return text
end

--------------------------------------------------------------------------------
-- The Fish view
--
-- The spots you fished, grouped by the zone they are in, from your own
-- casts alone (Logic/Fishing.lua): the pools you moused over before
-- casting, and open water for the rest. Nothing shipped and nothing from
-- the guild ever reaches it.
--
-- A spot shows catch rates and what a cast is worth from MIN_CASTS casts,
-- the same number as a mob's kills, and an hour's worth once it has timed
-- MIN_SECONDS of your fishing there.
--------------------------------------------------------------------------------

--- One spot as the Fish view shows it, or nil when it is hidden or has no
--- casts yet.
function GrindGather:FishSpot(summary)
    local spot = summary.spot
    local name = summary.name
    if ns.DB:IsHiddenSource(name) then return nil end

    local items, best = {}, nil
    for _, item in ipairs(summary.items) do
        if not ns.DB:IsHiddenItem(item.name) then
            items[#items + 1] = item
            if not best then best = item end
        end
    end

    local Fishing = ns.Fishing
    return {
        key = summary.key,
        name = name,
        -- "open water" starts a row, so it starts with a capital, the way the
        -- kills panel's fishing lines do.
        shown = (Fishing.ShowName(name):gsub("^%l", string.upper)),
        school = spot.school ~= nil,
        zone = ns.Spots.English(spot.zone) or spot.zone,
        location = spot.location,
        coords = type(spot.coords) == "table" and spot.coords or nil,
        casts = summary.casts,
        rated = summary.rated,
        needed = summary.needed,
        items = items,
        best = best,
        minSkill = tonumber(spot.minSkill),
        maxSkill = tonumber(spot.maxSkill),
        perCast = Fishing:WorthPerCast(summary.key),
        perHour = Fishing:WorthPerHour(summary.key),
        timed = Fishing:SecondsPerCast(summary.key) ~= nil,
    }
end

--- The zones you fished, each { zone, spots, count, casts, hops, travel },
--- in the order the Sort menu asks for.
function GrindGather:FishZones()
    local Fishing = ns.Fishing
    if not Fishing then return {} end

    local zones, byZone = {}, {}
    for _, summary in ipairs(Fishing:Spots()) do
        local spot = self:FishSpot(summary)
        -- A spot the client never named the zone of points nowhere.
        if spot and type(spot.zone) == "string" and spot.zone ~= "" then
            local zone = byZone[spot.zone]
            if not zone then
                zone = { zone = spot.zone, spots = {}, casts = 0 }
                byZone[spot.zone] = zone
                zones[#zones + 1] = zone
            end
            zone.spots[#zone.spots + 1] = spot
            zone.casts = zone.casts + spot.casts
        end
    end

    local player = ns.Spots:Player()
    for _, zone in ipairs(zones) do
        zone.count = #zone.spots
        table.sort(zone.spots, function(a, b)
            if a.casts ~= b.casts then return a.casts > b.casts end
            return a.shown < b.shown
        end)
        if ns.Spots.ZoneOf(zone.zone) and player.zone then
            zone.hops, zone.travel = ns.Spots.Hops(player.zone, zone.zone)
        end
    end

    local order = ns.Grinding.Sort()
    local FAR = 99
    table.sort(zones, function(a, b)
        local hopsA, hopsB = a.hops or FAR, b.hops or FAR
        -- There are no levels to go by here, so Level sorts as Nearest does.
        if order ~= "busiest" and hopsA ~= hopsB then return hopsA < hopsB end
        if a.casts ~= b.casts then return a.casts > b.casts end
        if a.count ~= b.count then return a.count > b.count end
        if hopsA ~= hopsB then return hopsA < hopsB end
        return a.zone < b.zone
    end)

    return zones
end

--- A spot as a camp the arrow follows: where you fished it.
function GrindGather.FishCamp(spot)
    local mob = { name = spot.shown, zone = spot.zone, location = spot.location,
        coords = spot.coords }
    return { zone = spot.zone, label = spot.shown, mobs = { mob }, count = 1,
        coords = spot.coords }
end

--- "Oily Blackmouth School in Stranglethorn Vale: 96 casts" for chat.
function GrindGather.FishLine(spot)
    local text = L.Format("%s in %s", ns.Util.Colored("accent", spot.shown), ns.Spots.Show(spot.zone))
    return ("%s: %s"):format(text, ns.Util.Plural(spot.casts, L["cast"], L["casts"]))
end
