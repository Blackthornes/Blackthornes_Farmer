-- Blackthornes Farmer -- UI/MapMarkers.lua
-- Markers on the world map and the minimap where you gathered herbs and ore,
-- and where you fished a school you moused over first.
--
-- The rules for these: they must never read as a node you can gather, and
-- a live node must always show over them. On the world map a marker is the
-- icon of what that spot gave you, in a gold ring, with a green check in the
-- corner, at the bottom of the map's pins. It stays greyed and faded until
-- Logic/Respawn.lua says the node should be back, then shows in full color.
-- A school never grows back, so its marker stays greyed. Pins of one kind
-- that would sit on top of each other at the zoom shown are drawn as one with
-- a count (MapMarkers.Group). On the minimap, where the game's
-- node blips are part of the map and every addon frame draws over them, a
-- marker is an empty gold frame with the check outside a corner, so a node
-- that has grown back shows through its middle. The longer ago the gather,
-- the fainter the marker. Hover one and it says what it was, how many times
-- you took it, when last, and when it should be back (Logic/Respawn.lua).
--
-- The spots themselves are Logic/Gathering.lua's. This file only draws them,
-- and only the ones on the map you are looking at (world map) or standing on
-- (minimap). Each map has its own switch, both on unless turned off on the
-- settings page or with /farm markers. Each character sees only the spots
-- for the gathering skills it knows, unless "My Professions Only:" is
-- unticked (MapMarkers.MineOnly).
--
-- Nothing here has a template or XML behind it: markers are plain frames
-- parented to the map's canvas and to the minimap, placed by hand. Every
-- client call is guarded, since nothing documents which of the map APIs this
-- client ships; a map this cannot read simply gets no markers.

local _, ns = ...
local L = ns.L

local MapMarkers = ns.NewModule("MapMarkers")

local Theme = ns.Theme
local Util = ns.Util

-- On screen, whatever the zoom. The minimap's is the outside of its frame;
-- the clear middle is a little smaller, and wider than the game's node blip.
local WORLD_SIZE = 18
local MINIMAP_SIZE = 20

-- World map pins of one kind closer than this on screen, in pixels, are
-- drawn as one pin with a count (the owner, 2026-10-26: a farmed patch was a
-- pile of pins). Only how they are drawn: the saved spots never change.
local JOIN_PIXELS = WORLD_SIZE

-- How many items a joined pin's hover lists.
local TOOLTIP_ITEMS = 3

-- The minimap is redrawn this often while you move, in seconds.
local MINIMAP_STEP = 0.1

-- At most this many markers on the minimap, nearest first.
local MINIMAP_MAX = 40

-- Fading with age: full strength for FRESH seconds, down to FADED_ALPHA by OLD.
local FRESH = 5 * 60
local OLD = 60 * 60
local FRESH_ALPHA = 0.95
local FADED_ALPHA = 0.5

-- Stand-ins for a spot whose item is not known.
local ICONS = {
    herb = [[Interface\Icons\INV_Misc_Flower_02]],
    ore = [[Interface\Icons\INV_Ore_Copper_01]],
    fish = [[Interface\Icons\INV_Misc_Fish_02]],
}

-- How a greyed icon is tinted, and a node that should be back.
local GREY_TINT = 0.8
local BACK_ALPHA = FRESH_ALPHA

-- A soft round alpha mask the game ships: it rounds the icon and, tinted,
-- makes the ring behind it.
local ROUND = [[Interface\CharacterFrame\TempPortraitAlphaMask]]
local CHECK = [[Interface\RaidFrame\ReadyCheck-Ready]]

MapMarkers.FRESH = FRESH
MapMarkers.OLD = OLD
MapMarkers.FRESH_ALPHA = FRESH_ALPHA
MapMarkers.ICONS = ICONS
MapMarkers.JOIN_PIXELS = JOIN_PIXELS

--- Cut `icon` round. A retail engine rounds a texture with a mask texture
--- of its own; through Texture:SetMask alone the icon can show square and
--- scrambled. SetMask only where the client has no mask textures.
function MapMarkers.RoundIcon(frame, icon)
    if type(frame.CreateMaskTexture) == "function" and type(icon.AddMaskTexture) == "function" then
        local ok, mask = pcall(frame.CreateMaskTexture, frame, nil, "ARTWORK")
        if ok and mask then
            pcall(mask.SetTexture, mask, ROUND, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
            mask:SetAllPoints(icon)
            pcall(icon.AddMaskTexture, icon, mask)
            return mask
        end
    end
    pcall(icon.SetMask, icon, ROUND)
    return nil
end

--------------------------------------------------------------------------------
-- Switches
--------------------------------------------------------------------------------

function MapMarkers.WorldOn()
    return ns.db and ns.db.markersWorld ~= false
end

function MapMarkers.MinimapOn()
    return ns.db and ns.db.markersMinimap ~= false
end

function MapMarkers:SetWorld(on)
    ns.db.markersWorld = on and true or false
    self:Refresh()
end

function MapMarkers:SetMinimap(on)
    ns.db.markersMinimap = on and true or false
    self:Refresh()
end

--- Only the spots for the gathering skills this character knows (Trent,
--- 2026-11-01: they are of no use on another character). On unless
--- unticked; nil reads as on.
function MapMarkers.MineOnly()
    return ns.db and ns.db.markersMyProfessions ~= false
end

function MapMarkers:SetMineOnly(on)
    ns.db.markersMyProfessions = on and true or false
    self.known = nil
    self:Refresh()
end

-- What each marker kind needs, by the skill's English name.
MapMarkers.KIND_SKILL = { herb = "Herbalism", ore = "Mining", fish = "Fishing" }
-- How often the skills are read again; a learned or dropped skill also
-- reads them at once (SKILL_LINES_CHANGED).
MapMarkers.KNOWN_EVERY = 10

local SKILL_NAMES = { "Herbalism", "Herb Gathering", "Mining", "Fishing" }
local SAME_SKILL = { ["Herb Gathering"] = "Herbalism" }

local function SkillFromName(name, line, found)
    line = ns.Harvest.ReadableNumber(line)
    if line then
        for english, lines in pairs(ns.Gathering.SKILL_LINES or {}) do
            for _, id in ipairs(lines) do
                if id == line then found[english] = true end
            end
        end
    end
    name = ns.Harvest.Readable(name)
    local english = name and ns.Gathering.SkillOf(name, SKILL_NAMES)
    if english then found[SAME_SKILL[english] or english] = true end
end

--- The gathering skills this character knows: { Herbalism = true, ... },
--- or nil when the client will not say (then every spot shows).
function MapMarkers.ReadKnown()
    local found, read = {}, false

    if type(GetProfessions) == "function" and type(GetProfessionInfo) == "function" then
        local ok, a, b, c, d, e = pcall(GetProfessions)
        if ok then
            read = true
            for _, index in ipairs({ a or false, b or false, c or false, d or false, e or false }) do
                index = index and ns.Harvest.ReadableNumber(index)
                if index then
                    local got, name, _, _, _, _, _, line = pcall(GetProfessionInfo, index)
                    if got then SkillFromName(name, line, found) end
                end
            end
        end
    end

    if not next(found) and type(GetNumSkillLines) == "function" and type(GetSkillLineInfo) == "function" then
        local ok, lines = pcall(GetNumSkillLines)
        lines = ok and ns.Harvest.ReadableNumber(lines) or nil
        if lines and lines > 0 then
            read = true
            for index = 1, lines do
                local got, name, header = pcall(GetSkillLineInfo, index)
                if got and not header then SkillFromName(name, nil, found) end
            end
        end
    end

    return read and found or nil
end

--- The kinds of spot to show: { herb = true, ... }, a stamp for redraw
--- keys, and nil kinds when every kind shows. Kept KNOWN_EVERY seconds.
function MapMarkers:ShownKinds()
    if not MapMarkers.MineOnly() then return nil, "all" end

    local now = GetTime and GetTime() or 0
    local kept = self.known
    if kept and now - kept.at < MapMarkers.KNOWN_EVERY then return kept.kinds, kept.stamp end

    local known = MapMarkers.ReadKnown()
    local kinds, stamp
    if known then
        kinds, stamp = {}, {}
        for kind, skill in pairs(MapMarkers.KIND_SKILL) do
            if known[skill] then kinds[kind] = true; stamp[#stamp + 1] = kind end
        end
        table.sort(stamp)
        stamp = "mine:" .. table.concat(stamp, ",")
    else
        stamp = "all"
    end
    self.known = { at = now, kinds = kinds, stamp = stamp }
    return kinds, stamp
end

--- Does a spot of this kind show for this character?
function MapMarkers.KindShows(kind, kinds)
    if not kinds then return true end
    if not MapMarkers.KIND_SKILL[kind] then return true end
    return kinds[kind] == true
end

--------------------------------------------------------------------------------
-- Words
--------------------------------------------------------------------------------

--- "just now", "12 min ago", "3 h ago", "2 days ago". Nil if unknown.
function MapMarkers.Ago(when, now)
    when, now = tonumber(when), tonumber(now)
    if not (when and now) then return nil end

    local seconds = math.max(0, now - when)

    if seconds < 60 then return L["just now"] end
    if seconds < 3600 then return L.Format("%d min ago", math.floor(seconds / 60)) end
    if seconds < 86400 then return L.Format("%d h ago", math.floor(seconds / 3600)) end

    local days = math.floor(seconds / 86400)
    return days == 1 and L["yesterday"] or L.Format("%d days ago", days)
end

--- How strongly to draw a spot last gathered at `when`.
function MapMarkers.AlphaFor(when, now)
    when, now = tonumber(when), tonumber(now)
    if not (when and now) then return FADED_ALPHA end

    local age = now - when
    if age <= FRESH then return FRESH_ALPHA end
    if age >= OLD then return FADED_ALPHA end

    local through = (age - FRESH) / (OLD - FRESH)
    return FRESH_ALPHA + (FADED_ALPHA - FRESH_ALPHA) * through
end

--------------------------------------------------------------------------------
-- A marker
--------------------------------------------------------------------------------

local function ShowTooltip(pin)
    local spot = pin.spot
    if not (spot and GameTooltip) then return end

    local group = pin.group
    if group and #group.spots > 1 then return MapMarkers.ShowGroupTooltip(pin, group) end

    pcall(GameTooltip.SetOwner, GameTooltip, pin, "ANCHOR_RIGHT")

    GameTooltip:AddLine(spot.node or L["Node"], Theme.Unpack("accent"))

    local gathers = tonumber(spot.gathers) or 1
    local ago = MapMarkers.Ago(spot.last, ns.Gathering.Clock())
    local line
    if spot.kind == "fish" then
        line = gathers == 1 and L["Fished"] or L.Format("Fished %d times", gathers)
    else
        line = gathers == 1 and L["Gathered"] or L.Format("Gathered %d times", gathers)
    end
    if ago then line = L.Format("%s, last %s", line, ago) end

    GameTooltip:AddLine(line, Theme.Unpack("text"))

    -- When it grows back, from your own returns to spots like it.
    if ns.Respawn then
        local back, known = ns.Respawn:SpotLine(spot, ns.Gathering.Clock())
        if back then GameTooltip:AddLine(back, Theme.Unpack(known and "accent" or "muted")) end
    end

    GameTooltip:Show()
end

--- An item's name: the client's, else the data's; nil while neither knows it.
function MapMarkers.ItemName(id)
    local api = _G.C_Item
    for _, get in ipairs({ type(api) == "table" and api.GetItemNameByID or false,
        type(api) == "table" and api.GetItemInfo or false, _G.GetItemInfo or false }) do
        if type(get) == "function" then
            local ok, name = pcall(get, id)
            if ok and type(name) == "string" and name ~= "" then return name end
        end
    end
    local DB = ns.DB
    local ok, byID = pcall(function() return DB and DB.ByID and DB:ByID() end)
    local item = ok and type(byID) == "table" and byID[id]
    return type(item) == "table" and type(item.name) == "string" and item.name or nil
end

--- A joined pin's hover: the node gathered most there, what the spots gave,
--- how many spots and gathers, and when they grow back.
function MapMarkers.ShowGroupTooltip(pin, group)
    pcall(GameTooltip.SetOwner, GameTooltip, pin, "ANCHOR_RIGHT")

    local fish = group.kind == "fish"
    GameTooltip:AddLine(MapMarkers.GroupNode(group) or L["Node"], Theme.Unpack("accent"))

    for index, entry in ipairs(MapMarkers:GroupItems(group)) do
        if index > TOOLTIP_ITEMS then break end
        local name = MapMarkers.ItemName(entry.id)
        local icon = Theme.ItemIcon(entry.id)
        if name then
            GameTooltip:AddLine(icon and ("|T%s:14:14|t %s"):format(tostring(icon), name) or name,
                Theme.Unpack("text"))
        end
    end

    local gathers, last = 0, nil
    for _, spot in ipairs(group.spots) do
        gathers = gathers + (tonumber(spot.gathers) or 1)
        local when = tonumber(spot.last)
        if when and (not last or when > last) then last = when end
    end
    local line = fish and L.Format("%d spots, fished %d times", #group.spots, gathers)
        or L.Format("%d spots, gathered %d times", #group.spots, gathers)
    local ago = MapMarkers.Ago(last, ns.Gathering.Clock())
    if ago then line = L.Format("%s, last %s", line, ago) end
    GameTooltip:AddLine(line, Theme.Unpack("text"))

    if ns.Respawn and not fish then
        for _, entry in ipairs(ns.Respawn:GroupLines(group.spots, ns.Gathering.Clock(), MapMarkers.GroupNode(group))) do
            GameTooltip:AddLine(entry.text, Theme.Unpack(entry.known and "accent" or "muted"))
        end
    end

    GameTooltip:Show()
end

local function HideTooltip()
    if GameTooltip then GameTooltip:Hide() end
end

--- Hover and the marker's check, shared by both kinds.
local function Complete(pin, size, corner)
    local badge = pin:CreateTexture(nil, "OVERLAY")
    badge:SetSize(math.ceil(size * 0.6), math.ceil(size * 0.6))
    badge:SetPoint("CENTER", pin, corner, 0, 0)
    badge:SetTexture(CHECK)
    pin.badge = badge
    -- Our own pin: the node tooltip (Logic/Respawn.lua) adds nothing to it.
    pin.farmerMarker = true

    if pin.hollow == true then
        -- A minimap marker takes the mouse only on its check, never over
        -- its clear middle: a node grown back in there keeps the game's own
        -- tooltip, and a click there still pings the minimap.
        local hit = CreateFrame("Frame", nil, pin)
        hit:SetAllPoints(badge)
        hit:EnableMouse(true)
        pcall(hit.SetMouseClickEnabled, hit, false)
        hit:SetScript("OnEnter", function() ShowTooltip(pin) end)
        hit:SetScript("OnLeave", HideTooltip)
        pin.hit = hit
    else
        pin:SetScript("OnEnter", ShowTooltip)
        pin:SetScript("OnLeave", HideTooltip)
    end
    pin:Hide()

    return pin
end

-- The minimap's own herb and ore blips are drawn by the minimap itself, as
-- part of its map, and anything an addon puts on the minimap is drawn over
-- that map: there is no layer between the two. So a marker there cannot sit
-- under a live node; it has to leave the node room to show. It is an empty
-- gold frame, four corner brackets round a clear middle wide enough for the
-- game's blip, with the check outside a corner. A node that has grown back
-- shows through the middle, untouched.
local BRACKET = 2

--- A minimap marker: gold corner brackets round an empty middle.
function MapMarkers.CreateFramePin(parent, size)
    local pin = CreateFrame("Frame", nil, parent)
    pin:SetSize(size, size)
    pin:EnableMouse(false)
    pin.hollow = true

    local arm = math.max(3, math.floor(size / 4))
    local r, g, b = Theme.Unpack("accent")
    local corners = {}

    for _, corner in ipairs({ "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT" }) do
        local across = pin:CreateTexture(nil, "ARTWORK")
        across:SetColorTexture(r, g, b, 1)
        across:SetSize(arm, BRACKET)
        across:SetPoint(corner)

        local down = pin:CreateTexture(nil, "ARTWORK")
        down:SetColorTexture(r, g, b, 1)
        down:SetSize(BRACKET, arm)
        down:SetPoint(corner)

        corners[#corners + 1] = across
        corners[#corners + 1] = down
    end

    pin.corners = corners
    return Complete(pin, math.floor(size * 0.7), "TOPRIGHT")
end

--- A world map marker: a greyed, faded node icon in a gold ring, checked.
function MapMarkers.CreatePin(parent, size)
    local pin = CreateFrame("Frame", nil, parent)
    pin:SetSize(size, size)
    pin:EnableMouse(true)
    -- It shows its tooltip under the mouse, but a click goes on to the map:
    -- a herbalist's dozens of markers swallowed the clicks that zoom in or out.
    pcall(pin.SetMouseClickEnabled, pin, false)

    local ring = pin:CreateTexture(nil, "BACKGROUND")
    ring:SetAllPoints(pin)
    ring:SetTexture(ROUND)
    ring:SetVertexColor(Theme.Unpack("accent"))

    local icon = pin:CreateTexture(nil, "ARTWORK")
    local inset = math.max(1, math.floor(size / 8))
    icon:SetPoint("TOPLEFT", inset, -inset)
    icon:SetPoint("BOTTOMRIGHT", -inset, inset)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    MapMarkers.RoundIcon(pin, icon)

    -- How many spots a joined pin stands for, on a small dark disc with a
    -- gold rim at the top right. Hidden on a pin of one.
    local countSize = math.ceil(size * 0.68)
    local countRim = pin:CreateTexture(nil, "OVERLAY", nil, 1)
    countRim:SetSize(countSize, countSize)
    countRim:SetPoint("CENTER", pin, "TOPRIGHT", -1, -1)
    countRim:SetTexture(ROUND)
    countRim:SetVertexColor(Theme.Unpack("accent"))
    local countFill = pin:CreateTexture(nil, "OVERLAY", nil, 2)
    countFill:SetPoint("TOPLEFT", countRim, "TOPLEFT", 1, -1)
    countFill:SetPoint("BOTTOMRIGHT", countRim, "BOTTOMRIGHT", -1, 1)
    countFill:SetTexture(ROUND)
    countFill:SetVertexColor(0.1, 0.08, 0.05)
    local count = Theme.CreateLabel(pin, "small", "accent", "CENTER")
    count:SetPoint("CENTER", countRim, "CENTER", 0, 0)
    pcall(count.SetDrawLayer, count, "OVERLAY", 3)
    countRim:Hide()
    countFill:Hide()
    count:Hide()

    pin.ring, pin.icon = ring, icon
    pin.count, pin.countRim, pin.countFill = count, countRim, countFill
    MapMarkers.Shade(pin, false)

    return Complete(pin, size, "BOTTOMRIGHT")
end

--------------------------------------------------------------------------------
-- What a spot shows
--------------------------------------------------------------------------------

-- Each node or school's name to the id of what it gave most, from your own
-- gathering and fishing records, for spots saved before they kept their
-- item. Laid out once, again only after the spots move.
local function BuildNodeItems()
    local best = {}
    local function Take(name, items, field)
        if type(name) ~= "string" or type(items) ~= "table" then return end
        for itemName, entry in pairs(items) do
            if type(entry) == "table" then
                local id = tonumber(entry.id)
                if not id and ns.Tracker then id = tonumber(ns.Tracker:LookOf(itemName).id) end
                local weight = tonumber(entry[field]) or 0
                local held = best[name]
                if id and (not held or weight > held.weight) then
                    best[name] = { id = id, weight = weight }
                end
            end
        end
    end

    local db = ns.db or {}
    local nodes = type(db.gathering) == "table" and db.gathering.nodes
    for _, entry in pairs(type(nodes) == "table" and nodes or {}) do
        if type(entry) == "table" then Take(entry.node, entry.items, "gathers") end
    end
    local schools = type(db.fishing) == "table" and db.fishing.spots
    for _, entry in pairs(type(schools) == "table" and schools or {}) do
        if type(entry) == "table" then Take(entry.school, entry.items, "casts") end
    end

    local found = {}
    for name, held in pairs(best) do found[name] = held.id end
    return found
end

--- The id of the item a spot's marker shows: the one it gave, else what
--- that node gave you most anywhere, else what the data says it gives.
function MapMarkers:SpotItem(spot)
    local id = tonumber(spot.item)
    if id then return id end
    if type(spot.node) ~= "string" then return nil end

    local version = ns.Gathering.spotsVersion or 0
    if not self.nodeItems or self.nodeItemsAt ~= version then
        self.nodeItems, self.nodeItemsAt = BuildNodeItems(), version
    end
    id = self.nodeItems[spot.node]
    if id then return id end

    if ns.DB and type(ns.DB.ByName) == "function" then
        local ok, byName = pcall(ns.DB.ByName, ns.DB)
        local list = ok and type(byName) == "table" and byName[spot.node]
        for _, entry in ipairs(type(list) == "table" and list or {}) do
            local item = type(entry) == "table" and entry.item
            if type(item) == "table" and tonumber(item.id) then return tonumber(item.id) end
        end
    end
    return nil
end

--- The texture a spot's marker shows.
function MapMarkers:IconFor(spot)
    local id = self:SpotItem(spot)
    return (id and Theme.ItemIcon(id)) or ICONS[spot.kind] or ICONS.herb
end

--- What a joined pin's spots gave, the item gathered most there first:
--- { { id, gathers } }. Each spot counts its own gathers for its item.
function MapMarkers:GroupItems(group)
    local weights, order = {}, {}
    for _, spot in ipairs(group.spots) do
        local id = self:SpotItem(spot)
        if id then
            if not weights[id] then order[#order + 1] = id end
            weights[id] = (weights[id] or 0) + (tonumber(spot.gathers) or 1)
        end
    end
    local list = {}
    for _, id in ipairs(order) do list[#list + 1] = { id = id, gathers = weights[id] } end
    table.sort(list, function(a, b)
        if a.gathers ~= b.gathers then return a.gathers > b.gathers end
        return a.id < b.id
    end)
    return list
end

--- The texture a joined pin shows: the item its spots gave most.
function MapMarkers:GroupIcon(group)
    if #group.spots == 1 then return self:IconFor(group.spots[1]) end
    for _, entry in ipairs(self:GroupItems(group)) do
        local icon = Theme.ItemIcon(entry.id)
        if icon then return icon end
    end
    return ICONS[group.kind] or ICONS.herb
end

--- The node a joined pin is named for: the one gathered most there.
function MapMarkers.GroupNode(group)
    local times, best = {}, nil
    for _, spot in ipairs(group.spots) do
        local node = spot.node
        if node then
            times[node] = (times[node] or 0) + (tonumber(spot.gathers) or 1)
            if not best or times[node] > times[best] or (times[node] == times[best] and node < best) then
                best = node
            end
        end
    end
    return best
end

--- A single spot as a pin's group of one.
function MapMarkers.Single(spot)
    return { spots = { spot }, kind = spot.kind, x = spot.x, y = spot.y }
end

--- Join spots of one kind that would sit on each other on screen. `width`
--- and `height` are the canvas's, `scale` how far it is zoomed: a spot's
--- place on screen is x * width * scale. Each pin keeps the first spot that
--- started it as its anchor, so a long line of spots never joins end to end.
--- Spots of different kinds never join. Returns { { spots, kind, x, y } },
--- x and y the middle of its spots.
function MapMarkers.Group(spots, width, height, scale, reach)
    reach = reach or JOIN_PIXELS
    local across, down = width * scale, height * scale
    local limit = reach * reach
    local groups = {}

    for _, spot in ipairs(spots) do
        local joined
        for _, group in ipairs(groups) do
            if group.kind == spot.kind then
                local dx = (spot.x - group.ax) * across
                local dy = (spot.y - group.ay) * down
                if dx * dx + dy * dy < limit then
                    joined = group
                    break
                end
            end
        end
        if joined then
            joined.spots[#joined.spots + 1] = spot
        else
            groups[#groups + 1] = { spots = { spot }, kind = spot.kind, ax = spot.x, ay = spot.y }
        end
    end

    for _, group in ipairs(groups) do
        local sx, sy = 0, 0
        for _, spot in ipairs(group.spots) do sx, sy = sx + spot.x, sy + spot.y end
        group.x, group.y = sx / #group.spots, sy / #group.spots
    end
    return groups
end

--- Greyed while the node is still growing back, full color once it should
--- be there.
function MapMarkers.Shade(pin, back)
    if not pin.icon then return end
    pin.back = back and true or false
    pcall(pin.icon.SetDesaturated, pin.icon, not back)
    if back then
        pin.icon:SetVertexColor(1, 1, 1)
    else
        pin.icon:SetVertexColor(GREY_TINT, GREY_TINT, GREY_TINT)
    end
end

--- Should the node at this marker be back by `now`?
function MapMarkers.IsBack(pin, now)
    now = tonumber(now)
    local at = pin.backAt
    return type(at) == "number" and now ~= nil and now >= at
end

--- How strongly to draw a marker: a node that should be back at full
--- strength, the rest faded with age.
function MapMarkers.PinAlpha(pin, now)
    if pin.back == true then return BACK_ALPHA end
    return MapMarkers.AlphaFor(pin.newest or (pin.spot and pin.spot.last), now)
end

--- Point a marker at a spot, or on the world map at a joined pin's group
--- (MapMarkers.Group). A joined pin turns to color once any node it stands
--- for should be back, is as strong as its newest gather otherwise, and
--- shows how many spots.
function MapMarkers.Dress(pin, spot, now)
    local group = type(spot.spots) == "table" and spot or MapMarkers.Single(spot)
    pin.group = group
    pin.spot = group.spots[1]
    pin.newest = nil
    if pin.hollow ~= true then
        local backAt, newest = nil, nil
        for _, member in ipairs(group.spots) do
            local at = ns.Respawn and ns.Respawn:BackAt(member) or nil
            if at and (not backAt or at < backAt) then backAt = at end
            local when = tonumber(member.last)
            if when and (not newest or when > newest) then newest = when end
        end
        pin.backAt, pin.newest = backAt, newest
        pin.icon:SetTexture(MapMarkers:GroupIcon(group))
        MapMarkers.Shade(pin, MapMarkers.IsBack(pin, now))

        local many = #group.spots > 1
        if pin.count then
            pin.count:SetText(many and tostring(#group.spots) or "")
            pin.count:SetShown(many)
            pin.countRim:SetShown(many)
            pin.countFill:SetShown(many)
        end
    end
    pin:SetAlpha(MapMarkers.PinAlpha(pin, now))
end

--- A pool of markers under one parent, reused from one redraw to the next.
local function Pool(parent, size, create)
    return { parent = parent, size = size, create = create or MapMarkers.CreatePin,
        pins = {}, used = 0 }
end

local function Acquire(pool)
    pool.used = pool.used + 1
    local pin = pool.pins[pool.used]

    if not pin then
        pin = pool.create(pool.parent, pool.size)
        pool.pins[pool.used] = pin
    end

    return pin
end

--- Start a redraw. Markers are reused in place rather than hidden and shown
--- again, so one under the mouse keeps its tooltip while the minimap turns.
local function Begin(pool)
    pool.used = 0
end

--- End a redraw: put away whatever this one did not use.
local function Finish(pool)
    for index = pool.used + 1, #pool.pins do pool.pins[index]:Hide() end
end

local function Release(pool)
    Begin(pool)
    Finish(pool)
end

--------------------------------------------------------------------------------
-- World map
--------------------------------------------------------------------------------

--- The world map's canvas, the map it shows, and how far it is zoomed.
-- Frame levels over the world map's canvas and the minimap: over the kill
-- heat glow (UI/Heat.lua), under the Grind tab's pins.
MapMarkers.WORLD_ABOVE = 3
MapMarkers.MINIMAP_ABOVE = 2

--- The frame level our world map layers count up from: the canvas's own,
--- or, on a zone map, the parts you have explored, which the game lays
--- over the map's art as pins of their own. The glow sat at their level
--- and was drawn under them, so it showed on Kalimdor, which has none, and
--- not on Ashenvale (2026-10-18). Read from those pins, else from the
--- level the map keeps for them; never lower than the canvas.
function MapMarkers.BaseLevel(canvas)
    local okLevel, level = pcall(canvas.GetFrameLevel, canvas)
    level = okLevel and tonumber(level) or 1
    local map = _G.WorldMapFrame
    if type(map) ~= "table" then return level end

    local top
    if type(map.EnumeratePinsByTemplate) == "function" then
        -- A pool's active pins, as pairs gives them: the pin is the key or
        -- the value, whichever is a frame.
        local ok, step, state, key = pcall(map.EnumeratePinsByTemplate, map, "MapExplorationPinTemplate")
        if ok and type(step) == "function" then
            for _ = 1, 64 do
                local okNext, nextKey, value = pcall(step, state, key)
                if not okNext or nextKey == nil then break end
                key = nextKey
                local pin = type(nextKey) == "table" and nextKey or value
                if type(pin) == "table" and type(pin.GetFrameLevel) == "function" then
                    local okPin, pinLevel = pcall(pin.GetFrameLevel, pin)
                    pinLevel = okPin and tonumber(pinLevel)
                    if pinLevel and (not top or pinLevel > top) then top = pinLevel end
                end
            end
        end
    end
    if not top and type(map.GetPinFrameLevelsManager) == "function" then
        local ok, manager = pcall(map.GetPinFrameLevelsManager, map)
        if ok and type(manager) == "table" and type(manager.GetValidFrameLevel) == "function" then
            local okKept, kept = pcall(manager.GetValidFrameLevel, manager, "PIN_FRAME_LEVEL_MAP_EXPLORATION")
            top = okKept and tonumber(kept) or nil
        end
    end
    -- The art is one over the canvas; explored parts sit at or over it.
    if top and top - 1 > level then return top - 1 end
    return level
end

function MapMarkers:WorldView()
    local map = _G.WorldMapFrame
    if type(map) ~= "table" then return nil end

    local okShown, shown = pcall(map.IsShown, map)
    if not (okShown and shown) then return nil end

    local canvas
    if type(map.GetCanvas) == "function" then
        local ok, value = pcall(map.GetCanvas, map)
        if ok then canvas = value end
    end
    canvas = canvas or (map.ScrollContainer and map.ScrollContainer.Child)
    if type(canvas) ~= "table" then return nil end

    local mapID
    if type(map.GetMapID) == "function" then
        local ok, value = pcall(map.GetMapID, map)
        if ok then mapID = ns.Harvest.ReadableNumber(value) end
    end
    if not mapID then return nil end

    local scale = 1
    local scroll = map.ScrollContainer
    if type(scroll) == "table" and type(scroll.GetCanvasScale) == "function" then
        local ok, value = pcall(scroll.GetCanvasScale, scroll)
        scale = ok and ns.Harvest.ReadableNumber(value) or 1
    end
    if scale <= 0 then scale = 1 end

    local okW, width = pcall(canvas.GetWidth, canvas)
    local okH, height = pcall(canvas.GetHeight, canvas)
    width = okW and ns.Harvest.ReadableNumber(width) or nil
    height = okH and ns.Harvest.ReadableNumber(height) or nil
    if not (width and height and width > 0 and height > 0) then return nil end

    return { canvas = canvas, mapID = mapID, scale = scale, width = width, height = height }
end

function MapMarkers:DrawWorld()
    local view = self:WorldView()

    if not view then
        -- Put away once: the driver asks ten times a second while the map
        -- is closed, and pins already hidden have nothing to redo.
        local pool = self.worldPool
        if pool and pool.used > 0 then Release(pool) end
        self.worldKey = nil
        return
    end

    local _, kindStamp = self:ShownKinds()
    local key = ("%d:%s:%s:%s:%d:%s"):format(view.mapID, view.scale, view.width,
        view.height, ns.Gathering.spotsVersion or 0, kindStamp)
    local on = MapMarkers.WorldOn()

    if key == self.worldKey and self.worldOn == on then
        self:WakeWorld()
        return
    end

    if not self.worldPool or self.worldPool.parent ~= view.canvas then
        if self.worldPool then Release(self.worldPool) end
        self.worldPool = Pool(view.canvas, WORLD_SIZE)
    end

    local pool = self.worldPool
    Begin(pool)

    -- Whatever happens below, nothing left over from the last redraw stays.
    local ok, err = true, nil
    if on then ok, err = pcall(self.PlaceWorld, self, pool, view) end
    Finish(pool)
    -- Kept only after a clean draw, so a failed one is tried again.
    self.worldKey, self.worldOn = ok and key or nil, on
    if not ok then error(err, 0) end
end

function MapMarkers:PlaceWorld(pool, view)
    local now = ns.Gathering.Clock()
    -- Low among the canvas's own pins: whatever else the map shows, the
    -- game's or another addon's, draws over a spot you have already taken.
    -- Just over the kill heat glow (HeatUI.WORLD_ABOVE), so a node shows on it.
    local level = MapMarkers.BaseLevel(view.canvas) + MapMarkers.WORLD_ABOVE

    -- Same size on screen at any zoom: shrink the marker as the canvas grows,
    -- and place it in its own, smaller, units.
    local scale = 1 / view.scale

    local groups = MapMarkers.Group(self:SpotsOn(view.mapID), view.width, view.height, view.scale)
    for _, group in ipairs(groups) do
        local pin = Acquire(pool)
        MapMarkers.Dress(pin, group, now)
        pin:SetScale(scale)
        pin:SetFrameLevel(level)
        pin:ClearAllPoints()
        pin:SetPoint("CENTER", view.canvas, "TOPLEFT",
            group.x * view.width / scale, -group.y * view.height / scale)
        pin:Show()
    end
end

--- Once a second, on the world map markers already placed: color in the
--- ones whose node should now be back, and move the age fade. Nothing is
--- placed again.
function MapMarkers:WakeWorld()
    local pool = self.worldPool
    if not pool or pool.used == 0 then return end

    local now = ns.Gathering.Clock()
    if now == self.wokeAt then return end
    self.wokeAt = now

    for index = 1, pool.used do
        local pin = pool.pins[index]
        if pin.spot then
            if pin.back ~= true and MapMarkers.IsBack(pin, now) then MapMarkers.Shade(pin, true) end
            pin:SetAlpha(MapMarkers.PinAlpha(pin, now))
        end
    end
end

--------------------------------------------------------------------------------
-- Minimap
--------------------------------------------------------------------------------

-- How many yards from the centre to the edge of the minimap, by zoom level,
-- for a client without Minimap:GetViewRadius. The game's own figures.
local OUTDOOR_RADIUS = { [0] = 233.33, 200, 166.67, 133.33, 100, 66.67 }
local INDOOR_RADIUS = { [0] = 150, 120, 90, 60, 40, 25 }

--- Yards from the minimap's centre to its edge.
function MapMarkers.MinimapRadius()
    if not Minimap then return nil end

    if type(Minimap.GetViewRadius) == "function" then
        local ok, radius = pcall(Minimap.GetViewRadius, Minimap)
        radius = ok and ns.Harvest.ReadableNumber(radius) or nil
        if radius and radius > 0 then return radius end
    end

    local zoom = 0
    if type(Minimap.GetZoom) == "function" then
        local ok, value = pcall(Minimap.GetZoom, Minimap)
        zoom = ok and ns.Harvest.ReadableNumber(value) or 0
    end

    local indoors = false
    if type(IsIndoors) == "function" then
        local ok, value = pcall(IsIndoors)
        indoors = ok and value == true
    end

    local radii = indoors and INDOOR_RADIUS or OUTDOOR_RADIUS
    return radii[zoom] or radii[0]
end

--- Does the minimap turn with you, and which way are you facing (radians)?
local function Facing()
    if type(GetCVar) ~= "function" then return nil end

    local ok, rotate = pcall(GetCVar, "rotateMinimap")
    if not (ok and rotate == "1") then return nil end

    if type(GetPlayerFacing) ~= "function" then return nil end
    local gotFacing, facing = pcall(GetPlayerFacing)
    return gotFacing and ns.Harvest.ReadableNumber(facing) or nil
end

--- Is the minimap square? Some UI addons make it so.
local function IsSquare()
    if type(GetMinimapShape) ~= "function" then return false end
    local ok, shape = pcall(GetMinimapShape)
    return ok and shape == "SQUARE"
end

--- Where a spot sits on the minimap, in pixels from its centre, or nil when
--- it is off the edge. `player` is { mapID, x, y }.
function MapMarkers.MinimapOffset(spot, player, width, height, radius, facing, square, half)
    -- Yards east and north of you. Map y runs down the map, which is south.
    local east = (spot.x - player.x) * width
    local north = (player.y - spot.y) * height

    -- A turning minimap turns the world so that ahead of you is up.
    if facing then
        local c, s = math.cos(facing), math.sin(facing)
        east, north = east * c + north * s, north * c - east * s
    end

    -- Kept a marker's width inside the rim, so it never hangs off it.
    local reach = radius * 0.94

    if square then
        if math.abs(east) > reach or math.abs(north) > reach then return nil end
    elseif east * east + north * north > reach * reach then
        return nil
    end

    return east / radius * half, north / radius * half, east * east + north * north
end

--- What the minimap markers depend on, as one string: where you stand and
--- face, the minimap's zoom, shape and size, and the spots. Standing still,
--- nothing in it changes, so the markers are left where they are rather than
--- placed again ten times a second. The age fade, which moves once a second,
--- is not in it: it used to be, and every saved spot on the map was gathered
--- up, sorted and placed again once a second even standing still, a hitch a
--- player saw as a jerky craft bar (2026-10-09). FadeMinimap moves the fade
--- on the markers already placed instead.
function MapMarkers:MinimapKey()
    if not MapMarkers.MinimapOn() then return "off" end

    local mapID, px, py = ns.Harvest:PlayerMapPosition()
    if not mapID then return "nowhere" end

    local okWidth, size = pcall(Minimap.GetWidth, Minimap)
    size = okWidth and ns.Harvest.ReadableNumber(size) or nil

    local _, kindStamp = self:ShownKinds()
    return ("%d|%s|%s|%s|%s|%s|%s|%s|%s"):format(mapID, tostring(px), tostring(py),
        tostring(Facing()), tostring(IsSquare()), tostring(MapMarkers.MinimapRadius()),
        tostring(size), tostring(ns.Gathering.spotsVersion or 0), kindStamp)
end

--- The spots on `mapID` this character shows (MineOnly), kept until the
--- spots or the skills change.
function MapMarkers:SpotsOn(mapID)
    local all = ns.Gathering:Spots()
    local version = ns.Gathering.spotsVersion or 0
    local kinds, stamp = self:ShownKinds()
    local kept = self.spotsKept
    if kept and kept.map == mapID and kept.version == version and kept.all == all
        and kept.stamp == stamp then
        return kept.spots
    end
    local spots = {}
    for _, spot in ipairs(ns.Gathering:SpotsOn(mapID)) do
        if MapMarkers.KindShows(spot.kind, kinds) then spots[#spots + 1] = spot end
    end
    self.spotsKept = { map = mapID, version = version, all = all, stamp = stamp, spots = spots }
    return spots
end

function MapMarkers:DrawMinimap()
    if not Minimap then return end

    local key = self:MinimapKey()
    if key == self.minimapKey then
        self:FadeMinimap()
        return
    end

    self.minimapPool = self.minimapPool or Pool(Minimap, MINIMAP_SIZE, MapMarkers.CreateFramePin)
    local pool = self.minimapPool
    Begin(pool)

    -- Whatever happens below, nothing left over from the last redraw stays.
    local ok, err = pcall(self.PlaceMinimap, self, pool)
    Finish(pool)
    -- Kept only after a clean draw, so a failed one is tried again.
    self.minimapKey = ok and key or nil
    if not ok then error(err, 0) end
end

--- Move the age fade on the minimap markers already placed, once a second.
function MapMarkers:FadeMinimap()
    local pool = self.minimapPool
    if not pool or pool.used == 0 then return end

    local now = ns.Gathering.Clock()
    if now == self.fadedAt then return end
    self.fadedAt = now

    for index = 1, pool.used do
        local pin = pool.pins[index]
        if pin.spot then pin:SetAlpha(MapMarkers.PinAlpha(pin, now)) end
    end
end

function MapMarkers:PlaceMinimap(pool)
    if not MapMarkers.MinimapOn() then return end

    local mapID, px, py = ns.Harvest:PlayerMapPosition()
    if not mapID then return end

    local spots = self:SpotsOn(mapID)
    if #spots == 0 then return end

    local width, height = ns.Gathering.MapSize(mapID)
    local radius = MapMarkers.MinimapRadius()
    if not (width and radius) then return end

    local okWidth, size = pcall(Minimap.GetWidth, Minimap)
    size = okWidth and ns.Harvest.ReadableNumber(size) or nil
    if not size then return end

    local player = { x = px, y = py }
    local facing, square = Facing(), IsSquare()

    local near = {}
    for _, spot in ipairs(spots) do
        local ox, oy, distance = MapMarkers.MinimapOffset(spot, player, width, height,
            radius, facing, square, size / 2)
        if ox then near[#near + 1] = { spot = spot, x = ox, y = oy, distance = distance } end
    end

    table.sort(near, function(a, b) return a.distance < b.distance end)

    local now = ns.Gathering.Clock()
    -- Just above the minimap and the kill heat glow, so another addon's pins
    -- draw over these.
    local okLevel, level = pcall(Minimap.GetFrameLevel, Minimap)
    level = (okLevel and tonumber(level) or 1) + MapMarkers.MINIMAP_ABOVE

    for index = 1, math.min(#near, MINIMAP_MAX) do
        local entry = near[index]
        local pin = Acquire(pool)
        MapMarkers.Dress(pin, entry.spot, now)
        pin:SetFrameLevel(level)
        pin:ClearAllPoints()
        pin:SetPoint("CENTER", Minimap, "CENTER", entry.x, entry.y)
        pin:Show()
    end
end

--------------------------------------------------------------------------------
-- Redrawing
--------------------------------------------------------------------------------

--- Draw both again: after a gather, a switch, or a clear.
function MapMarkers:Refresh()
    if not ns.db then return end
    self.worldKey = nil
    self.minimapKey = nil

    local ok, err = pcall(self.DrawWorld, self)
    if not ok then ns.Debug("world map markers:", tostring(err)) end

    ok, err = pcall(self.DrawMinimap, self)
    if not ok then ns.Debug("minimap markers:", tostring(err)) end
end

--- One tick of the driver: the world map when it changes, the minimap as you
--- move.
function MapMarkers:Step(elapsed)
    self.since = (self.since or 0) + (elapsed or 0)
    if self.since < MINIMAP_STEP then return end
    self.since = 0

    local ok, err = pcall(self.DrawWorld, self)
    if not ok then ns.Debug("world map markers:", tostring(err)) end

    ok, err = pcall(self.DrawMinimap, self)
    if not ok then ns.Debug("minimap markers:", tostring(err)) end
end

function MapMarkers:OnEnable()
    local driver = CreateFrame("Frame", nil, UIParent)
    driver:SetScript("OnUpdate", function(_, elapsed) MapMarkers:Step(elapsed) end)
    driver:Show()
    self.driver = driver

    -- A skill learned or dropped shows or hides its spots at once.
    ns.RegisterEvent(self, "SKILL_LINES_CHANGED", function()
        MapMarkers.known = nil
        MapMarkers:Refresh()
    end)
end

--------------------------------------------------------------------------------
-- Commands
--------------------------------------------------------------------------------

local function OnOff(on) return on and L["on"] or L["off"] end

local function Status()
    ns.Print(L.Format("gathered-node markers: world map %s, minimap %s. %s marked.",
        Util.Colored("accent", OnOff(MapMarkers.WorldOn())),
        Util.Colored("accent", OnOff(MapMarkers.MinimapOn())),
        Util.Plural(#ns.Gathering:Spots(), L["spot"], L["spots"])))
    ns.Print(L.Format("Only your professions: %s.", Util.Colored("accent", OnOff(MapMarkers.MineOnly()))))
    ns.PrintRaw(Util.Colored("muted",
        "  /farm markers on|off, /farm markers map on|off, /farm markers minimap on|off, /farm markers mine on|off"))
end

ns.RegisterCommand("markers", L["gathered herb and ore markers on the maps (on, off, map, minimap)"], function(rest)
    local argument = Util.Trim(rest):lower()
    local which, state = argument:match("^(%S+)%s*(%S*)$")

    if argument == "" then
        Status()
        return
    end

    if argument == "clear" then
        ns.Print(L.Format("this removes all %s from your maps, for good. Your gathering counts stay. Type /farm markers clear confirm to do it.",
            Util.Plural(#ns.Gathering:Spots(), L["marker"], L["markers"])))
        return
    end

    if argument == "clear confirm" then
        local count = ns.Gathering:ClearSpots()
        ns.Print(L.Format("%s cleared from your maps.", Util.Plural(count, L["marker"], L["markers"])))
        return
    end

    if which == "on" or which == "off" then
        MapMarkers:SetWorld(which == "on")
        MapMarkers:SetMinimap(which == "on")
    elseif (which == "map" or which == "world") and (state == "on" or state == "off") then
        MapMarkers:SetWorld(state == "on")
    elseif which == "minimap" and (state == "on" or state == "off") then
        MapMarkers:SetMinimap(state == "on")
    elseif which == "mine" and (state == "on" or state == "off") then
        MapMarkers:SetMineOnly(state == "on")
    end

    Status()
end)
