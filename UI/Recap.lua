-- Blackthornes Farmer -- UI/Recap.lua
-- The run's recap (Logic/Moments.lua decides when): a small card beside the
-- kills panel that sums up a run once you stop for a while, or at the next
-- login when the run ended with a logout. Kills, gold, time spent farming,
-- gold an hour against your usual, the best drop and the luckiest moment.
--
-- The look of 2026-11-26 (the owner said build it, from the mockup
-- farmer-improve-4-run-graph-and-recap, and approved its words): how long
-- and where on top, then what you made, gold an hour and kills as three big
-- numbers, then the best drops and "Coin and everything else" in dark glass
-- lines, and a Close button.
--
-- "Run Recap Stays:" (`recapStays`, false when off; never rename it), on
-- unless unticked: it stays until you close it (the close gem, Close or a
-- right-click). Unticked, it holds while the mouse is over it, else fades
-- after HOLD seconds, as before. Its size grip is its own (`recapScale`,
-- account wide, never rename it).

local _, ns = ...
local L = ns.L

local RecapUI = ns.NewModule("RecapUI")

local Theme = ns.Theme
local Widgets = ns.Widgets
local Util = ns.Util

local PADDING = 10
local ROW = 20
local HEAD = 30
local WIDTH = 280
local LINES = 6
-- The line under the header, and the three big numbers under it.
local SUB = 20
local BIG = 42
local BIG_SIZE = 20
local FOOT = 30

function RecapUI.Stays()
    return not (ns.db and ns.db.recapStays == false)
end

function RecapUI:SetStays(on)
    if not ns.db then return end
    if on == false then ns.db.recapStays = false else ns.db.recapStays = nil end
    if self:IsShown() then
        if RecapUI.Stays() then
            self.holding = nil
            self.timer:Hide()
        else
            self.holding = self.HOLD
            self.timer:Show()
        end
    end
end

RecapUI.HOLD = 14
RecapUI.FADE = 0.7

function RecapUI:Build()
    if self.frame then return self.frame end

    local frame = CreateFrame("Frame", "BlackthornesFarmerRecap", UIParent)
    frame:SetSize(WIDTH, HEAD + ROW * LINES + 40)
    frame:SetFrameStrata("MEDIUM")
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)

    local back = Theme.Fill(frame, "window", 0.94)
    Theme.Border(frame, "borderLit")
    Theme.Halo(frame, 8, 0.12)

    local header = Theme.CreatePanel(frame, "header", false)
    header:SetPoint("TOPLEFT", 1, -1)
    header:SetPoint("TOPRIGHT", -1, -1)
    header:SetHeight(HEAD - 4)
    if Theme.HouseHeader then Theme.HouseHeader(header) end

    local title = Theme.CreateLabel(header, "normal", "accent")
    title:SetPoint("LEFT", header, "LEFT", PADDING + 4, 0)
    frame.title = title

    -- The close gem; the fold gem has nothing to fold here.
    if Widgets.CreatePanelGems then
        local gems = Widgets.CreatePanelGems(header, { onClose = function() RecapUI:Hide() end })
        gems.fold:Hide()
        self.closeGem = gems.close
    end

    -- How long and where.
    self.sub = Theme.CreateLabel(frame, "small", "muted")
    self.sub:SetPoint("TOPLEFT", frame, "TOPLEFT", PADDING + 4, -(HEAD + 4))

    -- What you made, gold an hour and kills.
    self.big = {}
    for index = 1, 3 do
        local value = Theme.CreateLabel(frame, BIG_SIZE, index == 3 and "text" or "good")
        local caption = Theme.CreateLabel(frame, "tiny", "muted")
        caption:SetPoint("TOPLEFT", value, "BOTTOMLEFT", 0, -1)
        self.big[index] = { value = value, caption = caption }
    end

    self.lines = {}
    for index = 1, LINES do
        local line = CreateFrame("Frame", nil, frame)
        line:SetPoint("TOPLEFT", frame, "TOPLEFT", 4, -(HEAD + SUB + BIG + (index - 1) * ROW))
        line:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -(HEAD + SUB + BIG + (index - 1) * ROW))
        line:SetHeight(ROW)

        local stripe = line:CreateTexture(nil, "BACKGROUND")
        stripe:SetAllPoints(line)
        stripe:SetColorTexture(Theme.Unpack(index % 2 == 1 and "glass" or "glassAlt"))

        local rule = line:CreateTexture(nil, "BORDER")
        rule:SetPoint("BOTTOMLEFT")
        rule:SetPoint("BOTTOMRIGHT")
        rule:SetHeight(1)
        rule:SetColorTexture(Theme.Unpack("border", 0.6))

        line.left = Theme.CreateLabel(line, "normal", "muted")
        line.left:SetPoint("LEFT", line, "LEFT", PADDING, 0)
        line.right = Theme.CreateLabel(line, "normal", "text", "RIGHT")
        line.right:SetPoint("RIGHT", line, "RIGHT", -PADDING, 0)
        self.lines[index] = line
        ns.SeeThrough:AddGlass("recap", stripe)
        ns.SeeThrough:AddGlass("recap", rule)
    end

    local foot = Theme.CreateLabel(frame, "small", "accent")
    foot:SetPoint("TOPLEFT", frame, "TOPLEFT", PADDING + 4, -(HEAD + SUB + BIG + LINES * ROW + 6))
    foot:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PADDING, -(HEAD + SUB + BIG + LINES * ROW + 6))
    foot:SetWordWrap(true)
    foot:SetJustifyH("LEFT")
    self.foot = foot

    -- Close, at the foot. Save This Farm sits left of it while Saved
    -- Farms is on (UI/SavedFarms.lua).
    local closeWidth = math.max(64, math.ceil(Theme.TextWidth("small", L["Close"]) or 0) + 24)
    self.closeButton = Widgets.CreateButton(frame, L["Close"], function() RecapUI:Hide() end,
        { primary = true, width = closeWidth, height = 20 })
    self.closeButton:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -PADDING, 7)

    -- A thin gold line along the bottom that runs down while it holds.
    local timer = frame:CreateTexture(nil, "ARTWORK")
    timer:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 4, 3)
    timer:SetHeight(1)
    timer:SetColorTexture(Theme.Unpack("accent", 0.7))
    self.timer = timer

    frame:SetScript("OnUpdate", function(_, elapsed) RecapUI:Tick(elapsed) end)
    frame:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" then RecapUI:Hide() end
    end)

    Widgets.ApplySize(frame, ns.db and ns.db.recapScale)
    self.sizeGrip = Widgets.CreateSizeGrip(frame, {
        get = function() return ns.db and ns.db.recapScale end,
        save = function(percent) if ns.db then ns.db.recapScale = percent end end,
        done = function() RecapUI:Place() end,
    })

    -- See-through (UI/SeeThrough.lua, `recapSeeThrough`).
    ns.SeeThrough:AddGlass("recap", back)
    ns.SeeThrough:AddGlass("recap", header.background)
    ns.SeeThrough:Attach("recap", frame)

    frame:Hide()
    self.frame = frame
    return frame
end

local function PaceShow()
    return ns.Moments and ns.Moments.PACE_SHOW or 5
end

--- The top line: how long, where, and how it went against your usual.
function RecapUI.SubText(summary)
    local long = ns.XP and ns.XP.Duration and ns.XP.Duration(summary.seconds or 0)
        or tostring(math.floor((summary.seconds or 0) / 60))
    local text = type(summary.zone) == "string" and L.Format("%s in %s", long, summary.zone) or long
    local change = tonumber(summary.change)
    if change and change >= PaceShow() then
        text = text .. " " .. Util.Colored("good", L.Format("(up %d%%)", change))
    elseif summary.usual then
        text = text .. " " .. L.Format("(usual %s)", ns.Value.Coins(summary.usual))
    end
    return text
end

--- The three big numbers: { { value, caption } }.
function RecapUI.Big(summary)
    return {
        { ns.Value.Coins(summary.copper or 0), L["made"] },
        { ns.Value.Coins(math.floor((summary.rate or 0) + 0.5)), L["an hour"] },
        { tostring(summary.kills or 0), L["kills"] },
    }
end

local function ItemName(name)
    local look = ns.Tracker and ns.Tracker:LookOf(name)
    local color = look and type(look.color) == "string" and #look.color == 8 and look.color
    return color and ("|c%s%s|r"):format(color, name) or ns.Util.ColorItem(name)
end

--- The rows for `summary`: { { label, value, colorKey } }. The drops it
--- names, then the coin and everything else. A run saved before the drops
--- were kept shows its best drop.
function RecapUI.Rows(summary)
    local rows = {}
    if type(summary.items) == "table" then
        for _, item in ipairs(summary.items) do
            local label = ItemName(item.name)
            if (tonumber(item.count) or 1) > 1 then
                label = label .. " " .. Util.Colored("muted", "x" .. tostring(item.count))
            end
            rows[#rows + 1] = { label, ns.Value.Coins(item.worth or 0) }
        end
        if (tonumber(summary.rest) or 0) > 0 then
            rows[#rows + 1] = { L["Coin and everything else"], ns.Value.Coins(summary.rest) }
        end
    elseif summary.best then
        rows[#rows + 1] = { L["Best drop"], ItemName(summary.best) }
    end

    -- The session timer's run (Logic/SessionTimer.lua): how long it sat paused.
    local paused = tonumber(summary.paused)
    if paused and paused > 0 then
        rows[#rows + 1] = { L["Time paused:"], ns.XP and ns.XP.Duration and ns.XP.Duration(paused)
            or tostring(math.floor(paused / 60)) }
    end
    while #rows > LINES do table.remove(rows) end
    return rows
end

--- Show the card for `summary` under `title`.
function RecapUI:Show(summary, title)
    if type(summary) ~= "table" then return end
    local frame = self:Build()

    frame.title:SetText(title or L["YOUR RUN"])

    local width = WIDTH
    local subText = RecapUI.SubText(summary)
    self.sub:SetText(subText)
    width = math.max(width, PADDING * 2 + 8 + Theme.TextWidth("small", Util.StripColor(subText)))

    -- The big numbers, side by side, each as wide as its words.
    local x = PADDING + 4
    for index, big in ipairs(RecapUI.Big(summary)) do
        local cell = self.big[index]
        cell.value:SetText(big[1])
        cell.caption:SetText(big[2])
        cell.value:ClearAllPoints()
        cell.value:SetPoint("TOPLEFT", frame, "TOPLEFT", x, -(HEAD + SUB + 2))
        x = x + math.max(Theme.TextWidth(BIG_SIZE, Util.StripColor(big[1])),
            Theme.TextWidth("tiny", big[2])) + 20
    end
    width = math.max(width, x + PADDING - 20 + 8)

    local rows = RecapUI.Rows(summary)
    for index, line in ipairs(self.lines) do
        local row = rows[index]
        line:SetShown(row ~= nil)
        if row then
            line.left:SetText(row[1])
            line.right:SetText(row[2])
            line.right:SetTextColor(Theme.Unpack(row[3] or "text"))
            width = math.max(width, PADDING * 2 + 8 + 16
                + Theme.TextWidth("normal", Util.StripColor(row[1])) + Theme.TextWidth("normal", Util.StripColor(row[2])))
        end
    end
    -- The foot: Close, and Save This Farm left of it while Saved Farms is on.
    local footNeeds = PADDING * 2 + (self.closeButton:GetWidth() or 64)
    if ns.SavedFarms and ns.SavedFarms.On and ns.SavedFarms.On() then
        footNeeds = footNeeds + 6 + Theme.TextWidth("small", L["Save This Farm"]) + 24
    end
    width = math.max(width, footNeeds)
    frame:SetWidth(width)

    local top = HEAD + SUB + BIG + #rows * ROW
    local foot = type(summary.lucky) == "string" and summary.lucky or ""
    self.foot:SetText(foot)
    self.foot:ClearAllPoints()
    self.foot:SetPoint("TOPLEFT", frame, "TOPLEFT", PADDING + 4, -(top + 6))
    self.foot:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PADDING, -(top + 6))
    local footHeight = 0
    if foot ~= "" then
        local ok, height = pcall(self.foot.GetStringHeight, self.foot)
        footHeight = (ok and tonumber(height) or 14) + 8
    end
    frame:SetHeight(top + footHeight + 6 + FOOT)

    self:Place()
    frame:SetAlpha(1)
    frame:Show()
    if ns.Motion then ns.Motion:Open(frame, 10) end

    self.fading = false
    if RecapUI.Stays() then
        -- It stays until you close it.
        self.holding = nil
        self.timer:Hide()
        return
    end
    self.holding = self.HOLD
    self.timer:Show()
    self:Tick(0)
end

--- Beside the kills panel, else high in the middle.
function RecapUI:Place()
    local frame = self.frame
    if not frame then return end
    frame:ClearAllPoints()

    local panel = ns.TrackerUI and ns.TrackerUI.frame
    if panel and panel:IsShown() then
        local ok, right, screen = pcall(function() return panel:GetRight(), UIParent:GetWidth() end)
        local width = (frame:GetWidth() or 0) * ((frame.GetScale and frame:GetScale()) or 1)
        if ok and type(right) == "number" and type(screen) == "number" and right + width + 12 > screen then
            frame:SetPoint("BOTTOMRIGHT", panel, "BOTTOMLEFT", -10, 0)
        else
            frame:SetPoint("BOTTOMLEFT", panel, "BOTTOMRIGHT", 10, 0)
        end
    else
        -- No panel to sit beside: the next free place on the shared top
        -- shelf (UI/SharedWindow.lua), so it never lands on the arrow.
        local sw = ns.SharedWindow
        local placed = sw and sw.ShelfPlace and sw.ShelfPlace(frame, "recap.farmer", {
            free = function()
                local panel = ns.TrackerUI and ns.TrackerUI.frame
                return not (panel and panel:IsShown())
            end,
            place = function() RecapUI:Place() end,
        })
        if not placed then
            frame:SetPoint("TOP", UIParent, "TOP", 0, -140)
        end
    end
end

function RecapUI:Tick(elapsed)
    if not self.holding or self.fading then return end

    local ok, over = pcall(function() return self.frame:IsMouseOver() end)
    if not (ok and over) then
        self.holding = self.holding - (tonumber(elapsed) or 0)
    end

    local ok2, width = pcall(self.frame.GetWidth, self.frame)
    width = (ok2 and tonumber(width) or WIDTH) - 8
    self.timer:SetWidth(math.max(1, width * math.max(0, self.holding / self.HOLD)))

    if self.holding <= 0 then self:FadeOut() end
end

function RecapUI:FadeOut()
    if self.fading or not self.frame then return end
    self.fading = true
    self.timer:Hide()

    local frame = self.frame
    ns.Motion:Run(frame, "fade", self.FADE, function(p) frame:SetAlpha(1 - p) end, {
        done = function()
            RecapUI.holding = nil
            RecapUI.fading = false
            frame:Hide()
            frame:SetAlpha(1)
        end,
    })
end

function RecapUI:Hide()
    if ns.Motion and self.frame then ns.Motion:Stop(self.frame) end
    self.holding = nil
    self.fading = false
    if self.frame then
        self.frame:Hide()
        self.frame:SetAlpha(1)
    end
end

function RecapUI:IsShown()
    return self.frame and self.frame:IsShown() or false
end
