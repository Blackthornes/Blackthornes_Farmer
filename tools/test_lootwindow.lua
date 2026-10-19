-- Tests for ns.OnLootWindow: each loot window is read once, and a client
-- without LOOT_CLOSED still has every window read, not only the first.
-- Fast looting (2026-10-19): the loot events are asked for as Farmer loads,
-- so Farmer reads ahead of addons that ask at login or later, and a window
-- LOOT_READY finds empty is read again on LOOT_OPENED.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("lootwindow")

local function Reader(ns)
    local reads, seen = 0, {}
    ns.OnLootWindow({}, function()
        reads = reads + 1
        seen[#seen + 1] = GetNumLootItems()
    end)
    return function() return reads end, seen
end

local FANG = { name = "Large Fang", id = 5637 }

-- 1. The usual client: LOOT_READY reads, LOOT_OPENED of the same window
-- does not, LOOT_CLOSED ends it.
do
    local ns = env.Load()
    local reads = Reader(ns)
    local fire = ns.eventFrame:GetScript("OnEvent")

    for _ = 1, 3 do
        env.world.loot = { FANG }
        fire(ns.eventFrame, "LOOT_READY")
        fire(ns.eventFrame, "LOOT_OPENED")
        fire(ns.eventFrame, "LOOT_CLOSED")
    end
    suite.check("three windows, three reads", reads() == 3, reads())

    fire(ns.eventFrame, "LOOT_OPENED")
    fire(ns.eventFrame, "LOOT_CLOSED")
    suite.check("a window with no LOOT_READY is read on LOOT_OPENED", reads() == 4, reads())
end

-- 2. A client that refuses LOOT_CLOSED: nothing ends a window, so the guard
-- would have read the first one only.
do
    local ns = env.Load({ unknownEvents = { LOOT_CLOSED = true } })
    local reads = Reader(ns)
    local fire = ns.eventFrame:GetScript("OnEvent")

    suite.check("the client really refused LOOT_CLOSED", ns.GetUnknownEvents().LOOT_CLOSED ~= nil)
    for _ = 1, 3 do
        env.world.loot = { FANG }
        fire(ns.eventFrame, "LOOT_READY")
        fire(ns.eventFrame, "LOOT_OPENED")
    end
    suite.check("without LOOT_CLOSED every window is read, once", reads() == 3, reads())

    env.world.loot = {}
    fire(ns.eventFrame, "LOOT_READY")
    suite.check("and there an empty one is still read on LOOT_READY, its only turn", reads() == 4, reads())
end

-- 3. The loot events are asked for as Farmer loads, before any reader (they
-- join at login): the game hands an event out in the order it was asked for.
do
    local ns = env.Load()
    local events = ns.eventFrame._events
    suite.check("LOOT_READY asked for as Farmer loads", events.LOOT_READY == true)
    suite.check("LOOT_OPENED too", events.LOOT_OPENED == true)
    suite.check("LOOT_CLOSED too", events.LOOT_CLOSED == true)

    local fire = ns.eventFrame:GetScript("OnEvent")
    env.world.loot = { FANG }
    fire(ns.eventFrame, "LOOT_READY")
    fire(ns.eventFrame, "LOOT_CLOSED")
    suite.check("with no reader yet, nothing breaks", true)
end

-- 4. LOOT_READY finds the window empty; its slots are there by LOOT_OPENED.
do
    local ns = env.Load()
    local reads, seen = Reader(ns)
    local fire = ns.eventFrame:GetScript("OnEvent")

    env.world.loot = {}
    fire(ns.eventFrame, "LOOT_READY")
    suite.check("an empty LOOT_READY is not taken as read", reads() == 0, reads())
    suite.check("and is noted for the loot check", ns.lootWindows.empty == 1, ns.lootWindows.empty)

    env.world.loot = { FANG }
    fire(ns.eventFrame, "LOOT_OPENED")
    suite.check("LOOT_OPENED reads it, with its slot", reads() == 1 and seen[1] == 1, reads())
    fire(ns.eventFrame, "LOOT_CLOSED")

    -- Emptied for good: LOOT_OPENED still reads it, as it always did.
    env.world.loot = {}
    fire(ns.eventFrame, "LOOT_READY")
    fire(ns.eventFrame, "LOOT_OPENED")
    fire(ns.eventFrame, "LOOT_CLOSED")
    suite.check("a window empty at both is read once, on LOOT_OPENED", reads() == 2, reads())

    -- The next window reads on LOOT_READY again.
    env.world.loot = { FANG }
    fire(ns.eventFrame, "LOOT_READY")
    env.world.loot = {}
    fire(ns.eventFrame, "LOOT_OPENED")
    suite.check("a full LOOT_READY still reads first and once", reads() == 3 and seen[3] == 1, reads())
end

-- 5. A secret slot count is neither empty nor full: read on LOOT_READY as before.
do
    local ns = env.Load()
    local reads = Reader(ns)
    local fire = ns.eventFrame:GetScript("OnEvent")
    local base = GetNumLootItems
    _G.GetNumLootItems = function() return env.Secret("count") end
    fire(ns.eventFrame, "LOOT_READY")
    _G.GetNumLootItems = base
    suite.check("an unreadable count still reads on LOOT_READY", reads() == 1, reads())
end

suite.done()
