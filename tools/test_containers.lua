-- Containers: clams and the like.
--
-- What matters: a clam opened from the bags is counted against the clam,
-- never as a drop of the corpse still targeted; only an item the client
-- says holds loot, and only a window that opens soon after; a corpse the
-- client names is still the corpse's; a Giant Clam in the world goes in the
-- gathering record where it is, only when its name is known; the pause
-- stops it; and Where? lists the places a clam drops for what was inside.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("containers")

local clock = 1000
local ns = env.Load({ ui = true })
local Containers, Tracker, Harvest = ns.Containers, ns.Tracker, ns.Harvest

_G.GetTime = function() return clock end

-- The bags: slot 1 a clam, slot 2 a potion.
local SLOTS = {
    [1] = { itemID = 5524, hyperlink = "|cffffffff|Hitem:5524::|h[Thick-shelled Clam]|h|r", hasLoot = true },
    [2] = { itemID = 118, hyperlink = "|cffffffff|Hitem:118::|h[Minor Healing Potion]|h|r", hasLoot = false },
}
_G.C_Container = {
    GetContainerItemInfo = function(_, slot) return SLOTS[slot] end,
    UseContainerItem = function() end,
}
_G.hooksecurefunc = function(target, name, fn)
    if type(target) == "string" then target, name, fn = _G, target, name end
    local original = target[name]
    target[name] = function(...)
        local result = original(...)
        fn(...)
        return result
    end
end

Harvest:OnEnable()
Tracker:OnEnable()
ns.Fishing:OnEnable()
ns.Gathering:OnEnable()
Containers:OnEnable()

local fire = ns.eventFrame:GetScript("OnEvent")

local PEARL = { name = "Iridescent Pearl", id = 5500 }
local MEAT = { name = "Tangy Clam Meat", id = 5504 }
local CLAM = { name = "Thick-shelled Clam", id = 5524 }

local function Open(items)
    env.world.loot = items
    fire(ns.eventFrame, "LOOT_OPENED")
    fire(ns.eventFrame, "LOOT_CLOSED")
end

local function TallyItem(mob, item)
    local tally = ns.db.tracker and ns.db.tracker.mobs[mob]
    return tally and tally.items[item]
end

local function HarvestItem(mob, item)
    for _, record in pairs(Harvest.records) do
        if record.mob == mob and record.items[item] then return record.items[item] end
    end
end

env.world.zone, env.world.subZone = "Wetlands", "Bluegill Marsh"

-- A murloc killed and looted: it dropped a clam. Its corpse stays targeted.
env.world.target = { name = "Bluegill Murloc", level = 21, dead = true, guid = "Creature-0-1-2-3-1024-1" }
Open({ CLAM })
suite.check("the murloc is a kill", Tracker:Store()["Bluegill Murloc"].kills == 1)

-- The clam opened from the bags, the corpse still targeted.
C_Container.UseContainerItem(0, 1)
clock = clock + 1
Open({ PEARL, MEAT })

local clam = Containers:Store()["Thick-shelled Clam"]
suite.check("the clam opened is counted", clam and clam.opens == 1, clam and clam.opens)
suite.check("with its item id", clam and clam.id == 5524)
suite.check("what it held is counted", clam and clam.items["Iridescent Pearl"].opens == 1)
suite.check("and the meat", clam and clam.items["Tangy Clam Meat"].count == 1)
suite.check("the pearl is not the murloc's drop", TallyItem("Bluegill Murloc", "Iridescent Pearl") == nil)
suite.check("nor in the harvest", HarvestItem("Bluegill Murloc", "Iridescent Pearl") == nil)
suite.check("nor another kill", Tracker:Store()["Bluegill Murloc"].kills == 1)

-- A potion is no container: the corpse looted next is the corpse's.
env.world.target = { name = "Bluegill Murloc", level = 21, dead = true, guid = "Creature-0-1-2-3-1024-2" }
C_Container.UseContainerItem(0, 2)
Open({ CLAM })
suite.check("a potion drunk, then a corpse: a kill", Tracker:Store()["Bluegill Murloc"].kills == 2)
suite.check("not an opening", Containers:Store()["Minor Healing Potion"] == nil)

-- A clam clicked, then a corpse looted later: the corpse's.
C_Container.UseContainerItem(0, 1)
clock = clock + Containers.OPEN_SECONDS + 2
env.world.target = { name = "Bluegill Murloc", level = 21, dead = true, guid = "Creature-0-1-2-3-1024-3" }
Open({ CLAM })
suite.check("a stale click does not claim a corpse", Tracker:Store()["Bluegill Murloc"].kills == 3)
suite.check("the clam count stays", Containers:Store()["Thick-shelled Clam"].opens == 1)

-- A clam clicked, but the client says the window is a corpse's.
C_Container.UseContainerItem(0, 1)
_G.GetLootSourceInfo = function(slot) if slot == 1 then return "Creature-0-1-2-3-1024-4", 1 end end
env.world.target = { name = "Bluegill Murloc", level = 21, dead = true, guid = "Creature-0-1-2-3-1024-4" }
Open({ CLAM })
suite.check("a corpse the client names stays the corpse's", Tracker:Store()["Bluegill Murloc"].kills == 4)
suite.check("and is no opening", Containers:Store()["Thick-shelled Clam"].opens == 1)
_G.GetLootSourceInfo = nil
clock = clock + 10

--------------------------------------------------------------------------------
-- A clam opened with no click seen
--------------------------------------------------------------------------------

-- The game's bag button need not go through the call we watch. The loot
-- window still names the clam by its item guid, found in the bags.
local GUIDS = { [1] = "Item-4620-0-4000000AB12", [2] = "Item-4620-0-4000000AB13" }
local realCItem, realLocation = _G.C_Item, _G.ItemLocation
_G.C_Item = { GetItemGUID = function(location) return GUIDS[location.slot] end }
_G.ItemLocation = { CreateFromBagAndSlot = function(_, bag, slot)
    return bag == 0 and { bag = bag, slot = slot } or {}
end }
C_Container.GetContainerNumSlots = function(bag) return bag == 0 and 2 or 0 end

env.world.target = { name = "Bluegill Murloc", level = 21, dead = true, guid = "Creature-0-1-2-3-1024-5" }
Open({ CLAM })
local kills = Tracker:Store()["Bluegill Murloc"].kills
_G.GetLootSourceInfo = function(slot) if slot <= 2 then return GUIDS[1], 1 end end
Open({ PEARL, MEAT })
suite.check("no click: the window's item source is the clam",
    Containers:Store()["Thick-shelled Clam"].opens == 2, Containers:Store()["Thick-shelled Clam"].opens)
suite.check("no click: the pearl is not the murloc's", TallyItem("Bluegill Murloc", "Iridescent Pearl") == nil)
suite.check("no click: no kill", Tracker:Store()["Bluegill Murloc"].kills == kills)

-- The same stack opened again: one more.
Open({ MEAT })
suite.check("the same stack again is one more", Containers:Store()["Thick-shelled Clam"].opens == 3)

-- An item guid nothing in the bags carries is never guessed.
_G.GetLootSourceInfo = function(slot) if slot == 1 then return "Item-4620-0-4000000FFFF", 1 end end
Open({ MEAT })
suite.check("an item not in the bags is not guessed", Containers:Store()["Thick-shelled Clam"].opens == 3)

-- A client that won't say whether the clam holds loot: the click counts
-- when the window names an item, and never claims a corpse.
SLOTS[1].hasLoot = nil
-- (Its guid is one the bags don't show, so only the click can name it.)
_G.GetLootSourceInfo = function(slot) if slot <= 2 then return "Item-4620-0-4000000CCCC", 1 end end
C_Container.UseContainerItem(0, 1)
Open({ PEARL, MEAT })
suite.check("unsure click with an item source counts", Containers:Store()["Thick-shelled Clam"].opens == 4, tostring(Containers:Store()["Thick-shelled Clam"].opens) .. " " .. tostring(Containers:Store()["Minor Healing Potion"]))

_G.GetLootSourceInfo = nil
env.world.target = { name = "Bluegill Murloc", level = 21, dead = true, guid = "Creature-0-1-2-3-1024-6" }
C_Container.UseContainerItem(0, 1)
Open({ CLAM })
suite.check("unsure click does not claim a corpse", Tracker:Store()["Bluegill Murloc"].kills == kills + 1)
suite.check("and is no opening", Containers:Store()["Thick-shelled Clam"].opens == 4)
SLOTS[1].hasLoot = true

_G.C_Item, _G.ItemLocation = realCItem, realLocation
C_Container.GetContainerNumSlots = nil
clock = clock + 10

--------------------------------------------------------------------------------
-- A Giant Clam underwater
--------------------------------------------------------------------------------

local realGUID, realName = _G.UnitGUID, _G.UnitName
local soft = nil
_G.UnitGUID = function(unit)
    if unit == "softinteract" then return soft and soft.guid end
    return realGUID(unit)
end
_G.UnitName = function(unit)
    if unit == "softinteract" then return soft and soft.name end
    return realName(unit)
end

env.world.target = nil
_G.GetLootSourceInfo = function(slot) if slot == 1 then return "GameObject-0-1-2-3-19018-9", 1 end end

-- No name to give it: nothing recorded.
Open({ PEARL })
suite.check("an object with no name is not recorded", ns.Gathering:CountGathers() == 0, ns.Gathering:CountGathers())

soft = { guid = "GameObject-0-1-2-3-19018-9", name = "Giant Clam" }
Open({ PEARL })
local key = ns.Gathering.NodeKey("Wetlands", "Bluegill Marsh", "Giant Clam")
local node = ns.db.gathering.nodes[key]
suite.check("a Giant Clam opened goes in the gathering record", node and node.gathers == 1)
suite.check("as a container", node and node.kind == "container", node and node.kind)
suite.check("with what it held", node and node.items["Iridescent Pearl"].gathers == 1)
suite.check("it is no kill", Tracker:Store()["Giant Clam"] == nil)

-- Paused: nothing.
ns.db.harvestPaused = true
Open({ PEARL })
suite.check("the pause stops it", ns.db.gathering.nodes[key].gathers == 1)
ns.db.harvestPaused = nil
soft = nil
_G.GetLootSourceInfo = nil
_G.UnitGUID, _G.UnitName = realGUID, realName

--------------------------------------------------------------------------------
-- Where?
--------------------------------------------------------------------------------

local spots = ns.Spots:Candidates("Iridescent Pearl")
local inClam, giant
for _, spot in ipairs(spots) do
    if spot.name == "Thick-shelled Clam" and spot.zone == "Wetlands" then inClam = spot end
    if spot.name == "Giant Clam" and spot.zone == "Wetlands" and spot.yours then giant = spot end
end
suite.check("Where? lists the clam's place in Wetlands", inClam ~= nil)
suite.check("with what you found inside", inClam and inClam.yours and inClam.yours.opens == 4)
suite.check("which the note says",
    inClam and ns.GoalsUI.SpotNote(inClam):find("in 3 of the 4 you opened", 1, true) ~= nil,
    inClam and ns.GoalsUI.SpotNote(inClam))
suite.check("and the Giant Clam you opened there", giant ~= nil)
suite.check("whose note says so",
    giant and ns.GoalsUI.SpotNote(giant):find("1 from the 1 you opened here", 1, true) ~= nil,
    giant and ns.GoalsUI.SpotNote(giant))

suite.done()
