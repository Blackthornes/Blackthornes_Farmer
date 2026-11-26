-- Switching tabs does less work, and shows the same thing.
--
-- Trent felt a hitch on each tab switch (2026-11-25). Rankings priced the
-- same item once for every mob that drops it and walked every database row
-- of every mob again; the Grind tab sorted every mob spot again; the empty
-- Search tab walked every spot for its "Good at level" picks. Each is now
-- kept until what it is built from moves. These checks prove the kept
-- answers are the same as the long way, and that a change still shows.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("tabswitch")

local ns = env.Load({ ui = true })
local DB, Value, Rankings, Grinding, Search = ns.DB, ns.Value, ns.Rankings, ns.Grinding, ns.Search

-- Prices from a table we control, counted.
local price, asked = {}, 0
Value.IsPoor = function() return false, true end
Value.VendorPrice = function() return nil end
Value.AuctionPrice = function(_, id)
    asked = asked + 1
    return price[id]
end

DB:RegisterItem({ name = "Tab Test Fang", id = 991001, category = "Leather",
    sources = {
        { kind = "mob", name = "Tab Test Wolf", zone = "Elwynn Forest", minLevel = 5, maxLevel = 6, chance = 40 },
        { kind = "mob", name = "Tab Test Bear", zone = "Elwynn Forest", minLevel = 7, maxLevel = 8, chance = 20 },
    } })
DB:RegisterItem({ name = "Tab Test Pelt", id = 991002, category = "Leather",
    sources = { { kind = "mob", name = "Tab Test Wolf", zone = "Elwynn Forest", minLevel = 5, maxLevel = 6, chance = 10 } } })
price[991001], price[991002] = 1000, 500

--------------------------------------------------------------------------------
-- Rankings: one price a item a draw, and the same board
--------------------------------------------------------------------------------

local function Flat(board)
    local parts = {}
    for _, group in ipairs({ "measured", "estimate", "pending" }) do
        for _, entry in ipairs(board[group]) do
            parts[#parts + 1] = ("%s:%s:%s:%s:%s"):format(group, entry.mob, tostring(entry.value),
                tostring(entry.rank), tostring(entry.level))
        end
    end
    return table.concat(parts, "\n")
end

asked = 0
local board = Rankings:Build()
local onePass = asked
local items = {}
for name, sources in pairs(DB:ByName()) do
    for _, source in ipairs(sources) do
        local item = DB:ItemOf(source)
        if item and source.chance then items[item.id or item.name] = true end
    end
end
local unique = 0
for _ in pairs(items) do unique = unique + 1 end
suite.check("each item is priced at most once a board", onePass <= unique, onePass .. " vs " .. unique)
suite.check("the pass ends with the board", Value.pass == nil)

-- The long way: nothing kept, no pass.
local function LongWay()
    Rankings.spots, Value.ratedRows = nil, nil
    return Rankings:BuildNow()
end
suite.check("the kept board is the long way's", Flat(board) == Flat(LongWay()))

local wolf
for _, entry in ipairs(board.estimate) do if entry.mob == "Tab Test Wolf" then wolf = entry end end
suite.check("the wolf is worth both drops", wolf and wolf.value == 0.4 * 1000 + 0.1 * 500, wolf and wolf.value)

-- A price that moves shows at the next draw: no price is kept between draws.
price[991001] = 2000
for _, entry in ipairs(Rankings:Build().estimate) do if entry.mob == "Tab Test Wolf" then wolf = entry end end
suite.check("a new price shows on the next board", wolf.value == 0.4 * 2000 + 0.1 * 500, wolf.value)

-- A source added later shows, in the worth and the spot.
DB:RegisterItem({ name = "Tab Test Claw", id = 991003, category = "Leather",
    sources = { { kind = "mob", name = "Tab Test Wolf", zone = "Elwynn Forest", minLevel = 4, maxLevel = 6, chance = 50 } } })
price[991003] = 100
for _, entry in ipairs(Rankings:Build().estimate) do if entry.mob == "Tab Test Wolf" then wolf = entry end end
suite.check("a drop added later counts", wolf.value == 0.4 * 2000 + 0.1 * 500 + 0.5 * 100, wolf.value)
suite.check("and its lower level is the wolf's spot", Rankings:Spot("Tab Test Wolf").minLevel == 4)

-- The hide list moves: the hidden item drops out of the worth.
DB:Hide("item", "Tab Test Claw")
for _, entry in ipairs(Rankings:Build().estimate) do if entry.mob == "Tab Test Wolf" then wolf = entry end end
suite.check("a hidden drop no longer counts", wolf.value == 0.4 * 2000 + 0.1 * 500, wolf.value)
DB:Unhide("item", "Tab Test Claw")
suite.check("and counts again once shown", Value:FromDatabase("Tab Test Wolf") == 0.4 * 2000 + 0.1 * 500 + 0.5 * 100)
suite.check("the board still matches the long way", Flat(Rankings:Build()) == Flat(LongWay()))

-- An error inside the board still ends the pass, or prices would freeze.
local entry = Rankings.Entry
Rankings.Entry = function() error("test boom") end
local ok = pcall(Rankings.Build, Rankings)
Rankings.Entry = entry
suite.check("an error is passed on", not ok)
suite.check("and the pass is ended anyway", Value.pass == nil)

-- A pass inside a pass is the outer one's.
suite.check("a pass opens", Value:BeginPass() == true)
Rankings:Build()
suite.check("the board leaves an outer pass open", Value.pass ~= nil)
Value:EndPass()

--------------------------------------------------------------------------------
-- Grind: the mob list is sorted once
--------------------------------------------------------------------------------

local sorted = Grinding:SortedMobs()
suite.check("the sorted list is kept between calls", Grinding:SortedMobs() == sorted)
local inOrder = true
for index = 2, #sorted do
    local a, b = sorted[index - 1], sorted[index]
    if a.zone > b.zone or (a.zone == b.zone and (a.location or "") > (b.location or "")) then inOrder = false end
end
suite.check("and it is in zone and place order", inOrder)
local camps = Grinding:Camps({ low = 1, high = 60 })
suite.check("the camps are the same drawn twice", #Grinding:Camps({ low = 1, high = 60 }) == #camps)
DB:RegisterItem({ name = "Tab Test Ear", id = 991004, category = "Cloth",
    sources = { { kind = "mob", name = "Tab Test Kobold", zone = "Elwynn Forest", minLevel = 3, maxLevel = 4, chance = 30 } } })
suite.check("a new spot sorts the list again", Grinding:SortedMobs() ~= sorted)
local kobold = false
for _, mob in ipairs(Grinding:SortedMobs()) do if mob.name == "Tab Test Kobold" then kobold = true end end
suite.check("and the new mob is in it", kobold)

--------------------------------------------------------------------------------
-- Counting spots
--------------------------------------------------------------------------------

local function Counted()
    local total = 0
    for _, key in ipairs(DB.order) do total = total + #DB.items[key].sources end
    return total
end
suite.check("the spot count is right", DB:CountSources() == Counted())
DB:RegisterItem({ name = "Tab Test Tail", id = 991005, category = "Cloth",
    sources = { { kind = "mob", name = "Tab Test Kobold", zone = "Elwynn Forest", minLevel = 3, chance = 5 } } })
suite.check("and right after a spot is added", DB:CountSources() == Counted())

--------------------------------------------------------------------------------
-- The empty Search tab's picks
--------------------------------------------------------------------------------

ns.Spots.Skills = function() return nil end
local picks = Search:ForLevel(5)
suite.check("the picks are kept for the same level", Search:ForLevel(5) == picks)
local function Names(list)
    local names = {}
    for _, item in ipairs(list) do names[#names + 1] = item.name end
    return table.concat(names, ",")
end
suite.check("and are the long way's", Names(picks) == Names(Search:ForLevelNow(5, nil)))
suite.check("another level works them out again", Search:ForLevel(30) ~= picks)
local before = Search:ForLevel(5)
DB:Hide("item", "Tab Test Fang")
suite.check("a hide works them out again", Search:ForLevel(5) ~= before)
DB:Unhide("item", "Tab Test Fang")
suite.check("skills given are never kept", Search:ForLevel(5, {}) ~= Search:ForLevel(5, {}))

--------------------------------------------------------------------------------
-- A tab switch: one pass, ended
--------------------------------------------------------------------------------

local UI = ns.UI
UI:Build()
UI:Show()
asked = 0
UI:ShowTab("rankings")
suite.check("a switch prices each item at most once", asked <= unique + 3, asked)
suite.check("and ends its pass", Value.pass == nil)
UI:ShowTab("grind")
UI:ShowTab("search")
suite.check("every switch ends its pass", Value.pass == nil)

suite.done()
