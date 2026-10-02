-- The kill panel's size, scrolling and the bits around it.
--
-- What matters: the panel is never drawn taller than the height you set, the
-- "more below" strip included; scrolled to the bottom it always shows its
-- last line; a click on the corner grip, or a drag that only widens it, does
-- not change its height; per hour stays right after the kill tallies are
-- reset; its X keeps an open Settings page and the goals panel in step; and
-- the Loot tab's medals mean best earners only.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("panelfit")

local ns = env.Load({ ui = true })
local Tracker = ns.Tracker
local TUI = ns.TrackerUI

-- 1s a fish, 10c a Wool Cloth, 5c anything else.
local VENDOR = { [6303] = 100, [2592] = 10 }
_G.C_Item = {
    GetItemInfo = function(id) return "item", nil, 1, 1, 1, "", "", 1, "", "", VENDOR[id] or 5 end,
    GetItemCount = function() return 6 end,
}
local now = 1000
_G.GetTime = function() return now end

TUI:OnEnable()

local serial = 0
local function Loot(mob, items)
    serial = serial + 1
    env.world.target = { name = mob, level = 8, dead = true, guid = "Creature-0-1-2-3-300-" .. serial }
    env.world.loot = items or {}
    Tracker:OnLoot()
end

--------------------------------------------------------------------------------
-- Scrolled to the bottom
--------------------------------------------------------------------------------

-- One mob that has dropped 23 different things: its open card ends in four
-- rows of icons, taller than a short panel's room for lines.
local many = {}
for index = 1, 23 do many[index] = { name = "Item " .. index, id = 1000 + index } end
Loot("Defias Pillager", many)

local all = TUI:Lines()
local last = all[#all]
suite.check("the card ends in its icons", last.style == "icons")

ns.db.trackerHeight = 240
TUI.scroll = 0
TUI:Refresh()
local tall = TUI:LineHeight(last, TUI.frame:GetWidth())
suite.check("taller than the room for lines", tall > 240 - TUI.TOP - 16, tall)
TUI:ScrollBy(999)
suite.check("scrolled to the bottom, something is drawn", #TUI.shown > 0, #TUI.shown)
suite.check("the icons", TUI.shown[#TUI.shown] and TUI.shown[#TUI.shown].style == "icons")
suite.check("and nothing is said to be below", not TUI.moreLabel:IsShown())
TUI:ScrollBy(-999)

--------------------------------------------------------------------------------
-- Never taller than the height you set
--------------------------------------------------------------------------------

for index = 1, 40 do Loot("Kobold " .. index) end

local worst, at = 0, nil
for height = 120, 600 do
    ns.db.trackerHeight = height
    TUI.scroll = 0
    TUI:Refresh()
    local over = TUI.frame:GetHeight() - TUI:MaxHeight()
    if over > worst then worst, at = over, height end
end
suite.check("a full panel is never taller than the height set", worst == 0,
    ("%d px over at %s"):format(worst, tostring(at)))

ns.db.trackerHeight = 300
TUI:Refresh()
suite.check("and still says what is below", TUI.moreLabel:IsShown())

ns.db.trackerHeight = 120
suite.check("too short is held at the shortest it can draw", TUI:MaxHeight() > 120, TUI:MaxHeight())
TUI:Refresh()
suite.check("which it is no taller than", TUI.frame:GetHeight() <= TUI:MaxHeight(), TUI.frame:GetHeight())
local icons = { style = "icons", icons = { {} } }
suite.check("and which holds a row of loot icons",
    TUI:LineHeight(icons, TUI.frame:GetWidth()) <= TUI:MaxHeight() - TUI.TOP - 16)

--------------------------------------------------------------------------------
-- The corner grip
--------------------------------------------------------------------------------

ns.db.trackerWidth, ns.db.trackerHeight = nil, 600
Tracker:Reset()
Loot("Kobold Vermin")
local press = TUI.grip:GetScript("OnMouseDown")
local release = TUI.grip:GetScript("OnMouseUp")
local short = TUI.frame:GetHeight()
suite.check("a short session draws a short panel", short < 600, short)

press(TUI.grip)
release(TUI.grip)
suite.check("a click on the grip keeps the height set", ns.db.trackerHeight == 600, ns.db.trackerHeight)
suite.check("and the width", ns.db.trackerWidth == nil, ns.db.trackerWidth)

press(TUI.grip)
TUI.frame:SetWidth(320)
release(TUI.grip)
suite.check("widening saves the width", ns.db.trackerWidth == 320, ns.db.trackerWidth)
suite.check("and keeps the height set", ns.db.trackerHeight == 600, ns.db.trackerHeight)

press(TUI.grip)
TUI.frame:SetHeight(300)
release(TUI.grip)
suite.check("a drag down or up saves the height", ns.db.trackerHeight == 300, ns.db.trackerHeight)
ns.db.trackerWidth, ns.db.trackerHeight = nil, nil

--------------------------------------------------------------------------------
-- Per hour after a reset
--------------------------------------------------------------------------------

local FISH = "Raw Slitherskin Mackerel"
Tracker:Reset()
ns.db.tracker = ns.db.tracker or {}
ns.db.tracker.looks = ns.db.tracker.looks or {}
ns.db.tracker.looks[FISH] = { id = 6303 }

-- Two hours of fishing, a fish a minute: 120s.
local fishedFrom = now
for _ = 1, 120 do
    ns.Fishing:Record("Elwynn Forest", "Crystal Lake", nil, { FISH }, { [FISH] = 1 })
    now = now + 60
end
local before = TUI:PerHour()
suite.check("two hours of fishing earn 60s an hour", before and math.abs(before - 6000) < 1, before)

-- Clear the kill tallies, then ten minutes of kills.
Tracker:Reset()
for _ = 1, 10 do
    Loot("Kobold Worker", { { name = "10 Copper", money = true } })
    now = now + 60
end
local after = TUI:PerHour()
local expected = ns.Value:Session() / (now - fishedFrom) * 3600
suite.check("the reset does not restart the clock under the fishing",
    after and math.abs(after - expected) < 1, after)

-- With nothing fished or gathered, a reset does start it over.
ns.Fishing:Reset()
Tracker:Reset()
suite.check("an empty session has no per hour", TUI:PerHour() == nil and TUI.startedAt == nil)

--------------------------------------------------------------------------------
-- The X
--------------------------------------------------------------------------------

Loot("Kobold Vermin", { { name = "Wool Cloth", id = 2592 } })
ns.Goals:OnEnable()
ns.GoalsUI:OnEnable()
now = now + 30
ns.HandleSlash("goal copper 40")
local goals = ns.GoalsUI.frame
suite.check("the goals panel shows", goals:IsShown())
suite.check("hung under the kill panel", goals._point and goals._point[2] == TUI.frame,
    goals._point and tostring(goals._point[2]))

ns.SettingsUI:Show()
suite.check("the Settings page shows the panel on", ns.SettingsUI.controls.tracker:GetChecked())
TUI.closeButton:GetScript("OnClick")(TUI.closeButton, "LeftButton")
suite.check("the X hides the panel", not TUI.frame:IsShown() and ns.db.trackerHidden == true)
suite.check("and the open Settings page says so", ns.SettingsUI.controls.tracker:GetChecked() == false)
suite.check("the goals panel no longer hangs under it", goals._point and goals._point[2] ~= TUI.frame,
    goals._point and tostring(goals._point[2]))
ns.SettingsUI:Hide()

ns.HandleSlash("tracker on")
suite.check("shown again, the goals panel hangs under it again",
    TUI.frame:IsShown() and goals._point and goals._point[2] == TUI.frame)

--------------------------------------------------------------------------------
-- Medals
--------------------------------------------------------------------------------

Tracker:Reset()
Loot("Kobold Vermin", {
    { name = "Wool Cloth", id = 2592, quantity = 3 },
    { name = "Linen Cloth", id = 2589 },
    { name = "Large Fang", id = 5637 },
})
TUI:SetTab("loot")
suite.check("sorted by value", TUI:Sort("loot") == "value")
suite.check("the best earner wears a medal", TUI.lines[1].medal:IsShown())
TUI:NextSort()
suite.check("sorted by count, no medals", TUI:Sort("loot") == "count" and not TUI.lines[1].medal:IsShown())
TUI:NextSort()
suite.check("sorted by name, no medals", TUI:Sort("loot") == "name" and not TUI.lines[1].medal:IsShown())
suite.check("the rank is still there", TUI.lines[1].rank:GetText() == "1")
TUI:NextSort()
suite.check("back to value, medals again", TUI:Sort("loot") == "value" and TUI.lines[1].medal:IsShown())
TUI:SetTab("farm")

_G.GetTime = nil
_G.C_Item = nil

suite.done()
