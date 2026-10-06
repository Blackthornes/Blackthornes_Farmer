-- Tests for ns.OnLootWindow: each loot window is read once, and a client
-- without LOOT_CLOSED still has every window read, not only the first.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("lootwindow")

local function Reader(ns)
    local reads = 0
    ns.OnLootWindow({}, function() reads = reads + 1 end)
    return function() return reads end
end

-- 1. The usual client: LOOT_READY reads, LOOT_OPENED of the same window
-- does not, LOOT_CLOSED ends it.
do
    local ns = env.Load()
    local reads = Reader(ns)
    local fire = ns.eventFrame:GetScript("OnEvent")

    for _ = 1, 3 do
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
    local ns = env.Load()
    local register = ns.eventFrame.RegisterEvent
    ns.eventFrame.RegisterEvent = function(frame, event)
        if event == "LOOT_CLOSED" then error("unknown event " .. event) end
        return register(frame, event)
    end
    local reads = Reader(ns)
    local fire = ns.eventFrame:GetScript("OnEvent")

    for _ = 1, 3 do
        fire(ns.eventFrame, "LOOT_READY")
        fire(ns.eventFrame, "LOOT_OPENED")
    end
    suite.check("without LOOT_CLOSED every window is read, once", reads() == 3, reads())
end

suite.done()
