-- A mob kept as "Creature #ID" that one account has named and the other has
-- not. What matters: a partner's counts for it are taken once, whichever
-- side learned the name first, and the side that learned it later does not
-- keep them twice once its own record is named.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("unnamedshare")

local ns = env.Load({ ui = true })
ns.Harvest:OnEnable()
ns.Tracker:OnEnable()
_G.InCombatLockdown = function() return false end

local Share, Harvest = ns.Share, ns.Harvest
local known = Harvest.KnownNpcName
local names = {}
Harvest.KnownNpcName = function(id) return names[id] end

local UNNAMED = "Creature #11320|Ragefire Chasm|"
local NAMED = "Earthborer|Ragefire Chasm|"

local function Drop(mob, corpses, fangs)
    return { mob = mob, zone = "Ragefire Chasm", location = "", npc = 11320, corpses = corpses,
        items = { Fang = { name = "Fang", count = fangs, corpses = fangs } } }
end

local function Fresh()
    for key in pairs(Harvest.records) do Harvest.records[key] = nil end
    local mobs = ns.Tracker:Store()
    for key in pairs(mobs) do mobs[key] = nil end
    ns.db.shareIn = {}
    for key in pairs(names) do names[key] = nil end
end

local state = { key = "partner", name = "Partner" }

--------------------------------------------------------------------------------
-- 1. This side knows the name; the partner still sends "Creature #ID"
--------------------------------------------------------------------------------

Fresh()
names[11320] = "Earthborer"
suite.check("taken", Share:Accept(state, { s = "h", k = UNNAMED, h = "a", d = Drop("Creature #11320", 6, 2) }))
suite.check("under the name this side knows", Harvest.records[NAMED] and Harvest.records[NAMED].corpses == 6
    and Harvest.records[UNNAMED] == nil)
Share:Accept(state, { s = "h", k = UNNAMED, h = "b", d = Drop("Creature #11320", 8, 3) })
suite.check("sent again, only the rise is added", Harvest.records[NAMED].corpses == 8
    and Harvest.records[NAMED].items.Fang.count == 3, Harvest.records[NAMED].corpses)
Share:Accept(state, { s = "h", k = NAMED, h = "c", d = Drop("Earthborer", 8, 3) })
suite.check("and once they learn the name, nothing is added twice", Harvest.records[NAMED].corpses == 8,
    Harvest.records[NAMED].corpses)
suite.check("the hash stays under the key they sent",
    ns.db.shareIn.partner.hashes.h[ns.Comm.Hash(UNNAMED)] == "b")

Share:Accept(state, { s = "k", k = "Creature #11320", h = "d", d = { kills = 6 } })
suite.check("a kill tally goes under the name too", ns.db.tracker.mobs["Earthborer"]
    and ns.db.tracker.mobs["Earthborer"].kills == 6 and ns.db.tracker.mobs["Creature #11320"] == nil)

--------------------------------------------------------------------------------
-- 2. The partner knows the name first; this side learns it later
--------------------------------------------------------------------------------

Fresh()
Harvest.records[UNNAMED] = Drop("Creature #11320", 10, 4)   -- 4 own, 6 from the partner
Share:Accept(state, { s = "h", k = UNNAMED, h = "a", d = Drop("Creature #11320", 6, 2) })
suite.check("before: theirs is added to the nameless record", Harvest.records[UNNAMED].corpses == 16)
Share:Accept(state, { s = "h", k = NAMED, h = "b", d = Drop("Earthborer", 9, 3) })
suite.check("they named it: their whole count lands under the name", Harvest.records[NAMED].corpses == 9)

names[11320] = "Earthborer"
Harvest:NameUnnamed()
local record = Harvest.records[NAMED]
suite.check("named here, their counts are kept once", record.corpses == 19, record.corpses)
suite.check("their drops too", record.items.Fang.count == 7, record.items.Fang.count)
local credit = ns.db.shareIn.partner.credit.h
suite.check("the ledger keeps the most taken", credit[NAMED].corpses == 9 and credit[UNNAMED] == nil
    and credit[NAMED].items.Fang.count == 3)
local out = Share.Export(Share.Parts.BY_KEY.h.spec, record, { credit[NAMED] })
suite.check("only this side's own go back", out.corpses == 10 and out.items.Fang.count == 4, out.corpses)

-- The kill tally the same way.
ns.db.tracker.mobs["Creature #11320"] = { kills = 16, copper = 0, coinKills = 16, items = {} }
ns.db.shareIn.partner.credit.k = { ["Creature #11320"] = { kills = 6 } }
names[11320] = nil
Share:Accept(state, { s = "k", k = "Earthborer", h = "c", d = { kills = 9 } })
names[11320] = "Earthborer"
Harvest:NameUnnamed()
suite.check("kills are kept once too", ns.db.tracker.mobs["Earthborer"].kills == 19,
    ns.db.tracker.mobs["Earthborer"].kills)

--------------------------------------------------------------------------------
-- 3. Two partners: each one's ledger stands on its own
--------------------------------------------------------------------------------

Fresh()
ns.db.shareIn.other = { credit = { h = { [NAMED] = { corpses = 5 } } }, hashes = { h = {} } }
Harvest.records[UNNAMED] = Drop("Creature #11320", 6, 0)
Harvest.records[NAMED] = Drop("Earthborer", 5, 0)
ns.db.shareIn.partner = { credit = { h = { [UNNAMED] = { corpses = 6 } } }, hashes = { h = {} } }
names[11320] = "Earthborer"
Harvest:NameUnnamed()
suite.check("a different partner's counts are not taken off", Harvest.records[NAMED].corpses == 11,
    Harvest.records[NAMED].corpses)

Harvest.KnownNpcName = known
suite.done()
