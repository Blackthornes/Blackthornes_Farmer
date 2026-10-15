-- Blackthornes Farmer -- UI/KillPlates.lua
-- Your kill count to the left of a mob's nameplate, as its tooltip has it.
--
--   7/20 [Plainstrider]           (red, until drop rates unlock at 20)
--   134 [Plainstrider]            (your kills from 20 on)
--   134  1s 20c [Plainstrider]    (with "Worth on nameplates" ticked)
--   134 (crown) [Plainstrider]    (from 100 kills, the kills panel's mark)
--
-- A player asked, the owner said build it (2026-10-15). The numbers are
-- the tooltip's own (KillTooltip.Kills, KillTooltip:Worth), so the two
-- never disagree, and the worth only shows from 20 of your own kills,
-- never from the database's rates. "Kill count on nameplates"
-- (`killPlates`, on unless unticked) and "Worth on nameplates"
-- (`killPlatesWorth`, off unless ticked) on the Map & goals page, account
-- wide, never rename either; `/farm plates [on|off|worth on|off]`.
--
-- Which mobs: the same as the tooltip. A creature you can attack, or one
-- you have killed; never a player, a pet or a critter, and never a hidden
-- mob. Only where the game lets addons read a nameplate (not inside
-- dungeons), and only the plates the player has turned on.
--
-- Nothing is written on a game frame: each count is Farmer's own frame on
-- UIParent, anchored to the left of the nameplate's name (or the plate),
-- never parented to it, as UI/QuestMobs.lua does on the right. Smooth play:
-- a plate is read when it appears, and again only when a mob of the same
-- name is killed, a setting changes or the hide list moves; the worth is
-- the tooltip's kept answer, and the text is set only when it changed. No
-- OnUpdate, no ticker. Every client value is read in a pcall.

local _, ns = ...
local L = ns.L

local KillPlates = ns.NewModule("KillPlates")

local labels = {}      -- [plate] = { frame, text, shown }
local plateOf = {}     -- [unit token] = plate
local nameOf = {}      -- [unit token] = the mob's name, as its kills are kept

local RED = "ffe5604f"
local WHITE = "ffe6e8ec"

local function Field(object, key)
    if type(object) ~= "table" then return nil end
    local ok, value = pcall(function() return object[key] end)
    if ok then return value end
    return nil
end

function KillPlates:IsEnabled()
    return not (ns.db and ns.db.killPlates == false)
end

function KillPlates:WorthEnabled()
    return self:IsEnabled() and ns.db and ns.db.killPlatesWorth == true or false
end

--------------------------------------------------------------------------------
-- The text
--------------------------------------------------------------------------------

--- What to show for a mob of this name, from its kills.
function KillPlates:TextFor(name)
    local Tooltip = ns.KillTooltip
    local kills = Tooltip.Kills(name)
    local need = ns.Tracker.MIN_KILLS
    if kills < need then
        return ("|c%s%d/%d|r"):format(RED, kills, need)
    end
    local text = ("|c%s%d|r"):format(WHITE, kills)
    if self:WorthEnabled() then
        local ok, entry = pcall(Tooltip.Read, Tooltip, name, kills)
        if ok and type(entry) == "table" and entry.text and not entry.estimate then
            text = text .. "  " .. entry.text
        end
    end
    -- The crown you earned on this mob, next to its name.
    local crown = Tooltip.Crown(kills)
    if crown then text = text .. " " .. crown end
    return text
end

--- The mob over `unit` and its text, or nil: a creature you could farm or
--- have killed, not hidden.
function KillPlates:Read(unit)
    if type(UnitGUID) ~= "function" then return nil end
    local ok, value = pcall(UnitGUID, unit)
    local guid = ok and ns.Harvest.Readable(value) or nil
    if type(guid) ~= "string" or not ns.Harvest.NpcID(guid) then return nil end
    if not (guid:find("^Creature%-") or guid:find("^Vehicle%-")) then return nil end

    local Tooltip = ns.KillTooltip
    local name = Tooltip:MobName(unit, guid)
    if not name then return nil end
    if ns.DB and ns.DB:IsHiddenSource(name) then return nil end
    if Tooltip.Kills(name) == 0 and Tooltip:Attackable(unit) ~= true then return nil end
    return name, self:TextFor(name)
end

--------------------------------------------------------------------------------
-- The labels
--------------------------------------------------------------------------------

local function PlateFor(unit)
    local forUnit = Field(_G.C_NamePlate, "GetNamePlateForUnit")
    if type(forUnit) ~= "function" then return nil end
    local ok, plate = pcall(forUnit, unit)
    if ok and type(plate) == "table" then return plate end
    return nil
end

--- The nameplate's name text, when the game lets us read it.
local function NameText(plate)
    local name = Field(Field(plate, "UnitFrame"), "name")
    if type(name) ~= "table" then return nil end
    local ok, kind = pcall(function() return name:GetObjectType() end)
    if ok and kind == "FontString" then return name end
    return nil
end

local function Label(plate)
    local entry = labels[plate]
    if entry then return entry end
    local frame = CreateFrame("Frame", nil, UIParent)
    frame:SetSize(80, 16)
    pcall(frame.EnableMouse, frame, false)
    local text = ns.Theme.CreateLabel(frame, "normal", "text")
    text:SetPoint("RIGHT")
    pcall(text.SetJustifyH, text, "RIGHT")
    pcall(text.SetShadowOffset, text, 1, -1)
    frame:Hide()
    entry = { frame = frame, text = text }
    labels[plate] = entry
    return entry
end

function KillPlates:Show(plate, text)
    local entry = Label(plate)
    if entry.shown ~= text then
        entry.text:SetText(text)
        entry.shown = text
    end
    if not entry.placed then
        entry.frame:ClearAllPoints()
        local name = NameText(plate)
        if name then
            entry.frame:SetPoint("RIGHT", name, "LEFT", -4, 0)
        else
            entry.frame:SetPoint("RIGHT", plate, "LEFT", -2, 0)
        end
        entry.placed = true
    end
    entry.frame:Show()
end

--- The text showing over a plate, or nil.
function KillPlates:Shown(plate)
    local entry = plate and labels[plate]
    return entry and entry.frame:IsShown() and entry.shown or nil
end

function KillPlates:Hide(plate)
    local entry = plate and labels[plate]
    if not entry then return end
    entry.frame:Hide()
    entry.frame:ClearAllPoints()
    entry.placed, entry.shown = nil, nil
end

--- Read one plate's mob again.
-- @return the text shown, or nil
function KillPlates:Update(unit)
    local plate = PlateFor(unit)
    local old = plateOf[unit]
    if old and old ~= plate then self:Hide(old) end
    plateOf[unit], nameOf[unit] = plate, nil
    if not plate then return nil end
    local name, text
    if self:IsEnabled() then name, text = self:Read(unit) end
    nameOf[unit] = name
    if text then self:Show(plate, text) else self:Hide(plate) end
    return text
end

function KillPlates:Removed(unit)
    local plate = plateOf[unit]
    plateOf[unit], nameOf[unit] = nil, nil
    self:Hide(plate)
end

--- Every plate showing, read again.
function KillPlates:UpdateAll()
    for unit in pairs(plateOf) do self:Update(unit) end
end

--- A kill moved this mob's count: only plates of that name are read again.
function KillPlates:Killed(name)
    if not self:IsEnabled() or type(name) ~= "string" then return end
    for unit, shown in pairs(nameOf) do
        if shown == name then self:Update(unit) end
    end
end

function KillPlates:SetEnabled(on)
    ns.db.killPlates = on and true or false
    self:UpdateAll()
end

function KillPlates:SetWorthEnabled(on)
    ns.db.killPlatesWorth = on and true or false
    self:UpdateAll()
end

local function Safe(fn)
    return function(...)
        local ok = pcall(fn, ...)
        return ok
    end
end

function KillPlates:OnEnable()
    ns.RegisterEvent(self, "NAME_PLATE_UNIT_ADDED", Safe(function(_, _, unit)
        if type(unit) == "string" then KillPlates:Update(unit) end
    end))
    ns.RegisterEvent(self, "NAME_PLATE_UNIT_REMOVED", Safe(function(_, _, unit)
        if type(unit) == "string" then KillPlates:Removed(unit) end
    end))
end

ns.DB.hideWatchers.killPlates = function() KillPlates:UpdateAll() end

ns.RegisterCommand("plates", L["your kill count beside mobs' nameplates on or off"], function(rest)
    local argument = ns.Util.Trim(rest or ""):lower()
    local worth, value = argument:match("^(worth)%s*(%a*)$")
    if worth then
        local on
        if value == "on" then on = true
        elseif value == "off" then on = false
        else on = not (ns.db.killPlatesWorth == true) end
        KillPlates:SetWorthEnabled(on)
        ns.Print(on and L["worth on nameplates on."] or L["worth on nameplates off."])
    else
        local on
        if argument == "on" then on = true
        elseif argument == "off" then on = false
        else on = not KillPlates:IsEnabled() end
        KillPlates:SetEnabled(on)
        ns.Print(on and L["kill count on nameplates on."] or L["kill count on nameplates off."])
    end
    if ns.SettingsUI then ns.SettingsUI:Refresh() end
end)
