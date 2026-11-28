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
    ns.Share.ownNames, ns.Share.learned = nil, nil
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
-- And a Plainstrider (mob 3244) she looted, as her client names it.
greta.records["Ebenenschreiter|Brachland|"] = {
    mob = "Ebenenschreiter", zone = "Brachland", location = "", npc = 3244, corpses = 30,
    items = { ["Kupfererz"] = { name = "Kupfererz", count = 6, corpses = 6, id = 2770 } },
}
greta.db.tracker.mobs["Ebenenschreiter"] = { kills = 40, copper = 4000, coinKills = 40,
    items = { ["Kupfererz"] = 6 }, qty = {}, stacks = {}, places = { ["Brachland"] = 40 } }
local function Give()
    local out
    Transfer:Make(function(parts) out = parts and parts[1] end)
    return out
end
local text = Give()
check("the German player's data is handed out", type(text) == "string")

-- The English player: 20 of their own there.
local ed = Player()
Switch(ed)
_G.GetLocale = function() return "enUS" end
ed.db.gathering.nodes["The Barrens||Copper Vein"] = {
    zone = "The Barrens", location = "", node = "Copper Vein", kind = "ore",
    gathers = 20, items = { ["Copper Ore"] = { gathers = 20, count = 36, id = 2770 } },
}
ed.records["Plainstrider|The Barrens|"] = {
    mob = "Plainstrider", zone = "The Barrens", location = "", npc = 3244, corpses = 10,
    items = { ["Copper Ore"] = { name = "Copper Ore", count = 1, corpses = 1, id = 2770 } },
}
ed.db.tracker.mobs["Plainstrider"] = { kills = 12, copper = 1200, coinKills = 12,
    items = {}, qty = {}, stacks = {}, places = { ["The Barrens"] = 12 } }

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

-- Her drops and kills meet his Plainstrider.
local strider = ed.records["Plainstrider|The Barrens|"]
check("no German drop record", ed.records["Ebenenschreiter|Brachland|"] == nil
    and ed.records["Plainstrider|Brachland|"] == nil)
check("her corpses join his Plainstrider", strider.corpses == 40, "corpses " .. tostring(strider.corpses))
check("her ore joins his under its English name",
    strider.items["Copper Ore"] and strider.items["Copper Ore"].count == 7 and strider.items["Kupfererz"] == nil)
local tally = ed.db.tracker.mobs["Plainstrider"]
check("no German kill tally", ed.db.tracker.mobs["Ebenenschreiter"] == nil)
check("her kills join his tally", tally.kills == 52, "kills " .. tostring(tally.kills))
check("the tally's items and places are in English",
    tally.items["Copper Ore"] == 6 and tally.places["The Barrens"] == 52 and tally.places["Brachland"] == nil)

-- A newer text from her adds only what grew, under the same names.
Switch(greta)
greta.db.gathering.nodes["Brachland||Kupfervorkommen"].gathers = 177
local newer = Give()
Switch(ed)
Transfer:Parse(newer, function(p) plan = p end)
Transfer:Apply(plan, function() end)
check("a newer text adds only the rise",
    ed.db.gathering.nodes["The Barrens||Copper Vein"].gathers == 197,
    "gathers " .. tostring(ed.db.gathering.nodes["The Barrens||Copper Vein"].gathers))

-- Taking it back out leaves the English player's own counts.
Transfer:Remove(plan.id, function() end)
local own = ed.db.gathering.nodes["The Barrens||Copper Vein"]
check("removing the import leaves your own gathers", own ~= nil and own.gathers == 20)
check("and your own Plainstrider", ed.records["Plainstrider|The Barrens|"].corpses == 10
    and ed.db.tracker.mobs["Plainstrider"].kills == 12)

--------------------------------------------------------------------------------
-- The other way: English data taken on a German client
--------------------------------------------------------------------------------

Switch(ed)
_G.GetLocale = function() return "enUS" end
local english = Give()

Switch(greta)
_G.GetLocale = function() return "deDE" end
_G.C_Item = { GetItemNameByID = function(id) return id == 2770 and "Kupfererz" or nil end }
Transfer:Parse(english, function(p) plan = p end)
Transfer:Apply(plan, function() end)
local mine = greta.db.gathering.nodes["Brachland||Kupfervorkommen"]
check("his Copper Veins join her Kupfervorkommen", mine.gathers == 197,
    "gathers " .. tostring(mine.gathers))
check("no English vein beside it", greta.db.gathering.nodes["The Barrens||Copper Vein"] == nil
    and greta.db.gathering.nodes["Brachland||Copper Vein"] == nil)
check("his ore is named in German", mine.items["Kupfererz"].count == 336 and mine.items["Copper Ore"] == nil)
check("his Plainstrider joins her Ebenenschreiter",
    greta.records["Ebenenschreiter|Brachland|"].corpses == 40 and greta.records["Plainstrider|The Barrens|"] == nil)
_G.C_Item, _G.GetLocale = nil, nil

--------------------------------------------------------------------------------
-- Sharing with your other account names records the same way
--------------------------------------------------------------------------------

local sam = Player()
Switch(sam)
sam.db.gathering.nodes["The Barrens||Copper Vein"] = {
    zone = "The Barrens", location = "", node = "Copper Vein", kind = "ore",
    gathers = 5, items = { ["Copper Ore"] = { gathers = 5, count = 9, id = 2770 } },
}
local state = { key = "partner:test", name = "Test" }
local sent = { zone = "Brachland", location = "", node = "Kupfervorkommen", kind = "ore", gathers = 3,
    items = { ["Kupfererz"] = { gathers = 3, count = 4, id = 2770 } } }
check("a German record from your other account is taken",
    ns.Share:Accept(state, { s = "g", k = "Brachland||Kupfervorkommen", h = "a", d = sent }))
check("it joins your Copper Vein", sam.db.gathering.nodes["The Barrens||Copper Vein"].gathers == 8
    and sam.db.gathering.nodes["Brachland||Kupfervorkommen"] == nil)
sent.gathers = 4
ns.Share.ownNames = nil
ns.Share:Accept(state, { s = "g", k = "Brachland||Kupfervorkommen", h = "b", d = sent })
check("the next sync adds only what grew", sam.db.gathering.nodes["The Barrens||Copper Vein"].gathers == 9,
    "gathers " .. tostring(sam.db.gathering.nodes["The Barrens||Copper Vein"].gathers))

suite.done()
