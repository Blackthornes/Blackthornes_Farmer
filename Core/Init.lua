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

ns.VERSION = GetMeta("Version") or "0.0.0"

--------------------------------------------------------------------------------
-- Output
--------------------------------------------------------------------------------

ns.COLORS = {
    accent = "ffc8a44d",
    good   = "ff4fd18b",
    muted  = "ff7a8089",
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
    debug = false,

    -- Minimap button: where it sits on the ring, how far off the edge, and
    -- whether it is there at all.
    minimapAngle = math.rad(200),
    minimapGap = 16,
    minimapHidden = false,

    -- Kill tracker: whether its panel is kept out of the way, whether each
    -- kill is reported in chat (off unless asked for), and where it sits --
    -- down the left edge, under the player and party frames, by default.
    trackerHidden = false,
    trackerReport = false,
    trackerPoint = "TOPLEFT",
    trackerX = 8,
    trackerY = -190,
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
    ns.Print(("|c%sBlackthornes Farmer|r v%s"):format(ns.COLORS.accent, ns.VERSION))
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
end

SlashCmdList["BLACKTHORNESFARMER"] = ns.HandleSlash
