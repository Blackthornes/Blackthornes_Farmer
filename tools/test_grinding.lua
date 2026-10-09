-- The Grind tab: where mobs of a level band and a kind gather.
--
-- What matters: only mobs the data or your own loot knows are listed, and
-- nothing is made up; a creature type comes from the game (learned when you
-- meet a mob, or shipped in the harvest file) and a mob nobody has seen is
-- left out of a type filter and counted; a mob confirmed on Forever drops
-- its Classic rows in that zone; camps are named places, or spots close
-- together, and point at a real mob's spot; the band follows your level
-- until you pick one, never past 30; the tab sits in the window, the
-- command and Settings reach it, and a camp points the arrow and shows on
-- the world map.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("grinding")
local check = suite.check

local ns = env.Load({ ui = true })
local Grinding, GrindingUI, GrindPins, UI = ns.Grinding, ns.GrindingUI, ns.GrindPins, ns.UI
local DB = ns.DB

env.world.zone = "Westfall"
env.world.subZone = ""

-- The player is level 25 in the test client.

--------------------------------------------------------------------------------
-- Test mobs, in a zone of their own so the seed data stays out of the way
--------------------------------------------------------------------------------

local ZONE = "Test Vale"

DB:RegisterItem({ name = "Test Cloth", category = "Cloth", sources = {
    { name = "Vale Bandit", zone = ZONE, location = "Bandit Camp", coords = { 40, 40 },
        minLevel = 24, maxLevel = 25, chance = 30 },
    { name = "Vale Thug", zone = ZONE, location = "Bandit Camp", coords = { 42, 41 },
        minLevel = 25, maxLevel = 26, chance = 20 },
    -- Classic says 30-31 here; Forever measured it lower, below.
    { name = "Vale Ghoul", zone = ZONE, location = "Old Crypt", minLevel = 30, maxLevel = 31 },
    { name = "Vale Ogre", zone = ZONE, minLevel = 40, maxLevel = 41 },
} })

DB:RegisterItem({ name = "Test Bone", category = "Misc", sources = {
    { name = "Vale Ghoul", zone = ZONE, location = "The Graves", coords = { 70, 20 },
        minLevel = 23, maxLevel = 24, provenance = "forever" },
} })

DB:RegisterItem({ name = "Test Hide", category = "Leatherworking", sources = {
    { kind = "skinning", name = "Vale Wolf", zone = ZONE, coords = { 10, 80 }, minLevel = 22, maxLevel = 24 },
    { kind = "skinning", name = "Vale Boar", zone = ZONE, coords = { 13, 82 }, minLevel = 23, maxLevel = 25 },
    { kind = "skinning", name = "Vale Bear", zone = ZONE, coords = { 60, 90 }, minLevel = 25, maxLevel = 26 },
    { kind = "node", name = "Not A Mob", zone = ZONE, minLevel = 25 },
} })

local function CampsIn(camps, zone)
    local found = {}
    for _, camp in ipairs(camps) do
        if camp.zone == zone then found[#found + 1] = camp end
    end
    return found
end

local function CampNamed(camps, label)
    for _, camp in ipairs(camps) do
        if camp.zone == ZONE and camp.label == label then return camp end
    end
end

local function Names(camp)
    local names = {}
    for _, mob in ipairs(camp and camp.mobs or {}) do names[#names + 1] = mob.name end
    return table.concat(names, ",")
end

--------------------------------------------------------------------------------
-- The level band
--------------------------------------------------------------------------------

local low, high = Grinding:Range()
check("the band follows your level", low == 23 and high == 27, low .. "-" .. high)
check("until one is picked", Grinding:FollowsLevel())

check("a picked band is swapped round", select(1, Grinding:SetRange(26, 22)) == 22)
low, high = Grinding:Range()
check("and kept", low == 22 and high == 26 and not Grinding:FollowsLevel(), low .. "-" .. high)
Grinding:SetRange(28, 45)
check("never past the level cap", select(2, Grinding:Range()) == 30)
Grinding:FollowLevel()
check("My level goes back to following", Grinding:FollowsLevel())

--------------------------------------------------------------------------------
-- Camps, any type
--------------------------------------------------------------------------------

local camps, unknown = Grinding:Camps({ low = 22, high = 26, type = false, gives = false })
local mine = CampsIn(camps, ZONE)

local bandit = CampNamed(camps, "Bandit Camp")
check("a named place is one camp", bandit and Names(bandit) == "Vale Bandit,Vale Thug", Names(bandit))
check("its band spans its mobs", bandit and bandit.minLevel == 24 and bandit.maxLevel == 26)
check("its spot is one of its mobs' own",
    bandit and (bandit.coords[1] == 40 or bandit.coords[1] == 42), bandit and bandit.coords[1])

local graves = CampNamed(camps, "The Graves")
check("a mob confirmed on Forever is listed at its Forever level", graves
    and graves.mobs[1].minLevel == 23 and graves.forever, Names(graves))
check("and its Classic row in that zone is gone", CampNamed(camps, "Old Crypt") == nil)

local pack
for _, camp in ipairs(mine) do
    if camp.mobs[1] and camp.mobs[1].name == "Vale Wolf" then pack = camp end
end
check("unnamed spots close together are one camp", pack and Names(pack) == "Vale Wolf,Vale Boar", Names(pack))
check("named by where it is", pack and pack.label:find("^around ") ~= nil, pack and pack.label)
check("a spot further off is a camp of its own", (function()
    for _, camp in ipairs(mine) do
        if Names(camp) == "Vale Bear" then return true end
    end
    return false
end)())

for _, camp in ipairs(mine) do
    for _, mob in ipairs(camp.mobs) do
        check("out of the band is left out: " .. mob.name, mob.name ~= "Vale Ogre")
        check("a node is not a mob", mob.name ~= "Not A Mob")
    end
end
check("busiest camps first", camps[1].count >= camps[#camps].count)

--------------------------------------------------------------------------------
-- What they give
--------------------------------------------------------------------------------

camps = Grinding:Camps({ low = 22, high = 26, type = false, gives = "skinning" })
for _, camp in ipairs(CampsIn(camps, ZONE)) do
    for _, mob in ipairs(camp.mobs) do
        check("skinning lists only skinning sources: " .. mob.name, mob.skinning == true)
    end
end

camps = Grinding:Camps({ low = 22, high = 26, type = false, gives = "cloth" })
check("cloth lists the cloth droppers", CampNamed(camps, "Bandit Camp") ~= nil)
check("and not a mob with no cloth", CampNamed(camps, "The Graves") == nil)

--------------------------------------------------------------------------------
-- Creature types: from the game, never guessed
--------------------------------------------------------------------------------

camps, unknown = Grinding:Camps({ low = 22, high = 26, type = "Humanoid", gives = false })
check("no type seen yet: none listed as humanoid", #CampsIn(camps, ZONE) == 0)
check("and they are counted", unknown >= 7, unknown)

-- Shipped types (the harvest file) ...
DB:CreatureTypes({ ["Vale Bandit"] = "Humanoid", ["Vale Wolf"] = "Beast", [""] = "Beast", ["Vale Boar"] = 7 })
check("shipped types are read", Grinding.TypeOf("Vale Bandit") == "Humanoid")
check("bad rows are skipped", Grinding.TypeOf("Vale Boar") == nil)

-- ... and ones met in game, which win.
local seenType = { ["Vale Thug"] = "Humanoid", ["Vale Wolf"] = "Beast", ["Vale Bear"] = "Beast",
    ["Vale Ghoul"] = "Undead", ["Some Guard"] = "Humanoid", ["Vale Boar"] = "Not specified" }
_G.UnitCreatureType = function(unit)
    return env.world.target and seenType[env.world.target.name]
end
local serial = 0
local function Meet(name)
    serial = serial + 1
    env.world.target = { name = name, level = 25, dead = false, guid = "Creature-0-0-0-0-" .. serial }
    ns.Harvest:NoteUnit("target")
end
for _, name in ipairs({ "Vale Thug", "Vale Wolf", "Vale Bear", "Vale Ghoul", "Some Guard", "Vale Boar" }) do
    Meet(name)
end

check("a mob met in game is learned", ns.db.creatureTypes["Vale Thug"] == "Humanoid")
check("\"Not specified\" is not a type", ns.db.creatureTypes["Vale Boar"] == nil)

_G.UnitCreatureType = function() error("secret") end
Meet("Vale Bandit")
check("a type the client will not hand over breaks nothing", ns.db.creatureTypes["Vale Bandit"] == nil)
_G.UnitCreatureType = nil
Meet("Vale Bandit")
check("nor a client without the call", Grinding.TypeOf("Vale Bandit") == "Humanoid")

ns.db.creatureTypes["Vale Bandit"] = "Undead"
check("what you saw beats what shipped", Grinding.TypeOf("Vale Bandit") == "Undead")
ns.db.creatureTypes["Vale Bandit"] = nil

camps, unknown = Grinding:Camps({ low = 22, high = 26, type = "Humanoid", gives = false })
check("humanoids: the bandit camp", Names(CampNamed(camps, "Bandit Camp")) == "Vale Bandit,Vale Thug",
    Names(CampNamed(camps, "Bandit Camp")))
check("and no undead", CampNamed(camps, "The Graves") == nil)

camps = Grinding:Camps({ low = 22, high = 26, type = "Beast", gives = false })
check("beasts: the wolf pack, the boar's type still unseen",
    #CampsIn(camps, ZONE) == 2 and pack ~= nil)

check("a type with no chip of its own is Other", Grinding.Chip("Giant") == "Other"
    and Grinding.Chip("Beast") == "Beast" and Grinding.Chip(nil) == nil)

--------------------------------------------------------------------------------
-- The export ships types for mobs the data knows, and nothing else
--------------------------------------------------------------------------------

local block, count = Grinding:ExportBlock()
check("the export writes the learned types", block and block:find('%["Vale Thug"%] = "Humanoid"') ~= nil, block)
check("not a mob outside the data", block and not block:find("Some Guard"), block)
check("as one call the data file runs", block and block:find("DB:CreatureTypes%(") ~= nil)
-- Equipment's and Pets' tools read the harvest file with only RegisterItem.
local okRun, errRun = pcall(function()
    local chunk = assert(loadstring("local DB = ... " .. block))
    chunk({ RegisterItem = function() end })
end)
check("a reader without CreatureTypes still loads it", okRun, errRun)
local shipped = {}
assert(loadstring("local DB = ... " .. block))({ CreatureTypes = function(_, map) shipped = map end })
check("and the addon reads it back", shipped["Vale Thug"] == "Humanoid")
check("counted", count == 4, count)

--------------------------------------------------------------------------------
-- Nearest first
--------------------------------------------------------------------------------

Grinding:SetNearFirst(true)
camps = Grinding:Camps({ low = 1, high = 30, type = false, gives = false })
check("nearest first: your own zone leads", camps[1].hops == 0, camps[1].zone)
Grinding:SetNearFirst(false)

--------------------------------------------------------------------------------
-- The command
--------------------------------------------------------------------------------

ns.HandleSlash("grind 15-20 humanoids cloth")
check("/farm grind sets the band", ns.db.grindMin == 15 and ns.db.grindMax == 20)
check("and the type", Grinding:Type() == "Humanoid")
check("and what they give", Grinding:Gives() == "cloth")
check("and opens the tab", UI.frame:IsShown() and UI.tab == "grind", UI.tab)
check("which is remembered", ns.db.lastTab == "grind")

ns.HandleSlash("grind any me")
check("any clears the filters", Grinding:Type() == nil and Grinding:Gives() == nil)
check("me follows your level", Grinding:FollowsLevel())

ns.HandleSlash("grind 31 40")
check("a typed band is held to the cap", ns.db.grindMin == 30 and ns.db.grindMax == 30)

--------------------------------------------------------------------------------
-- The tab
--------------------------------------------------------------------------------

check("the window has a Grind tab", UI.tabs.grind ~= nil)
Grinding:SetRange(22, 26)
UI:ShowTab("grind")
check("its view shows", UI.grindView:IsShown() and not UI.searchView:IsShown()
    and not UI.rankingsView:IsShown())

local rows = GrindingUI.list.data
local campRow, mobRow
for _, row in ipairs(rows) do
    if row.type == "camp" and row.camp.zone == ZONE and row.camp.label == "Bandit Camp" then campRow = row end
    if row.type == "mob" and row.mob.name == "Vale Thug" then mobRow = row end
end
check("a band per camp", campRow ~= nil)
check("its mobs under it", mobRow ~= nil)
check("a mob's type shows", mobRow and GrindingUI:MobTexts(mobRow.mob).type == "Humanoid")
check("an unseen type is a question mark", GrindingUI:MobTexts({ name = "Nobody", minLevel = 1 }).type == "?")
check("what it gives", mobRow and GrindingUI:MobTexts(mobRow.mob).gives == "Cloth")
check("the band names the place and level", GrindingUI.CampText(campRow.camp):find("Test Vale, Bandit Camp") ~= nil)

Grinding:SetType("Humanoid")
GrindingUI:Render()
local note
for _, row in ipairs(GrindingUI.list.data) do
    if row.type == "note" and row.text:find("nobody has seen") then note = row end
end
check("mobs left out by type are counted in the list", note ~= nil)
check("its chip is lit, and only it", (function()
    for _, chip in ipairs(GrindingUI.typeChips) do
        if chip.selected ~= (chip.filterKind == "Humanoid") then return false end
    end
    return true
end)())
Grinding:SetType(nil)

Grinding:SetRange(1, 1)
Grinding:SetGives("skinning")
Grinding:SetType("Demon")
GrindingUI:Render()
check("an empty band says so", GrindingUI.list.data[1].type == "note"
    and GrindingUI.list.data[1].text:find("level 1 to 1") ~= nil, GrindingUI.list.data[1].text)
Grinding:SetType(nil)
Grinding:SetGives(nil)
Grinding:SetRange(22, 26)
GrindingUI:Render()

--------------------------------------------------------------------------------
-- A camp points the arrow
--------------------------------------------------------------------------------

local printed = {}
local print0 = ns.Print
ns.Print = function(text) printed[#printed + 1] = text end
GrindingUI:OnRowClick(campRow)
ns.Print = print0

check("a click on a camp follows it", ns.Arrow.grind == campRow.camp)
check("and turns the arrow on", ns.Arrow.IsOn())
local following = ns.Arrow:Following()
check("the arrow follows the camp", following.grind == campRow.camp
    and following.item == "Test Vale, Bandit Camp", following.item)
check("and says where", printed[#printed] and printed[#printed]:find("Bandit Camp") ~= nil)

local targets = ns.Arrow:GrindTargets(campRow.camp, nil)
-- The test client has no map for Test Vale: one place, named for the camp,
-- rather than a point made up.
check("a camp off the maps is one place, never a made-up point", #targets == 1
    and targets[1].name == "Bandit Camp" and targets[1].x == nil, targets[1] and targets[1].name)

ns.db.goals = { list = { { item = "Copper Ore", target = 10, have = 0 } }, today = {} }
check("following a goal again lets the camp go", ns.Arrow:Follow("Copper Ore") and ns.Arrow.grind == nil)
ns.Arrow:Grind(campRow.camp)
check("the dial's click goes back to goals", ns.Arrow:NextGoal() and ns.Arrow.grind == nil)

--------------------------------------------------------------------------------
-- The world map
--------------------------------------------------------------------------------

check("the map shows what the tab lists", GrindPins.camps == GrindingUI.camps)
local onMap = GrindPins:CampsOn(ZONE)
check("camps with a spot, on their zone's map", #onMap >= 3, #onMap)
for _, camp in ipairs(onMap) do
    check("never one without a spot", type(camp.coords) == "table")
end
check("not on another zone's", #GrindPins:CampsOn("Durotar") == 0 or GrindPins:CampsOn("Durotar")[1].zone == "Durotar")

check("on unless turned off", GrindPins.IsOn())
ns.HandleSlash("grind pins off")
check("/farm grind pins off", not GrindPins.IsOn() and ns.db.grindPins == false)
check("draws nothing then", GrindPins:Draw() == 0)

--------------------------------------------------------------------------------
-- Settings
--------------------------------------------------------------------------------

local SettingsUI = ns.SettingsUI
SettingsUI:Show()
local controls = SettingsUI.controls
check("Settings shows the map switch as saved", controls.grindPins:GetChecked() == false)
controls.grindPins:GetScript("OnClick")(controls.grindPins)
check("and turns it back on", GrindPins.IsOn(), ns.db.grindPins)
UI:Hide()
controls.grindOpen:GetScript("OnClick")(controls.grindOpen, "LeftButton")
check("its Open button opens the tab", UI.frame:IsShown() and UI.tab == "grind")
SettingsUI:Hide()

suite.done()
