-- Blackthornes Farmer -- UI/ItemTooltip.lua
-- One line on a material's tooltip: the best place to farm it from where you
-- stand, the same pick the Where? button makes (Spots:For).
--
--   Farm: Witchwing Slayer (16-17), The Barrens, ~14%, next zone over
--
-- Only materials get it: anything the seed files list, and whatever else the
-- database knows that the game files as a trade good (meat, cloth, leather
-- your own loot added). Gear, greys and potions a mob happened to drop are
-- left alone, since "farm it here" means nothing for them.
--
-- Hooked the way Tradeskills' and Equipment's tooltips are: retail's
-- TooltipDataProcessor is what fires on Forever, the older OnTooltipSetItem
-- script is hooked too in case, and a guard stops the line going on twice.
-- Only the game's main tooltip and the one a chat link opens are touched,
-- and only appended to.

local _, ns = ...

local ItemTooltip = ns.NewModule("ItemTooltip")

local Util = ns.Util

local TOOLTIP_NAMES = { "GameTooltip", "ItemRefTooltip" }

-- The game's item class for trade goods.
local TRADE_GOODS = 7

-- A tooltip is redrawn over and over while the mouse rests on it, so the
-- answer for an item is kept this long, as long as you stay in the same zone.
local KEEP_FOR = 10

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

function ItemTooltip:IsEnabled()
    return not (ns.db and ns.db.itemTooltip == false)
end

--- Is this one of the tooltips the line belongs on?
function ItemTooltip:Wanted(tooltip)
    for _, name in ipairs(TOOLTIP_NAMES) do
        if _G[name] ~= nil and _G[name] == tooltip then return true end
    end
    return false
end

--------------------------------------------------------------------------------
-- Which item
--------------------------------------------------------------------------------

--- The item id a tooltip shows, however this client offers it.
function ItemTooltip:ItemIDFor(tooltip, data)
    local id = ns.Harvest.ReadableNumber(Field(data, "id"))
    if id and id > 0 then return id end

    local link
    local displayed = Field(_G.TooltipUtil, "GetDisplayedItem")
    if type(displayed) == "function" then
        local ok, _, shown = pcall(displayed, tooltip)
        if ok then link = shown end
    end
    if not link then
        local getItem = Field(tooltip, "GetItem")
        if type(getItem) == "function" then
            local ok, _, shown = pcall(getItem, tooltip)
            if ok then link = shown end
        end
    end

    link = ns.Harvest.Readable(link)
    return link and tonumber(link:match("item:(%d+)")) or nil
end

-- Item ids the database knows, filled in the first time one is asked for.
local byID

local function DatabaseByID()
    if byID then return byID end
    byID = {}
    for item in ns.DB:Iterate() do
        if item.id then byID[item.id] = item end
    end
    return byID
end

--- The item's name from the client, or nil.
local function ClientName(itemID)
    local getName = Field(_G.C_Item, "GetItemNameByID")
    if type(getName) == "function" then
        local ok, name = pcall(getName, itemID)
        name = ok and ns.Harvest.Readable(name)
        if name then return name end
    end
    local getInfo = Field(_G.C_Item, "GetItemInfo") or _G.GetItemInfo
    if type(getInfo) == "function" then
        local ok, name = pcall(getInfo, itemID)
        return ok and ns.Harvest.Readable(name) or nil
    end
    return nil
end

--- The game's item class for an id, or nil.
local function ClassID(itemID)
    local instant = Field(_G.C_Item, "GetItemInfoInstant") or _G.GetItemInfoInstant
    if type(instant) ~= "function" then return nil end
    local ok, _, _, _, _, _, classID = pcall(instant, itemID)
    return ok and ns.Harvest.ReadableNumber(classID) or nil
end

--- The database's entry for an item id, when it is a material worth a line.
function ItemTooltip:Material(itemID)
    local item = DatabaseByID()[itemID]
    if not item then
        local name = ClientName(itemID)
        item = name and ns.DB:GetItem(name)
    end
    if not item then return nil end

    -- Harvested drops land in "Misc" whatever they are; of those, only the
    -- trade goods are materials.
    if item.category == "Misc" and ClassID(itemID) ~= TRADE_GOODS then return nil end
    return item
end

--------------------------------------------------------------------------------
-- The line
--------------------------------------------------------------------------------

--- "Farm: Witchwing Slayer (16-17), The Barrens, ~14%, next zone over", or
--- nil when no spot is known.
function ItemTooltip:LineFor(item, player)
    local spot = ns.Spots:For(item.name, player)[1]
    if not spot then return nil end

    local parts = { spot.name or ns.DB:KindLabel(spot.kind) or "?" }
    if spot.minLevel then
        parts[1] = parts[1] .. (" (%s)"):format(ns.Search:LevelText(spot))
    end
    if type(spot.zone) == "string" then parts[#parts + 1] = spot.zone end

    local rate = spot.measured or spot.chance
    if type(rate) == "number" then parts[#parts + 1] = ns.Search:ChanceText(rate) end

    local distance = ns.Spots.DistanceText(spot.hops, spot.zone, spot.travel)
    if distance ~= "" then parts[#parts + 1] = distance end
    local short = ns.Spots.SkillShortText and ns.Spots.SkillShortText(spot)
    if short then parts[#parts + 1] = short end

    return Util.Colored("accent", "Farm: ") .. Util.Colored("text", table.concat(parts, ", "))
end

-- Answers already worked out: [item name] = { line, at, zone }.
local kept = {}

--- The line for an item, worked out again only when the kept one is stale.
function ItemTooltip:CachedLine(item)
    local player = ns.Spots:Player()
    local entry = kept[item.name]
    local now = Now()
    if entry and entry.zone == player.zone and now - entry.at < KEEP_FOR then
        return entry.line
    end

    local line = self:LineFor(item, player)
    kept[item.name] = { line = line or false, at = now, zone = player.zone }
    return line
end

function ItemTooltip.ForgetKept()
    kept = {}
end

--------------------------------------------------------------------------------
-- Putting it on the tooltip
--------------------------------------------------------------------------------

-- Which tooltip already carries the line, for which item and at what length.
-- Cleared when the tooltip is, so the next showing gets it again.
local decorated = setmetatable({}, { __mode = "k" })

function ItemTooltip.Forget(tooltip)
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
-- @return "added", "quiet" (nothing to say), "duplicate" or "noitem"
function ItemTooltip:Decorate(tooltip, data)
    if not self:IsEnabled() then return "quiet" end
    if not self:Wanted(tooltip) then return "quiet" end
    if self.writing then return "duplicate" end

    local itemID = self:ItemIDFor(tooltip, data)
    if not itemID then return "noitem" end

    local mark = decorated[tooltip]
    if mark and mark.id == itemID then
        local now = LineCount(tooltip)
        if not now or now >= mark.lines then return "duplicate" end
    end

    local item = self:Material(itemID)
    if not item then return "quiet" end

    local line = self:CachedLine(item)
    if not line then return "quiet" end

    local addLine = Field(tooltip, "AddLine")
    if type(addLine) ~= "function" then return "noitem" end

    self.writing = true
    -- Wrapped, so a long zone name folds rather than stretching the tooltip.
    pcall(addLine, tooltip, line, nil, nil, nil, true)
    local show = Field(tooltip, "Show")
    if type(show) == "function" then pcall(show, tooltip) end
    self.writing = false

    decorated[tooltip] = { id = itemID, lines = LineCount(tooltip) or 0 }
    return "added"
end

--- Every hook comes through here, so one odd item costs its line and never a
--- Lua error on hover.
function ItemTooltip:OnTooltip(tooltip, data)
    local ok, outcome = pcall(self.Decorate, self, tooltip, data)
    if not ok then
        self.writing = false
        return "noitem"
    end
    return outcome
end

function ItemTooltip:InstallDataProcessor()
    local processor = _G.TooltipDataProcessor
    local dataType = Field(Field(_G.Enum, "TooltipDataType"), "Item")
    local add = Field(processor, "AddTooltipPostCall")
    if type(add) ~= "function" or dataType == nil then return false end

    return (pcall(add, dataType, function(tooltip, data)
        ItemTooltip:OnTooltip(tooltip, data)
    end))
end

function ItemTooltip:InstallScriptHooks()
    local installed = false
    for _, name in ipairs(TOOLTIP_NAMES) do
        local tooltip = _G[name]
        local hook = Field(tooltip, "HookScript")
        if type(hook) == "function" then
            if pcall(hook, tooltip, "OnTooltipSetItem", function(shown)
                ItemTooltip:OnTooltip(shown, nil)
            end) then
                installed = true
            end
            pcall(hook, tooltip, "OnTooltipCleared", function(shown)
                ItemTooltip.Forget(shown)
            end)
        end
    end
    return installed
end

function ItemTooltip:OnEnable()
    self.installed = {
        TooltipDataProcessor = self:InstallDataProcessor(),
        OnTooltipSetItem = self:InstallScriptHooks(),
    }
end

ns.RegisterCommand("tooltip", "turn the farming line on material tooltips on or off", function()
    ns.db.itemTooltip = not ItemTooltip:IsEnabled()
    ItemTooltip.ForgetKept()
    ns.Print(("farming line on material tooltips %s."):format(
        ItemTooltip:IsEnabled() and "on" or "off"))
    if ns.SettingsUI then ns.SettingsUI:Refresh() end
end)
