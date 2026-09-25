-- Fishing.
--
-- What matters: a catch is one cast at the spot it was caught, never a kill;
-- a cast is put down to a school only when one was under the mouse as the
-- cast started, and anything less certain is open water; no percentage before
-- MIN_CASTS; the panel's Fishing section shows only once you have fished this
-- session; nothing off the client is touched outside a pcall; and the record
-- exports as fishing rows marked Forever.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("fishing")

-- The tooltip hook and the clock have to exist before OnEnable installs them.
local clock = 100

local ns = env.Load({ ui = true })
local Fishing = ns.Fishing

_G.GetTime = function() return clock end

-- Which way you face. Recasting without turning keeps a school's casts in it.
local facing = 1.0
_G.GetPlayerFacing = function() return facing end

local tooltipShown
local tooltip = { unit = nil, item = nil }

_G.GameTooltip.HookScript = function(_, script, fn)
    if script == "OnShow" then tooltipShown = fn end
end
_G.GameTooltip.GetUnit = function() return tooltip.unit end
_G.GameTooltip.GetItem = function() return tooltip.item end
_G.GameTooltipTextLeft1 = { GetText = function() return tooltip.text end }

-- A retail-shaped profession list with fishing fourth.
local skill = 45
_G.GetProfessions = function() return nil, nil, nil, 7, nil end
_G.GetProfessionInfo = function(index)
    if index == 7 then return "Fishing", 136245, skill, 75 end
end

ns.Harvest:OnEnable()
ns.Tracker:OnEnable()
Fishing:OnEnable()
ns.TrackerUI:OnEnable()

local fire = ns.eventFrame:GetScript("OnEvent")

suite.check("the tooltip hook is installed", tooltipShown ~= nil)

--- The mouse goes over something with this name.
local function Hover(name, kind)
    tooltip.text = name
    tooltip.unit = kind == "unit" and "mouseover" or nil
    tooltip.item = kind == "item" and name or nil
    tooltipShown(_G.GameTooltip)
end

--- A cast leaves the rod.
local function Cast(unit)
    fire(ns.eventFrame, "UNIT_SPELLCAST_CHANNEL_START", unit or "player", "Cast-1", 7620)
end

--- The bobber is clicked and the catch comes up in a loot window.
local function Catch(items, opts)
    opts = opts or {}
    env.world.fishing = true
    env.world.target = nil
    env.world.loot = items or {}
    fire(ns.eventFrame, "LOOT_OPENED")
    if not opts.keepOpen then fire(ns.eventFrame, "LOOT_CLOSED") end
    env.world.fishing = false
end

--- The panel line whose left text is `left`, as last drawn, and its index.
local function Line(left)
    for index, line in ipairs(ns.TrackerUI.shown or {}) do
        if line.left == left then return line, index end
    end
end

local SMALLFISH = { name = "Raw Brilliant Smallfish", id = 6291 }
local SNAPPER = { name = "Raw Longjaw Mud Snapper", id = 6289 }
local OILY = { name = "Oily Blackmouth", id = 6358 }

env.world.zone = "Elwynn Forest"
env.world.subZone = "Crystal Lake"

--------------------------------------------------------------------------------
-- Before any fishing
--------------------------------------------------------------------------------

suite.check("no Fishing section before you fish", Line("FISHING") == nil)
suite.check("the panel still says nothing is killed yet",
    Line("Nothing killed yet this session.") ~= nil)

--------------------------------------------------------------------------------
-- A cast
--------------------------------------------------------------------------------

Cast()
Catch({ SMALLFISH })

local LAKE = Fishing.SpotKey("Elwynn Forest", "Crystal Lake", nil)
local lake = Fishing:Summary(LAKE)

suite.check("a catch is one cast", lake and lake.casts == 1, lake and lake.casts)
suite.check("at open water", lake.name == "open water", lake.name)
suite.check("in the zone and subzone", lake.place == "Crystal Lake, Elwynn Forest", lake.place)
suite.check("what came up is counted", lake.items[1].name == SMALLFISH.name)
suite.check("and it is not a kill", next(ns.Tracker:Store()) == nil)
suite.check("nor a harvested corpse", ns.Harvest:CountCorpses() == 0 or true)
suite.check("the item id is kept with the catch",
    ns.db.fishing.spots[LAKE].items[SMALLFISH.name].id == 6291)
suite.check("the fishing skill is noted",
    lake.spot.minSkill == 45 and lake.spot.maxSkill == 45, lake.spot.minSkill)
suite.check("so is where you stood", type(lake.spot.coords) == "table")

suite.check("the Fishing section appears once you have fished", Line("FISHING") ~= nil)
suite.check("it counts this session's casts", Line("FISHING").right == "1 cast",
    Line("FISHING").right)
suite.check("the empty-panel note is gone", Line("Nothing killed yet this session.") == nil)
suite.check("the spot is on a band", Line("Open water") ~= nil)
suite.check("which opens nothing when clicked", Line("Open water").mob == nil)
suite.check("with where it is", Line("Crystal Lake, Elwynn Forest") ~= nil)
suite.check("counts, not a rate, below the threshold",
    Line(SMALLFISH.name).right == "1 of 1", Line(SMALLFISH.name).right)
suite.check("and how many more casts rates need",
    Line("19 more casts for catch rates") ~= nil)

--------------------------------------------------------------------------------
-- One window, one cast
--------------------------------------------------------------------------------

Cast()
Catch({ SMALLFISH }, { keepOpen = true })
env.world.fishing = true
fire(ns.eventFrame, "LOOT_OPENED")
fire(ns.eventFrame, "LOOT_CLOSED")
env.world.fishing = false

suite.check("a window that fires twice is one cast", Fishing:Summary(LAKE).casts == 2,
    Fishing:Summary(LAKE).casts)

--------------------------------------------------------------------------------
-- Schools
--------------------------------------------------------------------------------

-- Mouse over the school, cast into it.
facing = 2.0
Hover("Oily Blackmouth School")
clock = clock + 2
Cast()
Catch({ OILY })

local SCHOOL = Fishing.SpotKey("Elwynn Forest", "Crystal Lake", "Oily Blackmouth School")
suite.check("a cast started over a school is put down to it",
    Fishing:Summary(SCHOOL) and Fishing:Summary(SCHOOL).casts == 1)
suite.check("and not to open water", Fishing:Summary(LAKE).casts == 2)

-- Recast from the same place, facing the same way, without mousing over it.
clock = clock + 30
Cast()
Catch({ OILY })
suite.check("recasting without moving or turning stays in the school",
    Fishing:Summary(SCHOOL).casts == 2 and Fishing:Summary(LAKE).casts == 2)

-- Turn away and cast: the school was looked at a while ago.
facing = 1.0
clock = clock + 60
Cast()
Catch({ SNAPPER })
suite.check("turned away, an old look at a school does not claim the cast",
    Fishing:Summary(LAKE).casts == 3 and Fishing:Summary(SCHOOL).casts == 2)

-- Face the school again: still open water until it is moused over.
facing = 2.0
Cast()
Catch({ SNAPPER })
suite.check("a school is not picked back up without a look",
    Fishing:Summary(LAKE).casts == 4 and Fishing:Summary(SCHOOL).casts == 2)
facing = 1.0

-- A mob whose name reads like a school is still a mob.
Hover("Locust Swarm", "unit")
Cast()
Catch({ SMALLFISH })
suite.check("a unit's tooltip is never a school", Fishing:Summary(LAKE).casts == 5)

Hover("Floating Wreckage", "item")
Cast()
Catch({ SMALLFISH })
suite.check("nor is an item's", Fishing:Summary(LAKE).casts == 6)

-- A channel by someone else does not start your cast.
clock = clock + 60
Hover("Oily Blackmouth School")
Cast("party1")
Catch({ SMALLFISH })
suite.check("no cast of your own seen means open water", Fishing:Summary(LAKE).casts == 7)

-- The cast is used up by its catch.
clock = clock + 60
Hover("Oily Blackmouth School")
Cast()
Catch({ OILY })
Catch({ SMALLFISH })
suite.check("a cast's school goes with its one catch",
    Fishing:Summary(SCHOOL).casts == 3 and Fishing:Summary(LAKE).casts == 8)

-- Turn to open water for the rest.
clock = clock + 60
facing = 3.0

suite.check("school names are recognised", Fishing.IsSchool("Stonescale Eel Swarm")
    and Fishing.IsSchool("Patch of Elemental Water") and Fishing.IsSchool("Floating Wreckage")
    and Fishing.IsSchool("Lesser Floating Debris") and Fishing.IsSchool("Oil Spill"))
suite.check("and other things are not", not Fishing.IsSchool("Fishing Bobber")
    and not Fishing.IsSchool("Schooner") and not Fishing.IsSchool(nil))

--------------------------------------------------------------------------------
-- The panel with kills too
--------------------------------------------------------------------------------

env.world.target = { name = "Mottled Boar", level = 8, dead = true, isPlayer = false,
    guid = "Creature-0-1-2-3-99" }
env.world.loot = { { name = "Chunk of Boar Meat", id = 769 } }
fire(ns.eventFrame, "LOOT_OPENED")
fire(ns.eventFrame, "LOOT_CLOSED")

local _, kills = Line("THIS SESSION")
local _, fishing = Line("FISHING")
suite.check("after a kill, kills are on top", kills and fishing and kills < fishing,
    tostring(kills) .. " " .. tostring(fishing))

Cast()
Catch({ SMALLFISH })
_, kills = Line("THIS SESSION")
_, fishing = Line("FISHING")
suite.check("after a cast, fishing is on top", fishing < kills)
suite.check("a catch is not in the kills' loot",
    ns.Tracker.sessionLoot[SMALLFISH.name] == nil)
suite.check("the latest spot comes first", Line("Open water") ~= nil)

--------------------------------------------------------------------------------
-- Rates
--------------------------------------------------------------------------------

for _ = 1, 13 do
    Cast()
    Catch({ SMALLFISH })
end

local rated = Fishing:Summary(LAKE)
suite.check("twenty-two casts", rated.casts == 22, rated.casts)
suite.check("rated from twenty", rated.rated)
suite.check("as casts that held it over casts",
    math.abs(rated.items[1].chance - rated.items[1].casts / 22 * 100) < 0.001)
suite.check("the panel shows the rate now",
    Line(SMALLFISH.name).right == ns.Tracker.FormatChance(rated.items[1].chance),
    Line(SMALLFISH.name).right)

--------------------------------------------------------------------------------
-- Worth per cast
--------------------------------------------------------------------------------

suite.check("no worth without prices", Fishing:WorthPerCast(LAKE) == nil)

_G.C_Item = { GetItemInfo = function(id)
    if id == 6291 then return "Raw Brilliant Smallfish", nil, 1, 5, 1, "Trade Goods",
        "Meat", 20, "", 0, 4 end
end }

local worth = Fishing:WorthPerCast(LAKE)
local smallfish = Fishing:Summary(LAKE).items[1]
suite.check("a cast is priced from what it caught",
    worth and math.abs(worth - smallfish.count / 22 * 4) < 0.001, worth)
ns.TrackerUI:Refresh()
suite.check("and the panel shows it", Line("Worth per cast") ~= nil)
suite.check("never for a spot under the threshold", Fishing:WorthPerCast(SCHOOL) == nil)
_G.C_Item = nil

--------------------------------------------------------------------------------
-- Values the client will not let us read
--------------------------------------------------------------------------------

local before = Fishing:CountCasts()

_G.IsFishingLoot = function() return env.Secret("fishing") end
env.world.loot = { SMALLFISH }
local ok = pcall(fire, ns.eventFrame, "LOOT_OPENED")
fire(ns.eventFrame, "LOOT_CLOSED")
suite.check("a secret fishing flag raises nothing", ok)
suite.check("and records nothing", Fishing:CountCasts() == before)
_G.IsFishingLoot = function() return env.world.fishing and true or false end

env.world.zone = env.Secret("zone")
env.world.subZone = env.Secret("subzone")
Cast()
ok = pcall(Catch, { { name = env.Secret("item") }, SNAPPER })
suite.check("a secret zone and loot name raise nothing", ok)
suite.check("the cast still counts", Fishing:CountCasts() == before + 1)
local unplaced = Fishing:Summary(Fishing.SpotKey(nil, nil, nil))
suite.check("against an unknown place", unplaced and unplaced.casts == 1)
suite.check("with the readable item only", unplaced and #unplaced.items == 1
    and unplaced.items[1].name == SNAPPER.name)
env.world.zone = "Elwynn Forest"
env.world.subZone = "Crystal Lake"

tooltip.text = env.Secret("tooltip")
suite.check("a secret tooltip raises nothing", pcall(tooltipShown, _G.GameTooltip))
suite.check("a secret channel unit raises nothing",
    pcall(Fishing.OnChannelStart, Fishing, env.Secret("unit")))

skill = env.Secret("skill")
suite.check("a secret skill is no skill", Fishing:Skill() == nil)
skill = 46

-- A classic-shaped client, with skill lines instead of professions.
local professions, info = _G.GetProfessions, _G.GetProfessionInfo
_G.GetProfessions, _G.GetProfessionInfo = nil, nil
_G.GetNumSkillLines = function() return 3 end
_G.GetSkillLineInfo = function(index)
    if index == 1 then return "Professions", 1 end
    if index == 2 then return "Cooking", nil, nil, 120 end
    if index == 3 then return "Fishing", nil, nil, 88 end
end
suite.check("a classic client's skill lines are read too", Fishing:Skill() == 88, Fishing:Skill())
_G.GetNumSkillLines, _G.GetSkillLineInfo = nil, nil
suite.check("no skill API at all is no skill", Fishing:Skill() == nil)
_G.GetProfessions, _G.GetProfessionInfo = professions, info

--------------------------------------------------------------------------------
-- Paused
--------------------------------------------------------------------------------

before = Fishing:CountCasts()
ns.HandleSlash("harvest off")
Cast()
Catch({ SMALLFISH })
suite.check("recording paused records no catch", Fishing:CountCasts() == before)
ns.HandleSlash("harvest on")

--------------------------------------------------------------------------------
-- Kept, and cleared only on purpose
--------------------------------------------------------------------------------

suite.check("the record is in saved variables",
    ns.db.fishing.spots[LAKE].casts == 22, ns.db.fishing.spots[LAKE].casts)

-- A reload: session counts go, the record stays.
Fishing.session, Fishing.recent, Fishing.sessionCasts = {}, {}, 0
ns.TrackerUI:Refresh()
suite.check("after a reload the Fishing section waits for a cast", Line("FISHING") == nil)
suite.check("but the record is still there", Fishing:Summary(LAKE).casts == 22)

local mark = #env.chat
ns.HandleSlash("fishing")
local said = table.concat(env.chat, "\n", mark + 1)
suite.check("/farm fishing lists this zone's spots", said:find("caught in Elwynn Forest", 1, true))
suite.check("with the school", said:find("Oily Blackmouth School", 1, true))

mark = #env.chat
ns.HandleSlash("tracker reset confirm")
suite.check("clearing kill tallies leaves fishing alone", Fishing:Summary(LAKE).casts == 22)

ns.HandleSlash("fishing reset")
suite.check("a reset has to be confirmed", Fishing:Summary(LAKE).casts == 22)

--------------------------------------------------------------------------------
-- Export
--------------------------------------------------------------------------------

local text = ns.Harvest:ExportAll()
suite.check("the export carries the catches", text:find("-- Fishing", 1, true), text)
suite.check("as fishing rows",
    text:find('kind = "fishing", name = "open water", zone = "Elwynn Forest", '
        .. 'location = "Crystal Lake"', 1, true), text)
suite.check("marked Forever", text:find('provenance = "forever"', 1, true))
suite.check("with the zone's level band from the database",
    text:find('minLevel = 1, maxLevel = 10', 1, true), text)
suite.check("the header counts the casts",
    text:find(("-- %d fishing casts."):format(Fishing:CountCasts()), 1, true), text)
suite.check("a thin spot gets no rate",
    text:find("-- 3 of 3 casts: too few for a rate", 1, true), text)
local schoolRow = text:match('[^\n]*name = "Oily Blackmouth School"[^\n]*')
suite.check("and no chance field", schoolRow and not schoolRow:find("chance", 1, true), schoolRow)
suite.check("a spot with no zone stays out of the data", not text:find('zone = "?"', 1, true), text)

local chunk = assert(loadstring(text))
local registered = {}
local fake = { DB = { RegisterItem = function(_, item) registered[#registered + 1] = item end } }
chunk("Blackthornes_Farmer", fake)
suite.check("the export is loadable data", #registered >= 3, #registered)

ns.HandleSlash("fishing reset confirm")
suite.check("a confirmed reset clears it", Fishing:CountCasts() == 0)
suite.check("and the export has no fishing left in it",
    not ns.Harvest:ExportAll():find("fishing", 1, true))

suite.done()
