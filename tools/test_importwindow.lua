-- The Take data window (UI/Import.lua): paste, read, Apply, Remove; and the
-- Give window's Next part button for a handout in parts.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("importwindow")

local ns = env.Load({ ui = true })
for _, module in ipairs(ns.moduleOrder) do
    if module.OnEnable then module:OnEnable() end
end
_G.time = _G.time or function() return 1000000 end
_G.date = _G.date or function() return "11 Oct" end
_G.InCombatLockdown = function() return false end

local UI, Transfer = ns.UI, ns.Transfer

-- A string from another Farmer.
local other = { records = {}, db = {} }
ns.db.tracker = ns.db.tracker or { mobs = {} }
local mine = ns.db.exportId
ns.db.exportId = "aaaaaaaaaaaa"
ns.db.tracker.mobs.Fox = { kills = 9, copper = 90, coinKills = 9, items = {}, qty = {}, stacks = {}, places = {} }
local text
Transfer:Make(function(parts) text = parts and parts[1] end)
ns.db.exportId = "bbbbbbbbbbbb"
ns.db.tracker.mobs = {}
suite.check("a string to paste", text ~= nil)

UI:ShowImport()
suite.check("the window opens with nothing taken in yet", UI.importFrame:IsShown() and UI.importNone:IsShown())
suite.check("and no Apply button", not UI.importApply:IsShown())

UI.importEdit:SetText(text)
UI:ImportChanged()
suite.check("pasting reads it and shows what it adds", (UI.importPreview:GetText() or ""):find("kills", 1, true) ~= nil,
    UI.importPreview:GetText())
suite.check("and nothing is added yet", next(ns.db.tracker.mobs) == nil)
suite.check("Apply shows", UI.importApply:IsShown())

UI:ImportApply()
suite.check("Apply adds it", ns.db.tracker.mobs.Fox and ns.db.tracker.mobs.Fox.kills == 9)
suite.check("it is listed with a Remove button", UI.importRows[1]:IsShown() and not UI.importNone:IsShown())

UI.importEdit:SetText("junk")
UI:ImportChanged()
suite.check("junk is explained, not taken", not UI.importApply:IsShown() and (UI.importPreview:GetText() or "") ~= "")

local after = C_Timer.After
C_Timer.After = function() end
UI:ImportRemove(UI.importRows[1])
suite.check("one click only asks", ns.db.tracker.mobs.Fox ~= nil)
UI:ImportRemove(UI.importRows[1])
suite.check("the second takes it back out", ns.db.tracker.mobs.Fox == nil and not UI.importRows[1]:IsShown())

C_Timer.After = after

-- A handout in parts.
local shown
UI.ShowExport = function(_, body, title, nav) shown = { body = body, title = title, nav = nav } end
local saved = Transfer.PART_RAW
Transfer.PART_RAW = 300
for i = 1, 20 do ns.db.tracker.mobs["Beast" .. i] = { kills = i, copper = i, coinKills = i, items = {}, qty = {}, stacks = {}, places = {} } end
Transfer:Give()
Transfer.PART_RAW = saved
suite.check("a handout in parts has Next", shown and shown.nav and shown.nav.count > 1 and shown.nav.index == 1, shown and shown.title)
local first = shown.body
shown.nav.step(1)
suite.check("Next shows the next part", shown.body ~= first and shown.nav.index == 2, shown.title)
ns.db.exportId = mine
