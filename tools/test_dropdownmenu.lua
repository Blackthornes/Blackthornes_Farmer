-- A drop-down's open list stays on top, even after the window it sits in
-- (One Window, for one) sets its own strata and takes the list down with it.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("dropdownmenu")

local ns = env.Load({ ui = true })
local Widgets = ns.Widgets

local parent = CreateFrame("Frame", nil, UIParent)
local dropdown = Widgets.CreateDropdown(parent, {
    { text = "One", value = 1 },
    { text = "Two", value = 2 },
}, function() end, { width = 120 })

local menu = dropdown.menu
suite.check("the list starts on top", menu:GetFrameStrata() == "FULLSCREEN_DIALOG", menu:GetFrameStrata())

-- What a host window's SetFrameStrata does to its children.
menu:SetFrameStrata("HIGH")
dropdown:Toggle()
suite.check("opening it shows the list", menu:IsShown())
suite.check("opening it lifts the list back on top", menu:GetFrameStrata() == "FULLSCREEN_DIALOG", menu:GetFrameStrata())

dropdown:Toggle()
suite.check("a second click closes it", not menu:IsShown())

suite.done()
