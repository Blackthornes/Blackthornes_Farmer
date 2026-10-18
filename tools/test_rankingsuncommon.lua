-- Rankings' "Skip Uncommon and better" (the owner, 2026-10-18).
--
-- What matters: off unless ticked, so worth per kill is as it was; ticked,
-- Uncommon, Rare and Epic drops leave a kill's worth and the best drop,
-- coin and common drops stay, a drop whose quality is not known stays, the
-- order follows the new worth, the rank-up order is laid out again, and
-- the tick box, Settings and /farm rankings uncommon all write the same key.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("rankingsuncommon")

local ns = env.Load({ ui = true })
local Rankings = ns.Rankings
local Tracker = ns.Tracker

local AUCTION = { [5637] = 50, [7001] = 5000, [7002] = 400 }
local QUALITY = { [5637] = 1, [7001] = 2, [7002] = 1 }

_G.C_Item = {
    GetItemInfo = function(id)
        return "item", nil, QUALITY[id] or 1, 1, 1, "", "", 1, "", "", 1
    end,
    GetItemQualityByID = function(id) return QUALITY[id] end,
}
_G.BlackthornesTS = {
    Prices = { GetValue = function(_, id) return AUCTION[id] end },
}

local serial = 0
local function Loot(mob, items)
    serial = serial + 1
    env.world.zone, env.world.subZone = "Silverpine Forest", ""
    env.world.target = { name = mob, level = 20, dead = true, guid = "U-" .. serial }
    env.world.loot = { { name = "12 Copper", money = true } }
    for _, item in ipairs(items) do env.world.loot[#env.world.loot + 1] = item end
    Tracker:OnLoot()
end

-- Green Wolf drops a green sword every kill; Plain Bear drops a white hide.
for _ = 1, 20 do
    Loot("Green Wolf", { { name = "Large Fang", id = 5637 }, { name = "Shiny Sword", id = 7001, color = "ff1eff00" } })
    Loot("Plain Bear", { { name = "Thick Hide", id = 7002 } })
end

local function Find(list, mob)
    for _, entry in ipairs(list) do
        if entry.mob == mob then return entry end
    end
    return nil
end

suite.check("off by default", not Rankings.SkipUncommon())
local board = Rankings:Build()
local wolf, bear = Find(board.measured, "Green Wolf"), Find(board.measured, "Plain Bear")
suite.check("off, both are measured", wolf ~= nil and bear ~= nil)
suite.check("off, the wolf's green counts", wolf and wolf.value > 5000)
suite.check("off, the wolf is first", wolf and wolf.rank == 1)
suite.check("off, the wolf's best drop is the green", wolf and wolf.best and wolf.best.name == "Shiny Sword")

local stamp = ns.RankUp.Stamp()
ns.HandleSlash("rankings uncommon on")
suite.check("/farm rankings uncommon on ticks it", Rankings.SkipUncommon() and ns.db.rankingsSkipUncommon == true)
suite.check("ticking it moves the rank-up stamp", ns.RankUp.Stamp() ~= stamp)

board = Rankings:Build()
wolf, bear = Find(board.measured, "Green Wolf"), Find(board.measured, "Plain Bear")
suite.check("ticked, both stay on the board", wolf ~= nil and bear ~= nil)
suite.check("ticked, the green leaves the wolf's worth", wolf and wolf.value < 100)
suite.check("ticked, coin and the fang stay", wolf and wolf.value >= 50 + 12)
suite.check("ticked, the bear goes first", bear and bear.rank == 1)
suite.check("ticked, the wolf's best drop is the fang", wolf and wolf.best and wolf.best.name == "Large Fang")
suite.check("ticked, the mob's own worth is untouched", (ns.Value:ForMob("Green Wolf")) > 5000)

-- A drop whose quality is not known yet stays in.
QUALITY[7001] = nil
suite.check("an unknown quality stays in",
    not Rankings.IsUncommonOrBetter({ name = "Mystery", id = 7001 }))
QUALITY[7001] = 2

ns.HandleSlash("rankings uncommon off")
suite.check("/farm rankings uncommon off unticks it", not Rankings.SkipUncommon())
board = Rankings:Build()
wolf = Find(board.measured, "Green Wolf")
suite.check("off again, the green counts", wolf and wolf.value > 5000)

-- The tab's tick box says the same.
ns.UI:Show()
ns.UI:ShowTab("rankings")
suite.check("the tab has the box", ns.RankingsUI.uncommon ~= nil)
suite.check("the tab's box shows it off", ns.RankingsUI.uncommon and not ns.RankingsUI.uncommon:GetChecked())
ns.RankingsUI.uncommon:GetScript("OnClick")(ns.RankingsUI.uncommon)
suite.check("ticking the tab's box turns it on", Rankings.SkipUncommon())
ns.HandleSlash("rankings uncommon")
suite.check("/farm rankings uncommon on its own toggles it", not Rankings.SkipUncommon())

suite.done()
