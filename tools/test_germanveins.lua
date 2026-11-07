-- Beams on a German client, and "My Professions Only" for the beams.
--
-- What matters: a vein the data knows only in English ("Copper Vein") still
-- lights up on a German client ("Kupfervorkommen") when the game's tooltip
-- names the skill under its name ("Benötigt Bergbau"), and its colour takes
-- the tooltip's number; herbs, by the client's item name, keep working; the
-- name line alone never counts; a creature or a hidden name is no node; a
-- German skinnable corpse is told by the game's own word. With "My
-- Professions Only" off (the default) every herb, vein and school lights up
-- for any character; ticked, only those for the skills this character knows,
-- while chests, quest things and the bobber never wait, and a character
-- whose skills the client won't give sees everything.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("germanveins")

local ns = env.Load({ ui = true, locale = "deDE" })
local NodeSparkle = ns.NodeSparkle

local saved = { GetProfessions = _G.GetProfessions, GetProfessionInfo = _G.GetProfessionInfo, C_TooltipInfo = _G.C_TooltipInfo,
    C_NamePlate = _G.C_NamePlate, C_CVar = _G.C_CVar, InCombatLockdown = _G.InCombatLockdown, UNIT_SKINNABLE_LEATHER = _G.UNIT_SKINNABLE_LEATHER,
    C_TradeSkillUI = _G.C_TradeSkillUI }
local cvars = { SoftTargetInteract = "3", SoftTargetNameplateInteract = "1", SoftTargetInteractRange = "15", SoftTargetInteractArc = "2",
    SoftTargetIconGameObject = "1", SoftTargetIconInteract = "1" }
_G.C_CVar = {
    GetCVar = function(name) return cvars[name] end,
    SetCVar = function(name, value) cvars[name] = tostring(value); return true end,
}
_G.InCombatLockdown = function() return false end
-- The client's German skill names by skill line, as a German client gives
-- them whether or not the character knows the skill.
local GERMAN_LINES = { [186] = "Bergbau", [2946] = "Bergbau", [182] = "Kräuterkunde", [2944] = "Kräuterkunde", [356] = "Angeln" }
_G.C_TradeSkillUI = { GetProfessionInfoBySkillLineID = function(line)
    return GERMAN_LINES[line] and { professionName = GERMAN_LINES[line] } or nil
end }

-- What the interact key points at, its nameplate and its tooltip.
local facing, tipLines = {}, nil
local plate = CreateFrame("Frame")
local realName, realGuid = _G.UnitName, _G.UnitGUID
_G.UnitName = function(unit)
    if unit == "softinteract" then return facing.name end
    return realName(unit)
end
_G.UnitGUID = function(unit)
    if unit == "softinteract" then return facing.guid end
    return realGuid(unit)
end
_G.C_NamePlate = {
    GetNamePlateForUnit = function(unit)
        if unit == "softinteract" and facing.guid then return plate end
        return nil
    end,
}
_G.C_TooltipInfo = { GetUnit = function(unit)
    if unit == "softinteract" and tipLines then return { lines = tipLines } end
    return nil
end }

-- The Professions book: German names, by skill line.
local book = {}
_G.GetProfessions = function() return book[1] and 1 or nil, book[2] and 2 or nil end
_G.GetProfessionInfo = function(index)
    local entry = book[index]
    if not entry then return nil end
    return entry[1], nil, entry[3] or 1, 300, 0, 0, entry[2]
end
local MINING = { "Bergbau", 186, 80 }
local HERBS = { "Kräuterkunde", 182, 40 }
local FISHING = { "Angeln", 356, 20 }

-- Each face is a fresh object, so the tooltip is read again.
local serial = 0
local function Face(name, lines, guid)
    serial = serial + 1
    facing = { name = name, guid = guid or ("GameObject-0-1-2-3-1731-%010d"):format(serial) }
    tipLines = lines
    NodeSparkle.known = nil
    return NodeSparkle:SafeRefresh()
end

local function Vein(need)
    return { { leftText = "Kupfervorkommen" }, { leftText = need and ("Benötigt Bergbau (%d)"):format(need) or "Benötigt Bergbau" } }
end

book = { MINING }
suite.check("a German vein is not known by name", not NodeSparkle:IsNode("Kupfervorkommen"))
suite.check("a German vein lights up from its tooltip", Face("Kupfervorkommen", Vein(1)) == "shown")
suite.check("and the beam shows", NodeSparkle.frame and NodeSparkle.frame:IsShown())
suite.check("the tooltip's skill is kept in English", NodeSparkle.tipSkill == "Mining" and NodeSparkle.tipNeed == 1)
suite.check("without a tooltip it still gets nothing", Face("Kupfervorkommen", nil) == "notnode")
suite.check("the name line alone never counts", Face("Bergbau", { { leftText = "Bergbau" } }) == "notnode")
suite.check("a line with no skill word does not count", Face("Briefkasten", { { leftText = "Briefkasten" }, { leftText = "Post abholen" } }) == "notnode")
suite.check("a creature is never a node", Face("Kobold", Vein(1), "Creature-0-1-2-3-6-0000000001") ~= "shown")

-- The skill word from the Professions book alone (Gathering.ClientNames
-- reads spell names the test client does not give).
book = { HERBS }
suite.check("a herb's skill word from the book", Face("Wilder Strauch", { { leftText = "Wilder Strauch" }, { leftText = "Benötigt Kräuterkunde" } }) == "shown"
    and NodeSparkle.tipSkill == "Herbalism")
suite.check("a herb the data knows still lights up", Face("Peacebloom", nil) == "shown")

-- Colour from the tooltip's number.
local C = NodeSparkle.COLORS
local realSkills = ns.Spots.Skills
local skills = { Mining = 80 }
ns.Spots.Skills = function() return skills end
book = { MINING }
Face("Kupfervorkommen", Vein(65))
suite.check("a German vein takes its colour from the tooltip", NodeSparkle.tint == C.orange)
Face("Kupfervorkommen", Vein(1))
suite.check("far past it is green", NodeSparkle.tint == C.green)
skills = { Herbalism = 50 }
Face("Kupfervorkommen", Vein(65))
suite.check("without Mining it is grey and still shows", NodeSparkle.tint == C.grey and NodeSparkle.frame:IsShown())
Face("Kupfervorkommen", Vein(nil))
suite.check("no number is gold", NodeSparkle.tint == NodeSparkle.GOLD)
ns.Spots.Skills = realSkills

-- A hidden name stays hidden.
ns.DB:Hide("source", "Kupfervorkommen")
suite.check("a hidden German vein gets nothing", Face("Kupfervorkommen", Vein(1)) == "notnode")
ns.DB:Unhide("source", "Kupfervorkommen")

-- My Professions Only.
suite.check("off by default", ns.DEFAULTS.nodeSparkleMine == false)
book = {}
suite.check("off: a vein lights up with no professions", Face("Kupfervorkommen", Vein(1)) == "shown")
suite.check("off: a herb too", Face("Peacebloom", nil) == "shown")
suite.check("off: a school too", Face("Oily Blackmouth School", nil) == "shown")
ns.HandleSlash("sparkle mine on")
suite.check("on is saved", ns.db.nodeSparkleMine == true)
suite.check("on: no vein without Mining", Face("Kupfervorkommen", Vein(1)) == "notnode"
    and not NodeSparkle.frame:IsShown())
suite.check("on: no data vein without Mining", Face("Copper Vein", nil) == "notnode")
suite.check("on: no herb without Herbalism", Face("Peacebloom", nil) == "notnode")
suite.check("on: no school without Fishing", Face("Oily Blackmouth School", nil) == "notnode")
suite.check("on: a chest still shines", Face("Battered Chest", nil) == "shown")
suite.check("on: the bobber still shines", Face("Fishing Bobber", nil) == "shown")
book = { MINING }
suite.check("on: a vein with Mining", Face("Kupfervorkommen", Vein(1)) == "shown")
suite.check("on: a data vein with Mining", Face("Copper Vein", nil) == "shown")
suite.check("on: still no herb", Face("Peacebloom", nil) == "notnode")
book = { MINING, HERBS }
suite.check("on: a herb with Herbalism", Face("Peacebloom", nil) == "shown")
book = { FISHING }
suite.check("on: a school with Fishing", Face("Oily Blackmouth School", nil) == "shown")
ns.db.gathering = ns.db.gathering or {}
ns.db.gathering.nodes = ns.db.gathering.nodes or {}
ns.db.gathering.nodes["test|Silberblatt"] = { node = "Silberblatt", kind = "herb" }
book = { MINING }
suite.check("on: a herb you gathered by its German name waits for Herbalism", Face("Silberblatt", nil) == "notnode")
book = { HERBS }
suite.check("on: and shows with it", Face("Silberblatt", nil) == "shown")
ns.db.gathering.nodes["test|Silberblatt"] = nil
local realProfessions = _G.GetProfessions
_G.GetProfessions = nil
suite.check("on: skills the client won't give show everything", Face("Kupfervorkommen", Vein(1)) == "shown")
_G.GetProfessions = realProfessions
ns.SettingsUI:Show()
suite.check("Settings shows it ticked", ns.SettingsUI.controls.nodeSparkleMine
    and ns.SettingsUI.controls.nodeSparkleMine:GetChecked())
ns.HandleSlash("sparkle mine off")
suite.check("off again", ns.db.nodeSparkleMine == false)
book = {}
suite.check("off again: every vein shines", Face("Kupfervorkommen", Vein(1)) == "shown")

-- A German skinnable corpse, by the game's own word.
_G.UNIT_SKINNABLE_LEATHER = "Kürschnerbar"
local realDead, realLevel = _G.UnitIsDead, _G.UnitLevel
_G.UnitIsDead = function(unit) if unit == "softinteract" then return true end return realDead and realDead(unit) end
_G.UnitLevel = function(unit) if unit == "softinteract" then return 12 end return realLevel and realLevel(unit) end
ns.Spots.Skills = function() return { Skinning = 60 } end
ns.HandleSlash("sparkle corpses on")
suite.check("a German skinnable corpse shines", Face("Wildschwein", { { leftText = "Wildschwein" }, { leftText = "Kürschnerbar" } },
    "Creature-0-1-2-3-3099-0000000002") == "shown")
ns.Spots.Skills = function() return {} end
suite.check("not without Skinning", Face("Wildschwein", { { leftText = "Wildschwein" }, { leftText = "Kürschnerbar" } },
    "Creature-0-1-2-3-3099-0000000003") ~= "shown")
ns.Spots.Skills = realSkills
ns.HandleSlash("sparkle corpses off")
_G.UnitIsDead, _G.UnitLevel = realDead, realLevel

-- Put the game back for the suites after this one.
_G.UnitName, _G.UnitGUID = realName, realGuid
for _, key in ipairs({ "GetProfessions", "GetProfessionInfo", "C_TooltipInfo", "C_NamePlate", "C_CVar", "InCombatLockdown",
    "UNIT_SKINNABLE_LEATHER", "C_TradeSkillUI" }) do
    _G[key] = saved[key]
end
ns.SettingsUI:Hide()

suite.done()
