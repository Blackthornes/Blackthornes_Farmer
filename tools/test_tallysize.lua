-- The kills and loot panel's size (the owner asked 2026-10-07, after
-- Tradeskills' window got the same).
--
-- What must hold:
--   1. A size is kept between 50% and 150%, whole; "small", "80", "80%" and
--      "0.8" all read as 80%; names read "Small (80%)", and a dragged size
--      reads as its percent.
--   2. It is drawn at the saved size (trackerScale, the key Settings' Kill
--      tally size has always used), never bigger than the screen.
--   3. Dragging the gold grip sizes the panel from its top left corner,
--      saves the size on release and converts the saved spot, so the panel
--      stays where the drag left it; right-click puts it back to normal.
--   4. /farm tracker size and the Settings row do the same; the stepper
--      shows a dragged size as it is, and the named size in use is lit.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("tallysize")

local ns = env.Load({ ui = true })
local TrackerUI, SettingsUI = ns.TrackerUI, ns.SettingsUI

for _, module in ipairs(ns.moduleOrder) do
    if module.OnEnable then module:OnEnable() end
end

local SCREEN_W, SCREEN_H = 1280, 720
local function near(a, b) return type(a) == "number" and math.abs(a - b) < 0.001 end

UIParent.GetWidth = function() return SCREEN_W end
UIParent.GetHeight = function() return SCREEN_H end
UIParent.GetEffectiveScale = function() return 1 end

local cursorX, cursorY = 0, 0
_G.GetCursorPosition = function() return cursorX, cursorY end
GameTooltip.IsOwned = function(self, frame) return self._owner == frame end
GameTooltip.SetOwner = function(self, owner) self._owner, self._lines = owner, {} end
GameTooltip.SetText = function(self, text) self._lines = { text } end

-- 1. Sizes and their names.
suite.check("nothing saved: normal", TrackerUI.ClampPercent(nil) == 100)
suite.check("too small: 50%", TrackerUI.ClampPercent(10) == 50)
suite.check("too big: 150%", TrackerUI.ClampPercent(900) == 150)
suite.check("whole", TrackerUI.ClampPercent(87.3) == 87)
suite.check("\"small\"", TrackerUI.ParseSize("small") == 80)
suite.check("\"Large\"", TrackerUI.ParseSize("Large") == 120)
suite.check("\"80%\"", TrackerUI.ParseSize("80%") == 80)
suite.check("\"80\"", TrackerUI.ParseSize("80") == 80)
suite.check("\"0.8\"", near(TrackerUI.ParseSize("0.8"), 80))
suite.check("\"tiny\": not a size", TrackerUI.ParseSize("tiny") == nil)
suite.check("named", TrackerUI.ScaleText(100) == "Normal (100%)")
suite.check("named, small", TrackerUI.ScaleText(80) == "Small (80%)")
suite.check("dragged to", TrackerUI.ScaleText(87) == "87%")

-- A panel that works out its edges from its one point, in its own units, as
-- the game does: an offset from UIParent's corner, divided by its scale.
local frame = TrackerUI:Build()
frame._scale = 1
frame._width, frame._height = 260, 420
frame.SetScale = function(self, s) self._scale = s end
frame.GetScale = function(self) return self._scale end
frame.ClearAllPoints = function(self) self._point = nil end
frame.SetPoint = function(self, point, relativeTo, relativePoint, x, y)
    self._point = { point, relativeTo, relativePoint, x or 0, y or 0 }
end
frame.GetLeft = function(self)
    local p = self._point
    return p and p[4]
end
frame.GetTop = function(self)
    local p = self._point
    if not p then return nil end
    if p[3] == "TOPLEFT" then return SCREEN_H / self._scale + p[5] end
    return p[5]
end

-- 2. The saved size, kept on the screen.
ns.db.trackerScale = 80
SettingsUI:ApplyTrackerScale()
suite.check("drawn at the saved size", near(frame._scale, 0.8))
suite.check("it has a gold grip", TrackerUI.sizeGrip ~= nil)
suite.check("beside the bottom right corner", TrackerUI.sizeGrip._point[3] == "BOTTOMRIGHT")
ns.db.trackerScale = 150
frame._height = 600
suite.check("150% of a tall panel on a 1280x720 screen: as big as fits",
    TrackerUI:DrawnPercent() < 150 and (600 + 16) * TrackerUI:DrawnPercent() / 100 <= SCREEN_H,
    TrackerUI:DrawnPercent())
frame._height = 900
suite.check("one taller than the screen at normal still gets normal", TrackerUI:DrawnPercent() == 100)
frame._height = 420

-- 3. The grip.
ns.db.trackerScale = 100
ns.db.trackerPoint, ns.db.trackerRelativePoint, ns.db.trackerX, ns.db.trackerY = "TOPLEFT", "TOPLEFT", 50, -20
SettingsUI:ApplyTrackerScale()
local grip = TrackerUI.sizeGrip
suite.check("at the saved spot", near(frame:GetLeft(), 50) and near(frame:GetTop(), 700))

-- Pressed 10 right of and 15 below the corner.
cursorX, cursorY = 50 + 260 + 10, 700 - 420 - 15
grip._scripts.OnMouseDown(grip, "LeftButton")
suite.check("sizing", grip.sizing == true and TrackerUI.sizing == true)
cursorX, cursorY = 50 + 260 * 0.8 + 10, 700 - 420 * 0.8 - 15
grip._scripts.OnUpdate(grip)
suite.check("drawn at 80% while dragging", near(frame._scale, 0.8), frame._scale)
suite.check("top left stays put (left)", near(frame:GetLeft() * frame._scale, 50))
suite.check("top left stays put (top)", near(frame:GetTop() * frame._scale, 700))
cursorX, cursorY = 50 + 260 * 0.3, 700 - 420 * 0.3
grip._scripts.OnUpdate(grip)
suite.check("never under 50%", near(frame._scale, 0.5))
cursorX, cursorY = 50 + 260 * 0.8 + 10, 700 - 420 * 0.8 - 15
grip._scripts.OnUpdate(grip)
grip._scripts.OnMouseUp(grip, "LeftButton")
suite.check("saved on release", ns.db.trackerScale == 80, ns.db.trackerScale)
suite.check("still drawn at 80%", near(frame._scale, 0.8))
suite.check("the saved spot converted", near(ns.db.trackerX, 62.5) and near(ns.db.trackerY, -25),
    tostring(ns.db.trackerX) .. ", " .. tostring(ns.db.trackerY))
suite.check("so it stays where the drag left it",
    near(frame:GetLeft() * frame._scale, 50) and near(frame:GetTop() * frame._scale, 700))
suite.check("stopped", grip._scripts.OnUpdate == nil and not TrackerUI.sizing)

grip._scripts.OnMouseDown(grip, "RightButton")
suite.check("right-click: normal again", near(frame._scale, 1) and ns.db.trackerScale == 100)
suite.check("in the same spot", near(ns.db.trackerX, 50))
grip._scripts.OnEnter(grip)
suite.check("its tooltip names the size", GameTooltip._lines[1] == "Normal (100%)", GameTooltip._lines[1])

-- 4. /farm tracker size and Settings.
ns.HandleSlash("tracker size small")
suite.check("/farm tracker size small", ns.db.trackerScale == 80 and near(frame._scale, 0.8))
ns.HandleSlash("tracker size 115%")
suite.check("/farm tracker size 115%", ns.db.trackerScale == 115)
ns.HandleSlash("tracker size tiny")
suite.check("/farm tracker size tiny changes nothing", ns.db.trackerScale == 115)
suite.check("and says what it takes", env.chat[#env.chat]:find("50%% to 150%%"), env.chat[#env.chat])
suite.check("size is not a show or hide", not ns.db.trackerHidden)

ns.HandleSlash("settings")
local controls = SettingsUI.controls
suite.check("the stepper shows 115% as it is", controls.trackerScale.text:GetText() == "115%",
    controls.trackerScale.text:GetText())
controls.trackerScale.minus:GetScript("OnClick")(controls.trackerScale.minus)
suite.check("and steps to the next on the list", ns.db.trackerScale == 110, ns.db.trackerScale)
suite.check("down to 50%", (function()
    for _ = 1, 10 do controls.trackerScale.minus:GetScript("OnClick")(controls.trackerScale.minus) end
    return ns.db.trackerScale == 50
end)(), ns.db.trackerScale)
local sizes = controls.trackerSizes
suite.check("Small, Normal and Large under it", #sizes == 3 and sizes[1].percent == 80 and sizes[3].percent == 120)
sizes[3]._scripts.OnClick(sizes[3], "LeftButton")
suite.check("Large draws it at 120%", ns.db.trackerScale == 120 and near(frame._scale, 1.2))
suite.check("and the stepper says so", controls.trackerScale.text:GetText() == "120%")

suite.done()
