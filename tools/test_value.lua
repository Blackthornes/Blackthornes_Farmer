-- What a kill is worth.
--
-- Prices come from Blackthornes Tradeskills when it is loaded, stood in for
-- here by a fake with the same GetValue. What matters: amounts and coin come
-- from your own tally, the vendor price wins when it is higher, nothing is
-- valued below MIN_KILLS, the database estimate is labelled as one, and a
-- value this client will not let us read costs that item, never an error.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("value")

local ns = env.Load({ ui = true })
local Value = ns.Value
local Tracker = ns.Tracker

-- Item info: the 11th return is what a vendor pays.
local VENDOR = { [5637] = 10, [2934] = 5, [3300] = 20 }

-- Quality is the 3rd return; 0 is grey. Everything else is white.
local QUALITY = { [3300] = 0, [3301] = 0 }

-- Item info the client has not cached yet answers nothing at all.
local UNCACHED = {}

_G.C_Item = {
    GetItemInfo = function(id)
        if UNCACHED[id] then return nil end
        return "item", nil, QUALITY[id] or 1, 1, 1, "", "", 1, "", "", VENDOR[id] or 0
    end,
}

-- Tradeskills, as far as Farmer ever touches it.
local AUCTION = { [5637] = 50, [2934] = 3, [3300] = 500, [3301] = 500, [3302] = 500 }

local function InstallTradeskills()
    _G.BlackthornesTS = {
        Prices = {
            GetValue = function(_, id) return AUCTION[id] end,
        },
    }
end

InstallTradeskills()

local serial = 0

local function Loot(mob, items, guid)
    serial = serial + 1
    env.world.target = { name = mob, level = 8, dead = true, guid = guid or ("C-" .. serial) }
    env.world.loot = items
    Tracker:OnLoot()
end

local WOLF = "Mangy Wolf"
local FANG = { name = "Large Fang", id = 5637 }
local SCRAPS = { name = "Ruined Leather Scraps", id = 2934, quantity = 2 }
local COINS = { name = "12 Copper", money = true }

--------------------------------------------------------------------------------
-- Money
--------------------------------------------------------------------------------

suite.check("Money: nothing", Value.Money(0) == "0c")
suite.check("Money: silver and copper", Value.Money(250) == "2s 50c", Value.Money(250))
suite.check("Money: past a gold, no copper", Value.Money(12345) == "1g 23s", Value.Money(12345))
suite.check("Money: past a gold with no silver, no copper either",
    Value.Money(10003) == "1g", Value.Money(10003))
suite.check("Money: rounds", Value.Money(34.5) == "35c", Value.Money(34.5))

suite.check("CoinCopper: mixed", Tracker.CoinCopper("1 Gold 2 Silver 3 Copper") == 10203)
suite.check("CoinCopper: over two lines", Tracker.CoinCopper("1 Silver\n5 Copper") == 105)
suite.check("CoinCopper: not coin", Tracker.CoinCopper("Copper Ore") == nil)

--------------------------------------------------------------------------------
-- Below the threshold there is no value
--------------------------------------------------------------------------------

for index = 1, 19 do
    Loot(WOLF, { COINS, SCRAPS, index <= 5 and FANG or nil })
end

suite.check("19 kills has no value from the tally", Value:FromTally(WOLF) == nil)

local mark = #env.chat
ns.HandleSlash("value mangy")
local said = table.concat(env.chat, "\n", mark + 1)
suite.check("/farm value says how many more kills", said:find("1 more kill before", 1, true) ~= nil, said)

--------------------------------------------------------------------------------
-- From the tally
--------------------------------------------------------------------------------

Loot(WOLF, { COINS, SCRAPS })

-- 20 kills: 12c each, fang on 5 at 50c (auction), 2 scraps each at 5c (the
-- vendor pays more than the 3c auction price).
-- 12 + 5/20*50 + 40/20*5 = 12 + 12.5 + 10 = 34.5
local worth, details = Value:ForMob(WOLF)
suite.check("20 kills has a value", worth ~= nil)
suite.check("it is coin plus amounts times prices", worth == 34.5, worth)
suite.check("it comes from the tally", details and details.basis == "tally")
suite.check("coin per kill is counted", details and details.coin == 12, details and details.coin)

local byName = {}
for _, entry in ipairs(details.priced) do byName[entry.name] = entry end
suite.check("the auction price is used when it is higher",
    byName["Large Fang"] and byName["Large Fang"].from == "auction")
suite.check("the vendor price is used when it pays more",
    byName["Ruined Leather Scraps"] and byName["Ruined Leather Scraps"].from == "vendor"
        and byName["Ruined Leather Scraps"].unit == 5)

-- Skinning the same corpse again adds no coin.
Loot(WOLF, { COINS }, "C-skin")
local copper = Tracker:Store()[WOLF].copper
Loot(WOLF, { COINS }, "C-skin")
suite.check("a second window on a corpse adds no coin",
    Tracker:Store()[WOLF].copper == copper, Tracker:Store()[WOLF].copper)

mark = #env.chat
ns.HandleSlash("value mangy")
said = table.concat(env.chat, "\n", mark + 1)
suite.check("/farm value prints the value", said:find("about", 1, true) ~= nil, said)
suite.check("and says the prices are auction prices",
    said:find("auction prices", 1, true) ~= nil, said)

--------------------------------------------------------------------------------
-- The panel and the search window
--------------------------------------------------------------------------------

ns.TrackerUI:Refresh()

local valueLine
for _, line in ipairs(ns.TrackerUI.shown) do
    if line.style == "value" then valueLine = line end
end
suite.check("the panel shows a value under the mob", valueLine ~= nil)
suite.check("from the tally, not an estimate",
    valueLine and valueLine.left == "Worth per kill", valueLine and valueLine.left)

GameTooltip._lines = {}
ns.UI:ShowValueTooltip({ data = { type = "source", source = { name = WOLF } } })
suite.check("hovering a mob in search shows its worth",
    (GameTooltip._lines[2] or ""):find("Worth about", 1, true) ~= nil, GameTooltip._lines[2])

GameTooltip._lines = {}
ns.UI:ShowValueTooltip({ data = { type = "source", source = { kind = "node" } } })
suite.check("a node has no worth tooltip", #GameTooltip._lines == 0)

--------------------------------------------------------------------------------
-- Without Tradeskills
--------------------------------------------------------------------------------

_G.BlackthornesTS = nil

worth, details = Value:ForMob(WOLF)
suite.check("without Tradeskills, vendor prices still value it", worth ~= nil)
suite.check("and it says so", Value:PriceNote(details) == "vendor prices", Value:PriceNote(details))

mark = #env.chat
ns.HandleSlash("value mangy")
said = table.concat(env.chat, "\n", mark + 1)
suite.check("/farm value says no auction prices are loaded",
    said:find("No auction prices are loaded", 1, true) ~= nil, said)

InstallTradeskills()

-- A price this client will not let us read costs that item, not the value.
_G.BlackthornesTS.Prices.GetValue = function() return env.Secret("price") end
local ok, err = pcall(Value.ForMob, Value, WOLF)
suite.check("a secret price does not raise", ok, err)
InstallTradeskills()

-- Tradeskills erroring is the same.
_G.BlackthornesTS.Prices.GetValue = function() error("scan in progress") end
ok, err = pcall(Value.ForMob, Value, WOLF)
suite.check("Tradeskills erroring does not raise", ok, err)
InstallTradeskills()

--------------------------------------------------------------------------------
-- From the database
--------------------------------------------------------------------------------

ns.DB:RegisterItem({ name = "Ogre Tooth", id = 99001, category = "misc",
    sources = { { name = "Test Ogre", zone = "Nowhere", minLevel = 30, chance = 40 } } })
AUCTION[99001] = 200

worth, details = Value:ForMob("Test Ogre")
suite.check("with no tally, the database's rates give an estimate", worth == 80, worth)
suite.check("marked as the database's", details and details.basis == "database")
suite.check("and the note says so", Value:PriceNote(details):find("database rates", 1, true) ~= nil)

suite.check("a mob with no rates has no value", Value:ForMob("Nobody At All") == nil)

--------------------------------------------------------------------------------
-- Grey items: vendor price only (2026-09-25)
--------------------------------------------------------------------------------

-- Rabbit Foot, say: a grey the auction house somehow shows at 5s.
local unit, from = Value:UnitPrice(3300)
suite.check("a grey item never takes the auction price", unit == 20 and from == "vendor", unit)

unit = Value:UnitPrice(3301)
suite.check("a grey item a vendor will not buy has no price", unit == nil, unit)

-- Not cached yet, but its loot link was grey. The looks are indexed once
-- per change, so a look noted later is counted (NoteLook counts them).
UNCACHED[3302] = true
Tracker:Looks()["Grey Thing"] = { id = 3302, color = Tracker.QUALITY[0] }
Tracker.looksVersion = (Tracker.looksVersion or 0) + 1
unit = Value:UnitPrice(3302)
suite.check("an uncached item with a grey link is not priced at auction", unit == nil, unit)

UNCACHED[3303] = true
AUCTION[3303] = 500
Tracker:Looks()["White Thing"] = { id = 3303, color = Tracker.QUALITY[1] }
Tracker.looksVersion = Tracker.looksVersion + 1
unit = Value:UnitPrice(3303)
suite.check("an uncached white item still takes the auction price", unit == 500, unit)
UNCACHED[3302], UNCACHED[3303] = nil, nil

-- A quality this client will not let us read costs nothing but the check.
local realInfo = C_Item.GetItemInfo
C_Item.GetItemInfo = function() return "item", nil, env.Secret("quality") end
local ok2, err2 = pcall(Value.UnitPrice, Value, 5637)
suite.check("a secret quality does not raise", ok2, err2)
C_Item.GetItemInfo = realInfo

--------------------------------------------------------------------------------
-- A tally from before amounts were kept
--------------------------------------------------------------------------------

Tracker:Store()[WOLF].qty = nil
Tracker:Store()[WOLF].copper = nil

worth = Value:ForMob(WOLF)
-- 21 kills now (the skinned corpse once); fang on 5 at 50c, scraps on 20,
-- valued one per corpse at 5c
local expected = 5 / 21 * 50 + 20 / 21 * 5
suite.check("an old tally is valued one per corpse, no coin",
    worth and math.abs(worth - expected) < 1e-9, worth)

--------------------------------------------------------------------------------
-- A mob typed in any case
--------------------------------------------------------------------------------

suite.check("a mob you have killed resolves from your tally",
    Value:ResolveMob("mangy wolf") == WOLF, Value:ResolveMob("mangy wolf"))
suite.check("a mob only the database knows resolves in its own spelling",
    Value:ResolveMob("defias trapper") == "Defias Trapper", Value:ResolveMob("defias trapper"))
suite.check("a start of a name resolves too",
    Value:ResolveMob("defias trap") == "Defias Trapper", Value:ResolveMob("defias trap"))
suite.check("a name nobody knows resolves to nothing", Value:ResolveMob("zzz nobody") == nil)

-- A kill of yours whose name only starts with what was typed does not hide
-- the database's mob of exactly that name.
Loot("Defias Trapper Scout", { COINS })
suite.check("an exact database name beats a prefix of your own kill",
    Value:ResolveMob("defias trapper") == "Defias Trapper", Value:ResolveMob("defias trapper"))
suite.check("and the prefix still finds your kill",
    Value:ResolveMob("defias trapper s") == "Defias Trapper Scout", Value:ResolveMob("defias trapper s"))

--------------------------------------------------------------------------------
-- The tooltip's sell price wins (2026-10-03)
--------------------------------------------------------------------------------

-- Greater Magic Wand: item info says Classic's 15s 35c, the tooltip 1c.
VENDOR[11288] = 1535
_G.C_TooltipInfo = {
    GetItemByID = function(id)
        local lines = { { type = 0, leftText = "item" } }
        if id == 11288 then lines[#lines + 1] = { type = 11, price = 1 } end
        return { id = id, lines = lines }
    end,
}
suite.check("the tooltip's sell price wins over the item info's", Value:VendorPrice(11288) == 1, Value:VendorPrice(11288))
suite.check("an item whose tooltip shows none keeps the item info's", Value:VendorPrice(3300) == 20, Value:VendorPrice(3300))
_G.C_TooltipInfo = nil
VENDOR[11288] = nil

-- A tooltip read before the item loaded shows no price; that must not stick
-- for the session once the item has loaded and its tooltip does.
VENDOR[11289] = 900
local loaded = false
local baseItem = _G.C_Item
_G.C_Item = setmetatable({ IsItemDataCachedByID = function() return loaded end }, { __index = baseItem })
_G.C_TooltipInfo = {
    GetItemByID = function(id)
        if not loaded then return { id = id, lines = { { type = 0, leftText = "Retrieving item information" } } } end
        return { id = id, lines = { { type = 0, leftText = "item" }, { type = 11, price = 5 } } }
    end,
}
suite.check("before it loads, the item info's price stands in", Value:VendorPrice(11289) == 900, Value:VendorPrice(11289))
loaded = true
-- The client says when the item has arrived; until then the tooltip is
-- not asked for again (a board prices hundreds of items a draw).
Value:ItemArrived(11289)  -- what GET_ITEM_INFO_RECEIVED calls
suite.check("once loaded, the tooltip's price is read after all", Value:VendorPrice(11289) == 5, Value:VendorPrice(11289))
_G.C_TooltipInfo, _G.C_Item = nil, baseItem
VENDOR[11289] = nil

suite.done()
