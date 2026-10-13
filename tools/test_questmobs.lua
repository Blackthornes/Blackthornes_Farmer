-- Your quest count beside quest mobs' names.
--
-- What matters: a mob whose tooltip carries an objective not yet met shows
-- that count beside its nameplate's name; else a quest log objective that
-- names it; a met count, a player, an object or a plain mob shows nothing;
-- a plate going away takes its count; a quest log change reads the plates
-- again; a secret value costs nothing worse; /farm questcount and the
-- Settings box turn it off and on.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("questmobs")

local ns = env.Load({ ui = true })
local QuestMobs = ns.QuestMobs

local units = {}       -- [token] = { guid, name, player, lines }
local plates = {}      -- [token] = frame
local realName, realGuid = _G.UnitName, _G.UnitGUID
_G.UnitGUID = function(unit) if units[unit] then return units[unit].guid end return realGuid(unit) end
_G.UnitName = function(unit) if units[unit] then return units[unit].name end return realName(unit) end
_G.UnitIsPlayer = function(unit) return units[unit] and units[unit].player or false end
_G.C_NamePlate = { GetNamePlateForUnit = function(unit) return plates[unit] end }
_G.C_TooltipInfo = { GetUnit = function(unit)
    local lines = {}
    for i, text in ipairs(units[unit] and units[unit].lines or {}) do lines[i] = { leftText = text } end
    return { lines = lines }
end }

local function Mob(token, name, lines, guid, player)
    units[token] = { name = name, lines = lines, guid = guid or ("Creature-0-1-2-3-2955-" .. token), player = player }
    plates[token] = plates[token] or CreateFrame("Frame")
    return QuestMobs:Update(token)
end

suite.check("on by default", ns.DEFAULTS.questMobCount == true)
suite.check("the tooltip's count shows", Mob("nameplate1", "Plainstrider", { "Plainstrider", "Level 8", "Plainstrider Beak: 3/8" }) == "3/8")
suite.check("beside the name", QuestMobs.CountIn("Plainstrider slain: 2/10") == "2/10")
suite.check("a count already met shows nothing", Mob("nameplate2", "Plainstrider", { "Plainstrider", "Plainstrider Beak: 8/8" }) == nil)
suite.check("a plain mob shows nothing", Mob("nameplate3", "Kodo", { "Kodo", "Level 9" }) == nil)
suite.check("a player shows nothing", Mob("nameplate4", "Bob", { "Bob", "Quest: 1/2" }, "Player-1-0001", true) == nil)
suite.check("an object shows nothing", Mob("nameplate5", "Peacebloom", { "Peacebloom", "1/2" }, "GameObject-0-1-2-3-1-0") == nil)
suite.check("a secret guid costs nothing worse", Mob("nameplate6", "Kodo", { "Kodo", "1/2" }, env.Secret("string")) == nil)

-- Not on the tooltip: the quest log names it.
_G.C_QuestLog = {
    GetNumQuestLogEntries = function() return 1 end,
    GetInfo = function() return { questID = 9 } end,
    GetQuestObjectives = function() return { { text = "Galak Centaur slain: 0/6", numFulfilled = 0, numRequired = 6, finished = false } } end,
}
suite.check("an objective in the log that names it", Mob("nameplate7", "Galak Centaur", { "Galak Centaur" }) == "0/6")

-- The plate goes; the count goes with it.
suite.check("it shows over the plate", QuestMobs:Shown(plates.nameplate1) == "3/8")
QuestMobs:Removed("nameplate1")
suite.check("a plate going away takes its count", QuestMobs:Shown(plates.nameplate1) == nil)

-- The quest log moves on: every plate is read again.
units.nameplate7.lines = { "Galak Centaur", "Galak Centaur slain: 1/6" }
QuestMobs:UpdateAll()
suite.check("read again after the log changes", QuestMobs:Update("nameplate7") == "1/6")

ns.HandleSlash("questcount")
suite.check("/farm questcount turns it off", ns.db.questMobCount == false)
suite.check("and nothing shows", QuestMobs:Update("nameplate7") == nil)
ns.HandleSlash("questcount on")
suite.check("/farm questcount on turns it on", ns.db.questMobCount == true)

ns.SettingsUI:Show()
local box = ns.SettingsUI.controls.questMobCount
suite.check("the settings page shows it on", box:GetChecked())
box:GetScript("OnClick")(box)
suite.check("unticking it turns it off", ns.db.questMobCount == false)
box:GetScript("OnClick")(box)
suite.check("and ticking it back on", ns.db.questMobCount == true)
ns.SettingsUI:Hide()

_G.C_QuestLog, _G.C_TooltipInfo = nil, nil
suite.done()
