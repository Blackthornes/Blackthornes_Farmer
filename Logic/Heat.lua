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

--- The mob the heat is for, or nil for every mob.
function Heat:Mob()
    local mob = ns.db and ns.db.heatMob
    if type(mob) == "string" and mob ~= "" then return mob end
    return nil
end

local function Changed()
    Heat.version = Heat.version + 1
    cached = nil
    if ns.HeatUI then ns.HeatUI:Refresh() end
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

--- The cells to draw on a map: { { cell, count }, ... } and the highest
--- count, for the picked mob or all of them, hidden mobs left out. Kept until
--- the cells, the mob or the hide list change.
function Heat:Cells(mapID)
    local mob = self:Mob()
    local hidden = ns.DB and ns.DB.hiddenVersion or 0

    if cached and cached.map == mapID and cached.mob == mob
        and cached.version == Heat.version and cached.hidden == hidden then
        return cached.list, cached.max
    end

    local map = type(ns.db.killHeat) == "table" and ns.db.killHeat[mapID] or nil
    local sums, highest = {}, 0

    if type(map) == "table" then
        for name, cells in pairs(map) do
            local wanted = (mob == nil or name == mob) and type(cells) == "table"
                and not (ns.DB and ns.DB:IsHiddenSource(name))
            if wanted then
                for cell, count in pairs(cells) do
                    count = tonumber(count)
                    if count and count > 0 then sums[cell] = (sums[cell] or 0) + count end
                end
            end
        end
    end

    local list = {}
    for cell, count in pairs(sums) do
        list[#list + 1] = { cell = cell, count = count }
        if count > highest then highest = count end
    end

    cached = { map = mapID, mob = mob, version = Heat.version, hidden = hidden,
        list = list, max = highest }
    return list, highest
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

ns.RegisterCommand("heat", L["a glow on the maps where you kill the most (on, off, map, minimap, strength, mob)"], function(rest)
    local argument = Util.Trim(rest)
    local lowered = argument:lower()
    local which, state = lowered:match("^(%S+)%s*(%S*)$")

    if lowered == "" then
        Status()
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
