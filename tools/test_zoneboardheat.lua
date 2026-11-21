-- The Zone Board's heat map eyes (the owner said build it, 2026-11-18, from
-- a mockup whose words he approved).
--
-- What must hold:
--   1. No eye while Kill Heat is off; one on every row once it is on.
--   2. An eye turns that mob's glow on and off, and is kept in heatMobs.
--   3. Several mobs at once add up into one glow, and the card lists them.
--   4. A pick goes by itself when its mob is finished on the board; one
--      shown with the Map button stays.
--   5. The Map button and Stop Tracking clear the picks; an item stops when
--      an eye is turned on.
--   6. A tap sets only the eyes: the board is not drawn again.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("zoneboardheat")
local check = suite.check

local ns = env.Load({ ui = true })
local L = ns.L
local ZoneBoard, UI, Heat, HeatUI = ns.ZoneBoard, ns.ZoneBoardUI, ns.Heat, ns.HeatUI
local Tracker = ns.Tracker

local ZONE = "Testwood Vale"
env.world.zone = ZONE

local function Mob(item, id, name, location, level, coords)
    ns.DB:RegisterItem({ name = item, id = id, category = "misc",
        sources = { { name = name, zone = ZONE, location = location, minLevel = level, maxLevel = level + 1,
            chance = 10, coords = coords, provenance = "forever" } } })
end
Mob("Wolf Pelt Test", 99101, "Test Wolf", "North Tide", 10, { 40, 30 })
Mob("Spider Silk Test", 99102, "Test Spider", "Fenris Isle", 12, { 60, 70 })
Mob("Bear Claw Test", 99103, "Test Bear", "Olsen's Farthing", 14, { 50, 50 })

local where = { 1421, 0.4, 0.3 }
ns.Harvest.PlayerMapPosition = function() return where[1], where[2], where[3] end

local serial = 0
local function Loot(mob)
    serial = serial + 1
    env.world.target = { name = mob, level = 10, dead = true, guid = "ZH-" .. serial }
    env.world.loot = { { name = "12 Copper", money = true } }
    Tracker:OnLoot()
end

ZoneBoard:SetOn(true)
for _ = 1, 5 do Loot("Test Wolf") end
for _ = 1, 18 do Loot("Test Spider") end
ZoneBoard:List(ZONE, true)
UI:Show()
ZoneBoard:SetTab("finish")
UI:Draw()

local function RowFor(name)
    for _, row in ipairs(UI.rows) do
        if row:IsShown() and row.data and row.data.name == name then return row end
    end
end

-- 1.
check("Kill Heat is off to start", not Heat.Recording())
check("no eye while Kill Heat is off", RowFor("Test Wolf") and not RowFor("Test Wolf").eye:IsShown())
Heat:SetMinimap(true)
check("turning Kill Heat on shows the eyes", RowFor("Test Wolf").eye:IsShown()
    and RowFor("Test Spider").eye:IsShown() and RowFor("Test Bear").eye:IsShown())
check("an eye starts off", not RowFor("Test Wolf").eye.on)

-- Kills with a spot now that Kill Heat records.
for _ = 1, 2 do Loot("Test Wolf") end
where = { 1421, 0.6, 0.7 }
Loot("Test Spider")
check("a mob with no spot yet has a dim eye", RowFor("Test Bear").eye:GetAlpha() < 1)
check("a mob with spots has a bright one", RowFor("Test Wolf").eye:GetAlpha() == 1)

-- 2. and 6.
local drew = 0
local realDraw = UI.Draw
UI.Draw = function(self, ...) drew = drew + 1; return realDraw(self, ...) end
RowFor("Test Wolf").eye:Click()
UI.Draw = realDraw
check("tapping the eye picks the mob", Heat:IsPicked("Test Wolf") and ns.db.heatMobs["Test Wolf"] == true)
check("the eye lights up", RowFor("Test Wolf").eye.on == true and RowFor("Test Wolf").eye.glow:IsShown())
check("a tap does not draw the board again", drew == 0, drew)
check("the maps glow for it", HeatUI.Tracking() and HeatUI.HasGlow())
local list = Heat:Cells(1421)
check("only that mob's spots glow", #list == 1 and list[1].cell == Heat.CellOf(0.4, 0.3), #list)
local card = HeatUI.CardText()
check("one mob reads as today on the card", card and card.name == "Test Wolf" and #card.rows == 0)

-- The hover words.
GameTooltip._lines = {}
RowFor("Test Wolf").eye:GetScript("OnEnter")(RowFor("Test Wolf").eye)
check("the hover on an eye that is on", GameTooltip._lines[1] == L["Hide from Map"], GameTooltip._lines[1])
GameTooltip._lines = {}
RowFor("Test Bear").eye:GetScript("OnEnter")(RowFor("Test Bear").eye)
check("the hover on an eye that is off, with no spot yet", GameTooltip._lines[1] == L["Show on Map"]
    and GameTooltip._lines[2] == L["Kill a few first and it will show here."], GameTooltip._lines[2])

-- 3.
RowFor("Test Spider").eye:Click()
list = Heat:Cells(1421)
check("two mobs glow together", #list == 2, #list)
card = HeatUI.CardText()
check("the card counts them", card.name == L.Format("%d mobs", 2), card.name)
check("and lists each one", #card.rows == 2 and card.rows[1].mob == "Test Spider" and card.rows[2].mob == "Test Wolf")
check("the status line counts them", Heat.ForWhat() == L.Format("%d mobs", 2))

-- Tapping again turns one off.
RowFor("Test Wolf").eye:Click()
check("the same eye again turns it off", not Heat:IsPicked("Test Wolf") and RowFor("Test Wolf").eye.on == false)
check("the other stays on", Heat:IsPicked("Test Spider"))

-- 4. The spider is picked and also shown with the Map button.
Heat:SetPicked("Test Wolf", true)
Loot("Test Spider")
check("the spider is finished", ZoneBoard.Kills("Test Spider", ZONE) == Tracker.MIN_KILLS)
check("a finished mob's pick goes by itself", not Heat:IsPicked("Test Spider"))
check("the other pick stays", Heat:IsPicked("Test Wolf"))

ns.db.heatMob = "Test Wolf"
for _ = 1, 13 do Loot("Test Wolf") end
check("the wolf is finished", ZoneBoard.Kills("Test Wolf", ZONE) == Tracker.MIN_KILLS)
check("its pick went", not Heat:IsPicked("Test Wolf"))
check("but the Map button's mob stays", Heat:Mob() == "Test Wolf" and HeatUI.Tracking())

-- 5.
Heat:ShowAll()
Heat:SetPicked("Test Bear", true)
Heat:ShowOnMap("mob", "Test Wolf")
check("the Map button shows just its mob", Heat:Mob() == "Test Wolf" and not Heat:Picks())
Heat:SetPicked("Test Bear", true)
check("an eye after it keeps both", Heat:Mob() == "Test Wolf" and Heat:IsPicked("Test Bear"))
Heat:ShowOnMap("mob", "Test Wolf")
check("the Map button again stops only its mob", Heat:Mob() == nil and Heat:IsPicked("Test Bear"))
Heat:SetItem("Wolf Pelt Test")
check("an item clears the picks", Heat:Item() == "Wolf Pelt Test" and not Heat:Picks())
Heat:SetPicked("Test Bear", true)
check("an eye stops the item", Heat:Item() == nil and Heat:IsPicked("Test Bear"))
Heat:ShowAll()
check("Stop Tracking clears every pick", not Heat:Picks() and ns.db.heatMobs == nil and not HeatUI.Tracking())
check("and the eyes go dark", not RowFor("Test Bear").eye.on)

-- Kill Heat off again hides the eyes.
Heat:SetMinimap(false)
check("Kill Heat off hides the eyes", not RowFor("Test Bear").eye:IsShown())

suite.done()
