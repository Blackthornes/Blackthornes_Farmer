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

-- Drawing never fails, in a fight or out.
local ok = pcall(function() ns.HeatUI:Refresh() end)
suite.check("drawing does not raise", ok)

-- 6.
ns.SettingsUI:Show()
local c = ns.SettingsUI.controls
suite.check("Settings has the controls", c.heatWorld ~= nil and c.heatMinimap ~= nil and c.heatLevel ~= nil)

suite.done()
