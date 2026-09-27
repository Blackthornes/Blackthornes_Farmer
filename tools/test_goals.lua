-- Gathering goals (Trent, 2026-09-27): set a target for a material, and the
-- Goals panel counts you toward it with count-ups, floats, milestones and a
-- GOAL COMPLETE banner.
--
-- What matters: the count is what is in your bags (bank if ticked), read the
-- whole way through a pcall; a rise out in the world is gathering, one with
-- the bank or a vendor open is not; milestones fire once on the way up; the
-- goal finishes exactly once, with the sound and a chat line; the panel
-- draws it all and its effects run to the end without error; and none of
-- it touches the kill tally or harvest.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("goals")

local ns = env.Load({ ui = true })
local Goals = ns.Goals
local GUI = ns.GoalsUI

local clock = 1000
_G.GetTime = function() return clock end

local played = {}
_G.PlaySoundFile = function(path) played[#played + 1] = path return true end

-- The bags: item id or name -> count; the bank adds on when asked.
local bags, bank = {}, {}
local asked = {}
_G.C_Item = {
    GetItemCount = function(item, includeBank)
        asked[#asked + 1] = { item = item, bank = includeBank }
        local count = bags[item] or 0
        if includeBank then count = count + (bank[item] or 0) end
        return count
    end,
}

local COPPER = 2770
bags[COPPER] = 6

ns.TrackerUI:OnEnable()
Goals:OnEnable()
GUI:OnEnable()

-- Out of the few seconds after login where the bags are still loading.
suite.check("quiet just after login", Goals.quietUntil > clock)
bags[COPPER] = 0
ns.HandleSlash("goal copper 40")
bags[COPPER] = 9
local early = Goals:Update()
suite.check("bags filling in at login still count", early[1] and early[1].to == 9)
suite.check("but are not loot", early[1] and early[1].gathered == nil)
Goals:Remove("Copper Ore")
bags[COPPER] = 6
clock = clock + 10

local function Settle()
    for _ = 1, 100 do GUI:Step(0.1) end
end

local function Bags(count)
    bags[COPPER] = count
    return Goals:Update()
end

local function Chat(pattern)
    for _, line in ipairs(env.chat) do
        if line:find(pattern) then return line end
    end
end

--------------------------------------------------------------------------------
-- Setting one
--------------------------------------------------------------------------------

suite.check("no goals, panel hidden", not GUI.frame:IsShown())

ns.HandleSlash("goal copper 40")
local goal = Goals:Find("Copper Ore")
suite.check("an alias finds the item", goal ~= nil)
suite.check("target kept", goal and goal.target == 40, goal and goal.target)
suite.check("counts what is already in the bags", goal and goal.have == 6, goal and goal.have)
suite.check("asked by item id", asked[#asked].item == COPPER, tostring(asked[#asked].item))
suite.check("bags only by default", asked[#asked].bank == false)
suite.check("told in chat", Chat("goal set") ~= nil)
suite.check("panel shows", GUI.frame:IsShown())
suite.check("one card", GUI.cards[1] and GUI.cards[1]:IsShown())
suite.check("card count", GUI.cards[1].count:GetText():find("^6") ~= nil, GUI.cards[1].count:GetText())
suite.check("34 left", GUI.cards[1].left:GetText():find("34") ~= nil, GUI.cards[1].left:GetText())

ns.HandleSlash("goal 40 Copper Ore")
suite.check("number first works too, and does not duplicate", #Goals:List() == 1)

env.chat = {}
ns.HandleSlash("goal Copper Ore 5")
suite.check("a target you already have is refused", Chat("already have 6") ~= nil)
suite.check("and the old goal stays", Goals:Find("Copper Ore").target == 40)

env.chat = {}
ns.HandleSlash("goal Copper Ore")
suite.check("no number asks for one", Chat("give it a number") ~= nil)

--------------------------------------------------------------------------------
-- Gathering toward it
--------------------------------------------------------------------------------

clock = clock + 10
local changes = Bags(9)
suite.check("a rise is gathering", changes[1] and changes[1].gathered == 3, changes[1] and changes[1].gathered)
suite.check("count moved", goal.have == 9)
suite.check("one loot", goal.loots == 1)
suite.check("the float is in the air", GUI.floats and GUI.floats[1] and GUI.floats[1].flying == true)
suite.check("it names the item", GUI.floats[1]:GetText() == "+3 Copper Ore", GUI.floats[1]:GetText())
suite.check("mid count-up the number is on its way", #GUI.effects > 0)
Settle()
suite.check("effects finish", #GUI.effects == 0)
suite.check("count lands on 9", GUI.cards[1].count:GetText():find("^9") ~= nil, GUI.cards[1].count:GetText())
suite.check("float gone", GUI.floats[1].flying == false)

-- Past 25%: a milestone, once.
clock = clock + 30
changes = Bags(11)
suite.check("25% reached", changes[1].milestone and changes[1].milestone.tag == "25%")
suite.check("tag shown", GUI.cards[1].tag:GetText() == "25%")
Settle()
clock = clock + 30
changes = Bags(12)
suite.check("no second 25%", changes[1].milestone == nil)
Settle()

-- The pace: 6 gathered over 60 seconds is one every 10 seconds.
suite.check("a pace by now", Goals.Eta(goal) ~= nil)
suite.check("28 left at 0.1 a second is about 5 min", Goals.Duration(Goals.Eta(goal), true) == "about 5 min",
    Goals.Duration(Goals.Eta(goal), true))
suite.check("shown on the card", GUI.cards[1].right:GetText():find("at your pace") ~= nil)

-- A long break does not drag the pace down.
clock = clock + 3600
Bags(14)
suite.check("a break counts as five minutes", goal.active == 60 + 300, goal.active)
Settle()

-- Halfway.
clock = clock + 20
changes = Bags(20)
suite.check("halfway", changes[1].milestone and changes[1].milestone.tag == "HALFWAY")
Settle()

--------------------------------------------------------------------------------
-- Not gathering
--------------------------------------------------------------------------------

local loots = goal.loots
ns.eventFrame:GetScript("OnEvent")(ns.eventFrame, "BANKFRAME_OPENED")
suite.check("bank noted", Goals.away.bank == true)
changes = Bags(26)
suite.check("taken from the bank is not gathered", changes[1].gathered == nil)
suite.check("but it counts", goal.have == 26)
suite.check("no loot added", goal.loots == loots)
suite.check("no float for it", not (GUI.floats[1].flying or (GUI.floats[2] and GUI.floats[2].flying)))
ns.eventFrame:GetScript("OnEvent")(ns.eventFrame, "BANKFRAME_CLOSED")
suite.check("bank closed", Goals.away.bank == nil)
Settle()

-- Crafting some away drops the count without a fuss.
changes = Bags(24)
suite.check("a drop is followed", goal.have == 24 and changes[1].gathered == nil)
Settle()

--------------------------------------------------------------------------------
-- The last stretch and the finish
--------------------------------------------------------------------------------

clock = clock + 20
Bags(37)
suite.check("final stretch", Goals.Final(goal))
suite.check("says how many more", GUI.cards[1].left:GetText() == "3 more!", GUI.cards[1].left:GetText())
Settle()

env.chat = {}
played = {}
clock = clock + 20
changes = Bags(41)
suite.check("finished", goal.done == true and changes[1].done == true)
suite.check("chat line", Chat("Goal done") ~= nil)
suite.check("the unlock sound", played[1] and played[1]:find("drop%-rates%-unlocked") ~= nil, played[1])
suite.check("banner up", GUI.banner and GUI.banner:IsShown())
suite.check("banner says it", GUI.banner.title:GetText() == "GOAL COMPLETE")
suite.check("one done today", Goals:DoneToday() == 1)
suite.check("footer counts it", GUI.footer:IsShown() and GUI.footer.left:GetText():find("1") ~= nil)
suite.check("card tagged done", GUI.cards[1].tag:GetText() == "DONE")
Settle()
suite.check("banner gone after", not GUI.banner:IsShown())

played = {}
Bags(45)
suite.check("a finished goal does not finish again", #played == 0 and Goals:DoneToday() == 1)

local recap = Goals:Recap(goal)
suite.check("recap counts loots", recap.loots == goal.loots and recap.loots > 0)

-- Clicking a finished card clears it.
GUI:OnCardClick(GUI.cards[1], "LeftButton")
suite.check("cleared", #Goals:List() == 0)
suite.check("panel hides with nothing on it", not GUI.frame:IsShown())

--------------------------------------------------------------------------------
-- Bank, remove, off, secret values
--------------------------------------------------------------------------------

bags[765] = 2
bank[765] = 5
ns.HandleSlash("goal bank on")
ns.HandleSlash("goal Silverleaf 20")
local leaf = Goals:Find("Silverleaf")
suite.check("bank counted when ticked", leaf and leaf.have == 7, leaf and leaf.have)
ns.HandleSlash("goal bank off")
suite.check("back to bags", leaf.have == 2, leaf.have)

ns.HandleSlash("goal remove silverleaf")
suite.check("removed", Goals:Find("Silverleaf") == nil)

-- Effects off: the count still follows, nothing plays.
ns.db.trackerEffects = "off"
ns.HandleSlash("goal Copper Ore 80")
GUI:Forget()
Bags(50)
suite.check("off: no effects", #GUI.effects == 0)
suite.check("off: still counts", Goals:Find("Copper Ore").have == 50)
ns.db.trackerEffects = nil

-- A client value that raises is skipped, not raised.
_G.C_Item.GetItemCount = function() return env.Secret("count") end
local ok = pcall(Goals.Update, Goals)
suite.check("a secret count does not raise", ok)
suite.check("and changes nothing", Goals:Find("Copper Ore").have == 50)

--------------------------------------------------------------------------------
-- The picker
--------------------------------------------------------------------------------

_G.C_Item.GetItemCount = function(item) return bags[item] or 0 end
bags[2771] = 30
GUI:OpenPicker("Tin Ore")
suite.check("picker open", GUI.picker:IsShown())
suite.check("offers amounts above what you have", GUI.picker.chips[1].amount == 40,
    GUI.picker.chips[1].amount)
suite.check("presets", table.concat(GUI.Presets(30), ",") == "40,60,80,100",
    table.concat(GUI.Presets(30), ","))
GUI.picker.amount:SetText("25")
GUI:PickerSet()
suite.check("too low is refused on the picker", GUI.picker.note:GetText():find("already have") ~= nil)
GUI.picker.amount:SetText("60")
GUI:PickerSet()
suite.check("set from the picker", Goals:Find("Tin Ore") and Goals:Find("Tin Ore").target == 60)
suite.check("picker closes", not GUI.picker:IsShown())

--------------------------------------------------------------------------------
-- Nothing recorded is touched
--------------------------------------------------------------------------------

suite.check("kill tally untouched", next(ns.db.tracker and ns.db.tracker.mobs or {}) == nil)
suite.check("goals saved in their own table", type(ns.db.goals) == "table" and type(ns.db.goals.list) == "table")

suite.done()
