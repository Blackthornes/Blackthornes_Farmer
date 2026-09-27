-- Blackthornes Farmer -- UI/Tracker.lua
-- The kills and loot panel, down the left side of the screen.
--
-- A tall, narrow column under the player and party frames that fills in as
-- you farm. At the top, this session: how many kills, and everything looted
-- with how many of each. Below it, every mob killed this session, latest
-- first, on its own band: its all-time kills, then until it has the 20 it
-- takes for drop rates a progress bar like a goal's ("12 / 20", marks at a
-- quarter, half and three quarters, green in the last stretch) and how many
-- more, then its best drops -- as counts until then, as rates with a bar
-- after.
--
-- Items are drawn the way the bags draw them, icon and quality colour, both
-- remembered from the loot window by the tracker.
--
-- Click a mob's band, or its "Show all" line, for its whole loot table in a
-- window of its own (UI/LootTable.lua).
--
-- /farm tracker (or its X) turns it off and on, and it stays that way from one
-- session to the next. Drag it if the left edge is busy. In a party or raid it
-- steps aside from the group frames (see "In a group" at the bottom).

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
-- The title bar: "Kills & Loot" and the X on top, the session's gathered
-- value on a second line under them.
local TITLE_LINE = 28
local TOTAL_LINE = 20
local HEADER = TITLE_LINE + TOTAL_LINE
TrackerUI.HEADER = HEADER
local LINE = 18
local ICON = 14
local BAR = 40
TrackerUI.BAR = BAR

-- The progress bar toward rates (Trent, 2026-09-27: "a progress bar like
-- the goals"): as tall as a goal's, never shorter than MIN_PROGRESS.
local PROGRESS_HEIGHT = 7
local MIN_PROGRESS = 60
local BRIGHT_GOLD = { 1, 0.906, 0.639 }
local GREEN_TIP = { 0.66, 1, 0.77 }

-- Marks on the bar, and the last stretch that turns it green: a goal's.
local MARKS = { 0.25, 0.5, 0.75 }
local FINAL = 0.1

-- Right-hand value and the green badge beside it, in pixels.
local RIGHT_WIDTH = 54
local BADGE_WIDTH = 28

-- How much of each section to show before moving on to the next.
local LOOT_LINES = 6

-- A kill streak shows once it reaches this many.
local STREAK_SHOWN = 3
local MOB_ITEMS = 3

-- Bumped when the default position moves, so a panel saved at the old spot
-- comes to the new one once instead of staying where nobody asked for it.
local LAYOUT = 2

local FALLBACK_ICON = [[Interface\Icons\INV_Misc_QuestionMark]]
local PLACE_ICON = [[Interface\Icons\INV_Misc_Map_01]]

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

--- The panel's width for lines that need `needs` pixels: the saved width, or
--- wider up to MAX_WIDTH.
function TrackerUI:FitWidth(needs)
    return math.min(MAX_WIDTH, math.max(self:Width(), math.ceil(tonumber(needs) or 0)))
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
        -- Resizing is not picking a spot; in a group it stays beside the
        -- group frames rather than being pinned where it happens to be.
        if not TrackerUI.grouped then TrackerUI:SavePosition() end
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

    frame:SetScript("OnDragStart", function(self)
        TrackerUI.dragging = true
        self:StartMoving()
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        TrackerUI.dragging = false
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
    title:SetPoint("LEFT", header, "TOPLEFT", PADDING + 4, -TITLE_LINE / 2)
    title:SetText("Kills & Loot")

    local close = Widgets.CreateButton(header, "X", function()
        ns.db.trackerHidden = true
        TrackerUI:Refresh()
        ns.Print("kill and loot panel hidden. /farm tracker brings it back.")
    end, { width = 18, height = 16 })
    close:SetPoint("RIGHT", header, "TOPRIGHT", -6, -TITLE_LINE / 2)

    -- The session's gathered value on the title bar's second line (Trent,
    -- 2026-09-27). Built like a line row so the count-up, glow and "+38s" in
    -- UI/TrackerFX.lua work on it unchanged.
    local total = CreateFrame("Frame", nil, header)
    total:SetPoint("TOPLEFT", header, "TOPLEFT", 3, -TITLE_LINE + 2)
    total:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", 0, 2)

    total.left = Theme.CreateLabel(total, "small", "muted")
    total.left:SetPoint("LEFT", PADDING + 1, 0)
    total.left:SetText("Gathered value")

    total.right = Theme.CreateLabel(total, "normal", "good", "RIGHT")
    total.right:SetPoint("RIGHT", -PADDING, 0)

    total.badge = Theme.CreateLabel(total, "tiny", "good", "RIGHT")
    total.badge:SetPoint("RIGHT", total.right, "LEFT", -4, 0)

    local rule = Theme.CreateDivider(frame, "borderLit")
    rule:SetPoint("TOPLEFT", header, "BOTTOMLEFT")
    rule:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT")

    self.frame = frame
    self.title = title
    self.titleRow = total
    self.header = header
    self.closeButton = close
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

    -- The progress bar, the Goals panel's: a dark track, the fill, a
    -- brighter tip, the part just gained, a shine, and the quarter marks.
    -- DrawLine sets where the track runs.
    local bar = {}
    row.progress = bar

    bar.track = row:CreateTexture(nil, "BORDER")
    bar.track:SetHeight(PROGRESS_HEIGHT)
    bar.track:SetColorTexture(Theme.Unpack("row"))

    bar.fill = row:CreateTexture(nil, "ARTWORK")
    bar.fill:SetPoint("TOPLEFT", bar.track, "TOPLEFT")
    bar.fill:SetHeight(PROGRESS_HEIGHT)

    bar.tip = row:CreateTexture(nil, "OVERLAY")
    bar.tip:SetPoint("TOPRIGHT", bar.fill, "TOPRIGHT")
    bar.tip:SetSize(4, PROGRESS_HEIGHT)

    bar.fresh = row:CreateTexture(nil, "OVERLAY")
    bar.fresh:SetHeight(PROGRESS_HEIGHT)
    bar.fresh:SetColorTexture(1, 0.95, 0.8, 1)
    pcall(bar.fresh.SetBlendMode, bar.fresh, "ADD")
    bar.fresh:SetAlpha(0)

    bar.shine = row:CreateTexture(nil, "OVERLAY")
    bar.shine:SetHeight(PROGRESS_HEIGHT)
    bar.shine:SetColorTexture(1, 1, 1, 1)
    pcall(bar.shine.SetBlendMode, bar.shine, "ADD")
    bar.shine:SetAlpha(0)

    bar.marks = {}
    for index = 1, #MARKS do
        local mark = row:CreateTexture(nil, "OVERLAY")
        mark:SetSize(1, PROGRESS_HEIGHT)
        mark:SetColorTexture(1, 1, 1, 0.22)
        bar.marks[index] = mark
    end

    bar.parts = { bar.track, bar.fill, bar.tip, bar.fresh, bar.shine }
    for _, mark in ipairs(bar.marks) do bar.parts[#bar.parts + 1] = mark end

    -- A mob's band and its "Show all" line open its loot table.
    row.dragged = false
    row.hover = Theme.Fill(row, "rowHover", 0.7, "BORDER")
    row.hover:Hide()

    row:SetScript("OnEnter", function(self)
        if not (self.line and self.line.mob) then return end
        self.hover:Show()

        if GameTooltip then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(self.line.mob)
            GameTooltip:AddLine("Click for everything it has dropped.", 1, 1, 1)
            GameTooltip:Show()
        end
    end)

    row:SetScript("OnLeave", function(self)
        self.hover:Hide()
        if GameTooltip then GameTooltip:Hide() end
    end)

    row:SetScript("OnMouseUp", function(self, button)
        -- Letting go at the end of a drag is not a click.
        if self.dragged then
            self.dragged = false
            return
        end

        if button == "LeftButton" and self.line and self.line.mob and ns.LootTableUI then
            ns.LootTableUI:Toggle(self.line.mob)
        end
    end)

    -- A row that takes the mouse would stop the panel dragging from it;
    -- hand the drag on to the panel.
    row:RegisterForDrag("LeftButton")
    row:SetScript("OnDragStart", function(self)
        self.dragged = true
        local start = parent:GetScript("OnDragStart")
        if start then start(parent) end
    end)
    row:SetScript("OnDragStop", function()
        local stop = parent:GetScript("OnDragStop")
        if stop then stop(parent) end
    end)

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
-- `bar` (0-1) and `barColor`, `rightColor`, and `mob` (a mob whose loot table
-- a click opens).
-- A line whose number can go up also has a `key` that names it from one
-- redraw to the next and that `count`, so UI/TrackerFX.lua can tell what just
-- went up and make it move.
-- Styles: "heading", "mob", "place", "value", "item", "note", "link",
-- "progress" (the bar toward rates: `have`, `target`, `progress` 0-1,
-- `milestone` for the marks passed, `final` in the last stretch).
-- A fishing spot or a node is drawn as a "mob" band with no `mob`, so a click
-- opens nothing.
function TrackerUI:Lines()
    local out = {}

    local function Add(line)
        line.right = line.right or ""
        out[#out + 1] = line
        return line
    end

    local mobs = ns.Tracker:SessionMobs()

    -- The Fishing and Gathering sections are there only once you have done
    -- that this session (Trent, 2026-09-25), and whichever you did last goes
    -- on top.
    local fished = ns.Fishing and ns.Fishing.sessionCasts > 0
    local gathered = ns.Gathering and ns.Gathering.sessionGathers > 0

    if #mobs == 0 and not fished and not gathered then
        Add({ style = "note", left = "Nothing killed yet this session." })
        Add({ style = "note", left = "Loot a corpse and it shows up here." })
        return out
    end

    local sections = {}

    if #mobs > 0 then
        sections[#sections + 1] = { key = "kill", draw = function(withTotal)
            self:KillLines(Add, mobs)
        end }
    end

    if fished then
        sections[#sections + 1] = { key = "fishing", draw = function(withTotal)
            self:FishingLines(Add, withTotal)
        end }
    end

    if gathered then
        sections[#sections + 1] = { key = "gathering", draw = function(withTotal)
            self:GatheringLines(Add, withTotal)
        end }
    end

    for index, section in ipairs(sections) do
        if section.key == ns.lastLoot and index > 1 then
            table.remove(sections, index)
            table.insert(sections, 1, section)
            break
        end
    end

    -- The haul's total goes with the kills when there are any, as it always
    -- has; otherwise under whichever heading is on top.
    for index, section in ipairs(sections) do
        section.draw(#mobs == 0 and index == 1)
    end

    return out
end

--- "12 / 20", the first part bright, as a goal's count reads.
function TrackerUI.CountText(have, target)
    return ("%d|c%s / %d|r"):format(have, ns.COLORS.muted, target)
end

--- In the last stretch toward `target`: a few left, and the bar goes green.
function TrackerUI.Final(have, target)
    local left = target - have
    return left > 0 and left <= math.max(1, math.floor(target * FINAL))
end

--- Under a band still short of rates (Trent, 2026-09-27): a progress bar
--- like a goal's, then how many more. `key` is the band's; `more` is the
--- countdown's text, "%d" for the number.
function TrackerUI:ProgressLines(Add, key, have, target, more)
    have = math.max(0, math.min(have, target))
    local fraction = target > 0 and have / target or 0

    local milestone = 0
    for index, at in ipairs(MARKS) do
        if fraction >= at then milestone = index end
    end

    local final = TrackerUI.Final(have, target)
    Add({ style = "progress", key = key .. ":progress", count = have,
        have = have, target = target, progress = fraction,
        milestone = milestone, final = final,
        right = TrackerUI.CountText(have, target), rightColor = "text" })

    -- The last few say so in green, as a goal's do.
    local left = target - have
    Add({ style = "note", left = more:format(left) .. (final and "!" or ""),
        leftColor = final and "good" or nil })
end

--- This session's kills: the loot heading, then each mob killed.
function TrackerUI:KillLines(Add, mobs)
    local Tracker = ns.Tracker

    Add({ style = "heading", left = "THIS SESSION",
        right = Util.Plural(Tracker:SessionKills(), "kill") })

    self:TotalLines(Add)

    -- A streak shows from its third kill (Trent, 2026-09-26), with the
    -- session's best beside it once there is a better one to beat.
    local streak = Tracker:Streak()
    if streak >= STREAK_SHOWN then
        local best = Tracker.bestStreak
        Add({ style = "value", key = "streak", count = streak,
            left = best > streak and ("Kill streak  (best %d)"):format(best) or "Kill streak",
            right = ("x%d"):format(streak), rightColor = "accent" })
    end

    local loot = Tracker:SessionLoot()

    if #loot == 0 then
        Add({ style = "note", left = "No loot yet" })
    end

    for index = 1, math.min(#loot, LOOT_LINES) do
        Add({ style = "item", item = loot[index].name, left = loot[index].name,
            right = ("x%d"):format(loot[index].count),
            key = "loot:" .. loot[index].name, count = loot[index].count })
    end

    if #loot > LOOT_LINES then
        Add({ style = "note", left = ("+%d more items"):format(#loot - LOOT_LINES) })
    end

    for _, summary in ipairs(mobs) do
        -- All-time kills on the band, this session's in green beside them,
        -- and until there are enough for rates, a bar filling toward it.
        Add({ style = "mob", left = summary.mob, mob = summary.mob,
            right = tostring(summary.kills), badge = ("+%d"):format(summary.session),
            key = "mob:" .. summary.mob, count = summary.kills })

        -- Where you kill it most; the loot table lists every place.
        local top = summary.places[1]
        if top then
            Add({ style = "place", left = top.name,
                right = #summary.places > 1 and ("+%d more"):format(#summary.places - 1) or nil })
        end

        if not summary.rated then
            self:ProgressLines(Add, "mob:" .. summary.mob, summary.kills, Tracker.MIN_KILLS,
                summary.needed == 1 and "%d more kill for drop rates" or "%d more kills for drop rates")
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
                    right = ("%d of %d"):format(item.corpses, summary.kills),
                    key = ("mob:%s:%s"):format(summary.mob, item.name), count = item.corpses })
            end
        end

        -- The rest are a click away, in the loot table window.
        if #summary.items > MOB_ITEMS then
            Add({ style = "link", mob = summary.mob,
                left = ("Show all %d items"):format(#summary.items) })
        end

        if summary.rated and #summary.items == 0 then
            Add({ style = "note", left = "nothing dropped yet" })
        end
    end
end

--- What everything gathered this session is worth (Trent, 2026-09-25): coin,
--- loot and fishing catches together, priced like worth per kill. Items with
--- no price are left out, so the total never guesses.
--
-- The total itself sits in the title bar (Trent, 2026-09-27). Returns its
-- line, or nil when nothing gathered this session has a price.
function TrackerUI:TitleTotal()
    if not ns.Value then return nil end

    local total = ns.Value:Session()
    if not total then return nil end

    return { style = "value", left = "Gathered value",
        right = ns.Value.Money(total), rightColor = "good",
        key = "total", count = total }
end

--- The note under the top heading when some items had no price to count.
function TrackerUI:TotalLines(Add)
    if not ns.Value then return end

    local total, details = ns.Value:Session()
    if not total then return end

    local missing = #details.unpriced
    if missing > 0 then
        Add({ style = "note", left = ("%s with no price not counted"):format(
            Util.Plural(missing, "item")) })
    end
end

--- This session's fishing: each spot fished, latest first, laid out like a
--- mob -- casts on the band, where it is, what a cast is worth, best catches.
function TrackerUI:FishingLines(Add, withTotal)
    local Fishing = ns.Fishing
    local Tracker = ns.Tracker

    Add({ style = "heading", left = "FISHING",
        right = Util.Plural(Fishing.sessionCasts, "cast") })

    -- No kills this session and this on top: the haul's total goes here.
    if withTotal then self:TotalLines(Add) end

    for _, summary in ipairs(Fishing:SessionSpots()) do
        Add({ style = "mob", left = (summary.name:gsub("^%l", string.upper)),
            right = tostring(summary.casts), badge = ("+%d"):format(summary.session),
            key = "spot:" .. tostring(summary.key), count = summary.casts })

        if summary.place then
            Add({ style = "place", left = summary.place })
        end

        if not summary.rated then
            self:ProgressLines(Add, "spot:" .. tostring(summary.key), summary.casts, Fishing.MIN_CASTS,
                summary.needed == 1 and "%d more cast for catch rates" or "%d more casts for catch rates")
        end

        local worth = Fishing:WorthPerCast(summary.key)
        if worth then
            Add({ style = "value", left = "Worth per cast",
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
                    right = ("%d of %d"):format(item.casts, summary.casts),
                    key = ("spot:%s:%s"):format(tostring(summary.key), item.name), count = item.casts })
            end
        end

        if #summary.items > MOB_ITEMS then
            Add({ style = "note", left = ("+%d more  |  /farm fishing"):format(
                #summary.items - MOB_ITEMS) })
        end

    end
end

--- This session's gathering: each herb or vein gathered, latest first, laid
--- out like a fishing spot -- gathers on the band, where, worth, what it gave.
function TrackerUI:GatheringLines(Add, withTotal)
    local Gathering = ns.Gathering
    local Tracker = ns.Tracker

    Add({ style = "heading", left = "GATHERING",
        right = Util.Plural(Gathering.sessionGathers, "gather") })

    if withTotal then self:TotalLines(Add) end

    for _, summary in ipairs(Gathering:SessionNodes()) do
        Add({ style = "mob", left = summary.name,
            right = tostring(summary.gathers), badge = ("+%d"):format(summary.session),
            key = "node:" .. tostring(summary.key), count = summary.gathers })

        if summary.place then
            Add({ style = "place", left = summary.place })
        end

        if not summary.rated then
            self:ProgressLines(Add, "node:" .. tostring(summary.key), summary.gathers,
                Gathering.MIN_GATHERS, "%d more for gather rates")
        end

        local worth = Gathering:WorthPerGather(summary.key)
        if worth then
            Add({ style = "value", left = "Worth per node",
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
                    right = ("%d of %d"):format(item.gathers, summary.gathers),
                    key = ("node:%s:%s"):format(tostring(summary.key), item.name), count = item.gathers })
            end
        end

        if #summary.items > MOB_ITEMS then
            Add({ style = "note", left = ("+%d more  |  /farm gathering"):format(
                #summary.items - MOB_ITEMS) })
        end

    end
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
    elseif line.style == "place" then
        row.icon:SetTexture(PLACE_ICON)
        row.icon:Show()
        indent = PADDING + 6 + ICON + 4
        row.left:SetTextColor(Theme.Unpack("muted"))
    else
        row.icon:Hide()

        if line.style == "note" or line.style == "value" or line.style == "progress" then
            indent = PADDING + 6
            row.left:SetTextColor(Theme.Unpack(line.leftColor or "muted"))
        elseif line.style == "link" then
            indent = PADDING + 6
            row.left:SetTextColor(Theme.Unpack("accent"))
        elseif line.style == "heading" then
            row.left:SetTextColor(Theme.Unpack("muted"))
        else
            row.left:SetTextColor(Theme.Unpack("accent"))
        end
    end

    -- The text runs to the value column, or all the way across when a line
    -- has no value. That second case is what cut "Nothing killed yet this
    -- session." short: it stopped where a value would have started.
    --
    -- The value and badge columns are as wide as their text needs, at least
    -- their usual width, so neither is cut short either.
    local rightWidth = math.max(RIGHT_WIDTH, Theme.TextWidth("small", Util.StripColor(line.right)) + 2)
    local badgeWidth = math.max(BADGE_WIDTH, Theme.TextWidth("tiny", line.badge) + 2)
    row.right:SetWidth(rightWidth)
    row.badge:SetWidth(badgeWidth)

    local stop = PADDING
    if line.right ~= "" then stop = stop + rightWidth + 4 end
    if line.badge then stop = stop + badgeWidth + 2 end

    row.left:ClearAllPoints()
    row.left:SetPoint("LEFT", indent, 0)
    row.left:SetPoint("RIGHT", -stop, 0)
    row.leftStop = stop
    row.leftIndent = indent

    -- How wide the panel must be for this line to show in full.
    row.needs = indent + Theme.TextWidth("small", line.left) + stop + 4
    row.left:SetText(line.left or "")
    row.left:Show()

    -- The progress bar runs from the indent to just short of its count.
    local bar = row.progress
    if line.style == "progress" then
        row.barLeft = indent
        row.barRight = stop
        row.needs = indent + MIN_PROGRESS + stop + 4

        bar.track:ClearAllPoints()
        bar.track:SetPoint("LEFT", indent, 0)
        bar.track:SetPoint("RIGHT", -stop, 0)
        for _, part in ipairs(bar.parts) do part:Show() end
        -- Drawn at its real width once the panel's width is settled.
        self:SetProgress(row, line.progress, line.final)
    else
        for _, part in ipairs(bar.parts) do part:Hide() end
    end

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

    -- Only rows that open something take the mouse, so the rest of the panel
    -- still drags from anywhere.
    row.line = line
    row.hover:Hide()
    row:EnableMouse(line.mob ~= nil)

    row:Show()
end

--- How long a row's progress bar is: the panel's width, less the indent
--- and the count.
function TrackerUI:ProgressWidth(row)
    local width = tonumber(self.frame and self.frame:GetWidth()) or self:Width()
    return math.max(20, width - 2 - (row.barLeft or PADDING) - (row.barRight or PADDING))
end

--- A row's progress bar filled to `fraction`, green in the last stretch, as
--- a goal's is (GoalsUI:SetBar).
function TrackerUI:SetProgress(row, fraction, green)
    local bar = row.progress
    local width = self:ProgressWidth(row)
    fraction = math.max(0, math.min(1, tonumber(fraction) or 0))

    bar.fill:SetColorTexture(Theme.Unpack(green and "good" or "accent"))
    bar.fill:SetWidth(math.max(1, width * fraction))
    bar.fill:SetShown(fraction > 0)

    local tip = green and GREEN_TIP or BRIGHT_GOLD
    bar.tip:SetColorTexture(tip[1], tip[2], tip[3], 0.9)
    bar.tip:SetShown(fraction > 0.02 and fraction < 1)

    for index, at in ipairs(MARKS) do
        local mark = bar.marks[index]
        mark:ClearAllPoints()
        mark:SetPoint("TOPLEFT", bar.track, "TOPLEFT", math.floor(width * at), 0)
    end
end

function TrackerUI:Render()
    self:Build()

    local lines = self:Lines()

    -- Every line, before the ones past the bottom are cut: a count that is
    -- only out of sight has not changed.
    local all = {}
    for index, line in ipairs(lines) do all[index] = line end

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

    -- The gathered value goes in the title bar. The effects see it as the
    -- first line, ahead of the column's.
    local titleLine = self:TitleTotal()
    self.titleLine = titleLine

    local fxShown = lines
    if titleLine then
        table.insert(all, 1, titleLine)
        fxShown = { titleLine }
        for _, line in ipairs(lines) do fxShown[#fxShown + 1] = line end
    end

    local function RowFor(index)
        if titleLine then
            if index == 1 then return self.titleRow end
            index = index - 1
        end
        return self.lines[index]
    end

    -- What went up since the last redraw, worked out before drawing so the
    -- value line can carry its "+38s". Never allowed to stop the panel.
    local FX = ns.TrackerFX
    local plan
    if FX then
        local ok, result = pcall(FX.Prepare, FX, all, fxShown)
        plan = ok and result or nil
        if not ok then ns.Debug("panel effects:", tostring(result)) end
    end

    -- As tall as what it holds, up to the saved height: no empty tail under
    -- a short session. Left alone mid-drag, where the drag is in charge.
    local needs = 0

    for index = 1, math.max(#lines, #self.lines) do
        local line = lines[index]

        if line then
            local row = self:Line(index)
            self:DrawLine(row, line)
            needs = math.max(needs, row.needs or 0)
        elseif self.lines[index] then
            self.lines[index]:Hide()
        end
    end

    needs = math.max(needs, self:DrawTitle(titleLine))

    -- At least the width you gave it, and wider when a line needs it, so no
    -- text is cut off (Trent, 2026-09-25: "Loot a corpse and it shows up
    -- he..."). Mid-drag the drag decides, and it widens again on letting go.
    if not self.sizing then
        self.frame:SetWidth(self:FitWidth(needs))
        self.frame:SetHeight(HEADER + PADDING * 2 + #lines * LINE)
    end

    self:FitTitleBadge()

    -- The progress bars again, now that the panel has its width.
    for index, line in ipairs(lines) do
        if line.style == "progress" then
            self:SetProgress(self.lines[index], line.progress, line.final)
        end
    end

    if plan then
        local ok, err = pcall(FX.Play, FX, plan, RowFor)
        if not ok then ns.Debug("panel effects:", tostring(err)) end
    end
end

--- The gathered value on the title bar's second line; "0c" until something
--- gathered has a price. Returns how wide the panel must be for both title
--- lines to show in full.
function TrackerUI:DrawTitle(line)
    local row = self.titleRow
    -- False rather than nil, so an effect still running on it sees no line.
    row.line = line or false
    self.titleBadgeNeeds = nil

    -- Top line: the title, a gap, and the X with its margins.
    local top = PADDING + 4 + Theme.TextWidth("normal", self.title:GetText()) + 8 + 6 + 18 + 6

    local value = line and line.right or (ns.Value and ns.Value.Money(0) or "0c")
    local valueWidth = Theme.TextWidth("normal", value) + 2
    row.right:SetWidth(valueWidth)
    row.right:SetText(value)
    row.right:SetTextColor(Theme.Unpack(line and (line.rightColor or "good") or "muted"))

    -- Second line: the label, a gap, and the value.
    local labelEnd = 3 + PADDING + 1 + Theme.TextWidth("small", row.left:GetText())
    local second = labelEnd + 12 + valueWidth + PADDING

    local badge = line and line.badge
    local badgeWidth = badge and (Theme.TextWidth("tiny", badge) + 2) or 0
    row.badge:SetWidth(math.max(1, badgeWidth))
    row.badge:SetText(badge or "")
    if badge then self.titleBadgeNeeds = labelEnd + 8 + badgeWidth + 4 + valueWidth + PADDING end

    return math.max(top, second)
end

--- The "+38s" only lasts a few seconds, so the panel does not widen for it:
--- it shows when there is room between the label and the value.
function TrackerUI:FitTitleBadge()
    local row = self.titleRow
    local width = self.frame:GetWidth()
    local needs = self.titleBadgeNeeds

    if needs and type(width) == "number" and needs <= width then
        row.badge:Show()
    else
        row.badge:Hide()
    end
end

--------------------------------------------------------------------------------
-- On and off
--------------------------------------------------------------------------------

--- Redraw, and show or hide to match the saved setting.
function TrackerUI:Refresh()
    self:Build()

    -- An open loot table follows the same tally.
    if ns.LootTableUI then ns.LootTableUI:Refresh() end
    if ns.RankingsUI then ns.RankingsUI:Refresh() end

    if ns.db.trackerHidden then
        self.frame:Hide()
        -- Hidden, nothing plays; shown again, the counts start from there.
        if ns.TrackerFX then ns.TrackerFX:Forget() end
        return
    end

    self:Render()
    self.frame:Show()
end

function TrackerUI:Hide()
    if self.frame then self.frame:Hide() end
    if ns.TrackerFX then ns.TrackerFX:Forget() end
end

function TrackerUI:OnEnable()
    self:Refresh()
    self:Place()

    local function Settle() TrackerUI:PlaceSoon() end
    ns.RegisterEvent(self, "GROUP_ROSTER_UPDATE", Settle)
    ns.RegisterEvent(self, "PLAYER_ENTERING_WORLD", Settle)
    -- The group frames moved in Edit Mode. Clients without it skip this.
    ns.RegisterEvent(self, "EDIT_MODE_LAYOUTS_UPDATED", Settle)
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

    -- Moved while in a group: that is where it goes in a group from now on,
    -- and the spot it has when you play alone stays as it was.
    if self.grouped then
        ns.db.trackerGroupX = x
        ns.db.trackerGroupY = y
        return
    end

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

--------------------------------------------------------------------------------
-- In a group
--------------------------------------------------------------------------------

-- The default spot is right where the party frames are. In a party or raid
-- the panel steps to the right of whichever group frames are showing, and
-- goes back when you are on your own again. Drag it while grouped and it
-- keeps that spot for groups instead (trackerGroupX/Y).
--
-- The panel is a plain frame anchored to UIParent, so moving it in combat is
-- allowed; the group frames are only read, never touched.

-- Blizzard's group frames, newest layout first. Whichever are showing count.
local GROUP_FRAMES = {
    "CompactRaidFrameContainer",
    "CompactPartyFrame",
    "PartyFrame",
    "PartyMemberFrame1", "PartyMemberFrame2", "PartyMemberFrame3", "PartyMemberFrame4",
}

-- Space left between the group frames and the panel.
local GROUP_GAP = 8

-- How long to let the group frames lay themselves out after a change.
local SETTLE = 0.5

function TrackerUI:InGroup()
    local ok, grouped = pcall(function()
        if IsInRaid and IsInRaid() then return true end
        if IsInGroup and IsInGroup() then return true end
        return (GetNumGroupMembers and GetNumGroupMembers() or 0) > 0
    end)
    return ok and grouped == true
end

function TrackerUI:DodgeGroupOn()
    return not (ns.db and ns.db.trackerDodgeGroup == false)
end

--- A frame's edges in the panel's own units, or nil if it is not on screen.
local function EdgesIn(frame, scale)
    local ok, left, right, top, bottom = pcall(function()
        if not (frame.IsVisible and frame:IsVisible()) then return end
        local own = frame:GetEffectiveScale() / scale
        local l, r, t, b = frame:GetLeft(), frame:GetRight(), frame:GetTop(), frame:GetBottom()
        -- Compared here, inside the pcall: a secret value raises on it.
        if not (type(l) == "number" and type(r) == "number" and r > l
            and type(t) == "number" and type(b) == "number" and t > b) then
            return
        end
        return l * own, r * own, t * own, b * own
    end)
    if ok and left then return left, right, top, bottom end
end

--- Where the showing group frames are, as one box in the panel's units.
function TrackerUI:GroupFrameBox()
    local ok, scale = pcall(self.frame.GetEffectiveScale, self.frame)
    if not (ok and type(scale) == "number" and scale > 0) then return end

    local box
    for _, name in ipairs(GROUP_FRAMES) do
        local frame = _G[name]
        if frame then
            local left, right, top, bottom = EdgesIn(frame, scale)
            if left then
                if box then
                    box.left = math.min(box.left, left)
                    box.right = math.max(box.right, right)
                    box.top = math.max(box.top, top)
                    box.bottom = math.min(box.bottom, bottom)
                else
                    box = { left = left, right = right, top = top, bottom = bottom }
                end
            end
        end
    end
    return box
end

--- Put the panel where it belongs for being solo or grouped.
function TrackerUI:Place()
    if not self.frame then return end
    -- Never pull it out from under a drag.
    if self.sizing or self.dragging then return end

    self:RestorePosition()

    local db = ns.db or {}
    self.grouped = self:DodgeGroupOn() and self:InGroup()
    if not self.grouped then return end

    if type(db.trackerGroupX) == "number" and type(db.trackerGroupY) == "number" then
        self.frame:ClearAllPoints()
        self.frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", db.trackerGroupX, db.trackerGroupY)
        return
    end

    local box = self:GroupFrameBox()
    if not box then return end

    local ok, left, top = pcall(function() return self.frame:GetLeft(), self.frame:GetTop() end)
    if not (ok and type(left) == "number" and type(top) == "number") then return end

    -- The panel grows downward as it fills, so check the whole height it may
    -- take, not just what it has now.
    local okWidth, width = pcall(self.frame.GetWidth, self.frame)
    if not (okWidth and type(width) == "number") then width = self:Width() end
    local right = left + width
    local bottom = top - self:MaxHeight()
    local overlaps = left < box.right and right > box.left
        and top > box.bottom and bottom < box.top
    if not overlaps then return end

    self.frame:ClearAllPoints()
    self.frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", box.right + GROUP_GAP, top)
end

--- Place it again once the group frames have settled.
function TrackerUI:PlaceSoon()
    if C_Timer and type(C_Timer.After) == "function" then
        pcall(C_Timer.After, SETTLE, function() TrackerUI:Place() end)
    else
        self:Place()
    end
end

function TrackerUI:SetDodgeGroup(on)
    ns.db.trackerDodgeGroup = on and true or false
    self:Place()
end

--- Forget the spot picked for groups; it goes back beside the group frames.
function TrackerUI:ResetGroupSpot()
    if not ns.db then return end
    ns.db.trackerGroupX = nil
    ns.db.trackerGroupY = nil
end
