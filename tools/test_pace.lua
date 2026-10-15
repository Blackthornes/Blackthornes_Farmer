-- How long it takes you to farm one of an item (Logic/Pace.lua), for
-- Tradeskills' Your time view.
--
-- What matters: the answer comes only from your own kills, skins and
-- gathers, each source only once MIN_SAMPLE are behind it (and a kill only
-- at the mob's own kill pace); the fastest source wins; too few says how
-- many there are; hidden items and sources are left out; an item ID finds
-- the name loot was recorded under; and nothing raises.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("pace")
local check = suite.check

local ns = env.Load({})
local Pace, Tracker, Stats, DB = ns.Pace, ns.Tracker, ns.Stats, ns.DB

check("the module is loaded", Pace ~= nil)
check("it is on the global", _G.BlackthornesFarmer.Pace == Pace)

local clock = 1000
_G.GetTime = function() return clock end

_G.C_Item = {
    GetItemInfo = function(id)
        if id == 2449 then return "Earthroot" end
        if id == 4306 then return "Silk Cloth" end
    end,
}

DB:RegisterItem({ name = "Silk Cloth", id = 4306, category = "Cloth", sources = {} })

-- 40 kills of a bandit, 20 of which gave silk, 2 a corpse: 1 silk a kill.
local store = Tracker:Store()
store["Vale Bandit"] = { kills = 40, coinKills = 40, items = { ["Silk Cloth"] = 20 },
    qty = { ["Silk Cloth"] = 40 }, stacks = { ["Silk Cloth"] = 20 } }
-- A quick mob with few kills: not enough yet.
store["Vale Cub"] = { kills = 6, items = { ["Silk Cloth"] = 6 } }

local stats = Stats:Store()
stats.pace["Vale Bandit"] = { kills = 30, seconds = 900 }   -- 30 s a kill
stats.pace["Vale Cub"] = { kills = 6, seconds = 30 }

local silk = Pace:ForItem(4306)
check("silk is found by item ID", silk ~= nil)
check("from the bandit's kills", silk and silk.kind == "kill" and silk.source == "Vale Bandit")
check("30 seconds a silk", silk and math.abs(silk.seconds - 30) < 0.01)
check("with the kills behind it", silk and silk.samples == 40)
check("by name too", (Pace:ForItem("Silk Cloth") or {}).source == "Vale Bandit")

-- A mob with enough kills but no pace of its own is not timed by the
-- average of every mob.
store["Vale Wolf"] = { kills = 50, items = { ["Wolf Fang"] = 50 } }
Pace:Forget()
local fang, few = Pace:ForItem("Wolf Fang")
check("no own pace, no answer", fang == nil)
check("but it says how many kills there are", few and few.samples == 50)

-- Gathers: 25 gathers over 1000 seconds, 50 herbs.
ns.db.gathering = { pace = { ["Test Vale|Earthroot"] = { gathers = 25, seconds = 1000,
    items = { Earthroot = 50 } } } }
Pace:Forget()
local herb = Pace:ForItem(2449)
check("a herb from your gathers", herb and herb.kind == "gather" and herb.zone == "Test Vale")
check("20 seconds a herb", herb and math.abs(herb.seconds - 20) < 0.01)
check("two a gather", herb and math.abs(herb.perAction - 2) < 0.01)

-- Too few gathers says so.
ns.db.gathering.pace["Test Vale|Mageroyal"] = { gathers = 4, seconds = 100, items = { Mageroyal = 4 } }
Pace:Forget()
local royal, short = Pace:ForItem("Mageroyal")
check("four gathers is not enough", royal == nil and short and short.samples == 4)

-- Skins at the mob's own kill pace: 20 skins, 30 leather.
ns.db.skinLog = { ["Vale Bandit"] = { skins = 20, items = { ["Light Leather"] = 30 } } }
Pace:Forget()
local leather = Pace:ForItem("Light Leather")
check("leather from your skins", leather and leather.kind == "skin")
check("20 seconds a leather", leather and math.abs(leather.seconds - 20) < 0.01)

-- The fastest source wins.
ns.db.gathering.pace["Other Vale|Earthroot"] = { gathers = 30, seconds = 300, items = { Earthroot = 30 } }
Pace:Forget()
check("the faster zone wins", (Pace:ForItem("Earthroot") or {}).zone == "Other Vale")

-- Hidden sources and items are left out.
DB:Hide("source", "Vale Bandit")
Pace:Forget()
check("a hidden mob gives no pace", Pace:ForItem("Silk Cloth") == nil)
DB:Unhide("source", "Vale Bandit")
DB:Hide("item", "Earthroot")
Pace:Forget()
check("a hidden item gives no pace", Pace:ForItem("Earthroot") == nil)
DB:Unhide("item", "Earthroot")

-- Kept a while, then built again.
Pace:Forget()
Pace:ForItem("Silk Cloth")
store["Vale Bandit"].kills = 80
check("kept between questions", Pace:ForItem("Silk Cloth").samples == 40)
clock = clock + Pace.KEEP + 1
check("built again after a while", Pace:ForItem("Silk Cloth").samples == 80)

-- Never raises.
local old = Tracker.Store
Tracker.Store = function() error("boom") end
Pace:Forget()
local ok, value, reason = pcall(Pace.ForItem, Pace, "Silk Cloth")
check("a broken store does not raise", ok and value == nil and reason and reason.samples == 0)
Tracker.Store = old
check("nonsense asks get nothing", Pace:ForItem(nil) == nil and Pace:ForItem({}) == nil)

suite.done()
