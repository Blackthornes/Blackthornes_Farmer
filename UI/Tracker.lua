-- Blackthornes Farmer -- UI/Tracker.lua
-- The kills and loot panel, down the left side of the screen.
--
-- A tall, narrow column under the player and party frames that fills in as
-- you farm. At the top, this session: how many kills, and everything looted
-- with how many of each. Below it, every mob killed this session, latest
-- first, on its own band: its all-time kills, a bar filling toward the 20 it
-- takes for drop rates, and its best drops -- as counts until then, as rates
-- with a bar after.
--
-- Items are drawn the way the bags draw them, icon and quality colour, both
-- remembered from the loot window by the tracker.
--
-- /farm tracker (or its X) turns it off and on, and it stays that way from one
-- session to the next. Drag it if the left edge is busy.

local _, ns = ...

local TrackerUI = ns.NewModule("TrackerUI")

local Theme = ns.Theme
local Widgets = ns.Widgets
local Util = ns.Util

-- The starting size. Drag the corner grip to change it; the size is saved.
local WIDTH = 236
local HEIGHT = 420

-- How small and how large the grip will let it go.
local MIN_WIDTH, MAX_WIDTH = 180, 600
local MIN_HEIGHT, MAX_HEIGHT = 120, 1000
local PADDING = 8
local HEADER = 28
local LINE = 18
local ICON = 14
local BAR = 40

-- Right-hand value and the green badge beside it, in pixels.
local RIGHT_WIDTH = 54
local BADGE_WIDTH = 28

-- How much of each section to show before moving on to the next.
local LOOT_LINES = 6
local MOB_ITEMS = 3

-- Bumped when the default position moves, so a panel saved at the old spot
-- comes to the new one once instead of staying where nobody asked for it.
local LAYOUT = 2

local FALLBACK_ICON = [[Interface\Icons\INV_Misc_QuestionMark]]

--- A rate worth staying for should look different from one that is not.
local function RateColor(chance)
    if chance >= 40 then return "good" end
    if chance >= 15 then return "accent" end
    return "muted"
end

--- A "ffrrggbb" colour as the four numbers SetTextColor takes.
local function HexColor(hex)
    if type(hex) ~= "string" or #hex ~= 8 then return nil end

    local r = tonumber(hex:sub(3, 4), 16)
    local g = tonumber(hex:sub(5, 6), 16)
    local b = tonumber(hex:sub(7, 8), 16)
    if not (r and g and b) then return nil end

    return r / 255, g / 255, b / 255, 1
end

--------------------------------------------------------------------------------
-- Size
--
-- The width is exactly what you drag it to. The height you drag to is the
-- tallest it grows: a short session still gets a short panel, and a long one
-- fills down to where you put the bottom edge and says what did not fit.
--------------------------------------------------------------------------------

local function Clamp(value, low, high)
    value = tonumber(value)
    if not value then return nil end
    return math.max(low, math.min(high, value))
end

function TrackerUI:Width()
    return Clamp(ns.db and ns.db.trackerWidth, MIN_WIDTH, MAX_WIDTH) or WIDTH
end

function TrackerUI:MaxHeight()
    return Clamp(ns.db and ns.db.trackerHeight, MIN_HEIGHT, MAX_HEIGHT) or HEIGHT
end

--- How many lines fit under the header at a given height.
function TrackerUI:LinesFor(height)
    return math.max(2, math.floor((height - HEADER - PADDING * 2) / LINE))
end

--- Row `index`, made the first time it is needed.
function TrackerUI:Line(index)
    local row = self.lines[index]
    if not row then
        row = self:CreateLine(self.frame, index)
        self.lines[index] = row
    end
    return row
end

function TrackerUI:SaveSize()
    if not (ns.db and self.frame) then return end

    ns.db.trackerWidth = math.floor(self.frame:GetWidth() + 0.5)
    ns.db.trackerHeight = math.floor(self.frame:GetHeight() + 0.5)
end

--- The corner grip. Drag it and the panel follows; let go and it keeps that.
function TrackerUI:BuildGrip(frame)
    frame:SetResizable(true)

    -- Retail spells the limits one way and older clients another; try both,
    -- and let neither's absence stop the panel from building.
    if not pcall(frame.SetResizeBounds, frame, MIN_WIDTH, MIN_HEIGHT, MAX_WIDTH, MAX_HEIGHT) then
        pcall(frame.SetMinResize, frame, MIN_WIDTH, MIN_HEIGHT)
        pcall(frame.SetMaxResize, frame, MAX_WIDTH, MAX_HEIGHT)
    end

    local grip = CreateFrame("Button", nil, frame)
    grip:SetSize(14, 14)
    grip:SetPoint("BOTTOMRIGHT", -2, 2)
    grip:SetFrameLevel(frame:GetFrameLevel() + 5)
    grip:EnableMouse(true)

    pcall(grip.SetNormalTexture, grip, [[Interface\ChatFrame\UI-ChatIM-SizeGrabber-Up]])
    pcall(grip.SetHighlightTexture, grip, [[Interface\ChatFrame\UI-ChatIM-SizeGrabber-Highlight]])
    pcall(grip.SetPushedTexture, grip, [[Interface\ChatFrame\UI-ChatIM-SizeGrabber-Down]])

    grip:SetScript("OnMouseDown", function()
        TrackerUI.sizing = true
        -- Pin the top first, so the panel grows downward from where it is.
        TrackerUI:AnchorTop()
        -- Start from the size on screen, so the corner stays under the
        -- cursor. Changing the height here would move the corner away from
        -- the mouse, and the drag would keep that gap the whole way.
        frame:StartSizing("BOTTOMRIGHT")
    end)

    grip:SetScript("OnMouseUp", function()
        frame:StopMovingOrSizing()
        TrackerUI.sizing = false
        TrackerUI:AnchorTop()
        TrackerUI:SaveSize()
        TrackerUI:SavePosition()
        TrackerUI:Render()
    end)

    -- Redraw while dragging, so you see what fits as you go.
    frame:SetScript("OnSizeChanged", function()
        if TrackerUI.sizing then TrackerUI:Render() end
    end)

    self.grip = grip
end

--------------------------------------------------------------------------------
-- Construction
--------------------------------------------------------------------------------

function TrackerUI:Build()
    if self.frame then return self.frame end

    local frame = CreateFrame("Frame", "BlackthornesFarmerTracker", UIParent)
    frame:SetSize(self:Width(), self:MaxHeight())
    frame:SetFrameStrata("LOW")
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")

    Theme.Fill(frame, "window", 0.88)
    Theme.Border(frame, "border")

    frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        TrackerUI:AnchorTop()
        TrackerUI:SavePosition()
    end)

    -- Title bar: the house header, with an accent stripe down its left edge
    -- so the panel reads as part of the same set as the search window.
    local header = Theme.CreatePanel(frame, "header", false)
    header:SetPoint("TOPLEFT")
    header:SetPoint("TOPRIGHT")
    header:SetHeight(HEADER)

    local stripe = header:CreateTexture(nil, "ARTWORK")
    stripe:SetPoint("TOPLEFT")
    stripe:SetPoint("BOTTOMLEFT")
    stripe:SetWidth(3)
    stripe:SetColorTexture(Theme.Unpack("accent"))

    local title = Theme.CreateLabel(header, "normal", "accent")
    title:SetPoint("LEFT", PADDING + 4, 0)
    title:SetText("Kills & Loot")

    local close = Widgets.CreateButton(header, "X", function()
        ns.db.trackerHidden = true
        TrackerUI:Refresh()
        ns.Print("kill and loot panel hidden. /farm tracker brings it back.")
    end, { width = 18, height = 16 })
    close:SetPoint("RIGHT", -6, 0)

    local rule = Theme.CreateDivider(frame, "borderLit")
    rule:SetPoint("TOPLEFT", header, "BOTTOMLEFT")
    rule:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT")

    self.frame = frame
    self.title = title
    self.lines = {}

    self:BuildGrip(frame)

    self:RestorePosition()
    frame:Hide()

    return frame
end

--- One row of the column. Every row can be any kind of line; Render decides
--- which parts to show.
function TrackerUI:CreateLine(parent, index)
    local row = CreateFrame("Frame", nil, parent)
    row:SetPoint("TOPLEFT", 1, -(HEADER + PADDING + (index - 1) * LINE))
    row:SetPoint("TOPRIGHT", -1, -(HEADER + PADDING + (index - 1) * LINE))
    row:SetHeight(LINE)

    -- A full-width band behind headings and mob names, so the column reads as
    -- blocks rather than one long list.
    row.band = Theme.Fill(row, "row", 0.9)

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(ICON, ICON)
    row.icon:SetPoint("LEFT", PADDING + 6, 0)
    -- Trim the icon's built-in border, as the bags do.
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    -- Anchored at both ends rather than given a width, so it stretches with
    -- the panel; DrawLine sets where it stops.
    row.left = Theme.CreateLabel(row, "small", "text")
    row.left:SetPoint("LEFT", PADDING, 0)
    row.left:SetPoint("RIGHT", -PADDING, 0)

    row.right = Theme.CreateLabel(row, "small", "muted", "RIGHT")
    row.right:SetPoint("RIGHT", -PADDING, 0)
    row.right:SetWidth(RIGHT_WIDTH)

    row.badge = Theme.CreateLabel(row, "tiny", "good", "RIGHT")
    row.badge:SetPoint("RIGHT", row.right, "LEFT", -2, 0)
    row.badge:SetWidth(BADGE_WIDTH)

    -- A thin bar under the value: a drop rate, or kills toward MIN_KILLS.
    row.track = row:CreateTexture(nil, "BORDER")
    row.track:SetPoint("BOTTOMRIGHT", -PADDING, 1)
    row.track:SetSize(BAR, 2)
    row.track:SetColorTexture(Theme.Unpack("rowAlt"))

    row.fill = row:CreateTexture(nil, "ARTWORK")
    row.fill:SetPoint("BOTTOMLEFT", row.track, "BOTTOMLEFT")
    row.fill:SetHeight(2)

    return row
end

--------------------------------------------------------------------------------
-- What goes in it
--
-- Built as a flat list of lines first, then drawn, so the layout rules live in
-- one place and a test can read the list without a frame.
--------------------------------------------------------------------------------

--- Every line the panel would show, top to bottom.
--
-- Each is { style, left, right }, plus as it applies: `item` (a name whose
-- icon and colour to draw), `badge` (small green text beside the value),
-- `bar` (0-1) and `barColor`, and `rightColor`.
-- Styles: "heading", "mob", "value", "item", "note".
function TrackerUI:Lines()
    local Tracker = ns.Tracker
    local out = {}

    local function Add(line)
        line.right = line.right or ""
        out[#out + 1] = line
        return line
    end

    local mobs = Tracker:SessionMobs()

    if #mobs == 0 then
        Add({ style = "note", left = "Nothing killed yet this session." })
        Add({ style = "note", left = "Loot a corpse and it shows up here." })
        return out
    end

    Add({ style = "heading", left = "THIS SESSION",
        right = Util.Plural(Tracker:SessionKills(), "kill") })

    local loot = Tracker:SessionLoot()

    if #loot == 0 then
        Add({ style = "note", left = "No loot yet" })
    end

    for index = 1, math.min(#loot, LOOT_LINES) do
        Add({ style = "item", item = loot[index].name, left = loot[index].name,
            right = ("x%d"):format(loot[index].count) })
    end

    if #loot > LOOT_LINES then
        Add({ style = "note", left = ("+%d more items"):format(#loot - LOOT_LINES) })
    end

    for _, summary in ipairs(mobs) do
        -- All-time kills on the band, this session's in green beside them,
        -- and until there are enough for rates, a bar filling toward it.
        local band = Add({ style = "mob", left = summary.mob,
            right = tostring(summary.kills), badge = ("+%d"):format(summary.session) })

        if not summary.rated then
            band.bar = summary.kills / Tracker.MIN_KILLS
            band.barColor = "accent"
        end

        -- What a kill is worth, priced by Tradeskills: from your own tally
        -- once it is rated, else from the database's rates, marked as such.
        local worth, details
        if ns.Value then worth, details = ns.Value:ForMob(summary.mob) end
        if worth then
            Add({ style = "value",
                left = details.basis == "tally" and "Worth per kill" or "Worth per kill (est.)",
                right = ns.Value.Money(worth), rightColor = "good" })
        end

        for index = 1, math.min(#summary.items, MOB_ITEMS) do
            local item = summary.items[index]

            if summary.rated then
                Add({ style = "item", item = item.name, left = item.name,
                    right = Tracker.FormatChance(item.chance),
                    rightColor = RateColor(item.chance),
                    bar = item.chance / 100, barColor = RateColor(item.chance) })
            else
                Add({ style = "item", item = item.name, left = item.name,
                    right = ("%d of %d"):format(item.corpses, summary.kills) })
            end
        end

        if not summary.rated then
            Add({ style = "note", left = ("%d more %s for drop rates"):format(
                summary.needed, summary.needed == 1 and "kill" or "kills") })
        elseif #summary.items == 0 then
            Add({ style = "note", left = "nothing dropped yet" })
        end
    end

    return out
end

--------------------------------------------------------------------------------
-- Drawing
--------------------------------------------------------------------------------

local BAND = {
    heading = { key = "header", alpha = 1 },
    mob     = { key = "row", alpha = 0.9 },
}

function TrackerUI:DrawLine(row, line)
    local band = BAND[line.style]

    if band then
        row.band:SetColorTexture(Theme.Unpack(band.key, band.alpha))
        row.band:Show()
    else
        row.band:Hide()
    end

    -- Items get an icon and their quality colour; everything else is text.
    local indent = PADDING

    if line.style == "item" then
        local look = ns.Tracker:LookOf(line.item)
        row.icon:SetTexture(look.icon or FALLBACK_ICON)
        row.icon:Show()
        indent = PADDING + 6 + ICON + 4

        local r, g, b, a = HexColor(look.color)
        if r then
            row.left:SetTextColor(r, g, b, a)
        else
            row.left:SetTextColor(Theme.Unpack("text"))
        end
    else
        row.icon:Hide()

        if line.style == "note" or line.style == "value" then
            indent = PADDING + 6
            row.left:SetTextColor(Theme.Unpack("muted"))
        elseif line.style == "heading" then
            row.left:SetTextColor(Theme.Unpack("muted"))
        else
            row.left:SetTextColor(Theme.Unpack("accent"))
        end
    end

    -- The text runs to the value column, or all the way across when a line
    -- has no value. That second case is what cut "Nothing killed yet this
    -- session." short: it stopped where a value would have started.
    local stop = PADDING
    if line.right ~= "" then stop = stop + RIGHT_WIDTH + 4 end
    if line.badge then stop = stop + BADGE_WIDTH + 2 end

    row.left:ClearAllPoints()
    row.left:SetPoint("LEFT", indent, 0)
    row.left:SetPoint("RIGHT", -stop, 0)
    row.leftStop = stop
    row.leftIndent = indent
    row.left:SetText(line.left)
    row.left:Show()

    row.right:SetText(line.right)
    row.right:SetTextColor(Theme.Unpack(line.rightColor
        or (line.style == "mob" and "text" or "muted")))
    row.right:Show()

    if line.badge then
        row.badge:SetText(line.badge)
        row.badge:Show()
    else
        row.badge:SetText("")
        row.badge:Hide()
    end

    if line.bar then
        row.track:Show()
        row.fill:SetWidth(math.max(1, BAR * math.min(1, line.bar)))
        row.fill:SetColorTexture(Theme.Unpack(line.barColor or "accent"))
        row.fill:Show()
    else
        row.track:Hide()
        row.fill:Hide()
    end

    row:Show()
end

function TrackerUI:Render()
    self:Build()

    local lines = self:Lines()

    -- While the grip is held, the panel is whatever size the drag says;
    -- otherwise it is the saved size.
    local limit = self.sizing and self.frame:GetHeight() or self:MaxHeight()
    local maxLines = self:LinesFor(limit)

    -- Past the bottom, the last line says how much did not fit rather than
    -- cutting off mid-mob without a word.
    if #lines > maxLines then
        local hidden = #lines - maxLines + 1
        for index = #lines, maxLines, -1 do lines[index] = nil end
        lines[maxLines] = { style = "note", right = "",
            left = ("+%d more lines  |  /farm kills <mob>"):format(hidden) }
    end

    self.shown = lines

    -- As tall as what it holds, up to the saved height: no empty tail under
    -- a short session. Left alone mid-drag, where the drag is in charge.
    if not self.sizing then
        self.frame:SetWidth(self:Width())
        self.frame:SetHeight(HEADER + PADDING * 2 + #lines * LINE)
    end

    for index = 1, math.max(#lines, #self.lines) do
        local line = lines[index]

        if line then
            self:DrawLine(self:Line(index), line)
        elseif self.lines[index] then
            self.lines[index]:Hide()
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

-- After a drag the client re-anchors the panel to whichever corner or edge is
-- nearest, often the bottom or the centre. The panel's height then changes
-- to fit its contents, and a bottom or centre anchor would move its top.
-- Anchor it by its top-left corner instead, where it is now on screen.
-- UIParent's bottom-left is 0,0 in every scale, so the panel's own left and
-- top are the offsets.
function TrackerUI:AnchorTop()
    local frame = self.frame
    if not frame then return end

    local ok, left, top = pcall(function() return frame:GetLeft(), frame:GetTop() end)
    if not (ok and type(left) == "number" and type(top) == "number") then return end

    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
end

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

    -- A panel saved by an earlier version may hang from its bottom or centre.
    if point ~= "TOPLEFT" then
        self:AnchorTop()
        self:SavePosition()
    end
end
