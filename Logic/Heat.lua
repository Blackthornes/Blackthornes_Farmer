-- Blackthornes Farmer -- Logic/Heat.lua
-- Where you kill, kept as a heat map for the world map and the minimap
-- (UI/Heat.lua draws it). A test feature: both switches are off unless
-- ticked, and nothing is recorded while both are off.
--
-- Each kill adds one to a small cell of the map you are on, by the mob's
-- name: killHeat[mapID][mob][cell] = count, with GRID cells across and down
-- (cell = row * GRID + column, from 0). A cell is about 1% of a map wide, so
-- the save stays small however many mobs you kill: a mob keeps at most
-- MAX_CELLS cells and a map at most MAX_MOBS mobs, and once either is full
-- only cells already there count up. Your own kills only: guild, shared and
-- shipped data never reach it. A kill whose spot the client will not say
-- (inside a dungeon) adds nothing; the kill itself still counts.
--
-- Saved, never renamed: killHeat, heatWorld, heatMinimap, heatLevel, heatMob.
--
-- Show on Map (the owner, 2026-10-18): a search row's Map button aims the
-- glow at one mob (heatMob) or one item. An item's glow is the mobs your own
-- loot says drop it, each weighted by how often it did (`Heat:ItemMobs`, from
-- Harvest.records only). The item is kept for the session only; nothing new
-- is saved.

local _, ns = ...
local L = ns.L

local Heat = ns.NewModule("Heat")

local Util = ns.Util

Heat.GRID = 100
Heat.MAX_CELLS = 400
Heat.MAX_MOBS = 200

-- Some, More, Most: how strong the glow is drawn (2 is the usual).
Heat.LEVELS = { 0.5, 0.75, 1 }

-- Bumped whenever the saved cells change, so a drawing knows to redo itself.
Heat.version = 0

local cached

--------------------------------------------------------------------------------
-- Cells
--------------------------------------------------------------------------------

--- The cell a point is in. x and y run 0 to 1 across and down the map.
function Heat.CellOf(x, y)
    local grid = Heat.GRID
    local cx = math.min(grid - 1, math.max(0, math.floor(x * grid)))
    local cy = math.min(grid - 1, math.max(0, math.floor(y * grid)))
    return cy * grid + cx
end

--- The middle of a cell, as 0 to 1 across and down the map.
function Heat.CellCentre(cell)
    local grid = Heat.GRID
    local cx = cell % grid
    local cy = (cell - cx) / grid
    return (cx + 0.5) / grid, (cy + 0.5) / grid
end

--- The colour of a share (0 to 1) of the busiest cell: blue, teal, yellow,
--- orange, red.
local STOPS = {
    { 0.00, 0.16, 0.36, 0.84 },
    { 0.25, 0.18, 0.72, 0.63 },
    { 0.50, 0.91, 0.85, 0.29 },
    { 0.75, 0.91, 0.54, 0.16 },
    { 1.00, 0.85, 0.19, 0.17 },
}

function Heat.Colour(share)
    share = math.min(1, math.max(0, tonumber(share) or 0))
    for index = 2, #STOPS do
        local low, high = STOPS[index - 1], STOPS[index]
        if share <= high[1] then
            local through = (share - low[1]) / (high[1] - low[1])
            return low[2] + (high[2] - low[2]) * through,
                low[3] + (high[3] - low[3]) * through,
                low[4] + (high[4] - low[4]) * through
        end
    end
    return STOPS[#STOPS][2], STOPS[#STOPS][3], STOPS[#STOPS][4]
end

--------------------------------------------------------------------------------
-- Switches
--------------------------------------------------------------------------------

function Heat.WorldOn() return ns.db ~= nil and ns.db.heatWorld == true end
function Heat.MinimapOn() return ns.db ~= nil and ns.db.heatMinimap == true end

--- Is anything asking for the heat? Kills are only noted while it is.
function Heat.Recording() return Heat.WorldOn() or Heat.MinimapOn() end

--- 1 to 3: Some, More, Most.
function Heat:Level()
    local level = math.floor(tonumber(ns.db and ns.db.heatLevel) or 2)
    return math.min(#Heat.LEVELS, math.max(1, level))
end

--- The mob the heat is for, or nil for every mob. Nil while an item is.
function Heat:Mob()
    if Heat.item then return nil end
    local mob = ns.db and ns.db.heatMob
    if type(mob) == "string" and mob ~= "" then return mob end
    return nil
end

--- The item the heat is for (Show on Map), or nil.
function Heat:Item()
    return Heat.item and Heat.item.name or nil
end

--- What the glow is for, as one string for a drawing's key.
function Heat:TargetKey()
    if Heat.item then return "item:" .. Heat.item.name end
    local mob = self:Mob()
    return mob and ("mob:" .. mob) or "all"
end

local function Changed()
    Heat.version = Heat.version + 1
    cached = nil
    if ns.HeatUI then ns.HeatUI:Refresh() end
    -- The loot table's Map button follows what the map shows.
    if ns.LootTableUI and ns.LootTableUI.Refresh then pcall(ns.LootTableUI.Refresh, ns.LootTableUI) end
end

function Heat:SetWorld(on)
    ns.db.heatWorld = on and true or false
    Changed()
end

function Heat:SetMinimap(on)
    ns.db.heatMinimap = on and true or false
    Changed()
end

function Heat:SetLevel(level)
    ns.db.heatLevel = math.min(#Heat.LEVELS, math.max(1, math.floor(tonumber(level) or 2)))
    Changed()
end

function Heat:SetMob(name)
    name = type(name) == "string" and Util.Trim(name) or ""
    ns.db.heatMob = name ~= "" and name or nil
    Heat.item = nil
    Changed()
end

--- The mobs your own loot says drop an item: { { mob, chance (0 to 1),
--- corpses } }, likeliest first. Suffixes count as their item, a mob in two
--- places is one mob, and hidden mobs are left out.
-- ItemMobs answers, kept by item until a corpse is recorded, the records
-- or the hide list change: a search row asks it on every redraw.
local itemMobsKept = {}

function Heat:ItemMobs(itemName)
    local Harvest = ns.Harvest
    if not (Harvest and type(Harvest.records) == "table" and type(itemName) == "string") then
        return {}
    end

    local stamp = tostring(Harvest.changes or 0) .. "|" .. tostring(Harvest.records)
        .. "|" .. tostring(ns.DB and ns.DB.hiddenVersion or 0)
    if itemMobsKept.stamp ~= stamp then itemMobsKept = { stamp = stamp } end
    local kept = itemMobsKept[itemName]
    if kept then return kept end

    local byMob = {}
    for _, record in pairs(Harvest.records) do
        local mob = type(record) == "table" and record.mob
        local corpses = tonumber(record and record.corpses) or 0
        if type(mob) == "string" and corpses > 0
            and not (ns.DB and ns.DB:IsHiddenSource(mob)) then
            local entry = Harvest:GroupedItems(record)[itemName]
            local tally = byMob[mob]
            if not tally then
                tally = { corpses = 0, had = 0 }
                byMob[mob] = tally
            end
            tally.corpses = tally.corpses + corpses
            if type(entry) == "table" then
                tally.had = tally.had + math.min(corpses, tonumber(entry.corpses) or 0)
            end
        end
    end

    local list = {}
    for mob, tally in pairs(byMob) do
        if tally.had > 0 then
            list[#list + 1] = { mob = mob, chance = tally.had / tally.corpses, corpses = tally.corpses }
        end
    end
    table.sort(list, function(a, b)
        if a.chance ~= b.chance then return a.chance > b.chance end
        return a.mob < b.mob
    end)
    itemMobsKept[itemName] = list
    return list
end

--- Aim the glow at an item's mobs, or nil for all mobs again.
function Heat:SetItem(itemName)
    if type(itemName) ~= "string" or itemName == "" then
        Heat.item = nil
        Changed()
        return
    end

    local mobs, weights, best = self:ItemMobs(itemName), {}, 0
    for _, entry in ipairs(mobs) do
        if entry.chance > best then best = entry.chance end
    end
    for _, entry in ipairs(mobs) do weights[entry.mob] = best > 0 and entry.chance / best or 0 end

    ns.db.heatMob = nil
    Heat.item = { name = itemName, mobs = mobs, weights = weights }
    Changed()
end

--- Back to every mob.
function Heat:ShowAll()
    ns.db.heatMob = nil
    Heat.item = nil
    Changed()
end

--------------------------------------------------------------------------------
-- Keeping
--------------------------------------------------------------------------------

function Heat:Store()
    if type(ns.db.killHeat) ~= "table" then ns.db.killHeat = {} end
    return ns.db.killHeat
end

--- Add one kill of `mob` at a point on a map. Returns true when it counted.
function Heat:Note(mapID, x, y, mob)
    mapID, x, y = tonumber(mapID), tonumber(x), tonumber(y)
    if not (mapID and x and y and type(mob) == "string" and mob ~= "") then return false end

    local store = self:Store()
    local map = store[mapID]
    if type(map) ~= "table" then
        map = {}
        store[mapID] = map
    end

    local cells = map[mob]
    if type(cells) ~= "table" then
        local mobs = 0
        for _ in pairs(map) do mobs = mobs + 1 end
        if mobs >= Heat.MAX_MOBS then return false end
        cells = {}
        map[mob] = cells
    end

    local cell = Heat.CellOf(x, y)
    local have = tonumber(cells[cell])

    if not have then
        local count = 0
        for _ in pairs(cells) do count = count + 1 end
        if count >= Heat.MAX_CELLS then return false end
        have = 0
    end

    cells[cell] = have + 1
    Heat.version = Heat.version + 1
    cached = nil
    return true
end

--- A kill just counted: note where you are. Never allowed to cost the kill.
function Heat:Kill(mob)
    if not (ns.db and Heat.Recording()) or ns.db.harvestPaused then return end

    local mapID, x, y = ns.Harvest:PlayerMapPosition()
    if mapID then self:Note(mapID, x, y, mob) end
end

--------------------------------------------------------------------------------
-- Reading
--------------------------------------------------------------------------------

--- Where map `inner` lies on map `outer`, as left, right, top, bottom in
--- `outer`'s 0 to 1, or nil when the client does not say. Read first from
--- both maps' corners in the world (two maps of one continent, nested or
--- side by side), else from C_Map.GetMapRectOnMap. On Forever a kill can
--- be kept under the continent while the zone map showed nothing of it
--- (Clattering Crawler glowed on Kalimdor, not Ashenvale, 2026-10-18).
--- Kept per pair: a map's place never moves.
local rects = {}

local function Read(value)
    local read = ns.Harvest and ns.Harvest.ReadableNumber or tonumber
    return read(value)
end

--- A map point in the world: continent, then the two world axes. A map's
--- x runs along the world's second axis and its y along the first.
local function World(mapID, x, y)
    if type(C_Map) ~= "table" or type(C_Map.GetWorldPosFromMapPos) ~= "function"
        or type(CreateVector2D) ~= "function" then
        return nil
    end
    local ok, continent, position = pcall(C_Map.GetWorldPosFromMapPos, mapID, CreateVector2D(x, y))
    if not ok or type(position) ~= "table" or type(position.GetXY) ~= "function" then return nil end
    local read, first, second = pcall(position.GetXY, position)
    if not read then return nil end
    continent, first, second = Read(continent), Read(first), Read(second)
    if not (continent and first and second) then return nil end
    return continent, first, second
end

local function ByWorld(inner, outer)
    local ic, ia0, ib0 = World(inner, 0, 0)
    local _, ia1, ib1 = World(inner, 1, 1)
    local oc, oa0, ob0 = World(outer, 0, 0)
    local _, oa1, ob1 = World(outer, 1, 1)
    if not (ic and oc and ia1 and oa1) or ic ~= oc then return nil end
    if ob1 == ob0 or oa1 == oa0 then return nil end
    local left, right = (ib0 - ob0) / (ob1 - ob0), (ib1 - ob0) / (ob1 - ob0)
    local top, bottom = (ia0 - oa0) / (oa1 - oa0), (ia1 - oa0) / (oa1 - oa0)
    if right - left > 0 and bottom - top > 0 then return { left, right, top, bottom } end
    return nil
end

local function ByRect(inner, outer)
    if type(C_Map) ~= "table" or type(C_Map.GetMapRectOnMap) ~= "function" then return nil end
    local ok, left, right, top, bottom = pcall(C_Map.GetMapRectOnMap, inner, outer)
    if not ok then return nil end
    left, right, top, bottom = Read(left), Read(right), Read(top), Read(bottom)
    if left and right and top and bottom and right - left > 0 and bottom - top > 0 then
        return { left, right, top, bottom }
    end
    return nil
end

function Heat.MapRect(inner, outer)
    local key = tostring(inner) .. ">" .. tostring(outer)
    local kept = rects[key]
    if kept == nil then
        kept = ByWorld(inner, outer) or ByRect(inner, outer) or false
        rects[key] = kept
    end
    if kept == false then return nil end
    return kept[1], kept[2], kept[3], kept[4]
end

--- A point on map `from` as a point on map `to`, or nil when it is off `to`
--- or the client can't place one map on the other. A kill is kept under the
--- map the game names where you stood, which need not be the map you look
--- at later (the owner tracked Clattering Crawler on Ashenvale and saw no
--- glow, 2026-10-18), so the glow reads every map the shown one holds or
--- lies in.
function Heat.Carry(from, to, x, y)
    if from == to then return x, y end
    local left, right, top, bottom = Heat.MapRect(from, to)
    local nx, ny
    if left then
        nx, ny = left + x * (right - left), top + y * (bottom - top)
    else
        left, right, top, bottom = Heat.MapRect(to, from)
        if not left then return nil end
        nx, ny = (x - left) / (right - left), (y - top) / (bottom - top)
    end
    if nx < 0 or nx > 1 or ny < 0 or ny > 1 then return nil end
    return nx, ny
end

--- The cells to draw on a map: { { cell, count }, ... } and the highest
--- count, for the picked mob or all of them, hidden mobs left out. Kills
--- kept under a map inside this one, or one this one lies in, count too,
--- moved onto this map's cells; `own` keeps to this map's own. Kept until
--- the cells, the mob or the hide list change.
function Heat:Cells(mapID, own)
    local mob = self:Mob()
    local target = self:TargetKey()
    local weights = Heat.item and Heat.item.weights
    local hidden = ns.DB and ns.DB.hiddenVersion or 0

    -- Kept per map, since the world map and the minimap can show two.
    local slot = tostring(mapID) .. (own and ":own" or "")
    local kept = cached and cached[slot]
    if kept and kept.target == target and kept.version == Heat.version and kept.hidden == hidden then
        return kept.list, kept.max
    end

    local store = type(ns.db.killHeat) == "table" and ns.db.killHeat or {}
    local sums, highest = {}, 0

    for storedID, map in pairs(store) do
        local here = storedID == mapID
        if type(map) == "table" and (here or not own) then
            for name, cells in pairs(map) do
                local weight = 1
                if weights then
                    weight = weights[name] or 0
                elseif mob ~= nil and name ~= mob then
                    weight = 0
                end
                local wanted = weight > 0 and type(cells) == "table"
                    and not (ns.DB and ns.DB:IsHiddenSource(name))
                if wanted then
                    for cell, count in pairs(cells) do
                        count = tonumber(count)
                        cell = tonumber(cell)
                        if count and count > 0 and cell then
                            local at = cell
                            if not here then
                                local x, y = Heat.CellCentre(cell)
                                x, y = Heat.Carry(storedID, mapID, x, y)
                                at = x and Heat.CellOf(x, y) or nil
                            end
                            if at then sums[at] = (sums[at] or 0) + count * weight end
                        end
                    end
                end
            end
        end
    end

    local list = {}
    for cell, count in pairs(sums) do
        list[#list + 1] = { cell = cell, count = count }
        if count > highest then highest = count end
    end

    cached = cached or {}
    cached[slot] = { target = target, version = Heat.version, hidden = hidden,
        list = list, max = highest }
    return list, highest
end

-- Which mobs have any spot kept, laid out again only when the cells move.
local withSpots, withSpotsVersion

--- Does a mob have a spot kept on any map?
function Heat:HasSpots(mob)
    if withSpotsVersion ~= Heat.version or not withSpots then
        withSpots, withSpotsVersion = {}, Heat.version
        local store = ns.db and ns.db.killHeat
        if type(store) == "table" then
            for _, map in pairs(store) do
                if type(map) == "table" then
                    for name, cells in pairs(map) do
                        if type(cells) == "table" and next(cells) ~= nil then withSpots[name] = true end
                    end
                end
            end
        end
    end
    return type(mob) == "string" and withSpots[mob] == true
end

--- Does any mob that dropped an item have a spot kept?
function Heat:ItemHasSpots(itemName)
    for _, entry in ipairs(self:ItemMobs(itemName)) do
        if self:HasSpots(entry.mob) then return true end
    end
    return false
end

--- The map with the most glow for what the heat is for now, or nil.
function Heat:BestMap()
    local store = ns.db and ns.db.killHeat
    if type(store) ~= "table" then return nil end

    local bestMap, bestSum = nil, 0
    for mapID in pairs(store) do
        -- Its own kills only: a continent holding them would tie with the zone.
        local list = self:Cells(mapID, true)
        local sum = 0
        for _, entry in ipairs(list) do sum = sum + entry.count end
        if sum > bestSum or (sum == bestSum and sum > 0 and bestMap and mapID < bestMap) then
            bestMap, bestSum = mapID, sum
        end
    end
    return bestMap
end

--- Open the world map where the glow is, out of a fight. True when it asked.
function Heat:OpenMap()
    local mapID = self:BestMap()
    if not mapID then return false end
    if type(InCombatLockdown) == "function" then
        local ok, fighting = pcall(InCombatLockdown)
        if ok and fighting then return false end
    end
    if type(OpenWorldMap) ~= "function" then return false end
    return (pcall(OpenWorldMap, mapID))
end

--- A search row's Map button: aim the glow at a mob ("mob") or an item
--- ("item") and open the map there. The same row again goes back to every
--- mob. Returns true when it aimed.
function Heat:ShowOnMap(kind, name)
    if type(name) ~= "string" or name == "" then return false end

    if (kind == "item" and self:Item() == name) or (kind == "mob" and self:Mob() == name) then
        self:ShowAll()
        return false
    end

    if kind == "item" then
        self:SetItem(name)
    else
        self:SetMob(name)
    end
    self:OpenMap()
    return true
end

--- How much is kept: maps, mob lines and cells.
function Heat:Summary()
    local maps, lines, cells = 0, 0, 0
    if type(ns.db.killHeat) == "table" then
        for _, map in pairs(ns.db.killHeat) do
            if type(map) == "table" then
                maps = maps + 1
                for _, mobCells in pairs(map) do
                    if type(mobCells) == "table" then
                        lines = lines + 1
                        for _ in pairs(mobCells) do cells = cells + 1 end
                    end
                end
            end
        end
    end
    return maps, lines, cells
end

--- Forget every kill spot. Typed command only; Settings never deletes data.
function Heat:Clear()
    local _, _, cells = self:Summary()
    ns.db.killHeat = {}
    Changed()
    return cells
end

--------------------------------------------------------------------------------
-- Command
--------------------------------------------------------------------------------

local function OnOff(on) return on and L["on"] or L["off"] end

local function Status()
    local _, lines, cells = Heat:Summary()
    local levelNames = { L["Some"], L["More"], L["Most"] }
    ns.Print(L.Format("kill heat: world map %s, minimap %s, strength %s, for %s.",
        Util.Colored("accent", OnOff(Heat.WorldOn())),
        Util.Colored("accent", OnOff(Heat.MinimapOn())),
        Util.Colored("accent", levelNames[Heat:Level()]),
        Util.Colored("accent", Heat:Mob() or L["all mobs"])))
    ns.Print(L.Format("%s kept for %s.", Util.Plural(cells, L["spot"], L["spots"]),
        Util.Plural(lines, L["mob"], L["mobs"])))
    ns.PrintRaw(Util.Colored("muted",
        "  /farm heat on|off, map on|off, minimap on|off, strength some|more|most, mob <name>|all"))
end

--- `/farm heat check`: what the glow reads, for a report (ns.KeepCheck
--- saves it). English on purpose, like the other checks.
function Heat.Check()
    local function Say(text) ns.PrintRaw(text) end
    local target = Heat:TargetKey()
    Say(("heat check: world %s, minimap %s, tracking %s"):format(tostring(Heat.WorldOn()),
        tostring(Heat.MinimapOn()), target))

    local best, bx, by = ns.Harvest:PlayerMapPosition()
    Say(("you stand on map %s at %s, %s"):format(tostring(best),
        bx and ("%.3f"):format(bx) or "?", by and ("%.3f"):format(by) or "?"))

    local view = ns.MapMarkers and ns.MapMarkers:WorldView()
    Say(("world map shows %s"):format(view and tostring(view.mapID) or "nothing (closed)"))

    local store = type(ns.db.killHeat) == "table" and ns.db.killHeat or {}
    local mob = Heat:Mob()
    local weights = Heat.item and Heat.item.weights
    local any = false
    for mapID, map in pairs(store) do
        if type(map) == "table" then
            local cells, kills = 0, 0
            for name, list in pairs(map) do
                local wanted = type(list) == "table"
                    and ((weights and weights[name]) or (not weights and (mob == nil or name == mob)))
                if wanted then
                    for _, count in pairs(list) do
                        cells, kills = cells + 1, kills + (tonumber(count) or 0)
                    end
                end
            end
            if cells > 0 then
                any = true
                local shown = view and view.mapID or best or mapID
                local left = mapID ~= shown and Heat.MapRect(mapID, shown)
                Say(("kept on map %s: %d spots, %d kills%s"):format(tostring(mapID), cells, kills,
                    left and " (lies on the map shown)" or ""))
            end
        end
    end
    if not any then Say("no spots kept for what is tracked") end

    local shownMap = view and view.mapID or best
    if shownMap then
        local list, highest = Heat:Cells(shownMap)
        Say(("glow on map %s: %d spots, busiest %s"):format(tostring(shownMap), #list, tostring(highest)))
    end
    local ui = ns.HeatUI
    local layer = ui and ui.world
    if layer then
        local okLevel, level = pcall(layer.frame.GetFrameLevel, layer.frame)
        local okShown, shown = pcall(layer.frame.IsVisible, layer.frame)
        Say(("world layer: %d dots, %d edges, level %s, visible %s, drawing %s"):format(layer.used or 0,
            layer.edgesUsed or 0, okLevel and tostring(level) or "?", okShown and tostring(shown) or "?",
            tostring(ui.job ~= nil)))
    else
        Say("world layer: not made yet")
    end
    if view and ns.MapMarkers and ns.MapMarkers.BaseLevel then
        local okCanvas, canvasLevel = pcall(view.canvas.GetFrameLevel, view.canvas)
        Say(("map art: canvas level %s, layers count from %s"):format(
            okCanvas and tostring(canvasLevel) or "?", tostring(ns.MapMarkers.BaseLevel(view.canvas))))
    end
end

ns.RegisterCommand("heat", L["a glow on the maps where you kill the most (on, off, map, minimap, strength, mob)"], function(rest)
    local argument = Util.Trim(rest)
    local lowered = argument:lower()
    local which, state = lowered:match("^(%S+)%s*(%S*)$")

    if lowered == "" then
        Status()
        return
    end

    if lowered == "check" then
        ns.KeepCheck("heat check", Heat.Check)
        return
    end

    if lowered == "clear" then
        local _, _, cells = Heat:Summary()
        ns.Print(L.Format("this forgets all %s you killed at, for good. Your kill counts stay. Type /farm heat clear confirm to do it.",
            Util.Plural(cells, L["spot"], L["spots"])))
        return
    end

    if lowered == "clear confirm" then
        ns.Print(L.Format("%s forgotten.", Util.Plural(Heat:Clear(), L["spot"], L["spots"])))
        return
    end

    local name = argument:match("^[Mm][Oo][Bb]%s+(.+)$")
    if name then
        if name:lower() == "all" then name = nil end
        Heat:SetMob(name)
    elseif which == "strength" then
        local index = ({ some = 1, more = 2, most = 3 })[state]
        if index then Heat:SetLevel(index) end
    elseif which == "on" or which == "off" then
        Heat:SetWorld(which == "on")
        Heat:SetMinimap(which == "on")
    elseif (which == "map" or which == "world") and (state == "on" or state == "off") then
        Heat:SetWorld(state == "on")
    elseif which == "minimap" and (state == "on" or state == "off") then
        Heat:SetMinimap(state == "on")
    end

    Status()
end)
