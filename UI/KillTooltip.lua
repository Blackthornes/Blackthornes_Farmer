-- Blackthornes Farmer -- UI/KillTooltip.lua
-- One line on a mob's tooltip: how many of it you have killed.
--
--   Kills: 7/20                         (red, until drop rates unlock)
--   Kills: 134, worth 1s 20c each       (from 20 kills on)
--
--   Best drops                          (gold; from 20 kills on, from
--   Linen Cloth 41%              52c     the player's own rates only)
--
-- Under it, the three drops that add most to a kill's worth: how often each
-- drops times its price, the same entries Value:ForMob adds up, so they come
-- for nothing once the worth is kept. "Best drops" (killTooltipDrops) turns
-- them off.
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

-- How many drops the tooltip names, and the muted grey of their chance.
KillTooltip.TOP_DROPS = 3
local MUTED = "ff9aa0ab"

-- The red of the count below 20, and the plain text of the rest, when the
-- theme is not loaded (the tests).
local RED = { 0.898, 0.376, 0.310 }
local WHITE = { 0.902, 0.910, 0.925 }
local GOLD = { 1, 0.82, 0 }

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

--- The tooltip's line for a mob with `kills` of yours, and its colour.
--- Nil below the 250th.
function KillTooltip.MarkLine(kills)
    kills = tonumber(kills) or 0
    local T = ns.Tracker
    if kills >= T.BANE_KILLS then return L["Bane of its kind"], 1, 0.5, 0 end
    if kills >= T.SLAYER_KILLS then return L["Slayer of its kind"], 1, 0.8, 0.27 end
    if kills >= T.LAUREL_KILLS then return L["They know your name."], 0.8, 0.84, 0.9 end
    return nil
end

--- The crown (and laurel) Farmer gave you for this many kills of a mob,
--- the same mark the kills panel puts after its name, or nil below the
--- 100th. Shown on the tooltip's kill line and beside its nameplate.
function KillTooltip.Crown(kills)
    local TrackerUI = ns.TrackerUI
    if not (TrackerUI and TrackerUI.MarkFor) then return nil end
    local ok, mark = pcall(TrackerUI.MarkFor, kills)
    if ok and type(mark) == "string" then return mark end
    return nil
end

--- A unit that is alive, as far as the client will say. A dead one, or one
--- it will not say, is not.
function KillTooltip.Alive(unit)
    if not unit or type(UnitIsDead) ~= "function" then return false end
    local ok, dead = pcall(UnitIsDead, unit)
    if not ok then return false end
    local readable, answer = pcall(function() return dead == false or dead == nil end)
    return readable and answer or false
end

function KillTooltip:IsEnabled()
    return not (ns.db and ns.db.killTooltip == false)
end

function KillTooltip:SetEnabled(on)
    ns.db.killTooltip = on and true or false
    KillTooltip.ForgetKept()
end

--- Are the best drops shown under the count? Never while the count is off.
function KillTooltip:DropsEnabled()
    return self:IsEnabled() and not (ns.db and ns.db.killTooltipDrops == false)
end

function KillTooltip:SetDropsEnabled(on)
    ns.db.killTooltipDrops = on and true or false
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

--- Kills of a mob's line from the saved tally, 0 for one never killed. A
--- name split by zone answers through its zone's key (Tracker:KeyHere).
function KillTooltip.Kills(key)
    local mob
    if ns.Tracker and ns.Tracker.SplitKey and select(2, ns.Tracker.SplitKey(key)) then
        mob = ns.Tracker:Tally(key)
    else
        local mobs = ns.db and type(ns.db.tracker) == "table" and ns.db.tracker.mobs
        mob = type(mobs) == "table" and mobs[key]
    end
    return type(mob) == "table" and tonumber(mob.kills) or 0
end

--- The line a mob of this name shows here: its name, or the zone's key
--- once kills of that name are kept apart by zone.
function KillTooltip.KeyHere(name)
    local Tracker = ns.Tracker
    if not (Tracker and Tracker.KeyHere) then return name end
    local ok, key = pcall(Tracker.KeyHere, Tracker, name)
    return ok and key or name
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

--- "73%", "2%", "0.4%": how often a drop comes, in a few characters.
function KillTooltip.Chance(percent)
    percent = tonumber(percent) or 0
    if percent >= 1 then return ("%d%%"):format(math.floor(percent + 0.5)) end
    if percent >= 0.1 then return ("%.1f%%"):format(percent) end
    return "<0.1%"
end

--- An item's colour and icon: as it looked when you looted it, else as the
--- client says. Only for the few drops a tooltip names, and kept with them.
local function ItemLook(name, id)
    local look = ns.Tracker and ns.Tracker:LookOf(name) or {}
    local color, icon = look.color, look.icon
    id = id or look.id or (ns.Value.ItemID and ns.Value:ItemID(name))

    if (not color or not icon) and id then
        local getInfo = Field(_G.C_Item, "GetItemInfo") or _G.GetItemInfo
        if type(getInfo) == "function" then
            local ok, _, _, quality, _, _, _, _, _, _, texture = pcall(getInfo, id)
            if ok then
                quality = ns.Harvest.ReadableNumber(quality)
                color = color or (quality and ns.Tracker.QUALITY[quality])
                icon = icon or ns.Harvest.ReadableNumber(texture) or ns.Harvest.Readable(texture)
            end
        end
    end
    return color or ns.Tracker.QUALITY[1], icon
end

--- The left and right text of one best drop's line.
function KillTooltip.DropLine(entry)
    local color, icon = ItemLook(entry.name, entry.id)
    local left = ("|c%s%s|r |c%s%s|r"):format(color, entry.name, MUTED, KillTooltip.Chance(entry.chance))
    if icon then left = ("|T%s:14:14|t %s"):format(tostring(icon), left) end
    return left, ns.Value.Coins(entry.perKill)
end

--- What a mob is worth and its best drops, worked out once a while:
--- { text, drops = { { left, right } }, estimate }.
function KillTooltip:Read(name, kills)
    local entry = kept[name]
    local now = Now()
    if entry and entry.kills == kills and now - entry.at < KEEP_FOR then
        return entry
    end

    entry = { kills = kills, at = now, drops = {} }
    local ok, value, details = pcall(ns.Value.ForMob, ns.Value, name)
    if ok and type(value) == "number" and value > 0 then
        entry.estimate = type(details) == "table" and details.basis == "database"
        entry.text = ns.Value.Coins(value)
        if entry.estimate then entry.text = entry.text .. L[" (est.)"] end

        -- Already sorted by what each adds to a kill. A drop worth under
        -- half a copper a kill is not one of the best, whatever its place.
        -- Rates from the shipped data stay hidden until the player has kills
        -- enough for their own (the owner, 2026-10-15): finding them is the fun.
        local priced = type(details) == "table" and not entry.estimate and details.priced or {}
        for _, drop in ipairs(priced) do
            if #entry.drops >= KillTooltip.TOP_DROPS then break end
            if (tonumber(drop.perKill) or 0) >= 0.5 then
                local made, left, right = pcall(KillTooltip.DropLine, drop)
                if made then entry.drops[#entry.drops + 1] = { left, right } end
            end
        end
    end

    kept[name] = entry
    return entry
end

--- "1s 20c" in coin colours, "1s 20c (est.)" from the database's rates, or
--- nil when nothing it drops has a price.
function KillTooltip:Worth(name, kills)
    return self:Read(name, kills).text
end

--- The best drops' lines and whether they come from the database's rates.
function KillTooltip:Drops(name, kills)
    local entry = self:Read(name, kills)
    return entry.drops, entry.estimate
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

--- "Greens: 1 in 25 kills" for a unit's level, or nil.
function KillTooltip:GreensLine(unit)
    local WorldDrops = ns.WorldDrops
    if not (unit and WorldDrops and WorldDrops:IsEnabled()) or type(UnitLevel) ~= "function" then
        return nil
    end
    local ok, value = pcall(UnitLevel, unit)
    local level = ok and ns.Harvest.ReadableNumber(value) or nil
    if not level or level < 1 then return nil end
    local chance = WorldDrops:GreenText(level)
    return chance and L.Format("Greens: %s", chance) or nil
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
    name = KillTooltip.KeyHere(name)

    -- A mob you could farm, or one you already have.
    if KillTooltip.Kills(name) == 0 and self:Attackable(unit) ~= true then return "quiet" end

    local text, red = self:LineFor(name)
    local addLine = Field(tooltip, "AddLine")
    if type(addLine) ~= "function" then return "nounit" end

    local r, g, b
    if red then r, g, b = Color("loss", RED) else r, g, b = Color("text", WHITE) end

    local crown = KillTooltip.Crown(KillTooltip.Kills(name))
    if crown then text = text .. " " .. crown end

    self.writing = true
    pcall(addLine, tooltip, text, r, g, b)
    -- The marks of the milestones: its name known at 250, Slayer at 500,
    -- Bane at 1000 in legendary orange; from 750 a live one trembles.
    local mark, mr, mg, mb = KillTooltip.MarkLine(KillTooltip.Kills(name))
    if mark then pcall(addLine, tooltip, mark, mr, mg, mb) end
    if KillTooltip.Kills(name) >= ns.Tracker.FEAR_KILLS and KillTooltip.Alive(unit) then
        pcall(addLine, tooltip, L["It trembles at the sight of you."], 0.8, 0.6, 0.95)
    end
    -- The drops that add most to a kill.
    if self:DropsEnabled() then
        local drops, estimate = self:Drops(name, KillTooltip.Kills(name))
        local addDouble = Field(tooltip, "AddDoubleLine")
        if #drops > 0 and type(addDouble) == "function" then
            local gr, gg, gb = Color("accentHi", GOLD)
            pcall(addLine, tooltip, estimate and L["Best drops (est.)"] or L["Best drops"], gr, gg, gb)
            for _, drop in ipairs(drops) do
                pcall(addDouble, tooltip, drop[1], drop[2], 1, 1, 1, 1, 1, 1)
            end
        end
    end
    -- The chance of green gear from a mob of its level (Logic/WorldDrops.lua),
    -- only once that level has kills enough behind it.
    local greens = self:GreensLine(unit)
    if greens then pcall(addLine, tooltip, greens, 0.12, 1, 0) end
    local show = Field(tooltip, "Show")
    if type(show) == "function" then pcall(show, tooltip) end
    self.writing = false

    decorated[tooltip] = { guid = guid, lines = LineCount(tooltip) or 0 }
    return "added"
end

--- Keeps the name of a creature the data cannot name, from the tooltip:
--- the unit's name, else the tooltip's first line, with the guid it shows.
function KillTooltip:Learn(tooltip, data)
    local unit, guid = self:UnitFor(tooltip, data)
    local npcID = ns.Harvest.NpcID(guid)
    if not npcID or ns.Harvest.KnownNpcName(npcID) then return end
    local name
    if unit and type(UnitName) == "function" then
        local ok, value = pcall(UnitName, unit)
        name = ok and ns.Harvest.Readable(value) or nil
    end
    if not name then
        local ok, line = pcall(function() return data.lines[1].leftText end)
        name = ok and ns.Harvest.Readable(line) or nil
    end
    if name then ns.Harvest:KeepName(npcID, name) end
end

--- Every hook comes through here, so one odd unit costs its line and never a
--- Lua error on hover.
function KillTooltip:OnTooltip(tooltip, data)
    -- A mob Forever added gets its name kept from the tooltip, line or not.
    pcall(self.Learn, self, tooltip, data)
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

ns.RegisterCommand("killcount", L["turn the kill count on mob tooltips on or off (drops [on|off] shows the best drops under it)"], function(rest)
    local word, choice = (rest or ""):lower():match("^%s*(%S*)%s*(%S*)")
    if word == "drops" then
        local on
        if choice == "on" then on = true elseif choice == "off" then on = false
        else on = ns.db.killTooltipDrops == false end
        KillTooltip:SetDropsEnabled(on)
        ns.Print(on and L["best drops on mob tooltips on."]
            or L["best drops on mob tooltips off. /farm killcount drops brings them back."])
        if ns.SettingsUI then ns.SettingsUI:Refresh() end
        return
    end
    KillTooltip:SetEnabled(not KillTooltip:IsEnabled())
    ns.Print(KillTooltip:IsEnabled() and L["kill count on mob tooltips on."]
        or L["kill count on mob tooltips off."])
    if ns.SettingsUI then ns.SettingsUI:Refresh() end
end)
