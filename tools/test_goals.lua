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

-- The pace: the first loot (3) only starts the clock, then 3 more came in
-- over 60 seconds, one every 20 seconds. Counting the first 3 as well made
-- it one every 10, and the estimate half what it should be.
suite.check("a pace by now", Goals.Eta(goal) ~= nil)
suite.check("the first loot is not part of the pace", goal.paced == 3, goal.paced)
suite.check("28 left at one every 20 seconds is about 9 min", Goals.Duration(Goals.Eta(goal), true) == "about 9 min",
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

-- Crafting it is not gathering either (a goal for bars, say), nor is the
-- last craft reaching the bags just after the window shuts.
ns.eventFrame:GetScript("OnEvent")(ns.eventFrame, "TRADE_SKILL_SHOW")
suite.check("crafting noted", Goals.away.craft == true)
changes = Bags(25)
suite.check("a craft is not gathered", changes[1] and changes[1].gathered == nil)
ns.eventFrame:GetScript("OnEvent")(ns.eventFrame, "TRADE_SKILL_CLOSE")
changes = Bags(26)
suite.check("nor one landing just after the window shuts", changes[1] and changes[1].gathered == nil)
clock = clock + 5
changes = Bags(27)
suite.check("a little later a rise is loot again", changes[1] and changes[1].gathered == 1)
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
-- Each character's own goals
--------------------------------------------------------------------------------

-- The goals are saved for the account, but a count is one character's bags.
-- Logging in on a bank alt used to count its bags toward every goal, finish
-- them without a word, and leave "120 / 40 DONE" on the main.
local realUnitName, realAfter = _G.UnitName, C_Timer.After
local settleRead
C_Timer.After = function(_, fn) settleRead = fn end

local function LogIn(name, copper)
    _G.UnitName = function(unit)
        if unit == "player" then return name end
        return realUnitName(unit)
    end
    Goals.me = nil
    bags[COPPER] = copper
    clock = clock + 600
    Goals:Settle()
    Goals:Update(true)
    GUI:Refresh()
end

-- The bags have settled: the read that can finish a goal.
local function BagsSettled()
    clock = clock + 10
    if settleRead then settleRead() end
end

Goals:Remove("Copper Ore")
Goals:Remove("Tin Ore")

LogIn("Blackthornes", 6)
BagsSettled()
ns.HandleSlash("goal Copper Ore 40")
local main = Goals:Find("Copper Ore")
suite.check("a new goal is its character's", main and main.owner == "Blackthornes", main and main.owner)
clock = clock + 30
Bags(30)

env.chat = {}
local doneToday = Goals:DoneToday()
LogIn("Bankalt", 120)
BagsSettled()
suite.check("another character does not see it", Goals:Find("Copper Ore") == nil and #Goals:List() == 0)
suite.check("so its panel stays shut", not GUI.frame:IsShown())
suite.check("its bags are not the goal's count", main.have == 30, main.have)
suite.check("and do not finish it", not main.done and Goals:DoneToday() == doneToday and Chat("Goal done") == nil)
suite.check("nor can it remove it", not Goals:Remove("Copper Ore") and #ns.db.goals.list == 1)

-- Six of its own, whatever the other character has.
local six = { "Tin Ore", "Silverleaf", "Peacebloom", "Linen Cloth", "Wool Cloth", "Iron Ore" }
for _, item in ipairs(six) do Goals:Set(item, 500) end
suite.check("six of its own", #Goals:List() == 6, #Goals:List())
local seventh, why = Goals:Set("Mageweave Cloth", 500)
suite.check("and no seventh", seventh == nil and tostring(why):find("most at once") ~= nil, why)
for _, item in ipairs(six) do Goals:Remove(item) end

env.chat = {}
LogIn("Blackthornes", 30)
BagsSettled()
suite.check("back on the first, its goal is there", Goals:Find("Copper Ore") == main and #Goals:List() == 1)
suite.check("at its own count", main.have == 30 and not main.done, main.have)
suite.check("on its panel", GUI.frame:IsShown() and GUI.cards[1].goal == main)

-- A quiet read never finishes a goal; the read once the bags settle does.
LogIn("Blackthornes", 45)
suite.check("bags filling in past the number finish nothing", main.have == 45 and not main.done)
BagsSettled()
suite.check("the read after they settle does", main.done == true and Chat("Goal done") ~= nil)
suite.check("and counts it for today", Goals:DoneToday() == doneToday + 1, Goals:DoneToday())
Settle()

LogIn("Bankalt", 120)
suite.check("another character's clear leaves it be", Goals:ClearDone() == 0)
LogIn("Blackthornes", 45)
suite.check("still there, done", Goals:Find("Copper Ore") == main and main.done)
Goals:ClearDone()

-- A goal saved before goals had owners shows on every character, and none
-- finishes it until one gathers toward it or changes it.
local old = { item = "Copper Ore", target = 40, have = 30, start = 6, gained = 24, loots = 6,
    active = 300, milestone = 2 }
table.insert(ns.db.goals.list, old)

LogIn("Bankalt", 120)
suite.check("an old goal shows on every character", Goals:Find("Copper Ore") == old)
BagsSettled()
suite.check("read there, never finished there", old.have == 120 and not old.done and old.owner == nil)
ns.eventFrame:GetScript("OnEvent")(ns.eventFrame, "MERCHANT_SHOW")
Bags(110)
ns.eventFrame:GetScript("OnEvent")(ns.eventFrame, "MERCHANT_CLOSED")
suite.check("selling some is not gathering toward it", not old.done and old.owner == nil)

LogIn("Blackthornes", 30)
BagsSettled()
suite.check("its own character sees it too", Goals:Find("Copper Ore") == old and old.have == 30)
clock = clock + 30
Bags(33)
suite.check("gathering toward it makes it yours", old.owner == "Blackthornes", old.owner)
suite.check("and it keeps the pace it had", old.paced == nil and Goals.Eta(old) ~= nil)

LogIn("Bankalt", 120)
suite.check("then the others no longer see it", Goals:Find("Copper Ore") == nil)

local older = { item = "Tin Ore", target = 80, have = 30, start = 30, gained = 0, loots = 0, active = 0 }
table.insert(ns.db.goals.list, older)
Goals:Set("Tin Ore", 90)
suite.check("changing an old goal makes it yours", older.owner == "Bankalt" and older.target == 90, older.owner)
LogIn("Blackthornes", 33)
suite.check("and only yours", Goals:Find("Tin Ore") == nil)

-- With a realm the tag carries it; one the client will not read is asked
-- for again rather than left off, so one character is never two.
local realRealm = _G.GetRealmName
_G.GetRealmName = function() return env.Secret("realm") end
Goals.me = nil
suite.check("an unreadable realm tags nothing yet", Goals:Owner() == nil and Goals.me == nil)
_G.GetRealmName = function() return "Forever" end
suite.check("name and realm", Goals:Owner() == "Blackthornes-Forever", Goals:Owner())

_G.GetRealmName = realRealm
_G.UnitName = realUnitName
C_Timer.After = realAfter
Goals.me = nil

--------------------------------------------------------------------------------
-- Nothing recorded is touched
--------------------------------------------------------------------------------

suite.check("kill tally untouched", next(ns.db.tracker and ns.db.tracker.mobs or {}) == nil)
suite.check("goals saved in their own table", type(ns.db.goals) == "table" and type(ns.db.goals.list) == "table")

suite.done()
