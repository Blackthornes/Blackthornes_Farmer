-- What a clam or a sack is worth: what came out of it.
--
-- What matters: a clam opened fewer than MIN_OPENS times keeps its own
-- price; from then on it is worth its average contents when that pays
-- more, and the mob that drops it is worth more a kill to match; hidden
-- items are left out; the loot table's tooltip says what is inside, or how
-- many more to open.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("containerworth")

local ns = env.Load({ ui = true })
local Value, Tracker, Containers = ns.Value, ns.Tracker, ns.Containers

local CLAM = { name = "Thick-shelled Clam", id = 5524 }
local PEARL = { name = "Iridescent Pearl", id = 5500 }
local MEAT = { name = "Tangy Clam Meat", id = 5504 }

-- A clam sells for 1c; a pearl is worth 900c, meat 10c.
local VENDOR = { [5524] = 1, [5504] = 10 }
_G.C_Item = {
    GetItemInfo = function(id)
        return "item", nil, 1, 1, 1, "", "", 1, "", "", VENDOR[id] or 0
    end,
}
_G.BlackthornesTS = { Prices = { GetValue = function(_, id) return id == 5500 and 900 or nil end } }

local serial = 0
local function Loot(mob, items)
    serial = serial + 1
    env.world.target = { name = mob, level = 30, dead = true, guid = "C-" .. serial }
    env.world.loot = items
    Tracker:OnLoot()
end

-- 20 kills, a clam off half of them.
for index = 1, 20 do Loot("Saltspittle Oracle", { index % 2 == 0 and CLAM or nil }) end

local opened = 0
local function Open(times)
    for _ = 1, times do
        opened = opened + 1
        local index = opened
        -- Meat every time, two once in a while; a pearl one in ten.
        local items = { MEAT.name }
        local quantities = { [MEAT.name] = index % 4 == 0 and 2 or 1 }
        if index % 10 == 0 then items[2] = PEARL.name end
        Containers:Record(CLAM.name, CLAM.id, items, quantities)
    end
    local entry = Containers:Store()[CLAM.name]
    entry.items[MEAT.name].id = MEAT.id
    if entry.items[PEARL.name] then entry.items[PEARL.name].id = PEARL.id end
end

--------------------------------------------------------------------------------
-- Too few opened: the clam's own price
--------------------------------------------------------------------------------

Open(19)
suite.check("19 opened says nothing about what's inside", Value:Contents(CLAM.name) == nil)
local unit, from = Value:WorthOf(CLAM.name, CLAM.id)
suite.check("19 opened: the clam's own price", unit == 1 and from == "vendor", tostring(unit) .. " " .. tostring(from))

local lines = ns.LootTableUI:ContentsLines(CLAM.name)
suite.check("tooltip says how many opened so far",
    lines[2] and lines[2][1]:find("19 of 20", 1, true) ~= nil, lines[2] and lines[2][1])
suite.check("nothing for an item never opened", #ns.LootTableUI:ContentsLines(MEAT.name) == 0)

local before = Value:FromTally("Saltspittle Oracle")

--------------------------------------------------------------------------------
-- Enough opened: worth what's inside
--------------------------------------------------------------------------------

Open(1)
local worth, details = Value:Contents(CLAM.name)
-- 20 opens: 25 meat (10c) and 2 pearls (900c) = 250 + 1800 = 2050 / 20.
suite.check("20 opened: the average opening", worth and math.abs(worth - 102.5) < 0.01, tostring(worth))
suite.check("pearl listed first, at 1 in 10", details and details.priced[1].name == PEARL.name
    and math.abs(details.priced[1].chance - 10) < 0.01)
suite.check("meat counts how many came out", details and math.abs(details.priced[2].each - 1.25) < 0.01)

unit, from = Value:WorthOf(CLAM.name, CLAM.id)
suite.check("the clam is worth its contents", from == "contents" and math.abs(unit - 102.5) < 0.01)

local after, tally = Value:FromTally("Saltspittle Oracle")
suite.check("the mob's worth a kill rises with it",
    before and after and math.abs(after - 102.5 / 2) < 0.01 and after > before,
    tostring(before) .. " -> " .. tostring(after))
suite.check("the drop says where its price came from", tally.priced[1].from == "contents")

local table_ = ns.LootTableUI:Table("Saltspittle Oracle")
suite.check("the loot table's per kill counts the contents",
    table_ and math.abs(table_.rows[1].perKill - 102.5 / 2) < 0.01)

lines = ns.LootTableUI:ContentsLines(CLAM.name)
suite.check("tooltip heads with what it opens to",
    lines[2] and lines[2][1]:find("Opens to (20 opened)", 1, true) ~= nil, lines[2] and lines[2][1])
suite.check("tooltip lists the pearl", lines[3] and lines[3][1]:find(PEARL.name, 1, true) ~= nil)
suite.check("tooltip says how many each time", lines[4] and lines[4][1]:find("1.2 each", 1, true) ~= nil,
    lines[4] and lines[4][1])

--------------------------------------------------------------------------------
-- Hidden items, and a clam that sells for more than it holds
--------------------------------------------------------------------------------

ns.DB:Hide("item", PEARL.name)
worth = Value:Contents(CLAM.name)
suite.check("a hidden item is left out", worth and math.abs(worth - 12.5) < 0.01, tostring(worth))
ns.DB:Unhide("item", PEARL.name)

VENDOR[5524] = 5000
unit, from = Value:WorthOf(CLAM.name, CLAM.id)
suite.check("a vendor that pays more wins", unit == 5000 and from == "vendor", tostring(unit) .. " " .. tostring(from))
VENDOR[5524] = 1

--------------------------------------------------------------------------------
-- The session haul (the Loot tab, gold per hour) counts what's inside too
--------------------------------------------------------------------------------

local savedLoot, savedCopper = Tracker.sessionLoot, Tracker.sessionCopper
Tracker.sessionLoot, Tracker.sessionCopper = { [CLAM.name] = 2 }, 0
local sessionWorth = Value:Session()
suite.check("the session counts a clam by what's inside",
    sessionWorth and math.abs(sessionWorth - 205) < 0.01, tostring(sessionWorth))
Tracker.sessionLoot, Tracker.sessionCopper = savedLoot, savedCopper

_G.BlackthornesTS = nil
_G.C_Item = nil
suite.done()
