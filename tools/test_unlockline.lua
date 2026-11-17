-- The drop rates fanfare plays at the 20th kill of the line you see.
--
-- Found in game (2026-11-17): a mob killed in two zones gets a line a zone
-- (see test_zonelines), but the 20 kill fanfare counted the whole name, so
-- the 9th Hillsbrad Miner on the panel's line played it (11 more were on the
-- other line). The fanfare must follow the line's own count, the one the
-- panel, the tooltip and the nameplate show.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("unlockline")

local ns = env.Load({ ui = true })
local Tracker = ns.Tracker

_G.C_Item = {
    GetItemInfo = function()
        return "item", nil, 1, 1, 1, "", "", 1, "", "", 1
    end,
}

local played = {}
local realCelebrate = Tracker.Celebrate
Tracker.Celebrate = function(self, key)
    played[#played + 1] = key
    return realCelebrate(self, key)
end

local serial = 0
local function Kill(mob, zone, subZone)
    serial = serial + 1
    env.world.zone, env.world.subZone = zone, subZone
    env.world.target = { name = mob, level = 20, dead = true, guid = "U-" .. serial }
    env.world.loot = { { name = "Silk Cloth", id = 4306 } }
    Tracker:OnLoot()
end

local MINER = "Hillsbrad Miner"
for _ = 1, 11 do Kill(MINER, "Hillsbrad Foothills", "Azurelode Mine") end
for _ = 1, 8 do Kill(MINER, "Azurelode Mine", "") end
local mine = Tracker.ZoneKey(MINER, "Azurelode Mine")
suite.check("the miner is split in two lines", Tracker:IsSplit(MINER))
suite.check("no fanfare yet", #played == 0, played)

-- The 9th on the mine's line is the 20th of the whole name.
Kill(MINER, "Azurelode Mine", "")
suite.check("the whole name has 20 kills", Tracker:Store()[MINER].kills == 20)
suite.check("the panel's line has 9", Tracker:Tally(mine).kills == 9)
suite.check("no fanfare on the line's 9th kill", #played == 0, played)

for _ = 1, 10 do Kill(MINER, "Azurelode Mine", "") end
suite.check("still none at the line's 19th", #played == 0, played)
Kill(MINER, "Azurelode Mine", "")
suite.check("the fanfare plays at the line's 20th", #played == 1 and played[1] == mine, played)
local summary = Tracker:Summary(mine)
suite.check("and names the line's 20 kills", summary and summary.kills == 20)

-- The other line gets its own at its own 20th.
for _ = 1, 9 do Kill(MINER, "Hillsbrad Foothills", "Azurelode Mine") end
suite.check("the other line's 20th has its own",
    #played == 2 and played[2] == Tracker.ZoneKey(MINER, "Hillsbrad Foothills"), played)

-- A mob in one zone plays it at its 20th, as before.
for _ = 1, 19 do Kill("Gray Wolf", "Elwynn Forest", "Northshire") end
suite.check("one zone: none at 19", #played == 2, played)
Kill("Gray Wolf", "Elwynn Forest", "Northshire")
suite.check("one zone: the 20th plays it", #played == 3 and played[3] == "Gray Wolf", played)

suite.done()
