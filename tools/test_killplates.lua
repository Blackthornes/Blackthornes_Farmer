-- Your kill count beside mobs' nameplates.
--
-- What matters: a mob you can attack shows 0/20 in red to the left of its
-- nameplate and counts up as it is killed; from 20 kills it shows the
-- whole count, and the worth only with "Worth on nameplates" ticked and
-- only from your own kills; friendly NPCs, players, pets, critters, objects
-- and hidden mobs get nothing; a kill reads only plates of that mob again;
-- a plate going away takes its count; a secret value costs nothing worse;
-- /farm plates and the Settings boxes turn it off and on.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("killplates")

local ns = env.Load({ ui = true })
local KillPlates = ns.KillPlates

_G.GetTime = function() return 1000 end

local units = {}       -- [token] = { guid, name, player, pet, friendly, kind }
local plates = {}      -- [token] = frame
local realName, realGuid = _G.UnitName, _G.UnitGUID
_G.UnitGUID = function(unit) if units[unit] then return units[unit].guid end return realGuid(unit) end
_G.UnitName = function(unit) if units[unit] then return units[unit].name end return realName(unit) end
_G.UnitIsPlayer = function(unit) return units[unit] and units[unit].player or false end
_G.UnitPlayerControlled = function(unit) return units[unit] and units[unit].pet or false end
_G.UnitCanAttack = function(_, unit) return units[unit] ~= nil and not units[unit].friendly end
_G.UnitCreatureType = function(unit) return units[unit] and (units[unit].kind or "Beast") or nil end
_G.C_NamePlate = { GetNamePlateForUnit = function(unit) return plates[unit] end }

local reads = 0
local realForMob = ns.Value.ForMob
ns.Value.ForMob = function(_, name)
    reads = reads + 1
    if name == "Plainstrider" then return 120, { basis = "tally", priced = {} } end
    if name == "Kodo" then return 300, { basis = "database", priced = {} } end
    return nil
end

local serial = 0
local function Mob(token, name, extra)
    serial = serial + 1
    local unit = { name = name, guid = ("Creature-0-1-2-3-%d-%08d"):format(2955, serial) }
    for key, value in pairs(extra or {}) do unit[key] = value end
    units[token] = unit
    plates[token] = plates[token] or CreateFrame("Frame")
    return KillPlates:Update(token)
end

ns.db.tracker = ns.db.tracker or {}
ns.db.tracker.mobs = ns.db.tracker.mobs or {}

local function Kills(name, kills)
    ns.db.tracker.mobs[name] = { kills = kills, items = {} }
    ns.KillTooltip.ForgetKept()
end

local function Plain(text)
    return text and text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "") or nil
end

suite.check("on by default", ns.DEFAULTS.killPlates == true)
suite.check("the worth is off by default", ns.DEFAULTS.killPlatesWorth == false)

suite.check("a mob never killed shows 0/20", Plain(Mob("nameplate1", "Plainstrider")) == "0/20")
suite.check("in red", (Mob("nameplate1", "Plainstrider") or ""):find("^|cffe5604f") ~= nil)
Kills("Plainstrider", 7)
suite.check("it counts up", Plain(Mob("nameplate1", "Plainstrider")) == "7/20")
suite.check("it shows over the plate", Plain(KillPlates:Shown(plates.nameplate1)) == "7/20")

Kills("Plainstrider", 64)
suite.check("from 20 it's the whole count", Plain(Mob("nameplate1", "Plainstrider")) == "64")

ns.db.killPlatesWorth = true
local withWorth = Plain(Mob("nameplate1", "Plainstrider")) or ""
suite.check("with the worth ticked, the worth follows", withWorth:find("^64  ") ~= nil and #withWorth > 5, withWorth)
local before = reads
Mob("nameplate2", "Plainstrider")
suite.check("a second plate uses the kept worth", reads == before, reads - before)
Kills("Kodo", 40)
suite.check("never a worth from the database's rates", Plain(Mob("nameplate3", "Kodo")) == "40")
ns.db.killPlatesWorth = false

suite.check("a friendly NPC never killed shows nothing", Mob("nameplate4", "Innkeeper", { friendly = true }) == nil)
suite.check("a player shows nothing", Mob("nameplate5", "Bob", { player = true, guid = "Player-1-0001" }) == nil)
suite.check("a pet shows nothing", Mob("nameplate6", "Wolf", { pet = true }) == nil)
suite.check("a critter shows nothing", Mob("nameplate7", "Rabbit", { kind = "Critter" }) == nil)
suite.check("an object shows nothing", Mob("nameplate8", "Peacebloom", { guid = "GameObject-0-1-2-3-1-0" }) == nil)
suite.check("a secret guid costs nothing worse", Mob("nameplate9", "Kodo", { guid = env.Secret("string") }) == nil)

ns.DB:Hide("source", "Kodo")
suite.check("a hidden mob shows nothing", KillPlates:Shown(plates.nameplate3) == nil)
ns.DB:Unhide("source", "Kodo")
suite.check("and comes back when shown again", Plain(KillPlates:Shown(plates.nameplate3)) == "40")

-- A kill: only plates of that mob are read again.
Kills("Plainstrider", 65)
local updated = {}
local realUpdate = KillPlates.Update
KillPlates.Update = function(self, unit) updated[#updated + 1] = unit; return realUpdate(self, unit) end
KillPlates:Killed("Plainstrider")
KillPlates.Update = realUpdate
suite.check("a kill reads only that mob's plates", #updated == 2, #updated)
suite.check("and they show the new count", Plain(KillPlates:Shown(plates.nameplate2)) == "65")

-- The crown Farmer gave you on a mob shows beside its name too.
Kills("Plainstrider", 99)
suite.check("no crown before the 100th kill", Plain(Mob("nameplate1", "Plainstrider")) == "99")
Kills("Plainstrider", 100)
KillPlates:Killed("Plainstrider")
local crowned = KillPlates:Shown(plates.nameplate1) or ""
suite.check("the 100th kill puts the crown on its plate",
    crowned:find(ns.TrackerUI.CROWN, 1, true) ~= nil, crowned)
suite.check("after the count, next to the name", crowned:sub(-#ns.TrackerUI.CROWN) == ns.TrackerUI.CROWN, crowned)
Kills("Plainstrider", 250)
local laurel = Mob("nameplate1", "Plainstrider") or ""
suite.check("the laurel comes with it from 250", laurel:find("Laurel", 1, true) ~= nil, laurel)
Kills("Plainstrider", 1000)
local bane = Mob("nameplate1", "Plainstrider") or ""
suite.check("the legendary crown at 1000", bane:find(ns.TrackerUI.LEGENDARY_CROWN, 1, true) ~= nil, bane)
Kills("Plainstrider", 65)
Mob("nameplate1", "Plainstrider")

KillPlates:Removed("nameplate2")
suite.check("a plate going away takes its count", KillPlates:Shown(plates.nameplate2) == nil)

ns.HandleSlash("plates")
suite.check("/farm plates turns it off", ns.db.killPlates == false)
suite.check("and nothing shows", KillPlates:Shown(plates.nameplate1) == nil)
ns.HandleSlash("plates on")
suite.check("/farm plates on turns it on", ns.db.killPlates == true)
ns.HandleSlash("plates worth on")
suite.check("/farm plates worth on turns the worth on", ns.db.killPlatesWorth == true)
ns.HandleSlash("plates worth off")
suite.check("/farm plates worth off turns it off", ns.db.killPlatesWorth == false)

ns.SettingsUI:Show()
local box = ns.SettingsUI.controls.killPlates
suite.check("the settings page shows it on", box:GetChecked())
box:GetScript("OnClick")(box)
suite.check("unticking it turns it off", ns.db.killPlates == false)
box:GetScript("OnClick")(box)
suite.check("and ticking it back on", ns.db.killPlates == true)
local worthBox = ns.SettingsUI.controls.killPlatesWorth
suite.check("the worth box starts unticked", not worthBox:GetChecked())
worthBox:GetScript("OnClick")(worthBox)
suite.check("ticking it turns the worth on", ns.db.killPlatesWorth == true)
ns.SettingsUI:Hide()

ns.Value.ForMob = realForMob
_G.C_NamePlate = nil
suite.done()
