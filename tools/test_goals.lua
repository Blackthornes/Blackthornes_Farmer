-- Gathering goals (2026-09-27): set a target for a material, and the
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
suite.check("the peon's \"Work complete!\"", played[1] == ns.TrackerFX.VOICE.goal and #played == 1, played[1])
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
    Goals.me, Goals.oldMe = nil, nil
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
suite.check("a new goal is its character's", main and main.owner == "Player-1-Blackthornes", main and main.owner)
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
suite.check("and no seventh", seventh == nil and tostring(why):find("goals at once") ~= nil, why)
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
suite.check("gathering toward it makes it yours", old.owner == "Player-1-Blackthornes", old.owner)
suite.check("and it keeps the pace it had", old.paced == nil and Goals.Eta(old) ~= nil)

LogIn("Bankalt", 120)
suite.check("then the others no longer see it", Goals:Find("Copper Ore") == nil)

local older = { item = "Tin Ore", target = 80, have = 30, start = 30, gained = 0, loots = 0, active = 0 }
table.insert(ns.db.goals.list, older)
Goals:Set("Tin Ore", 90)
suite.check("changing an old goal makes it yours", older.owner == "Player-1-Bankalt" and older.target == 90, older.owner)
LogIn("Blackthornes", 33)
suite.check("and only yours", Goals:Find("Tin Ore") == nil)

-- Goals are tagged by GUID (2026-10-11): Forever lets characters share a
-- first name, and the old "Name-Realm" tag filed them all as one. A GUID
-- the client will not read is asked for again rather than left off.
local realGUID = _G.UnitGUID
_G.UnitGUID = function(unit) if unit == "player" then return env.Secret("guid") end return realGUID(unit) end
Goals.me = nil
suite.check("an unreadable GUID tags nothing yet", Goals:Owner() == nil and Goals.me == nil)
_G.UnitGUID = realGUID
suite.check("the tag is the GUID", Goals:Owner() == "Player-1-Blackthornes", Goals:Owner())

-- Two characters of one first name are two owners.
local function AsGuid(guid)
    _G.UnitGUID = function(unit) if unit == "player" then return guid end return realGUID(unit) end
    Goals.me, Goals.oldMe = nil, nil
end
LogIn("Bob", 5)
AsGuid("Player-1-ASH")
Goals:Set("Silk Cloth", 40)
local ash = Goals:Find("Silk Cloth")
AsGuid("Player-1-STONE")
suite.check("another Bob does not see the first Bob's goal", Goals:Find("Silk Cloth") == nil)
AsGuid("Player-1-ASH")
suite.check("the first Bob does", Goals:Find("Silk Cloth") == ash)
Goals:Remove("Silk Cloth")

-- A goal tagged the old way is read as the character's, and gets the GUID
-- once it gathers toward it.
local realRealm = _G.GetRealmName
_G.GetRealmName = function() return env.Secret("realm") end
Goals.oldMe = nil
suite.check("an unreadable realm gives no old tag", Goals:OldOwner() == nil)
_G.GetRealmName = function() return "Forever" end
suite.check("the old tag is name and realm", Goals:OldOwner() == "Bob-Forever", Goals:OldOwner())
local tagged = { item = "Copper Ore", owner = "Bob-Forever", target = 900, have = 5, start = 5,
    gained = 0, loots = 0, active = 0 }
table.insert(ns.db.goals.list, tagged)
suite.check("an old-tagged goal is its character's", Goals:Find("Copper Ore") == tagged)
clock = clock + 30
Bags(9)
suite.check("gathering toward it tags it with the GUID", tagged.owner == "Player-1-ASH", tagged.owner)
Goals:Remove("Copper Ore")
_G.UnitGUID = realGUID

_G.GetRealmName = realRealm
_G.UnitName = realUnitName
C_Timer.After = realAfter
Goals.me, Goals.oldMe = nil, nil

--------------------------------------------------------------------------------
-- Every line fits
--------------------------------------------------------------------------------

Goals:Remove("Copper Ore")

-- Undocked and at its narrowest, so the panel's width comes from its lines.
local trackerHidden, trackerWidth = ns.db.trackerHidden, ns.db.trackerWidth
ns.db.trackerHidden = true
ns.db.trackerWidth = 180
ns.TrackerUI:Refresh()

local function CardOf(item)
    for _, card in ipairs(GUI.cards) do
        if card:IsShown() and card.goal and card.goal.item == item then return card end
    end
end

-- A long name widens the panel and is then drawn whole: the width it was
-- widened to was 2px short of the room the card gives a name.
local LONG = "Elemental Earth Fragments Of The Deep"
Goals:Set(LONG, 40)
suite.check("a long name widens the panel", GUI.frame:GetWidth() > 180, GUI.frame:GetWidth())
suite.check("and is drawn whole", CardOf(LONG) and CardOf(LONG).name:GetText() == LONG,
    CardOf(LONG) and CardOf(LONG).name:GetText())
Goals:Remove(LONG)

-- The footer's count stays clear of its Set another button.
bags[COPPER] = 0
Goals:Set("Copper Ore", 40)
clock = clock + 30
Bags(40)
Settle()
local countEnd = 1 + 8 + ns.Theme.TextWidth("small", ns.Util.StripColor(GUI.footer.left:GetText()))
local buttonStart = GUI.frame:GetWidth() - 7 - GUI.footer.next:GetWidth()
suite.check("the footer's count clears Set another", GUI.footer:IsShown() and countEnd + 8 <= buttonStart,
    countEnd .. " vs " .. buttonStart)

-- GOAL COMPLETE says how long it took where the banner has room for it,
-- and leaves that to the chat line where it would be cut off.
local finished = { item = "Copper Ore", have = 40, target = 40, doneIn = 75, done = true }
GUI:Banner()._width = 500
GUI:Complete(finished)
suite.check("the banner says how long it took",
    GUI.banner.subject:GetText() == "40 / 40 Copper Ore  |  1 min 15s", GUI.banner.subject:GetText())
GUI.banner._width = 150
GUI:Complete(finished)
suite.check("unless that would run off it", GUI.banner.subject:GetText() == "40 / 40 Copper Ore",
    GUI.banner.subject:GetText())
GUI.banner._width = nil
Settle()

-- The search list's "23/40" buttons keep up with the goals panel closed.
Goals:ClearDone()
bags[COPPER] = 6
Goals:Set("Copper Ore", 40)
ns.UI:Search("copper ore")
ns.db.goalsHidden = true
GUI:Refresh()
clock = clock + 30
Bags(20)
local button
for _, row in ipairs(ns.UI.list.rows) do
    if row:IsShown() and row.data and row.data.type == "item" and row.data.item.name == "Copper Ore" then
        button = row.goal.label:GetText()
    end
end
suite.check("the search list follows the count with the panel closed", button == "20/40", button)
ns.db.goalsHidden = false

-- The picker opened from a result closes once that row shows something
-- else (rows are reused as the list scrolls), and with the window.
local function CopperRow()
    for _, row in ipairs(ns.UI.list.rows) do
        if row:IsShown() and row.data and row.data.type == "item" and row.data.item.name == "Copper Ore" then
            return row
        end
    end
end
local copperRow = CopperRow()
copperRow.goal:GetScript("OnClick")(copperRow.goal, "LeftButton")
suite.check("the Goal button opens the picker", GUI.picker:IsShown() and GUI.pickItem == "Copper Ore")
ns.UI.list:SetData(ns.UI.list.data, true)
suite.check("a redraw of the same rows keeps it open", GUI.picker:IsShown())
local kept = copperRow.data
copperRow.data = { type = "item", item = { name = "Tin Ore" } }
GUI:CheckPicker()
suite.check("it closes once its row shows another item", not GUI.picker:IsShown())
copperRow.data = kept
copperRow.goal:GetScript("OnClick")(copperRow.goal, "LeftButton")
ns.UI.frame:Hide()
GUI:CheckPicker()
suite.check("and when the search window closes", not GUI.picker:IsShown())
ns.UI:Hide()

-- The picker opens outside the search window, level with the Goal button,
-- never over the window's right edge and close gem; on the left when the
-- right has no room, and it follows the window when it is resized.
ns.UI:Show()
local win, button = ns.UI.frame, copperRow.goal
win._left, win._right, win._top = 300, 900, 800
button._left, button._right, button._top = 850, 894, 640
UIParent._left, UIParent._right, UIParent._top = 0, 1920, 1080
GUI.picker:Hide()
button:GetScript("OnClick")(button, "LeftButton")
ns.Motion:FinishAll()
local at = GUI.picker._point
suite.check("the picker opens beside the window, not over it",
    at[1] == "TOPLEFT" and at[2] == win and at[3] == "TOPRIGHT" and at[4] >= 10, table.concat({ tostring(at[1]), tostring(at[3]), tostring(at[4]) }, " "))
suite.check("level with the Goal button", at[5] == -160 + 8, at[5])
suite.check("on the right", GUI.picker.side == "right")

win._left, win._right = 1200, 1800
GUI:CheckPicker()
at = GUI.picker._point
suite.check("on the left when the window is near the screen's right edge",
    at[1] == "TOPRIGHT" and at[2] == win and at[3] == "TOPLEFT" and at[4] <= -10, table.concat({ tostring(at[1]), tostring(at[3]), tostring(at[4]) }, " "))

win._left, win._right = 100, 1850
GUI:CheckPicker()
suite.check("a window wider than both sides allow picks the roomier side",
    GUI.picker.side == "left")

win._left, win._right = 300, 700
GUI:CheckPicker()
suite.check("back on the right once the window narrows", GUI.picker.side == "right")
suite.check("still open after the moves", GUI.picker:IsShown())
GUI.picker:Hide()
win._left, win._right, win._top = nil, nil, nil
button._left, button._right, button._top = nil, nil, nil
UIParent._left, UIParent._right, UIParent._top = nil, nil, nil
ns.UI:Hide()

-- The picker's amount box keeps its room for the number: no magnifier or
-- clear button in it. The search box keeps both.
GUI:OpenPicker("Tin Ore")
local amount = GUI.picker.amount
suite.check("the amount box is plain", not amount.icon:IsShown() and amount.editBox._point[2] == -6,
    tostring(amount.editBox._point[2]))
amount:SetText("40")
suite.check("with no clear button", not amount.clear:IsShown())
suite.check("the search box keeps its magnifier",
    ns.UI.searchBox.icon:IsShown() and ns.UI.searchBox.editBox._point[2] == -26)

-- Why a goal was refused goes on a line of its own, under Include bank.
local note, tick = GUI.picker.note._point, GUI.picker.bank._point
suite.check("the refusal sits under Include bank",
    note[1] == "TOPRIGHT" and note[3] < tick[3] - GUI.picker.bank:GetHeight(), note[3])
GUI.picker:Hide()

-- Docked under a kills panel made bigger in Settings, as wide as it is on
-- screen: its width is taken into this panel's units.
ns.db.trackerHidden = trackerHidden
ns.db.trackerWidth = trackerWidth
ns.TrackerUI:Refresh()
GUI:Refresh()
local tracker = ns.TrackerUI.frame
local trackerScale = tracker.GetEffectiveScale
tracker.GetEffectiveScale = function() return 1.2 end
suite.check("docked, as wide as the kills panel on screen",
    GUI:Width() == math.min(380, math.floor(tracker:GetWidth() * 1.2 + 0.5)),
    GUI:Width() .. " for " .. tracker:GetWidth())
tracker.GetEffectiveScale = trackerScale

-- A tall kills panel low on the screen: the goals panel goes above it, or
-- beside it, rather than being pushed up over it to stay on screen.
local saved = { tracker.GetBottom, tracker.GetTop, tracker.GetLeft, tracker.GetRight,
    UIParent.GetTop, UIParent.GetRight }
UIParent.GetTop = function() return 768 end
UIParent.GetRight = function() return 1366 end
tracker.GetLeft = function() return 8 end
tracker.GetRight = function() return 268 end
tracker.GetTop = function() return 578 end
tracker.GetBottom = function() return 400 end
GUI:Place()
local at = GUI.frame._point
suite.check("under the kills panel with room there", at[1] == "TOPLEFT" and at[3] == "BOTTOMLEFT", at[3])
tracker.GetBottom = function() return 60 end
GUI:Place()
at = GUI.frame._point
suite.check("above it with none below", at[1] == "BOTTOMLEFT" and at[3] == "TOPLEFT", at[3])
tracker.GetTop = function() return 740 end
GUI:Place()
at = GUI.frame._point
suite.check("beside it with none above either", at[1] == "TOPLEFT" and at[3] == "TOPRIGHT", at[3])
tracker.GetBottom, tracker.GetTop, tracker.GetLeft, tracker.GetRight = saved[1], saved[2], saved[3], saved[4]
UIParent.GetTop, UIParent.GetRight = saved[5], saved[6]
GUI:Place()

--------------------------------------------------------------------------------
-- The goal arrow comes on with a new goal, unless it was ever turned off
--------------------------------------------------------------------------------

do
    local Arrow = ns.Arrow
    local function Fresh(name, amount)
        Goals:Remove(name)
        return Goals:Set(name, amount)
    end
    ns.db.arrowShown, ns.db.arrowTurnedOff = false, nil
    for _, goal in ipairs(Goals:List()) do Goals:Remove(goal.item) end
    Fresh("Tin Ore", 90)
    suite.check("a new goal turns the arrow on", Arrow.IsOn())
    Goals:Set("Tin Ore", 95)
    suite.check("changing a goal leaves it as it is", Arrow.IsOn())
    Arrow:SetOn(false)
    suite.check("turned off, that is remembered", ns.db.arrowTurnedOff == true)
    Fresh("Tin Ore", 90)
    suite.check("so a new goal leaves it off", not Arrow.IsOn())
    Goals:Remove("Tin Ore")
end

--------------------------------------------------------------------------------
-- Nothing recorded is touched
--------------------------------------------------------------------------------

suite.check("kill tally untouched", next(ns.db.tracker and ns.db.tracker.mobs or {}) == nil)
suite.check("goals saved in their own table", type(ns.db.goals) == "table" and type(ns.db.goals.list) == "table")

suite.done()
