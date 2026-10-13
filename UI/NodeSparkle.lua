-- Blackthornes Farmer -- UI/NodeSparkle.lua
-- Gold sparkles over the herb or ore node you are facing.
--
-- The game tells addons nothing about the nodes around you: not where they
-- are, not where they sit on screen. The one it does name is the node the
-- interact key would pick, "softinteract": the one in front of you, close
-- by. With the game's own nameplate for that object turned on, the
-- nameplate is a frame that follows the node in the world, so a few
-- sparkles anchored above it stay on the node as you move.
--
-- The game's own icon over the object (SoftTargetIconGameObject,
-- SoftTargetIconInteract) is turned on with them; the sparkles gather round
-- it when the nameplate lets us read where it is.
--
-- So, while "Sparkle on nodes" is ticked (`nodeSparkle`, on unless
-- unticked; never rename it), Farmer turns on, out of combat, the two game
-- settings that make that nameplate (SoftTargetInteract to "always",
-- SoftTargetNameplateInteract on) and lets it look farther and all the way
-- round (SoftTargetInteractRange, SoftTargetInteractArc), keeping what each was in
-- `nodeSparkleCVars` (never rename it) and putting them back when the box
-- is unticked. Nothing is set that the player had already set that way.
--
-- A node is a herb or ore the data knows (a herb's own name, a vein's
-- source name), the client's name for that herb, or any node the player
-- has gathered (Gathering keeps the name the client gave). A hidden source
-- gets nothing. Fishing schools, chests and quest objects get nothing.
--
-- Smooth play: no OnUpdate and no timer. The soft target and nameplate
-- events say when to look again, the anchor makes it follow the node, and
-- the twinkle is an animation the game plays, only while it shows. Every
-- client value is read in a pcall. Nothing is written on a game frame: the
-- sparkles are Farmer's own frame, anchored to the nameplate, never
-- parented to it.

local _, ns = ...
local L = ns.L

local NodeSparkle = ns.NewModule("NodeSparkle")

local UNIT = "softinteract"

-- The game settings Farmer turns on, and to what.
NodeSparkle.CVARS = {
    { name = "SoftTargetInteract", value = "3", atLeast = 3 },
    { name = "SoftTargetNameplateInteract", value = "1", atLeast = 1 },
    -- How far the interact target looks, in yards (the game's own is about
    -- 10; it keeps its own limit if 100 is past it, and the check says what
    -- it took), and how wide: 2 is all the way round you, 1 only in front
    -- (the owner asked 2026-10-13 for 30, then for far more).
    { name = "SoftTargetInteractRange", value = "100", atLeast = 100 },
    { name = "SoftTargetInteractArc", value = "2", atLeast = 2 },
    -- The game's own icon over the object you face (the owner picked it
    -- 2026-10-13, once the probe showed Forever gave no nameplate without
    -- it). A client without one of these simply skips it.
    { name = "SoftTargetIconGameObject", value = "1", atLeast = 1 },
    { name = "SoftTargetIconInteract", value = "1", atLeast = 1 },
}

-- Where each sparkle sits round the node, in pixels from the anchor, how
-- big it is and when in the loop it lights.
NodeSparkle.SPARKS = {
    { x = -26, y = 10, size = 18, delay = 0.0 },
    { x = 24, y = 22, size = 14, delay = 0.5 },
    { x = 18, y = -8, size = 12, delay = 1.0 },
    { x = -12, y = -14, size = 10, delay = 0.8 },
    { x = 2, y = 34, size = 13, delay = 0.3 },
    { x = -30, y = 30, size = 9, delay = 1.2 },
}

NodeSparkle.TWINKLE = 0.8          -- seconds to light up, and again to fade
NodeSparkle.GOLD = { 1.0, 0.84, 0.36 }
NodeSparkle.GLOW = "Interface\\AddOns\\Blackthornes_Farmer\\Media\\Frame\\Glow"
-- A four-pointed star, drawn by tools/make_sparkle_art.py.
NodeSparkle.STAR = "Interface\\AddOns\\Blackthornes_Farmer\\Media\\Frame\\Sparkle"

local function Field(object, key)
    if type(object) ~= "table" then return nil end
    local ok, value = pcall(function() return object[key] end)
    if ok then return value end
    return nil
end

local function Readable(value)
    return ns.Harvest and ns.Harvest.Readable(value) or nil
end

local function InCombat()
    if type(InCombatLockdown) ~= "function" then return false end
    local ok, value = pcall(InCombatLockdown)
    return ok and value == true
end

function NodeSparkle:IsEnabled()
    return not (ns.db and ns.db.nodeSparkle == false)
end

--------------------------------------------------------------------------------
-- The game's settings
--------------------------------------------------------------------------------

function NodeSparkle.GetCVar(name)
    local cvar = _G.C_CVar
    local get = Field(cvar, "GetCVar") or _G.GetCVar
    if type(get) ~= "function" then return nil end
    local ok, value = pcall(get, name)
    if not ok or value == nil then return nil end
    return tostring(value)
end

function NodeSparkle.SetCVar(name, value)
    local cvar = _G.C_CVar
    local set = Field(cvar, "SetCVar") or _G.SetCVar
    if type(set) ~= "function" then return false end
    local ok, result = pcall(set, name, value)
    return ok and result ~= false
end

local function Saved()
    local db = ns.db
    if type(db.nodeSparkleCVars) ~= "table" then db.nodeSparkleCVars = {} end
    return db.nodeSparkleCVars
end

--- Turn on the game settings the sparkle needs, keeping what each was.
--- Out of combat only; in a fight it waits for the fight to end.
function NodeSparkle:ApplySettings()
    if not ns.db or not self:IsEnabled() then return false end
    if InCombat() then
        self.applyAfterCombat = true
        return false
    end
    self.applyAfterCombat = nil

    local saved = Saved()
    for _, cvar in ipairs(self.CVARS) do
        local now = self.GetCVar(cvar.name)
        if now ~= nil and (tonumber(now) or 0) < cvar.atLeast then
            if saved[cvar.name] == nil then saved[cvar.name] = now end
            self.SetCVar(cvar.name, cvar.value)
        end
    end
    return true
end

--- Put back what the player had before Farmer changed it.
function NodeSparkle:RestoreSettings()
    if not ns.db then return false end
    local saved = ns.db.nodeSparkleCVars
    if type(saved) ~= "table" or next(saved) == nil then return true end
    if InCombat() then
        self.restoreAfterCombat = true
        return false
    end
    self.restoreAfterCombat = nil

    for name, value in pairs(saved) do
        if self.SetCVar(name, value) then saved[name] = nil end
    end
    return true
end

function NodeSparkle:SetEnabled(on)
    ns.db.nodeSparkle = on and true or false
    if on then
        self.restoreAfterCombat = nil
        self:ApplySettings()
        self:Refresh()
    else
        self.applyAfterCombat = nil
        self:RestoreSettings()
        self:HideSparkle()
    end
end

--------------------------------------------------------------------------------
-- Which objects are nodes
--------------------------------------------------------------------------------

local names, namesKey = nil, nil

local function GatherCount()
    local gathering = ns.db and ns.db.gathering
    local nodes = type(gathering) == "table" and gathering.nodes
    if type(nodes) ~= "table" then return 0 end
    local count = 0
    for _ in pairs(nodes) do count = count + 1 end
    return count
end

local function Add(set, name)
    if type(name) == "string" and name ~= "" then set[name:lower()] = name end
end

--- Every node name Farmer knows, in lower case. Laid out again only when the
--- data, the client's names or the gathered nodes changed.
function NodeSparkle:Names()
    local DB = ns.DB
    local key = ("%s:%s:%d"):format(tostring(DB and DB.changes), tostring(DB and DB.namesVersion), GatherCount())
    if names and namesKey == key then return names end

    local set = {}
    if DB then
        for item in DB:Iterate() do
            for _, source in ipairs(item.sources or {}) do
                if source.kind == "herb" then
                    Add(set, item.name)
                    Add(set, DB:ClientName(item))
                elseif source.kind == "node" then
                    Add(set, source.name)
                end
            end
        end
    end

    local gathering = ns.db and ns.db.gathering
    if type(gathering) == "table" and type(gathering.nodes) == "table" then
        for _, entry in pairs(gathering.nodes) do
            if type(entry) == "table" and (entry.kind == "herb" or entry.kind == "ore") then
                Add(set, entry.node)
            end
        end
    end

    names, namesKey = set, key
    return set
end

function NodeSparkle:IsNode(name)
    if type(name) ~= "string" or name == "" then return false end
    if not self:Names()[name:lower()] then return false end
    if ns.DB and ns.DB:IsHiddenSource(name) then return false end
    return true
end

--- What the interact key points at: its guid, its name, and whether it is a
--- game object. Nil values where the client will not say.
function NodeSparkle:Facing()
    local guid, name
    if type(UnitGUID) == "function" then
        local ok, value = pcall(UnitGUID, UNIT)
        guid = ok and Readable(value) or nil
    end
    if type(UnitName) == "function" then
        local ok, value = pcall(UnitName, UNIT)
        name = ok and Readable(value) or nil
    end
    local object = type(guid) == "string" and guid:find("^GameObject%-") ~= nil
    return guid, name, object
end

--- The game's nameplate for the object, or nil.
function NodeSparkle:Plate(guid)
    local plates = _G.C_NamePlate
    local forUnit = Field(plates, "GetNamePlateForUnit")
    if type(forUnit) == "function" then
        local ok, plate = pcall(forUnit, UNIT)
        if ok and type(plate) == "table" then return plate end
    end

    -- Some clients give the object a nameplateN token instead.
    local all = Field(plates, "GetNamePlates")
    if not guid or type(all) ~= "function" then return nil end
    local ok, list = pcall(all)
    if not ok or type(list) ~= "table" then return nil end
    for _, plate in ipairs(list) do
        local token = Readable(Field(plate, "namePlateUnitToken"))
            or Readable(Field(Field(plate, "UnitFrame"), "unit"))
        if token and type(UnitGUID) == "function" then
            local read, value = pcall(UnitGUID, token)
            if read and Readable(value) == guid then return plate end
        end
    end
    return nil
end

--------------------------------------------------------------------------------
-- The sparkles
--------------------------------------------------------------------------------

local function Twinkle(texture, delay)
    local ok, group = pcall(texture.CreateAnimationGroup, texture)
    if not ok or type(group) ~= "table" then return nil end
    local made = pcall(function()
        group:SetLooping("REPEAT")
        local light = group:CreateAnimation("Alpha")
        light:SetFromAlpha(0)
        light:SetToAlpha(1)
        light:SetDuration(NodeSparkle.TWINKLE)
        light:SetStartDelay(delay)
        light:SetSmoothing("OUT")
        light:SetOrder(1)
        local fade = group:CreateAnimation("Alpha")
        fade:SetFromAlpha(1)
        fade:SetToAlpha(0)
        fade:SetDuration(NodeSparkle.TWINKLE)
        fade:SetSmoothing("IN")
        fade:SetOrder(2)
    end)
    return made and group or nil
end

--- One sparkle: a soft glow behind a four-pointed star.
local function MakeSpark(parent, spec)
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetSize(spec.size * 2, spec.size * 2)
    holder:SetPoint("CENTER", parent, "CENTER", spec.x, spec.y)

    local r, g, b = NodeSparkle.GOLD[1], NodeSparkle.GOLD[2], NodeSparkle.GOLD[3]
    local pieces = {
        { file = NodeSparkle.GLOW, w = spec.size, h = spec.size, a = 0.45 },
        { file = NodeSparkle.STAR, w = spec.size * 2, h = spec.size * 2, a = 1 },
    }
    for _, piece in ipairs(pieces) do
        local texture = holder:CreateTexture(nil, "OVERLAY")
        texture:SetTexture(piece.file)
        texture:SetSize(piece.w, piece.h)
        texture:SetPoint("CENTER")
        pcall(texture.SetBlendMode, texture, "ADD")
        texture:SetVertexColor(r, g, b, piece.a)
    end

    return { holder = holder, twinkle = Twinkle(holder, spec.delay) }
end

function NodeSparkle:Build()
    if self.frame then return self.frame end
    local frame = CreateFrame("Frame", "BlackthornesFarmerNodeSparkle", UIParent)
    frame:SetSize(80, 60)
    pcall(frame.SetFrameStrata, frame, "BACKGROUND")
    pcall(frame.EnableMouse, frame, false)
    frame:Hide()

    self.sparks = {}
    for index, spec in ipairs(self.SPARKS) do
        self.sparks[index] = MakeSpark(frame, spec)
    end
    self.frame = frame
    return frame
end

local function Moving()
    local level = ns.Motion and ns.Motion.Level and ns.Motion.Level() or "full"
    return level ~= "off"
end

--- The game's icon on the nameplate, when it has one we can read; the
--- sparkles gather round it. Read only: nothing is written on it.
function NodeSparkle.Icon(plate)
    local icon = Field(Field(plate, "UnitFrame"), "SoftTargetFrame")
    if type(icon) ~= "table" then return nil end
    local ok, kind = pcall(function() return icon:GetObjectType() end)
    if ok and type(kind) == "string" then return icon end
    return nil
end

function NodeSparkle:ShowSparkle(plate, guid)
    local frame = self:Build()
    if self.shownOn ~= plate then
        frame:ClearAllPoints()
        local icon = self.Icon(plate)
        if icon then
            -- Round the game's icon.
            frame:SetPoint("CENTER", icon, "CENTER", 0, 0)
        else
            -- Just above the node, under the name the game writes there.
            frame:SetPoint("BOTTOM", plate, "BOTTOM", 0, -10)
        end
    end
    self.shownOn, self.shownGuid = plate, guid

    local moving = Moving()
    for _, spark in ipairs(self.sparks) do
        local twinkle = spark.twinkle
        if twinkle and moving then
            spark.holder:SetAlpha(1)
            local ok, playing = pcall(twinkle.IsPlaying, twinkle)
            if not (ok and playing == true) then pcall(twinkle.Play, twinkle) end
        else
            if twinkle then pcall(twinkle.Stop, twinkle) end
            spark.holder:SetAlpha(0.85)
        end
    end
    frame:Show()
end

function NodeSparkle:HideSparkle()
    self.shownOn, self.shownGuid = nil, nil
    local frame = self.frame
    if not frame then return end
    for _, spark in ipairs(self.sparks or {}) do
        if spark.twinkle then pcall(spark.twinkle.Stop, spark.twinkle) end
    end
    frame:ClearAllPoints()
    frame:Hide()
end

--- Look again at what the interact key points at.
-- @return "shown", "off", "nothing", "notnode" or "noplate"
function NodeSparkle:Refresh()
    if not self:IsEnabled() then self:HideSparkle(); return "off" end
    local guid, name, object = self:Facing()
    if not guid or not object then self:HideSparkle(); return "nothing" end
    if not self:IsNode(name) then self:HideSparkle(); return "notnode" end
    local plate = self:Plate(guid)
    if not plate then self:HideSparkle(); return "noplate" end
    self:ShowSparkle(plate, guid)
    return "shown"
end

function NodeSparkle:SafeRefresh()
    local ok, outcome = pcall(self.Refresh, self)
    if not ok then
        pcall(self.HideSparkle, self)
        return "nothing"
    end
    return outcome
end

function NodeSparkle:OnPlateRemoved(unit)
    if not self.shownOn then return end
    local plates = _G.C_NamePlate
    local forUnit = Field(plates, "GetNamePlateForUnit")
    local gone = true
    if type(forUnit) == "function" then
        local ok, plate = pcall(forUnit, UNIT)
        gone = not (ok and plate == self.shownOn)
    end
    if gone or unit == UNIT then self:SafeRefresh() end
end

function NodeSparkle:OnEnable()
    ns.RegisterEvent(self, "PLAYER_SOFT_INTERACT_CHANGED", function() NodeSparkle:SafeRefresh() end)
    ns.RegisterEvent(self, "NAME_PLATE_UNIT_ADDED", function() NodeSparkle:SafeRefresh() end)
    ns.RegisterEvent(self, "NAME_PLATE_UNIT_REMOVED", function(_, _, unit) NodeSparkle:OnPlateRemoved(unit) end)
    ns.RegisterEvent(self, "PLAYER_REGEN_ENABLED", function()
        if NodeSparkle.applyAfterCombat then NodeSparkle:ApplySettings() end
        if NodeSparkle.restoreAfterCombat then NodeSparkle:RestoreSettings() end
    end)
    ns.RegisterEvent(self, "PLAYER_ENTERING_WORLD", function()
        if NodeSparkle:IsEnabled() then NodeSparkle:ApplySettings() end
    end)
end

-- A source hidden or shown again: the node under the sparkle may be one.
ns.DB.hideWatchers.nodeSparkle = function() NodeSparkle:SafeRefresh() end

--------------------------------------------------------------------------------
-- The check, for a report: face a node and run it.
--------------------------------------------------------------------------------

function NodeSparkle:Check()
    ns.Print("sparkle check (face a herb or ore node first):")
    ns.PrintRaw(("  setting: %s"):format(self:IsEnabled() and "on" or "off"))
    for _, cvar in ipairs(self.CVARS) do
        ns.PrintRaw(("  %s: %s"):format(cvar.name, tostring(self.GetCVar(cvar.name))))
    end
    local saved = ns.db and ns.db.nodeSparkleCVars
    if type(saved) == "table" then
        for name, value in pairs(saved) do
            ns.PrintRaw(("  kept to put back: %s = %s"):format(name, tostring(value)))
        end
    end
    ns.PrintRaw(("  C_NamePlate.GetNamePlateForUnit: %s"):format(
        type(Field(_G.C_NamePlate, "GetNamePlateForUnit")) == "function" and "yes" or "no"))

    local guid, name, object = self:Facing()
    local kind = type(guid) == "string" and guid:match("^(%a+)%-") or nil
    ns.PrintRaw(("  facing: %s (%s)"):format(tostring(name), tostring(kind or (guid and "?" or "nothing"))))
    ns.PrintRaw(("  a node Farmer knows: %s"):format(name and (self:IsNode(name) and "yes" or "no") or "-"))
    local plate = object and self:Plate(guid) or nil
    ns.PrintRaw(("  nameplate for it: %s"):format(object and (plate and "yes" or "no") or "-"))
    ns.PrintRaw(("  game icon on it: %s"):format(plate and (self.Icon(plate) and "yes" or "no") or "-"))
    local all = Field(_G.C_NamePlate, "GetNamePlates")
    if type(all) == "function" then
        local ok, list = pcall(all)
        ns.PrintRaw(("  nameplates showing: %s"):format(ok and type(list) == "table" and tostring(#list) or "?"))
    end
    ns.PrintRaw(("  sparkle: %s"):format(self:SafeRefresh()))
end

ns.RegisterCommand("sparkle", L["sparkles on the herb or ore node you face on or off (check)"], function(rest)
    local argument = ns.Util.Trim(rest or ""):lower()
    if argument == "check" then
        ns.KeepCheck("sparkle check", NodeSparkle.Check, NodeSparkle)
        return
    end
    local on
    if argument == "on" then on = true
    elseif argument == "off" then on = false
    else on = not NodeSparkle:IsEnabled() end
    NodeSparkle:SetEnabled(on)
    ns.Print(on and L["sparkles on nodes on."] or L["sparkles on nodes off."])
    if ns.SettingsUI then ns.SettingsUI:Refresh() end
end)
