-- Blackthornes Farmer -- UI/SeeThrough.lua
-- See-through for the panels that stay on screen while you play, one setting
-- each (the owner asked 2026-10-16, after the Kills & Loot panel got it):
-- the goals panel, Where to farm, the rank-up board, the run recap and the
-- XP bar. It works as the Kills & Loot panel's does (UI/Tracker.lua, which
-- keeps its own): the panel's dark glass thins out so the world shows
-- through, every word gets a black shadow, and the glass comes back while
-- the mouse is on the panel.
--
-- Each panel's level is saved account wide, 0 (off, the default) to 3,
-- Some, More or Most clear, an index into LEVELS: `goalsSeeThrough`,
-- `goalSpotsSeeThrough`, `rankUpSeeThrough`, `recapSeeThrough` and
-- `xpBarSeeThrough`. Never rename them. Only each panel's own textures are
-- faded (texture SetAlpha), so no game frame is touched; gold edges, icons,
-- bars and glows stay as they are. A shadow a label already had is put back
-- when it is turned off.

local _, ns = ...
local L = ns.L

local SeeThrough = ns.NewModule("SeeThrough")

--- How much of each piece of glass stays, by level: Some, More, Most clear
--- (the same as the Kills & Loot panel's).
SeeThrough.LEVELS = { 0.5, 0.3, 0.15 }
--- The words the command takes, by level from 0.
SeeThrough.WORDS = { [0] = "off", "some", "more", "most" }
--- How often the mouse is looked for while see-through, in seconds.
SeeThrough.LOOK = 0.1
--- How long the glass takes to come back or go, in seconds.
SeeThrough.FADE = 0.2

--- The panels, by the word the command takes for each.
SeeThrough.PANELS = {
    goals = { key = "goalsSeeThrough", name = L["Goals panel"] },
    places = { key = "goalSpotsSeeThrough", name = L["Where to farm"] },
    rankup = { key = "rankUpSeeThrough", name = L["Your top 15"] },
    recap = { key = "recapSeeThrough", name = L["Run recap"] },
    xpbar = { key = "xpBarSeeThrough", name = L["XP bar"] },
}
SeeThrough.ORDER = { "goals", "places", "rankup", "recap", "xpbar" }

-- Each panel's state: { frame, parts, watch, shown, solid }.
SeeThrough.states = {}

--- The panel's level, 0 (off) to #LEVELS.
function SeeThrough:Level(id)
    local panel = SeeThrough.PANELS[id]
    local level = panel and ns.db and tonumber(ns.db[panel.key])
    if not level or not SeeThrough.LEVELS[level] then return 0 end
    return level
end

function SeeThrough:On(id)
    return self:Level(id) > 0
end

local function State(id)
    local state = SeeThrough.states[id]
    if not state then
        state = { parts = {}, shown = 1 }
        SeeThrough.states[id] = state
    end
    return state
end

--------------------------------------------------------------------------------
-- Shadows under the words
--------------------------------------------------------------------------------

-- The shadow each label had before, so turning it off puts that back.
local before = setmetatable({}, { __mode = "k" })

local function ShadeText(region, on)
    if type(region) ~= "table" or type(region.GetObjectType) ~= "function" then return end
    local ok, kind = pcall(region.GetObjectType, region)
    if not ok or kind ~= "FontString" then return end
    if on then
        if not before[region] then
            local okOffset, x, y = pcall(region.GetShadowOffset, region)
            local okColor, r, g, b, a = pcall(region.GetShadowColor, region)
            before[region] = {
                x = okOffset and tonumber(x) or 0, y = okOffset and tonumber(y) or 0,
                r = okColor and tonumber(r) or 0, g = okColor and tonumber(g) or 0,
                b = okColor and tonumber(b) or 0, a = okColor and tonumber(a) or 1,
            }
        end
        pcall(region.SetShadowColor, region, 0, 0, 0, 1)
        pcall(region.SetShadowOffset, region, 1, -1)
    else
        local was = before[region]
        if not was then return end
        before[region] = nil
        pcall(region.SetShadowColor, region, was.r, was.g, was.b, was.a)
        pcall(region.SetShadowOffset, region, was.x, was.y)
    end
end

--- A black shadow under every word in `frame` and the frames inside it.
function SeeThrough.ShadeAll(frame, on)
    if type(frame) ~= "table" then return end
    if type(frame.GetRegions) == "function" then
        local regions = { pcall(frame.GetRegions, frame) }
        for i = 2, #regions do ShadeText(regions[i], on) end
    end
    if type(frame.GetChildren) == "function" then
        local children = { pcall(frame.GetChildren, frame) }
        for i = 2, #children do SeeThrough.ShadeAll(children[i], on) end
    end
end

--------------------------------------------------------------------------------
-- The glass
--------------------------------------------------------------------------------

--- Keep a piece of the panel's glass, to thin out while see-through.
--- `floor` is the least of it that ever stays (a picked row's gold).
function SeeThrough:AddGlass(id, texture, floor)
    if not texture then return texture end
    local state = State(id)
    state.parts[#state.parts + 1] = { texture = texture, floor = floor or 0 }
    -- A line made while the panel is see-through starts that way.
    if state.shown < 1 then
        pcall(texture.SetAlpha, texture, math.max(state.shown, floor or 0))
    end
    return texture
end

--- A row or card the panel made after it was built: its words get the
--- shadow too while the panel is see-through.
function SeeThrough:Grew(id, frame)
    if self:On(id) then SeeThrough.ShadeAll(frame, true) end
end

--- Every piece of the panel's glass at `shown` (1 is the usual dark glass).
function SeeThrough:SetGlass(id, shown)
    local state = State(id)
    state.shown = shown
    for _, part in ipairs(state.parts) do
        pcall(part.texture.SetAlpha, part.texture, math.max(shown, part.floor))
    end
end

local function MouseOn(state)
    local frame = state.frame
    if not frame or type(frame.IsMouseOver) ~= "function" then return false end
    local ok, over = pcall(frame.IsMouseOver, frame)
    return ok and over == true
end

--- Blend the glass toward solid (mouse on the panel) or see-through.
function SeeThrough:Fade(id, solid)
    local state = State(id)
    local level = self:Level(id)
    local target = (solid or level == 0) and 1 or SeeThrough.LEVELS[level]
    state.solid = solid
    ns.Motion:Blend(state, "seeThrough", target, SeeThrough.FADE,
        function(value) SeeThrough:SetGlass(id, value) end)
end

--- Hand the panel over, once it is built: a watcher that brings the glass
--- back under the mouse runs only while the panel shows and is see-through.
function SeeThrough:Attach(id, frame)
    if not frame then return end
    local state = State(id)
    state.frame = frame
    state.watch = CreateFrame("Frame", nil, frame)
    state.watch.wait = 0
    ns.Motion:SetValue(state, "seeThrough", 1)
    self:Apply(id)
end

--- Put the panel in step with its setting: the glass, the shadows and the
--- mouse watcher.
function SeeThrough:Apply(id)
    local state = SeeThrough.states[id]
    if not state or not state.frame or not state.watch then return end
    local on = self:On(id)

    SeeThrough.ShadeAll(state.frame, on)
    if on then
        self:Fade(id, MouseOn(state))
        state.watch:SetScript("OnUpdate", function(watch, elapsed)
            watch.wait = watch.wait - (tonumber(elapsed) or 0)
            if watch.wait > 0 then return end
            watch.wait = SeeThrough.LOOK
            local over = MouseOn(state)
            if over ~= state.solid then SeeThrough:Fade(id, over) end
        end)
    else
        state.watch:SetScript("OnUpdate", nil)
        state.solid = nil
        ns.Motion:Stop(state, "seeThrough")
        ns.Motion:SetValue(state, "seeThrough", 1)
        self:SetGlass(id, 1)
    end
end

--- Set the panel's level, 0 (off) to #LEVELS.
function SeeThrough:Set(id, level)
    local panel = SeeThrough.PANELS[id]
    level = tonumber(level)
    if not panel or not level or (level ~= 0 and not SeeThrough.LEVELS[level]) then return false end
    ns.db[panel.key] = level
    self:Apply(id)
    return true
end

--------------------------------------------------------------------------------
-- The command
--------------------------------------------------------------------------------

--- The levels' names as a player reads them, from 0 (off).
function SeeThrough.Names()
    return { [0] = L["Off"], L["Some"], L["More"], L["Most"] }
end

local function Say(id)
    local panel = SeeThrough.PANELS[id]
    ns.Print(L.Format("%s transparent: %s.", panel.name, SeeThrough.Names()[SeeThrough:Level(id)]))
end

local function Command(rest)
    local id, word = (rest or ""):lower():match("^(%a*)%s*(%a*)")
    if not SeeThrough.PANELS[id] then
        for _, each in ipairs(SeeThrough.ORDER) do Say(each) end
        ns.Print(L["Type /farm transparent goals, places, rankup, recap or xpbar, then off, some, more or most."])
        return
    end
    if word == "" then
        -- Alone, it turns the panel on at More, or off.
        SeeThrough:Set(id, SeeThrough:On(id) and 0 or 2)
    elseif word == "on" then
        SeeThrough:Set(id, SeeThrough:On(id) and SeeThrough:Level(id) or 2)
    else
        local level
        for index = 0, #SeeThrough.LEVELS do
            if SeeThrough.WORDS[index] == word then level = index end
        end
        if not level then
            ns.Print(L["Type off, some, more or most."])
            return
        end
        SeeThrough:Set(id, level)
    end
    Say(id)
end

-- Players see "Transparent" (the owner, 2026-10-16); the older word still
-- works but is left out of the help list.
ns.RegisterCommand("transparent", L["lets the world show through a panel: goals, places, rankup, recap or xpbar, then off, some, more or most"], Command)
ns.commands.seethrough = ns.commands.transparent
