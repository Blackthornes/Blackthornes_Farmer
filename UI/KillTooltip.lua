-- Blackthornes Farmer -- UI/KillTooltip.lua
-- One line on a mob's tooltip: how many of it you have killed.
--
--   Kills: 7/20                         (red, until drop rates unlock)
--   Kills: 134, worth 1s 20c each       (from 20 kills on)
--
-- Below Tracker.MIN_KILLS the count runs up toward it in red, from 0/20 on a
-- mob never killed. From there it is the whole count and what a kill is
-- worth, the same number the kills panel and Rankings give (Value:ForMob).
--
-- A kill is a corpse opened, as everywhere in Farmer (Logic/Tracker.lua),
-- and the tally is read only: hovering a mob never makes a tally for it.
-- A mob you can attack gets the line even at 0; a friendly one only once
-- you have killed it, and players, their pets and critters never get it.
--
-- Hooked the way the material line is (UI/ItemTooltip.lua): retail's
-- TooltipDataProcessor first, the older OnTooltipSetUnit script in case,
-- and a guard so the line goes on once. Only appended to the game's main
-- tooltip and the one a chat link opens. Every client value is read inside
-- a pcall, since a dungeon hands out names and guids that raise when used.

local _, ns = ...
local L = ns.L

local KillTooltip = ns.NewModule("KillTooltip")

local TOOLTIP_NAMES = { "GameTooltip", "ItemRefTooltip" }

-- A unit's tooltip is redrawn over and over while the mouse rests on it, so
-- a mob's worth is kept this long, as long as its kill count stays the same.
local KEEP_FOR = 10

-- The red of the count below 20, and the plain text of the rest, when the
-- theme is not loaded (the tests).
local RED = { 0.898, 0.376, 0.310 }
local WHITE = { 0.902, 0.910, 0.925 }

local function Field(object, key)
    if type(object) ~= "table" then return nil end
    local ok, value = pcall(function() return object[key] end)
    if ok then return value end
    return nil
end

local function Now()
    local ok, now = pcall(GetTime)
    if ok and type(now) == "number" then return now end
    return 0
end

local function Color(key, fallback)
    if ns.Theme and ns.Theme.Unpack then
        local ok, r, g, b = pcall(ns.Theme.Unpack, key)
        if ok and type(r) == "number" then return r, g, b end
    end
    return fallback[1], fallback[2], fallback[3]
end

function KillTooltip:IsEnabled()
    return not (ns.db and ns.db.killTooltip == false)
end

function KillTooltip:SetEnabled(on)
    ns.db.killTooltip = on and true or false
    KillTooltip.ForgetKept()
end

--- Is this one of the tooltips the line belongs on?
function KillTooltip:Wanted(tooltip)
    for _, name in ipairs(TOOLTIP_NAMES) do
        if _G[name] ~= nil and _G[name] == tooltip then return true end
    end
    return false
end

--------------------------------------------------------------------------------
-- Which mob
--------------------------------------------------------------------------------

--- A yes or no from the client, or nil when it will not say.
local function Ask(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, value = pcall(fn, ...)
    if not ok then return nil end
    local readable, answer = pcall(function() return value == true end)
    if readable then return answer end
    return nil
end

--- The unit token and guid a tooltip shows, however this client offers them.
function KillTooltip:UnitFor(tooltip, data)
    local unit
    local getUnit = Field(tooltip, "GetUnit")
    if type(getUnit) == "function" then
        local ok, _, token = pcall(getUnit, tooltip)
        if ok then unit = ns.Harvest.Readable(token) end
    end
    if not unit then
        local displayed = Field(_G.TooltipUtil, "GetDisplayedUnit")
        if type(displayed) == "function" then
            local ok, _, token = pcall(displayed, tooltip)
            if ok then unit = ns.Harvest.Readable(token) end
        end
    end

    local guid = ns.Harvest.Readable(Field(data, "guid"))
    if not guid and unit and type(UnitGUID) == "function" then
        local ok, value = pcall(UnitGUID, unit)
        guid = ok and ns.Harvest.Readable(value) or nil
    end
    return unit, guid
end

--- The name Farmer keeps this mob's kills under: the one the client gives,
--- else, where the client will not say (a dungeon), the one its mob ID is
--- known by, else "Creature #ID", as the harvest keeps it. Nothing is
--- written here; asking the game a name is left to the loot window.
function KillTooltip:MobName(unit, guid)
    if unit and type(UnitName) == "function" then
        local ok, value = pcall(UnitName, unit)
        local name = ok and ns.Harvest.Readable(value) or nil
        if name then return name end
    end
    local npcID = ns.Harvest.NpcID(guid)
    if not npcID then return nil end
    return ns.Harvest.KnownNpcName(npcID) or ("Creature #%d"):format(npcID)
end

--- Kills of a mob from the saved tally, 0 for one never killed.
function KillTooltip.Kills(name)
    local mobs = ns.db and type(ns.db.tracker) == "table" and ns.db.tracker.mobs
    local mob = type(mobs) == "table" and mobs[name]
    return type(mob) == "table" and tonumber(mob.kills) or 0
end

--- Is this something you would farm? A creature you can attack, not
--- another player's and not a critter. Nil when the client will not say.
function KillTooltip:Attackable(unit)
    if not unit then return nil end
    if Ask(_G.UnitIsPlayer, unit) then return false end
    if Ask(_G.UnitPlayerControlled, unit) then return false end

    if type(UnitCreatureType) == "function" and ns.Grinding then
        local ok, value = pcall(UnitCreatureType, unit)
        local kind = ok and ns.Harvest.Readable(value) or nil
        if ns.Grinding.EnglishType(kind) == "Critter" then return false end
    end

    return Ask(_G.UnitCanAttack, "player", unit)
end

--------------------------------------------------------------------------------
-- The line
--------------------------------------------------------------------------------

-- Worth already worked out: [mob name] = { kills, at, text }.
local kept = {}

function KillTooltip.ForgetKept()
    kept = {}
end

--- "1s 20c" in coin colours, "1s 20c (est.)" from the database's rates, or
--- nil when nothing it drops has a price.
function KillTooltip:Worth(name, kills)
    local entry = kept[name]
    local now = Now()
    if entry and entry.kills == kills and now - entry.at < KEEP_FOR then
        return entry.text or nil
    end

    local text
    local ok, value, details = pcall(ns.Value.ForMob, ns.Value, name)
    if ok and type(value) == "number" and value > 0 then
        text = ns.Value.Coins(value)
        if type(details) == "table" and details.basis == "database" then
            text = text .. L[" (est.)"]
        end
    end

    kept[name] = { kills = kills, at = now, text = text or false }
    return text
end

--- The line's text and whether it is the red count, or nil.
function KillTooltip:LineFor(name)
    local kills = KillTooltip.Kills(name)
    local need = ns.Tracker.MIN_KILLS

    if kills < need then
        return L.Format("Kills: %d/%d", kills, need), true
    end

    local worth = self:Worth(name, kills)
    if worth then return L.Format("Kills: %1$d, worth %2$s each", kills, worth), false end
    return L.Format("Kills: %d", kills), false
end

--------------------------------------------------------------------------------
-- Putting it on the tooltip
--------------------------------------------------------------------------------

-- Which tooltip already carries the line, for which mob and at what length.
local decorated = setmetatable({}, { __mode = "k" })

function KillTooltip.Forget(tooltip)
    decorated[tooltip] = nil
end

local function LineCount(tooltip)
    local numLines = Field(tooltip, "NumLines")
    if type(numLines) ~= "function" then return nil end
    local ok, count = pcall(numLines, tooltip)
    if ok and type(count) == "number" then return count end
    return nil
end

--- Put the line on a tooltip.
-- @return "added", "quiet" (nothing to say), "duplicate" or "nounit"
function KillTooltip:Decorate(tooltip, data)
    if not self:IsEnabled() then return "quiet" end
    if not self:Wanted(tooltip) then return "quiet" end
    if self.writing then return "duplicate" end

    local unit, guid = self:UnitFor(tooltip, data)
    if not guid or not ns.Harvest.NpcID(guid) then return "nounit" end

    local mark = decorated[tooltip]
    if mark and mark.guid == guid then
        local now = LineCount(tooltip)
        if not now or now >= mark.lines then return "duplicate" end
    end

    local name = self:MobName(unit, guid)
    if not name then return "nounit" end
    if ns.DB and ns.DB:IsHiddenSource(name) then return "quiet" end

    -- A mob you could farm, or one you already have.
    if KillTooltip.Kills(name) == 0 and self:Attackable(unit) ~= true then return "quiet" end

    local text, red = self:LineFor(name)
    local addLine = Field(tooltip, "AddLine")
    if type(addLine) ~= "function" then return "nounit" end

    local r, g, b
    if red then r, g, b = Color("loss", RED) else r, g, b = Color("text", WHITE) end

    self.writing = true
    pcall(addLine, tooltip, text, r, g, b)
    local show = Field(tooltip, "Show")
    if type(show) == "function" then pcall(show, tooltip) end
    self.writing = false

    decorated[tooltip] = { guid = guid, lines = LineCount(tooltip) or 0 }
    return "added"
end

--- Every hook comes through here, so one odd unit costs its line and never a
--- Lua error on hover.
function KillTooltip:OnTooltip(tooltip, data)
    local ok, outcome = pcall(self.Decorate, self, tooltip, data)
    if not ok then
        self.writing = false
        return "nounit"
    end
    return outcome
end

function KillTooltip:InstallDataProcessor()
    local processor = _G.TooltipDataProcessor
    local dataType = Field(Field(_G.Enum, "TooltipDataType"), "Unit")
    local add = Field(processor, "AddTooltipPostCall")
    if type(add) ~= "function" or dataType == nil then return false end

    return (pcall(add, dataType, function(tooltip, data)
        KillTooltip:OnTooltip(tooltip, data)
    end))
end

function KillTooltip:InstallScriptHooks()
    local installed = false
    for _, name in ipairs(TOOLTIP_NAMES) do
        local tooltip = _G[name]
        local hook = Field(tooltip, "HookScript")
        if type(hook) == "function" then
            if pcall(hook, tooltip, "OnTooltipSetUnit", function(shown)
                KillTooltip:OnTooltip(shown, nil)
            end) then
                installed = true
            end
            pcall(hook, tooltip, "OnTooltipCleared", function(shown)
                KillTooltip.Forget(shown)
            end)
        end
    end
    return installed
end

function KillTooltip:OnEnable()
    self.installed = {
        TooltipDataProcessor = self:InstallDataProcessor(),
        OnTooltipSetUnit = self:InstallScriptHooks(),
    }
end

-- Prices or "Hide skinning" moved: the kept worth was worked out before.
ns.DB.hideWatchers.killTooltip = function() KillTooltip.ForgetKept() end

ns.RegisterCommand("killcount", L["turn the kill count on mob tooltips on or off"], function()
    KillTooltip:SetEnabled(not KillTooltip:IsEnabled())
    ns.Print(KillTooltip:IsEnabled() and L["kill count on mob tooltips on."]
        or L["kill count on mob tooltips off."])
    if ns.SettingsUI then ns.SettingsUI:Refresh() end
end)
