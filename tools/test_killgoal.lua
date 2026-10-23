-- Kill goals (a player asked, the owner said build it, 2026-10-20): set a
-- number of kills, of any mob or one, follow it in the Goals panel and get a
-- summary of what each mob dropped when it is done.
--
-- What matters: only kills from the moment it starts count, each corpse
-- once; a later window on a corpse adds its items but no kill; a goal for
-- one mob leaves the others out; long breaks are not farming time; the goal
-- finishes exactly once, keeps a summary and opens its window; Got It takes
-- it off the panel and keeps the summary; the panel lists it first; and the
-- command and the New Goal box set it.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("killgoal")

local ns = env.Load({ ui = true })
local KillGoal, KUI = ns.KillGoal, ns.KillGoalUI

local now = 50000
_G.time = function() return now end

ns.Harvest:OnEnable()
ns.Tracker:OnEnable()
ns.TrackerUI:OnEnable()
ns.Goals:OnEnable()
ns.GoalsUI:OnEnable()

local fire = ns.eventFrame:GetScript("OnEvent")
local serial = 0
local function Loot(mob, items, guid)
    if guid == nil then
        serial = serial + 1
        guid = "Creature-0-1-2-3-" .. serial
    end
    env.world.target = { name = mob, level = 8, dead = true, isPlayer = false, guid = guid }
    env.world.loot = items or {}
    fire(ns.eventFrame, "LOOT_OPENED")
end

local BOAR, WOLF = "Mottled Boar", "Prowler"
local MEAT = { name = "Chunk of Boar Meat", id = 769 }
local FANG = { name = "Wolf Fang", id = 7074 }
local COINS = { name = "12 Copper", money = true }

-- Kills before a goal count for nothing.
Loot(BOAR, { MEAT })
suite.check("no goal, nothing kept", KillGoal:Current() == nil)

-- Setting it.
suite.check("0 is refused", KillGoal:Start(0) == nil)
suite.check("past the most is refused", KillGoal:Start(KillGoal.MOST + 1) == nil)
local goal = KillGoal:Start(3)
suite.check("a goal of 3 starts", goal and goal.target == 3 and goal.have == 0 and goal.kills == true)
suite.check("saved by GUID", ns.db.killGoals and ns.db.killGoals[ns.Goals:Owner()].goal == goal)
suite.check("the Goals panel lists it first", ns.GoalsUI:List()[1] == goal)
suite.check("its title", KillGoal.Title(goal) == "Kill 3 Mobs", KillGoal.Title(goal))

-- Counting.
Loot(BOAR, { MEAT, COINS }, "Creature-boar-A")
suite.check("a kill counts", goal.have == 1, goal.have)
suite.check("its mob is kept", goal.mobs[BOAR] and goal.mobs[BOAR].kills == 1)
suite.check("its drop is kept", goal.mobs[BOAR].items[MEAT.name] == 1)
suite.check("its coin is kept", goal.copper == 12, goal.copper)

Loot(BOAR, { MEAT, FANG }, "Creature-boar-A")
suite.check("the same corpse again is no new kill", goal.have == 1, goal.have)
suite.check("what was left is not counted twice", goal.mobs[BOAR].items[MEAT.name] == 1)
suite.check("but something new in it counts", goal.mobs[BOAR].items[FANG.name] == 1)

now = now + 30
Loot(WOLF, { FANG })
suite.check("any mob counts", goal.have == 2 and goal.mobs[WOLF].kills == 1)
suite.check("time between kills counts", goal.seconds == 30, goal.seconds)

now = now + KillGoal.BREAK + 100
KillGoal:GainedXP(450, 0)
local doneLines = #env.chat
Loot(WOLF, { FANG })
suite.check("a long break is not farming time", goal.seconds == 30, goal.seconds)
suite.check("XP is kept", goal.xp == 450, goal.xp)
suite.check("the third kill finishes it", goal.done == true)
local said = table.concat(env.chat, "\n", doneLines + 1)
suite.check("chat says so", said:find("Goal done", 1, true) ~= nil, said)

local last = KillGoal:Last()
suite.check("a summary is kept", last and last.kills == 3 and last.target == 3)
suite.check("its mobs, most kills first", last.mobs[1].name == WOLF and last.mobs[1].kills == 2)
suite.check("the summary window opens", KUI.summary and KUI.summary:IsShown())

Loot(BOAR, { MEAT })
suite.check("a done goal counts no more", goal.have == 3)

-- The window's words.
local tiles = KUI.Tiles(last)
suite.check("four tiles", #tiles == 4)
suite.check("too short for gold an hour", tiles[3][2] == "--", tostring(tiles[3][2]))

-- Got It.
KUI:GotIt()
suite.check("Got It takes it off", KillGoal:Current() == nil and not KUI.summary:IsShown())
suite.check("the summary stays", KillGoal:Last() ~= nil)

-- One mob only, by the command.
ns.HandleSlash("killgoal 2 mottled boar")
goal = KillGoal:Current()
suite.check("the command starts one", goal and goal.target == 2 and goal.mob == "mottled boar")
Loot(WOLF, { FANG })
suite.check("another mob is left out", goal.have == 0)
Loot(BOAR, { MEAT })
suite.check("that mob counts, any case", goal.have == 1)
ns.HandleSlash("killgoal stop")
suite.check("stop takes it off", KillGoal:Current() == nil)

-- The New Goal box.
local box = KUI:ShowNew()
suite.check("the box opens", box and box:IsShown())
suite.check("it offers any mob first", KUI:PickedMob() == nil)
suite.check("Which Mobs is a drop-down, Any Mob first", box.mobs.options[1].text == "Any Mob"
    and box.mob:GetText() == "Any Mob" and #box.mobs.options == #KUI.choices)
if #box.mobs.options > 1 then
    box.mobs:GetScript("OnMouseDown")(box.mobs)
    box.mobs.entries[2]:GetScript("OnClick")()
    suite.check("a line of its menu picks that mob", KUI:PickedMob() == KUI.choices[2]
        and box.mob:GetText() == KUI.choices[2])
    box.mobs:GetScript("OnMouseDown")(box.mobs)
    box.mobs.entries[1]:GetScript("OnClick")()
end
box.box:SetText("25")
goal = KUI:StartGoal()
suite.check("Start sets it", goal and goal.target == 25 and goal.mob == nil)
suite.check("and closes the box", not box:IsShown())
KillGoal:Stop()

-- Summary by command.
ns.HandleSlash("killgoal summary")
suite.check("summary opens the window", KUI.summary:IsShown())

suite.done()
