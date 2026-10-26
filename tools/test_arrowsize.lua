-- Arrow Size (the owner, 2026-10-26): the whole arrow can be drawn at 50%,
-- 75% or 100%. 100% is the default and saves nothing, so nobody's arrow
-- changes until a size is picked, and a new size keeps the arrow's spot.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("arrowsize")

local ns = env.Load({ ui = true })
local ArrowUI = ns.ArrowUI
local db = ns.db

suite.check("full size until one is picked", ArrowUI.Scale() == 1 and ArrowUI.Size() == 100)
suite.check("nothing saved at first", db.arrowSize == nil)

ArrowUI:SetSize(75)
suite.check("75% is kept", db.arrowSize == 75 and ArrowUI.Scale() == 0.75 and ArrowUI.Size() == 75)
ArrowUI:SetSize(33)
suite.check("a size not offered is ignored", db.arrowSize == 75)
db.arrowSize = "junk"
suite.check("a bad save reads as full size", ArrowUI.Scale() == 1)
ArrowUI:SetSize(100)
suite.check("100% saves nothing", db.arrowSize == nil)

-- The spot is kept in the screen's own units: an arrow saved at full size
-- at 400, 300 is put back at 800, 600 in its own units at 50%.
local frame = ArrowUI:Build()
local placed
frame.SetPoint = function(_, point, rel, relPoint, x, y)
    placed = { point = point, x = x, y = y }
end
frame.SetScale = function(self, scale) self.scale = scale end
db.arrowX, db.arrowY = 400, 300
ArrowUI:SetSize(50)
suite.check("drawn at half size", frame.scale == 0.5)
suite.check("the spot stays on screen", placed and placed.point == "CENTER"
    and math.abs(placed.x - 800) < 0.01 and math.abs(placed.y - 600) < 0.01)
suite.check("the saved spot is untouched", db.arrowX == 400 and db.arrowY == 300)

-- Dragged at half size: the centre in its own units is saved in the screen's.
frame.GetCenter = function() return 200, 100 end
ArrowUI:SavePosition()
suite.check("a drag saves screen units", db.arrowX == 100 and db.arrowY == 50)

ArrowUI:SetSize(100)
suite.check("back to full size", frame.scale == 1 and db.arrowSize == nil)

suite.done()
