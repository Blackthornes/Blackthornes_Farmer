-- The same name in another zone gets its own line (the owner, 2026-10-16).
--
-- What matters: a mob killed in one zone is one line, as before; killed in
-- two zones it is a line a zone, each with its own kills and loot, on
-- Rankings, the kills panel, the loot table, the mob tooltip and the
-- nameplates; the whole tally under its name is untouched, so nothing a
-- player kept is lost; kills from before the split are laid out from the
-- loot records once, and never counted twice.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("zonelines")

local ns = env.Load({ ui = true })
local Tracker = ns.Tracker

local AUCTION = { [5637] = 50, [2318] = 10 }
_G.C_Item = {
    GetItemInfo = function()
        return "item", nil, 1, 1, 1, "", "", 1, "", "", 1
    end,
}
_G.BlackthornesTS = { Prices = { GetValue = function(_, id) return AUCTION[id] end } }

local serial = 0
local function Loot(mob, zone, subZone, item)
    serial = serial + 1
    env.world.zone, env.world.subZone = zone, subZone
    env.world.target = { name = mob, level = 20, dead = true, guid = "Z-" .. serial }
    env.world.loot = { { name = "12 Copper", money = true }, item }
    Tracker:OnLoot()
end

local FANG = { name = "Large Fang", id = 5637 }
local LEATHER = { name = "Light Leather", id = 2318 }

-- One zone: one line, as before.
for _ = 1, 5 do Loot("Gray Wolf", "Elwynn Forest", "Northshire", FANG) end
suite.check("one zone is not split", not Tracker:IsSplit("Gray Wolf"))
suite.check("its one line is its name", #Tracker:Lines("Gray Wolf") == 1 and Tracker:Lines("Gray Wolf")[1] == "Gray Wolf")
suite.check("the zone's tally is kept beside it", Tracker:Store()["Gray Wolf"].zones["Elwynn Forest"].kills == 5)

-- Two zones: two lines.
for _ = 1, 3 do Loot("Gray Wolf", "Westfall", "Sentinel Hill", LEATHER) end
suite.check("two zones are split", Tracker:IsSplit("Gray Wolf"))
local elwynn = Tracker.ZoneKey("Gray Wolf", "Elwynn Forest")
local westfall = Tracker.ZoneKey("Gray Wolf", "Westfall")
suite.check("a line a zone", #Tracker:Lines("Gray Wolf") == 2)
suite.check("the whole tally is untouched", Tracker:Store()["Gray Wolf"].kills == 8)
suite.check("each line has its own kills",
    Tracker:Tally(elwynn).kills == 5 and Tracker:Tally(westfall).kills == 3)
suite.check("each line has its own loot",
    (Tracker:Tally(elwynn).items["Large Fang"] or 0) == 5 and Tracker:Tally(elwynn).items["Light Leather"] == nil
    and (Tracker:Tally(westfall).items["Light Leather"] or 0) == 3)
suite.check("each line has its own coin", Tracker:Tally(westfall).copper == 36)
suite.check("a line reads as its zone", Tracker.ShowKey(westfall) == "Gray Wolf (Westfall)")
suite.check("a plain name reads as it is", Tracker.ShowKey("Gray Wolf") == "Gray Wolf")
suite.check("the name comes back out of a key", Tracker.NameOf(westfall) == "Gray Wolf")

local tallies = Tracker:Tallies()
suite.check("the tallies have both lines and not the name",
    tallies[elwynn] and tallies[westfall] and tallies["Gray Wolf"] == nil)

-- The summary and the worth follow the line.
local summary = Tracker:Summary(westfall)
suite.check("a line's summary is that zone's", summary and summary.kills == 3 and summary.zone == "Westfall")
suite.check("and knows the mob's name", summary and summary.name == "Gray Wolf")
suite.check("the name's summary is the whole", Tracker:Summary("Gray Wolf").kills == 8)

-- The kills panel shows the zones killed in this session.
local shown = {}
for _, entry in ipairs(Tracker:SessionMobs()) do shown[entry.mob or entry.name or entry] = true end
suite.check("the panel has a line a zone", shown[elwynn] and shown[westfall], shown)
suite.check("the line you are on is the last killed", Tracker.currentKey == westfall)

-- The mob tooltip and nameplates read the zone you are in.
env.world.zone = "Elwynn Forest"
suite.check("here is Elwynn's line", Tracker:KeyHere("Gray Wolf") == elwynn)
suite.check("the tooltip counts Elwynn's kills", ns.KillTooltip.Kills(ns.KillTooltip.KeyHere("Gray Wolf")) == 5)
env.world.zone = "Westfall"
suite.check("the tooltip counts Westfall's kills there", ns.KillTooltip.Kills(ns.KillTooltip.KeyHere("Gray Wolf")) == 3)
env.world.zone = "Duskwood"
suite.check("a zone it was never killed in is the whole", Tracker:KeyHere("Gray Wolf") == "Gray Wolf")
suite.check("an unsplit mob is its name anywhere", Tracker:KeyHere("Nobody") == "Nobody")

-- Rankings gives each zone its own place once it has kills enough.
for _ = 1, 20 do Loot("Gray Wolf", "Elwynn Forest", "Northshire", FANG) end
for _ = 1, 20 do Loot("Gray Wolf", "Westfall", "Sentinel Hill", LEATHER) end
local board = ns.Rankings:Build()
local found = {}
for _, entry in ipairs(board.measured) do found[entry.mob] = entry end
suite.check("Rankings has a line a zone", found[elwynn] and found[westfall])
suite.check("and not the name", found["Gray Wolf"] == nil)
suite.check("each with its own worth",
    found[elwynn] and found[westfall] and found[elwynn].value ~= found[westfall].value)

-- Kills from before the split come from the loot records, once.
local mobs = Tracker:Store()
mobs["Old Bat"] = { kills = 30, items = { ["Large Fang"] = 30 }, qty = {}, stacks = {},
    copper = 300, coinKills = 30,
    places = { ["Ruins, Duskwood"] = 20, ["Hill, Redridge Mountains"] = 10 } }
ns.Harvest.records = ns.Harvest.records or {}
ns.Harvest.records["Old Bat|Duskwood|Ruins"] = { mob = "Old Bat", zone = "Duskwood", location = "Ruins",
    corpses = 20, items = { ["Large Fang"] = { count = 20, corpses = 20 } } }
ns.Harvest.records["Old Bat|Redridge Mountains|Hill"] = { mob = "Old Bat", zone = "Redridge Mountains",
    location = "Hill", corpses = 10, items = { ["Large Fang"] = { count = 10, corpses = 10 } } }
mobs["Old Owl"] = { kills = 12, items = { ["Large Fang"] = 4 }, qty = {}, stacks = {}, copper = 50,
    coinKills = 12, places = { ["Glade, Teldrassil"] = 12 } }
Tracker:SeedAllZones()
suite.check("an old mob over two zones is split", Tracker:IsSplit("Old Bat"))
suite.check("its zones come from the loot records",
    Tracker:Tally(Tracker.ZoneKey("Old Bat", "Duskwood")).kills == 20
    and Tracker:Tally(Tracker.ZoneKey("Old Bat", "Redridge Mountains")).kills == 10)
suite.check("its whole tally is untouched", mobs["Old Bat"].kills == 30 and mobs["Old Bat"].copper == 300)
suite.check("an old mob in one zone is copied whole", mobs["Old Owl"].zones["Teldrassil"].kills == 12
    and mobs["Old Owl"].zones["Teldrassil"].copper == 50)
Tracker:SeedAllZones()
suite.check("laid out only once", Tracker:Tally(Tracker.ZoneKey("Old Bat", "Duskwood")).kills == 20)
Loot("Old Bat", "Duskwood", "Ruins", FANG)
suite.check("a new kill adds once", Tracker:Tally(Tracker.ZoneKey("Old Bat", "Duskwood")).kills == 21
    and mobs["Old Bat"].kills == 31)

-- Sharing never sends the zones.
local exported = ns.Share and ns.Share.Export and select(2, pcall(ns.Share.Export, "k")) or nil
if type(exported) == "table" then
    local leaked = false
    for _, record in pairs(exported) do
        if type(record) == "table" and record.zones ~= nil then leaked = true end
    end
    suite.check("sharing leaves the zones out", not leaked)
end

suite.done()
