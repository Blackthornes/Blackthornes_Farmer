-- The kill heat map (a test feature, 2026-10-17).
--
-- What must hold:
--   1. Off by default, and nothing is recorded while both switches are off.
--   2. A kill adds one to its map cell for its mob; a spot the client will
--      not give adds nothing, and the kill still counts.
--   3. The save stays small: cell and mob caps.
--   4. Hidden mobs are left out, and one mob can be picked.
--   5. /farm heat turns it on and off and forgets only on "clear confirm".
--   6. The Settings controls exist.
--   7. Show on Map: a mob or an item from the search aims the glow, an
--      item's mobs weighted by your own drop rate; the map opens where the
--      glow is; the same row again, or the card's button, stops tracking.
--   8. The maps glow only while a mob or an item is tracked, and the glow's
--      outer edge has an outline that closes round it.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("heat")

local ns = env.Load({ ui = true })
for _, module in ipairs(ns.moduleOrder) do
    if module.OnEnable then module:OnEnable() end
end

local Heat = ns.Heat

-- 1.
suite.check("world map is off by default", ns.db.heatWorld == false)
suite.check("minimap is off by default", ns.db.heatMinimap == false)
suite.check("nothing is asking for it", not Heat.Recording())

local where = { 1411, 0.5, 0.5 }
ns.Harvest.PlayerMapPosition = function()
    if where then return where[1], where[2], where[3] end
end

Heat:Kill("Plainstrider")
suite.check("nothing recorded while off", select(3, Heat:Summary()) == 0)

-- 2.
Heat:SetWorld(true)
Heat:Kill("Plainstrider")
Heat:Kill("Plainstrider")
local list, most = Heat:Cells(1411)
suite.check("two kills share a cell", #list == 1 and most == 2)
suite.check("the cell is the middle of the map", list[1].cell == Heat.CellOf(0.5, 0.5))

where = nil
Heat:Kill("Plainstrider")
suite.check("an unreadable spot adds nothing", select(3, Heat:Summary()) == 1)

suite.check("cell maths keeps to the edges", Heat.CellOf(-1, 2) == 99 * 100 and Heat.CellOf(1, 1) == 9999)
local cx, cy = Heat.CellCentre(Heat.CellOf(0.255, 0.755))
suite.check("a cell's middle is inside it", math.abs(cx - 0.255) < 0.01 and math.abs(cy - 0.755) < 0.01)

-- 3.
for i = 0, Heat.MAX_CELLS + 20 do
    Heat:Note(1, (i % 100) / 100 + 0.001, math.floor(i / 100) / 100 + 0.001, "Boar")
end
local _, _, cells = Heat:Summary()
suite.check("a mob keeps at most MAX_CELLS cells", cells <= 1 + Heat.MAX_CELLS)
local before = Heat.version
suite.check("a full mob still counts a cell it has", Heat:Note(1, 0.001, 0.001, "Boar"))
suite.check("but not a new one", not Heat:Note(1, 0.999, 0.999, "Boar"))
for i = 1, Heat.MAX_MOBS + 5 do Heat:Note(2, 0.5, 0.5, "Mob" .. i) end
local _, lines = Heat:Summary()
suite.check("a map keeps at most MAX_MOBS mobs", lines <= 2 + Heat.MAX_MOBS)
suite.check("bad input is refused", not Heat:Note("x", 0.5, 0.5, "A") and not Heat:Note(1, 0.5, 0.5, ""))

-- 4.
Heat:Clear()
Heat:Note(7, 0.1, 0.1, "Wolf")
Heat:Note(7, 0.9, 0.9, "Bear")
suite.check("all mobs shows both", #Heat:Cells(7) == 2)
Heat:SetMob("Wolf")
suite.check("one mob shows only its own", #Heat:Cells(7) == 1)
Heat:SetMob("")
suite.check("empty name means every mob", Heat:Mob() == nil)
ns.DB:Hide("source", "Bear")
suite.check("a hidden mob is left out", #Heat:Cells(7) == 1)

-- 5.
ns.HandleSlash("heat off")
suite.check("/farm heat off", not Heat.WorldOn() and not Heat.MinimapOn())
ns.HandleSlash("heat minimap on")
suite.check("/farm heat minimap on", Heat.MinimapOn() and not Heat.WorldOn())
ns.HandleSlash("heat strength most")
suite.check("/farm heat strength most", Heat:Level() == 3)
ns.HandleSlash("heat mob Wolf")
suite.check("/farm heat mob", Heat:Mob() == "Wolf")
ns.HandleSlash("heat mob all")
suite.check("/farm heat mob all", Heat:Mob() == nil)
ns.HandleSlash("heat clear")
suite.check("clear alone forgets nothing", select(3, Heat:Summary()) > 0)
ns.HandleSlash("heat clear confirm")
suite.check("clear confirm forgets", select(3, Heat:Summary()) == 0)

-- 7.
Heat:SetWorld(true)
ns.DB:Unhide("source", "Bear")
Heat:Note(7, 0.1, 0.1, "Wolf")
Heat:Note(7, 0.1, 0.1, "Wolf")
Heat:Note(7, 0.9, 0.9, "Bear")
Heat:Note(8, 0.5, 0.5, "Bear")
local keptRecords = ns.Harvest.records
ns.Harvest.records = {
    ["Wolf|Mulgore|"] = { mob = "Wolf", zone = "Mulgore", corpses = 10, items = {
        ["Wolf Fang"] = { name = "Wolf Fang", id = 900, count = 5, corpses = 5 },
    } },
    ["Bear|Mulgore|"] = { mob = "Bear", zone = "Mulgore", corpses = 10, items = {
        ["Wolf Fang"] = { name = "Wolf Fang", id = 900, count = 1, corpses = 1 },
    } },
    ["Boar|Mulgore|"] = { mob = "Boar", zone = "Mulgore", corpses = 10, items = {} },
}

local mobs = Heat:ItemMobs("Wolf Fang")
suite.check("an item's mobs, likeliest first", #mobs == 2 and mobs[1].mob == "Wolf"
    and math.abs(mobs[1].chance - 0.5) < 1e-9 and math.abs(mobs[2].chance - 0.1) < 1e-9)
suite.check("a mob with spots has them", Heat:HasSpots("Wolf") and not Heat:HasSpots("Boar"))
suite.check("an item with a spotted mob has spots", Heat:ItemHasSpots("Wolf Fang")
    and not Heat:ItemHasSpots("Nothing"))

local opened
_G.OpenWorldMap = function(mapID) opened = mapID end
suite.check("Map on an item aims the glow", Heat:ShowOnMap("item", "Wolf Fang")
    and Heat:Item() == "Wolf Fang" and Heat:Mob() == nil)
local itemCells = Heat:Cells(7)
local wolfCell, bearCell
for _, entry in ipairs(itemCells) do
    if entry.cell == Heat.CellOf(0.1, 0.1) then wolfCell = entry.count end
    if entry.cell == Heat.CellOf(0.9, 0.9) then bearCell = entry.count end
end
suite.check("an item's glow is weighted by drop rate", wolfCell == 2 and math.abs(bearCell - 0.2) < 1e-9)
suite.check("the map opens where the glow is most", opened == 7)
suite.check("nothing new is saved for an item", ns.db.heatMob == nil)

local text, lines = ns.HeatUI.CardText()
suite.check("the card says what it shows", text:find("Showing:", 1, true) and text:find("Wolf Fang", 1, true))
suite.check("the card lists the mobs with their rate", lines[1] == "Wolf (50% a kill)" and lines[2] == "Bear (10% a kill)")

suite.check("the same row again shows all", not Heat:ShowOnMap("item", "Wolf Fang") and Heat:Item() == nil)

opened = nil
suite.check("Map on a mob picks the mob", Heat:ShowOnMap("mob", "Bear") and Heat:Mob() == "Bear")
suite.check("a mob's map is where it was killed most", opened == 7 or opened == 8)
local _, mobLines = ns.HeatUI.CardText()
suite.check("a mob's card has no rate lines", #mobLines == 0)
Heat:ShowAll()
suite.check("Stop Tracking goes back to every mob", Heat:Mob() == nil and Heat:Item() == nil
    and Heat:TargetKey() == "all")

ns.DB:Hide("source", "Bear")
suite.check("a hidden mob is left out of an item", #Heat:ItemMobs("Wolf Fang") == 1)
ns.DB:Unhide("source", "Bear")

local inFight = _G.InCombatLockdown
_G.InCombatLockdown = function() return true end
opened = nil
Heat:ShowOnMap("mob", "Wolf")
suite.check("the map is not opened in a fight", opened == nil and Heat:Mob() == "Wolf")
_G.InCombatLockdown = inFight
Heat:ShowAll()

-- The search's Map button.
suite.check("a mob row gets a Map button", ns.UI.MapTarget({ type = "source",
    source = { name = "Wolf", kind = "mob" } }) == "mob")
suite.check("a node row does not", ns.UI.MapTarget({ type = "source",
    source = { name = "Copper Vein", kind = "mining" } }) == nil)
suite.check("an item row does", ns.UI.MapTarget({ type = "item", item = { name = "Wolf Fang" } }) == "item")
suite.check("world drops do not", ns.UI.MapTarget({ type = "item",
    item = { name = "World drops", worldDrops = true } }) == nil)
-- Drawn in a real search: the mob rows get the button in a slot of its own.
local mobName
for _, source in ipairs(ns.DB:GetItem("Wool Cloth").sources) do
    if (source.kind or "mob") == "mob" and source.name then mobName = source.name break end
end
Heat:Note(9, 0.3, 0.3, mobName)
local searched = pcall(function() ns.UI:Search("wool cloth") end)
suite.check("a search with the heat map on draws", searched)
suite.check("the Map slot opens up", ns.UI.columns.map.w > 0)
local shownMob, shownItem
for index = 1, #ns.UI.list.rows do
    local r = ns.UI.list.rows[index]
    if r:IsShown() and r.data and r.map:IsShown() then
        if r.data.type == "source" then shownMob = true end
        if r.data.type == "item" then shownItem = true end
    end
end
suite.check("mob rows and the item heading show Map", shownMob and shownItem)
Heat:SetWorld(false)
ns.UI:Search("wool cloth")
local anyMap = false
for index = 1, #ns.UI.list.rows do
    local r = ns.UI.list.rows[index]
    if r:IsShown() and r.map:IsShown() then anyMap = true end
end
suite.check("no Map buttons with the heat map off", not anyMap and ns.UI.columns.map.w == 0)
suite.check("no Map button while the heat map is off", ns.UI.MapTarget({ type = "source",
    source = { name = "Wolf", kind = "mob" } }) == nil)
ns.Harvest.records = keptRecords

-- Drawing never fails, in a fight or out.
local ok = pcall(function() ns.HeatUI:Refresh() end)
suite.check("drawing does not raise", ok)

-- 8.
local outline = ns.HeatUI.Outline({ { cell = Heat.CellOf(0.505, 0.505), count = 1 } })
-- One cell grown to three by three: a square with its corners cut: four corners and two pieces a side.
suite.check("one cell's outline has twelve pieces", #outline == 12)
local ends = {}
for _, piece in ipairs(outline) do
    for _, at in ipairs({ { piece[1], piece[2] }, { piece[3], piece[4] } }) do
        local k = ("%.4f,%.4f"):format(at[1], at[2])
        ends[k] = (ends[k] or 0) + 1
    end
end
local closed = true
for _, n in pairs(ends) do if n ~= 2 then closed = false end end
suite.check("the outline closes round the glow", closed)
local outside = true
for _, piece in ipairs(outline) do
    for _, at in ipairs({ { piece[1], piece[2] }, { piece[3], piece[4] } }) do
        local far = math.max(math.abs(at[1] - 0.505), math.abs(at[2] - 0.505))
        if far < 0.0099 then outside = false end
    end
end
suite.check("the outline sits outside the cell", outside)
suite.check("a corner cell's outline stays on the map", (function()
    for _, piece in ipairs(ns.HeatUI.Outline({ { cell = 0, count = 1 } })) do
        for _, v in ipairs(piece) do if v < 0 or v > 1 then return false end end
    end
    return true
end)())
suite.check("no cells, no outline", #ns.HeatUI.Outline({}) == 0)

local keptView = ns.MapMarkers.WorldView
ns.MapMarkers.WorldView = function()
    return { mapID = 9, width = 1000, height = 700, canvas = env.Stub() }
end
Heat:SetWorld(true)
Heat:ShowAll()
ns.HeatUI:Refresh()
suite.check("nothing tracked, no glow on the map", ns.HeatUI.job == nil
    and (not ns.HeatUI.world or ns.HeatUI.world.used == 0))
Heat:SetMob(mobName)
ns.HeatUI:Refresh()
for _ = 1, 20 do ns.HeatUI:Slice() end
suite.check("tracking a mob, the map glows", ns.HeatUI.world and ns.HeatUI.world.used > 0)
suite.check("and its edge is outlined", (ns.HeatUI.world.edgesUsed or 0) > 0)
Heat:ShowAll()
suite.check("stop tracking, the glow goes", ns.HeatUI.world.used == 0
    and ns.HeatUI.world.edgesUsed == 0)
ns.MapMarkers.WorldView = keptView

-- The card says when there is nothing to show yet, and stays inside the map.
Heat:SetMob(mobName)
suite.check("a mob with spots has glow", ns.HeatUI.HasGlow())
Heat:SetMob("Never Killed Here")
suite.check("a mob with no spots has none yet", not ns.HeatUI.HasGlow())
Heat:ShowAll()
ns.db.heatCardX, ns.db.heatCardY = 5000, -50
local okPlace = pcall(function()
    _G.WorldMapFrame = _G.WorldMapFrame or env.Stub()
    Heat:SetMob(mobName)
    ns.HeatUI:UpdateCard()
    ns.HeatUI:PlaceCard()
    ns.HeatUI:KeepCardPlace()
end)
suite.check("placing and dragging the card does not raise", okPlace)
Heat:ShowAll()
ns.db.heatCardX, ns.db.heatCardY = nil, nil
Heat:SetWorld(false)

-- 6.
ns.SettingsUI:Show()
local c = ns.SettingsUI.controls
suite.check("Settings has the controls", c.heatWorld ~= nil and c.heatMinimap ~= nil and c.heatLevel ~= nil)

suite.done()
