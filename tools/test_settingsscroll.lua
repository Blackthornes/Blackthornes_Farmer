-- A Settings window never grows past the screen: a page taller than the
-- room left scrolls inside the window instead (a player's report,
-- 2026-11-01: with Show Descriptions on, the window ran off the bottom
-- and its size grip could not be reached). Its drop-downs open on top
-- of the scrolling area, not cut off by it.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("settingsscroll")

local ns = env.Load({ ui = true })
local SettingsPages, Widgets = ns.SettingsPages, ns.Widgets

local saved = {}
local frame = CreateFrame("Frame", nil, UIParent)
local pages = SettingsPages.New(frame, {
    pages = { { key = "one", text = "One" }, { key = "two", text = "Two" } },
    top = 40, bottom = 30, padding = 12,
    columnWidth = 200, columnGap = 20, controlX = 120,
    db = function() return saved end,
})

-- Forty rows of 60 on page one: far taller than a screen 1000 high.
local rows = {}
for i = 1, 40 do
    local item = CreateFrame("Frame", nil, pages.pages.one.content)
    item.fixedHeight = 60
    pages:Place("one", 1, item, 4)
    rows[i] = item
end
local short = CreateFrame("Frame", nil, pages.pages.two.content)
short.fixedHeight = 60
pages:Place("two", 1, short, 4)

UIParent._height = 1000
pages:Fit()
pages:Show("one")

suite.check("the window stays inside the screen",
    pages.need[2] <= 1000, pages.need[2])
suite.check("the window still has room to show something",
    pages.need[2] >= 320, pages.need[2])
suite.check("the tall page can scroll", pages:ScrollRange() > 0, pages:ScrollRange())

pages:ScrollTo(-50)
suite.check("it never scrolls above the top", pages.offset == 0, pages.offset)
pages:ScrollTo(1e6)
suite.check("it never scrolls past the bottom",
    pages.offset == pages:ScrollRange(), pages.offset)

pages:ScrollTo(0)
pages:ScrollIntoView(rows[40])
local top = pages:ItemTop(pages.pages.one, rows[40])
suite.check("a row found by search scrolls into view",
    top >= pages.offset and top + 60 <= pages.offset + pages:ViewHeight() + 8,
    pages.offset)

pages:Show("two")
suite.check("a new page opens at its top", pages.offset == 0, pages.offset)
suite.check("a short page does not scroll", pages:ScrollRange() == 0, pages:ScrollRange())

-- A big screen leaves the window at its full height.
UIParent._height = 6000
pages:Fit()
suite.check("with room, the window fits the fullest page",
    pages.need[2] >= pages:TallestColumn() + 70, pages.need[2])
UIParent._height = 2160

-- A drop-down inside the scrolling page opens on UIParent, on top.
local dropdown = Widgets.CreateDropdown(pages.pages.one.content, {
    { text = "One", value = 1 }, { text = "Two", value = 2 },
}, function() end, { width = 120 })
dropdown:Toggle()
suite.check("the open list sits on UIParent", dropdown.menu:GetParent() == UIParent)
suite.check("the open list shows", dropdown.menu:IsShown())

suite.done()
