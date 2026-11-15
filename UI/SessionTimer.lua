-- Blackthornes Farmer -- UI/SessionTimer.lua
-- The session timer's strip in the Kills & Loot panel (Logic/SessionTimer.lua
-- keeps the clock). It sits under the Gathered value line: the clock and a
-- tag (Ready, Timing or Paused), a note while it paused by itself, and
-- Start, Pause and Stop. Start reads Resume while paused.
--
-- Each button has a gold copy and a plain one, and the one the state wants
-- shows: gold for the next thing to do, plain for the rest, plain and dim
-- for what does nothing right now (a dim click is ignored). All are as wide
-- as the widest of the four words, so none is ever cut.
--
-- With the timer off the strip is 0 tall and hidden, and the panel is laid
-- out exactly as before (UI/Tracker.lua, `PlaceTimer`).

local _, ns = ...
local L = ns.L
local Theme = ns.Theme
local Widgets = ns.Widgets

local SessionTimerUI = ns.NewModule("SessionTimerUI")

SessionTimerUI.PAD = 8
SessionTimerUI.CLOCK = 28      -- the clock's row
SessionTimerUI.NOTE = 16       -- the note's row, while it paused by itself
SessionTimerUI.BUTTON = 20
SessionTimerUI.GAP = 6

local BUTTONS = { "start", "pause", "stop" }

-- What each button says on its hover.
local TIPS = {
    start = "Start the clock for this run.",
    pause = "Stop the clock for a bit. Your loot still counts.",
    stop = "End this run and see how it went.",
}

-- The tag's words and colour, by state.
local TAGS = {
    ready = { "Ready", "muted" },
    timing = { "Timing", "good" },
    paused = { "Paused", "accentHi" },
}

--- 0:42:15, always with the hour, so the clock never jumps in width.
function SessionTimerUI.Clock(seconds)
    seconds = math.max(0, math.floor(tonumber(seconds) or 0))
    local h = math.floor(seconds / 3600)
    local m = math.floor(seconds % 3600 / 60)
    local s = seconds % 60
    return string.format("%d:%02d:%02d", h, m, s)
end

--- Which look each button wears now: "gold", "plain" or "dim".
function SessionTimerUI.Looks(state)
    if state == "timing" then
        return { start = "dim", pause = "gold", stop = "plain" }
    elseif state == "paused" then
        return { start = "gold", pause = "dim", stop = "plain" }
    end
    return { start = "gold", pause = "dim", stop = "dim" }
end

--- The word on Start: Resume while paused.
function SessionTimerUI.StartWord(state)
    return state == "paused" and L["Resume"] or L["Start"]
end

local function Timer()
    return ns.SessionTimer
end

local function On()
    local timer = Timer()
    return timer and timer.On and timer.On() or false
end

--- How wide each button is: the widest of the four words.
function SessionTimerUI.ButtonWidth()
    local most = 0
    for _, word in ipairs({ L["Start"], L["Pause"], L["Resume"], L["Stop"] }) do
        most = math.max(most, Theme.TextWidth("small", word))
    end
    return most + 16
end

--- How wide the panel must be for the strip.
function SessionTimerUI.Needs()
    if not On() then return 0 end
    local self = SessionTimerUI
    return self.PAD * 2 + self.ButtonWidth() * 3 + self.GAP * 2
end

--- How tall the strip is now: 0 while the timer is off.
function SessionTimerUI:Height()
    if not On() then return 0 end
    local timer = Timer()
    local h = self.PAD + self.CLOCK + self.GAP + self.BUTTON + self.PAD
    if timer:Note() then h = h + self.NOTE end
    return h
end

local function Clicked(key)
    local timer = Timer()
    if not timer then return end
    local look = SessionTimerUI.Looks(timer.state)[key]
    if look == "dim" then return end
    if key == "start" then
        timer:Start()
    elseif key == "pause" then
        timer:Pause()
    elseif key == "stop" then
        timer:Stop()
    end
end

local function ShowTip(button, key)
    if not GameTooltip then return end
    GameTooltip:SetOwner(button, "ANCHOR_TOP")
    local word = key == "start" and SessionTimerUI.StartWord(Timer() and Timer().state)
        or key == "pause" and L["Pause"] or L["Stop"]
    GameTooltip:SetText(word, 1, 0.9, 0.6)
    GameTooltip:AddLine(L[TIPS[key]], 1, 1, 1, true)
    GameTooltip:Show()
end

--- The strip, made once under the panel `frame`.
function SessionTimerUI:Build(frame)
    if self.strip then return self.strip end
    local strip = CreateFrame("Frame", nil, frame)
    strip:SetHeight(1)
    if ns.TrackerUI and ns.TrackerUI.AddGlass then
        ns.TrackerUI:AddGlass(Theme.Fill(strip, "glassActive", 0.9))
    else
        Theme.Fill(strip, "glassActive", 0.9)
    end
    local top = Theme.CreateDivider(strip, "accent")
    top:SetPoint("TOPLEFT", strip, "TOPLEFT", 0, 0)
    top:SetPoint("TOPRIGHT", strip, "TOPRIGHT", 0, 0)
    local bottom = Theme.CreateDivider(strip, "borderLit")
    bottom:SetPoint("BOTTOMLEFT", strip, "BOTTOMLEFT", 0, 0)
    bottom:SetPoint("BOTTOMRIGHT", strip, "BOTTOMRIGHT", 0, 0)

    local clock = Theme.CreateLabel(strip, "title", "accentHi")
    clock:SetPoint("TOPLEFT", strip, "TOPLEFT", self.PAD, -self.PAD)
    clock:SetHeight(self.CLOCK)
    pcall(function()
        local font, size, flags = clock:GetFont()
        if font then clock:SetFont(font, (size or 16) + 8, flags) end
    end)
    strip.clock = clock

    local tag = CreateFrame("Frame", nil, strip)
    tag:SetHeight(16)
    tag:SetPoint("LEFT", clock, "RIGHT", 10, 0)
    tag.fill = Theme.Fill(tag, "glass", 0.9)
    tag.edge = Theme.Border(tag, "borderLit", 0.9)
    tag.label = Theme.CreateLabel(tag, "small", "muted", "CENTER")
    tag.label:SetPoint("CENTER", 0, 0)
    strip.tag = tag

    local note = Theme.CreateLabel(strip, "small", "muted")
    note:SetPoint("TOPLEFT", clock, "BOTTOMLEFT", 0, -2)
    note:SetPoint("RIGHT", strip, "RIGHT", -self.PAD, 0)
    note:Hide()
    strip.note = note

    strip.buttons = {}
    local width = self.ButtonWidth()
    for _, key in ipairs(BUTTONS) do
        local pair = {}
        for _, look in ipairs({ "gold", "plain" }) do
            local button = Widgets.CreateButton(strip, L["Start"], function() Clicked(key) end,
                { width = width, height = self.BUTTON, primary = look == "gold" })
            button:HookScript("OnEnter", function(b) ShowTip(b, key) end)
            button:HookScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
            button:Hide()
            pair[look] = button
        end
        strip.buttons[key] = pair
    end

    strip:Hide()
    self.strip = strip
    return strip
end

--- The clock's words only (the ticker, once a second while timing).
function SessionTimerUI:Tick()
    local strip, timer = self.strip, Timer()
    if not (strip and timer and strip:IsShown()) then return end
    local words = self.Clock(timer:Seconds())
    if words ~= strip.clockText then
        strip.clockText = words
        strip.clock:SetText(words)
    end
end

--- Lay the strip out at `width` for the state the clock is in.
function SessionTimerUI:Draw(width)
    local strip, timer = self.strip, Timer()
    if not (strip and timer) then return end
    if not On() then strip:Hide() return end
    strip:Show()

    local state = timer.state or "ready"
    strip.clockText = nil
    self:Tick()
    strip.clock:SetText(self.Clock(timer:Seconds()))
    strip.clock:SetTextColor(Theme.Unpack(state == "ready" and "dim" or "accentHi"))
    strip.clock:SetAlpha(state == "paused" and 0.6 or 1)

    local tag = TAGS[state] or TAGS.ready
    strip.tag.label:SetText(L[tag[1]])
    strip.tag.label:SetTextColor(Theme.Unpack(tag[2]))
    strip.tag:SetWidth(Theme.TextWidth("small", L[tag[1]]) + 16)

    local note = timer:Note()
    strip.note:SetText(note or "")
    strip.note:SetShown(note ~= nil)

    -- The buttons share the width left, never narrower than their words.
    width = tonumber(width) or 0
    local each = math.max(self.ButtonWidth(),
        math.floor((width - self.PAD * 2 - self.GAP * 2) / 3))
    local y = -(self.PAD + self.CLOCK + self.GAP + (note and self.NOTE or 0))
    local looks = self.Looks(state)
    for index, key in ipairs(BUTTONS) do
        local pair = strip.buttons[key]
        local look = looks[key]
        local show = look == "gold" and pair.gold or pair.plain
        local hide = look == "gold" and pair.plain or pair.gold
        hide:Hide()
        local word = key == "start" and self.StartWord(state) or key == "pause" and L["Pause"] or L["Stop"]
        show:SetText(word)
        show:SetWidth(each)
        show:ClearAllPoints()
        show:SetPoint("TOPLEFT", strip, "TOPLEFT", self.PAD + (index - 1) * (each + self.GAP), y)
        if look ~= "gold" then show:SetLabelColor(look == "dim" and "dim" or nil) end
        show:SetAlpha(look == "dim" and 0.5 or 1)
        show:Show()
    end
end
