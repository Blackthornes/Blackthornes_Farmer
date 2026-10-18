-- Blackthornes Farmer -- UI/Recap.lua
-- The run's recap (Logic/Moments.lua decides when): a small card beside the
-- kills panel that sums up a run once you stop for a while, or at the next
-- login when the run ended with a logout. Kills, gold, time spent farming,
-- gold an hour against your usual, the best drop and the luckiest moment.
--
-- Dark glass lines by place. It holds while the mouse is over it, else
-- fades after HOLD seconds; a right-click puts it away. Its size grip is
-- its own (`recapScale`, account wide, never rename it).

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
local LINES = 5

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

    self.lines = {}
    for index = 1, LINES do
        local line = CreateFrame("Frame", nil, frame)
        line:SetPoint("TOPLEFT", frame, "TOPLEFT", 4, -(HEAD + (index - 1) * ROW))
        line:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -(HEAD + (index - 1) * ROW))
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
    foot:SetPoint("TOPLEFT", frame, "TOPLEFT", PADDING + 4, -(HEAD + LINES * ROW + 6))
    foot:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PADDING, -(HEAD + LINES * ROW + 6))
    foot:SetWordWrap(true)
    foot:SetJustifyH("LEFT")
    self.foot = foot

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

--- The rows for `summary`: { { label, value, colorKey } }.
function RecapUI.Rows(summary)
    local rows = {}
    rows[#rows + 1] = { L["Kills"], tostring(summary.kills or 0) }
    rows[#rows + 1] = { L["Gold"], ns.Value.Coins(summary.copper or 0), "good" }
    rows[#rows + 1] = { L["Time farming"], ns.XP and ns.XP.Duration and ns.XP.Duration(summary.seconds or 0)
        or tostring(math.floor((summary.seconds or 0) / 60)) }

    local rate = ns.Value.Coins(summary.rate or 0)
    local change = tonumber(summary.change)
    if change and change >= PaceShow() then
        rate = rate .. " " .. Util.Colored("good", L.Format("(up %d%%)", change))
    elseif summary.usual then
        rate = rate .. " " .. Util.Colored("muted", L.Format("(usual %s)", ns.Value.Coins(summary.usual)))
    end
    rows[#rows + 1] = { L["Gold an hour"], rate }

    if summary.best then
        local look = ns.Tracker and ns.Tracker:LookOf(summary.best)
        local color = look and type(look.color) == "string" and #look.color == 8 and look.color
        rows[#rows + 1] = { L["Best drop"], color and ("|c%s%s|r"):format(color, summary.best)
            or ns.Util.ColorItem(summary.best) }
    end
    return rows
end

--- Show the card for `summary` under `title`.
function RecapUI:Show(summary, title)
    if type(summary) ~= "table" then return end
    local frame = self:Build()

    frame.title:SetText(title or L["YOUR RUN"])
    local rows = RecapUI.Rows(summary)
    local width = WIDTH
    for index, line in ipairs(self.lines) do
        local row = rows[index]
        line:SetShown(row ~= nil)
        if row then
            line.left:SetText(row[1])
            line.right:SetText(row[2])
            line.right:SetTextColor(Theme.Unpack(row[3] or "text"))
            width = math.max(width, PADDING * 2 + 8 + 16
                + Theme.TextWidth("normal", row[1]) + Theme.TextWidth("normal", Util.StripColor(row[2])))
        end
    end
    frame:SetWidth(width)

    local foot = type(summary.lucky) == "string" and summary.lucky or ""
    self.foot:SetText(foot)
    local footHeight = 0
    if foot ~= "" then
        local ok, height = pcall(self.foot.GetStringHeight, self.foot)
        footHeight = (ok and tonumber(height) or 14) + 8
    end
    frame:SetHeight(HEAD + ROW * #rows + footHeight + 10)

    self:Place()
    frame:SetAlpha(1)
    frame:Show()
    if ns.Motion then ns.Motion:Open(frame, 10) end

    self.holding = self.HOLD
    self.fading = false
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
        frame:SetPoint("TOP", UIParent, "TOP", 0, -140)
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
