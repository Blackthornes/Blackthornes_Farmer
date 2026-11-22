-- Hiding a mob from the Zone Board with a right-click (the owner said build
-- it, 2026-11-22, from a mockup whose words he approved).
--
-- What must hold:
--   1. A right-click on a row opens the house menu: Take Me There first,
--      then Hide from Zone Board.
--   2. Hide puts the mob on this zone's skip list only, never the global
--      hide list, says one chat line, and the row leaves the board.
--   3. The foot says how many are hidden here, with Show Again beside it;
--      Show Again brings them all back and goes away.
--   4. Hiding the hunted mob moves the hunt on; BEST rows open it too.
--   5. Take Me There on the menu picks that row and starts its hunt.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("zoneboardhide")
local check = suite.check

local ns = env.Load({ ui = true })
local L = ns.L
local ZoneBoard, UI, Tracker = ns.ZoneBoard, ns.ZoneBoardUI, ns.Tracker

local ZONE = "Testwood Vale"
env.world.zone = ZONE

local function Mob(item, id, name, location, level, coords)
    ns.DB:RegisterItem({ name = item, id = id, category = "misc",
        sources = { { name = name, zone = ZONE, location = location, minLevel = level, maxLevel = level + 1,
            chance = 10, coords = coords, provenance = "forever" } } })
end
Mob("Wolf Pelt Test", 99101, "Test Wolf", "North Tide", 10, { 40, 30 })
Mob("Spider Silk Test", 99102, "Test Spider", "Fenris Isle", 12, { 60, 70 })
Mob("Bear Claw Test", 99103, "Lady Testgazer", "Olsen's Farthing", 14, { 50, 50 })

local serial = 0
local function Loot(mob)
    serial = serial + 1
    env.world.target = { name = mob, level = 10, dead = true, guid = "ZX-" .. serial }
    env.world.loot = { { name = "12 Copper", money = true } }
    Tracker:OnLoot()
end

ZoneBoard:SetOn(true)
for _ = 1, 5 do Loot("Test Wolf") end
for _ = 1, 18 do Loot("Test Spider") end
Loot("Lady Testgazer")
ZoneBoard:List(ZONE, true)
UI:Show()
ZoneBoard:SetTab("finish")
UI:Draw()

local function RowFor(name)
    for _, row in ipairs(UI.rows) do
        if row:IsShown() and row.data and row.data.name == name then return row end
    end
end

-- Timers wait, as the game's do, so the menu stays open.
C_Timer.After = function() end

-- 1.
check("rows take a right-click", RowFor("Lady Testgazer") ~= nil)
check("no Show Again while nothing is hidden", not UI.showAgain:IsShown())
local row = RowFor("Lady Testgazer")
row:GetScript("OnClick")(row, "RightButton")
local menu = ns.HideMenu.frame
check("a right-click opens the menu", menu and menu:IsShown())
check("Take Me There comes first", menu.lines[1].label:GetText() == L["Take Me There"], menu.lines[1].label:GetText())
check("then Hide from Zone Board", menu.lines[2].label:GetText() == L["Hide from Zone Board"]
    and not menu.lines[3]:IsShown(), menu.lines[2].label:GetText())
check("a right-click does not pick the row", UI.picks.finish ~= "Lady Testgazer")

-- 2.
env.chat = {}
menu.lines[2]:GetScript("OnClick")(menu.lines[2])
check("the menu goes", not menu:IsShown())
check("kept on this zone's skip list", ns.db.zoneBoardSkips[ZONE]["Lady Testgazer"] == true)
check("not on the global hide list", not ns.DB:IsHiddenSource("Lady Testgazer"))
check("one chat line says how to bring it back", #env.chat == 1
    and env.chat[1]:find("is off the Zone Board here. Show Again at the bottom of the board brings it back.", 1, true) ~= nil,
    env.chat[1])
check("the row leaves the board", RowFor("Lady Testgazer") == nil)
check("the others stay", RowFor("Test Wolf") and RowFor("Test Spider"))

-- 3.
check("the foot counts it", UI.foot:GetText():find(L.Format("%d hidden here.", 1), 1, true) ~= nil, UI.foot:GetText())
check("the foot still says who is left out",
    UI.foot:GetText():find(L["Rare mobs, bosses and town guards are left out."], 1, true) == 1)
check("Show Again shows", UI.showAgain:IsShown() and UI.showAgain.label:GetText() == L["Show Again"])
ZoneBoard:SetTab("best")
UI:Draw()
check("BEST shows the count too", UI.foot:GetText():find(L.Format("%d hidden here.", 1), 1, true) ~= nil
    and UI.showAgain:IsShown())
check("BEST leaves it out", RowFor("Lady Testgazer") == nil)
UI.showAgain:GetScript("OnClick")(UI.showAgain)
check("Show Again brings it back", ns.db.zoneBoardSkips[ZONE] == nil and RowFor("Lady Testgazer") ~= nil)
check("and Show Again goes", not UI.showAgain:IsShown())
check("the count goes from the foot", UI.foot:GetText():find(L.Format("%d hidden here.", 1), 1, true) == nil)

-- 4. A BEST row opens the menu too, and hiding the hunted mob moves on.
row = RowFor("Lady Testgazer")
row:GetScript("OnClick")(row, "RightButton")
check("BEST rows open the menu", menu:IsShown() and menu.lines[2].label:GetText() == L["Hide from Zone Board"])
ns.HideMenu.frame:Hide()
ZoneBoard:SetTab("finish")
UI:Draw()
ZoneBoard:StartHunt("Lady Testgazer")
check("hunting her", ZoneBoard.hunt and ZoneBoard.hunt.target == "Lady Testgazer")
UI:HideMob(ZONE, "Lady Testgazer")
check("hiding the hunted mob moves the hunt on", ZoneBoard.hunt == nil or ZoneBoard.hunt.target ~= "Lady Testgazer",
    ZoneBoard.hunt and ZoneBoard.hunt.target)
check("two hidden reads 2", (function()
    UI:HideMob(ZONE, "Test Wolf")
    return UI.foot:GetText():find(L.Format("%d hidden here.", 2), 1, true) ~= nil
end)(), UI.foot:GetText())
ZoneBoard:Unskip(ZONE)
ZoneBoard:StopHunt()
UI:Draw()

-- 5.
row = RowFor("Test Wolf")
row:GetScript("OnClick")(row, "RightButton")
menu.lines[1]:GetScript("OnClick")(menu.lines[1])
check("Take Me There picks the row", UI.picks.finish == "Test Wolf")
check("and hunts it", ZoneBoard.hunt and ZoneBoard.hunt.target == "Test Wolf", ZoneBoard.hunt and ZoneBoard.hunt.target)

-- Every new word is in every language.
for _, word in ipairs({ "Hide from Zone Board", "%d hidden here.", "Show Again",
    "%s is off the Zone Board here. Show Again at the bottom of the board brings it back." }) do
    for _, code in ipairs({ "deDE", "frFR", "esES", "ruRU", "zhCN" }) do
        local file = io.open(lfs_cwd .. "/Locale/" .. code .. ".lua", "r")
        local text = file and file:read("*a") or ""
        if file then file:close() end
        check(code .. " has " .. word, text:find('L["' .. word .. '"] =', 1, true) ~= nil)
    end
end

suite.done()
