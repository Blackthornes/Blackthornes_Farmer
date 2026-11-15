-- Rankings' "Vendor prices only" (the owner, 2026-11-15).
--
-- What matters: off unless ticked, so worth per kill is as it was; ticked,
-- every drop counts at what a vendor pays, a drop no vendor buys counts as
-- nothing, coin stays, the order and best drop follow, the rank-up order is
-- laid out again, the price note says vendor prices, the mob's own worth is
-- untouched, and the tick box, Settings and /farm rankings vendor all write
-- the same key.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("rankingsvendor")

local ns = env.Load({ ui = true })
local Rankings = ns.Rankings
local Tracker = ns.Tracker

-- Silk sells well at auction but a vendor pays little; the hide sells
-- poorly at auction but well at a vendor; the gem no vendor buys.
local AUCTION = { [4306] = 3000, [7002] = 40, [7003] = 900 }
local VENDOR = { [4306] = 10, [7002] = 200, [7003] = 0 }

_G.C_Item = {
    GetItemInfo = function(id)
        return "item", nil, 1, 1, 1, "", "", 1, "", "", VENDOR[id] or 0
    end,
    GetItemQualityByID = function() return 1 end,
}
_G.BlackthornesTS = {
    Prices = { GetValue = function(_, id) return AUCTION[id] end },
}

local serial = 0
local function Loot(mob, items)
    serial = serial + 1
    env.world.zone, env.world.subZone = "Silverpine Forest", ""
    env.world.target = { name = mob, level = 20, dead = true, guid = "V-" .. serial }
    env.world.loot = { { name = "12 Copper", money = true } }
    for _, item in ipairs(items) do env.world.loot[#env.world.loot + 1] = item end
    Tracker:OnLoot()
end

for _ = 1, 20 do
    Loot("Silk Spider", { { name = "Silk Cloth", id = 4306 }, { name = "Odd Gem", id = 7003 } })
    Loot("Hide Bear", { { name = "Thick Hide", id = 7002 } })
end

local function Find(list, mob)
    for _, entry in ipairs(list) do
        if entry.mob == mob then return entry end
    end
    return nil
end

suite.check("off by default", not Rankings.VendorOnly())
local board = Rankings:Build()
local spider, bear = Find(board.measured, "Silk Spider"), Find(board.measured, "Hide Bear")
suite.check("off, both are measured", spider ~= nil and bear ~= nil)
suite.check("off, the spider is first", spider and spider.rank == 1)
suite.check("off, the spider's best drop is the silk", spider and spider.best and spider.best.name == "Silk Cloth")
suite.check("off, the note names auction prices", ns.RankingsUI:PriceText() ~= ns.L["vendor prices"])

local stamp = ns.RankUp.Stamp()
ns.HandleSlash("rankings vendor on")
suite.check("/farm rankings vendor on ticks it", Rankings.VendorOnly() and ns.db.rankingsVendorOnly == true)
suite.check("ticking it moves the rank-up stamp", ns.RankUp.Stamp() ~= stamp)

board = Rankings:Build()
spider, bear = Find(board.measured, "Silk Spider"), Find(board.measured, "Hide Bear")
suite.check("ticked, both stay on the board", spider ~= nil and bear ~= nil)
suite.check("ticked, the spider is coin and vendor silk", spider and math.abs(spider.value - (12 + 10)) < 0.5)
suite.check("ticked, the gem no vendor buys counts as nothing", spider and spider.best and spider.best.name == "Silk Cloth"
    and #spider.details.priced == 1)
suite.check("ticked, the bear is coin and vendor hide", bear and math.abs(bear.value - (12 + 200)) < 0.5)
suite.check("ticked, the bear goes first", bear and bear.rank == 1)
suite.check("ticked, drops say vendor", bear and bear.best and bear.best.from == "vendor" and bear.best.unit == 200)
suite.check("ticked, the note says vendor prices", ns.RankingsUI:PriceText() == ns.L["vendor prices"])
suite.check("ticked, the mob's own worth is untouched", (ns.Value:ForMob("Silk Spider")) > 2000)

ns.HandleSlash("rankings vendor off")
suite.check("/farm rankings vendor off unticks it", not Rankings.VendorOnly())
board = Rankings:Build()
spider = Find(board.measured, "Silk Spider")
suite.check("off again, the spider is first", spider and spider.rank == 1)

-- The tab's tick box and Settings say the same.
ns.UI:Show()
ns.UI:ShowTab("rankings")
suite.check("the tab has the box", ns.RankingsUI.vendor ~= nil)
suite.check("the tab's box shows it off", ns.RankingsUI.vendor and not ns.RankingsUI.vendor:GetChecked())
ns.RankingsUI.vendor:GetScript("OnClick")(ns.RankingsUI.vendor)
suite.check("ticking the tab's box turns it on", Rankings.VendorOnly())
ns.HandleSlash("rankings vendor")
suite.check("/farm rankings vendor on its own toggles it", not Rankings.VendorOnly())

suite.done()
