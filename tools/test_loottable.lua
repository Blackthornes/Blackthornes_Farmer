-- A mob's full loot table.
--
-- What matters: the panel still shows three drops a mob, says how many more
-- there are and opens the rest on a click; the window lists every item with
-- its counts and totals, holds rates and values back until MIN_KILLS, prices
-- what it can, follows new loot while open, and /farm loot finds a mob loosely.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("loottable")

local ns = env.Load({ ui = true })
local Tracker = ns.Tracker
local TUI = ns.TrackerUI
local LTU = ns.LootTableUI

_G.C_Item = {
    GetItemInfo = function(id)
        return "item", nil, 1, 1, 1, "", "", 1, "", "", id == 2934 and 5 or 0
    end,
}
_G.BlackthornesTS = {
    Prices = { GetValue = function(_, id) return ({ [5637] = 50 })[id] end },
}

TUI:OnEnable()

local serial = 0

local function Loot(mob, items)
    serial = serial + 1
    env.world.target = { name = mob, level = 8, dead = true, guid = "C-" .. serial }
    env.world.loot = items
    Tracker:OnLoot()
end

local function Line(left)
    for index, line in ipairs(TUI.shown or {}) do
        if line.left == left then return line, index end
    end
end

local WOLF = "Mangy Wolf"
local FANG = { name = "Large Fang", id = 5637 }
local SCRAPS = { name = "Ruined Leather Scraps", id = 2934, quantity = 2 }
local PAW = { name = "Wolf Paw", id = 1001 }
local TOOTH = { name = "Chipped Tooth", id = 1002 }
local SKULL = { name = "Wolf Skull", id = 1003 }
local COINS = { name = "10 Copper", money = true }

--------------------------------------------------------------------------------
-- The panel: three drops, then a way to the rest
--------------------------------------------------------------------------------

Loot(WOLF, { COINS, SCRAPS, FANG, PAW, TOOTH, SKULL })
Loot(WOLF, { COINS, SCRAPS, FANG, PAW })
Loot(WOLF, { COINS, SCRAPS, FANG })
Loot(WOLF, { COINS, SCRAPS })
Loot(WOLF, { COINS, SCRAPS })

local band = Line(WOLF)
suite.check("the mob's band opens its table", band and band.mob == WOLF)

-- Every item the mob has dropped sits under its band as an icon, most
-- common first (Trent, 2026-09-28: three was "limiting").
local icons, iconsIndex
for index = select(2, Line(WOLF)) + 1, #TUI.shown do
    local line = TUI.shown[index]
    if line.style == "mob" then break end
    if line.style == "icons" then icons, iconsIndex = line, index break end
end
local names = {}
for _, icon in ipairs(icons and icons.icons or {}) do names[#names + 1] = icon.item end
suite.check("the panel shows every item the mob has dropped",
    #names == 5 and names[1] == "Ruined Leather Scraps" and names[2] == "Large Fang",
    table.concat(names, ","))
suite.check("each with how many corpses held it", icons and icons.icons[1].text == "5",
    icons and icons.icons[1].text)
suite.check("no Show all line any more", Line("Show all 5 items") == nil)

--------------------------------------------------------------------------------
-- The table, before there are enough kills for rates
--------------------------------------------------------------------------------

local data = LTU:Table(WOLF)
suite.check("every item is in the table", data and #data.rows == 5, data and #data.rows)
suite.check("most common first", data.rows[1].name == "Ruined Leather Scraps", data.rows[1].name)
suite.check("how many corpses held it", data.rows[1].dropped == "5 of 5", data.rows[1].dropped)
suite.check("how many were taken in all", data.rows[1].total == "x10", data.rows[1].total)
suite.check("the rarest is there too", data.rows[5].dropped == "1 of 5", data.rows[5].dropped)
suite.check("no rate below the threshold", data.rows[1].rate == nil and data.rows[1].chance == nil)
suite.check("and no value", data.rows[1].perKill == nil)
-- Coin is measured, not a rate, so it shows from the first kill.
suite.check("coin per kill shows before the rate threshold", data.coinPerKill == 10,
    data.coinPerKill)
suite.check("it knows how many kills are left", data.needed == 15, data.needed)

suite.check("a mob never killed has no table", LTU:Table("Nobody") == nil)
suite.check("and does not open", LTU:Show("Nobody") == false)

--------------------------------------------------------------------------------
-- Clicking
--------------------------------------------------------------------------------

local slot = TUI.lines[iconsIndex].slots[1]
suite.check("the drawn icon remembers its item", slot.line == icons.icons[1])

slot:GetScript("OnClick")(slot, "LeftButton")
suite.check("clicking an item opens the window", LTU:IsShown() and LTU.mob == WOLF)
suite.check("titled with the mob", LTU.title:GetText() == WOLF, LTU.title:GetText())
suite.check("it is as tall as its rows", LTU.frame:GetHeight() == LTU:HeightFor(5)
    and LTU:HeightFor(5) < LTU:HeightFor(12), LTU.frame:GetHeight())
suite.check("with a floor and a ceiling", LTU:HeightFor(0) == 240 and LTU:HeightFor(500) == 460)
suite.check("it hangs from its top edge", LTU.frame._point[1] == "TOP", LTU.frame._point[1])
LTU.frame._left, LTU.frame._top = 300, 800
LTU.frame:GetScript("OnDragStop")(LTU.frame)
suite.check("and still does after a drag", LTU.frame._point[1] == "TOPLEFT"
    and LTU.frame._point[4] == 300 and LTU.frame._point[5] == 800, LTU.frame._point[1])
suite.check("it says rates are still to come",
    LTU.status:GetText():find("15 more kills", 1, true) ~= nil, LTU.status:GetText())
suite.check("it says where the mob was killed",
    LTU.where:GetText() == "Killed at: The Sepulcher, Silverpine Forest.", LTU.where:GetText())
suite.check("the window is wide enough for that line",
    LTU.frame:GetWidth() >= LTU:WidthFor(nil, "", LTU.where:GetText()), LTU.frame:GetWidth())

slot:GetScript("OnClick")(slot, "LeftButton")
suite.check("clicking the same mob again closes it", not LTU:IsShown())

-- A drag that starts on an icon moves the panel, and letting go does not
-- count as a click.
slot:GetScript("OnDragStart")(slot)
slot:GetScript("OnDragStop")(slot)
slot:GetScript("OnClick")(slot, "LeftButton")
suite.check("letting go after a drag does not open it", not LTU:IsShown())
slot:GetScript("OnClick")(slot, "LeftButton")
suite.check("the next click does", LTU:IsShown())

local plain = TUI.lines[select(2, Line("The Sepulcher, Silverpine Forest"))]
suite.check("a place row opens nothing", plain.line.mob == nil and plain.line.openKey == nil)
LTU:Hide()
plain:GetScript("OnMouseUp")(plain, "LeftButton")
suite.check("so clicking it does nothing", not LTU:IsShown())

--------------------------------------------------------------------------------
-- It follows new loot while open, and fills in rates at the threshold
--------------------------------------------------------------------------------

LTU:Show(WOLF)
for _ = 1, 15 do Loot(WOLF, { COINS, SCRAPS }) end

data = LTU.data
suite.check("new loot updates the open table", data.kills == 20, data.kills)
suite.check("rates appear at the threshold", data.rows[1].rate == "100%", data.rows[1].rate)
suite.check("a rare drop gets its rate", data.rows[5].rate == "5%", data.rows[5].rate)

-- Scraps: 40 taken over 20 kills, vendor 5c (above its missing auction price).
suite.check("a priced item is worth its share of a kill",
    math.abs((data.rows[1].perKill or 0) - 10) < 0.001, data.rows[1].perKill)
-- Fang: 3 over 20 kills at 50c auction.
local fang
for _, entry in ipairs(data.rows) do if entry.name == "Large Fang" then fang = entry end end
suite.check("an auction price counts too", fang and math.abs(fang.perKill - 7.5) < 0.001,
    fang and fang.perKill)

-- Items with no price stay unpriced rather than zero.
local paw
for _, entry in ipairs(data.rows) do if entry.name == "Wolf Paw" then paw = entry end end
suite.check("an item with no price has no value", paw and paw.perKill == nil)

suite.check("coin per kill appears", data.coinPerKill == 10, data.coinPerKill)
suite.check("the whole kill is valued from the tally", data.basis == "tally" and data.worth ~= nil)
suite.check("the window says rates are from your kills",
    LTU.status:GetText():find("your own kills", 1, true) ~= nil, LTU.status:GetText())

Tracker:Reset()
suite.check("clearing the tally closes it", not LTU:IsShown())

--------------------------------------------------------------------------------
-- A tally from before coin was counted per kill (Trent, 2026-09-25)
--
-- Coin was divided by every kill, including the many from before any coin was
-- recorded, so coin per kill showed a fraction of the real amount.
--------------------------------------------------------------------------------

local BOAR = "Mottled Boar"
Tracker:Store()[BOAR] = { kills = 40, items = { ["Boar Ribs"] = 12 },
    qty = { ["Boar Ribs"] = 3 }, copper = 60 }

suite.check("an old tally has no coin per kill until it records some",
    Tracker:CoinPerKill(BOAR) == nil)
suite.check("and its drops count one each", Tracker:StackSize(BOAR, "Boar Ribs") == 1)
suite.check("an old tally says places start from the next kill",
    LTU:Table(BOAR).where == "Killed at: recorded from your next kill on.", LTU:Table(BOAR).where)

local RIBS = { name = "Boar Ribs", id = 2677, quantity = 2 }
local SILVER = { name = "1 Silver 5 Copper", money = true }
Loot(BOAR, { SILVER, RIBS })
Loot(BOAR, { SILVER })

suite.check("coin per kill is over the kills that recorded coin",
    Tracker:CoinPerKill(BOAR) == 105, Tracker:CoinPerKill(BOAR))
local boar = Tracker:Store()[BOAR]
suite.check("the old coin is kept, set aside", boar.oldCopper == 60, boar.oldCopper)
suite.check("and the old amounts", boar.oldQty and boar.oldQty["Boar Ribs"] == 3)
suite.check("the kill count is untouched", boar.kills == 42, boar.kills)
suite.check("stacks are from the kills that recorded them",
    Tracker:StackSize(BOAR, "Boar Ribs") == 2, Tracker:StackSize(BOAR, "Boar Ribs"))

LTU:Show(BOAR)
suite.check("opening counts the coin up", ns.Motion:Running(LTU.coin, "count"))
ns.Motion:FinishAll()
suite.check("the window shows the real coin per kill",
    LTU.coin:GetText() == ns.Value.Coins(105), LTU.coin:GetText())
suite.check("and says how many kills it is from",
    LTU.status:GetText():find("Coin is from your last 2 kills.", 1, true) ~= nil,
    LTU.status:GetText())
suite.check("and owns up to the kills that have no place",
    LTU.where:GetText() == "Killed at: The Sepulcher, Silverpine Forest. 40 kills with no place.",
    LTU.where:GetText())
LTU:Hide()

-- The worth of a kill uses the same coin.
local worth, details = ns.Value:ForMob(BOAR)
suite.check("the value of a kill uses it too", details and details.coin == 105,
    details and details.coin)

--------------------------------------------------------------------------------
-- /farm loot
--------------------------------------------------------------------------------

Loot(WOLF, { SCRAPS })

ns.HandleSlash("loot mangy")
suite.check("/farm loot finds a mob by the start of its name", LTU:IsShown() and LTU.mob == WOLF)
LTU:Hide()

local mark = #env.chat
ns.HandleSlash("loot kobold")
suite.check("/farm loot for a mob never killed says so",
    table.concat(env.chat, "\n", mark + 1):find("no kills of kobold", 1, true) ~= nil)
suite.check("and opens nothing", not LTU:IsShown())

suite.done()
