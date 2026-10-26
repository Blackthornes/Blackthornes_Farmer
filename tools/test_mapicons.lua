-- Round icons and joined pins on the world map.
--
-- What matters: a pin's icon is cut round with a mask texture where the
-- client has them, else SetMask; pins of one kind that would sit on each
-- other at the zoom shown are drawn as one with a count, and pins of
-- different kinds never join; a joined pin shows the item its spots gave
-- most, turns to color once any spot should be back, and its hover says how
-- many spots, how many should be back and when the next is; the node
-- tooltip adds no grow-back line to Farmer's own pin; and a single pin works
-- as it did.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("mapicons")

local wall = 1000000

local ns = env.Load({ ui = true })
local Gathering, MapMarkers, Respawn = ns.Gathering, ns.MapMarkers, ns.Respawn

_G.GetTime = function() return 500 end
_G.time = function() return wall end

local ICON = { [2447] = 133939, [765] = 133938, [2770] = 135232 }
local NAME = { [2447] = "Peacebloom", [765] = "Silverleaf", [2770] = "Copper Ore" }
_G.C_Item = {
    GetItemIconByID = function(id) return ICON[id] end,
    GetItemNameByID = function(id) return NAME[id] end,
}

for _, module in ipairs(ns.moduleOrder) do
    if module.OnEnable then module:OnEnable() end
end

--------------------------------------------------------------------------------
-- Round icons
--------------------------------------------------------------------------------

do
    local frame, icon, used = env.Stub(), env.Stub(), {}
    local mask = env.Stub()
    frame.CreateMaskTexture = function() return mask end
    icon.AddMaskTexture = function(_, value) used.added = value end
    icon.SetMask = function() used.setMask = true end
    MapMarkers.RoundIcon(frame, icon)
    suite.check("a mask texture rounds the icon", used.added == mask and not used.setMask)

    local plain, plainIcon, seen = {}, env.Stub(), {}
    plainIcon.SetMask = function(_, value) seen.mask = value end
    plainIcon.AddMaskTexture = nil
    rawset(plainIcon, "AddMaskTexture", false)
    MapMarkers.RoundIcon(setmetatable(plain, {}), plainIcon)
    suite.check("SetMask only where there are no mask textures", type(seen.mask) == "string")
end

--------------------------------------------------------------------------------
-- Grouping
--------------------------------------------------------------------------------

local function Spot(x, y, node, kind, item, last, gathers)
    return { map = 37, x = x, y = y, node = node, kind = kind or "herb", item = item,
        last = last, gathers = gathers or 1 }
end

-- A 1000 by 700 canvas at zoom 1: 0.01 across is 10 pixels.
local spots = {
    Spot(0.30, 0.30, "Peacebloom", "herb", 2447),
    Spot(0.31, 0.30, "Silverleaf", "herb", 765),
    Spot(0.30, 0.31, "Peacebloom", "herb", 2447),
    Spot(0.305, 0.305, "Copper Vein", "ore", 2770),
    Spot(0.60, 0.60, "Peacebloom", "herb", 2447),
}
local groups = MapMarkers.Group(spots, 1000, 700, 1)
suite.check("close herbs join, the far one and the ore stay apart", #groups == 3, #groups)
suite.check("three herbs in the first pin", #groups[1].spots == 3 and groups[1].kind == "herb")
suite.check("the ore never joins a herb", groups[2].kind == "ore" and #groups[2].spots == 1)
suite.check("a joined pin sits in the middle of its spots",
    math.abs(groups[1].x - (0.30 + 0.31 + 0.30) / 3) < 1e-9)

local zoomed = MapMarkers.Group(spots, 1000, 700, 4)
suite.check("zoomed in, close spots stand apart again", #zoomed == 5, #zoomed)

-- A long line of spots never joins end to end: each pin keeps its anchor.
local line = {}
for index = 0, 5 do line[#line + 1] = Spot(0.1 + index * 0.012, 0.5, "Peacebloom") end
local chain = MapMarkers.Group(line, 1000, 700, 1)
suite.check("a line of spots is not one pin", #chain > 1, #chain)

suite.check("named for the node gathered most",
    MapMarkers.GroupNode(groups[1]) == "Peacebloom", MapMarkers.GroupNode(groups[1]))
suite.check("shows the item its spots gave most", MapMarkers:GroupIcon(groups[1]) == 133939)

--------------------------------------------------------------------------------
-- When a joined pin's spots grow back
--------------------------------------------------------------------------------

for _ = 1, 3 do Respawn:Learn(37, "Peacebloom", 600) end
local patch = {
    Spot(0.30, 0.30, "Peacebloom", "herb", 2447, wall - 900),
    Spot(0.30, 0.31, "Peacebloom", "herb", 2447, wall - 700),
    Spot(0.31, 0.30, "Peacebloom", "herb", 2447, wall - 300),
}
local lines = Respawn:GroupLines(patch, wall, "Peacebloom")
suite.check("says how many should be back", lines[1] and lines[1].known
    and lines[1].text:find("^2 should be back by now") ~= nil, lines[1] and lines[1].text)
suite.check("and when the next one is", lines[2] and lines[2].text:find("^Next back in about") ~= nil,
    lines[2] and lines[2].text)

local learning = Respawn:GroupLines({ Spot(0.1, 0.1, "Earthroot", "herb", nil, wall - 10) }, wall, "Earthroot")
suite.check("no time known yet says it is learning", #learning == 1 and learning[1].known == false)

--------------------------------------------------------------------------------
-- On the world map
--------------------------------------------------------------------------------

Gathering:ClearSpots()
local saved = Gathering:Spots()
for _, spot in ipairs(patch) do saved[#saved + 1] = spot end
saved[#saved + 1] = Spot(0.7, 0.7, "Copper Vein", "ore", 2770, wall - 10)
Gathering:SpotsChanged()

local canvas = env.Stub({ _width = 1000, _height = 700 })
_G.WorldMapFrame = env.Stub({ _shown = true })
WorldMapFrame.GetCanvas = function() return canvas end
WorldMapFrame.GetMapID = function() return 37 end
WorldMapFrame.ScrollContainer = { GetCanvasScale = function() return 1 end }

MapMarkers:Refresh()
local pool = MapMarkers.worldPool
suite.check("one pin for the patch and one for the vein", pool and pool.used == 2, pool and pool.used)

local herbPin, orePin
for index = 1, pool.used do
    local pin = pool.pins[index]
    if pin.group.kind == "herb" then herbPin = pin else orePin = pin end
end
suite.check("the joined pin shows its count", herbPin.count:GetText() == "3" and herbPin.count:IsShown())
suite.check("a single pin shows no count", not orePin.count:IsShown())
suite.check("the joined pin is in color once one spot is back", herbPin.back == true)
suite.check("the vein just taken is still grey", orePin.back == false)
suite.check("our own pins say so, for the node tooltip", herbPin.farmerMarker == true)

GameTooltip._lines = {}
herbPin:GetScript("OnEnter")(herbPin)
local text = table.concat(GameTooltip._lines, "\n")
suite.check("the hover counts the spots", text:find("3 spots, gathered 3 times") ~= nil, text)
suite.check("and says how many are back", text:find("2 should be back by now") ~= nil, text)
suite.check("and names the item", text:find("Peacebloom") ~= nil, text)

GameTooltip._lines = {}
orePin:GetScript("OnEnter")(orePin)
text = table.concat(GameTooltip._lines, "\n")
suite.check("a single pin's hover is as before", text:find("Copper Vein") == 1
    and text:find("spots") == nil, text)

--------------------------------------------------------------------------------
-- One grow-back line
--------------------------------------------------------------------------------

local tooltip = env.Stub({ _lines = {} })
tooltip.AddLine = function(self, value) self._lines[#self._lines + 1] = value end
tooltip.GetOwner = function() return herbPin end
_G.GameTooltipTextLeft1 = env.Stub({ _text = "Peacebloom" })
env.world.mapID, env.world.position = 37, { 0.3, 0.3 }
Respawn.added = nil
Respawn:OnTooltipShown(tooltip, false)
suite.check("the node tooltip adds nothing to a Farmer pin", #tooltip._lines == 0, #tooltip._lines)

tooltip._lines = {}
tooltip.GetOwner = function() return env.Stub() end
Respawn.added = nil
Respawn:OnTooltipShown(tooltip, false)
suite.check("a node in the world still gets its line", #tooltip._lines > 0, #tooltip._lines)

suite.done()
