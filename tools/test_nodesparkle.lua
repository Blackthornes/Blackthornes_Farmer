-- Sparkles on the herb or ore node you face.
--
-- What matters: a herb or vein the interact key points at sparkles, over the
-- game's nameplate for it; a mob, a chest, a hidden node or no nameplate
-- gets nothing; turning it on sets the game's two settings only where they
-- were lower, keeping the old values, and turning it off puts them back; in
-- a fight the settings wait; a secret guid costs nothing worse than the
-- sparkle; /farm sparkle and the Settings box turn it off and on.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("nodesparkle")

local ns = env.Load({ ui = true })
local NodeSparkle = ns.NodeSparkle

-- The game's settings.
local cvars = { SoftTargetInteract = "1", SoftTargetNameplateInteract = "0", SoftTargetInteractRange = "10", SoftTargetInteractArc = "0",
    SoftTargetIconGameObject = "0", SoftTargetIconInteract = "0" }
local sets = 0
_G.C_CVar = {
    GetCVar = function(name) return cvars[name] end,
    SetCVar = function(name, value) cvars[name] = tostring(value); sets = sets + 1; return true end,
}
local fighting = false
_G.InCombatLockdown = function() return fighting end

-- What the interact key points at, and its nameplate.
local facing = {}
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
local plateShown = true
_G.C_NamePlate = {
    GetNamePlateForUnit = function(unit)
        if unit == "softinteract" and facing.guid and plateShown then return plate end
        return nil
    end,
}

local function Face(name, guid)
    facing = { name = name, guid = guid }
    return NodeSparkle:SafeRefresh()
end

local VEIN = "GameObject-0-1-2-3-1731-0000ABCDEF"

suite.check("on by default", ns.DEFAULTS.nodeSparkle == true)

suite.check("a copper vein sparkles", Face("Copper Vein", VEIN) == "shown")
suite.check("the sparkle shows", NodeSparkle.frame and NodeSparkle.frame:IsShown())
suite.check("a herb the data knows sparkles", Face("Peacebloom", VEIN) == "shown")
suite.check("any case", Face("peacebloom", VEIN) == "shown")
suite.check("a mob does not", Face("Kobold Vermin", "Creature-0-1-2-3-6-0000000001") == "nothing")
suite.check("and the sparkle goes", not NodeSparkle.frame:IsShown())
suite.check("a chest does not", Face("Battered Chest", VEIN) == "notnode")
suite.check("facing nothing", Face(nil, nil) == "nothing")

-- A node the player gathered that the data does not know (say, Forever's).
ns.db.gathering = ns.db.gathering or {}
ns.db.gathering.nodes = ns.db.gathering.nodes or {}
ns.db.gathering.nodes["Elwynn Forest||Silberblatt"] = { node = "Silberblatt", kind = "herb", gathers = 3, items = {} }
suite.check("a node you gathered sparkles, in the client's language", Face("Silberblatt", VEIN) == "shown")

-- With the game's icon on the nameplate, the sparkles gather round it.
local icon = CreateFrame("Frame")
icon.GetObjectType = function() return "Frame" end
plate.UnitFrame = { SoftTargetFrame = icon }
NodeSparkle:HideSparkle()
suite.check("round the game's icon", Face("Copper Vein", VEIN) == "shown" and NodeSparkle.Icon(plate) == icon)
plate.UnitFrame = nil
suite.check("no icon to read, still a sparkle", NodeSparkle.Icon(plate) == nil)

plateShown = false
suite.check("no nameplate, no sparkle", Face("Copper Vein", VEIN) == "noplate")
plateShown = true

ns.DB:Hide("source", "Copper Vein")
suite.check("a hidden node does not", Face("Copper Vein", VEIN) == "notnode")
ns.DB:Unhide("source", "Copper Vein")

suite.check("a secret guid costs nothing worse", Face("Copper Vein", env.Secret("string")) == "nothing")

-- The game's settings.
NodeSparkle:SetEnabled(true)
suite.check("turns on the interact target", cvars.SoftTargetInteract == "3", cvars.SoftTargetInteract)
suite.check("and its nameplate", cvars.SoftTargetNameplateInteract == "1")
suite.check("looks farther", cvars.SoftTargetInteractRange == "100")
suite.check("and all the way round", cvars.SoftTargetInteractArc == "2")
suite.check("turns on the game's icon over objects", cvars.SoftTargetIconGameObject == "1" and cvars.SoftTargetIconInteract == "1")
suite.check("keeping what they were", ns.db.nodeSparkleCVars.SoftTargetInteract == "1"
    and ns.db.nodeSparkleCVars.SoftTargetNameplateInteract == "0")

local before = sets
NodeSparkle:ApplySettings()
suite.check("nothing set twice", sets == before)

NodeSparkle:SetEnabled(false)
suite.check("off puts them back", cvars.SoftTargetInteract == "1" and cvars.SoftTargetNameplateInteract == "0"
    and cvars.SoftTargetInteractRange == "10" and cvars.SoftTargetInteractArc == "0"
    and cvars.SoftTargetIconGameObject == "0" and cvars.SoftTargetIconInteract == "0")
suite.check("and forgets them", next(ns.db.nodeSparkleCVars) == nil)
suite.check("off shows nothing", Face("Copper Vein", VEIN) == "off")

cvars.SoftTargetInteract = "3"
NodeSparkle:SetEnabled(true)
suite.check("a setting already on is left alone", ns.db.nodeSparkleCVars.SoftTargetInteract == nil)
NodeSparkle:SetEnabled(false)
suite.check("and stays on after", cvars.SoftTargetInteract == "3")
cvars.SoftTargetInteract = "1"

fighting = true
NodeSparkle:SetEnabled(true)
suite.check("in a fight nothing is set", cvars.SoftTargetInteract == "1")
fighting = false
NodeSparkle:ApplySettings()
suite.check("after the fight it is", cvars.SoftTargetInteract == "3")

-- The command and the Settings box.
ns.HandleSlash("sparkle")
suite.check("/farm sparkle turns it off", ns.db.nodeSparkle == false)
suite.check("and puts the settings back", cvars.SoftTargetInteract == "1")
ns.HandleSlash("sparkle on")
suite.check("/farm sparkle on turns it on", ns.db.nodeSparkle == true)

ns.SettingsUI:Show()
local box = ns.SettingsUI.controls.nodeSparkle
suite.check("the settings page shows it on", box:GetChecked())
box:GetScript("OnClick")(box)
suite.check("unticking it turns it off", ns.db.nodeSparkle == false)
box:GetScript("OnClick")(box)
suite.check("and ticking it back on", ns.db.nodeSparkle == true)

ns.HandleSlash("sparkle check")
suite.check("the check is kept for a report", ns.db.lastProbe and ns.db.lastProbe.check == "sparkle check")

ns.SettingsUI:Hide()

suite.done()
