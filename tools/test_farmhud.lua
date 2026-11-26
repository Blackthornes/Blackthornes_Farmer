-- The Farm HUD: a see-through ring of your saved spots in the middle of the
-- screen.
--
-- What matters: it is off until turned on, and costs nothing while off; it
-- lets clicks through but for its close gem, which turns it off; it hides in
-- a fight and inside dungeons; spots sit the right way round (north up, east
-- right) and only within the rim; a spot still growing back is hollow; My
-- Professions Only counts here as on the maps; the route's next stop gets a
-- line and its name with how far; standing still redraws nothing; the size,
-- the Settings box, /farm hud and the key all reach it.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("farmhud")

local wall = 1000000
local ns = env.Load({ ui = true })
local Gathering, FarmHUD = ns.Gathering, ns.FarmHUD

_G.time = function() return wall end
_G.C_Map.GetMapWorldSize = function(mapID)
    if mapID == 37 then return 3000, 2000 end
    return nil
end

local inInstance, inCombat = false, false
_G.IsInInstance = function() return inInstance end
_G.InCombatLockdown = function() return inCombat end
local facing = 0
_G.GetPlayerFacing = function() return facing end

-- Both skills known, so My Professions Only shows herbs and ore.
local ALL = { Herbalism = true, Mining = true, Fishing = true }
ns.MapMarkers.ReadKnown = function() return ALL end

for _, module in ipairs(ns.moduleOrder) do
    if module.OnEnable then module:OnEnable() end
end

env.world.mapID = 37
env.world.position = { 0.45, 0.68 }

--------------------------------------------------------------------------------
-- Off by default
--------------------------------------------------------------------------------

suite.check("off by default", FarmHUD.IsOn() == false)
suite.check("nothing is built while it is off", FarmHUD.frame == nil)
suite.check("nothing is saved while it is off", ns.db.farmHud == nil)
suite.check("Medium unless picked", FarmHUD.Size() == "medium")

--------------------------------------------------------------------------------
-- Spots on the ring
--------------------------------------------------------------------------------

-- 100 yards east, 50 yards north, and one far past the rim (400 yards).
Gathering:AddSpot(37, 0.45 + 100 / 3000, 0.68, "Copper Vein", "ore")
Gathering:AddSpot(37, 0.45, 0.68 - 50 / 2000, "Silverleaf", "herb")
Gathering:AddSpot(37, 0.45 - 400 / 3000, 0.68, "Far Herb", "herb")

env.chat = {}
FarmHUD:SetOn(true)
local frame = FarmHUD.frame
suite.check("turning it on builds and shows it", frame and frame:IsShown())
suite.check("it says so in chat", (env.chat[#env.chat] or ""):find("The Farm HUD is on.", 1, true),
    env.chat[#env.chat])
suite.check("it sits in the middle of the screen", frame._point and frame._point[1] == "CENTER")
suite.check("it never sits over windows", frame._strata == "BACKGROUND")
suite.check("Medium is 420 pixels across", frame._width == 420, frame._width)
suite.check("it has a close gem", frame.close ~= nil)

local function Placed()
    local list = {}
    for _, dot in ipairs(frame.dots) do
        if dot:IsShown() then list[#list + 1] = dot end
    end
    return list
end

local dots = Placed()
suite.check("two spots in reach, the far one left off", #dots == 2, #dots)

-- 250 yards is the rim, 210 pixels at Medium.
local function Near(a, b) return math.abs(a - b) < 0.5 end
local found = {}
for _, dot in ipairs(dots) do
    local p = dot._point
    found[#found + 1] = { x = p[4], y = p[5] }
end
table.sort(found, function(a, b) return a.y < b.y end)
suite.check("east is to the right", Near(found[1].x, 100 / 250 * 210) and Near(found[1].y, 0),
    found[1].x .. "," .. found[1].y)
suite.check("north is up", Near(found[2].x, 0) and Near(found[2].y, 50 / 250 * 210),
    found[2].x .. "," .. found[2].y)

--------------------------------------------------------------------------------
-- Standing still
--------------------------------------------------------------------------------

local draws = 0
local near = FarmHUD.Near
FarmHUD.Near = function(...) draws = draws + 1; return near(...) end
FarmHUD:Step(1)
FarmHUD:Step(1)
suite.check("standing still draws nothing again", draws == 0, draws)

env.world.position = { 0.45 + 10 / 3000, 0.68 }
FarmHUD:Step(1)
suite.check("moving draws again", draws == 1, draws)
suite.check("a short move keeps the near list",
    FarmHUD.near and FarmHUD.near.x == 0.45, FarmHUD.near and FarmHUD.near.x)
env.world.position = { 0.45 + 60 / 3000, 0.68 }
FarmHUD:Step(1)
suite.check("a longer move makes the near list again",
    FarmHUD.near and FarmHUD.near.x == 0.45 + 60 / 3000)
FarmHUD.Near = near
env.world.position = { 0.45, 0.68 }
FarmHUD:Step(1)

--------------------------------------------------------------------------------
-- Hollow until seen up (Trent, 2026-11-26): a dot fills only once the node
-- there is seen, as the node you face, and stays filled until you gather it
-- or SEEN_FOR passes. A grow-back time alone never fills it.
--------------------------------------------------------------------------------

local silver
for _, each in ipairs(Gathering:SpotsOn(37)) do
    if each.node == "Silverleaf" then silver = each end
end
local backAt = ns.Respawn.BackAt
ns.Respawn.BackAt = function() return wall - 1 end
suite.check("a spot whose time says back is still hollow", FarmHUD.IsUp(silver, wall) == false)
ns.Respawn.BackAt = backAt

local function Dots()
    local filled, hollow = 0, 0
    for _, dot in ipairs(frame.dots) do
        if dot:IsShown() then
            if dot._texture and dot._texture:find("HudDot$") then filled = filled + 1 else hollow = hollow + 1 end
        end
    end
    return filled, hollow
end
local setTexture = frame.dots[1].SetTexture
for _, dot in ipairs(frame.dots) do
    dot.SetTexture = function(self, file) self._texture = file end
end
FarmHUD.key = nil
FarmHUD:Draw()
local filled, hollow = Dots()
suite.check("every dot starts hollow", filled == 0 and hollow == 2, filled .. "/" .. hollow)

-- Facing the Silverleaf 50 yards north... within reach of the saved spot.
local realGUID, realName = _G.UnitGUID, _G.UnitName
local soft = { guid = "GameObject-0-1-2-3-4-5", name = "Silverleaf" }
_G.UnitGUID = function(unit)
    if unit == "softinteract" then return soft.guid end
    return realGUID and realGUID(unit)
end
_G.UnitName = function(unit)
    if unit == "softinteract" then return soft.name end
    return realName and realName(unit)
end
env.world.position = { 0.45, 0.68 - 40 / 2000 }
local fire = ns.eventFrame:GetScript("OnEvent")
fire(ns.eventFrame, "PLAYER_SOFT_INTERACT_CHANGED")
suite.check("facing the node marks its spot up", FarmHUD.IsUp(silver, wall) == true)
FarmHUD:Draw()
filled, hollow = Dots()
suite.check("its dot fills", filled == 1 and hollow == 1, filled .. "/" .. hollow)

-- A node of that name far from any saved spot marks nothing.
local copper
for _, each in ipairs(Gathering:SpotsOn(37)) do
    if each.node == "Copper Vein" then copper = each end
end
soft.name = "Copper Vein"
fire(ns.eventFrame, "PLAYER_SOFT_INTERACT_CHANGED")
suite.check("a node far from its saved spot marks nothing", FarmHUD.IsUp(copper, wall) == false)

-- A creature is never a node.
env.world.position = { 0.45 + 100 / 3000, 0.68 }
soft.guid = "Creature-0-1-2-3-4-5"
fire(ns.eventFrame, "PLAYER_SOFT_INTERACT_CHANGED")
suite.check("a creature marks nothing", FarmHUD.IsUp(copper, wall) == false)
soft.guid = "GameObject-0-1-2-3-4-6"

-- Gathered after it was seen: hollow again.
local oldLast = silver.last
silver.last = wall + 5
suite.check("gathered after it was seen, it goes hollow", FarmHUD.IsUp(silver, wall + 6) == false)
silver.last = oldLast
suite.check("seen up lasts a while", FarmHUD.IsUp(silver, wall + FarmHUD.SEEN_FOR - 1) == true)
suite.check("then goes hollow again", FarmHUD.IsUp(silver, wall + FarmHUD.SEEN_FOR + 1) == false)

for _, dot in ipairs(frame.dots) do dot.SetTexture = setTexture end
_G.UnitGUID, _G.UnitName = realGUID, realName
env.world.position = { 0.45, 0.68 }
FarmHUD:Step(1)

--------------------------------------------------------------------------------
-- My Professions Only
--------------------------------------------------------------------------------

ns.MapMarkers.ReadKnown = function() return { Herbalism = true } end
ns.MapMarkers.known = nil
ns.MapMarkers.spotsKept = nil
FarmHUD.key = nil
FarmHUD:Draw()
suite.check("only the skills you know", #Placed() == 1, #Placed())
ns.MapMarkers.ReadKnown = function() return ALL end
ns.MapMarkers.known = nil
ns.MapMarkers.spotsKept = nil
FarmHUD.key = nil
FarmHUD:Draw()
suite.check("both again", #Placed() == 2, #Placed())

--------------------------------------------------------------------------------
-- The route's next stop
--------------------------------------------------------------------------------

suite.check("no route, no line", not frame.nextLabel:IsShown())
local stop = Gathering:SpotsOn(37)[1]
for _, each in ipairs(Gathering:SpotsOn(37)) do
    if each.node == "Copper Vein" then stop = each end
end
-- The route's plan: the stop the Route list and the minimap call next.
local planNext
local realPlan = ns.GatherRoute.Plan
ns.GatherRoute.Plan = function()
    return { map = 37, nextStop = planNext and { spot = planNext } or nil }
end
planNext = stop
ns.GatherRoute.run = { aimed = stop, visited = {}, picked = {} }
FarmHUD:Draw()
suite.check("a running route shows its next stop", frame.nextLabel:IsShown())
suite.check("named with how far", frame.nextLabel:GetText() == "Copper Vein, 100 yards",
    frame.nextLabel:GetText())
suite.check("with a dotted line", frame.dashes[1]:IsShown())

-- A stop past the rim is held to the rim.
local farStop
for _, each in ipairs(Gathering:SpotsOn(37)) do
    if each.node == "Far Herb" then farStop = each end
end
ns.GatherRoute.run.aimed, planNext = farStop, farStop
FarmHUD:Draw()
local p = frame.nextDot._point
suite.check("a stop past the rim is held inside it", p[4] < 0 and p[4] > -210, p[4])
suite.check("its real distance is still named", frame.nextLabel:GetText() == "Far Herb, 400 yards",
    frame.nextLabel:GetText())
-- Trent's screenshot (2026-11-26): the route picked a new next stop on its
-- own (the Route list and the minimap moved on to it), and the HUD kept
-- pointing at the stop it had been aimed at.
local silverleaf
for _, each in ipairs(Gathering:SpotsOn(37)) do
    if each.node == "Silverleaf" then silverleaf = each end
end
ns.GatherRoute.run.aimed, planNext = stop, silverleaf
FarmHUD:Draw()
suite.check("the HUD follows the route's new next stop", frame.nextLabel:GetText() == "Silverleaf, 50 yards",
    frame.nextLabel:GetText())

ns.GatherRoute.run, planNext = nil, nil
FarmHUD:Draw()
suite.check("the line goes when the route stops", not frame.nextLabel:IsShown())
ns.GatherRoute.Plan = realPlan

--------------------------------------------------------------------------------
-- Turning
--------------------------------------------------------------------------------

local turned
frame.arrow.SetRotation = function(_, value) turned = value end
facing = 1.5
FarmHUD:Step(1)
suite.check("the arrow turns with you", turned == 1.5, turned)

--------------------------------------------------------------------------------
-- Hiding
--------------------------------------------------------------------------------

inCombat = true
fire(ns.eventFrame, "PLAYER_REGEN_DISABLED")
suite.check("it hides in a fight", not frame:IsShown())
inCombat = false
fire(ns.eventFrame, "PLAYER_REGEN_ENABLED")
suite.check("and comes back after", frame:IsShown())

inInstance = true
fire(ns.eventFrame, "PLAYER_ENTERING_WORLD")
suite.check("it hides inside a dungeon", not frame:IsShown())
inInstance = false
fire(ns.eventFrame, "PLAYER_ENTERING_WORLD")
suite.check("and comes back outside", frame:IsShown())

--------------------------------------------------------------------------------
-- Size
--------------------------------------------------------------------------------

suite.check("Large can be picked", FarmHUD:SetSize("large"))
suite.check("Large is 560 pixels across", frame._width == 560, frame._width)
suite.check("a size is saved", ns.db.farmHudSize == "large")
suite.check("nonsense is refused", FarmHUD:SetSize("huge") == false)
FarmHUD:SetSize("medium")
suite.check("Medium saves nothing", ns.db.farmHudSize == nil)

--------------------------------------------------------------------------------
-- Closing
--------------------------------------------------------------------------------

env.chat = {}
frame.close:Click()
suite.check("the close gem turns it off", FarmHUD.IsOn() == false and not frame:IsShown())
suite.check("off says so", (env.chat[#env.chat] or ""):find("The Farm HUD is off.", 1, true),
    env.chat[#env.chat])
suite.check("off saves nothing", ns.db.farmHud == nil)

--------------------------------------------------------------------------------
-- The command and the key
--------------------------------------------------------------------------------

ns.commands.hud.fn("")
suite.check("/farm hud turns it on", FarmHUD.IsOn())
ns.commands.hud.fn("off")
suite.check("/farm hud off turns it off", not FarmHUD.IsOn())
ns.commands.hud.fn("size small")
suite.check("/farm hud size small", FarmHUD.Size() == "small")
FarmHUD:SetSize("medium")
suite.check("the key has a name", _G.BINDING_NAME_BLACKTHORNESFARMER_HUD == "Show or Hide Farm HUD")

local bindings = io.open(lfs_cwd .. "/Bindings.xml"):read("*a")
suite.check("the key is in Bindings.xml", bindings:find("BLACKTHORNESFARMER_HUD", 1, true) ~= nil)

--------------------------------------------------------------------------------
-- Settings
--------------------------------------------------------------------------------

ns.SettingsUI:Build()
local controls = ns.SettingsUI.controls
suite.check("the Map page has the box", controls.farmHud ~= nil)
suite.check("and the size", controls.farmHudSize ~= nil)
ns.SettingsUI:Refresh()
suite.check("the box starts clear", controls.farmHud:GetChecked() == false)

suite.done()
