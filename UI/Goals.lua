-- Blackthornes Farmer -- UI/Goals.lua
-- The Goals panel, and the picker that sets a goal from a search result
-- (Trent, 2026-09-27: "an onscreen UI element that shows how many you have
-- and how many left to gather with dopamine built in").
--
-- The panel hangs under the Kills & Loot panel until you drag it somewhere
-- else. Each goal is a card: icon, name, "23 / 40", a bar with marks at a
-- quarter, half and three quarters, how many are left, and how long that
-- should take at your pace (or the best place to get it, until there is a
-- pace).
--
-- When the count goes up:
--   * the number counts up and pops, the bar slides and a shine runs along it
--   * "+3 Copper Ore" floats off the card's right edge
--   * the card washes green; passing 25%, half or 75% pulses it gold and
--     puts a tag beside the name
--   * the last stretch turns the bar green and says "3 more!"
--   * the last one drops a GOAL COMPLETE banner over the panel with
--     sparkles and the drop-rates-unlocked sound, and the card turns into a
--     short recap
--
-- The effects follow /farm effects, like the kills panel: Subtle keeps the
-- washes, count-up and slide; Off keeps none. They compare the addon's own
-- counts and never read the client, and anything that goes wrong is
-- dropped rather than raised.

local _, ns = ...

local GoalsUI = ns.NewModule("GoalsUI")

local Theme = ns.Theme
local Widgets = ns.Widgets
local Util = ns.Util

local WIDTH = 236
-- As tall as the kills panel's title line, which it docks under.
local HEADER = 28
local PADDING = 8
local CARD = 62
-- As wide as the widest line needs, up to this, so nothing is cut off.
local MAX_WIDTH = 380
local FOOTER = 22
local ICON = 22
local BAR_HEIGHT = 7
local GAP = 6

GoalsUI.CARD = CARD
GoalsUI.HEADER = HEADER

local FALLBACK_ICON = [[Interface\Icons\INV_Misc_QuestionMark]]

-- Timings, in seconds.
local COUNT_TIME = 0.7
local SLIDE_TIME = 0.5
local SHINE_TIME = 0.8
local GLOW_TIME = 1.3
local PULSE_TIME = 2.2
local POP_TIME = 0.4
local FLOAT_TIME = 1.8
local FLOAT_RISE = 30
local BANNER_TIME = 4
local BANNER_HEIGHT = 44

local COUNT_SIZE = 14
local POP_SIZE = 20
local SHINE_WIDTH = 26

local BRIGHT_GOLD = { 1, 0.906, 0.639 }

GoalsUI.cards = {}
GoalsUI.effects = {}

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local function Color(key)
    local r, g, b = Theme.Unpack(key)
    return { r, g, b }
end

local function EaseOut(p)
    return 1 - (1 - p) ^ 3
end

local function Level()
    if ns.TrackerFX then return ns.TrackerFX.Level() end
    return "full"
end

--- "23 / 40", the first part bright.
function GoalsUI.CountText(have, target)
    return ("%s|c%s / %d|r"):format(tostring(math.floor(have + 0.5)), ns.COLORS.muted, target)
end

local function IconOf(name)
    local look = ns.Tracker and ns.Tracker:LookOf(name) or {}
    if look.icon then return look.icon end

    local id = ns.Value and ns.Value:ItemID(name)
    if id and type(C_Item) == "table" and type(C_Item.GetItemIconByID) == "function" then
        local ok, icon = pcall(C_Item.GetItemIconByID, id)
        if ok and icon then
            local readable = ns.Harvest.ReadableNumber(icon) or ns.Harvest.Readable(icon)
            if readable then return readable end
        end
    end

    return FALLBACK_ICON
end

--------------------------------------------------------------------------------
-- The clock
--
-- Its own, on a frame of UIParent's: the kills panel's clock stops when that
-- panel is hidden, and the goals panel may well be showing without it.
--------------------------------------------------------------------------------

function GoalsUI:Driver()
    if self.driver then return self.driver end

    local driver = CreateFrame("Frame", nil, UIParent)
    driver:SetScript("OnUpdate", function(_, elapsed) GoalsUI:Step(elapsed) end)
    driver:Hide()

    self.driver = driver
    return driver
end

--- Start `effect`: { slot, duration, delay, apply(p), stop() }. A new effect
--- in the same slot replaces the one there.
function GoalsUI:Animate(effect)
    for index = #self.effects, 1, -1 do
        local other = self.effects[index]
        if effect.slot and other.slot == effect.slot then
            if other.stop then pcall(other.stop) end
            table.remove(self.effects, index)
        end
    end

    effect.age = -(effect.delay or 0)
    self.effects[#self.effects + 1] = effect
    -- Drawn at its start straight away, so the finished state never shows
    -- for a frame first.
    if not effect.delay then pcall(effect.apply, 0) end
    self:Driver():Show()
end

function GoalsUI:Step(elapsed)
    elapsed = tonumber(elapsed) or 0
    local live = {}

    for _, effect in ipairs(self.effects) do
        effect.age = effect.age + elapsed

        if effect.age >= 0 then
            local p = math.min(1, effect.age / effect.duration)
            local ok, err = pcall(effect.apply, p)

            if not ok then
                if effect.stop then pcall(effect.stop) end
                ns.Debug("goal effect dropped:", tostring(err))
            elseif p < 1 then
                live[#live + 1] = effect
            end
        else
            live[#live + 1] = effect
        end
    end

    self.effects = live
    if #live == 0 and self.driver then self.driver:Hide() end
end

--- Stop the effects running on `card`, put back as they were. For a card
--- about to show a different goal: a glow or count still running there
--- belonged to the goal that was on it.
function GoalsUI:StopCard(card)
    local slots = { [card.flash] = true, [card.count] = true, [card.fill] = true,
        [card.fresh] = true, [card.shine] = true }
    local live = {}
    for _, effect in ipairs(self.effects) do
        if effect.slot and slots[effect.slot] then
            if effect.stop then pcall(effect.stop) end
        else
            live[#live + 1] = effect
        end
    end
    self.effects = live
end

--- Everything stopped and put back.
function GoalsUI:Forget()
    for _, effect in ipairs(self.effects) do
        if effect.stop then pcall(effect.stop) end
    end
    self.effects = {}
    if self.driver then self.driver:Hide() end
end

--------------------------------------------------------------------------------
-- The panel
--------------------------------------------------------------------------------

function GoalsUI:Width()
    -- Docked under the kills panel, as wide as it is on screen (it widens
    -- past its saved width to fit its lines), so the two line up.
    local tracker = ns.TrackerUI and ns.TrackerUI.frame
    if not ns.db.goalsX and tracker and tracker:IsShown() then
        local ok, width = pcall(tracker.GetWidth, tracker)
        if ok and type(width) == "number" and width > 0 then
            return math.min(MAX_WIDTH, math.floor(width + 0.5))
        end
    end
    if ns.TrackerUI and ns.TrackerUI.Width then return ns.TrackerUI:Width() end
    return WIDTH
end

function GoalsUI:Build()
    if self.frame then return self.frame end

    local frame = CreateFrame("Frame", "BlackthornesFarmerGoals", UIParent)
    frame:SetSize(self:Width(), HEADER + CARD)
    frame:SetFrameStrata("LOW")
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")

    -- Solid enough that name plates and chat behind it do not show through
    -- the text (Trent's screenshot, 2026-09-27).
    Theme.Fill(frame, "window", 0.96)
    Theme.Border(frame, "border")

    frame:SetScript("OnDragStart", function(self)
        GoalsUI.dragging = true
        self:StartMoving()
    end)
    frame:SetScript("OnDragStop", function(self)
        GoalsUI.dragging = nil
        self:StopMovingOrSizing()
        GoalsUI:SavePosition()
    end)

    local header = Theme.CreatePanel(frame, "header", false)
    header:SetPoint("TOPLEFT")
    header:SetPoint("TOPRIGHT")
    header:SetHeight(HEADER)

    Theme.HouseHeader(header)

    local title = Theme.CreateLabel(header, "normal", "accent")
    title:SetPoint("LEFT", PADDING + 4, 0)
    title:SetText("Goals")

    local close = Widgets.CreateButton(header, "X", function()
        ns.db.goalsHidden = true
        GoalsUI:Refresh()
        ns.Print("goals panel hidden. /farm goals brings it back.")
    end, { width = 18, height = 16, danger = true })
    close:SetPoint("RIGHT", -6, 0)

    local rule = Theme.CreateDivider(frame, "borderLit")
    rule:SetPoint("TOPLEFT", header, "BOTTOMLEFT")
    rule:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT")

    -- Goals done today, and a way to the next one.
    local footer = CreateFrame("Frame", nil, frame)
    footer:SetPoint("BOTTOMLEFT", 1, 1)
    footer:SetPoint("BOTTOMRIGHT", -1, 1)
    footer:SetHeight(FOOTER)
    Theme.Fill(footer, "header", 0.9)

    footer.left = Theme.CreateLabel(footer, "small", "muted")
    footer.left:SetPoint("LEFT", PADDING, 0)

    footer.next = Widgets.CreateButton(footer, "Set another", function()
        if ns.UI then
            ns.UI:Show()
            -- The search box is on the Search tab: focused while the window
            -- shows Rankings, it would take your keys out of sight.
            if ns.UI.tab ~= "search" then ns.UI:ShowTab("search") end
            if ns.UI.searchBox then ns.UI.searchBox:SetFocus() end
        end
    end, { width = 70, height = 16 })
    footer.next:SetPoint("RIGHT", -PADDING + 2, 0)

    self.frame = frame
    self.header = header
    self.title = title
    self.closeButton = close
    self.footer = footer

    self:RestorePosition()
    frame:Hide()
    return frame
end

--- One goal's card, made the first time it is needed.
function GoalsUI:Card(index)
    local card = self.cards[index]
    if card then return card end

    local frame = self.frame
    card = CreateFrame("Button", nil, frame)
    card:SetHeight(CARD)
    card:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    card.band = Theme.Fill(card, "row", 1)

    -- The wash and the left edge the effects light up.
    card.flash = card:CreateTexture(nil, "BORDER")
    card.flash:SetAllPoints(card)
    pcall(card.flash.SetBlendMode, card.flash, "ADD")
    card.flash:SetAlpha(0)

    card.edge = card:CreateTexture(nil, "ARTWORK")
    card.edge:SetPoint("TOPLEFT")
    card.edge:SetPoint("BOTTOMLEFT")
    card.edge:SetWidth(2)
    card.edge:SetAlpha(0)

    card.outline = {}
    for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
        local line = card:CreateTexture(nil, "ARTWORK")
        if side == "TOP" or side == "BOTTOM" then
            line:SetPoint(side .. "LEFT")
            line:SetPoint(side .. "RIGHT")
            line:SetHeight(1)
        else
            line:SetPoint("TOP" .. side)
            line:SetPoint("BOTTOM" .. side)
            line:SetWidth(1)
        end
        line:SetAlpha(0)
        card.outline[#card.outline + 1] = line
    end

    card.iconBorder = card:CreateTexture(nil, "ARTWORK")
    card.iconBorder:SetSize(ICON + 2, ICON + 2)
    card.iconBorder:SetPoint("TOPLEFT", PADDING - 1, -5)
    card.iconBorder:SetColorTexture(Theme.Unpack("borderLit"))

    card.icon = card:CreateTexture(nil, "OVERLAY")
    card.icon:SetSize(ICON, ICON)
    card.icon:SetPoint("TOPLEFT", PADDING, -6)
    card.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    card.name = Theme.CreateLabel(card, "normal", "text")
    card.name:SetPoint("TOPLEFT", PADDING + ICON + 8, -6)

    card.sub = Theme.CreateLabel(card, "tiny", "muted")
    card.sub:SetPoint("TOPLEFT", card.name, "BOTTOMLEFT", 0, -2)

    -- The best places near you to farm it (Trent, 2026-09-27).
    card.where = Widgets.CreateButton(card, "Where?", function()
        if card.goal then GoalsUI:OpenSpots(card.goal.item, GoalsUI.frame) end
    end, { width = 46, height = 15, labelKey = "accent" })
    card.where:HookScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)
    card.where:HookScript("OnEnter", function(self)
        if GameTooltip then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine("Best places near you to farm this")
            GameTooltip:Show()
        end
    end)

    -- The milestone tag: dark text on a gold chip.
    card.tagBack = card:CreateTexture(nil, "ARTWORK")
    card.tagBack:SetColorTexture(Theme.Unpack("accent"))
    card.tagBack:SetHeight(12)

    card.tag = Theme.CreateLabel(card, "tiny", "window", "CENTER")
    card.tag:SetPoint("LEFT", card.name, "RIGHT", 8, 0)
    card.tagBack:SetPoint("TOPLEFT", card.tag, "TOPLEFT", -4, 1)
    card.tagBack:SetPoint("BOTTOMRIGHT", card.tag, "BOTTOMRIGHT", 4, -1)

    card.count = Theme.CreateLabel(card, "large", "text", "RIGHT")
    pcall(card.count.SetFont, card.count, Theme.FONT, COUNT_SIZE, "OUTLINE")
    card.count:SetPoint("TOPRIGHT", -PADDING, -8)

    -- The bar: a dark track, the fill, a brighter tip, the part just
    -- gathered, and a shine that runs along it.
    card.track = card:CreateTexture(nil, "BORDER")
    card.track:SetPoint("TOPLEFT", PADDING, -36)
    card.track:SetPoint("TOPRIGHT", -PADDING, -36)
    card.track:SetHeight(BAR_HEIGHT)
    card.track:SetColorTexture(Theme.Unpack("window"))

    card.fill = card:CreateTexture(nil, "ARTWORK")
    card.fill:SetPoint("TOPLEFT", card.track, "TOPLEFT")
    card.fill:SetHeight(BAR_HEIGHT)

    card.tip = card:CreateTexture(nil, "OVERLAY")
    card.tip:SetPoint("TOPRIGHT", card.fill, "TOPRIGHT")
    card.tip:SetSize(4, BAR_HEIGHT)
    card.tip:SetColorTexture(BRIGHT_GOLD[1], BRIGHT_GOLD[2], BRIGHT_GOLD[3], 0.9)

    card.fresh = card:CreateTexture(nil, "OVERLAY")
    card.fresh:SetHeight(BAR_HEIGHT)
    card.fresh:SetColorTexture(1, 0.95, 0.8, 1)
    pcall(card.fresh.SetBlendMode, card.fresh, "ADD")
    card.fresh:SetAlpha(0)

    card.shine = card:CreateTexture(nil, "OVERLAY")
    card.shine:SetSize(SHINE_WIDTH, BAR_HEIGHT)
    card.shine:SetColorTexture(1, 1, 1, 1)
    pcall(card.shine.SetBlendMode, card.shine, "ADD")
    card.shine:SetAlpha(0)

    card.ticks = {}
    for index = 1, 3 do
        local tick = card:CreateTexture(nil, "OVERLAY")
        tick:SetSize(1, BAR_HEIGHT)
        tick:SetColorTexture(1, 1, 1, 0.22)
        card.ticks[index] = tick
    end

    card.left = Theme.CreateLabel(card, "small", "muted")
    card.left:SetPoint("TOPLEFT", card.track, "BOTTOMLEFT", 0, -3)

    card.right = Theme.CreateLabel(card, "tiny", "muted", "RIGHT")

    -- The Where? button sits on the line under the bar, at its right end,
    -- with the time left just before it.
    card.where:SetPoint("TOPRIGHT", card.track, "BOTTOMRIGHT", 0, -3)

    card:SetScript("OnEnter", function(self) GoalsUI:ShowCardTooltip(self) end)
    card:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    card:SetScript("OnClick", function(self, button) GoalsUI:OnCardClick(self, button) end)

    self.cards[index] = card
    return card
end

function GoalsUI:BarWidth()
    local width = (self.frame and self.frame:GetWidth()) or self:Width()
    return math.max(20, width - 2 - PADDING * 2)
end

--- The bar filled to `fraction`, green in the last stretch or when done.
function GoalsUI:SetBar(card, fraction, green)
    local width = self:BarWidth()
    fraction = math.max(0, math.min(1, fraction or 0))

    local r, g, b = Theme.Unpack(green and "good" or "accent")
    card.fill:SetColorTexture(r, g, b, 1)
    card.fill:SetWidth(math.max(1, width * fraction))
    card.fill:SetShown(fraction > 0)

    if green then
        card.tip:SetColorTexture(0.66, 1, 0.77, 0.9)
    else
        card.tip:SetColorTexture(BRIGHT_GOLD[1], BRIGHT_GOLD[2], BRIGHT_GOLD[3], 0.9)
    end
    card.tip:SetShown(fraction > 0.02 and fraction < 1)
end

--- The small grey line under the name: the best place near you, from the
--- same ranking the Where button opens.
local function SpotText(goal)
    local ok, spots = pcall(ns.Spots.For, ns.Spots, goal.item)
    local spot = ok and spots and spots[1]
    if not spot then return "" end

    local distance = ns.Spots.DistanceText(spot.hops, spot.zone)
    if distance == "you are here" then
        return ("%s, %s"):format(spot.name or "?", Util.Colored("good", "here"))
    end
    return ("%s, %s"):format(spot.name or "?", spot.zone or "?")
end

function GoalsUI:DrawCard(card, goal)
    local Goals = ns.Goals
    card.goal = goal

    card.icon:SetTexture(IconOf(goal.item))

    -- The name in its quality colour where the tracker has seen it.
    local look = ns.Tracker and ns.Tracker:LookOf(goal.item) or {}
    -- The name stops short of the count and the milestone tag, both
    -- measured: a width picked by eye let a long name run into "23 / 40".
    local countText = GoalsUI.CountText(goal.have or 0, goal.target or 0)
    local maxName = self:BarWidth() - ICON - 8 - Theme.TextWidth("large", Util.StripColor(countText)) - 10
    local tagText = goal.done and "DONE"
        or ((goal.milestone or 0) > 0 and Goals.MILESTONES[goal.milestone].tag) or nil
    if tagText then maxName = maxName - Theme.TextWidth("tiny", tagText) - 16 end
    local name = goal.item
    if Theme.TextWidth("normal", name) > maxName then
        while #name > 4 and Theme.TextWidth("normal", name .. "...") > maxName do
            name = name:sub(1, -2)
        end
        name = name .. "..."
    end
    card.name:SetText(name)
    if type(look.color) == "string" and #look.color == 8 and look.color ~= "ffffffff" then
        card.name:SetText(("|c%s%s|r"):format(look.color, name))
    end

    local fraction = Goals.Fraction(goal)
    local final = Goals.Final(goal)

    card.count:SetText(GoalsUI.CountText(goal.have or 0, goal.target or 0))
    pcall(card.count.SetFont, card.count, Theme.FONT, COUNT_SIZE, "OUTLINE")

    -- The tag: the last milestone passed, or DONE.
    local tag
    if goal.done then
        tag = "DONE"
    elseif (goal.milestone or 0) > 0 then
        tag = Goals.MILESTONES[goal.milestone].tag
    end
    card.tag:SetText(tag or "")
    card.tag:SetShown(tag ~= nil)
    card.tagBack:SetShown(tag ~= nil)
    card.tagBack:SetColorTexture(Theme.Unpack(goal.done and "good" or "accent"))

    local width = self:BarWidth()
    for index, milestone in ipairs(Goals.MILESTONES) do
        local tick = card.ticks[index]
        tick:ClearAllPoints()
        tick:SetPoint("TOPLEFT", card.track, "TOPLEFT", math.floor(width * milestone.at), 0)
        tick:SetShown(not goal.done)
    end

    self:SetBar(card, fraction, final or goal.done)
    card.where:SetShown(not goal.done)

    card.right:ClearAllPoints()
    if goal.done then
        card.right:SetPoint("TOPRIGHT", card.track, "BOTTOMRIGHT", 0, -5)
    else
        card.right:SetPoint("RIGHT", card.where, "LEFT", -6, 0)
    end
    card.sub:SetWidth(self:BarWidth() - ICON - 8)

    if goal.done then
        local recap = Goals:Recap(goal)
        card.sub:SetText(Util.Colored("good", "Goal done") .. (goal.doneIn and goal.doneIn >= 1
            and Util.Colored("muted", "  in " .. Goals.Duration(goal.doneIn)) or ""))

        local parts = {}
        if recap.loots > 0 then
            parts[#parts + 1] = Util.Plural(recap.loots, "loot")
            if recap.perLoot then
                parts[#parts + 1] = ("%.1f each"):format(recap.perLoot)
            end
        end
        card.left:SetText(table.concat(parts, "  |  "))
        card.left:SetTextColor(Theme.Unpack("muted"))
        card.right:SetText(recap.worth and ns.Value.Coins(recap.worth) or "")
    else
        card.sub:SetText(SpotText(goal))

        local left = Goals.Left(goal)
        if final then
            card.left:SetText(left == 1 and "1 more!" or ("%d more!"):format(left))
            card.left:SetTextColor(Theme.Unpack("good"))
        else
            card.left:SetText(("|c%s%d|r left"):format(ns.COLORS.text, left))
            card.left:SetTextColor(Theme.Unpack("muted"))
        end

        local eta = Goals.Eta(goal)
        card.right:SetText(eta and (Goals.Duration(eta, true) .. " at your pace") or "")
    end

    card:Show()
end

--- How wide a card has to be for none of its text to be cut off or run
--- into something else. Measured, since the game's font runs wider than
--- any width picked by eye.
function GoalsUI:CardNeeds(card, goal)
    local text = Util.StripColor
    local count = Theme.TextWidth("large", text(card.count:GetText())) + 8

    local top = PADDING + ICON + 8 + Theme.TextWidth("normal", goal.item) + count + PADDING
    if card.tag:IsShown() then top = top + Theme.TextWidth("tiny", card.tag:GetText()) + 16 end

    local sub = PADDING + ICON + 8 + Theme.TextWidth("tiny", text(card.sub:GetText())) + PADDING

    local bottom = PADDING * 2 + Theme.TextWidth("small", text(card.left:GetText()))
        + Theme.TextWidth("tiny", text(card.right:GetText())) + 16
    if card.where:IsShown() then bottom = bottom + card.where:GetWidth() + 6 end

    return math.max(top, sub, bottom) + 2
end

function GoalsUI:Render()
    self:Build()

    local list = ns.Goals:List()
    local width = self:Width()
    -- The width it started from, so the kills panel can tell when it has
    -- changed and a redraw is due.
    self.lastBase = width
    self.frame:SetWidth(width)

    -- Draw once at the usual width, measure, and widen and draw again when
    -- a line needs more room.
    local needs = 0
    for index, goal in ipairs(list) do
        local card = self:Card(index)
        if card.goal ~= nil and card.goal ~= goal then self:StopCard(card) end
        self:DrawCard(card, goal)
        needs = math.max(needs, self:CardNeeds(card, goal))
    end
    local fit = math.min(MAX_WIDTH, math.max(width, math.ceil(needs)))
    if fit ~= width then self.frame:SetWidth(fit) end

    for index, goal in ipairs(list) do
        local card = self:Card(index)
        card:ClearAllPoints()
        card:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 1, -(HEADER + GAP / 2 + (index - 1) * (CARD + 2)))
        card:SetPoint("TOPRIGHT", self.frame, "TOPRIGHT", -1, -(HEADER + GAP / 2 + (index - 1) * (CARD + 2)))
        self:DrawCard(card, goal)
    end

    for index = #list + 1, #self.cards do
        self:StopCard(self.cards[index])
        self.cards[index]:Hide()
        self.cards[index].goal = nil
    end

    local done = ns.Goals:DoneToday()
    local anyDone = false
    for _, goal in ipairs(list) do
        if goal.done then anyDone = true end
    end

    local footer = done > 0 or anyDone
    if footer then
        self.footer.left:SetText(("Goals done today: |c%s%d|r"):format(ns.COLORS.accent, done))
    end
    self.footer:SetShown(footer)

    self.frame:SetHeight(HEADER + GAP + #list * (CARD + 2) + (footer and FOOTER or 0))
end

--- Redraw, and show or hide: shown while there are goals, unless you
--- closed it.
function GoalsUI:Refresh()
    self:Build()

    if #ns.Goals:List() == 0 or ns.db.goalsHidden then
        self.frame:Hide()
        self:Forget()
        return
    end

    self:Render()
    self:Place()
    self.frame:Show()
end

function GoalsUI:Show()
    ns.db.goalsHidden = false
    self:Refresh()
end

function GoalsUI:Toggle()
    if self.frame and self.frame:IsShown() then
        ns.db.goalsHidden = true
        self:Refresh()
    else
        self:Show()
    end
end

function GoalsUI:OnEnable()
    self:Refresh()
end

--------------------------------------------------------------------------------
-- The card under the mouse
--------------------------------------------------------------------------------

function GoalsUI:ShowCardTooltip(card)
    local goal = card.goal
    if not (goal and GameTooltip) then return end

    GameTooltip:SetOwner(card, "ANCHOR_RIGHT")
    GameTooltip:AddLine(goal.item)
    GameTooltip:AddLine(("%d of %d"):format(goal.have or 0, goal.target or 0), 1, 1, 1)
    if goal.done then
        GameTooltip:AddLine("Click to clear it.", 0.6, 0.6, 0.6)
    else
        GameTooltip:AddLine("Click to find where to farm it.", 0.6, 0.6, 0.6)
        GameTooltip:AddLine("Right-click to remove the goal.", 0.6, 0.6, 0.6)
    end
    GameTooltip:Show()
end

function GoalsUI:OnCardClick(card, button)
    local goal = card.goal
    if not goal then return end

    if goal.done then
        ns.Goals:Remove(goal.item)
        return
    end

    if button == "RightButton" then
        ns.Goals:Remove(goal.item)
        ns.Print(("goal for %s removed."):format(Util.Colored("accent", goal.item)))
        return
    end

    if ns.RunSearch then ns.RunSearch(goal.item) end
end

--------------------------------------------------------------------------------
-- Effects
--------------------------------------------------------------------------------

local function CardFor(goal)
    for _, card in ipairs(GoalsUI.cards) do
        if card.goal == goal and card:IsShown() then return card end
    end
    return nil
end

function GoalsUI:Glow(card, rgb, peak, duration, beats)
    card.flash:SetColorTexture(rgb[1], rgb[2], rgb[3], 1)
    card.edge:SetColorTexture(rgb[1], rgb[2], rgb[3], 1)
    for _, line in ipairs(card.outline) do line:SetColorTexture(rgb[1], rgb[2], rgb[3], 1) end

    local function Alpha(alpha, outline)
        card.flash:SetAlpha(alpha)
        card.edge:SetAlpha(math.min(1, alpha * 2.5))
        for _, line in ipairs(card.outline) do line:SetAlpha(outline and math.min(1, alpha * 1.8) or 0) end
    end

    self:Animate({ slot = card.flash, duration = duration or GLOW_TIME,
        apply = function(p)
            if beats then
                local beat = 0.55 + 0.45 * math.cos(p * beats * 2 * math.pi)
                Alpha(peak * (1 - p) ^ 1.5 * beat, true)
            else
                Alpha(peak * (1 - p) ^ 2, false)
            end
        end,
        stop = function() Alpha(0, false) end })
end

function GoalsUI:CountUp(card, goal, from, to, pop)
    local target = goal.target or 0

    self:Animate({ slot = card.count, duration = COUNT_TIME,
        apply = function(p)
            local e = EaseOut(p)
            card.count:SetText(GoalsUI.CountText(from + (to - from) * e, target))
            if pop then
                pcall(card.count.SetFont, card.count, Theme.FONT,
                    COUNT_SIZE + (POP_SIZE - COUNT_SIZE) * (1 - EaseOut(math.min(1, p * 1.75))), "OUTLINE")
            end
        end,
        stop = function()
            card.count:SetText(GoalsUI.CountText(card.goal and card.goal.have or to, target))
            pcall(card.count.SetFont, card.count, Theme.FONT, COUNT_SIZE, "OUTLINE")
        end })
end

--- The bar sliding from where it was, the part just gathered lit, and (at
--- Full) a shine running along it once it lands.
function GoalsUI:Slide(card, goal, fromFraction, toFraction, shine)
    local width = self:BarWidth()
    local green = goal.done or ns.Goals.Final(goal)

    self:Animate({ slot = card.fill, duration = SLIDE_TIME,
        apply = function(p)
            self:SetBar(card, fromFraction + (toFraction - fromFraction) * EaseOut(p), green)
        end,
        stop = function() self:SetBar(card, ns.Goals.Fraction(goal), green) end })

    if toFraction > fromFraction then
        card.fresh:ClearAllPoints()
        card.fresh:SetPoint("TOPLEFT", card.track, "TOPLEFT", width * fromFraction, 0)
        card.fresh:SetWidth(math.max(1, width * (toFraction - fromFraction)))

        self:Animate({ slot = card.fresh, duration = GLOW_TIME, delay = SLIDE_TIME * 0.6,
            apply = function(p) card.fresh:SetAlpha(0.6 * (1 - p) ^ 2) end,
            stop = function() card.fresh:SetAlpha(0) end })
    end

    if shine then
        local reach = math.max(SHINE_WIDTH, width * toFraction)
        self:Animate({ slot = card.shine, duration = SHINE_TIME, delay = SLIDE_TIME * 0.5,
            apply = function(p)
                card.shine:ClearAllPoints()
                card.shine:SetPoint("TOPLEFT", card.track, "TOPLEFT",
                    math.max(0, (reach - SHINE_WIDTH) * p), 0)
                card.shine:SetAlpha(0.55 * math.sin(p * math.pi))
            end,
            stop = function() card.shine:SetAlpha(0) end })
    end
end

function GoalsUI:FloatLabel()
    self.floats = self.floats or {}

    for _, label in ipairs(self.floats) do
        if not label.flying then return label end
    end

    if not self.holder then
        self.holder = CreateFrame("Frame", nil, self.frame)
        self.holder:SetAllPoints(self.frame)
        self.holder:SetFrameLevel(self.frame:GetFrameLevel() + 10)
    end

    local label = Theme.CreateLabel(self.holder, "normal", "good")
    label:Hide()
    self.floats[#self.floats + 1] = label
    return label
end

--- "+3 Copper Ore" rising off the card's right edge.
function GoalsUI:Float(card, text, size, delay)
    local label = self:FloatLabel()
    pcall(label.SetFont, label, Theme.FONT, size or 13, "OUTLINE")
    label:SetText(text)
    label:SetAlpha(0)
    label.flying = true

    local function Place(rise)
        label:ClearAllPoints()
        label:SetPoint("LEFT", card, "RIGHT", 8, 6 + rise)
    end

    Place(0)
    label:Show()

    self:Animate({ slot = label, duration = FLOAT_TIME, delay = delay,
        apply = function(p)
            Place(FLOAT_RISE * EaseOut(p))
            label:SetAlpha(p < 0.15 and p / 0.15 or (1 - (p - 0.15) / 0.85))
            if p >= 1 then
                label:Hide()
                label.flying = false
            end
        end,
        stop = function()
            label:Hide()
            label.flying = false
        end })
end

-- Where the sparkles sit on the banner, as fractions across and down.
local SPARKS = {
    { 0.04, 0.2 }, { 0.12, 0.85 }, { 0.3, 0.1 }, { 0.62, 0.9 },
    { 0.8, 0.12 }, { 0.95, 0.75 }, { 0.5, 0.06 }, { 0.2, 0.5 },
    { 0.72, 0.55 }, { 0.88, 0.35 },
}

function GoalsUI:Banner()
    if self.banner then return self.banner end

    local frame = self.frame
    local banner = CreateFrame("Frame", nil, frame)
    banner:SetPoint("TOPLEFT", frame, "TOPLEFT", 4, -(HEADER + 3))
    banner:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -(HEADER + 3))
    banner:SetHeight(BANNER_HEIGHT)
    banner:SetFrameLevel(frame:GetFrameLevel() + 12)

    Theme.Fill(banner, "window", 0.96)
    Theme.Border(banner, "accent")

    local wash = banner:CreateTexture(nil, "BORDER")
    wash:SetAllPoints(banner)
    wash:SetColorTexture(Theme.Unpack("accent"))
    pcall(wash.SetBlendMode, wash, "ADD")
    banner.wash = wash

    local title = Theme.CreateLabel(banner, "large", "accent", "CENTER")
    pcall(title.SetFont, title, Theme.FONT, 15, "OUTLINE")
    title:SetTextColor(BRIGHT_GOLD[1], BRIGHT_GOLD[2], BRIGHT_GOLD[3], 1)
    title:SetPoint("TOPLEFT", 6, -6)
    title:SetPoint("TOPRIGHT", -6, -6)
    banner.title = title

    local subject = Theme.CreateLabel(banner, "small", "text", "CENTER")
    subject:SetPoint("BOTTOMLEFT", 6, 7)
    subject:SetPoint("BOTTOMRIGHT", -6, 7)
    banner.subject = subject

    banner.sparks = {}
    for index = 1, #SPARKS do
        local spark = banner:CreateTexture(nil, "OVERLAY")
        spark:SetSize(3, 3)
        spark:SetColorTexture(BRIGHT_GOLD[1], BRIGHT_GOLD[2], BRIGHT_GOLD[3], 1)
        pcall(spark.SetBlendMode, spark, "ADD")
        banner.sparks[index] = spark
    end

    local shine = banner:CreateTexture(nil, "OVERLAY")
    shine:SetHeight(BANNER_HEIGHT)
    shine:SetWidth(40)
    shine:SetColorTexture(BRIGHT_GOLD[1], BRIGHT_GOLD[2], BRIGHT_GOLD[3], 1)
    pcall(shine.SetBlendMode, shine, "ADD")
    shine:SetAlpha(0)
    banner.shine = shine

    banner:Hide()
    self.banner = banner
    return banner
end

--- GOAL COMPLETE across the top of the panel.
function GoalsUI:Complete(goal)
    local banner = self:Banner()
    banner.title:SetText("GOAL COMPLETE")

    local subject = ("%d / %d %s"):format(goal.have or 0, goal.target or 0, goal.item)
    if (tonumber(goal.doneIn) or 0) >= 1 then
        subject = subject .. "  |  " .. ns.Goals.Duration(goal.doneIn)
    end
    banner.subject:SetText(subject)
    banner:SetAlpha(0)
    banner:Show()

    local ok, width = pcall(banner.GetWidth, banner)
    width = ok and tonumber(width) or WIDTH

    for index, spark in ipairs(banner.sparks) do
        spark:ClearAllPoints()
        spark:SetPoint("CENTER", banner, "TOPLEFT", SPARKS[index][1] * width,
            -SPARKS[index][2] * BANNER_HEIGHT)
    end

    self:Animate({ slot = "banner", duration = BANNER_TIME,
        apply = function(p)
            local alpha = p < 0.06 and p / 0.06 or (p > 0.8 and (1 - p) / 0.2 or 1)
            banner:SetAlpha(alpha)
            banner.wash:SetAlpha(0.14 + 0.1 * math.sin(p * 8 * math.pi))

            for index, spark in ipairs(banner.sparks) do
                local twinkle = 0.5 + 0.5 * math.sin(p * 14 * math.pi + index * 1.7)
                spark:SetAlpha(twinkle * alpha)
            end

            local sweep = p * BANNER_TIME / SHINE_TIME
            if sweep < 1 then
                banner.shine:ClearAllPoints()
                banner.shine:SetPoint("TOPLEFT", banner, "TOPLEFT", (width - 40) * sweep, 0)
                banner.shine:SetAlpha(0.4 * math.sin(sweep * math.pi))
            else
                banner.shine:SetAlpha(0)
            end

            if p >= 1 then banner:Hide() end
        end,
        stop = function()
            banner:Hide()
            banner.shine:SetAlpha(0)
        end })
end

--- The search list's Goal buttons read "23/40"; keep them current while
--- the window is open.
function GoalsUI:RedrawSearch()
    local UI = ns.UI
    if UI and UI.list and UI.frame and UI.frame:IsShown() then
        pcall(UI.Render, UI)
    end
end

--- The goals' counts moved (Goals:Update). Redraw, then animate each card
--- from where it was.
function GoalsUI:Changed(changes)
    if not (self.frame and self.frame:IsShown()) then
        -- Closed: a finished goal still opens it, for the moment.
        local finished = false
        for _, change in ipairs(changes) do
            if change.done then finished = true end
        end
        if not finished then return end
        ns.db.goalsHidden = false
        self:Refresh()
    else
        self:Render()
    end

    self:RedrawSearch()

    local level = Level()
    if level == "off" then return end

    local floats = 0
    for _, change in ipairs(changes) do
        local ok, err = pcall(self.Play, self, change, level, floats)
        if not ok then ns.Debug("goal effects:", tostring(err)) end
        if change.gathered then floats = floats + 1 end
    end
end

function GoalsUI:Play(change, level, floats)
    local goal = change.goal
    local card = CardFor(goal)
    if not card then return end

    local target = tonumber(goal.target) or 0
    if target <= 0 then return end

    local full = level == "full"
    local up = change.to > change.from

    self:CountUp(card, goal, change.from, change.to, full and up)
    self:Slide(card, goal, math.min(1, change.from / target), math.min(1, change.to / target), full and up)

    if change.done then
        self:Glow(card, BRIGHT_GOLD, 0.6, PULSE_TIME, 3)
        -- The banner, its sparkles and shine are Full's; Subtle keeps the glow.
        if full then self:Complete(goal) end
    elseif change.milestone then
        self:Glow(card, BRIGHT_GOLD, 0.55, PULSE_TIME, 3)
    elseif up then
        self:Glow(card, Color("good"), 0.3)
    end

    if full and change.gathered then
        self:Float(card, ("+%d %s"):format(change.gathered, goal.item), 13, floats * 0.18)
        if change.milestone then
            self:Float(card, Util.Colored("accent", change.milestone.tag == "HALFWAY"
                and "Halfway there!" or (change.milestone.tag .. "!")), 16, floats * 0.18 + 0.35)
        elseif ns.Goals.Final(goal) then
            local left = ns.Goals.Left(goal)
            self:Float(card, Util.Colored("good", left == 1 and "1 more!" or (left .. " more!")),
                15, floats * 0.18 + 0.35)
        end
    end
end

--------------------------------------------------------------------------------
-- Position
--
-- Under the kills panel until you drag it; after that, where you put it.
--------------------------------------------------------------------------------

function GoalsUI:Place()
    local frame = self.frame
    if not frame or ns.db.goalsX then return end

    local tracker = ns.TrackerUI and ns.TrackerUI.frame
    frame:ClearAllPoints()
    if tracker and tracker:IsShown() then
        frame:SetPoint("TOPLEFT", tracker, "BOTTOMLEFT", 0, -GAP)
    else
        frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 8, -190)
    end
end

function GoalsUI:SavePosition()
    local frame = self.frame
    if not frame then return end

    local ok, left, top = pcall(function() return frame:GetLeft(), frame:GetTop() end)
    if not (ok and type(left) == "number" and type(top) == "number") then return end

    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
    ns.db.goalsX = left
    ns.db.goalsY = top
end

function GoalsUI:RestorePosition()
    local frame = self.frame
    if not frame then return end

    if ns.db.goalsX and ns.db.goalsY then
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", ns.db.goalsX, ns.db.goalsY)
    else
        self:Place()
    end
end

--- Back under the kills panel.
function GoalsUI:Dock()
    ns.db.goalsX = nil
    ns.db.goalsY = nil
    self:Place()
end

--------------------------------------------------------------------------------
-- Where to farm it: the best places near you (Logic/Spots.lua)
--------------------------------------------------------------------------------

local SPOTS_WIDTH = 300
local SPOT_ROW = 36
local SPOTS_TOP = 44

--- What a spot's distance looks like: here in green, next door in gold.
local function DistanceColor(hops)
    if hops == 0 then return "good" end
    if hops == 1 then return "accent" end
    return "muted"
end

--- The note under a spot: what you measured there, else the rate known.
function GoalsUI.SpotNote(spot)
    local yours = spot.yours
    if yours and yours.gathers then
        return Util.Colored("good", ("you gathered %d here"):format(yours.got or 0))
    end
    if yours and yours.kills then
        if spot.measured then
            return Util.Colored("good", ("%d%% in your %d kills"):format(spot.measured, yours.kills))
        end
        return Util.Colored("good", ("%d from your %d kills"):format(yours.got or 0, yours.kills))
    end
    if spot.chance then return ("%d%% drop"):format(spot.chance) end
    if spot.requires then return spot.requires end
    return ""
end

function GoalsUI:BuildSpots()
    if self.spots then return self.spots end

    local panel = CreateFrame("Frame", "BlackthornesFarmerGoalSpots", UIParent)
    panel:SetSize(SPOTS_WIDTH, SPOTS_TOP + SPOT_ROW)
    panel:SetFrameStrata("DIALOG")
    panel:SetClampedToScreen(true)
    panel:EnableMouse(true)

    Theme.Fill(panel, "window", 0.96)
    Theme.Border(panel, "accent")

    local stripe = panel:CreateTexture(nil, "ARTWORK")
    stripe:SetPoint("TOPLEFT")
    stripe:SetPoint("BOTTOMLEFT")
    stripe:SetWidth(3)
    stripe:SetColorTexture(Theme.Unpack("accent"))

    local title = Theme.CreateLabel(panel, "normal", "accent")
    title:SetPoint("TOPLEFT", 12, -8)
    title:SetPoint("TOPRIGHT", -30, -8)
    panel.title = title

    local from = Theme.CreateLabel(panel, "tiny", "muted")
    from:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    from:SetPoint("RIGHT", -10, 0)
    panel.from = from

    local close = Widgets.CreateButton(panel, "X", function() panel:Hide() end,
        { width = 16, height = 14, danger = true })
    close:SetPoint("TOPRIGHT", -6, -6)

    local rule = Theme.CreateDivider(panel, "borderLit")
    rule:SetPoint("TOPLEFT", 1, -(SPOTS_TOP - 4))
    rule:SetPoint("TOPRIGHT", -1, -(SPOTS_TOP - 4))

    panel.empty = Theme.CreateLabel(panel, "small", "muted")
    panel.empty:SetPoint("TOPLEFT", 12, -(SPOTS_TOP + 8))
    panel.empty:SetText("No places known for this yet.")

    panel.rows = {}

    local hint = Theme.CreateLabel(panel, "tiny", "dim")
    hint:SetPoint("BOTTOMLEFT", 12, 6)
    hint:SetPoint("BOTTOMRIGHT", -10, 6)
    hint:SetText("Click a place to print it to chat, pinned on your map when it is in this zone.")
    hint:SetWordWrap(true)
    panel.hint = hint

    if type(UISpecialFrames) == "table" then
        table.insert(UISpecialFrames, "BlackthornesFarmerGoalSpots")
    end

    panel:Hide()
    self.spots = panel
    return panel
end

function GoalsUI:SpotRow(index)
    local panel = self.spots
    local row = panel.rows[index]
    if row then return row end

    row = CreateFrame("Button", nil, panel)
    row:SetHeight(SPOT_ROW)
    row:SetPoint("TOPLEFT", 1, -(SPOTS_TOP + (index - 1) * SPOT_ROW))
    row:SetPoint("TOPRIGHT", -1, -(SPOTS_TOP + (index - 1) * SPOT_ROW))

    row.band = Theme.Fill(row, "row", index % 2 == 0 and 0.35 or 0.8)
    row.hover = Theme.Fill(row, "rowHover", 0, "BORDER")

    row.flash = row:CreateTexture(nil, "BORDER")
    row.flash:SetAllPoints(row)
    pcall(row.flash.SetBlendMode, row.flash, "ADD")
    row.flash:SetColorTexture(Theme.Unpack("good"))
    row.flash:SetAlpha(0)

    row.rank = Theme.CreateLabel(row, "large", "accent", "CENTER")
    pcall(row.rank.SetFont, row.rank, Theme.FONT, 15, "OUTLINE")
    row.rank:SetPoint("LEFT", 6, 0)
    row.rank:SetWidth(18)

    row.name = Theme.CreateLabel(row, "normal", "text")
    row.name:SetPoint("TOPLEFT", 30, -4)
    row.name:SetPoint("RIGHT", -60, 0)

    row.level = Theme.CreateLabel(row, "small", "text", "RIGHT")
    row.level:SetPoint("TOPRIGHT", -10, -5)
    row.level:SetWidth(50)

    -- The note sizes to its own text; the zone line stops short of it.
    row.note = Theme.CreateLabel(row, "tiny", "muted", "RIGHT")
    row.note:SetPoint("BOTTOMRIGHT", -10, 5)

    row.zone = Theme.CreateLabel(row, "tiny", "muted")
    row.zone:SetPoint("BOTTOMLEFT", 30, 5)
    row.zone:SetPoint("RIGHT", row.note, "LEFT", -8, 0)

    row:SetScript("OnEnter", function(self) self.hover:SetAlpha(0.7) end)
    row:SetScript("OnLeave", function(self) self.hover:SetAlpha(0) end)
    row:SetScript("OnClick", function(self)
        if not self.spot then return end
        ns.Spots:Share(GoalsUI.spotsItem, self.spot)
        GoalsUI:Animate({ slot = self.flash, duration = GLOW_TIME,
            apply = function(p) self.flash:SetAlpha(0.35 * (1 - p) ^ 2) end,
            stop = function() self.flash:SetAlpha(0) end })
    end)

    panel.rows[index] = row
    return row
end

--- Level band coloured the way the search window colours it: red well
--- above you, gold around you, grey below.
local function LevelColor(spot, level)
    if not (level and spot.minLevel) then return "text" end
    if spot.minLevel > level + 2 then return "warn" end
    if (spot.maxLevel or spot.minLevel) < level - 8 then return "muted" end
    return "good"
end

--- Rank the places for `item` from where you are and show them beside
--- `anchor` (the goals panel), or on their own.
function GoalsUI:OpenSpots(item, anchor)
    local panel = self:BuildSpots()

    if panel:IsShown() and self.spotsItem == item then
        panel:Hide()
        return
    end
    self.spotsItem = item

    local spots, player = ns.Spots:For(item)

    panel.title:SetText(("Where to farm |c%s%s|r"):format(ns.COLORS.text, item))
    if player.zone and player.level then
        panel.from:SetText(("Nearest first, from %s at level %d"):format(player.zone, player.level))
    elseif player.zone then
        panel.from:SetText(("Nearest first, from %s"):format(player.zone))
    else
        panel.from:SetText("Your zone could not be read here, so these are by level and rate")
    end

    for index, spot in ipairs(spots) do
        local row = self:SpotRow(index)
        row.spot = spot

        row.rank:SetText(tostring(index))
        row.name:SetText(spot.name or "?")

        row.level:SetText(spot.minLevel and ns.Search:LevelText(spot) or "")
        row.level:SetTextColor(Theme.Unpack(LevelColor(spot, player.level)))

        local distance = ns.Spots.DistanceText(spot.hops, spot.zone)
        local where = spot.zone or "?"
        if spot.location then where = where .. ", " .. spot.location end
        if distance ~= "" then
            where = where .. ("  |c%s%s|r"):format(ns.COLORS[DistanceColor(spot.hops)], distance)
        end
        row.zone:SetText(where)
        row.note:SetText(GoalsUI.SpotNote(spot))
        row:Show()
    end

    for index = #spots + 1, #panel.rows do
        panel.rows[index]:Hide()
        panel.rows[index].spot = nil
    end

    -- Wide enough for every row's text, measured.
    local needs = Theme.TextWidth("normal", Util.StripColor(panel.title:GetText())) + 42
    needs = math.max(needs, Theme.TextWidth("tiny", panel.from:GetText()) + 22)
    for index = 1, #spots do
        local row = panel.rows[index]
        needs = math.max(needs,
            30 + Theme.TextWidth("normal", row.name:GetText()) + 70,
            30 + Theme.TextWidth("tiny", Util.StripColor(row.zone:GetText())) + 8
                + Theme.TextWidth("tiny", Util.StripColor(row.note:GetText())) + 12)
    end
    panel:SetWidth(math.min(480, math.max(SPOTS_WIDTH, math.ceil(needs))))

    panel.empty:SetShown(#spots == 0)
    panel:SetHeight(SPOTS_TOP + math.max(1, #spots) * SPOT_ROW + 30)

    panel:ClearAllPoints()
    if anchor and anchor.IsShown and anchor:IsShown() then
        panel:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 6, 0)
    else
        panel:SetPoint("CENTER", UIParent, "CENTER", 0, 80)
    end
    local opening = not panel:IsShown()
    panel:Show()
    if opening then ns.Motion:Open(panel, 4) end

    -- The rows slide in one after another.
    if Level() == "full" then
        for index = 1, #spots do
            local row = panel.rows[index]
            row:SetAlpha(0)
            self:Animate({ slot = row, duration = 0.35, delay = (index - 1) * 0.06,
                apply = function(p) row:SetAlpha(EaseOut(p)) end,
                stop = function() row:SetAlpha(1) end })
        end
    end
end

--------------------------------------------------------------------------------
-- The picker: set a goal from a search result
--------------------------------------------------------------------------------

local PICK_WIDTH = 250
local PRESETS = { 20, 40, 60, 100 }

--- Four amounts to offer, all above what you have: 20, 40, 60, 100 while
--- they are, then the next steps of 20 above it.
function GoalsUI.Presets(have)
    have = tonumber(have) or 0
    local amounts = {}
    for _, amount in ipairs(PRESETS) do
        if amount > have then amounts[#amounts + 1] = amount end
    end

    local step = (math.floor(have / 20) + 1) * 20
    while #amounts < #PRESETS do
        local taken = false
        for _, amount in ipairs(amounts) do
            if amount == step then taken = true end
        end
        if not taken then amounts[#amounts + 1] = step end
        step = step + 20
    end

    table.sort(amounts)
    return amounts
end

function GoalsUI:BuildPicker()
    if self.picker then return self.picker end

    local picker = CreateFrame("Frame", "BlackthornesFarmerGoalPicker", UIParent)
    picker:SetSize(PICK_WIDTH, 128)
    picker:SetFrameStrata("DIALOG")
    picker:SetClampedToScreen(true)
    picker:EnableMouse(true)

    Theme.Fill(picker, "panel", 0.98)
    Theme.Border(picker, "accent")

    local title = Theme.CreateLabel(picker, "small", "accent")
    title:SetPoint("TOPLEFT", 10, -9)
    title:SetPoint("TOPRIGHT", -30, -9)
    picker.title = title

    local close = Widgets.CreateButton(picker, "X", function() picker:Hide() end,
        { width = 16, height = 14, danger = true })
    close:SetPoint("TOPRIGHT", -6, -6)

    picker.chips = {}
    for index = 1, #PRESETS do
        local chip = Widgets.CreateChip(picker, "", function(self)
            picker.amount:SetText(tostring(self.amount))
            GoalsUI:PickerSelect(self.amount)
        end)
        chip:SetWidth(40)
        chip:SetPoint("TOPLEFT", 10 + (index - 1) * 44, -28)
        picker.chips[index] = chip
    end

    local amount = Widgets.CreateSearchBox(picker, "other", function(text)
        GoalsUI:PickerSelect(tonumber(text))
    end, function() GoalsUI:PickerSet() end)
    amount:SetPoint("TOPLEFT", 10 + #PRESETS * 44, -27)
    amount:SetPoint("TOPRIGHT", -10, -27)
    amount:SetHeight(20)
    if amount.editBox then
        pcall(amount.editBox.SetNumeric, amount.editBox, true)
        pcall(amount.editBox.SetMaxLetters, amount.editBox, 5)
    end
    picker.amount = amount

    local have = Theme.CreateLabel(picker, "small", "muted")
    have:SetPoint("TOPLEFT", 10, -56)
    picker.have = have

    local bank = Widgets.CreateCheckbox(picker, "Include bank", function(on)
        ns.Goals:SetCountsBank(on)
        GoalsUI:FillPicker()
    end, ns.Goals:CountsBank())
    bank:SetPoint("TOPLEFT", 10, -74)
    picker.bank = bank

    local set = Widgets.CreateButton(picker, "Set goal", function() GoalsUI:PickerSet() end,
        { width = 80, height = 22, primary = true })
    set:SetPoint("BOTTOMLEFT", 10, 10)
    picker.set = set

    local remove = Widgets.CreateButton(picker, "Remove goal", function()
        ns.Goals:Remove(GoalsUI.pickItem)
        ns.Print(("goal for %s removed."):format(Util.Colored("accent", GoalsUI.pickItem)))
        picker:Hide()
        GoalsUI:RedrawSearch()
    end, { width = 80, height = 22 })
    remove:SetPoint("BOTTOMRIGHT", -10, 10)
    picker.remove = remove

    local note = Theme.CreateLabel(picker, "tiny", "warn")
    note:SetPoint("BOTTOMLEFT", set, "TOPLEFT", 0, 4)
    note:SetPoint("RIGHT", -10, 0)
    picker.note = note

    -- Escape closes it, like the game's own windows.
    if type(UISpecialFrames) == "table" then
        table.insert(UISpecialFrames, "BlackthornesFarmerGoalPicker")
    end

    picker:Hide()
    self.picker = picker
    return picker
end

function GoalsUI:PickerSelect(amount)
    local picker = self.picker
    GoalsUI.choice = tonumber(amount)
    for _, chip in ipairs(picker.chips) do
        chip:SetSelected(chip.amount == GoalsUI.choice)
    end
    picker.note:SetText("")
end

function GoalsUI:FillPicker()
    local picker = self.picker
    local item = GoalsUI.pickItem
    local goal = ns.Goals:Find(item)
    local have = ns.Goals:Have(item) or 0

    picker.title:SetText(("GATHERING GOAL  |c%s%s|r"):format(ns.COLORS.text, item:upper()))
    picker.have:SetText(("You have |c%s%d|r %s."):format(ns.COLORS.text, have,
        ns.Goals:CountsBank() and "in your bags and bank" or "in your bags"))
    picker.bank:SetChecked(ns.Goals:CountsBank())

    -- As wide as its title needs, measured: a long name in capitals ran
    -- past a fixed width and ended in "...".
    picker:SetWidth(math.min(460, math.max(PICK_WIDTH,
        Theme.TextWidth("small", Util.StripColor(picker.title:GetText())) + 42,
        Theme.TextWidth("small", Util.StripColor(picker.have:GetText())) + 22)))

    for index, amount in ipairs(GoalsUI.Presets(have)) do
        local chip = picker.chips[index]
        chip.amount = amount
        chip.label:SetText(tostring(amount))
    end

    picker.set:SetText(goal and "Change goal" or "Set goal")
    picker.remove:SetShown(goal ~= nil)

    if not GoalsUI.choice or GoalsUI.choice <= have then
        GoalsUI.choice = goal and goal.target or GoalsUI.Presets(have)[2]
    end
    picker.amount:SetText(tostring(GoalsUI.choice))
    self:PickerSelect(GoalsUI.choice)
end

--- Open the picker for `item`, beside `anchor` (the Goal button pressed).
function GoalsUI:OpenPicker(item, anchor)
    local picker = self:BuildPicker()

    if picker:IsShown() and GoalsUI.pickItem == item then
        picker:Hide()
        return
    end

    GoalsUI.pickItem = item
    GoalsUI.choice = nil
    self:FillPicker()

    picker:ClearAllPoints()
    if anchor then
        picker:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 6, 0)
    else
        picker:SetPoint("CENTER", UIParent, "CENTER", 0, 80)
    end
    picker:Show()
    ns.Motion:Open(picker, 4)
end

function GoalsUI:PickerSet()
    local picker = self.picker
    if not (picker and GoalsUI.pickItem) then return end

    local amount = tonumber(picker.amount:GetText()) or GoalsUI.choice
    local goal, why = ns.Goals:Set(GoalsUI.pickItem, amount)

    if not goal then
        picker.note:SetText(why and (why:sub(1, 1):upper() .. why:sub(2) .. ".") or "")
        -- Wide enough for the note too, measured.
        local wants = Theme.TextWidth("tiny", picker.note:GetText()) + 22
        if wants > (tonumber(picker:GetWidth()) or 0) then picker:SetWidth(math.min(460, wants)) end
        return
    end

    picker:Hide()
    ns.Print(("goal set: %s %s. You have %d, %d to go."):format(
        Util.Colored("good", tostring(goal.target)), Util.Colored("accent", goal.item),
        goal.have, ns.Goals.Left(goal)))
    self:Show()
    GoalsUI:RedrawSearch()
end

--------------------------------------------------------------------------------
-- Commands
--------------------------------------------------------------------------------

ns.RegisterCommand("goals", "show or hide the goals panel (dock puts it back under the kills panel)", function(rest)
    local word = Util.Trim(rest):lower()

    if word == "dock" then
        GoalsUI:Dock()
        ns.Print("goals panel back under the kills panel.")
        return
    end

    if #ns.Goals:List() == 0 then
        ns.Print("no goals yet. /farm goal Copper Ore 40, or the Goal button on a search result.")
        return
    end

    GoalsUI:Toggle()
end)
