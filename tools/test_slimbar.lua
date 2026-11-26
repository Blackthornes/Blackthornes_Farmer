-- Slim Bar for Kills & Loot (UI/SlimBar.lua, the owner said build it
-- 2026-11-26).
--
-- What matters: Full Panel unless picked, so nothing changes for anyone who
-- never picks it; Slim Bar folds the panel to one line with gold an hour,
-- this run, kills and the clock; the mouse on it opens the whole list and
-- the mouse off folds it back after a moment; a click keeps it open; a
-- green drop shows on the bar for a while; the clock's tick writes only the
-- bar's words, never prices the session again; Full Panel puts every piece
-- back; the Settings choice and Set Default know the key.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("slimbar")

local ns = env.Load({ ui = true })
local Slim = ns.SlimBar
local TUI = ns.TrackerUI
local Tracker = ns.Tracker

ns.Harvest:OnEnable()
Tracker:OnEnable()
TUI:OnEnable()

local fire = ns.eventFrame:GetScript("OnEvent")
local serial = 0
local function Loot(mob, items)
    serial = serial + 1
    env.world.target = { name = mob, level = 8, dead = true, isPlayer = false,
        guid = "Creature-0-1-2-3-" .. serial }
    env.world.loot = items or {}
    fire(ns.eventFrame, "LOOT_OPENED")
end

local function Plain(text) return ns.Util.StripColor(text or ""):gsub("|T.-|t", "") end

local BOAR = "Mottled Boar"
local SCRAPS = { name = "Ruined Leather Scraps", id = 2934 }
local BELT = { name = "Wizard's Belt", id = 4827 }

--------------------------------------------------------------------------------
-- Off unless picked
--------------------------------------------------------------------------------

suite.check("Full Panel unless picked", not Slim.On() and Slim:Index() == 1
    and ns.db.trackerSlimBar == nil)
suite.check("the panel looks as it always has", TUI.title:GetText() == "Kills & Loot"
    and TUI.frame:GetHeight() > Slim.HEIGHT)
suite.check("no watcher runs for Full Panel", Slim.watch == nil
    or Slim.watch:GetScript("OnUpdate") == nil)

Loot(BOAR, { SCRAPS })
Loot(BOAR, {})

--------------------------------------------------------------------------------
-- Folded to the bar
--------------------------------------------------------------------------------

TUI.frame.IsMouseOver = function() return false end
suite.check("picking Slim Bar by its index saves it", Slim:Set(2) and ns.db.trackerSlimBar == true)
suite.check("it is folded to one line", Slim:Folded() and Slim.shape == "bar"
    and TUI.frame:GetHeight() == Slim.HEIGHT, TUI.frame:GetHeight())
local bar = Plain(TUI.title:GetText())
suite.check("the bar says this run and the kills", bar:find("this run", 1, true) ~= nil
    and bar:find("2 kills", 1, true) ~= nil, bar)
suite.check("the tabs, toolbar and lines are hidden", not TUI.tabStrip:IsShown()
    and not TUI.toolbar:IsShown() and not TUI.titleRow:IsShown())
local anyLine = false
for _, line in ipairs(TUI.lines) do if line:IsShown() then anyLine = true end end
suite.check("no line of the list shows", not anyLine)
suite.check("the panel still shows", TUI.frame:IsShown())
suite.check("the watcher runs", Slim.watch:GetScript("OnUpdate") ~= nil)

-- The gold an hour shows once the panel knows it.
local perHour = TUI.PerHour
TUI.PerHour = function() return 184000 end
TUI:Refresh()
bar = Plain(TUI.title:GetText())
suite.check("gold an hour leads the bar", bar:find("^ ?18g 40s an hour") ~= nil, bar)
TUI.PerHour = perHour

-- The clock.
suite.check("the clock reads minutes under an hour", Slim.Clock(1182) == "19:42")
suite.check("and hours past one", Slim.Clock(3725) == "1:02:05")

--------------------------------------------------------------------------------
-- The clock's tick prices nothing
--------------------------------------------------------------------------------

local priced = 0
local session = ns.Value.Session
ns.Value.Session = function(...) priced = priced + 1 return session(...) end
local refreshed = 0
local refresh = TUI.Refresh
TUI.Refresh = function(...) refreshed = refreshed + 1 return refresh(...) end
for _ = 1, 5 do Slim:Tick() end
suite.check("the tick never prices the session", priced == 0, priced)
suite.check("nor redraws the panel", refreshed == 0, refreshed)
ns.Value.Session = session
TUI.Refresh = refresh

--------------------------------------------------------------------------------
-- The mouse
--------------------------------------------------------------------------------

TUI.frame.IsMouseOver = function() return true end
Slim:Look(Slim.LOOK)
suite.check("the mouse on the bar opens the list", Slim:IsOpen() and not Slim:Folded()
    and Slim.shape == "open")
suite.check("the list is the whole panel", TUI.frame:GetHeight() > Slim.HEIGHT
    and TUI.toolbar:IsShown() and TUI.titleRow:IsShown())
suite.check("its title line keeps the bar's words",
    Plain(TUI.title:GetText()):find("this run", 1, true) ~= nil)
suite.check("it says how to keep it open",
    TUI.titleRow.left:GetText() == "Click the bar to keep the list open.")

TUI.frame.IsMouseOver = function() return false end
Slim:Look(Slim.LOOK)
suite.check("a moment off it, the list stays", Slim:IsOpen())
for _ = 1, 4 do Slim:Look(Slim.LOOK) end
suite.check("then it folds back", Slim:Folded() and TUI.frame:GetHeight() == Slim.HEIGHT)

-- Never mid-drag.
TUI.frame.IsMouseOver = function() return true end
Slim:Look(Slim.LOOK)
TUI.frame.IsMouseOver = function() return false end
TUI.dragging = true
for _ = 1, 10 do Slim:Look(Slim.LOOK) end
suite.check("a drag never folds it under the mouse", Slim:IsOpen())
TUI.dragging = nil
for _ = 1, 5 do Slim:Look(Slim.LOOK) end
suite.check("let go, it folds", Slim:Folded())

-- A click keeps it open.
local up = TUI.frame:GetScript("OnMouseUp")
local down = TUI.frame:GetScript("OnMouseDown")
down(TUI.frame, "LeftButton")
up(TUI.frame, "LeftButton")
suite.check("a click keeps the list open", Slim.pinned == true and not Slim:Folded())
suite.check("kept open, the hint goes", TUI.titleRow.left:GetText() == "")
for _ = 1, 10 do Slim:Look(Slim.LOOK) end
suite.check("the mouse off does not fold it", not Slim:Folded())
down(TUI.frame, "LeftButton")
up(TUI.frame, "LeftButton")
suite.check("a second click lets it fold", Slim:Folded())

-- A drag is not a click.
down(TUI.frame, "LeftButton")
TUI.frame:GetScript("OnDragStart")(TUI.frame)
TUI.frame:GetScript("OnDragStop")(TUI.frame)
up(TUI.frame, "LeftButton")
suite.check("a drag does not keep it open", not Slim.pinned)

-- The right-click menu.
local opened
local open = ns.RowMenu.Open
ns.RowMenu.Open = function(_, lines, opts) opened = { lines = lines, opts = opts } end
down(TUI.frame, "RightButton")
up(TUI.frame, "RightButton")
ns.RowMenu.Open = open
suite.check("a right-click opens Sort", opened ~= nil and opened.opts.title == "Sort"
    and #opened.lines >= 2)

-- Middle-click on the minimap button keeps the list open too.
ns.UI:BringBackPanels()
suite.check("middle-click keeps the list open", Slim.pinned == true and not Slim:Folded())
ns.UI:BringBackPanels()
suite.check("and lets it fold again", Slim:Folded())

--------------------------------------------------------------------------------
-- A good drop on the bar
--------------------------------------------------------------------------------

local quality = ns.TrackerFX.QualityOf
ns.TrackerFX.QualityOf = function(name) return name == BELT.name and 2 or 1 end
Loot(BOAR, { SCRAPS })
suite.check("a white drop leaves the bar as it is", Slim.flash == nil)
local clock = 100
_G.GetTime = function() return clock end
local after = C_Timer.After
-- The redraw after a loot runs; the bar's own wait is left to the clock.
C_Timer.After = function(delay, fn) if delay == 0 then fn() end end
Loot(BOAR, { BELT })
local flash = Plain(TUI.title:GetText())
suite.check("a green drop shows on the bar", flash:find("Wizard's Belt", 1, true) ~= nil
    and flash:find("from Mottled Boar", 1, true) ~= nil, flash)
clock = clock + Slim.FLASH + 1
Slim:Tick()
suite.check("a few seconds later the bar comes back",
    Plain(TUI.title:GetText()):find("this run", 1, true) ~= nil, Plain(TUI.title:GetText()))
C_Timer.After = after
_G.GetTime = nil
ns.TrackerFX.QualityOf = quality

--------------------------------------------------------------------------------
-- Full Panel again
--------------------------------------------------------------------------------

suite.check("picking Full Panel saves it as unset", Slim:Set(1) and ns.db.trackerSlimBar == nil)
suite.check("the title comes back", TUI.title:GetText() == "Kills & Loot")
suite.check("and the whole panel", TUI.frame:GetHeight() > Slim.HEIGHT
    and TUI.toolbar:IsShown() and TUI.titleRow:IsShown() and TUI.titleRow.left:GetText() == "")
suite.check("the watcher stops", Slim.watch:GetScript("OnUpdate") == nil)
suite.check("a word it does not know changes nothing", not Slim:Set("round") and ns.db.trackerSlimBar == nil)

--------------------------------------------------------------------------------
-- Settings
--------------------------------------------------------------------------------

local keys = {}
for _, key in ipairs(ns.SettingsUI.SETTING_KEYS) do keys[key] = true end
suite.check("Set Default puts it back", keys.trackerSlimBar == true)

local Settings = ns.SettingsUI
Settings:Show()
local choice = Settings.controls.trackerSlimBar
suite.check("Settings has the choice", choice ~= nil)
if choice then
    choice:SetValue(2)
    suite.check("picking Slim Bar in Settings turns it on", Slim.On() and Slim:Folded())
    choice:SetValue(1)
    suite.check("and Full Panel off", not Slim.On())
end

suite.done()
