-- Blackthornes Farmer -- Core/Init.lua
-- Namespace, module registry, event dispatch and slash-command routing.
--
-- Same shape as Blackthornes Tradeskills, and for the same reason: Ace3 and
-- LibStub are not known to be ported to WoW: Forever, so the framework is ours
-- and is small enough to read in one sitting.

local ADDON_NAME, ns = ...

_G.BlackthornesFarmer = ns

ns.ADDON_NAME = ADDON_NAME

local function GetMeta(field)
    if C_AddOns and C_AddOns.GetAddOnMetadata then
        local ok, value = pcall(C_AddOns.GetAddOnMetadata, ADDON_NAME, field)
        if ok then return value end
    end
    if type(_G.GetAddOnMetadata) == "function" then
        local ok, value = pcall(_G.GetAddOnMetadata, ADDON_NAME, field)
        if ok then return value end
    end
    return nil
end

-- The TOC carries @project-version@, which the release packager rewrites to
-- the tag it is building, "v0.2.0" say. Running straight from the repository
-- there is no packager, so the keyword arrives unsubstituted and is shown as
-- "dev".
local function ReadVersion()
    local value = GetMeta("Version")
    if type(value) ~= "string" or value == "" then return "0.0.0" end
    if value:find("@", 1, true) then return "dev" end
    -- Tags start with a "v"; the version itself does not.
    return (value:gsub("^[vV]", ""))
end

ns.VERSION = ReadVersion()

--- The version as players see it: "v0.2.0", or "dev build" from a checkout.
function ns.VersionLabel()
    if ns.VERSION == "dev" then return "dev build" end
    return "v" .. ns.VERSION
end

--------------------------------------------------------------------------------
-- Output
--------------------------------------------------------------------------------

ns.COLORS = {
    accent = "ffc8a44d",
    good   = "ff4fd18b",
    -- Theme's muted (#8B919B), so grey text in chat and on the windows is
    -- the same grey.
    muted  = "ff8b919b",
    -- Theme's dim (#6B707B), for the " / " between a zone and its landmark:
    -- missing here, it came out in the bright text colour.
    dim    = "ff6b707b",
    warn   = "ffe8c15a",
    text   = "ffe6e8ec",
}

local PREFIX = "|c" .. ns.COLORS.accent .. "Farmer|r "

local function Join(...)
    local n = select("#", ...)
    if n == 0 then return "" end

    local parts = {}
    for i = 1, n do
        parts[i] = tostring((select(i, ...)))
    end
    return table.concat(parts, " ")
end

function ns.Print(...)
    local frame = DEFAULT_CHAT_FRAME
    if frame then
        frame:AddMessage(PREFIX .. Join(...))
    end
end

-- Raw line with no prefix, for multi-line reports where the prefix is noise.
function ns.PrintRaw(...)
    local frame = DEFAULT_CHAT_FRAME
    if frame then
        frame:AddMessage(Join(...))
    end
end

function ns.Debug(...)
    if ns.db and ns.db.debug then
        ns.PrintRaw("|c" .. ns.COLORS.muted .. "Farmer debug|r " .. Join(...))
    end
end

function ns.Warn(...)
    ns.Print("|c" .. ns.COLORS.warn .. Join(...) .. "|r")
end

--------------------------------------------------------------------------------
-- Module registry
--------------------------------------------------------------------------------

ns.modules = {}
ns.moduleOrder = {}

local moduleProto = {}
moduleProto.__index = moduleProto

function moduleProto:RegisterEvent(event, fn)
    return ns.RegisterEvent(self, event, fn or self[event])
end

function moduleProto:UnregisterEvent(event)
    return ns.UnregisterEvent(self, event)
end

function ns.NewModule(name)
    assert(type(name) == "string", "module name must be a string")
    assert(not ns.modules[name], "duplicate module: " .. name)

    local module = setmetatable({ moduleName = name }, moduleProto)
    ns.modules[name] = module
    ns.moduleOrder[#ns.moduleOrder + 1] = module
    ns[name] = module
    return module
end

--------------------------------------------------------------------------------
-- Event dispatch
--------------------------------------------------------------------------------

local eventFrame = CreateFrame("Frame", "BlackthornesFarmerEventFrame")
ns.eventFrame = eventFrame

local handlers = {}
local unknownEvents = {}

--- Register an event handler.
-- On Forever, registering an event the client does not know raises a Lua error
-- rather than failing quietly, so every registration goes through pcall.
function ns.RegisterEvent(owner, event, fn)
    if type(fn) ~= "function" then
        ns.Debug("RegisterEvent: no handler for", event)
        return false
    end

    local list = handlers[event]
    if not list then
        if unknownEvents[event] then return false end

        local ok, err = pcall(eventFrame.RegisterEvent, eventFrame, event)
        if not ok then
            unknownEvents[event] = err or true
            ns.Debug("event not supported by this client:", event)
            return false
        end
        list = {}
        handlers[event] = list
    end

    list[#list + 1] = { owner = owner, fn = fn }
    return true
end

function ns.UnregisterEvent(owner, event)
    local list = handlers[event]
    if not list then return false end

    for i = #list, 1, -1 do
        if list[i].owner == owner then
            table.remove(list, i)
        end
    end

    if #list == 0 then
        handlers[event] = nil
        pcall(eventFrame.UnregisterEvent, eventFrame, event)
    end
    return true
end

function ns.GetUnknownEvents()
    return unknownEvents
end

--- Run `fn` once for every loot window, whichever event shows it first.
--
-- A loot window raises LOOT_READY when its contents can be read and
-- LOOT_OPENED when it is drawn. With auto loot, and with the fast-loot
-- addons many players run, everything is taken on LOOT_READY and the window
-- is often empty or gone by LOOT_OPENED, so a reader that waited for
-- LOOT_OPENED saw nothing at all (a player's report, 2026-10-05: the kills
-- panel stayed empty while goals, which count the bags, kept up). So the
-- readers run on LOOT_READY, and LOOT_OPENED only runs them for a window
-- LOOT_READY never announced. LOOT_CLOSED ends the window.
--
-- That guard needs LOOT_CLOSED. On a client without it nothing would end a
-- window, and every loot after the first would go unread, so there each
-- window is read on LOOT_READY alone (or LOOT_OPENED, without LOOT_READY).
local lootReaders = {}
local lootReadEarly = false
local lootHasReady, lootHasClosed = false, false

local function ReadLoot()
    for i = 1, #lootReaders do
        local entry = lootReaders[i]
        local ok, err = pcall(entry.fn, entry.owner)
        if not ok then geterrorhandler()(err) end
    end
end

function ns.OnLootWindow(owner, fn)
    if type(fn) ~= "function" then return false end

    if #lootReaders == 0 then
        lootHasClosed = ns.RegisterEvent(ns, "LOOT_CLOSED", function() lootReadEarly = false end)
        lootHasReady = ns.RegisterEvent(ns, "LOOT_READY", function()
            if lootReadEarly then return end
            lootReadEarly = lootHasClosed
            ReadLoot()
        end)
        ns.RegisterEvent(ns, "LOOT_OPENED", function()
            if lootReadEarly or (lootHasReady and not lootHasClosed) then return end
            ReadLoot()
        end)
    end

    lootReaders[#lootReaders + 1] = { owner = owner, fn = fn }
    return true
end

eventFrame:SetScript("OnEvent", function(_, event, ...)
    local list = handlers[event]
    if not list then return end

    -- One handler erroring must not swallow the rest.
    for i = 1, #list do
        local entry = list[i]
        if entry then
            local ok, err = pcall(entry.fn, entry.owner, event, ...)
            if not ok then
                geterrorhandler()(err)
            end
        end
    end
end)

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

local initialized = false
local enabled = false

local function RunLifecycle(method)
    for i = 1, #ns.moduleOrder do
        local module = ns.moduleOrder[i]
        local fn = module[method]
        if type(fn) == "function" then
            local ok, err = pcall(fn, module)
            if not ok then
                ns.Warn(("module %s:%s failed"):format(module.moduleName, method))
                geterrorhandler()(err)
            end
        end
    end
end

--------------------------------------------------------------------------------
-- Saved variables
--------------------------------------------------------------------------------

local DEFAULTS = {
    point = "CENTER",
    relativePoint = "CENTER",
    x = 0,
    y = 40,
    lastSearch = "",
    -- The main window's tab when it was last closed: "search", "rankings"
    -- or "grind".
    lastTab = "search",
    debug = false,

    -- Window sizes in percent, set on the settings page.
    windowScale = 100,
    trackerScale = 100,

    -- Loot recording paused from the settings page or /farm harvest off.
    -- Remembered, so pausing it once does not quietly undo itself at login.
    harvestPaused = false,

    -- Minimap button: where it sits on the ring, how far off the edge, and
    -- whether it is there at all.
    minimapAngle = math.rad(200),
    minimapGap = 16, -- kept for old saves; the button now sits on the ring
    minimapHidden = false,

    -- Kill tracker: whether its panel is kept out of the way, whether each
    -- kill is reported in chat (off unless asked for), whether unlocking a
    -- mob's drop rates gets a fanfare (on) and an /emote others see (on), and
    -- where it sits --
    -- down the left edge, under the player and party frames, by default.
    trackerHidden = false,
    trackerReport = false,
    trackerCelebrate = true,
    trackerAnnounce = true,
    trackerPoint = "TOPLEFT",
    trackerX = 8,
    trackerY = -190,
    -- In a party or raid, step aside from the group frames.
    trackerDodgeGroup = true,

    -- Markers where herbs and ore were gathered, on the world map and the
    -- minimap. Each can be turned off on its own.
    markersWorld = true,
    markersMinimap = true,

    -- The best place to farm a material, on its tooltip.
    itemTooltip = true,

    -- The goal arrow (UI/Arrow.lua): off until turned on.
    arrowShown = false,
    -- With TomTom installed, its arrow shows the goal arrow's place
    -- (Logic/TomTom.lua).
    useTomTom = true,

    -- The Grind tab's camps on the world map (UI/GrindPins.lua). Its level
    -- band (grindMin, grindMax), type, what the mobs give and order are
    -- unset until picked; the creature types learned in game are kept in
    -- creatureTypes (Logic/Grinding.lua).
    grindPins = true,
}

local function LoadSavedVariables()
    if type(BlackthornesFarmerDB) ~= "table" then
        BlackthornesFarmerDB = {}
    end

    for key, value in pairs(DEFAULTS) do
        if BlackthornesFarmerDB[key] == nil then
            BlackthornesFarmerDB[key] = value
        end
    end

    ns.db = BlackthornesFarmerDB
end

ns.LoadSavedVariables = LoadSavedVariables

-- Read-only: the settings page puts window positions back from here.
ns.DEFAULTS = DEFAULTS

local bootstrap = ns.NewModule("Bootstrap")

function bootstrap:ADDON_LOADED(_, loadedAddon)
    if loadedAddon ~= ADDON_NAME or initialized then return end
    initialized = true

    LoadSavedVariables()
    RunLifecycle("OnInitialize")
end

function bootstrap:PLAYER_LOGIN()
    if enabled then return end
    enabled = true
    RunLifecycle("OnEnable")
end

ns.RegisterEvent(bootstrap, "ADDON_LOADED", bootstrap.ADDON_LOADED)
ns.RegisterEvent(bootstrap, "PLAYER_LOGIN", bootstrap.PLAYER_LOGIN)

--------------------------------------------------------------------------------
-- Slash commands
--------------------------------------------------------------------------------

ns.commands = {}
ns.commandOrder = {}

--- Register a `/farm <name>` subcommand.
function ns.RegisterCommand(name, usage, fn)
    ns.commands[name] = { usage = usage, fn = fn }
    ns.commandOrder[#ns.commandOrder + 1] = name
end

local function ShowHelp()
    ns.Print(("|c%sBlackthornes Farmer|r %s"):format(ns.COLORS.accent, ns.VersionLabel()))
    ns.PrintRaw(("  |c%s/farm <text>|r  |c%ssearch for something to farm|r"):format(
        ns.COLORS.accent, ns.COLORS.muted))

    for i = 1, #ns.commandOrder do
        local name = ns.commandOrder[i]
        local command = ns.commands[name]
        ns.PrintRaw(("  |c%s/farm %s|r  |c%s%s|r"):format(
            ns.COLORS.accent, name, ns.COLORS.muted, command.usage or ""))
    end
end

ns.RegisterCommand("help", "show this list", ShowHelp)

SLASH_BLACKTHORNESFARMER1 = "/farm"
SLASH_BLACKTHORNESFARMER2 = "/farmer"

-- Named rather than anonymous so the test suite can drive it directly; the
-- slash routing is where a command goes wrong, so it is worth testing.
function ns.HandleSlash(input)
    input = (input or ""):gsub("^%s+", ""):gsub("%s+$", "")

    local keyword, rest = input:match("^(%S+)%s*(.*)$")
    if not keyword then
        if ns.UI and ns.UI.Toggle then
            ns.UI:Toggle()
        else
            ShowHelp()
        end
        return
    end

    -- Unlike the tradeskills addon, an unrecognised keyword is not an error
    -- here: the common case is a material name, and making people type
    -- `/farm search copper ore` to search would be the wrong default.
    local command = ns.commands[keyword:lower()]

    local ok, err
    if command then
        ok, err = pcall(command.fn, rest or "")
    else
        ok, err = pcall(ns.RunSearch, input)
    end

    -- Wrapped because a command that errors is otherwise completely silent:
    -- this client does not show Lua errors unless scriptErrors is on, so a
    -- broken command and one that did nothing look identical from the chat
    -- frame.
    if not ok then
        ns.Warn(("/farm %s failed: %s"):format(keyword, tostring(err)))
        geterrorhandler()(err)
    end

    -- Most commands flip something the settings page shows; keep it honest
    -- if it happens to be open.
    if ns.SettingsUI then
        pcall(ns.SettingsUI.Refresh, ns.SettingsUI)
    end
end

SlashCmdList["BLACKTHORNESFARMER"] = ns.HandleSlash
