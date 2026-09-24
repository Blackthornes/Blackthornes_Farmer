-- Blackthornes Farmer -- UI/Tracker.lua
-- The kill tally panel: a small card that follows your farming.
--
-- Loot a corpse and it shows that mob: how many you have killed, how many of
-- those this session, and what they dropped. Counts until there are enough
-- kills for a rate to mean anything, percentages after. It stays put where you
-- drag it, and /farm tracker (or its X) puts it away until you ask again.

local _, ns = ...

local TrackerUI = ns.NewModule("TrackerUI")

local Theme = ns.Theme
local Widgets = ns.Widgets
local Util = ns.Util

local WIDTH = 236
local PADDING = 10
local LINE = 16
local MAX_ITEMS = 6

--- A rate worth staying for should look different from one that is not.
local function RateColor(chance)
    if chance >= 40 then return "good" end
    if chance >= 15 then return "accent" end
    return "muted"
end

--------------------------------------------------------------------------------
-- Construction
--------------------------------------------------------------------------------

function TrackerUI:Build()
    if self.frame then return self.frame end

    local frame = CreateFrame("Frame", "BlackthornesFarmerTracker", UIParent)
    frame:SetWidth(WIDTH)
    frame:SetFrameStrata("MEDIUM")
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")

    Theme.Fill(frame, "window", 0.92)
    Theme.Border(frame, "borderLit")

    frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        TrackerUI:SavePosition()
    end)

    local title = Theme.CreateLabel(frame, "large", "accent")
    title:SetPoint("TOPLEFT", PADDING, -PADDING)
    title:SetWidth(WIDTH - PADDING * 2 - 24)

    local close = Widgets.CreateButton(frame, "X", function()
        ns.db.trackerHidden = true
        TrackerUI:Hide()
        ns.Print("kill tally hidden. /farm tracker brings it back.")
    end, { width = 18, height = 16 })
    close:SetPoint("TOPRIGHT", -6, -6)

    local tally = Theme.CreateLabel(frame, "small", "muted")
    tally:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)

    local divider = Theme.CreateDivider(frame, "border")
    divider:SetPoint("TOPLEFT", PADDING, -(PADDING + 38))
    divider:SetPoint("TOPRIGHT", -PADDING, -(PADDING + 38))

    local rows = {}

    for index = 1, MAX_ITEMS do
        local top = -(PADDING + 44 + (index - 1) * LINE)

        local name = Theme.CreateLabel(frame, "small", "text")
        name:SetPoint("TOPLEFT", PADDING, top)
        name:SetWidth(WIDTH - PADDING * 2 - 60)

        local value = Theme.CreateLabel(frame, "small", "muted", "RIGHT")
        value:SetPoint("TOPRIGHT", -PADDING, top)
        value:SetWidth(60)

        rows[index] = { name = name, value = value }
    end

    local footer = Theme.CreateLabel(frame, "tiny", "muted")

    self.frame = frame
    self.title = title
    self.tally = tally
    self.rows = rows
    self.footer = footer

    self:RestorePosition()
    frame:Hide()

    return frame
end

--------------------------------------------------------------------------------
-- Filling it in
--------------------------------------------------------------------------------

function TrackerUI:Render(summary)
    self:Build()

    self.title:SetText(summary.mob)
    self.tally:SetText(("%s  |  %d this session"):format(
        Util.Plural(summary.kills, "kill"), summary.session))

    local shown = math.min(#summary.items, MAX_ITEMS)

    for index, row in ipairs(self.rows) do
        local item = summary.items[index]

        if item then
            row.name:SetText(item.name)

            if summary.rated then
                row.value:SetText(ns.Tracker.FormatChance(item.chance))
                row.value:SetTextColor(Theme.Unpack(RateColor(item.chance)))
            else
                row.value:SetText(("%d of %d"):format(item.corpses, summary.kills))
                row.value:SetTextColor(Theme.Unpack("muted"))
            end

            row.name:Show()
            row.value:Show()
        else
            row.name:Hide()
            row.value:Hide()
        end
    end

    local footer

    if not summary.rated then
        footer = ("%d more %s for drop rates"):format(
            summary.needed, summary.needed == 1 and "kill" or "kills")
    elseif #summary.items == 0 then
        footer = "nothing dropped yet"
    elseif #summary.items > MAX_ITEMS then
        footer = ("+%d more  |  /farm kills for all"):format(#summary.items - MAX_ITEMS)
    end

    -- The footer sits under the last item, or under the divider when there
    -- are none, and the card is exactly as tall as what it holds.
    local bottom = PADDING + 44 + shown * LINE

    if footer then
        self.footer:SetText(footer)
        self.footer:SetPoint("TOPLEFT", PADDING, -(bottom + 2))
        self.footer:Show()
        bottom = bottom + LINE
    else
        self.footer:SetText("")
        self.footer:Hide()
    end

    self.frame:SetHeight(bottom + PADDING - 4)
end

--- Show this mob's tally, unless the panel has been put away.
function TrackerUI:ShowMob(mobName)
    local summary = ns.Tracker:Summary(mobName)
    if not summary then return end

    self:Render(summary)

    if ns.db.trackerHidden then
        self.frame:Hide()
    else
        self.frame:Show()
    end
end

function TrackerUI:Hide()
    if self.frame then self.frame:Hide() end
end

--------------------------------------------------------------------------------
-- Position
--------------------------------------------------------------------------------

function TrackerUI:SavePosition()
    if not (ns.db and self.frame) then return end

    local point, _, relativePoint, x, y = self.frame:GetPoint()

    ns.db.trackerPoint = point
    ns.db.trackerRelativePoint = relativePoint
    ns.db.trackerX = x
    ns.db.trackerY = y
end

function TrackerUI:RestorePosition()
    if not self.frame then return end

    local db = ns.db or {}
    local point = db.trackerPoint or "RIGHT"

    self.frame:ClearAllPoints()
    self.frame:SetPoint(point, UIParent, db.trackerRelativePoint or point,
        db.trackerX or -220, db.trackerY or 120)
end
