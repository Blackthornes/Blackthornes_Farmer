-- Blackthornes Farmer -- UI/Tracker.lua
-- The kill and loot panel, down the left side of the screen.
--
-- A tall, narrow column that sits under the player and party frames and fills
-- in as you farm: this session's kills and loot at the top, then every mob
-- you have killed this session, latest first, each with its all-time tally and
-- what it drops. Counts until a mob has enough kills for a rate to mean
-- anything, percentages after.
--
-- /farm tracker (or its X) turns it off and on, and it stays that way from one
-- session to the next. Drag it by its title if the left edge is busy.

local _, ns = ...

local TrackerUI = ns.NewModule("TrackerUI")

local Theme = ns.Theme
local Widgets = ns.Widgets
local Util = ns.Util

local WIDTH = 230
local HEIGHT = 400
local PADDING = 10
local HEADER = 30
local LINE = 15

-- Lines the body can hold; anything past it is summarised on the last line.
local MAX_LINES = math.floor((HEIGHT - HEADER - PADDING * 2) / LINE)

-- How much of each section to show before moving on to the next.
local LOOT_LINES = 6
local MOB_ITEMS = 3

-- Bumped when the default position moves, so a panel saved at the old spot
-- comes to the new one once instead of staying where nobody asked for it.
local LAYOUT = 2

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
    frame:SetSize(WIDTH, HEIGHT)
    frame:SetFrameStrata("LOW")
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")

    Theme.Fill(frame, "window", 0.85)
    Theme.Border(frame, "border")

    frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        TrackerUI:SavePosition()
    end)

    local header = Theme.CreatePanel(frame, "header", false)
    header:SetPoint("TOPLEFT")
    header:SetPoint("TOPRIGHT")
    header:SetHeight(HEADER)

    local title = Theme.CreateLabel(header, "normal", "accent")
    title:SetPoint("LEFT", PADDING, 0)
    title:SetText("Kills & Loot")

    local close = Widgets.CreateButton(header, "X", function()
        ns.db.trackerHidden = true
        TrackerUI:Refresh()
        ns.Print("kill and loot panel hidden. /farm tracker brings it back.")
    end, { width = 18, height = 16 })
    close:SetPoint("RIGHT", -6, 0)

    local lines = {}

    for index = 1, MAX_LINES do
        local top = -(HEADER + PADDING + (index - 1) * LINE)

        local left = Theme.CreateLabel(frame, "small", "text")
        left:SetPoint("TOPLEFT", PADDING, top)
        left:SetWidth(WIDTH - PADDING * 2 - 64)

        local right = Theme.CreateLabel(frame, "small", "muted", "RIGHT")
        right:SetPoint("TOPRIGHT", -PADDING, top)
        right:SetWidth(64)

        lines[index] = { left = left, right = right }
    end

    self.frame = frame
    self.title = title
    self.lines = lines

    self:RestorePosition()
    frame:Hide()

    return frame
end

--------------------------------------------------------------------------------
-- What goes in it
--
-- Built as a flat list of lines first, then drawn, so the layout rules live in
-- one place and a test can read the list without a frame.
--------------------------------------------------------------------------------

--- Every line the panel would show, top to bottom: { left, right, style }.
-- Styles: "heading", "mob", "item", "note".
function TrackerUI:Lines()
    local Tracker = ns.Tracker
    local out = {}

    local function Add(left, right, style, color)
        out[#out + 1] = { left = left, right = right or "", style = style, color = color }
    end

    local mobs = Tracker:SessionMobs()

    if #mobs == 0 then
        Add("Nothing killed yet this session.", nil, "note")
        Add("Loot a corpse and it shows up here.", nil, "note")
        return out
    end

    Add("This session", ("%s, %s"):format(
        Util.Plural(Tracker:SessionKills(), "kill"),
        Util.Plural(#mobs, "mob")), "heading")

    local loot = Tracker:SessionLoot()

    if #loot == 0 then
        Add("No loot yet", nil, "note")
    end

    for index = 1, math.min(#loot, LOOT_LINES) do
        Add(loot[index].name, ("x%d"):format(loot[index].count), "item")
    end

    if #loot > LOOT_LINES then
        Add(("+%d more items"):format(#loot - LOOT_LINES), nil, "note")
    end

    for _, summary in ipairs(mobs) do
        -- All-time kills, with this session's share in brackets.
        Add(summary.mob, ("%d (%d now)"):format(summary.kills, summary.session), "mob")

        for index = 1, math.min(#summary.items, MOB_ITEMS) do
            local item = summary.items[index]

            if summary.rated then
                Add(item.name, ns.Tracker.FormatChance(item.chance), "item",
                    RateColor(item.chance))
            else
                Add(item.name, ("%d of %d"):format(item.corpses, summary.kills), "item")
            end
        end

        if not summary.rated then
            Add(("%d more %s for drop rates"):format(summary.needed,
                summary.needed == 1 and "kill" or "kills"), nil, "note")
        elseif #summary.items == 0 then
            Add("nothing dropped yet", nil, "note")
        end
    end

    return out
end

local STYLE = {
    heading = { left = "accent", right = "muted", indent = 0 },
    mob     = { left = "accent", right = "muted", indent = 0 },
    item    = { left = "text",   right = "muted", indent = 8 },
    note    = { left = "muted",  right = "muted", indent = 8 },
}

function TrackerUI:Render()
    self:Build()

    local lines = self:Lines()

    -- Past the bottom, the last line says how much did not fit rather than
    -- cutting off mid-mob without a word.
    if #lines > MAX_LINES then
        local hidden = #lines - MAX_LINES + 1
        for index = #lines, MAX_LINES, -1 do lines[index] = nil end
        lines[MAX_LINES] = { left = ("+%d more lines  |  /farm kills <mob>"):format(hidden),
            right = "", style = "note" }
    end

    self.shown = lines

    for index, widgets in ipairs(self.lines) do
        local line = lines[index]

        if line then
            local style = STYLE[line.style] or STYLE.item
            local top = -(HEADER + PADDING + (index - 1) * LINE)

            widgets.left:SetPoint("TOPLEFT", PADDING + style.indent, top)
            widgets.left:SetText(line.left)
            widgets.left:SetTextColor(Theme.Unpack(style.left))
            widgets.right:SetText(line.right)
            widgets.right:SetTextColor(Theme.Unpack(line.color or style.right))
            widgets.left:Show()
            widgets.right:Show()
        else
            widgets.left:SetText("")
            widgets.right:SetText("")
            widgets.left:Hide()
            widgets.right:Hide()
        end
    end
end

--------------------------------------------------------------------------------
-- On and off
--------------------------------------------------------------------------------

--- Redraw, and show or hide to match the saved setting.
function TrackerUI:Refresh()
    self:Build()

    if ns.db.trackerHidden then
        self.frame:Hide()
        return
    end

    self:Render()
    self.frame:Show()
end

function TrackerUI:Hide()
    if self.frame then self.frame:Hide() end
end

function TrackerUI:OnEnable()
    self:Refresh()
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

    -- The first version sat on the right; move a panel saved there once.
    if db.trackerLayout ~= LAYOUT then
        db.trackerPoint = "TOPLEFT"
        db.trackerRelativePoint = "TOPLEFT"
        db.trackerX = 8
        db.trackerY = -190
        db.trackerLayout = LAYOUT
    end

    local point = db.trackerPoint or "TOPLEFT"

    self.frame:ClearAllPoints()
    self.frame:SetPoint(point, UIParent, db.trackerRelativePoint or point,
        db.trackerX or 8, db.trackerY or -190)
end
