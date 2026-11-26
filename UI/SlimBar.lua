--------------------------------------------------------------------------------
-- UI/SlimBar.lua
--
-- Slim Bar for Kills & Loot (the owner said build it, 2026-11-26, from the
-- mockup farmer-improve-1-slim-bar, and approved its words). "Kills and Loot
-- Size:" on the WINDOWS page picks Full Panel (the default) or Slim Bar.
--
-- Slim Bar is the same panel folded to one line: the gold coin, gold an
-- hour, this run, kills and the clock. The mouse on it drops the whole list
-- down; the mouse off folds it back. A click on the bar keeps the list open
-- until the next click; a right-click opens Sort (and the Zone Board while
-- it is ticked). A green or better drop shows on the bar for a few seconds.
--
-- It is the panel's own frame, so it keeps the panel's spot, drags, docks
-- the goals under it, and follows Transparent and Panel Style with no work
-- of its own. Nothing new is counted: the words come from what the panel
-- already reads. While folded, only the bar's one line is written, and only
-- when its words change (the clock, once a second). Saved account wide as
-- `trackerSlimBar` (true, or nil for Full Panel), never rename it.
--------------------------------------------------------------------------------

local _, ns = ...

local SlimBar = ns.NewModule("SlimBar")

local L = ns.L
local Theme = ns.Theme

--- How often the mouse is looked for, in seconds.
SlimBar.LOOK = 0.1
--- How long the mouse may be off before the list folds back.
SlimBar.CLOSE_WAIT = 0.4
--- How often the bar's words are read again (the clock moves each second).
SlimBar.TICK = 1
--- How long a good drop stays on the bar.
SlimBar.FLASH = 5
--- Green and better drops show on the bar.
SlimBar.FLASH_QUALITY = 2
--- The bar's height: the title line of the full panel.
SlimBar.HEIGHT = 28
--- The gold coin at the start of the bar.
SlimBar.COIN = [[Interface\MoneyFrame\UI-GoldIcon]]

--- The two sizes, in the order Settings shows them.
SlimBar.SIZES = { "full", "slim" }

function SlimBar.Names()
    return { L["Full Panel"], L["Slim Bar"] }
end

function SlimBar.On()
    return ns.db ~= nil and ns.db.trackerSlimBar == true
end

--- 1 for Full Panel, 2 for Slim Bar (the Settings choice).
function SlimBar:Index()
    return SlimBar.On() and 2 or 1
end

--- Pick Full Panel or Slim Bar, by index, key or true/false.
function SlimBar:Set(value)
    local on
    if value == true or value == 2 or value == "slim" then
        on = true
    elseif value == false or value == 1 or value == "full" then
        on = false
    else
        return false
    end
    if not ns.db then return false end
    ns.db.trackerSlimBar = on or nil
    self.pinned, self.hovered, self.flash, self.seen = nil, nil, nil, nil
    self.wide, self.numbers = nil, nil
    local ui = ns.TrackerUI
    if ui and ui.frame then
        if not on then self:Restore(ui) end
        self:Watch(ui)
        ui:Refresh()
    end
    return true
end

--- The list shows: the mouse is on the bar, or a click keeps it open.
function SlimBar:IsOpen()
    return self.pinned == true or self.hovered == true
end

--- Slim Bar on and folded to its one line.
function SlimBar:Folded()
    return SlimBar.On() and not self:IsOpen()
end

--------------------------------------------------------------------------------
-- The words
--------------------------------------------------------------------------------

--- "19:42" under an hour, "1:02:05" past it.
function SlimBar.Clock(seconds)
    seconds = math.max(0, math.floor(tonumber(seconds) or 0))
    local h = math.floor(seconds / 3600)
    local m = math.floor(seconds % 3600 / 60)
    local s = seconds % 60
    if h > 0 then return ("%d:%02d:%02d"):format(h, m, s) end
    return ("%d:%02d"):format(m, s)
end

--- Seconds this run has been timed: the session timer when it is on, else
--- the panel's own clock from the first thing gathered. Nil before either.
function SlimBar.Seconds()
    local timer = ns.SessionTimer
    if timer and timer.On and timer.On() and timer.state ~= "ready" then
        local ok, seconds = pcall(timer.Seconds, timer)
        if ok and type(seconds) == "number" then return seconds end
    end
    local ui = ns.TrackerUI
    local started = ui and ui.startedAt
    if type(started) ~= "number" or type(GetTime) ~= "function" then return nil end
    local ok, now = pcall(GetTime)
    if not (ok and type(now) == "number") then return nil end
    return math.max(0, now - started)
end

local SEPARATOR = "  |cff7a715e||r  "

--- The bar's numbers: gold an hour (once there is one), this run and
--- kills. Read when the panel redraws (something changed), never on the
--- clock's tick: pricing a long session each second would cost play.
function SlimBar:ReadNumbers()
    local Value = ns.Value
    local function Coins(copper)
        if Value and Value.Coins then return Value.Coins(math.floor(copper + 0.5)) end
        return tostring(math.floor(copper + 0.5))
    end

    local parts = {}
    local ui = ns.TrackerUI
    local perHour = ui and ui.PerHour and ui:PerHour()
    if type(perHour) == "number" then
        parts[#parts + 1] = L.Format("%s an hour", Coins(perHour))
    end
    local run = Value and Value.Session and Value:Session() or 0
    parts[#parts + 1] = L.Format("%s this run", Coins(tonumber(run) or 0))
    local kills = ns.Tracker and ns.Tracker.SessionKills and ns.Tracker:SessionKills() or 0
    parts[#parts + 1] = ns.Util.Plural(kills, L["kill"], L["kills"])
    self.numbers = parts
    return parts
end

--- The bar's line: the coin, the numbers last read and the clock.
function SlimBar:Text()
    local parts = {}
    for index, part in ipairs(self.numbers or self:ReadNumbers()) do parts[index] = part end
    local seconds = SlimBar.Seconds()
    if seconds then parts[#parts + 1] = SlimBar.Clock(seconds) end
    return ("|T%s:14:14:0:0|t "):format(SlimBar.COIN) .. table.concat(parts, SEPARATOR)
end

--------------------------------------------------------------------------------
-- A good drop on the bar
--------------------------------------------------------------------------------

local function Counts()
    local counts = {}
    local function Take(from)
        for name, count in pairs(from or {}) do
            if not ns.Tracker.Counts or ns.Tracker.Counts(name) then
                counts[name] = (counts[name] or 0) + (tonumber(count) or 0)
            end
        end
    end
    if ns.Tracker then Take(ns.Tracker.sessionLoot) end
    if ns.Fishing then Take(ns.Fishing.sessionCatch) end
    if ns.Gathering then Take(ns.Gathering.sessionItems) end
    return counts
end

local function Now()
    if type(GetTime) ~= "function" then return nil end
    local ok, now = pcall(GetTime)
    return ok and type(now) == "number" and now or nil
end

--- Where the most of `name` came from this session, or nil.
local function SourceOf(name)
    local from = ns.Tracker and ns.Tracker.sessionFrom and ns.Tracker.sessionFrom[name]
    if type(from) ~= "table" then return nil end
    local best, most
    for source, count in pairs(from) do
        if not most or count > most or (count == most and source < best) then
            best, most = source, count
        end
    end
    return best
end

--- The bar's words for a drop: its icon, its name in its colour, what one
--- is worth and where it came from.
function SlimBar.FlashText(name)
    local Util = ns.Util
    local parts = {}
    local id = Util.ItemIDOf and Util.ItemIDOf(name)
    local icon
    if id and C_Item and type(C_Item.GetItemIconByID) == "function" then
        local ok, texture = pcall(C_Item.GetItemIconByID, id)
        if ok and texture then icon = texture end
    end
    if icon then parts[#parts + 1] = ("|T%s:14:14:0:0|t"):format(tostring(icon)) end
    parts[#parts + 1] = Util.ColorItem and Util.ColorItem(name) or name
    local worth = ns.Value and ns.Value.WorthOf and ns.Value:WorthOf(name)
    if worth and worth > 0 and ns.Value.Coins then parts[#parts + 1] = ns.Value.Coins(worth) end
    local source = SourceOf(name)
    if source then parts[#parts + 1] = "|cff9b927c" .. L.Format("from %s", source) .. "|r" end
    return table.concat(parts, " ")
end

--- Look for a green or better drop since the last look. The first look only
--- takes note: that is where the counts start.
function SlimBar:NoteDrops()
    local counts = Counts()
    local was = self.seen
    self.seen = counts
    if not was then return end

    local best, bestQuality
    for name, count in pairs(counts) do
        if count > (was[name] or 0) then
            local quality = ns.TrackerFX and ns.TrackerFX.QualityOf and ns.TrackerFX.QualityOf(name) or 0
            if quality >= SlimBar.FLASH_QUALITY and (not bestQuality or quality > bestQuality) then
                best, bestQuality = name, quality
            end
        end
    end
    if not best then return end

    local now = Now()
    self.flash = { text = SlimBar.FlashText(best), untilAt = now and (now + SlimBar.FLASH) or nil }
    if now and C_Timer and type(C_Timer.After) == "function" then
        local flash = self.flash
        pcall(C_Timer.After, SlimBar.FLASH, function()
            if SlimBar.flash == flash then
                SlimBar.flash = nil
                SlimBar:Tick(true)
            end
        end)
    end
end

--- The drop showing on the bar now, or nil.
function SlimBar:Flashing()
    local flash = self.flash
    if not flash then return nil end
    local now = Now()
    if flash.untilAt and now and now >= flash.untilAt then
        self.flash = nil
        return nil
    end
    return flash.text
end

--------------------------------------------------------------------------------
-- Drawing
--------------------------------------------------------------------------------

--- The bar's words: a good drop while it shows, else the line.
function SlimBar:BarText()
    return self:Flashing() or self:Text()
end

--- How wide the panel must be for `text` on its title line, with the gems.
function SlimBar.WidthFor(text)
    local plain = ns.Util.StripColor(text):gsub("|T.-|t", "XXX")
    return 8 + 4 + Theme.TextWidth("normal", plain) + 8 + 6 + 18 + 4 + 18 + 6
end

--- Fold the panel to the bar: only the title line shows, with the bar's
--- words where the title was.
function SlimBar:Draw(ui)
    local frame = ui.frame
    if not frame then return end
    self:NoteDrops()

    local timerUI = ns.SessionTimerUI
    for _, part in ipairs({ ui.titleRow, ui.tabStrip, ui.toolbar, ui.rule, ui.moreLabel,
        ui.fadeTop, ui.fadeBottom, ui.grip, ui.sizeGrip, timerUI and timerUI.strip }) do
        if part then part:Hide() end
    end
    for _, line in ipairs(ui.lines or {}) do line:Hide() end
    for _, card in ipairs(ui.cards or {}) do card:Hide() end

    self:ReadNumbers()
    local text = self:BarText()
    ui.title:SetText(text)
    ui.header:SetHeight(SlimBar.HEIGHT)
    -- Only ever wider while the session runs, so the clock never makes it
    -- jump back and forth.
    self.wide = math.max(self.wide or 0, SlimBar.WidthFor(text))
    frame:SetWidth(self.wide)
    frame:SetHeight(SlimBar.HEIGHT)
    self.shape = "bar"
    self.shown = text
end

--- The list is open: the panel as it always is, with the bar's words on
--- its title line and, while only the mouse holds it open, how to keep it.
--- Called before the panel draws, so its width takes the words in.
function SlimBar:Open(ui)
    if not ui.frame then return end
    -- The list shows every drop; one made while it is open is not news on
    -- the bar once it folds.
    self.seen = Counts()
    self.flash = nil
    ui.header:SetHeight(ui.HEADER)
    for _, part in ipairs({ ui.titleRow, ui.grip, ui.sizeGrip }) do
        if part then part:Show() end
    end
    if not ui.folded then
        for _, part in ipairs({ ui.tabStrip, ui.toolbar }) do
            if part then part:Show() end
        end
        if ui.rule and not ui.glassBare then ui.rule:Show() end
    end
    self:ReadNumbers()
    local text = self:BarText()
    ui.title:SetText(text)
    ui.titleRow.left:SetText(self.pinned and "" or L["Click the bar to keep the list open."])
    self.shape = "open"
    self.shown = text
end

--- Full Panel again: its title and its second line as they were.
function SlimBar:Restore(ui)
    if not (ui and ui.frame) or not self.shape then return end
    ui.header:SetHeight(ui.HEADER)
    ui.title:SetText(L["Kills & Loot"])
    ui.titleRow.left:SetText("")
    for _, part in ipairs({ ui.titleRow, ui.grip, ui.sizeGrip }) do
        if part then part:Show() end
    end
    if not ui.folded then
        for _, part in ipairs({ ui.tabStrip, ui.toolbar }) do
            if part then part:Show() end
        end
        if ui.rule and not ui.glassBare then ui.rule:Show() end
    end
    ui.title:Show()
    self.shape = nil
    self.shown = nil
end

--- Once a second while shown: write the bar's words again when they
--- changed. Nothing else is drawn. `force` redraws the whole panel (a drop
--- leaving the bar).
function SlimBar:Tick(force)
    local ui = ns.TrackerUI
    if not (SlimBar.On() and ui and ui.frame and ui.frame:IsShown()) then return end
    if force then return ui:Refresh() end
    local text = self:BarText()
    if text == self.shown then return end
    if self.shape == "bar" then
        local needs = SlimBar.WidthFor(text)
        if needs > (self.wide or 0) then
            self.wide = needs
            ui.frame:SetWidth(needs)
        end
        ui.title:SetText(text)
        self.shown = text
    elseif self.shape == "open" then
        local width = tonumber(ui.frame:GetWidth()) or 0
        if SlimBar.WidthFor(text) > width then return ui:Refresh() end
        ui.title:SetText(text)
        self.shown = text
    end
end

--------------------------------------------------------------------------------
-- The mouse
--------------------------------------------------------------------------------

local function CursorOnTitleLine(frame)
    local ok, on = pcall(function()
        if not (GetCursorPosition and frame.GetTop and frame.GetEffectiveScale) then return true end
        local _, y = GetCursorPosition()
        local top, scale = frame:GetTop(), frame:GetEffectiveScale()
        if type(y) ~= "number" or type(top) ~= "number" or type(scale) ~= "number" or scale <= 0 then
            return true
        end
        return top - y / scale <= SlimBar.HEIGHT
    end)
    return not ok or on == true
end

--- A left click on the bar keeps the list open, or lets it fold again.
function SlimBar:Click()
    if not SlimBar.On() then return end
    self.pinned = not self.pinned or nil
    -- Let go: it folds as soon as the mouse is off.
    local ui = ns.TrackerUI
    if ui then ui:Refresh() end
end

--- The right-click menu: Sort's orders for the tab showing, then the Zone
--- Board while it is ticked.
function SlimBar:MenuLines()
    local ui = ns.TrackerUI
    local lines = ui and ui.SortLines and ui:SortLines() or {}
    if ns.ZoneBoard and ns.ZoneBoard.IsOn and ns.ZoneBoard.IsOn() and ns.ZoneBoardUI then
        lines[#lines + 1] = { text = L["Zone Board"], run = function() ns.ZoneBoardUI:Toggle() end }
    end
    return lines
end

function SlimBar:OpenMenu()
    if ns.RowMenu then ns.RowMenu:Open(self:MenuLines(), { title = L["Sort"] }) end
end

--- HookScript where the frame has it (the game's frames all do), else the
--- script wrapped by hand.
local function Hook(frame, script, fn)
    if type(frame.HookScript) == "function" then return frame:HookScript(script, fn) end
    local old = frame:GetScript(script)
    frame:SetScript(script, function(...)
        if old then old(...) end
        fn(...)
    end)
end

--- The panel's mouse: clicks on it, and a watcher that opens the list
--- while the mouse is on it. The watcher runs only while Slim Bar is on and
--- the panel shows.
function SlimBar:Watch(ui)
    local frame = ui and ui.frame
    if not frame then return end

    if not self.hooked then
        self.hooked = true
        Hook(frame, "OnMouseDown", function() SlimBar.dragged = nil end)
        Hook(frame, "OnDragStart", function() SlimBar.dragged = true end)
        Hook(frame, "OnMouseUp", function(f, button)
            if not SlimBar.On() or SlimBar.dragged then return end
            if button == "RightButton" then
                SlimBar:OpenMenu()
            elseif button == "LeftButton" or button == nil then
                if SlimBar:IsOpen() and not CursorOnTitleLine(f) then return end
                SlimBar:Click()
            end
        end)
    end

    local watch = self.watch
    if not watch then
        watch = CreateFrame("Frame", nil, frame)
        watch.look, watch.tick, watch.off = 0, 0, 0
        self.watch = watch
    end

    if not SlimBar.On() then
        watch:SetScript("OnUpdate", nil)
        return
    end
    watch:SetScript("OnUpdate", function(w, elapsed)
        elapsed = tonumber(elapsed) or 0
        w.tick = w.tick - elapsed
        if w.tick <= 0 then
            w.tick = SlimBar.TICK
            SlimBar:Tick()
        end
        w.look = w.look - elapsed
        if w.look > 0 then return end
        w.look = SlimBar.LOOK
        SlimBar:Look(SlimBar.LOOK)
    end)
end

--- One look for the mouse. On the panel, the list opens; off it for
--- CLOSE_WAIT, it folds back. Never while the panel is dragged or sized,
--- or while its right-click menu is open.
function SlimBar:Look(step)
    local ui = ns.TrackerUI
    if not (ui and ui.frame) then return end
    if ui.dragging or ui.sizing then return end
    local over = ui:MouseOnPanel()
    if over then
        self.offFor = 0
        if not self.hovered then
            self.hovered = true
            if not self.pinned then ui:Refresh() end
        end
        return
    end
    if not self.hovered then return end
    if ns.RowMenu and ns.RowMenu.IsShown and ns.RowMenu:IsShown() then return end
    self.offFor = (self.offFor or 0) + (step or SlimBar.LOOK)
    if self.offFor < SlimBar.CLOSE_WAIT then return end
    self.hovered = nil
    self.offFor = 0
    if not self.pinned then ui:Refresh() end
end
