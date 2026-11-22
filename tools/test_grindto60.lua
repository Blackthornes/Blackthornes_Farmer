-- Grind to 60 (the owner said build it, 2026-11-22, from a mockup whose
-- words he approved; a test feature, off unless ticked).
--
-- What must hold:
--   1. Off by default; the chip shows only while it is on.
--   2. The path runs from level 1 to 60 in steps, the first where the
--      race starts, never in the other side's zones or towns.
--   3. A real Forever camp beats a guess; a camp with only older rows is
--      an estimate.
--   4. Herbs and skins count only with the skill.
--   5. Hide This Area and Hide <mob> move the step to the next best camp,
--      say one chat line, count in the foot, and Show Again brings them
--      back. A mob goes on Farmer's hide list too.
--   6. Skip Step picks the next best camp for those levels.
--   7. Kill rewards stay secret: no coin or percent on the step.
--   8. Built once per stamp, not again on a redraw.
--   9. The view: the step you're on open, tags, Show Again under the
--      list, the step menu's six lines, the Experimental page's tick.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("grindto60")
local check = suite.check

local ns = env.Load({ ui = true })
local L = ns.L
local G = ns.GrindTo60

local who = { level = 14, race = "Orc", class = "HUNTER", faction = "Horde" }
_G.UnitLevel = function(unit)
    if unit == "player" then return who.level end
    return env.world.target and env.world.target.level or 0
end
_G.UnitRace = function() return who.race, who.race end
_G.UnitClass = function() return who.class, who.class end
_G.UnitFactionGroup = function(unit)
    if unit == "player" then return who.faction, who.faction end
    return nil
end

-- A small world: every camp at Forever level bands.
local serial = 99500
local function Mob(name, zone, location, low, high, opts)
    opts = opts or {}
    serial = serial + 1
    ns.DB:RegisterItem({ name = opts.item or (name .. " Bit"), id = serial, category = opts.category or "misc",
        sources = { { name = name, zone = zone, location = location, minLevel = low, maxLevel = high,
            chance = 20, coords = { 50, 50 }, provenance = not opts.classic and "forever" or nil } } })
end

Mob("Test Boar", "Durotar", "Valley of Trials", 1, 4)
Mob("Test Scorpid", "Durotar", "Valley of Trials", 3, 6)
Mob("Test Raptor", "Durotar", "Razormane Grounds", 6, 10)
Mob("Test Kobold", "Elwynn Forest", "Fargodeep Mine", 1, 6)
Mob("Test Quilboar", "The Barrens", "The Dry Hills", 10, 16)
Mob("Test Harpy", "The Barrens", "Crossroads", 12, 15)
Mob("Test Defias", "Westfall", "Jangolode Mine", 10, 16)
Mob("Test Centaur", "Thousand Needles", "Camp E'thok", 22, 27)
Mob("Test Ogre", "Stranglethorn Vale", "Kurzen's Compound", 32, 38)
Mob("Test Kurzen", "Stranglethorn Vale", "Kurzen's Compound", 33, 37)
Mob("Test Yeti", "Winterspring", "Ice Thistle Hills", 53, 57, { classic = true })

G:SetOn(false)
-- 1.
check("off by default", not G.IsOn())
local UI = ns.GrindingUI
ns.UI:Show()
ns.UI:ShowTab("grind")
check("no chip while off", UI.to60Chip and not UI.to60Chip:IsShown())
G:SetOn(true)
UI:LayoutChips()
check("the chip shows while on", UI.to60Chip:IsShown())
check("the EXPERIMENTAL tag beside it", UI.to60Tag and UI.to60Tag:IsShown()
    and UI.to60Tag.label:GetText() == L["EXPERIMENTAL"])

-- 2.
local plan = G:Plan()
check("a path of steps", #plan.steps >= 4, #plan.steps)
check("starts at level 1", plan.steps[1] and plan.steps[1].low == 1)
check("ends at 60", plan.steps[#plan.steps] and plan.steps[#plan.steps].high == 60, plan.steps[#plan.steps] and plan.steps[#plan.steps].high)
check("the first step is in the race's zone", plan.steps[1].zone == "Durotar", plan.steps[1].zone)
local bad = false
for _, step in ipairs(plan.steps) do
    if step.zone == "Elwynn Forest" or step.zone == "Westfall" or step.location == "Crossroads" then bad = true end
    if step.low >= step.high then bad = true end
end
check("never the other side's zones or a town", not bad)
local joined = true
for index = 2, #plan.steps do
    if plan.steps[index].low ~= plan.steps[index - 1].high then joined = false end
end
check("each step starts where the last ended", joined)
check("the step you're on is marked", plan.current and plan.steps[plan.current].low <= 14
    and plan.steps[plan.current].high > 14)
check("steps under your level are done", plan.steps[1].done == true)
check("Barrens camp for the teens", plan.steps[plan.current].label == "The Dry Hills", plan.steps[plan.current].label)
check("both sides flagged", (function()
    for _, step in ipairs(plan.steps) do if step.zone == "Thousand Needles" then return step.both end end
end)() == true)

who.faction, who.race = "Alliance", "Human"
local alliance = G:Plan()
check("an Alliance path starts in Elwynn", alliance.steps[1].zone == "Elwynn Forest", alliance.steps[1].zone)
local noHorde = true
for _, step in ipairs(alliance.steps) do
    if step.zone == "Durotar" or step.zone == "The Barrens" then noHorde = false end
end
check("and never in Horde zones", noHorde)
who.faction, who.race = "Horde", "Orc"

-- 3.
plan = G:Plan()
local yeti
for _, step in ipairs(plan.steps) do if step.zone == "Winterspring" then yeti = step end end
check("an older row only is an estimate", yeti and yeti.estimate == true and not yeti.real)
check("a Forever camp is real", plan.steps[1].real == true and not plan.steps[1].estimate)
Mob("Test Owl", "Winterspring", "Owl Wing Thicket", 53, 57)
plan = G:Plan()
for _, step in ipairs(plan.steps) do if step.low >= 50 and step.zone == "Winterspring" then yeti = step end end
check("a real camp beats the guess", yeti and yeti.label == "Owl Wing Thicket", yeti and yeti.label)

-- 4.
Mob("Peacebloom Test", "Durotar", nil, 1, 10, { category = "Herbalism", item = "Peacebloom Test" })
ns.DB:RegisterItem({ name = "Silverleaf Test", id = 99901, category = "Herbalism",
    sources = { { kind = "herb", zone = "Durotar", minLevel = 1, maxLevel = 10, requires = "Herbalism 1" } } })
ns.Spots.Skills = function() return {} end
plan = G:Plan()
check("no herbs without Herbalism", #plan.steps[1].herbs == 0)
ns.Spots.Skills = function() return { Herbalism = 50 } end
plan = G:Plan()
check("herbs with Herbalism", #plan.steps[1].herbs >= 1)
local _, tagWords = ns.GrindTo60UI.TagsText(plan.steps[1])
check("the HERBS tag", tagWords:find(L["HERBS"], 1, true) ~= nil, tagWords)
check("Also Here names what to pick", ns.GrindTo60UI.AlsoText(plan.steps[1]):find("to pick", 1, true) ~= nil,
    ns.GrindTo60UI.AlsoText(plan.steps[1]))
ns.Spots.Skills = function() return {} end
plan = G:Plan()
_, tagWords = ns.GrindTo60UI.TagsText(plan.steps[1])
check("no HERBS tag without the skill", tagWords:find(L["HERBS"], 1, true) == nil, tagWords)
check("and no Also Here line", ns.GrindTo60UI.AlsoText(plan.steps[1]) == "")
ns.Spots.Skills = function() return {} end

-- Skins the same way: only with Skinning, and enough of it.
ns.DB:RegisterItem({ name = "Test Hide", id = 99902, category = "Leather",
    sources = { { kind = "skinning", name = "Test Boar", zone = "Durotar", location = "Valley of Trials",
        minLevel = 1, maxLevel = 4, requires = "Skinning 1", provenance = "forever" } } })
plan = G:Plan()
check("no skins without Skinning", #plan.steps[1].skinnable == 0)
ns.Spots.Skills = function() return { Skinning = 50 } end
plan = G:Plan()
check("skins with Skinning", #plan.steps[1].skinnable >= 1, #plan.steps[1].skinnable)
_, tagWords = ns.GrindTo60UI.TagsText(plan.steps[1])
check("the SKINS tag", tagWords:find(L["SKINS"], 1, true) ~= nil, tagWords)
check("Also Here names what to skin", ns.GrindTo60UI.AlsoText(plan.steps[1]):find("Test Boar", 1, true) ~= nil,
    ns.GrindTo60UI.AlsoText(plan.steps[1]))
ns.Spots.Skills = function() return {} end

-- 5.
plan = G:Plan()
local current = plan.steps[plan.current]
env.chat = {}
G:HideArea(current)
check("one chat line for the area", #env.chat == 1
    and env.chat[1]:find("is hidden from Grind to 60.", 1, true) ~= nil, env.chat[1])
plan = G:Plan()
check("the step moved to another camp", plan.steps[plan.current].label ~= "The Dry Hills",
    plan.steps[plan.current].label)
check("counted in the foot", G.HiddenCount() == 1)
env.chat = {}
G:HideMob("Test Raptor")
check("one chat line for the mob", #env.chat == 1)
check("the mob is on Farmer's hide list", ns.DB:IsHiddenSource("Test Raptor"))
check("two hidden", G.HiddenCount() == 2)
plan = G:Plan()
for _, step in ipairs(plan.steps) do
    for _, mob in ipairs(step.mobs) do check("hidden mob left out", mob.name ~= "Test Raptor") end
end
G:ShowAgain()
check("Show Again brings them back", G.HiddenCount() == 0 and not ns.DB:IsHiddenSource("Test Raptor"))
plan = G:Plan()
check("the area is back", plan.steps[plan.current].label == "The Dry Hills")

-- A mob hidden elsewhere stays hidden after Show Again.
ns.DB:Hide("source", "Test Defias")
G:ShowAgain()
check("other hides are left alone", ns.DB:IsHiddenSource("Test Defias"))
ns.DB:Unhide("source", "Test Defias")

-- 6.
plan = G:Plan()
local before = plan.steps[plan.current].label
G:Skip(plan.steps[plan.current])
plan = G:Plan()
check("Skip Step picks the next best camp", plan.steps[plan.current].label ~= before)
G.skips, G.skipsVersion = nil, (G.skipsVersion or 0) + 1

-- 8.
plan = G:Plan()
check("kept while nothing moved", G:Plan() == plan)
who.level = 15
check("a level up builds it again", G:Plan() ~= plan)

-- The view.
G:SetShown(true)
UI:Render(true)
local view = ns.GrindTo60UI
check("the view shows", view.frame and view.frame:IsShown())
check("the list hides under it", not UI.list:IsShown())
local text = UI.footer:GetText() or ""
check("the foot starts with Experimental.", text:find(L["Experimental."], 1, true) == 1, text)
check("the foot says the step", text:find(L.Format("Step %d of %d", G:Plan().current, #G:Plan().steps), 1, true) ~= nil, text)

check("who is playing heads the view", (view.who:GetText() or ""):find("15", 1, true) ~= nil, view.who:GetText())
check("the step you're on is open", view.detail:IsShown() and view.detail.step == G:Plan().steps[G:Plan().current])
check("its mobs are named", (view:DetailWords()[1] or ""):find("Test Quilboar", 1, true) ~= nil, view:DetailWords()[1])
check("nothing hidden: no Show Again", not view.foot:IsShown())

-- An estimate says so, and a step both sides share is flagged.
for _, step in ipairs(G:Plan().steps) do
    local _, words = view.TagsText(step)
    if step.estimate then check("an estimate is tagged", words:find(L["estimate"], 1, true) ~= nil, words) end
    if step.both then check("a shared zone is tagged", words:find(L["BOTH SIDES"], 1, true) ~= nil, words) end
end

-- A click on another step opens it; a click on the open one shuts it.
local other
for _, each in ipairs(view.rows) do
    if each:IsShown() and each.step and not each.step.current and not each.step.done then other = other or each end
end
other:GetScript("OnMouseUp")(other, "LeftButton")
check("a click opens that step", view.detail:IsShown() and view.detail.step == other.step)
check("a step ahead can be skipped", view.detail.skip:IsShown())
other:GetScript("OnMouseUp")(other, "LeftButton")
check("a second click shuts it", not view.detail:IsShown())
view.open = nil
view.key = nil
UI:Render()

-- Hidden from here: counted under the list, with Show Again.
env.chat = {}
G:HideArea(G:Plan().steps[#G:Plan().steps])
UI:Render()
check("the foot counts what is hidden", view.foot:IsShown()
    and view.foot.text:GetText() == L.Format("%d hidden.", 1), view.foot.text:GetText())
view.foot.button:GetScript("OnClick")(view.foot.button, "LeftButton")
UI:Render()
check("Show Again clears it", G.HiddenCount() == 0 and not view.foot:IsShown())

-- 7. No coin and no percent anywhere on the open step.
local shown = {}
for _, row in ipairs(view.rows) do
    if row:IsShown() then
        for _, label in ipairs(row.texts or {}) do shown[#shown + 1] = label:GetText() or "" end
    end
end
for _, words in ipairs(view.detailTexts and view:DetailWords() or {}) do shown[#shown + 1] = words end
local secret = true
for _, words in ipairs(shown) do
    if words:find("%%") or words:find("|T.-Coin") or words:find("%d+g") then secret = false end
end
check("no coin or percent on the steps", secret)

-- Right-click: Show the Way, Hide This Area, a line per mob, Cancel.
C_Timer.After = function() end
local row
for _, each in ipairs(view.rows) do if each:IsShown() and each.step and each.step.current then row = each end end
check("the step you're on has a row", row ~= nil)
row:GetScript("OnMouseUp")(row, "RightButton")
local menu = ns.HideMenu.frame
check("a right-click opens the menu", menu and menu:IsShown())
check("Show the Way first", menu.lines[1].label:GetText() == L["Show the Way"], menu.lines[1].label:GetText())
check("then Hide This Area", menu.lines[2].label:GetText() == L["Hide This Area"])
check("then a mob", menu.lines[3].label:GetText():find(L.Format("Hide %s", "Test"), 1, true) == 1,
    menu.lines[3].label:GetText())
local last
for index = #menu.lines, 1, -1 do if menu.lines[index]:IsShown() then last = menu.lines[index] break end end
check("Cancel last", last and last.label:GetText() == L["Cancel"])
menu:Hide()

-- Other menus keep their four lines.
local many = {}
for index = 1, 7 do many[index] = { kind = "action", text = "Line " .. index, run = function() end } end
ns.HideMenu:Open(many)
local showing = 0
for _, line in ipairs(menu.lines) do if line:IsShown() then showing = showing + 1 end end
check("a plain menu still stops at four lines", showing == 4, showing)
menu:Hide()

-- Show the Way points the arrow at the camp.
local aimed
ns.Arrow.Grind = function(_, camp) aimed = camp return true end
view:ShowTheWay(G:Plan().steps[G:Plan().current])
check("Show the Way aims the arrow at the camp", aimed and aimed.zone == G:Plan().steps[G:Plan().current].zone)

-- The Experimental page's tick turns it off and on.
ns.HandleSlash("settings")
local tick = ns.SettingsUI.controls.grindTo60
check("Settings has the Grind to 60 tick, ticked", tick ~= nil and tick:GetChecked() == true)
ns.SettingsUI.pages:Show("experimental")
check("on its own Experimental page", ns.SettingsUI.pages.shown == "experimental", ns.SettingsUI.pages.shown)
ns.UI:ShowTab("grind")

-- Off hides the chip and the view.
G:SetOn(false)
UI:Render(true)
check("off: the view goes", not view.frame:IsShown())
check("off: the list is back", UI.list:IsShown())

suite.done()
