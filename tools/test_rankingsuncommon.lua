-- Rankings' "Skip Uncommon and better" (the owner, 2026-10-18).
--
-- What matters: off unless ticked, so worth per kill is as it was; ticked,
-- Uncommon, Rare and Epic drops leave a kill's worth and the best drop,
-- coin and common drops stay, a drop whose quality is not known stays, the
-- order follows the new worth, the rank-up order is laid out again, and
-- the tick box, Settings and /farm rankings uncommon all write the same key.
-- Since 2026-11-18 it is "Exclude Rarity:", a drop-down of Nothing, Epic and
-- Above, Rare and Above or Uncommon and Above.

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

-- Exclude Rarity (a player asked, the owner said build it 2026-11-18):
-- the box became a drop-down of which rarity and better to leave out.
suite.check("Exclude starts on Nothing", Rankings.Exclude() == "none")
QUALITY[7003] = 3
AUCTION[7003] = 8000
for _ = 1, 20 do
    Loot("Blue Wolf", { { name = "Large Fang", id = 5637 }, { name = "Blue Blade", id = 7003, color = "ff0070dd" } })
end
local blue
board = Rankings:Build()
blue, wolf = Find(board.measured, "Blue Wolf"), Find(board.measured, "Green Wolf")
suite.check("Nothing counts the blue", blue and blue.value > 8000)
suite.check("Nothing counts the green", wolf and wolf.value > 5000)

stamp = ns.RankUp.Stamp()
ns.HandleSlash("rankings exclude rare")
suite.check("/farm rankings exclude rare sets it", Rankings.Exclude() == "rare" and ns.db.rankingsExclude == "rare")
suite.check("the old key stays off for Rare", ns.db.rankingsSkipUncommon == false)
suite.check("picking a rarity moves the rank-up stamp", ns.RankUp.Stamp() ~= stamp)
board = Rankings:Build()
blue, wolf = Find(board.measured, "Blue Wolf"), Find(board.measured, "Green Wolf")
suite.check("Rare and Above leaves the blue out", blue and blue.value < 100)
suite.check("Rare and Above keeps the green", wolf and wolf.value > 5000)
suite.check("Rare and Above puts the green wolf first", wolf and wolf.rank == 1)

ns.HandleSlash("rankings exclude epic")
board = Rankings:Build()
blue = Find(board.measured, "Blue Wolf")
suite.check("Epic and Above keeps the blue", blue and blue.value > 8000)

ns.HandleSlash("rankings exclude uncommon")
suite.check("Uncommon and Above is the old box ticked", Rankings.SkipUncommon() and ns.db.rankingsSkipUncommon == true)
board = Rankings:Build()
wolf = Find(board.measured, "Green Wolf")
suite.check("Uncommon and Above leaves the green out", wolf and wolf.value < 100)

ns.HandleSlash("rankings exclude nonsense")
suite.check("a word it doesn't know changes nothing", Rankings.Exclude() == "uncommon")
ns.HandleSlash("rankings exclude none")
suite.check("/farm rankings exclude none counts every drop", Rankings.Exclude() == "none")

-- A save from before: the box ticked, no new key.
ns.db.rankingsExclude = nil
ns.db.rankingsSkipUncommon = true
suite.check("an old save with the box ticked reads as Uncommon and Above", Rankings.Exclude() == "uncommon")
ns.db.rankingsSkipUncommon = false
suite.check("an old save with the box off reads as Nothing", Rankings.Exclude() == "none")

suite.check("the choices run Nothing, Epic, Rare, Uncommon", (function()
    local options = Rankings.ExcludeOptions()
    return #options == 4 and options[1].value == "none" and options[2].value == "epic"
        and options[3].value == "rare" and options[4].value == "uncommon"
        and options[1].plain == "Nothing" and options[3].plain == "Rare and Above"
end)())

-- The tab's drop-down and Settings say the same.
ns.UI:Show()
ns.UI:ShowTab("rankings")
local drop = ns.RankingsUI.exclude
suite.check("the tab has the drop-down", drop ~= nil and ns.RankingsUI.uncommon == nil)
suite.check("the tab's drop-down shows Nothing", drop and drop:GetValue() == "none")
drop:GetScript("OnMouseDown")(drop)
drop.entries[3]:GetScript("OnClick")()
suite.check("picking Rare and Above on the tab sets it", Rankings.Exclude() == "rare")
ns.HandleSlash("rankings uncommon")
suite.check("/farm rankings uncommon on its own toggles to Uncommon and Above", Rankings.Exclude() == "uncommon")
ns.RankingsUI:Render()
suite.check("the tab's drop-down follows the command", drop:GetValue() == "uncommon")
ns.HandleSlash("rankings uncommon off")
suite.check("/farm rankings uncommon off goes back to Nothing", Rankings.Exclude() == "none")

ns.HandleSlash("settings")
local controls = ns.SettingsUI.controls
suite.check("Settings has the drop-down", controls and controls.rankingsExclude ~= nil
    and controls.rankingsSkipUncommon == nil)
if controls and controls.rankingsExclude then
    local box = controls.rankingsExclude
    box:GetScript("OnMouseDown")(box)
    box.entries[2]:GetScript("OnClick")()
    suite.check("picking Epic and Above in Settings sets it", Rankings.Exclude() == "epic")
    ns.HandleSlash("rankings exclude rare")
    suite.check("Settings follows the command", box:GetValue() == "rare")
end

-- A rarity the game hasn't sent yet (the owner, 2026-11-24: with Uncommon
-- and Above picked, greens and blues stayed as Best Drop until the
-- drop-down was changed once). The board asks the game for it, and when
-- it comes in the board on screen is ranked again, not just recoloured.
ns.HandleSlash("rankings exclude uncommon")
local asked = {}
_G.C_Item.RequestLoadItemDataByID = function(id) asked[id] = true end
local plainInfo = _G.C_Item.GetItemInfo
_G.C_Item.GetItemInfo = function(id)
    if not QUALITY[id] then return nil end
    return plainInfo(id)
end
AUCTION[7004] = 9000
for _ = 1, 20 do
    Loot("Cape Ghoul", { { name = "Large Fang", id = 5637 }, { name = "Ghost Cape", id = 7004 } })
end
-- Like the Estimates board: a drop known only by its ID, never looted, so
-- no loot link colour to go on.
ns.Tracker:Looks()["Ghost Cape"] = { id = 7004 }
ns.Util.ForgetRarity()
ns.UI:Build()
ns.UI:Show()
ns.UI:ShowTab("rankings")
local ghoul = Find(Rankings:Build().measured, "Cape Ghoul")
suite.check("a cape of unknown rarity stays in for now", ghoul and ghoul.best and ghoul.best.name == "Ghost Cape")
suite.check("the board asks the game for its rarity", asked[7004] == true)

local function DrawnBest(mob)
    for _, row in ipairs(ns.RankingsUI.list.data or {}) do
        if row.entry and row.entry.mob == mob then return row.entry.best and row.entry.best.name end
    end
    return nil
end
suite.check("the drawn row shows the cape first", DrawnBest("Cape Ghoul") == "Ghost Cape", tostring(DrawnBest("Cape Ghoul")))
local stamp2 = ns.RankUp.Stamp()
QUALITY[7004] = 2
local fire = ns.eventFrame:GetScript("OnEvent")
fire(ns.eventFrame, "GET_ITEM_INFO_RECEIVED", 7004, true)
suite.check("once the game says green, the drawn row drops the cape", DrawnBest("Cape Ghoul") == "Large Fang", tostring(DrawnBest("Cape Ghoul")))
suite.check("and the rank-up order is laid out again", ns.RankUp.Stamp() ~= stamp2)
suite.check("the saved choice is untouched", ns.db.rankingsExclude == "uncommon")

suite.done()
