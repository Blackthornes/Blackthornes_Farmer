-- Blackthornes Farmer -- UI/FishingBar.lua
-- The Fishing window: Cast and Add Lure while a fishing pole is in the main
-- hand (the owner said build it 2026-10-26, from a mockup whose words he
-- approved). Both wear the gold plaque, Cast with the Fishing skill under
-- it; under them, the lure on the pole and its time left.
--
-- Addon code may not cast or use an item, but the player's own click on a
-- secure button may. So Cast is a secure button that casts Fishing by the
-- client's own name for it, and each row in the lure list is a secure
-- button whose macro uses the lure and then the main hand slot
-- ("/use item:ID", "/use 16"), which is how a lure goes on a pole. Their
-- attributes are only ever set out of combat.
--
-- The window holds those secure buttons, so it is hidden as a fight starts
-- (PLAYER_REGEN_DISABLED, the last moment the game lets addon code hide
-- one) and comes back when the fight ends. It is hidden too at a vendor,
-- the bank, a mailbox, the auction house or a trade, where a click on a
-- lure would do something else with it.
--
-- The lure list is the lures in the bags, best first (LURES), each greyed
-- with "Needs Fishing N" while the skill is short (read off the item's own
-- tooltip, kept per item). The time left is the game's
-- (GetWeaponEnchantInfo), read once a second only while shown and a lure
-- is on; Legacy.LureOn reads the same call and is left as it was.
--
-- "Fishing Buttons:" under FISHING on the Loot page (`fishingBar`, off
-- unless ticked) and /farm fishbar. Its place and size: `fishingBarX`,
-- `fishingBarY` (its top left, nil for the first place) and
-- `fishingBarScale`. All account wide; never rename them.

local _, ns = ...
local L = ns.L

local FishingBar = ns.NewModule("FishingBar")

local Theme = ns.Theme
local Widgets = ns.Widgets

FishingBar.WIDTH = 300
FishingBar.HEIGHT = 124
FishingBar.BUTTON_HEIGHT = 46
FishingBar.PADDING = 14
FishingBar.ROW = 26
-- After the last bag, gear or skill event, how long before it reads again.
FishingBar.SETTLE = 0.2
-- Its first place, from the middle of the screen.
FishingBar.FIRST_X = 240
FishingBar.FIRST_Y = -80

-- Fishing (Apprentice). The client casts the rank the player knows by name.
FishingBar.SPELL = 7620
-- Its icon, on the Cast plaque.
FishingBar.FISHING_ICON = 136245
-- The main hand, and a fishing pole: weapon (2), fishing pole (20).
FishingBar.MAIN_HAND = 16
FishingBar.POLE_CLASS = 2
FishingBar.POLE_SUBCLASS = 20

-- Lures, best first. Each is in the Forever client's game tables.
FishingBar.LURES = {
    { id = 6533, bonus = 100, name = "Aquadynamic Fish Attractor" },
    { id = 6532, bonus = 75, name = "Bright Baubles" },
    { id = 7307, bonus = 75, name = "Flesh Eating Worm" },
    { id = 6530, bonus = 50, name = "Nightcrawlers" },
    { id = 6811, bonus = 50, name = "Aquadynamic Fish Lens" },
    { id = 6529, bonus = 25, name = "Shiny Bauble" },
}
-- What each lure's enchant on the pole adds, by the enchant's ID.
FishingBar.LURE_ENCHANTS = { [263] = 25, [264] = 50, [265] = 75, [266] = 100 }

local PLACES = {
    MERCHANT_SHOW = "MERCHANT_CLOSED",
    BANKFRAME_OPENED = "BANKFRAME_CLOSED",
    MAIL_SHOW = "MAIL_CLOSED",
    AUCTION_HOUSE_SHOW = "AUCTION_HOUSE_CLOSED",
    TRADE_SHOW = "TRADE_CLOSED",
}
FishingBar.at = {}
-- The skill each lure needs, as its tooltip says: [itemID] = number, or
-- false when it needs none.
FishingBar.needs = {}

--------------------------------------------------------------------------------
-- Client calls
--------------------------------------------------------------------------------

local function Number(value)
    local ok, n = pcall(function()
        local n = tonumber(value)
        if n then return n + 0 end
    end)
    if ok and type(n) == "number" then return n end
    return nil
end

local function InCombat()
    local fn = rawget(_G, "InCombatLockdown")
    if type(fn) ~= "function" then return false end
    local ok, fighting = pcall(fn)
    return ok and fighting and true or false
end

--- Is a fishing pole in the main hand?
function FishingBar.HoldsPole()
    if type(GetInventoryItemID) ~= "function" then return false end
    local ok, id = pcall(GetInventoryItemID, "player", FishingBar.MAIN_HAND)
    id = ok and Number(id) or nil
    if not id then return false end

    local info = type(C_Item) == "table" and C_Item.GetItemInfoInstant or rawget(_G, "GetItemInfoInstant")
    if type(info) ~= "function" then return false end
    local results = { pcall(info, id) }
    if not results[1] then return false end
    local class, subclass = Number(results[7]), Number(results[8])
    return class == FishingBar.POLE_CLASS and subclass == FishingBar.POLE_SUBCLASS
end

--- The lure on the pole: on (true, false, or nil when the client won't
--- say), seconds left and what it adds (nil when not known).
function FishingBar.LureOnPole()
    if type(GetWeaponEnchantInfo) ~= "function" then return nil end
    local ok, has, expires, _, enchant = pcall(GetWeaponEnchantInfo)
    if not ok then return nil end
    local readable, on = pcall(function() return has == true or has == 1 end)
    if not readable then return nil end
    if not on then return false end
    local ms = Number(expires)
    return true, ms and math.max(0, math.floor(ms / 1000)) or nil,
        FishingBar.LURE_ENCHANTS[Number(enchant) or 0]
end

local function ItemCount(id)
    local fn = type(C_Item) == "table" and C_Item.GetItemCount or rawget(_G, "GetItemCount")
    if type(fn) ~= "function" then return 0 end
    local ok, count = pcall(fn, id)
    return ok and Number(count) or 0
end

local function ItemName(id, fallback)
    local fn = type(C_Item) == "table" and C_Item.GetItemNameByID or nil
    if type(fn) == "function" then
        local ok, name = pcall(fn, id)
        if ok and type(name) == "string" and name ~= "" then return name end
    end
    if type(GetItemInfo) == "function" then
        local ok, name = pcall(GetItemInfo, id)
        if ok and type(name) == "string" and name ~= "" then return name end
    end
    return fallback
end

local function ItemIcon(id)
    if Theme.ItemIcon then
        local ok, icon = pcall(Theme.ItemIcon, id)
        if ok and icon then return icon end
    end
    return 134400
end

--- The client's name for Fishing, else its ID (a secure button casts
--- either).
function FishingBar.SpellName()
    local fn = type(C_Spell) == "table" and C_Spell.GetSpellName or nil
    if type(fn) == "function" then
        local ok, name = pcall(fn, FishingBar.SPELL)
        if ok and type(name) == "string" and name ~= "" then return name end
    end
    if type(GetSpellInfo) == "function" then
        local ok, name = pcall(GetSpellInfo, FishingBar.SPELL)
        if ok and type(name) == "string" and name ~= "" then return name end
    end
    return FishingBar.SPELL
end

--- "Requires %s (%d)" as a pattern that gives the number.
local function SkillPattern()
    local format = rawget(_G, "ITEM_MIN_SKILL")
    if type(format) ~= "string" then format = "Requires %s (%d)" end
    local pattern = format:gsub("([%(%)%.%[%]%+%-%*%?%^%$])", "%%%1")
    pattern = pattern:gsub("%%%d?%$?s", ".+"):gsub("%%%d?%$?d", "(%%d+)")
    return pattern
end

--- The Fishing skill a lure needs, from its tooltip, or nil when none.
function FishingBar:Needs(id)
    local known = self.needs[id]
    if known ~= nil then return known or nil end

    local api = rawget(_G, "C_TooltipInfo")
    local get = type(api) == "table" and api.GetItemByID or nil
    if type(get) ~= "function" then return nil end
    local ok, data = pcall(get, id)
    if not ok or type(data) ~= "table" or type(data.lines) ~= "table" then return nil end

    local pattern, need = SkillPattern(), false
    for _, line in ipairs(data.lines) do
        local readable, text = pcall(function() return line.leftText .. "" end)
        if readable and text then
            local number = text:match(pattern)
            if number then need = Number(number) or false break end
        end
    end
    self.needs[id] = need
    return need or nil
end

--------------------------------------------------------------------------------
-- What it shows
--------------------------------------------------------------------------------

--- The lures in the bags, best first: { id, bonus, name, count, need,
--- usable }.
function FishingBar:Lures(skill)
    local found = {}
    for _, lure in ipairs(self.LURES) do
        local count = ItemCount(lure.id)
        if count > 0 then
            local need = self:Needs(lure.id)
            found[#found + 1] = {
                id = lure.id, bonus = lure.bonus, count = count,
                name = ItemName(lure.id, lure.name),
                need = need,
                usable = not (need and skill and skill < need),
            }
        end
    end
    return found
end

--- "8:42" for seconds left.
function FishingBar.Clock(seconds)
    seconds = math.max(0, math.floor(seconds or 0))
    local hours = math.floor(seconds / 3600)
    local minutes = math.floor(seconds % 3600 / 60)
    local rest = seconds % 60
    if hours > 0 then return ("%d:%02d:%02d"):format(hours, minutes, rest) end
    return ("%d:%02d"):format(minutes, rest)
end

--- The lure line's words and colour, and whether Add Lure should glow.
function FishingBar:LureText(lures)
    local on, seconds, bonus = self.LureOnPole()
    if on then
        local left = seconds and L.Format("%s left", self.Clock(seconds)) or ""
        if bonus then
            if left ~= "" then return ("+%d, %s"):format(bonus, left), "good", false end
            return ("+%d"):format(bonus), "good", false
        end
        return left, "good", false
    end
    if #lures == 0 then return L["No lures in your bags"], "warn", false end
    return L["None on"], "warn", on == false
end

--------------------------------------------------------------------------------
-- Settings
--------------------------------------------------------------------------------

function FishingBar:Enabled()
    return ns.db ~= nil and ns.db.fishingBar == true
end

function FishingBar:SetEnabled(on)
    if not ns.db then return end
    ns.db.fishingBar = on and true or false
    self.closed = nil
    self:Update()
end

function FishingBar.Busy()
    for _, open in pairs(FishingBar.at) do
        if open then return true end
    end
    return false
end

--- Should the window be up now?
function FishingBar:Wanted()
    return self:Enabled() and not self.closed and not self.fighting and not InCombat()
        and not self.Busy() and self.HoldsPole()
end

--------------------------------------------------------------------------------
-- The window
--------------------------------------------------------------------------------

local function Tooltip(owner, text)
    owner:HookScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(text, 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    owner:HookScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
end

function FishingBar:Build()
    if self.frame then return self.frame end
    local PAD = self.PADDING

    local frame = CreateFrame("Frame", "BlackthornesFarmerFishingFrame", UIParent)
    frame:SetSize(self.WIDTH, self.HEIGHT)
    frame:SetFrameStrata("MEDIUM")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:Hide()

    Theme.Fill(frame, "window")
    local trim
    if ns.Titanforged then
        trim = ns.Titanforged:Dress(frame, {
            title = L["Fishing"],
            close = function() FishingBar:Close() end,
        })
        local left, right, top, bottom = ns.Titanforged.Reach(trim)
        if frame.SetClampRectInsets then
            pcall(frame.SetClampRectInsets, frame, -left, right, top, -bottom)
        end
    else
        Theme.Border(frame, "borderLit")
    end
    Theme.Halo(frame, 8, 0.10)
    self.trim = trim

    frame:SetScript("OnDragStart", function(self)
        if InCombat() then return end
        ns.Motion:Stop(self, "open", true)
        self:StartMoving()
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        FishingBar:SavePlace()
    end)
    frame:SetScript("OnHide", function()
        FishingBar:StopClock()
        FishingBar.lureGlowing = nil
    end)
    self.frame = frame

    Widgets.ApplySize(frame, ns.db and ns.db.fishingBarScale)
    self.sizeGrip = Widgets.CreateSizeGrip(frame, {
        below = trim and select(4, ns.Titanforged.Reach(trim)) or 0,
        get = function() return ns.db and ns.db.fishingBarScale end,
        save = function(percent) if ns.db then ns.db.fishingBarScale = percent end end,
    })

    local half = math.floor((self.WIDTH - PAD * 2 - 8) / 2)

    -- The gold plaque (UI/Plaque.lua, the owner's pick, 2026-10-27): an
    -- icon, what the click does, and a second line under it. Cast is
    -- itself the secure button.
    local cast = ns.Plaque.Create(frame, {
        name = "BlackthornesFarmerFishingCast",
        template = "SecureActionButtonTemplate",
        width = half,
        height = self.BUTTON_HEIGHT,
    })
    cast:RegisterForClicks("AnyUp")
    cast:SetAttribute("useOnKeyDown", false)
    cast:SetPoint("TOPLEFT", PAD, -36)
    cast:SetIcon(self.FISHING_ICON)
    cast:SetLines(L["Cast"])
    Tooltip(cast, L["Cast your line."])
    self.cast = cast
    self.castSecure = cast

    local lure = ns.Plaque.Create(frame, { width = half, height = self.BUTTON_HEIGHT })
    lure:SetScript("OnClick", function() FishingBar:ToggleList() end)
    lure:SetPoint("TOPRIGHT", -PAD, -36)
    lure:SetIcon(134400)
    lure:SetLines(L["Add Lure"])
    Tooltip(lure, L["Pick a lure to put on your pole."])
    self.lureButton = lure

    local lureLabel = Theme.CreateLabel(frame, "small", "muted")
    lureLabel:SetPoint("TOPLEFT", PAD, -94)
    lureLabel:SetText(L["Lure:"])
    local lureValue = Theme.CreateLabel(frame, "small", "good", "RIGHT")
    lureValue:SetPoint("TOPRIGHT", -PAD, -94)
    lureValue:SetPoint("LEFT", lureLabel, "RIGHT", 6, 0)
    lureValue:SetWordWrap(true)
    self.lureValue = lureValue

    if ns.FoldWindow then
        ns.FoldWindow:Add(frame, {
            canFold = function() return not InCombat() end,
            onToggle = function(folded) if folded then FishingBar:HideList() end end,
        })
    end

    self:Place()
    return frame
end

--- Put it where it was left, else in its first place.
function FishingBar:Place()
    local frame = self.frame
    if not frame then return end
    frame:ClearAllPoints()
    local x, y = Number(ns.db and ns.db.fishingBarX), Number(ns.db and ns.db.fishingBarY)
    if x and y then
        frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x, y)
    else
        frame:SetPoint("TOPLEFT", UIParent, "CENTER", self.FIRST_X, self.FIRST_Y)
    end
end

--- Keep where its top left corner is now.
function FishingBar:SavePlace()
    local frame = self.frame
    if not frame or not ns.db then return end
    local ok, left, top = pcall(function() return frame:GetLeft(), frame:GetTop() end)
    if ok and type(left) == "number" and type(top) == "number" then
        ns.db.fishingBarX, ns.db.fishingBarY = left, top
    end
    self:Place()
end

--- The close gem: put away until the pole comes off and on again.
function FishingBar:Close()
    if InCombat() then return end
    self.closed = true
    self:HideList()
    if self.frame then self.frame:Hide() end
end

--------------------------------------------------------------------------------
-- The lure list
--------------------------------------------------------------------------------

function FishingBar:BuildList()
    if self.list then return self.list end
    local frame = self:Build()

    local list = CreateFrame("Frame", nil, frame)
    list:SetWidth(self.WIDTH)
    local below = self.trim and select(4, ns.Titanforged.Reach(self.trim)) or 0
    list:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 0, -(below + 6))
    list:EnableMouse(true)
    list:Hide()
    Theme.Fill(list, "window")
    Theme.Border(list, "accent")

    local heading = Theme.CreateLabel(list, "small", "gilt")
    heading:SetPoint("TOPLEFT", 10, -8)
    heading:SetText(L["YOUR LURES"])

    local empty = Theme.CreateLabel(list, "small", "dim")
    empty:SetPoint("TOPLEFT", 10, -30)
    empty:SetPoint("TOPRIGHT", -10, -30)
    empty:SetWordWrap(true)
    empty:SetText(L["No lures in your bags"])
    list.empty = empty

    list.rows = {}
    self.list = list
    return list
end

--- One row, a secure button: the lure's icon, its name in its rarity
--- colour, what it adds in green and how many.
function FishingBar:Row(index)
    local list = self:BuildList()
    local row = list.rows[index]
    if row then return row end

    row = CreateFrame("Button", "BlackthornesFarmerFishingLure" .. index, list, "SecureActionButtonTemplate")
    row:SetHeight(self.ROW)
    row:SetPoint("TOPLEFT", 6, -26 - (index - 1) * self.ROW)
    row:SetPoint("TOPRIGHT", -6, -26 - (index - 1) * self.ROW)
    row:RegisterForClicks("AnyUp")
    row:SetAttribute("useOnKeyDown", false)

    local stripe = row:CreateTexture(nil, "BACKGROUND")
    stripe:SetAllPoints(row)
    stripe:SetColorTexture(Theme.Unpack(index % 2 == 1 and "glass" or "glassAlt"))

    local rule = row:CreateTexture(nil, "BORDER")
    rule:SetPoint("BOTTOMLEFT")
    rule:SetPoint("BOTTOMRIGHT")
    rule:SetHeight(1)
    rule:SetColorTexture(Theme.Unpack("border", 0.6))

    local hover = row:CreateTexture(nil, "HIGHLIGHT")
    hover:SetAllPoints(row)
    hover:SetColorTexture(Theme.Unpack("glassHover"))
    local edge = row:CreateTexture(nil, "HIGHLIGHT")
    edge:SetPoint("TOPLEFT")
    edge:SetPoint("BOTTOMLEFT")
    edge:SetWidth(2)
    edge:SetColorTexture(Theme.Unpack("accentHi"))

    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetSize(20, 20)
    icon:SetPoint("LEFT", 4, 0)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    row.icon = icon

    local count = Theme.CreateLabel(row, "small", "muted", "RIGHT")
    count:SetPoint("RIGHT", -6, 0)
    row.count = count

    local bonus = Theme.CreateLabel(row, "small", "good", "RIGHT")
    bonus:SetPoint("RIGHT", count, "LEFT", -6, 0)
    row.bonus = bonus

    local name = Theme.CreateLabel(row, "small", "text")
    name:SetPoint("LEFT", icon, "RIGHT", 6, 0)
    name:SetPoint("RIGHT", bonus, "LEFT", -6, 0)
    name:SetWordWrap(true)
    row.name = name

    row:HookScript("OnEnter", function(self)
        local data = self.data
        if not (data and GameTooltip) then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if not data.usable and data.need then
            GameTooltip:SetText(L.Format("Needs Fishing %d", data.need), 1, 0.4, 0.3, 1, true)
        elseif not pcall(GameTooltip.SetItemByID, GameTooltip, data.id) then
            GameTooltip:SetText(data.name, 1, 1, 1, 1, true)
        end
        GameTooltip:Show()
    end)
    row:HookScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    -- The list goes once a lure is picked.
    row:SetScript("PostClick", function(self)
        if self.data and self.data.usable and not InCombat() then FishingBar:HideList() end
    end)

    list.rows[index] = row
    return row
end

function FishingBar:DrawList()
    local list = self.list
    if not (list and list:IsShown()) or InCombat() then return end
    local skill = ns.GatherToCap and ns.GatherToCap.ReadSkill("Fishing") or nil
    local lures = self:Lures(skill)

    for index, data in ipairs(lures) do
        local row = self:Row(index)
        row.data = data
        row.icon:SetTexture(ItemIcon(data.id))
        row.icon:SetDesaturated(not data.usable)
        local name = data.usable and ns.Util.ColorItem(data.name, data.id) or data.name
        row.name:SetText(name)
        row.name:SetTextColor(Theme.Unpack(data.usable and "text" or "dim"))
        row.bonus:SetText(("+%d"):format(data.bonus))
        row.bonus:SetTextColor(Theme.Unpack(data.usable and "good" or "dim"))
        row.count:SetText(("x%d"):format(data.count))
        if data.usable then
            row:SetAttribute("type", "macro")
            row:SetAttribute("macrotext", ("/use item:%d\n/use %d"):format(data.id, self.MAIN_HAND))
        else
            row:SetAttribute("type", nil)
            row:SetAttribute("macrotext", nil)
        end
        row:Show()
    end
    for index = #lures + 1, #list.rows do
        local row = list.rows[index]
        row.data = nil
        row:SetAttribute("type", nil)
        row:SetAttribute("macrotext", nil)
        row:Hide()
    end

    if #lures == 0 then
        list.empty:Show()
        list:SetHeight(58)
    else
        list.empty:Hide()
        list:SetHeight(32 + #lures * self.ROW)
    end
end

function FishingBar:ToggleList()
    if InCombat() then return end
    local list = self:BuildList()
    if list:IsShown() then
        list:Hide()
    else
        list:Show()
        self:DrawList()
    end
end

function FishingBar:HideList()
    if self.list and not InCombat() then self.list:Hide() end
end

--------------------------------------------------------------------------------
-- Drawing
--------------------------------------------------------------------------------

function FishingBar:DrawLines()
    if not (self.frame and self.frame:IsShown()) then return end
    local lures = self:Lures(nil)
    local text, color, glow = self:LureText(lures)
    self.lureValue:SetText(text)
    self.lureValue:SetTextColor(Theme.Unpack(color))
    self:Glow(glow)
    local best = lures[1]
    local button = self.lureButton
    button:SetIcon(best and ItemIcon(best.id) or 134400)
    button:SetLines(L["Add Lure"], best and L.Format("%s, %d left", best.name, best.count) or nil)
    button:SetAlpha(#lures == 0 and 0.55 or 1)

    -- The skill sits on the Cast plaque.
    local skill, cap
    if ns.GatherToCap then skill, cap = ns.GatherToCap.ReadSkill("Fishing") end
    self.cast:SetLines(L["Cast"], skill and L.Format("Fishing %d / %d", skill, cap or skill) or nil)

    -- The time left moves once a second, only while a lure is on.
    if self.LureOnPole() then self:StartClock() else self:StopClock() end
end

function FishingBar:StartClock()
    if self.clock or type(C_Timer) ~= "table" or type(C_Timer.NewTicker) ~= "function" then return end
    self.clock = C_Timer.NewTicker(1, function()
        if not (FishingBar.frame and FishingBar.frame:IsShown()) then
            FishingBar:StopClock()
            return
        end
        local text, color, glow = FishingBar:LureText(FishingBar:Lures(nil))
        FishingBar.lureValue:SetText(text)
        FishingBar.lureValue:SetTextColor(Theme.Unpack(color))
        FishingBar:Glow(glow)
        if color ~= "good" then FishingBar:StopClock() end
    end)
end

--- Add Lure's glow breathes while no lure is on and one is in the bags.
function FishingBar:Glow(on)
    on = on and true or false
    if on == self.lureGlowing then return end
    self.lureGlowing = on
    self.lureButton:SetGlowing(on)
end

--- A catch came in: the Cast plaque flashes gold, a small cheer.
function FishingBar:Caught()
    local cast = rawget(self, "cast")
    if cast and self.frame and self.frame:IsShown() then cast:Flash() end
end

function FishingBar:StopClock()
    if self.clock then
        pcall(function() self.clock:Cancel() end)
        self.clock = nil
    end
end

--- Show or hide it for how things stand, and draw what shows.
function FishingBar:Update()
    if self.fighting or InCombat() then return end
    local holds = self.HoldsPole()
    -- Taking the pole off lets the close gem's choice go.
    if not holds then self.closed = nil end

    if not self:Wanted() then
        self:HideList()
        if self.frame then self.frame:Hide() end
        return
    end

    local frame = self:Build()
    self.castSecure:SetAttribute("type", "spell")
    self.castSecure:SetAttribute("spell", self.SpellName())
    if not frame:IsShown() then frame:Show() end
    self:DrawLines()
    self:DrawList()
end

--- Bag, gear and skill events come in bursts: one read after they settle.
function FishingBar:Changed()
    if self.pending then return end
    self.pending = true
    C_Timer.After(self.SETTLE, function()
        FishingBar.pending = nil
        FishingBar:Update()
    end)
end

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------

function FishingBar:OnEnable()
    local function Changed() FishingBar:Changed() end
    ns.RegisterEvent(self, "PLAYER_ENTERING_WORLD", Changed)
    ns.RegisterEvent(self, "PLAYER_EQUIPMENT_CHANGED", Changed)
    ns.RegisterPlayerEvent(self, "UNIT_INVENTORY_CHANGED", function(_, _, unit)
        if unit == nil or unit == "player" then Changed() end
    end)
    ns.RegisterEvent(self, "BAG_UPDATE_DELAYED", Changed)
    ns.RegisterEvent(self, "SKILL_LINES_CHANGED", Changed)

    -- Just before combat locks secure frames: hidden while it still may be.
    ns.RegisterEvent(self, "PLAYER_REGEN_DISABLED", function()
        FishingBar.fighting = true
        if FishingBar.list then FishingBar.list:Hide() end
        if FishingBar.frame then FishingBar.frame:Hide() end
    end)
    ns.RegisterEvent(self, "PLAYER_REGEN_ENABLED", function()
        FishingBar.fighting = false
        FishingBar:Update()
    end)

    for open, close in pairs(PLACES) do
        ns.RegisterEvent(self, open, function()
            FishingBar.at[open] = true
            FishingBar:Update()
        end)
        ns.RegisterEvent(self, close, function()
            FishingBar.at[open] = nil
            FishingBar:Update()
        end)
    end
end

ns.RegisterCommand("fishbar", L["Cast and lure buttons while you hold a fishing pole."], function(rest)
    local word = ns.Util.Trim(rest or ""):lower()
    local on
    if word == "on" then on = true elseif word == "off" then on = false else on = not FishingBar:Enabled() end
    FishingBar:SetEnabled(on)
    ns.Print(L["Fishing Buttons:"] .. " " .. (on and L["On"] or L["Off"]))
end)
