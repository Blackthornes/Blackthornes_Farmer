-- The window's key: one entry on the game's Key Bindings page, under the
-- addon's own header, that opens or closes the window the way the slash
-- command on its own does (so with the one window on, this addon's tab).
-- No key is set for the player.
--
-- What must hold:
--   1. Bindings.xml lists the key first, with the addon's header.
--   2. The header and the key's name are set for the Key Bindings page.
--   3. Pressing the key runs UI:Toggle, once per press, as the slash does.
--   4. Before the addon has loaded its window code, a press does nothing
--      and raises nothing.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("windowkey")

local ns = env.Load({ ui = true })

-- 1. Bindings.xml.
local handle = assert(io.open(lfs_cwd .. "/Bindings.xml", "r"))
local xml = handle:read("*a")
handle:close()
local first = xml:match("<Binding%s+[^>]*>")
suite.check("the window key is the first binding",
    first and first:find('name="BLACKTHORNESFARMER_TOGGLE"', 1, true) ~= nil, first)
suite.check("it carries the addon's header",
    first and first:find('header="BLACKTHORNESFARMER"', 1, true) ~= nil, first)
suite.check("no other binding repeats the header",
    select(2, xml:gsub('header="', "")) == 1)
local body = xml:match('<Binding name="BLACKTHORNESFARMER_TOGGLE"[^>]*>(.-)</Binding>')
suite.check("the key has a line to run", body and body:find("%S") ~= nil)

-- 2. Names on the Key Bindings page.
suite.check("the header is the addon's name",
    _G.BINDING_HEADER_BLACKTHORNESFARMER == "Blackthornes Farmer", tostring(_G.BINDING_HEADER_BLACKTHORNESFARMER))
suite.check("the key reads Open or close the window",
    _G.BINDING_NAME_BLACKTHORNESFARMER_TOGGLE == "Open or close the window",
    tostring(_G.BINDING_NAME_BLACKTHORNESFARMER_TOGGLE))
suite.check("the slash and the key share UI:Toggle",
    type(ns.UI) == "table" and type(ns.UI.Toggle) == "function")

-- 3. A press runs UI:Toggle, as the slash command does.
local press = assert(loadstring(body))
local realToggle = ns.UI.Toggle
local toggles = 0
ns.UI.Toggle = function(self)
    suite.check("Toggle is called on the addon's UI", self == ns.UI)
    toggles = toggles + 1
end
press()
suite.check("one press toggles once", toggles == 1, toggles)
press()
suite.check("a second press toggles again", toggles == 2, toggles)
ns.HandleSlash("")
suite.check("the slash on its own toggles the same way", toggles == 3, toggles)
ns.UI.Toggle = realToggle

-- 4. Not loaded yet.
local saved = _G.BlackthornesFarmer
_G.BlackthornesFarmer = nil
suite.check("before the addon loads, a press raises nothing", pcall(press))
_G.BlackthornesFarmer = { }
suite.check("before the window code loads, a press raises nothing", pcall(press))
_G.BlackthornesFarmer = saved

suite.done()
