-- Rares and Treasures: the shipped list, the Grind tab's two views, the map
-- pins, the search rows, and Last seen / Killed from your own play. Never a
-- drop rate; the three Map settings are off until ticked.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("rares")
local check = suite.check

local ns = env.Load({ ui = true })
local Rares, DB = ns.Rares, ns.DB

--------------------------------------------------------------------------------
-- The shipped list
--------------------------------------------------------------------------------

local rares, treasures = Rares:Entries("rare"), Rares:Entries("treasure")
check("rares load", #rares > 300, #rares)
check("treasures load", #treasures > 50, #treasures)

local badSpot, noName = 0, 0
for _, list in ipairs({ rares, treasures }) do
    for _, entry in ipairs(list) do
        if entry.kind == "rare" and not entry.name then noName = noName + 1 end
        for _, spot in ipairs(entry.spots) do
            if not (spot.zone and spot.x > 0 and spot.x < 100 and spot.y > 0 and spot.y < 100) then
                badSpot = badSpot + 1
            end
        end
    end
end
check("every spot is in a zone, on the map", badSpot == 0, badSpot)
check("every rare has a name", noName == 0, noName)

local boahn
for _, entry in ipairs(rares) do if entry.name == "Boahn" then boahn = entry end end
check("Boahn is a rare in The Barrens", boahn and boahn.zone == "The Barrens" and boahn.low == 20)
check("with what it can drop, named", boahn and Rares.ItemsText(boahn):find("Boahn's Fang", 1, true) ~= nil,
    boahn and Rares.ItemsText(boahn))

-- The search names the rare, with no rate.
local fang = DB:GetItem("Boahn's Fang")
local lead
for _, source in ipairs(fang and fang.sources or {}) do
    if source.name == "Boahn" then lead = source end
end
check("the search finds Boahn's Fang on Boahn", lead ~= nil)
check("never with a drop rate", lead and lead.chance == nil)

local rated = 0
for _, item in pairs(DB.items) do
    for _, source in ipairs(item.sources) do
        if source.rare and source.chance then rated = rated + 1 end
    end
end
check("no rare row carries a rate", rated == 0, rated)

--------------------------------------------------------------------------------
-- The lists
--------------------------------------------------------------------------------

local list, here = Rares:List("rare", "The Barrens", 22)
check("The Barrens lists its own rares", here and #list > 5, #list)
local onlyHere = true
for _, entry in ipairs(list) do
    if not Rares.InZone(entry, "The Barrens") then onlyHere = false end
end
check("and only those", onlyHere)
check("near your level first", Rares.LevelGap(list[1], 22) <= Rares.NEAR)
local sawFar = false
local nearAfterFar = false
for _, entry in ipairs(list) do
    local near = Rares.LevelGap(entry, 22) <= Rares.NEAR
    if not near then sawFar = true elseif sawFar then nearAfterFar = true end
end
check("no near rare after a far one", not nearAfterFar)

local all, inZone = Rares:List("rare", "Nowhere Land", 30)
check("a zone with none lists every rare", not inZone and #all == #rares)

local chests = Rares:List("treasure", nil, nil)
check("treasures list", #chests == #treasures)

--------------------------------------------------------------------------------
-- Last seen and Killed, from your own play
--------------------------------------------------------------------------------

local guid = ("Creature-0-1-1-1-%d-0000000001"):format(boahn.id)
check("never seen at first", Rares.SeenText(boahn) == "Never seen")

local played = 0
_G.PlaySound = function() played = played + 1; return true end

env.world.target = { name = "Boahn", level = 20, dead = false, guid = guid }
Rares:NoteUnit("target")
check("targeting it: seen today", Rares.SeenText(boahn) == "Seen today", Rares.SeenText(boahn))
check("saved account wide", type(ns.db.rareLog.seen[boahn.id]) == "number")
check("no sound while Rare Seen Sound is off", played == 0)

ns.db.rareLog.seen[boahn.id] = nil
Rares:SetSound(true)
Rares:NoteUnit("target")
check("with it on, a sound", played == 1, played)
Rares:NoteUnit("target")
check("but not twice in a row", played == 1, played)

ns.db.rareLog.seen[boahn.id] = nil
ns.SharedChoices:SetMute(true)
check("muted", ns.Muted())
Rares:NoteUnit("target")
check("Mute All Sounds quiets it", played == 1, played)
ns.SharedChoices:SetMute(false)
Rares:SetSound(false)

-- A guid a dungeon will not let us read never breaks it.
env.world.target = { name = "Boahn", guid = env.Secret("guid") }
local ok = pcall(Rares.NoteUnit, Rares, "target")
check("a secret guid is left alone", ok)

-- The live game's secret guid is a string: joining it works, indexing it
-- raises (Sunken Temple and Blackfathom Deeps, on every hover).
do
    local secretGuid, undo = env.SecretString("guid")
    env.world.target = { name = "Boahn", guid = secretGuid }
    local okTarget, errTarget = pcall(Rares.NoteUnit, Rares, "target")
    local okNpc, npc = pcall(ns.Harvest.NpcID, secretGuid)
    local okRead, read = pcall(ns.Harvest.Readable, secretGuid)
    local okSeen, errSeen = pcall(ns.Harvest.NoteUnit, ns.Harvest, "target")
    local okPlate, errPlate = true, nil
    if ns.KillPlates and ns.KillPlates.Read then
        okPlate, errPlate = pcall(ns.KillPlates.Read, ns.KillPlates, "target")
    end
    undo()
    check("the mob seen alive skips a secret guid", okSeen, errSeen)
    check("the kill count by a nameplate skips it", okPlate and errPlate == nil, errPlate)
    check("a secret string guid raises nothing", okTarget, errTarget)
    check("and notes nothing", okTarget and errTarget == false, errTarget)
    check("NpcID leaves a secret guid alone", okNpc and npc == nil, npc)
    check("Readable refuses a secret string", okRead and read == nil, read)
end

-- Looting it is a kill.
env.Loot(ns, { name = "Boahn", level = 20, dead = true, guid = guid }, { { name = "Boahn's Fang", id = 5423 } })
ns.Tracker:OnLoot()
check("looted: killed today", Rares.SeenText(boahn) == "Killed today", Rares.SeenText(boahn))
check("the hover says so", Rares.TipText(boahn) == "You killed it today.")
-- Hovering the corpse after is no sighting (a bug pass, 2026-11-28: the
-- line went back to "Seen today" and the seen sound could play).
Rares:SetSound(true)
local playedBefore = played
env.world.target = { name = "Boahn", level = 20, dead = true, guid = guid }
check("a corpse is not noted", Rares:NoteUnit("target") == false)
check("killed stays killed", Rares.SeenText(boahn) == "Killed today", Rares.SeenText(boahn))
check("and no seen sound for a corpse", played == playedBefore, played)
Rares:SetSound(false)
_G.UnitIsDead = function() return env.Secret("dead") end
env.world.target = { name = "Boahn", level = 20, dead = false, guid = guid }
check("a secret dead answer raises nothing", pcall(Rares.NoteUnit, Rares, "target"))
_G.UnitIsDead = function(unit)
    if unit ~= "target" then return false end
    return env.world.target ~= nil and env.world.target.dead ~= false
end
check("a few days later", Rares.When(Rares.Clock() - 3 * 86400 - 60) == "3 days ago", Rares.When(Rares.Clock() - 3 * 86400 - 60))

-- A chest you loot is opened.
local chest = treasures[1]
check("a chest starts never opened", Rares.SeenText(chest) == "Never opened")
check("opened by its guid", Rares:NoteOpened(("GameObject-0-1-1-1-%d-0000000002"):format(chest.id)))
check("opened today", Rares.SeenText(chest) == "Opened today", Rares.SeenText(chest))
check("a mob's guid opens no chest", not Rares:NoteOpened(guid))

--------------------------------------------------------------------------------
-- Settings: off until ticked
--------------------------------------------------------------------------------

check("rares off the map at first", not Rares.PinsOn("rare"))
check("treasures off the map at first", not Rares.PinsOn("treasure"))
check("the sound off at first", ns.db.rareSound == nil)
check("no pins while off", #ns.RarePins.On(1413) == 0)
Rares:SetPins("rare", true)
local pins = ns.RarePins.On(1413)
check("ticked: The Barrens' rares get pins", #pins > 5, #pins)
check("only rares", pins[1].entry.kind == "rare")
Rares:SetPins("treasure", true)
check("and chests with the other tick", #ns.RarePins.On(chest.spots[1].map) > 0)
Rares:SetPins("rare", false)
Rares:SetPins("treasure", false)
check("unticked, saved as nothing", ns.db.rarePins == nil and ns.db.treasurePins == nil)
check("the settings are on the reset list", (function()
    local keys = {}
    for _, key in ipairs(ns.SettingsUI.SETTING_KEYS) do keys[key] = true end
    return keys.rarePins and keys.treasurePins and keys.rareSound
end)())

--------------------------------------------------------------------------------
-- The Grind tab
--------------------------------------------------------------------------------

local UI, GrindingUI, Grinding = ns.UI, ns.GrindingUI, ns.Grinding
env.world.zone = "The Barrens"
Grinding:SetGives("rares")
check("Rares is a Grind view", GrindingUI.Layout() == "rares")
check("no camps worked out for it", #(Grinding:Camps()) == 0)
UI:ShowTab("grind")
local view = ns.RaresView
check("the Rares view shows", view.frame:IsShown())
check("over the list", not GrindingUI.list:IsShown())
check("its line names your zone", view.head:GetText():find("The Barrens", 1, true) ~= nil, view.head:GetText())
check("rows for The Barrens' rares", #view.list.data > 5, #view.list.data)
check("headed RARE", view.nameHeading:GetText() == "RARE")

local row = view.list.rows[1]
check("a row has its name, level and Show Way", row and row.name:GetText() ~= "" and row.button ~= nil)
local boahnRow
for _, each in ipairs(view.list.rows) do
    if each.data == boahn then boahnRow = each end
end
if boahnRow then
    check("Boahn's row says it was killed", boahnRow.seen:GetText() == "Killed today", boahnRow.seen:GetText())
    check("and where, with what it drops", boahnRow.sub:GetText():find("49.1, 33.9", 1, true) ~= nil,
        boahnRow.sub:GetText())
end

view:ShowWay(boahn)
check("Show Way points the arrow at it", ns.Arrow.grind and ns.Arrow.grind.rare == boahn)
check("at its spot", ns.Arrow.grind.mobs[1].coords[1] == 49.1)

Grinding:SetGives("treasures")
GrindingUI:Render()
check("Treasures is its own view", view.kind == "treasure" and view.nameHeading:GetText() == "TREASURE")

Grinding:SetGives("cloth")
GrindingUI:Render()
check("back on Cloth the list returns", not view.frame:IsShown() and GrindingUI.list:IsShown())

suite.done()
