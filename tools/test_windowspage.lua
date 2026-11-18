-- The Settings pages after the 2026-11-16 tidy: ten pages, the Windows
-- table (one line a window: Show, Transparent, Reset Spot), a Sounds page,
-- and the page names wrapping rather than widening the window. Rows moved;
-- every saved key is the one it was.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("windowspage")

local ns = env.Load({ ui = true })
local SettingsUI = ns.SettingsUI

for _, module in ipairs(ns.moduleOrder) do
    if module.OnEnable then module:OnEnable() end
end

ns.HandleSlash("settings")
local pages, controls = SettingsUI.pages, SettingsUI.controls

local order = {}
for index, def in ipairs(pages.defs) do order[index] = def.key end
suite.check("the pages, in order", table.concat(order, " ")
    == "tally loot map goals tooltips sounds panels sharing all about", table.concat(order, " "))
-- General joined Windows (the owner said build it, 2026-11-17): a page
-- saved under an old key opens the page its rows are on now.
suite.check("old saves of General, Windows and Advanced open Windows",
    SettingsUI.OLD_PAGES.general == "panels" and SettingsUI.OLD_PAGES.windows == "panels"
    and SettingsUI.OLD_PAGES.advanced == "panels")
suite.check("no page takes a key that old saves send elsewhere",
    SettingsUI.OLD_PAGES.panels == nil and SettingsUI.OLD_PAGES.sounds == nil)
local switchWords = {}
for _, def in ipairs(pages.defs) do switchWords[#switchWords + 1] = def.text end
suite.check("the shared pages read the same in all five",
    table.concat(switchWords, " "):find("TOOLTIPS SOUNDS WINDOWS SHARING ALL ADDONS ABOUT", 1, true) ~= nil,
    table.concat(switchWords, " "))
suite.check("the switch wraps at the window's width, never past it",
    pages.opts.barCap == SettingsUI.BAR_CAP and pages:BarWidth() <= SettingsUI.BAR_CAP, pages:BarWidth())

local function PageOf(control)
    local row = control._parent
    for _, entry in ipairs(pages.searchables or {}) do
        if entry.frame == row then return entry.page end
    end
end

-- The Windows table: each window's controls share one line.
local lines = SettingsUI.tableLines
for _, set in ipairs({
    { "tracker", "tracker", "seeThrough", "trackerReset" },
    { "goals", "goals", "goalsSeeThrough", "goalsDock" },
    { "places", nil, "goalSpotsSeeThrough", "goalSpotsReset" },
    { "rankup", "rankUpShow", "rankUpSeeThrough", "rankUpReset" },
    { "recap", nil, "recapSeeThrough", nil },
    { "xpbar", "xpBar", "xpBarSeeThrough", "xpBarReset" },
    { "lootfeed", "lootFeed", "lootFeedSeeThrough", "lootFeedReset" },
    { "route", "routeWindow", "routeWindowSeeThrough", "routeWindowReset" },
    { "fishing", "fishingPanel", nil, "fishingPanelReset" },
    { "zoneBoard", "zoneBoardShow", "zoneBoardSeeThrough", "zoneBoardReset" },
}) do
    local line = lines[set[1]]
    local together = line ~= nil
    for index = 2, 4 do
        local name = set[index]
        if name and (controls[name] == nil or controls[name]._parent ~= line) then together = false end
    end
    suite.check(set[1] .. " has its controls on one line of the Windows page",
        together and PageOf({ _parent = line }) == "panels")
end

local x = SettingsUI.tableX
suite.check("the columns do not run into each other", x.show < x.clear and x.clear < x.spot
    and x.spot + 100 <= x.wide, ("%s %s %s %s"):format(x.show, x.clear, x.spot, x.wide))
suite.check("a line is as wide as both columns", lines.tracker:GetWidth() == x.wide, lines.tracker:GetWidth())

for _, name in ipairs({ "trackerScale", "snapPanels" }) do
    suite.check(name .. " sits under the table", PageOf(controls[name]) == "panels", tostring(PageOf(controls[name])))
end

-- Sounds in one place.
suite.check("the fanfare box is on the Sounds page", PageOf(controls.celebrate) == "sounds",
    tostring(PageOf(controls.celebrate)))

-- What every Blackthornes addon shares has its own page, the same in each.
for _, name in ipairs({ "windowStyle", "textSize", "effects", "muteSounds", "combineButtons", "oneWindow",
    "resetPositions", "sisters", "whatsnew", "whatsNewAfter" }) do
    suite.check(name .. " is on the All Addons page", PageOf(controls[name]) == "all", tostring(PageOf(controls[name])))
end
suite.check("Window Size is on Windows", PageOf(controls.windowScale) == "panels")
suite.check("and so is Farmer UI", PageOf(controls.rankingsVendorOnly) == "panels")
suite.check("Mute All Sounds is on top of Sounds too", PageOf(controls.muteSoundsHere) == "sounds",
    tostring(PageOf(controls.muteSoundsHere)))
SettingsUI:SetMuteSounds(true)
suite.check("ticking Mute ticks both boxes",
    controls.muteSounds:GetChecked() == true and controls.muteSoundsHere:GetChecked() == true)
SettingsUI:SetMuteSounds(false)
suite.check("and unticking clears both",
    not controls.muteSounds:GetChecked() and not controls.muteSoundsHere:GetChecked())
ns.WhatsNew:SetOn(false)
SettingsUI:Refresh()
suite.check("After Updates shows what is saved", controls.whatsNewAfter:GetValue() == "off",
    tostring(controls.whatsNewAfter:GetValue()))
ns.WhatsNew:SetOn(true)
SettingsUI:ShowAllAddons()
suite.check("the one window's gear opens Settings on All Addons", pages.shown == "all", pages.shown)
pages:Search("node sound")
suite.check("Node Sound is found on the Sounds page", pages.shown == "sounds", pages.shown)
pages:Search("dock to the map")
suite.check("Dock to the Map is on the Goals page", pages.shown == "goals", pages.shown)
pages:Search("nameplate worth")
suite.check("nameplate rows are on the Tooltips page", pages.shown == "tooltips", pages.shown)
pages:Search("heat strength")
suite.check("kill heat stays on the Map page", pages.shown == "map", pages.shown)
pages:Search("")

-- Reset Spot moves one window and nothing else.
ns.db.trackerX, ns.db.trackerY = 123, -45
ns.db.trackerWidth = 300
ns.db.lootFeedX = 77
controls.trackerReset:GetScript("OnClick")(controls.trackerReset)
suite.check("Reset Spot puts Kills & Loot back", ns.db.trackerX == ns.DEFAULTS.trackerX
    and ns.db.trackerY == ns.DEFAULTS.trackerY, tostring(ns.db.trackerX))
suite.check("and keeps its size", ns.db.trackerWidth == 300)
suite.check("and leaves the other windows where they are", ns.db.lootFeedX == 77)

ns.db.windowSpots = { ["farmer.fishingpanel"] = { x = 10, y = 20 }, ["farmer.export"] = { x = 1, y = 2 } }
controls.fishingPanelReset:GetScript("OnClick")(controls.fishingPanelReset)
suite.check("Reset Spot forgets the Fishing Panel's spot only",
    ns.db.windowSpots["farmer.fishingpanel"] == nil and ns.db.windowSpots["farmer.export"] ~= nil)

if ns.MapDock then
    ns.MapDock.loose = true
    controls.goalSpotsReset:GetScript("OnClick")(controls.goalSpotsReset)
    suite.check("Reset Spot lets Where to Farm go back to its place", ns.MapDock.loose == nil)
end

-- The old Show boxes still write the same saved values.
local function Toggle(box) box:GetScript("OnClick")(box) end
local was = ns.db.trackerHidden
Toggle(controls.tracker)
suite.check("the Kills & Loot tick writes trackerHidden", ns.db.trackerHidden ~= was)
Toggle(controls.tracker)

suite.done()
