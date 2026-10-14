-- Your top 15 after an auction scan (the owner, 2026-10-14): a new top farm
-- called out, and the board shuffling to its new order.
--
-- What must hold:
--   1. Tradeskills' scan watcher is asked for; a finished scan values the
--      board again a few mobs a frame and shows the new order, every row
--      sliding from its old place and every worth counting.
--   2. A different mob first, worth LEAD more than the old leader at the
--      new prices, is a new top farm: NEW TOP FARM, TOP on it, the top
--      farm sound, and it is not called again for the same mob that day.
--   3. A new leader by less than LEAD is a shuffle, not a top farm.
--   4. Climbers show how far they went; a scan that moves nothing shows
--      nothing.
--   5. Only mobs with MIN_KILLS kills are on the board.
--   6. Never in a fight; off is kept; without Tradeskills' call the auction
--      house closing is the cue.
--   7. Settings has the box and Try it.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("topfarm")

local ns = env.Load({ ui = true })
local Tracker, RankUp, RankUpUI, TopFarm = ns.Tracker, ns.RankUp, ns.RankUpUI, ns.TopFarm

-- Tradeskills with the scan watcher, as it is at login.
local watchers = {}
_G.BlackthornesTS = {
    Prices = {
        GetValue = function() return nil end,
        WatchScans = function(_, fn) watchers[#watchers + 1] = fn; return true end,
    },
}
local function Scan()
    for _, fn in ipairs(watchers) do fn({ items = 100, at = 0 }) end
end


_G.C_Item = { GetItemInfo = function() return "item", nil, 1, 1, 1, "", "", 1, "", "", 0 end }

local played = {}
_G.PlaySoundFile = function(path) played[#played + 1] = path; return true end
_G.PlaySound = function() return true end

local fighting = false
_G.InCombatLockdown = function() return fighting end

local serial = 0
local function Kill(mob, copper)
    serial = serial + 1
    env.world.target = { name = mob, level = 10, dead = true, guid = "T-" .. serial }
    env.world.loot = copper and copper > 0 and { { name = copper .. " Copper", money = true } } or {}
    Tracker:OnLoot()
end

-- What prices do, here: a factor on a mob's worth a kill.
local factor = {}
local realFromTally = ns.Value.FromTally
ns.Value.FromTally = function(self, name)
    local value, details = realFromTally(self, name)
    if value and factor[name] then value = value * factor[name] end
    return value, details
end

-- Six measured mobs, Mob 1 best (300c) down to Mob 6 (250c); one short.
local function Name(index) return ("Mob %d"):format(index) end
for index = 1, 6 do
    for _ = 1, 20 do Kill(Name(index), 310 - 10 * index) end
end
for _ = 1, 19 do Kill("Short Boar", 900) end

RankUp:OnEnable()
TopFarm:OnEnable()
RankUp:Forget()
RankUp:BuildNow()

local function Settle()
    ns.Motion:FinishAll()
    ns.Motion:FinishAll()
end
local function Reset()
    RankUpUI:Hide()
    played = {}
end
local function Picked()
    for _, item in ipairs(RankUpUI.items or {}) do
        if item.picked then return item end
    end
end
local function ItemOf(mob)
    for _, item in ipairs(RankUpUI.items or {}) do
        if item.mob == mob then return item end
    end
end

suite.check("Tradeskills is asked to tell us about scans", #watchers == 1 and TopFarm:Watching())
suite.check("the board is your own kills", #RankUp.snapshot.list == 6)

--------------------------------------------------------------------------------
-- 1, 2. A new top farm
--------------------------------------------------------------------------------

Reset()
-- Mob 4 (270c) doubles: 540c, first, 80% over Mob 1. Mob 5 passes Mob 6
-- too? No: only Mob 4 moves, the others slide down one.
factor[Name(4)] = 2
Scan()
suite.check("a scan lays the board out again over frames", RankUp.building ~= nil)
suite.check("keeping the old order meanwhile", RankUp.snapshot and RankUp.snapshot.list[1].mob == Name(1))
RankUp:Step(math.huge)

suite.check("the board pops up", RankUpUI:IsShown())
suite.check("titled NEW TOP FARM", RankUpUI.frame.title:GetText() == "NEW TOP FARM",
    RankUpUI.frame.title:GetText())
local picked = Picked()
suite.check("the new leader is picked, from fourth to first",
    picked and picked.mob == Name(4) and picked.from == 3 and picked.to == 0)
local passed = ItemOf(Name(1))
suite.check("the old leader slides down one", passed and passed.from == 0 and passed.to == 1)
suite.check("every worth counts", RankUpUI.counting == true)

Settle()
suite.check("TOP on the new leader", picked.row.chip:IsShown() and picked.row.chip.label:GetText() == "TOP",
    picked.row.chip.label:GetText())
suite.check("the top farm sound",
    #played == 1 and played[1]:find("top-farm.ogg", 1, true) ~= nil, played[1])
suite.check("the foot names it and the lead",
    RankUpUI.foot:GetText():find("Mob 4 is your best farm now", 1, true) ~= nil
    and RankUpUI.foot:GetText():find("80% more than Mob 1", 1, true) ~= nil, RankUpUI.foot:GetText())
suite.check("the told list keeps it", type(ns.db.topFarmTold[Name(4)]) == "number")
suite.check("the kills panel's ranks follow", RankUp:RankOf(Name(4)) == 1)

--------------------------------------------------------------------------------
-- 4. Nothing moved
--------------------------------------------------------------------------------

Reset()
Scan()
RankUp:Step(math.huge)
suite.check("a scan that moves nothing shows nothing", not RankUpUI:IsShown())

--------------------------------------------------------------------------------
-- 3, 4. A shuffle, and a close leader
--------------------------------------------------------------------------------

Reset()
-- Mob 1 back on top by a hair (300 * 1.85 = 555c over 540c), Mob 6 past Mob 5.
factor[Name(1)] = 1.85
factor[Name(6)] = 1.1
Scan()
RankUp:Step(math.huge)
suite.check("a shuffle pops up", RankUpUI:IsShown())
suite.check("not as a top farm under LEAD", RankUpUI.frame.title:GetText() == "YOUR TOP 15",
    RankUpUI.frame.title:GetText())
suite.check("the foot says prices moved",
    RankUpUI.foot:GetText():find("auction scan", 1, true) ~= nil, RankUpUI.foot:GetText())
local six = ItemOf(Name(6))
suite.check("the climber is lit", Picked() and Picked().mob == Name(1))
Settle()
suite.check("other climbers show how far", six and six.row.chip:IsShown() and six.row.chip.label:GetText() == "+1",
    six and six.row.chip.label:GetText())
suite.check("with the rank-up chime",
    #played == 1 and played[1]:find("rank-up.ogg", 1, true) ~= nil, played[1])

--------------------------------------------------------------------------------
-- 2. Once a day a mob
--------------------------------------------------------------------------------

Reset()
factor[Name(1)] = nil
Scan()
RankUp:Step(math.huge)
suite.check("Mob 4 first again shuffles", RankUpUI:IsShown())
suite.check("but is not called the top farm twice in a day", RankUpUI.frame.title:GetText() == "YOUR TOP 15")
Settle()

--------------------------------------------------------------------------------
-- 5, 6. Short mobs, fights, off, no Tradeskills
--------------------------------------------------------------------------------

suite.check("a mob short of 20 kills is never on it", RankUp.snapshot.byMob["Short Boar"] == nil)

Reset()
factor[Name(2)] = 5
fighting = true
Scan()
suite.check("never in a fight", RankUp.building == nil and not RankUpUI:IsShown())
fighting = false
local events = ns.eventFrame:GetScript("OnEvent")
events(ns.eventFrame, "PLAYER_REGEN_ENABLED")
RankUp:Step(math.huge)
suite.check("it shows when the fight ends", RankUpUI:IsShown() and Picked() and Picked().mob == Name(2))
Settle()

Reset()
factor[Name(3)] = 9
ns.commands.topfarm.fn("off")
suite.check("off is kept", ns.db.topFarmAlert == false)
Scan()
suite.check("off shows nothing", RankUp.building == nil and not RankUpUI:IsShown())
ns.commands.topfarm.fn("on")
suite.check("on again", TopFarm.On())

-- Without Tradeskills' call, the auction house closing is the cue.
Reset()
TopFarm.watching = false
local savedTS = _G.BlackthornesTS
_G.BlackthornesTS = nil
events(ns.eventFrame, "AUCTION_HOUSE_CLOSED")
RankUp:Step(math.huge)
suite.check("without Tradeskills the auction house closing looks", RankUpUI:IsShown()
    and Picked() and Picked().mob == Name(3))
Settle()
_G.BlackthornesTS = savedTS

--------------------------------------------------------------------------------
-- 8. It waits for the auction house and the game's windows to close
--------------------------------------------------------------------------------

Reset()
events(ns.eventFrame, "AUCTION_HOUSE_SHOW")
factor[Name(5)] = 20
Scan()
RankUp:Step(math.huge)
suite.check("at the auction house it waits", not RankUpUI:IsShown() and TopFarm:Holding())
suite.check("and so does the sound", #played == 0, #played)
suite.check("looking again while it waits", TopFarm.ticker ~= nil)

-- A second scan before it closes folds into the first.
factor[Name(4)] = 40
Scan()
RankUp:Step(math.huge)
suite.check("a second scan still waits", not RankUpUI:IsShown())

events(ns.eventFrame, "AUCTION_HOUSE_CLOSED")
suite.check("it shows when the auction house closes", RankUpUI:IsShown() and not TopFarm:Holding())
suite.check("from the order before the first scan to after the last",
    ItemOf(Name(4)) and ItemOf(Name(4)).to == 0 and ItemOf(Name(5)) and ItemOf(Name(5)).to == 1)
suite.check("no longer looking", TopFarm.ticker == nil)
Settle()
suite.check("with its sound", #played == 1, #played)

-- Any of the game's own panels holds it too.
Reset()
local panel = { name = "a panel" }
_G.GetUIPanel = function(key) return key == "left" and panel or nil end
factor[Name(2)] = 200
Scan()
RankUp:Step(math.huge)
suite.check("a game window open holds it", not RankUpUI:IsShown() and TopFarm:Holding())
_G.GetUIPanel = function() return nil end
TopFarm:TryShow()
suite.check("and it shows once that closes", RankUpUI:IsShown())
Settle()
_G.GetUIPanel = nil

-- Turned off while it waits: nothing is held.
Reset()
events(ns.eventFrame, "AUCTION_HOUSE_SHOW")
factor[Name(1)] = 500
Scan()
RankUp:Step(math.huge)
ns.commands.topfarm.fn("off")
events(ns.eventFrame, "AUCTION_HOUSE_CLOSED")
suite.check("off while it waits lets it go", not RankUpUI:IsShown() and not TopFarm:Holding())
ns.commands.topfarm.fn("on")

-- Try it: the second mob rises to the top.
Reset()
ns.commands.topfarm.fn("test")
suite.check("Try it shows a new top farm", RankUpUI:IsShown()
    and RankUpUI.frame.title:GetText() == "NEW TOP FARM")
Settle()

suite.done()
