-- Blackthornes Farmer -- Logic/TomTom.lua
-- The goal arrow's place, handed to TomTom (a player asked, 2026-10-09).
--
-- When TomTom is installed and "Use TomTom" is ticked (on unless unticked),
-- the place the goal arrow would point at goes to TomTom as a waypoint, and
-- Farmer's own dial stays hidden, so only TomTom's arrow is on screen. The
-- waypoint follows the dial's choice: a new nearest place, the next place or
-- the next goal swaps it, and the goal finished, the arrow turned off, a
-- dungeon, or another Blackthornes arrow aimed later take it away. Places
-- the dial cannot point at (the other continent, the zone you are in) have
-- no waypoint; the dial shows them as before.
--
-- Without TomTom, nothing changes. TomTom is only read through its global,
-- inside a pcall, so a missing or different version breaks nothing: a
-- waypoint TomTom will not take falls back to Farmer's own dial. Waypoints
-- are never saved in TomTom's list; Farmer adds them again after a reload.

local _, ns = ...

local TomTomLink = ns.NewModule("TomTom")

local Util = ns.Util

local FROM = "Blackthornes Farmer"

--- TomTom's global, when it is loaded and has the calls used here.
function TomTomLink.Addon()
    local tomtom = rawget(_G, "TomTom")
    if type(tomtom) ~= "table" then return nil end
    local ok, usable = pcall(function()
        return type(tomtom.AddWaypoint) == "function" and type(tomtom.RemoveWaypoint) == "function"
    end)
    return ok and usable and tomtom or nil
end

function TomTomLink.Installed()
    return TomTomLink.Addon() ~= nil
end

--- The switch: on unless the player unticked it.
function TomTomLink.IsOn()
    return ns.db ~= nil and ns.db.useTomTom ~= false
end

function TomTomLink:SetOn(on)
    ns.db.useTomTom = on and true or false
    if not on then self:Clear() end
    if ns.Arrow then ns.Arrow:Changed() end
end

--- True when TomTom shows the goal arrow's place for this state.
function TomTomLink.Fits(state)
    if not (TomTomLink.IsOn() and TomTomLink.Installed()) then return false end
    if type(state) ~= "table" or not (state.mode == "point" or state.mode == "arrived") then
        return false
    end
    local target = state.target
    return type(target) == "table" and type(target.map) == "number"
        and type(target.x) == "number" and type(target.y) == "number"
end

--- What the waypoint is called: "Copper Ore: Copper Vein, Westfall".
function TomTomLink.Title(state)
    local place = ns.Arrow.Place(state.target)
    local item = state.goal and state.goal.item
    return item and (item .. ": " .. place) or place
end

--- Give TomTom the place for `state`. True when TomTom shows it, so the
--- dial can stay hidden; false (and no waypoint of ours left) otherwise.
function TomTomLink:Take(state)
    if not TomTomLink.Fits(state) then
        self:Clear()
        return false
    end

    local target = state.target
    local key = (state.goal and state.goal.item or "?") .. "|" .. ns.Arrow.Key(target)
    if self.uid and self.key == key then return true end
    -- TomTom turned this one down already: the dial shows it.
    if self.refused == key then return false end

    self:Clear()
    local tomtom = TomTomLink.Addon()
    local title = TomTomLink.Title(state)
    local ok, uid = pcall(tomtom.AddWaypoint, tomtom, target.map, target.x, target.y, {
        title = title, desc = title, from = FROM,
        persistent = false, minimap = true, world = true, crazy = true, silent = true,
    })
    if not ok or uid == nil then
        ns.Debug("TomTom would not take the waypoint:", tostring(uid))
        self.refused = key
        return false
    end

    self.uid, self.key, self.refused = uid, key, nil
    return true
end

--- Take our waypoint off TomTom, if there is one.
function TomTomLink:Clear()
    local uid = self.uid
    self.uid, self.key = nil, nil
    if uid == nil then return end
    local tomtom = TomTomLink.Addon()
    if tomtom then pcall(tomtom.RemoveWaypoint, tomtom, uid) end
end

--- One line for /farm arrow check.
function TomTomLink.CheckLine()
    if not TomTomLink.Installed() then
        return "  TomTom: not installed, so the dial shows the way"
    end
    if not TomTomLink.IsOn() then
        return "  TomTom: installed, not used (/farm arrow tomtom on)"
    end
    return "  TomTom: " .. Util.Colored("good", "yes") .. ", its arrow shows the way and the dial hides"
end
