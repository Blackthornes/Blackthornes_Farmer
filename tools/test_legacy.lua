-- Legacy perks: Bountiful Harvest and Luremaster, read only.
--
-- What matters: the ranks are read from the Legacy trait config, found by
-- its trait system or by the trees that hold its nodes; a client that gives
-- nothing leaves every rank nil and every record as it was; a gather, skin
-- or cast made with a perk is noted beside its record (`boosted`), while the
-- record itself still counts it; the export and every share leave the
-- boosted samples out; and nothing here ever spends a point.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("legacy")

local clock = 500

local ns = env.Load({ ui = true })
local Legacy = ns.Legacy
local Gathering = ns.Gathering
local Harvest = ns.Harvest
local Fishing = ns.Fishing
local Share = ns.Share

_G.GetTime = function() return clock end

Harvest:OnEnable()
ns.Tracker:OnEnable()
Fishing:OnEnable()
Gathering:OnEnable()

local fire = ns.eventFrame:GetScript("OnEvent")

--------------------------------------------------------------------------------
-- A pretend Legacy tree
--------------------------------------------------------------------------------

local CONFIG = 77
local NODES = {
    [110290] = { def = 501, rank = 2, name = "Bountiful Harvest" },
    [110291] = { def = 502, rank = 1, name = "Luremaster" },
    [110292] = { def = 503, rank = 3, name = "Something Else" },
}
local spent = false

local function Traits(opts)
    opts = opts or {}
    return {
        GetConfigIDBySystemID = function(system)
            if opts.bySystem and system == 9 then return CONFIG end
            return 0
        end,
        GetTreeNodes = function(treeID)
            if treeID == 812 then return { 110290, 110291, 110292 } end
            if treeID == 3 then return { 5, 6 } end
            return {}
        end,
        GetConfigIDByTreeID = function(treeID)
            if treeID == 812 then return CONFIG end
            return 0
        end,
        GetConfigInfo = function(configID)
            if configID == CONFIG then return { treeIDs = { 812 } } end
        end,
        GetNodeInfo = function(configID, nodeID)
            if configID ~= CONFIG then error("no such config") end
            local node = NODES[nodeID]
            if not node then return nil end
            return { activeEntry = { entryID = node.def + 1000 }, currentRank = node.rank }
        end,
        GetEntryInfo = function(_, entryID) return { definitionID = entryID - 1000 } end,
        GetDefinitionInfo = function(definitionID)
            for _, node in pairs(NODES) do
                if node.def == definitionID then return { overrideName = node.name } end
            end
        end,
        -- Never to be called.
        PurchaseRank = function() spent = true end,
        CommitConfig = function() spent = true end,
    }
end

--------------------------------------------------------------------------------
-- Nothing to read: everything as today
--------------------------------------------------------------------------------

_G.C_Traits = nil
Legacy:Find()
suite.check("no trait calls, no ranks", Legacy:Rank("harvest") == nil and Legacy:Rank("lure") == nil)
suite.check("so no gather is boosted", Legacy:GatherBoost("herb") == nil)
suite.check("and no cast", Legacy:CastBoost() == nil)
suite.check("the check says it can't be read", Legacy:CheckLine():find("can't be read", 1, true) ~= nil,
    Legacy:CheckLine())

-- A client whose calls raise keeps nothing too.
_G.C_Traits = setmetatable({}, { __index = function() return function() error("secret") end end })
Legacy:Find()
suite.check("calls that raise leave the ranks unread", Legacy.ranks == nil)

--------------------------------------------------------------------------------
-- Found by the trait system
--------------------------------------------------------------------------------

_G.C_Traits = Traits({ bySystem = true })
_G.Enum = _G.Enum or {}
_G.Enum.TraitSystem = { ClassTalents = 1, LegacySystem = 9 }
Legacy:Find()
suite.check("Bountiful Harvest's rank is read", Legacy:Rank("harvest") == 2, Legacy:Rank("harvest"))
suite.check("Luremaster's rank is read", Legacy:Rank("lure") == 1, Legacy:Rank("lure"))
suite.check("other perks are left alone", Legacy.ranks.something == nil)
suite.check("only the config's own trees were looked at", #Legacy.configs[1].nodes == 3)

-- A perk not taken reads 0, and 0 boosts nothing.
NODES[110290].rank = 0
Legacy:Refresh()
suite.check("a perk not taken is 0", Legacy:Rank("harvest") == 0)
suite.check("and boosts nothing", Legacy:GatherBoost("ore") == nil)
NODES[110290].rank = 2
Legacy:Changed()
suite.check("a talent event reads the ranks again", Legacy:Rank("harvest") == 2)

--------------------------------------------------------------------------------
-- Found by its trees
--------------------------------------------------------------------------------

_G.Enum.TraitSystem = { ClassTalents = 1 }
_G.C_Traits = Traits()
Legacy.ranks, Legacy.configs = nil, nil
Legacy:Find()
suite.check("the tree holding Legacy nodes is found", Legacy.configs and #Legacy.configs == 1
    and Legacy.configs[1].configID == CONFIG)
suite.check("and read the same", Legacy:Rank("harvest") == 2 and Legacy:Rank("lure") == 1)
suite.check("nothing was spent", not spent)

--------------------------------------------------------------------------------
-- What counts as boosted
--------------------------------------------------------------------------------

suite.check("herbs, ore and skins are boosted by Bountiful Harvest",
    Legacy:GatherBoost("herb") == 2 and Legacy:GatherBoost("ore") == 2 and Legacy:GatherBoost("skin") == 2)
suite.check("but not other gathers", Legacy:GatherBoost("chest") == nil)

_G.GetWeaponEnchantInfo = function() return false end
suite.check("no lure on the pole, no boosted cast", Legacy:CastBoost() == nil)
_G.GetWeaponEnchantInfo = function() return true, 600000, 1, 263 end
suite.check("a lure on, Luremaster boosts the cast", Legacy:CastBoost() == 1)
_G.GetWeaponEnchantInfo = function() error("secret") end
suite.check("a pole that can't be read counts as lured", Legacy:CastBoost() == 1)
_G.GetWeaponEnchantInfo = function() return true end

--------------------------------------------------------------------------------
-- Records
--------------------------------------------------------------------------------

env.world.zone = "Elwynn Forest"
env.world.subZone = "Goldshire"
env.world.target = nil

local HERB_GATHERING, SKINNING = 2366, 8613
local PEACEBLOOM = { name = "Peacebloom", id = 2447 }
local FANG = { name = "Large Fang", id = 5637 }
local LEATHER = { name = "Light Leather", id = 2318 }
local casts = 0

local function Send(spell, target)
    casts = casts + 1
    local id = "Cast-" .. casts
    fire(ns.eventFrame, "UNIT_SPELLCAST_SENT", "player", target, id, spell)
    return id
end

local function Open(items)
    env.world.loot = items
    fire(ns.eventFrame, "LOOT_OPENED")
    fire(ns.eventFrame, "LOOT_CLOSED")
end

local function Gather(items)
    local id = Send(HERB_GATHERING, "Peacebloom")
    clock = clock + 2
    fire(ns.eventFrame, "UNIT_SPELLCAST_SUCCEEDED", "player", id, HERB_GATHERING)
    Open(items)
    clock = clock + 1
end

local BLOOM = Gathering.NodeKey("Elwynn Forest", "Goldshire", "Peacebloom")

-- Two picks without the perk, one with.
Legacy.ranks = { harvest = 0, lure = 0 }
Gather({ PEACEBLOOM })
Gather({ PEACEBLOOM })
local node = ns.db.gathering.nodes[BLOOM]
suite.check("a pick without the perk notes nothing", node.boosted == nil)

Legacy.ranks = { harvest = 2, lure = 1 }
Gather({ { name = "Peacebloom", id = 2447, quantity = 4 } })
suite.check("the record still counts every pick", node.gathers == 3, node.gathers)
suite.check("one pick is noted boosted", node.boosted and node.boosted.gathers == 1)
suite.check("with what it gave", node.boosted.items.Peacebloom.count == 4,
    node.boosted.items.Peacebloom.count)
suite.check("and the rank", node.boosted.rank == 2)

local clean = Legacy.Without(node, "gathers")
suite.check("taken out, two picks are left", clean.gathers == 2, clean.gathers)
suite.check("and only their herbs", clean.items.Peacebloom.count == node.items.Peacebloom.count - 4)
suite.check("the record itself is untouched", node.gathers == 3 and node.boosted ~= nil)
suite.check("a record with nothing boosted is its own clean copy", Legacy.Without({ gathers = 1 }, "gathers").gathers == 1)

-- Sharing leaves the boosted pick out.
local section = Share.Parts.BY_KEY.g
local sent = Share.Export(section.spec, node, Share.Parts.CreditsFor(section, BLOOM))
suite.check("a share sends only the unboosted picks", sent.gathers == 2, sent.gathers)
suite.check("and their herbs", sent.items.Peacebloom.count == node.items.Peacebloom.count - 4)

-- A cast with Luremaster and a lure.
Legacy.ranks = { harvest = 2, lure = 0 }
Fishing:Record("Elwynn Forest", "Goldshire", nil, { "Raw Brilliant Smallfish" }, nil, 20)
Legacy.ranks = { harvest = 2, lure = 1 }
Fishing:Record("Elwynn Forest", "Goldshire", nil, { "Raw Brilliant Smallfish" }, { ["Raw Brilliant Smallfish"] = 2 }, 20)
local spotKey
for key in pairs(ns.db.fishing.spots) do spotKey = key end
local spot = ns.db.fishing.spots[spotKey]
suite.check("both casts are counted", spot.casts == 2, spot.casts)
suite.check("the lured one is noted", spot.boosted and spot.boosted.casts == 1)
suite.check("fishing's own numbers keep both", Fishing:CountCasts() == 2, Fishing:CountCasts())
suite.check("the clean count leaves it out", Fishing:CountCasts(true) == 1, Fishing:CountCasts(true))
suite.check("the shipped fishing rows count one cast",
    (Fishing:ExportBlocks() or ""):find("casts = 1", 1, true) ~= nil
    or (Fishing:ExportBlocks() or ""):find("1 cast", 1, true) ~= nil)

-- A skin with Bountiful Harvest moves the whole corpse aside.
local serial = 0
local function Kill(name, items)
    serial = serial + 1
    local guid = "Creature-0-1-2-3-4-" .. serial
    env.world.target = { name = name, level = 8, dead = true, guid = guid }
    Open(items)
    return guid
end

Legacy.ranks = { harvest = 2, lure = 1 }
Kill("Mangy Wolf", { FANG })
Kill("Mangy Wolf", { FANG })
local skin = Send(SKINNING, "Mangy Wolf")
fire(ns.eventFrame, "UNIT_SPELLCAST_SUCCEEDED", "player", skin, SKINNING)
Open({ LEATHER })

local wolf
for _, record in pairs(Harvest.records) do
    if record.mob == "Mangy Wolf" then wolf = record end
end
suite.check("both wolves are in the harvest", wolf and wolf.corpses == 2, wolf and wolf.corpses)
suite.check("the skinned corpse is noted boosted", wolf.boosted and wolf.boosted.corpses == 1,
    wolf.boosted and wolf.boosted.corpses)
suite.check("with its leather", wolf.boosted.items["Light Leather"]
    and wolf.boosted.items["Light Leather"].count == 1)
suite.check("and the fang it dropped", wolf.boosted.items["Large Fang"]
    and wolf.boosted.items["Large Fang"].corpses == 1)

local exported = Harvest:ExportRecords()
local cleanWolf
for _, record in pairs(exported) do
    if record.mob == "Mangy Wolf" then cleanWolf = record end
end
suite.check("the export counts one corpse", cleanWolf and cleanWolf.corpses == 1)
suite.check("and no leather from the perk", cleanWolf.items["Light Leather"] == nil)
suite.check("the export header counts the clean corpses",
    Harvest:ExportAll():find("1 corpses looted", 1, true) ~= nil)
suite.check("the player's own count keeps both", Harvest:CountCorpses() == 2)

local hsection = Share.Parts.BY_KEY.h
local wolfKey
for key, record in pairs(Harvest.records) do if record == wolf then wolfKey = key end end
local hsent = Share.Export(hsection.spec, wolf, Share.Parts.CreditsFor(hsection, wolfKey))
suite.check("a share sends one wolf", hsent.corpses == 1, hsent.corpses)

-- Without a perk, a skin notes nothing.
Legacy.ranks = nil
Kill("Kobold Vermin", { FANG })
local skin2 = Send(SKINNING, "Kobold Vermin")
fire(ns.eventFrame, "UNIT_SPELLCAST_SUCCEEDED", "player", skin2, SKINNING)
Open({ LEATHER })
local kobold
for _, record in pairs(Harvest.records) do
    if record.mob == "Kobold Vermin" then kobold = record end
end
suite.check("with no rank read, nothing is noted", kobold and kobold.boosted == nil)

suite.check("nothing was ever spent", not spent)

suite.done()
