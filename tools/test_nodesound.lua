-- A sound when the light finds a node.
--
-- What matters: off unless picked; your character's "Follow me!" in its own
-- race and voice, the peon's line, or the map's ping; once a node and not
-- again too soon; never in a fight; never for your own bobber; a sound the
-- client won't play counts as not played; /farm sparkle sound and the
-- Settings drop-down pick it.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("nodesound")

local ns = env.Load({ ui = true })
local NodeSparkle = ns.NodeSparkle

local cvars = {}
_G.C_CVar = {
    GetCVar = function(name) return cvars[name] end,
    SetCVar = function(name, value) cvars[name] = tostring(value); return true end,
}
local fighting = false
_G.InCombatLockdown = function() return fighting end
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
_G.C_NamePlate = {
    GetNamePlateForUnit = function(unit)
        if unit == "softinteract" and facing.guid then return plate end
        return nil
    end,
}
local function Face(name, guid)
    facing = { name = name, guid = guid }
    return NodeSparkle:SafeRefresh()
end

local played, pinged = {}, {}
local willPlay = true
_G.PlaySound = function(kit, channel) pinged[#pinged + 1] = { kit, channel }; return willPlay end
_G.PlaySoundFile = function(id) played[#played + 1] = id; return willPlay end
_G.UnitRace = function() return "Orc", "Orc" end
_G.UnitSex = function() return 3 end
local clock = 100
_G.GetTime = function() return clock end

suite.check("off unless picked", NodeSparkle:Voice() == "off" and ns.db.nodeVoice == nil)
suite.check("no sound while off", not NodeSparkle:SayFound("g0", true) and #played == 0)
Face("Copper Vein", "GameObject-0-1-2-3-1731-0000000001")
suite.check("finding a node while off plays nothing", #played == 0 and #pinged == 0)

NodeSparkle:SetVoice("character")
suite.check("your character says follow me, in its own voice",
    NodeSparkle:SayFound("g1") and played[#played] == NodeSparkle.FOLLOW_ME.Orc[2])
suite.check("once a node", not NodeSparkle:SayFound("g1"))
clock = clock + 5
suite.check("and not again too soon", not NodeSparkle:SayFound("g2"))
clock = clock + NodeSparkle.VOICE_GAP
fighting = true
suite.check("never in a fight", not NodeSparkle:SayFound("g3"))
fighting = false
suite.check("a new node later speaks again", NodeSparkle:SayFound("g3"))

clock = clock + NodeSparkle.VOICE_GAP
local before = #played
suite.check("finding a vein plays it", Face("Tin Vein", "GameObject-0-1-2-3-1732-0000000002") == "shown"
    and #played == before + 1)
clock = clock + NodeSparkle.VOICE_GAP
before = #played
Face("Fishing Bobber", "GameObject-0-1-2-3-35591-0000000003")
suite.check("your bobber never plays it", #played == before)

NodeSparkle:SetVoice("peon")
suite.check("picking it plays the peon now", NodeSparkle:SayFound(nil, true) and played[#played] == NodeSparkle.PEON_READY)
NodeSparkle:SetVoice("ping")
local fileCount = #played
suite.check("the ping plays the map's ping, not a voice file",
    NodeSparkle:SayFound(nil, true) and pinged[#pinged][1] == NodeSparkle.PING_KIT
    and pinged[#pinged][2] == "SFX" and #played == fileCount)

willPlay = false
NodeSparkle.saidGuid, NodeSparkle.saidAt = nil, nil
suite.check("a sound the client won't play is not counted", not NodeSparkle:SayFound("g9")
    and NodeSparkle.saidAt == nil)
willPlay = true

_G.UnitRace = function() return "Skyborne", "Skyborne" end
_G.UnitSex = function() return 2 end
NodeSparkle:SetVoice("character")
suite.check("a race with no line falls back to a human's", NodeSparkle:VoiceFile() == NodeSparkle.FOLLOW_ME.Human[1])
NodeSparkle:SetVoice("loud")
suite.check("anything else is off", ns.db.nodeVoice == "off")

ns.HandleSlash("sparkle sound peon")
suite.check("the command picks the peon", ns.db.nodeVoice == "peon")
ns.HandleSlash("sparkle sound")
suite.check("the command alone steps to the next", ns.db.nodeVoice == "ping")
ns.HandleSlash("sparkle sound off")
suite.check("and off again", ns.db.nodeVoice == "off")

ns.SettingsUI:Show()
local control = ns.SettingsUI.controls and ns.SettingsUI.controls.nodeVoice
suite.check("Settings has the drop-down", control ~= nil)
if control then
    ns.db.nodeVoice = "character"
    ns.SettingsUI:Refresh()
    suite.check("it shows the pick", control:GetValue() == 2)
    control:Pick(3)
    suite.check("picking in Settings saves it", ns.db.nodeVoice == "peon")
end
ns.SettingsUI:Hide()

suite.done()
