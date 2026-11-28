-- Data given by a player on another language's client (a German player's
-- report, 2026-11-28: "I now have English and German data in my farmer stats
-- ... separately").
--
-- A German client keeps its gathers under the names it sees: "Brachland",
-- "Kupfervorkommen", "Kupfererz". Given to a player on an English client,
-- they must count toward The Barrens' Copper Vein, not sit beside it as a
-- second zone and node with no spots and no prices.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("import_language")
local check = suite.check

local ns = env.Load()
local Transfer, GrindGather = ns.Transfer, ns.GrindGather

_G.time = _G.time or function() return 1000000 end
_G.date = _G.date or function() return "28 Nov" end
_G.InCombatLockdown = function() return false end

local function Player()
    local db = {}
    for key, value in pairs(ns.DEFAULTS) do db[key] = value end
    db.tracker = { mobs = {} }
    db.gathering = { nodes = {}, spots = {} }
    db.fishing = { spots = {} }
    return { db = db, records = {} }
end
local function Switch(p)
    ns.db = p.db
    ns.Harvest.records = p.records
    p.db.harvest = p.records
end

-- The German player: 167 Copper Veins mined in The Barrens, as their client
-- names it.
local greta = Player()
Switch(greta)
greta.db.gathering.nodes["Brachland||Kupfervorkommen"] = {
    zone = "Brachland", location = "", node = "Kupfervorkommen", kind = "ore",
    gathers = 167, items = { ["Kupfererz"] = { gathers = 167, count = 300, id = 2770 } },
}
local text
Transfer:Make(function(parts) text = parts and parts[1] end)
check("the German player's data is handed out", type(text) == "string")

-- The English player: 20 of their own there.
local ed = Player()
Switch(ed)
_G.GetLocale = function() return "enUS" end
ed.db.gathering.nodes["The Barrens||Copper Vein"] = {
    zone = "The Barrens", location = "", node = "Copper Vein", kind = "ore",
    gathers = 20, items = { ["Copper Ore"] = { gathers = 20, count = 36, id = 2770 } },
}

local plan
Transfer:Parse(text, function(p) plan = p end)
check("the text reads", plan ~= nil)
local taken
Transfer:Apply(plan, function(n) taken = n end)
check("the import finishes", taken ~= nil)

-- What the Ore view shows the English player for levels 10 to 25.
local function Zone(zones, name)
    for _, zone in ipairs(zones) do if zone.zone == name then return zone end end
end
local function Node(zone, name)
    for _, node in ipairs(zone and zone.nodes or {}) do if node.name == name then return node end end
end
local zones = GrindGather:Zones("ore", 10, 25)

check("no zone row named Brachland", Zone(zones, "Brachland") == nil,
    "the German zone shows as its own heading")
check("no Kupfervorkommen row anywhere",
    Node(Zone(zones, "Brachland"), "Kupfervorkommen") == nil and Node(Zone(zones, "The Barrens"), "Kupfervorkommen") == nil,
    "the German vein sits beside Copper Vein")
local vein = Node(Zone(zones, "The Barrens"), "Copper Vein")
check("The Barrens' Copper Vein counts both players' gathers",
    vein ~= nil and vein.gathers == 187, "gathers " .. tostring(vein and vein.gathers))
check("its gives list has no German item name", vein ~= nil and not vein.gives["Kupfererz"])

-- Taking it back out leaves the English player's own 20.
local removed
Transfer:Remove(plan.id or next(ed.db.shareIn or {}), function() removed = true end)
local own = ed.db.gathering.nodes["The Barrens||Copper Vein"]
check("removing the import leaves your own gathers", own ~= nil and own.gathers == 20)

suite.done()
