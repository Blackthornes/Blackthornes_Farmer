-- Blackthornes Butler's one question (2026-10-10): does a goal of the
-- character playing need this item, and how many more?
--
-- What matters: Butler:Advise(itemID) answers { goal, have, target, need }
-- for this character's goal, by item ID or through the name the client
-- gives the ID; another character's goal is nil, one saved before goals had
-- owners counts; no goal is nil; a goal set, changed or taken off is seen at
-- once; the lookup is not built again while nothing changed; and an error
-- anywhere is nil, never raised.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("butler")

local ns = env.Load()
local Goals = ns.Goals
local Butler = ns.Butler

-- The bags: item ID or name -> count.
local bags = {}
local names = { [2770] = "Copper Ore", [2589] = "Linen Cloth", [99001] = "Odd Rock" }
local infoAsked = 0
_G.C_Item = {
    GetItemCount = function(item) return bags[item] or 0 end,
    GetItemInfo = function(itemID)
        infoAsked = infoAsked + 1
        return names[itemID]
    end,
}

local COPPER, LINEN, ODD = 2770, 2589, 99001

suite.check("the global answers Butler", _G.BlackthornesFarmer.Butler == Butler)
suite.check("no goals, no answer", Butler:Advise(COPPER) == nil)

--------------------------------------------------------------------------------
-- A goal of this character
--------------------------------------------------------------------------------

bags[COPPER] = 6
local goal = Goals:Set("Copper Ore", 40)
suite.check("goal set", goal and goal.owner == "Blackthornes", goal and goal.owner)

local answer = Butler:Advise(COPPER)
suite.check("found by item ID", answer ~= nil)
suite.check("goal is the item's name", answer.goal == "Copper Ore", answer.goal)
suite.check("have", answer.have == 6, answer.have)
suite.check("target", answer.target == 40, answer.target)
suite.check("need", answer.need == 34, answer.need)

bags[COPPER] = 15
suite.check("have read fresh from the bags", Butler:Advise(COPPER).need == 25)
bags[COPPER] = 55
suite.check("need is never below 0", Butler:Advise(COPPER).need == 0)
bags[COPPER] = 6

suite.check("another item, no answer", Butler:Advise(LINEN) == nil)
suite.check("an item ID as a string still reads", Butler:Advise("2770") ~= nil)
suite.check("nonsense is nil", Butler:Advise(nil) == nil and Butler:Advise({}) == nil)

-- A goal the database does not know is matched through the client's name.
bags[ODD] = 1
Goals:Set("Odd Rock", 5)
answer = Butler:Advise(ODD)
suite.check("found by the name the client gives", answer and answer.goal == "Odd Rock" and answer.need == 4,
    answer and answer.need)

--------------------------------------------------------------------------------
-- Kept, not rebuilt, while nothing changed
--------------------------------------------------------------------------------

local lookup = Butler:Lookup()
for _ = 1, 100 do Butler:Advise(LINEN) end
suite.check("the lookup is kept across a burst", Butler:Lookup() == lookup)
infoAsked = 0
for _ = 1, 100 do Butler:Advise(ODD) end
suite.check("a name the client gave is kept", infoAsked == 0, infoAsked)

--------------------------------------------------------------------------------
-- Goal changes are seen
--------------------------------------------------------------------------------

Goals:Set("Copper Ore", 80)
suite.check("a changed target is seen", Butler:Advise(COPPER).target == 80)
suite.check("the lookup was built again", Butler:Lookup() ~= lookup)

Goals:Remove("Odd Rock")
suite.check("a removed goal is gone", Butler:Advise(ODD) == nil)

Goals:Set("Linen Cloth", 20)
suite.check("a new goal is seen", Butler:Advise(LINEN) and Butler:Advise(LINEN).need == 20)
Goals:Remove("Linen Cloth")

--------------------------------------------------------------------------------
-- Whose goal
--------------------------------------------------------------------------------

local list = Goals:Store().list
list[#list + 1] = { item = "Linen Cloth", owner = "Bankalt-Forever", target = 30, have = 2 }
suite.check("another character's goal is nil", Butler:Advise(LINEN) == nil)

-- As saved data loads at login: the list is only ever changed through
-- Goals, so a goal laid in by hand here is a new item.
list[#list + 1] = { item = "Odd Rock", target = 30, have = 2 }
bags[ODD] = 3
answer = Butler:Advise(ODD)
suite.check("a goal saved before owners counts", answer and answer.target == 30 and answer.have == 3,
    answer and answer.have)
suite.check("and its need", answer and answer.need == 27)

-- Another character logs in: the copper goal is not theirs.
local realUnitName = _G.UnitName
_G.UnitName = function(unit)
    if unit == "player" then return "Bankalt" end
    return realUnitName(unit)
end
Goals.me = nil
suite.check("the main's goal is not the alt's", Butler:Advise(COPPER) == nil)
suite.check("the old goal still counts on the alt", Butler:Advise(ODD) ~= nil)
_G.UnitName = realUnitName
Goals.me = nil
suite.check("back on the main", Butler:Advise(COPPER) ~= nil)

--------------------------------------------------------------------------------
-- Never raises
--------------------------------------------------------------------------------

_G.C_Item.GetItemCount = function() error("client broke") end
answer = Butler:Advise(COPPER)
suite.check("a count the client will not give falls back to the saved one",
    answer and answer.have == 6, answer and answer.have)

_G.C_Item.GetItemInfo = function() return env.Secret("name") end
Butler.names = {}
suite.check("a secret name is nil", Butler:Advise(ODD) == nil)
Butler.names[ODD] = "Odd Rock"

local realStore = Goals.Store
Goals.Store = function() error("saved data broke") end
local ok, result = pcall(Butler.Advise, Butler, COPPER)
suite.check("an error inside is nil, not raised", ok and result == nil)
Goals.Store = realStore

suite.check("nothing written by asking", #Goals:Store().list == 3)

suite.done()
