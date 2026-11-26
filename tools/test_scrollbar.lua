-- Farmer's scroll bars go the way they are dragged. The game's own slider
-- runs backward on Forever (dragging down scrolled the list up), so the
-- lists and the Export box wear the hand-drawn bar Butler uses.
--
-- What must hold:
--   1. Dragging the thumb down shows rows further down; up goes back up.
--   2. A press below the thumb jumps down, above it jumps up.
--   3. The thumb sits at the top at the start and at the bottom at the end.
--   4. The mouse wheel turned toward the player scrolls down.
--   5. A redraw sets the bar without being taken as the player's move.
--   6. The Export box: dragging down shows text further down, the wheel
--      moves the bar with the text, and the bar hides when all fits.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("scrollbar")

local ns = env.Load({ ui = true })

local parent = CreateFrame("Frame")
local list = ns.Widgets.CreateRowList(parent, { rowHeight = 20 })
list._height = 200 -- ten rows on screen
local bar = list.scrollbar
bar._height = 200
bar._top = 500

local data = {}
for i = 1, 50 do data[i] = { i = i } end
list:SetData(data)

local cursorY = 0
_G.GetCursorPosition = function() return 0, cursorY end

-- The thumb is 200 * 10 / 50 = 40 tall, so it travels 160 pixels for 40 rows.
suite.check("the thumb starts at the top", bar:ThumbTop() == 0, tostring(bar:ThumbTop()))

-- 1. Catch the thumb 10 pixels into it and drag it 80 pixels down.
cursorY = 500 - 10
bar:GetScript("OnMouseDown")(bar, "LeftButton")
suite.check("a press on the thumb does not move the list", list.offset == 0, tostring(list.offset))
cursorY = 500 - 90
bar:GetScript("OnUpdate")(bar)
suite.check("dragging down scrolls down", list.offset == 20, tostring(list.offset))
cursorY = 500 - 50
bar:GetScript("OnUpdate")(bar)
suite.check("dragging back up scrolls up", list.offset == 10, tostring(list.offset))
bar:GetScript("OnMouseUp")(bar)
suite.check("letting go stops following", bar:GetScript("OnUpdate") == nil)

-- 2.
list.offset = 0
list:Refresh()
cursorY = 500 - 190
bar:GetScript("OnMouseDown")(bar, "LeftButton")
bar:GetScript("OnMouseUp")(bar)
suite.check("a press low on the bar jumps down", list.offset >= 35, tostring(list.offset))
cursorY = 500 - 5
bar:GetScript("OnMouseDown")(bar, "LeftButton")
bar:GetScript("OnMouseUp")(bar)
suite.check("a press high on the bar jumps up", list.offset == 0, tostring(list.offset))

-- 3.
list.offset = 40
list:Refresh()
suite.check("the thumb sits at the bottom at the end", bar:ThumbTop() == 160, tostring(bar:ThumbTop()))

-- 4. The game's delta is -1 for the wheel turned toward the player.
list.offset = 0
list:Refresh()
list:GetScript("OnMouseWheel")(list, -1)
suite.check("the wheel toward you scrolls down", list.offset == 3, tostring(list.offset))
list:GetScript("OnMouseWheel")(list, 1)
suite.check("the wheel away scrolls up", list.offset == 0, tostring(list.offset))

-- 5.
local moved = 0
local before = bar.onValueChanged
bar.onValueChanged = function(value) moved = moved + 1; before(value) end
list:SetData({ { i = 1 }, { i = 2 } })
list:SetData(data, true)
suite.check("a redraw is not a move", moved == 0, tostring(moved))

-- 6.
local UI = ns.UI
UI:ShowExport("hello\nworld", "Export")
local scroll, ebar = UI.exportScroll, UI.exportSlider
suite.check("the Export box wears the hand-drawn bar", type(ebar.ThumbTop) == "function")
local scrolled = 0
scroll.SetVerticalScroll = function(_, v) scrolled = v end
scroll._height = 200
ebar._height = 200
ebar._top = 500
scroll:GetScript("OnScrollRangeChanged")(scroll, 0, 300)
suite.check("the bar shows when the text is longer than the box", ebar:IsShown())
cursorY = 500 - 10
ebar:GetScript("OnMouseDown")(ebar, "LeftButton")
cursorY = 500 - 70
ebar:GetScript("OnUpdate")(ebar)
ebar:GetScript("OnMouseUp")(ebar)
suite.check("dragging down shows text further down", scrolled > 0 and ebar:GetValue() == scrolled,
    tostring(scrolled))
local was = scrolled
scroll:GetScript("OnMouseWheel")(scroll, -1)
suite.check("the wheel toward you scrolls down", scrolled == was + 40 and ebar:GetValue() == scrolled,
    tostring(scrolled))
scroll:GetScript("OnScrollRangeChanged")(scroll, 0, 0)
suite.check("the bar hides when it all fits", not ebar:IsShown())
suite.check("and the text goes back to its top", scrolled == 0, tostring(scrolled))

suite.done()
