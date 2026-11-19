-- The swap gem on Farmer's windows and the one window (UI/SharedWindow.lua
-- AddSwap and Swap, FarmerTabs' tab, show and hide; the owner said build
-- it, 2026-11-19).
--
-- What must hold:
--   1. Farmer's main window and Settings carry a join gem; the one window a
--      split gem.
--   2. Split from the one window on Rankings: the one window closes, Farmer
--      opens on its own on Rankings, with its rim, and the All Addons box
--      reads unticked.
--   3. Join from Farmer's own Settings: Settings moves into the one window,
--      still on Settings, and the box reads ticked.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("swapwindows")

_G.BlackthornesWindow = nil
local ns = env.Load({ ui = true })
local UI, SettingsUI, Tabs, SW = ns.UI, ns.SettingsUI, ns.FarmerTabs, ns.SharedWindow

for _, module in ipairs(ns.moduleOrder) do
    if module.OnEnable then module:OnEnable() end
end
UI:JoinSharedMinimap()
local hub = _G.BlackthornesWindow

-- The game runs a frame's OnHide as it hides; the fake game does not.
local function HidesLikeTheGame(frame)
    local hide = frame.Hide
    frame.Hide = function(self)
        local was = self:IsShown()
        hide(self)
        local onHide = was and self:GetScript("OnHide")
        if onHide then onHide(self) end
    end
end

-- 1.
SW.SetOn(true)
UI:Show()
UI:ShowTab("rankings")
HidesLikeTheGame(hub.frame)
local oneGem = rawget(hub.frame, "blackthornesSwap")
suite.check("the one window has the split gem", oneGem and rawget(oneGem, "join") == false)
local mainGem = rawget(UI.frame, "blackthornesSwap")
suite.check("Farmer's main window has the join gem", mainGem and rawget(mainGem, "join") == true
    and rawget(mainGem, "swapKey") == "farmer")
SettingsUI:Build()
local settingsGem = rawget(SettingsUI.frame, "blackthornesSwap")
suite.check("and so does Settings", settingsGem and rawget(settingsGem, "join") == true)
suite.check("on Rankings in the one window", Tabs:Hosted() and UI.tab == "rankings")

-- 2.
oneGem:GetScript("OnClick")(oneGem)
suite.check("split: the choice is off", not SW.On() and ns.db.oneWindow == false)
suite.check("the one window closed", not hub.frame:IsShown())
suite.check("Farmer opens on its own", not Tabs:Hosted() and UI.frame:IsShown()
    and UI.frame:GetParent() == UIParent)
suite.check("on the same tab", UI.tab == "rankings")
suite.check("with its own rim and gems again", UI.trim:IsShown())
UI:ShowTab("settings")
suite.check("the One Window box reads unticked", SettingsUI.controls.oneWindow:GetChecked() == false)

-- 3.
suite.check("Settings is up on its own", SettingsUI.frame:IsShown() and SettingsUI.frame:GetParent() == UIParent)
settingsGem:GetScript("OnClick")(settingsGem)
suite.check("join: the choice is on", SW.On() and ns.db.oneWindow == true)
suite.check("the one window opens on Farmer", hub.frame:IsShown() and hub.current == hub.entries.farmer)
suite.check("still on Settings, inside it", Tabs:Hosted() and SettingsUI.frame:IsShown()
    and SettingsUI.frame:GetParent() == hub.frame.area)
suite.check("the main window stays out of the way", not UI.frame:IsShown())
SettingsUI:Refresh()
suite.check("the One Window box reads ticked", SettingsUI.controls.oneWindow:GetChecked() == true)

SW.SetOn(false)
_G.BlackthornesWindow = nil
suite.done()
