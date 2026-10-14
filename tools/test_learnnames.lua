-- Names for mobs Forever added (a player's Ruins of Lordaeron kills showed
-- as "Creature #250488", 2026-10-14).
--
-- What matters: whenever the client lets a creature's name and guid both be
-- read (target, mouse, nameplate, tooltip), a mob ID the data cannot name
-- gets that name kept; an ID Classic's list already names is left alone;
-- the panel shows the name at once, and what was kept under the number is
-- moved to the name at the next login, nothing lost.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("learnnames")

local ns = env.Load({ ui = true })
local Harvest = ns.Harvest
-- A mob the shipped names do not name yet.
ns.FOREVER_NPC_NAMES = {}

local GHOUL = "Creature-0-4621-2999-76516-250488-0000CB0C4B"
local TROGG = "Creature-0-4621-389-76516-11318-000CCB0C4B"
local units = {}
_G.UnitGUID = function(unit) return units[unit] and units[unit].guid end
_G.UnitName = function(unit) return units[unit] and units[unit].name end
_G.UnitLevel = function() return 20 end
_G.UnitIsDead = function() return false end

ns.db.npcNames = nil
units.target = { guid = GHOUL, name = "Lordaeron Ghoul" }
suite.check("a new mob's name is learned from the target", Harvest:LearnName("target", true) == true)
suite.check("and kept by its ID", ns.db.npcNames[250488] == "Lordaeron Ghoul")
suite.check("once", Harvest:LearnName("target", true) == false)

units.target = { guid = TROGG, name = "Ragefire-Trogg" }
Harvest:LearnName("target", true)
suite.check("an ID Classic names keeps Classic's name", ns.db.npcNames[11318] == nil)

-- Name hidden, but the tooltip says it.
ns.db.npcNames = {}
units.mouseover = { guid = GHOUL, name = env.Secret("string") }
_G.C_TooltipInfo = { GetUnit = function(unit)
    if unit == "mouseover" then return { guid = GHOUL, lines = { { leftText = "Lordaeron Ghoul" } } } end
end }
suite.check("a hidden name is read off the tooltip", Harvest:LearnName("mouseover", true) == true
    and ns.db.npcNames[250488] == "Lordaeron Ghoul")

-- Both hidden: nothing is guessed.
ns.db.npcNames = {}
_G.C_TooltipInfo = nil
units.target = { guid = env.Secret("string"), name = env.Secret("string") }
suite.check("hidden everywhere, nothing is kept", Harvest:LearnName("target", true) == false
    and next(ns.db.npcNames) == nil)
suite.check("a number is never kept as a name", Harvest:KeepName(250488, "Creature #250488") == false)

-- Seen alive (a nameplate) teaches it too.
units.nameplate1 = { guid = GHOUL, name = "Lordaeron Ghoul" }
Harvest:NoteUnit("nameplate1")
suite.check("a nameplate teaches it", ns.db.npcNames[250488] == "Lordaeron Ghoul")

-- The panel shows it at once; the saved data moves at the next login.
suite.check("the panel shows the name", Harvest.ShowName("Creature #250488") == "Lordaeron Ghoul")
suite.check("a still unknown one keeps its number", Harvest.ShowName("Creature #250489") == "Creature #250489")
suite.check("a real name is shown as it is", Harvest.ShowName("Defias Thug") == "Defias Thug")

Harvest.records["Creature #250488|Ruins of Lordaeron|"] = {
    mob = "Creature #250488", zone = "Ruins of Lordaeron", corpses = 2, npc = 250488,
    items = { ["Linen Cloth"] = { name = "Linen Cloth", id = 2589, corpses = 1, count = 2 } },
}
ns.db.tracker = ns.db.tracker or {}
ns.db.tracker.mobs = ns.db.tracker.mobs or {}
ns.db.tracker.mobs["Creature #250488"] = { kills = 2, copper = 40, coinKills = 2,
    items = { ["Linen Cloth"] = 2 }, places = { ["Ruins of Lordaeron"] = 2 } }
Harvest:NameUnnamed()
local record = Harvest.records["Lordaeron Ghoul|Ruins of Lordaeron|"]
suite.check("the record takes the name", record and record.corpses == 2
    and Harvest.records["Creature #250488|Ruins of Lordaeron|"] == nil)
suite.check("with its drops", record and record.items["Linen Cloth"].count == 2)
local tally = ns.db.tracker.mobs["Lordaeron Ghoul"]
suite.check("the kill tally too", tally and tally.kills == 2 and ns.db.tracker.mobs["Creature #250488"] == nil)

-- A dungeon corpse after that is named, not numbered.
_G.GetRealZoneText = function() return "Ruins of Lordaeron" end
_G.GetSubZoneText = function() return "" end
units = {}
_G.UnitIsDead = function() return true end
env.world.loot = { { name = "Linen Cloth", id = 2589 } }
_G.GetLootSourceInfo = function(slot) if slot == 1 then return GHOUL, 1 end end
Harvest.opened = {}
Harvest:RecordCorpse()
suite.check("the next corpse goes under the name",
    Harvest.records["Lordaeron Ghoul|Ruins of Lordaeron|"].corpses == 3,
    Harvest.records["Lordaeron Ghoul|Ruins of Lordaeron|"].corpses)

-- The tooltip hook learns it too, the kill line on or off.
ns.db.npcNames = {}
ns.db.killTooltip = false
ns.KillTooltip:Learn({}, { guid = GHOUL, lines = { { leftText = "Lordaeron Ghoul" } } })
suite.check("a mob tooltip teaches it", ns.db.npcNames[250488] == "Lordaeron Ghoul")

suite.done()
