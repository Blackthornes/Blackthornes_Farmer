-- The settings window.
--
-- What matters is that every way in opens it, that each control changes the
-- same saved value its chat command does, that the page shows what is saved
-- rather than what it last drew, and that nothing on it can delete data.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("settings")

local ns = env.Load({ ui = true })
local UI, SettingsUI = ns.UI, ns.SettingsUI

suite.check("the module is loaded", SettingsUI ~= nil)

-- A client with retail's Settings API, recording what is registered.
local registered = {}
_G.Settings = {
    RegisterCanvasLayoutCategory = function(panel, name)
        return { panel = panel, name = name }
    end,
    RegisterAddOnCategory = function(category)
        registered[#registered + 1] = category
    end,
}

-- PLAYER_LOGIN, as the client runs it.
for _, module in ipairs(ns.moduleOrder) do
    if module.OnEnable then module:OnEnable() end
end

--------------------------------------------------------------------------------
-- Ways in
--------------------------------------------------------------------------------

suite.check("it starts closed", not (SettingsUI.frame and SettingsUI.frame:IsShown()))

ns.HandleSlash("settings")
suite.check("/farm settings opens it", SettingsUI.frame:IsShown())

ns.HandleSlash("settings")
suite.check("typing it again closes it", not SettingsUI.frame:IsShown())

ns.HandleSlash("options")
suite.check("/farm options is the same command", SettingsUI.frame:IsShown())
SettingsUI:Hide()

-- The aliases are not printed as separate lines in /farm help.
local listed = {}
for _, name in ipairs(ns.commandOrder) do listed[name] = true end
suite.check("help lists settings", listed.settings)
suite.check("help does not repeat it as options", not listed.options)

local click = UI.minimapButton:GetScript("OnClick")
click(UI.minimapButton, "RightButton")
suite.check("right-clicking the minimap button opens it", SettingsUI.frame:IsShown())
suite.check("and does not open the search window", not UI.frame:IsShown())
click(UI.minimapButton, "RightButton")
suite.check("right-clicking again closes it", not SettingsUI.frame:IsShown())

click(UI.minimapButton, "LeftButton")
suite.check("left-click still opens the search window", UI.frame:IsShown())
UI:Hide()

suite.check("the search window has a Settings button", UI.settingsButton ~= nil)
UI.settingsButton:GetScript("OnClick")(UI.settingsButton, "LeftButton")
suite.check("which opens it", SettingsUI.frame:IsShown())
SettingsUI:Hide()

suite.check("it is in the game's AddOns options", #registered == 1, #registered)
suite.check("under the addon's name",
    registered[1] and registered[1].name == "Blackthornes Farmer")

--------------------------------------------------------------------------------
-- Controls write what the commands write
--------------------------------------------------------------------------------

SettingsUI:Show()
local controls = SettingsUI.controls

local function Toggle(control)
    control:GetScript("OnClick")(control)
end

suite.check("the minimap box starts ticked", controls.minimap:GetChecked())
Toggle(controls.minimap)
suite.check("unticking it hides the button", ns.db.minimapHidden == true)
suite.check("the button is actually hidden", not UI.minimapButton:IsShown())
Toggle(controls.minimap)
suite.check("ticking it brings it back", ns.db.minimapHidden == false
    and UI.minimapButton:IsShown())

Toggle(controls.report)
suite.check("chat report writes the /farm report setting", ns.db.trackerReport == true)

Toggle(controls.tracker)
suite.check("the tally box writes the /farm tracker setting", ns.db.trackerHidden == true)
Toggle(controls.tracker)
suite.check("and back", ns.db.trackerHidden == false)

Toggle(controls.debug)
suite.check("debug output", ns.db.debug == true)
Toggle(controls.debug)

-- Recording.
suite.check("recording starts on", ns.Harvest.enabled and controls.record:GetChecked())
Toggle(controls.record)
suite.check("unticking it pauses recording", ns.Harvest.enabled == false)
suite.check("and remembers that for next login", ns.db.harvestPaused == true)

env.Loot(ns, { name = "Dalaran Apprentice", level = 22, guid = "paused-1" },
    { { name = "Wool Cloth", id = 2592 } })
suite.check("a paused recorder records nothing", ns.Harvest:CountCorpses() == 0,
    ns.Harvest:CountCorpses())

Toggle(controls.record)
suite.check("ticking it resumes", ns.Harvest.enabled and ns.db.harvestPaused == false)

--------------------------------------------------------------------------------
-- Sizes
--------------------------------------------------------------------------------

local scaled
UI.frame.SetScale = function(_, value) scaled = value end

local stepper = controls.windowScale
suite.check("the size starts at 100%", stepper:GetValue() == 100, stepper:GetValue())
suite.check("and says so", stepper.text:GetText() == "100%", stepper.text:GetText())

stepper.plus:GetScript("OnClick")(stepper.plus)
suite.check("+ steps the size up", ns.db.windowScale == 110, ns.db.windowScale)
suite.check("and resizes the window", scaled and math.abs(scaled - 1.1) < 1e-9, scaled)

for _ = 1, 20 do stepper.plus:GetScript("OnClick")(stepper.plus) end
suite.check("it stops at the top of its range", ns.db.windowScale == 150, ns.db.windowScale)

for _ = 1, 20 do stepper.minus:GetScript("OnClick")(stepper.minus) end
suite.check("and at the bottom", ns.db.windowScale == 70, ns.db.windowScale)

stepper:SetValue(103)
suite.check("an odd value snaps to a step", ns.db.windowScale == 100, ns.db.windowScale)

local trackerScaled
ns.TrackerUI:Build().SetScale = function(_, value) trackerScaled = value end
controls.trackerScale.minus:GetScript("OnClick")(controls.trackerScale.minus)
suite.check("the tally has its own size", ns.db.trackerScale == 90 and ns.db.windowScale == 100)
suite.check("which resizes the tally", trackerScaled and math.abs(trackerScaled - 0.9) < 1e-9,
    trackerScaled)

--------------------------------------------------------------------------------
-- The page follows the saved values
--------------------------------------------------------------------------------

ns.HandleSlash("report off")
suite.check("typing a command while it is open updates the page",
    controls.report:GetChecked() == false)

ns.HandleSlash("minimap")
suite.check("the minimap command too", controls.minimap:GetChecked() == false)
ns.HandleSlash("minimap")

ns.HandleSlash("harvest off")
suite.check("/farm harvest off unticks recording", controls.record:GetChecked() == false)
suite.check("and is remembered", ns.db.harvestPaused == true)
ns.HandleSlash("harvest on")
suite.check("/farm harvest on ticks it", controls.record:GetChecked() == true)

--------------------------------------------------------------------------------
-- Positions
--------------------------------------------------------------------------------

ns.db.point, ns.db.x, ns.db.y = "TOPLEFT", 4000, -4000
ns.db.trackerPoint, ns.db.trackerX = "BOTTOM", 9999

SettingsUI:ResetPositions()

suite.check("the search window goes back", ns.db.point == ns.DEFAULTS.point
    and ns.db.x == ns.DEFAULTS.x and ns.db.y == ns.DEFAULTS.y)
suite.check("so does the tally", ns.db.trackerPoint == ns.DEFAULTS.trackerPoint
    and ns.db.trackerX == ns.DEFAULTS.trackerX)

--------------------------------------------------------------------------------
-- Nothing here deletes data
--------------------------------------------------------------------------------

env.Loot(ns, { name = "Dalaran Apprentice", level = 22, guid = "kept-1" },
    { { name = "Wool Cloth", id = 2592 } })
local corpses = ns.Harvest:CountCorpses()
suite.check("recording works again", corpses == 1, corpses)

-- Every button and box on the page, pressed.
for _, control in pairs(controls) do
    local onClick = control.GetScript and control:GetScript("OnClick")
    if onClick then onClick(control) end
end

suite.check("no control on the page clears recorded loot",
    ns.Harvest:CountCorpses() == corpses, ns.Harvest:CountCorpses())

--------------------------------------------------------------------------------
-- A client without the options API
--------------------------------------------------------------------------------

_G.Settings = nil
_G.InterfaceOptions_AddCategory = nil
SettingsUI.optionsPanel = nil

local ok, result = pcall(SettingsUI.RegisterGameOptions, SettingsUI)
suite.check("no options API is not an error", ok, result)
suite.check("it just reports it was not registered", result == false)

_G.Settings = { RegisterCanvasLayoutCategory = function() error("nope") end,
    RegisterAddOnCategory = function() end }
SettingsUI.optionsPanel = nil
ok, result = pcall(SettingsUI.RegisterGameOptions, SettingsUI)
suite.check("an options API that raises is not an error either", ok and result == false, result)
_G.Settings = nil

suite.done()
