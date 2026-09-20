-- Shared test environment: enough of the WoW client to load the addon.
--
-- Not a test itself -- runtests.py only runs tools/test_*.lua -- this is what
-- each suite calls to get a loaded addon and a widget layer that remembers
-- what was written to it.
--
--   local env = dofile(lfs_cwd .. "/tools/testenv.lua")
--   local ns = env.Load()            -- data and logic
--   local ns = env.Load({ ui = true })

local env = {}

local ROOT = lfs_cwd or "."

--------------------------------------------------------------------------------
-- Widgets
--------------------------------------------------------------------------------

-- Any method a test does not care about answers as a no-op, so the window can
-- build its panels, labels and anchors undisturbed.
local function Stub(fields)
    local frame = fields or {}

    frame._shown = frame._shown or false
    frame._height = frame._height or 300
    frame._text = frame._text or ""

    function frame:Show() self._shown = true end
    function frame:Hide() self._shown = false end
    function frame:IsShown() return self._shown end
    function frame:SetShown(value) self._shown = value and true or false end

    function frame:SetHeight(value) self._height = value end
    function frame:GetHeight() return self._height end
    function frame:SetWidth(value) self._width = value end
    function frame:GetWidth() return self._width or 500 end

    function frame:SetText(value) self._text = tostring(value or "") end
    function frame:GetText() return self._text end

    function frame:SetScript(script, fn) self._scripts[script] = fn end
    function frame:GetScript(script) return self._scripts[script] end

    function frame:GetPoint() return "CENTER", nil, "CENTER", 0, 40 end
    function frame:GetFrameLevel() return 1 end

    function frame:RegisterEvent(event) self._events[event] = true end
    function frame:UnregisterEvent(event) self._events[event] = nil end

    function frame:CreateTexture() return Stub() end
    function frame:CreateFontString() return Stub() end

    function frame:SetMinMaxValues(low, high) self._min, self._max = low, high end
    function frame:SetValue(value) self._value = value end
    function frame:GetValue() return self._value or 0 end

    frame._scripts = frame._scripts or {}
    frame._events = frame._events or {}

    return setmetatable(frame, { __index = function(self, key)
        local noop = function() end
        rawset(self, key, noop)
        return noop
    end })
end

env.Stub = Stub

--------------------------------------------------------------------------------
-- Client
--------------------------------------------------------------------------------

function env.InstallClient()
    env.chat = {}

    _G.UIParent = Stub()

    _G.CreateFrame = function(_, name)
        local frame = Stub()
        if name then _G[name] = frame end
        return frame
    end

    _G.DEFAULT_CHAT_FRAME = {
        AddMessage = function(_, message) env.chat[#env.chat + 1] = message end,
    }

    _G.SlashCmdList = {}
    _G.geterrorhandler = function() return function(err) error(err, 0) end end
    _G.BlackthornesFarmerDB = nil

    -- Theme asks for the default font through pcall and falls back on its own,
    -- so leaving GameFontNormal absent exercises that path.
    _G.GameFontNormal = nil
end

--------------------------------------------------------------------------------
-- Loading
--------------------------------------------------------------------------------

local FILES = {
    "Core/Init.lua",
    "Core/Util.lua",
    "Data/Database.lua",
    "Data/Data_Mining.lua",
    "Data/Data_Herbalism.lua",
    "Data/Data_Cloth.lua",
    "Data/Data_Leather.lua",
    "Data/Data_Misc.lua",
    "Data/Data_MobDrops.lua",
    "Logic/Search.lua",
}

local UI_FILES = {
    "UI/Theme.lua",
    "UI/Widgets.lua",
    "UI/Main.lua",
}

--- Load the addon exactly as the TOC does, and return its namespace.
function env.Load(opts)
    opts = opts or {}

    env.InstallClient()

    local ns = {}

    local function Run(relative)
        local chunk = assert(loadfile(ROOT .. "/" .. relative))
        chunk("Blackthornes_Farmer", ns)
    end

    for _, file in ipairs(FILES) do Run(file) end

    if opts.ui then
        for _, file in ipairs(UI_FILES) do Run(file) end
    end

    -- ADDON_LOADED installs saved variables; tests that skip the event loop
    -- still need ns.db to exist.
    ns.LoadSavedVariables()

    env.ns = ns
    return ns
end

--------------------------------------------------------------------------------
-- Assertions
--------------------------------------------------------------------------------

function env.NewSuite(name)
    local suite = { name = name, checks = 0 }

    function suite.check(label, ok, detail)
        suite.checks = suite.checks + 1
        if not ok then
            error(("%s: %s%s"):format(name, label,
                detail and ("  -> " .. tostring(detail)) or ""), 0)
        end
    end

    function suite.done()
        print(("  %s: %d checks passed"):format(name, suite.checks))
    end

    return suite
end

return env
