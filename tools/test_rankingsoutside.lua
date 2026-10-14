-- Rankings' "Outside dungeons only" (the owner, 2026-10-14).
--
-- What matters: off unless ticked, so the board is as it was; ticked, a mob
-- whose kills were all inside a dungeon or raid leaves every board (Forever's
-- own dungeons too, told by the client's game tables), a mob killed inside and
-- out stays, a capital is no dungeon, a database mob Classic's data puts in a
-- dungeon goes while one in an open world subzone that shares a dungeon's
-- name stays; the rank-up order follows it; the tick box, Settings and
-- /farm rankings outside all write the same key.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("rankingsoutside")

local ns = env.Load({ ui = true })
local Rankings = ns.Rankings
local Tracker = ns.Tracker
local Spots = ns.Spots

local AUCTION = { [5637] = 50, [99001] = 200, [99002] = 20, [99003] = 30 }

_G.C_Item = {
    GetItemInfo = function(id)
        return "item", nil, 1, 1, 1, "", "", 1, "", "", 1
    end,
}
_G.BlackthornesTS = {
    Prices = { GetValue = function(_, id) return AUCTION[id] end },
}

local serial = 0
local function Loot(mob, zone, subZone)
    serial = serial + 1
    env.world.zone, env.world.subZone = zone, subZone
    env.world.target = { name = mob, level = 20, dead = true, guid = "O-" .. serial }
    env.world.loot = { { name = "12 Copper", money = true }, { name = "Large Fang", id = 5637 } }
    Tracker:OnLoot()
end

for _ = 1, 20 do
    Loot("Open Wolf", "Silverpine Forest", "The Sepulcher")
    Loot("Defias Miner", "The Deadmines", "Mast Room")
    Loot("Cursed Ghoul", "Ruins of Lordaeron", "")
    Loot("City Rat", "Stormwind City", "Trade District")
end
for index = 1, 20 do
    Loot("Wandering Bat", index <= 10 and "Shadowfang Keep" or "Silverpine Forest", "")
end

-- Database estimates: one in Classic's dungeon, one in an open world
-- subzone of a dungeon's name as recorded in game, one in the open.
ns.DB:RegisterItem({ name = "Ogre Tooth", id = 99001, category = "misc",
    sources = { { name = "Test Pirate", zone = "Westfall", location = "The Deadmines",
        minLevel = 18, chance = 40 } } })
ns.DB:RegisterItem({ name = "Hound Fang", id = 99002, category = "misc",
    sources = { { name = "Test Hound", zone = "Tirisfal Glades", location = "Ruins of Lordaeron",
        minLevel = 8, chance = 40, provenance = "forever" } } })
ns.DB:RegisterItem({ name = "Troll Tusk", id = 99003, category = "misc",
    sources = { { name = "Test Troll", zone = "Stranglethorn Vale", minLevel = 40, chance = 40 } } })

local function Has(list, mob)
    for _, entry in ipairs(list) do
        if entry.mob == mob then return true end
    end
    return false
end

-- What is a dungeon.
suite.check("The Deadmines is a dungeon", Spots.IsInstance("The Deadmines"))
suite.check("Forever's Ruins of Lordaeron is a dungeon", Spots.IsInstance("Ruins of Lordaeron"))
suite.check("Forever's name for Wailing Caverns is a dungeon", Spots.IsInstance("The Wailing Caverns"))
suite.check("Blackrock Depths is a dungeon", Spots.IsInstance("Blackrock Depths"))
suite.check("Molten Core is a raid", Spots.IsInstance("Molten Core"))
suite.check("a capital is no dungeon", not Spots.IsInstance("Stormwind City"))
suite.check("an open zone is no dungeon", not Spots.IsInstance("Silverpine Forest"))
suite.check("Deadwind Pass stays an open zone", not Spots.IsInstance("Deadwind Pass"))

-- Off unless ticked.
suite.check("off by default", not Rankings.OutsideOnly())
local board = Rankings:Build()
suite.check("off, a dungeon's mob is ranked", Has(board.measured, "Defias Miner"))
suite.check("off, a dungeon's estimate is ranked", Has(board.estimate, "Test Pirate"))

local stamp = ns.RankUp.Stamp()
ns.RankUp:Forget()
ns.RankUp:BuildNow()
suite.check("the rank-up order has the dungeon's mob", ns.RankUp:RankOf("Defias Miner") ~= nil)

-- Ticked.
ns.HandleSlash("rankings outside on")
suite.check("/farm rankings outside on ticks it", Rankings.OutsideOnly() and ns.db.rankingsOutside == true)
board = Rankings:Build()
suite.check("a mob killed only in a dungeon leaves", not Has(board.measured, "Defias Miner"))
suite.check("a mob killed only in Forever's dungeon leaves", not Has(board.measured, "Cursed Ghoul"))
suite.check("a mob killed in the open stays", Has(board.measured, "Open Wolf"))
suite.check("a mob killed in a capital stays", Has(board.measured, "City Rat"))
suite.check("a mob killed inside and out stays", Has(board.measured, "Wandering Bat"))
suite.check("a Classic dungeon estimate leaves", not Has(board.estimate, "Test Pirate"))
suite.check("an open subzone named like a dungeon stays", Has(board.estimate, "Test Hound"))
suite.check("an open world estimate stays", Has(board.estimate, "Test Troll"))
suite.check("the ranks close up", board.measured[1].rank == 1)

suite.check("the stamp moved", ns.RankUp.Stamp() ~= stamp)
suite.check("the old rank-up order is not used", ns.RankUp:RankOf("Open Wolf") == nil)
ns.RankUp:Step(math.huge)
suite.check("laid out again without the dungeon's mob", ns.RankUp:RankOf("Defias Miner") == nil)
suite.check("and with the open world's", ns.RankUp:RankOf("Open Wolf") ~= nil)

-- The tab's tick box and Settings say the same.
ns.UI:Show()
ns.UI:ShowTab("rankings")
suite.check("the tab's box shows it ticked", ns.RankingsUI.outside and ns.RankingsUI.outside:GetChecked())
ns.RankingsUI.outside:GetScript("OnClick")(ns.RankingsUI.outside)
suite.check("unticking the tab's box turns it off", not Rankings.OutsideOnly())
ns.HandleSlash("rankings outside")
suite.check("/farm rankings outside on its own toggles it", Rankings.OutsideOnly())
ns.HandleSlash("rankings outside off")
suite.check("/farm rankings outside off turns it off", not Rankings.OutsideOnly())
board = Rankings:Build()
suite.check("off again, the dungeon's mob is back", Has(board.measured, "Defias Miner"))
suite.check("nothing recorded was lost", Tracker:Store()["Defias Miner"].kills == 20)

suite.done()
