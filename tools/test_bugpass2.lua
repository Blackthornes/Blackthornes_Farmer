-- The second bug pass of 2026-10-12.
--
-- What matters: scrolling the kills panel only moves its rows, never prices
-- the mobs again; worth 0 with prices still loading keeps the per-hour
-- clock; a shared item record never has a nil count; a handout cannot be
-- taken back out twice at once; and a "Creature #ID" record renamed keeps
-- what partners gave under its new key.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("bugpass2")

local ns = env.Load({ ui = true })
local Tracker, TUI = ns.Tracker, ns.TrackerUI

ns.Harvest:OnEnable()
Tracker:OnEnable()
TUI:OnEnable()
_G.InCombatLockdown = function() return false end

--------------------------------------------------------------------------------
-- 1. Scrolling the panel
--------------------------------------------------------------------------------

for index = 1, 30 do
    Tracker.session["Wolf " .. index] = index
    Tracker:GetMob("Wolf " .. index).kills = index
end
ns.db.trackerHeight = 200
TUI:Refresh()

local built = 0
local lines = TUI.Lines
TUI.Lines = function(self, ...)
    built = built + 1
    return lines(self, ...)
end

suite.check("the list is longer than the panel", (TUI.maxScroll or 0) > 0, TUI.maxScroll)
local firstShown = TUI.shown[1]
TUI:ScrollBy(2)
suite.check("a wheel tick scrolls", TUI.scroll == 2 and TUI.shown[1] ~= firstShown, TUI.scroll)
suite.check("without building the lines again", built == 0, built)

TUI:Refresh()
suite.check("a refresh still builds them", built == 1, built)
suite.check("and keeps the scroll", TUI.scroll == 2, TUI.scroll)
TUI.Lines = lines

-- The corner grip: hidden mid-drag, the drag still ends.
local press = TUI.grip:GetScript("OnMouseDown")
press(TUI.grip)
suite.check("pressing the corner grip sizes", TUI.sizing == true)
TUI.grip:GetScript("OnHide")(TUI.grip)
suite.check("hiding mid-drag ends it", TUI.sizing == false)
ns.db.trackerHeight = nil

--------------------------------------------------------------------------------
-- 2. The per-hour clock
--------------------------------------------------------------------------------

local Value = ns.Value
local session = Value.Session
Value.Session = function() return 0, { coin = 0, priced = 0, unpriced = { "Peacebloom" } } end
TUI.startedAt = 50
TUI:NoteStart()
suite.check("worth 0 with prices loading keeps the clock", TUI.startedAt == 50, TUI.startedAt)
Value.Session = function() return nil end
TUI:NoteStart()
suite.check("nothing gathered stops it", TUI.startedAt == nil)
Value.Session = session

--------------------------------------------------------------------------------
-- 3. A shared item record
--------------------------------------------------------------------------------

local Share = ns.Share
local spec = { add = { corpses = true }, maps = { items = { add = { count = true, corpses = true } } } }
local own, credit = { corpses = 0 }, {}
Share.Merge(spec, own, { corpses = 2, items = { Fang = { count = 3 } } }, credit)
suite.check("a new item's counts all start at 0", own.items.Fang.count == 3 and own.items.Fang.corpses == 0,
    tostring(own.items.Fang.corpses))

--------------------------------------------------------------------------------
-- 4. Taking a handout back out
--------------------------------------------------------------------------------

local Transfer = ns.Transfer
ns.db.shareIn = ns.db.shareIn or {}
local key = Transfer.LedgerKey("abc")
ns.db.shareIn[key] = { kind = "import", credit = { k = {} }, hashes = {} }
Transfer.removing[key] = true
local answer, why
Transfer:Remove("abc", function(count, reason) answer, why = count, reason end)
suite.check("a second Remove while one runs is refused", answer == nil and why == "busy")
Transfer.removing[key] = nil
Transfer:Remove("abc", function(count, reason) answer, why = count, reason end)
suite.check("on its own it runs", answer == 0 and why == nil and ns.db.shareIn[key] == nil)

--------------------------------------------------------------------------------
-- 5. A "Creature #ID" record named
--------------------------------------------------------------------------------

local Harvest = ns.Harvest
local known = Harvest.KnownNpcName
Harvest.KnownNpcName = function(id) if id == 11320 then return "Earthborer" end end
Harvest.records["Creature #11320|Ragefire Chasm|"] = {
    mob = "Creature #11320", zone = "Ragefire Chasm", location = "", npc = 11320, corpses = 10,
    items = { Fang = { count = 4, corpses = 4 } },
}
ns.db.tracker.mobs["Creature #11320"] = { kills = 10, items = {}, coinKills = 10, copper = 100 }
ns.db.shareIn["partner"] = { credit = {
    h = { ["Creature #11320|Ragefire Chasm|"] = { corpses = 6, items = { Fang = { count = 2, corpses = 2 } } } },
    k = { ["Creature #11320"] = { kills = 6 } },
} }
Harvest:NameUnnamed()
local held = ns.db.shareIn["partner"].credit
suite.check("the record takes its name", Harvest.records["Earthborer|Ragefire Chasm|"] ~= nil)
suite.check("what the partner gave follows it",
    held.h["Earthborer|Ragefire Chasm|"] and held.h["Earthborer|Ragefire Chasm|"].corpses == 6
    and held.h["Creature #11320|Ragefire Chasm|"] == nil)
suite.check("in the kill tally too", held.k["Earthborer"] and held.k["Earthborer"].kills == 6
    and held.k["Creature #11320"] == nil)
Harvest.KnownNpcName = known

suite.done()
