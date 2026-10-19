-- Blackthornes Farmer -- UI/Trash.lua
-- A small gold can on the item worth the least while the bags are full
-- (the owner asked 2026-10-13: "a small can icon for the lowest value
-- item", in Butler and Farmer both).
--
-- Blackthornes Butler has the same can, judged by its own verdicts. Only
-- one can shows: while Butler is loaded (_G.BlackthornesButler.Trash),
-- Farmer's stands down and Butler's is the one on screen.
--
-- What it picks: the stack worth least in all, by Farmer's own prices
-- (Value:UnitPrice: grey is vendor only, the rest the best of auction and
-- vendor) times the stack, among items in bags that take anything (a herb
-- in a herb bag frees no room). Never an item a goal of this character
-- counts, a quest item, anything soulbound above grey, gear that could be
-- worn (only grey gear may go), an item a vendor won't buy, a locked slot,
-- or an item with no price. A trade good (cloth, herbs, ore and the like)
-- counts as `Trash.MATERIAL_LEAN` times its worth there, so when it is close
-- the can leans to junk and leaves the material (the owner, 2026-10-16).
--
-- Stacking first (the owner, 2026-10-16): when two short stacks of one item
-- fit in one slot, the can sits on the smaller one and says to stack them,
-- whatever the item is. A click joins them; nothing has to go.
--
-- A red glow lies round the picked slot too (the owner, 2026-10-19: "a red
-- glowing outline around the item in the bag"), so it is easy to spot. It
-- is its own frame beside the can, shown and hidden with it, and pulses
-- slowly; Media/Trash/PickGlow.tga comes from the same tool as the can.
--
-- Nothing is ever deleted by Farmer. A click on the can picks the item up
-- and says so; the player drops it outside the bags and the game's own box
-- asks before anything is destroyed, or clicks the slot to put it back.
--
-- The can is Farmer's own button on UIParent, anchored to the game's item
-- button (found as Equipment's UI/BagIcons.lua finds them: retail's
-- EnumerateValidItems and GetBagID, else classic's ContainerFrame<n>Item<m>).
-- Nothing is written on a game frame: the bag windows' UpdateItems, OnShow
-- and OnHide are only hooked. Hidden in combat, at a vendor and while the
-- cursor holds something.
--
-- Smooth play: bag events only mark it stale; one look follows 0.2 s after
-- the burst, only while a bag window is open, and the bags are read only
-- once they are nearly full, Trash.BUDGET slots a frame. A slot is priced
-- again only when its item, count or lock changed.

local _, ns = ...
local L = ns.L

local Trash = ns.NewModule("Trash")

-- Shows only at this many free slots or fewer: none (Butler's number too).
Trash.FREE = 0
Trash.SETTLE = 0.2
Trash.BUDGET = 40
Trash.ART = [[Interface\AddOns\Blackthornes_Farmer\Media\Trash\TrashCan]]
Trash.GLOW_ART = [[Interface\AddOns\Blackthornes_Farmer\Media\Trash\PickGlow]]
-- How far the glow reaches past each edge of the slot, as a share of its
-- side (the art's slot sits a seventh of the way in from each side).
Trash.GLOW_REACH = 0.2
-- The can's side, as a share of the item button's.
Trash.SHARE = 0.6
-- A trade good counts as this many times its worth when picking, so junk
-- worth up to half as much again goes first.
Trash.MATERIAL_LEAN = 1.5
-- Enum.ItemClass.Tradegoods on every build.
local TRADE_GOODS = 7

local MAX_FRAMES = 13
local MAX_BUTTONS = 36

-- ["bag:slot"] = { bag, slot, key, worth, unit, itemID, link, count, id,
-- stack, itemLink, weight } from the last read; worth is nil for a slot that
-- may not be thrown away. id, stack and itemLink are what the slot holds
-- either way, for stacking.
Trash.slots = {}

local function Field(object, key)
    if type(object) ~= "table" then return nil end
    local ok, value = pcall(function() return object[key] end)
    if ok then return value end
    return nil
end

local function Ask(object, method, ...)
    local fn = Field(object, method)
    if type(fn) ~= "function" then return nil end
    local ok, value = pcall(fn, object, ...)
    if ok then return value end
    return nil
end

local function Container(name, ...)
    local api = rawget(_G, "C_Container")
    local fn = type(api) == "table" and api[name] or rawget(_G, name)
    if type(fn) ~= "function" then return nil end
    local results = { pcall(fn, ...) }
    if not results[1] then return nil end
    return unpack(results, 2)
end

-- A client number as a plain one; a secret value reads as nil.
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
    return type(fn) == "function" and fn() and true or false
end

local function Holding()
    local fn = rawget(_G, "GetCursorInfo")
    if type(fn) ~= "function" then return false end
    local ok, what = pcall(fn)
    return ok and what ~= nil
end

function Trash:Enabled()
    return ns.db ~= nil and ns.db.trashCan ~= false
end

--- Butler is loaded and draws its own can, so Farmer's stands down.
function Trash.ButlerHasIt()
    return type(Field(rawget(_G, "BlackthornesButler"), "Trash")) == "table"
end

--- Turn the can on or off (Settings and /farm trash).
function Trash:SetEnabled(on)
    ns.db.trashCan = on and true or false
    if on then self:Changed() else self:Hide() end
end

--------------------------------------------------------------------------------
-- The bags
--------------------------------------------------------------------------------

--- The bags that take anything, and how many of their slots are free:
--- { bags = { { bag, total }, ... }, free }, or nil when the client says
--- nothing.
function Trash.Space()
    local last = Number(rawget(_G, "NUM_BAG_SLOTS")) or 4
    local reagent = Field(Field(rawget(_G, "Enum"), "BagIndex"), "ReagentBag")
    local result, any = { bags = {}, free = 0 }, false
    for bag = 0, last do
        local total = Number(Container("GetContainerNumSlots", bag))
        if total and total > 0 and bag ~= reagent then
            local free, family = Container("GetContainerNumFreeSlots", bag)
            free, family = Number(free), Number(family) or 0
            if free and family == 0 then
                any = true
                result.free = result.free + free
                result.bags[#result.bags + 1] = { bag = bag, total = total }
            end
        end
    end
    return any and result or nil
end

local function Name(link)
    if type(link) ~= "string" then return nil end
    local ok, name = pcall(function() return link:match("%[(.-)%]") end)
    return ok and name or nil
end

--- What one slot is worth in all when it may be thrown away, then one's
--- worth, its item ID, link and count; nil when it may not. `info` is the
--- client's GetContainerItemInfo table.
function Trash:Worth(bag, slot, info)
    local ok, itemID, link, count, quality, bound, noValue, locked = pcall(function()
        return info.itemID, info.hyperlink, tonumber(info.stackCount) or 1, tonumber(info.quality),
            info.isBound and true or false, info.hasNoValue and true or false, info.isLocked and true or false
    end)
    if not ok or not itemID or locked or noValue then return nil end

    local quest = Container("GetContainerItemQuestInfo", bag, slot)
    if type(quest) == "table" then
        local plain = pcall(function()
            if quest.isQuestItem or quest.questID then error("quest") end
        end)
        if not plain then return nil end
    end

    local grey = quality == 0
    if bound and not grey then return nil end
    -- Gear that could be worn may be someone's upgrade; only grey gear goes.
    if not grey then
        local getInstant = Field(rawget(_G, "C_Item"), "GetItemInfoInstant") or rawget(_G, "GetItemInfoInstant")
        if type(getInstant) == "function" then
            local fine, _, _, _, equipLoc = pcall(getInstant, itemID)
            if fine and type(equipLoc) == "string" and equipLoc ~= "" then return nil end
        end
    end

    -- What a goal of this character counts.
    local name = Name(link)
    if name and ns.Goals and ns.Goals:Find(name) then return nil end

    local unit = Number(ns.Value and ns.Value:UnitPrice(itemID))
    if not unit or unit <= 0 then return nil end
    return unit * count, unit, itemID, link, count
end

--- Read the bags that take anything, a few dozen slots a frame, then run
--- `done`. Only a slot whose item, count or lock changed is priced again.
function Trash:Scan(space, done)
    if self.scanning then
        self.again = done
        return
    end
    self.scanning = true
    local places = {}
    for _, entry in ipairs(space.bags) do
        for slot = 1, entry.total do places[#places + 1] = { entry.bag, slot } end
    end
    local seen, index = {}, 0

    local function Step()
        local stop = math.min(#places, index + Trash.BUDGET)
        for i = index + 1, stop do
            local bag, slot = places[i][1], places[i][2]
            local place = bag .. ":" .. slot
            local info = Container("GetContainerItemInfo", bag, slot)
            if type(info) == "table" then
                local okKey, key = pcall(function()
                    -- A goal set or removed changes what may go.
                    return ("%s:%s:%s:%s"):format(tostring(info.hyperlink or info.itemID),
                        tostring(info.stackCount), info.isLocked and "l" or "",
                        tostring(ns.Goals and ns.Goals.version or 0))
                end)
                key = okKey and key or nil
                seen[place] = true
                local old = Trash.slots[place]
                if not (old and key and old.key == key) then
                    -- One odd item costs its slot, never the can until /reload.
                    local fine, worth, unit, itemID, link, count = pcall(Trash.Worth, Trash, bag, slot, info)
                    if not fine then worth, unit, itemID, link, count = nil, nil, nil, nil, nil end
                    local okRaw, id, stack, itemLink, locked = pcall(function()
                        return info.itemID, tonumber(info.stackCount) or 1, info.hyperlink, info.isLocked and true or false
                    end)
                    if not okRaw then id, stack, itemLink, locked = nil, nil, nil, true end
                    local weight = worth
                    if worth and Trash.ClassOf(itemID) == TRADE_GOODS then weight = worth * Trash.MATERIAL_LEAN end
                    Trash.slots[place] = { bag = bag, slot = slot, key = key, worth = worth, unit = unit,
                        itemID = itemID, link = link, count = count, weight = weight,
                        id = id, stack = stack, itemLink = itemLink, locked = locked }
                end
            end
        end
        index = stop
        if index < #places then
            C_Timer.After(0, Step)
            return
        end
        for place in pairs(Trash.slots) do
            if not seen[place] then Trash.slots[place] = nil end
        end
        Trash.scanning = false
        local again = Trash.again
        Trash.again = nil
        if again then return Trash:Scan(space, again) end
        if done then done() end
    end
    Step()
end

--- The item's class ID from what the client always has, or nil.
function Trash.ClassOf(itemID)
    local getInstant = Field(rawget(_G, "C_Item"), "GetItemInfoInstant") or rawget(_G, "GetItemInfoInstant")
    if type(getInstant) ~= "function" then return nil end
    local ok, _, _, _, _, _, classID = pcall(getInstant, itemID)
    return ok and Number(classID) or nil
end

--- How many of an item fit in one slot, or nil while the client does not say.
function Trash.MaxStack(itemID)
    local getInfo = Field(rawget(_G, "C_Item"), "GetItemInfo") or rawget(_G, "GetItemInfo")
    if type(getInfo) ~= "function" then return nil end
    local ok, name, _, _, _, _, _, _, max = pcall(getInfo, itemID)
    if not ok or not name then return nil end
    return Number(max)
end

--- Two short stacks of one item that fit in one slot, from the last read:
--- { merge = true, bag, slot, itemID, link, count, to }, or nil. The smaller
--- stack goes onto the fullest one that still has room for it.
function Trash:Merge()
    local byItem = {}
    for _, entry in pairs(self.slots) do
        if entry.id and not entry.locked then
            local list = byItem[entry.id]
            if not list then
                list = {}
                byItem[entry.id] = list
            end
            list[#list + 1] = entry
        end
    end
    local function Before(a, b)
        if a.stack ~= b.stack then return a.stack < b.stack end
        if a.bag ~= b.bag then return a.bag < b.bag end
        return a.slot < b.slot
    end
    local best
    for id, list in pairs(byItem) do
        local max = #list > 1 and self.MaxStack(id)
        if max and max > 1 then
            table.sort(list, Before)
            local from, to = list[1], nil
            for i = #list, 2, -1 do
                if from.stack + list[i].stack <= max then
                    to = list[i]
                    break
                end
            end
            if to and (not best or Before(from, best.from)) then
                best = { merge = true, bag = from.bag, slot = from.slot, itemID = id, link = from.itemLink,
                    count = from.stack, to = to, from = from }
            end
        end
    end
    return best
end

--- The stack worth least from the last read, or nil. A trade good is
--- weighed at MATERIAL_LEAN times its worth.
function Trash:Pick()
    local best
    for _, entry in pairs(self.slots) do
        if entry.worth and (not best or entry.weight < best.weight
            or (entry.weight == best.weight and (entry.bag < best.bag
                or (entry.bag == best.bag and entry.slot < best.slot)))) then
            best = entry
        end
    end
    return best
end

--------------------------------------------------------------------------------
-- The game's bag windows
--------------------------------------------------------------------------------

function Trash:Frames()
    local frames = {}
    local combined = rawget(_G, "ContainerFrameCombinedBags")
    if type(combined) == "table" then frames[#frames + 1] = combined end
    local count = Number(rawget(_G, "NUM_CONTAINER_FRAMES")) or MAX_FRAMES
    for i = 1, count do
        local frame = rawget(_G, "ContainerFrame" .. i)
        if type(frame) == "table" then frames[#frames + 1] = frame end
    end
    return frames
end

function Trash:ShownFrames()
    local shown = {}
    for _, frame in ipairs(self:Frames()) do
        if Ask(frame, "IsShown") then shown[#shown + 1] = frame end
    end
    return shown
end

function Trash:Buttons(frame)
    local buttons = {}
    local enumerate = Field(frame, "EnumerateValidItems")
    if type(enumerate) == "function" then
        local ok = pcall(function()
            for _, button in enumerate(frame) do buttons[#buttons + 1] = button end
        end)
        if ok and #buttons > 0 then return buttons end
        buttons = {}
    end
    local name = Ask(frame, "GetName")
    if type(name) == "string" then
        for i = 1, MAX_BUTTONS do
            local button = rawget(_G, name .. "Item" .. i)
            if type(button) ~= "table" then break end
            buttons[#buttons + 1] = button
        end
    end
    return buttons
end

--- The shown item button for a bag slot, or nil.
function Trash:FindButton(frames, bag, slot)
    for _, frame in ipairs(frames) do
        for _, button in ipairs(self:Buttons(frame)) do
            local buttonBag = Ask(button, "GetBagID")
            if type(buttonBag) ~= "number" then buttonBag = Ask(Ask(button, "GetParent") or frame, "GetID") end
            if buttonBag == bag and Ask(button, "GetID") == slot and Ask(button, "IsVisible") then
                return button
            end
        end
    end
    return nil
end

--- Hear the bag windows open, close and redraw: hooks only, once each.
function Trash:InstallHooks()
    self.hooked = self.hooked or {}
    local hook = rawget(_G, "hooksecurefunc")
    for _, frame in ipairs(self:Frames()) do
        if not self.hooked[frame] then
            self.hooked[frame] = true
            if type(hook) == "function" and type(Field(frame, "UpdateItems")) == "function" then
                pcall(hook, frame, "UpdateItems", function() Trash:Changed() end)
            end
            if type(Field(frame, "HookScript")) == "function" then
                pcall(frame.HookScript, frame, "OnShow", function() Trash:Changed() end)
                pcall(frame.HookScript, frame, "OnHide", function() Trash:Changed() end)
            end
        end
    end
    if type(hook) == "function" and not self.hookedUpdate and type(rawget(_G, "ContainerFrame_Update")) == "function" then
        self.hookedUpdate = pcall(hook, "ContainerFrame_Update", function() Trash:Changed() end)
    end
end

--------------------------------------------------------------------------------
-- The can
--------------------------------------------------------------------------------

function Trash:Can()
    if self.can then return self.can end
    local can = CreateFrame("Button", "BlackthornesFarmerTrashCan", UIParent)
    can:SetSize(16, 16)
    can:Hide()
    local icon = can:CreateTexture(nil, "OVERLAY")
    icon:SetAllPoints(can)
    icon:SetTexture(self.ART)
    can.icon = icon
    -- A slow pulse (size and glow) so it is easy to spot among the icons.
    pcall(function()
        local group = can:CreateAnimationGroup()
        group:SetLooping("BOUNCE")
        local fade = group:CreateAnimation("Alpha")
        fade:SetFromAlpha(1)
        fade:SetToAlpha(0.5)
        fade:SetDuration(0.6)
        fade:SetSmoothing("IN_OUT")
        local grow = group:CreateAnimation("Scale")
        grow:SetScaleFrom(1, 1)
        grow:SetScaleTo(1.3, 1.3)
        grow:SetDuration(0.6)
        grow:SetSmoothing("IN_OUT")
        grow:SetOrigin("CENTER", 0, 0)
        can.pulse = group
    end)
    can:SetScript("OnShow", function(owner)
        if owner.pulse then pcall(owner.pulse.Play, owner.pulse) end
    end)
    can:SetScript("OnHide", function(owner)
        if owner.pulse then pcall(owner.pulse.Stop, owner.pulse) end
    end)
    can:SetScript("OnClick", function() Trash:Take() end)
    can:SetScript("OnEnter", function(owner) Trash:ShowTooltip(owner) end)
    can:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    self.can = can
    return can
end

--- The red glow round the picked slot: our own frame, no mouse, so a click
--- still reaches the item button under it.
function Trash:Glow()
    if self.glow then return self.glow end
    local glow = CreateFrame("Frame", nil, UIParent)
    glow:Hide()
    pcall(glow.EnableMouse, glow, false)
    local texture = glow:CreateTexture(nil, "OVERLAY")
    texture:SetAllPoints(glow)
    texture:SetTexture(self.GLOW_ART)
    glow.texture = texture
    pcall(function()
        local group = glow:CreateAnimationGroup()
        group:SetLooping("BOUNCE")
        local fade = group:CreateAnimation("Alpha")
        fade:SetFromAlpha(1)
        fade:SetToAlpha(0.45)
        fade:SetDuration(0.8)
        fade:SetSmoothing("IN_OUT")
        glow.pulse = group
    end)
    glow:SetScript("OnShow", function(owner)
        if owner.pulse then pcall(owner.pulse.Play, owner.pulse) end
    end)
    glow:SetScript("OnHide", function(owner)
        if owner.pulse then pcall(owner.pulse.Stop, owner.pulse) end
    end)
    self.glow = glow
    return glow
end

function Trash:Hide()
    self.pick = nil
    if self.glow then
        self.glow:Hide()
        if Ask(self.glow, "GetParent") ~= UIParent then pcall(self.glow.SetParent, self.glow, UIParent) end
    end
    if self.can then
        self.can:Hide()
        if Ask(self.can, "GetParent") ~= UIParent then pcall(self.can.SetParent, self.can, UIParent) end
    end
end

--- Lay the can on the picked item's button.
function Trash:Place(frames)
    self.waiting = false
    if self.stale then return self:Changed() end
    -- A fight or a vendor may have come while the bags were read.
    if self:IsOff() or Holding() then return self:Hide() end
    local pick = self:Merge() or self:Pick()
    local button = pick and self:FindButton(frames, pick.bag, pick.slot)
    if not button then return self:Hide() end

    local can = self:Can()
    self.pick = pick
    -- A child of the item button it sits on, so it is drawn with that
    -- button, at its scale and strata, over it. Our own frame; nothing is
    -- written on the game's.
    if Ask(can, "GetParent") ~= button then pcall(can.SetParent, can, button) end
    local size = (Number(Ask(button, "GetWidth")) or 37) * self.SHARE
    can:SetSize(size, size)
    can:SetFrameLevel((Number(Ask(button, "GetFrameLevel")) or 1) + 10)
    can:ClearAllPoints()
    can:SetPoint("TOPRIGHT", button, "TOPRIGHT", 1, 1)
    can:Show()

    local glow = self:Glow()
    if Ask(glow, "GetParent") ~= button then pcall(glow.SetParent, glow, button) end
    local reach = (Number(Ask(button, "GetWidth")) or 37) * self.GLOW_REACH
    glow:SetFrameLevel((Number(Ask(button, "GetFrameLevel")) or 1) + 9)
    glow:ClearAllPoints()
    glow:SetPoint("TOPLEFT", button, "TOPLEFT", -reach, reach)
    glow:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", reach, -reach)
    glow:Show()
end

local function Off(self)
    return not self:Enabled() or self.ButlerHasIt() or InCombat() or self.atVendor
end

function Trash:IsOff()
    return Off(self)
end

--- Look again once the burst is over.
function Trash:Changed()
    self.stale = true
    if self.settling or self.waiting then return end
    if Off(self) then return self:Hide() end
    self.settling = true
    C_Timer.After(self.SETTLE, function()
        Trash.settling = false
        Trash:Refresh()
    end)
end

function Trash:Refresh()
    self.stale = false
    -- While the cursor holds something (the item the can picked up, say),
    -- the can waits rather than jump to the next item.
    if Off(self) or Holding() then return self:Hide() end
    local frames = self:ShownFrames()
    if #frames == 0 then return self:Hide() end
    local space = Trash.Space()
    if not space or space.free > self.FREE then return self:Hide() end
    self.waiting = true
    self:Scan(space, function() Trash:Place(frames) end)
end

local function ItemText(entry)
    local text = entry.link or L.Format("item %s", tostring(entry.itemID))
    if (entry.count or 1) > 1 then text = L.Format("%s x%d", text, entry.count) end
    return text
end

function Trash:ShowTooltip(owner)
    local pick = self.pick
    if not (pick and GameTooltip) then return end
    pcall(function()
        GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
        if pick.merge then
            GameTooltip:AddLine(L["Stack these to make room"], 1, 0.82, 0)
            GameTooltip:AddLine(ItemText(pick), 1, 1, 1)
            GameTooltip:AddLine(L.Format("It fits on your other stack of %d.", pick.to.stack), 1, 1, 1, true)
            GameTooltip:AddLine(L["Click to stack them. Nothing is thrown away."], 0.2, 1, 0.2, true)
            GameTooltip:Show()
            return
        end
        GameTooltip:AddLine(L["Throw away to make room"], 1, 0.82, 0)
        GameTooltip:AddLine(ItemText(pick), 1, 1, 1)
        GameTooltip:AddLine(L.Format("Worth %s in all, the least in your bags", ns.Value.Coins(pick.worth)),
            1, 1, 1, true)
        GameTooltip:AddLine(L["Click to pick it up."],
            0.2, 1, 0.2, true)
        GameTooltip:Show()
    end)
end

--- The click: pick the item up, after making sure it is still there.
--- Farmer never deletes it; the game's own box asks when it is dropped.
function Trash:Take()
    local pick = self.pick
    if not pick or InCombat() then return false end
    if pick.merge then return self:Stack(pick) end
    local info = Container("GetContainerItemInfo", pick.bag, pick.slot)
    local same = type(info) == "table" and pcall(function()
        if info.itemID ~= pick.itemID or (tonumber(info.stackCount) or 1) ~= pick.count or info.isLocked then
            error("moved")
        end
    end)
    -- A goal set since the can was placed: that item stays.
    local name = Name(pick.link)
    if same and name and ns.Goals and ns.Goals:Find(name) then same = false end
    if not same then
        self:Changed()
        return false
    end
    if Holding() then
        ns.Print(L["Your cursor is already holding something. Put it down first."])
        return false
    end
    Container("PickupContainerItem", pick.bag, pick.slot)
    if GameTooltip then GameTooltip:Hide() end
    ns.Print(L.Format("%s is on your cursor. Drop it outside your bags and the game will ask before it is destroyed, or click its bag slot to put it back.",
        ItemText(pick)))
    return true
end

--- Whether a slot still holds what the last read saw there.
local function Still(bag, slot, itemID, count)
    local info = Container("GetContainerItemInfo", bag, slot)
    return type(info) == "table" and pcall(function()
        if info.itemID ~= itemID or (tonumber(info.stackCount) or 1) ~= count or info.isLocked then
            error("moved")
        end
    end)
end

--- The click on a stack: pick the smaller stack up and drop it on the
--- other, and the game joins them. Nothing is thrown away.
function Trash:Stack(pick)
    if not (Still(pick.bag, pick.slot, pick.itemID, pick.count)
        and Still(pick.to.bag, pick.to.slot, pick.itemID, pick.to.stack)) then
        self:Changed()
        return false
    end
    if Holding() then
        ns.Print(L["Your cursor is already holding something. Put it down first."])
        return false
    end
    Container("PickupContainerItem", pick.bag, pick.slot)
    Container("PickupContainerItem", pick.to.bag, pick.to.slot)
    if GameTooltip then GameTooltip:Hide() end
    return true
end

function Trash:OnEnable()
    ns.RegisterEvent(self, "BAG_UPDATE_DELAYED", function() Trash:Changed() end)
    ns.RegisterEvent(self, "BAG_CONTAINER_UPDATE", function() Trash:Changed() end)
    ns.RegisterEvent(self, "CURSOR_CHANGED", function() Trash:Changed() end)
    ns.RegisterEvent(self, "PLAYER_ENTERING_WORLD", function()
        Trash:InstallHooks()
        Trash:Changed()
    end)
    ns.RegisterEvent(self, "PLAYER_REGEN_DISABLED", function() Trash:Hide() end)
    ns.RegisterEvent(self, "PLAYER_REGEN_ENABLED", function() Trash:Changed() end)
    ns.RegisterEvent(self, "MERCHANT_SHOW", function()
        Trash.atVendor = true
        Trash:Hide()
    end)
    ns.RegisterEvent(self, "MERCHANT_CLOSED", function()
        Trash.atVendor = false
        Trash:Changed()
    end)
end

ns.RegisterCommand("trash", L["show or hide the trash can on the item worth the least when your bags are full"], function()
    Trash:SetEnabled(not Trash:Enabled())
    ns.Print(Trash:Enabled() and L["the trash can shows on the item worth the least when your bags are full."]
        or L["the trash can no longer shows when your bags are full."])
end)
