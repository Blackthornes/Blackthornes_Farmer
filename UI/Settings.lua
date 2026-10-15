-- Blackthornes Farmer -- UI/Settings.lua
-- The settings window: every switch the addon has, in one place.
--
-- Built the way Tradeskills' Settings tab is (UI/SettingsPages.lua): pages
-- picked along the top, two columns of rows a page, a row being [label ..
-- control] on one line, and what it does in the row's tooltip or, with Show
-- descriptions ticked, underneath it. "Find a setting" searches every page.
--
-- Open it with /farm settings, right-click on the minimap button, the Settings
-- button in the search window, or from the game's own AddOns options list.
-- Every /farm command has a button or control here (a house rule).
--
-- Nothing here deletes anything. Wiping kill tallies, recorded loot, fishing,
-- gathering or map markers stays a typed two-word command, so a stray click
-- on this page can never cost data.

local _, ns = ...
local L = ns.L

local SettingsUI = ns.NewModule("SettingsUI")

local Theme = ns.Theme
local Widgets = ns.Widgets
local Util = ns.Util

local PADDING = 18
local HEADER = 36

local COLUMN_WIDTH = 310
local COLUMN_GAP = 18
-- Where the controls start: room for a label like "Search window size" in the
-- game's font, which runs wider than it looks.
local CONTROL_X = 170

-- Window sizes, in percent. Wide enough to matter on a 4K screen or a laptop,
-- narrow enough that neither end breaks the layout.
local SCALE_MIN = 70
local SCALE_MAX = 150
local SCALE_STEP = 10

local TITLE = "Blackthornes Farmer"

-- The pages along the top (UI/SettingsPages.lua), as Tradeskills' Settings
-- tab has them. Every setting kept its saved name; only its place moved.
local PAGES = {
    { key = "windows", text = L["WINDOWS"],
      tip = L["The minimap button, window sizes and places, effects and text size"] },
    { key = "tally", text = L["KILL TALLY"],
      tip = L["The kills and loot panel, what it says in chat, and your kills"] },
    { key = "loot", text = L["LOOT"],
      tip = L["Recording what drops and its export, fishing and gathering, and skinning"] },
    { key = "map", text = L["MAP & GOALS"],
      tip = L["Node markers, grinding camps, goals and the goal arrow"] },
    { key = "sharing", text = L["SHARING"],
      tip = L["Share kills, drop rates and gathering with your other account"] },
    { key = "advanced", text = L["ADVANCED"],
      tip = L["Debug output, the data loaded and the list of commands"] },
    { key = "about", text = L["ABOUT"],
      tip = L["How these addons are made, the version, the Discord and the other Blackthornes addons"] },
}

--------------------------------------------------------------------------------
-- Layout helpers
--------------------------------------------------------------------------------

--- Make room in a row for a second line of controls under its first, the
--- description moving down by `by`. Call it before anything changes the
--- row's description.
local function GrowRow(row, by)
    local top = row.compactHeight
    row.hint:ClearAllPoints()
    row.hint:SetPoint("TOPLEFT", 0, -(top + by))
    row.compactHeight = top + by
    row.fullHeight = row.fullHeight + by
    local described = ns.db and ns.db.settingsDescriptions == true
    row.shownHeight = described and row.fullHeight or row.compactHeight
    row:SetHeight(row.shownHeight)
end

--- A button's tooltip: what it does, in clear white on the dark tooltip.
local function Explain(button, title, text)
    button:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(title, Theme.Unpack("accent"))
        GameTooltip:AddLine(text, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    button:HookScript("OnLeave", function() GameTooltip:Hide() end)
end

--- A button on `row` that runs a /farm command, at `x` (CONTROL_X unless
--- given).
local function CommandButton(row, text, command, width, x)
    local button = Widgets.CreateButton(row, text, function()
        if type(command) == "function" then command() else ns.HandleSlash(command) end
    end, { width = width or 100, height = 20 })
    button:SetPoint("TOPLEFT", x or CONTROL_X, 0)
    return button
end

--- A row whose button runs a /farm command, so every command has a button
--- here (a house rule).
local function CommandRow(pages, page, column, label, description, buttonText, command)
    local row = pages:Row(page, column, label, description)
    return row, CommandButton(row, buttonText, command)
end

local function Percent(value)
    return ("%d%%"):format(value)
end

--------------------------------------------------------------------------------
-- Applying settings
--
-- Each of these is what one control does, kept apart from the control so the
-- tests can drive them and so a chat command could share them later.
--------------------------------------------------------------------------------

--- Saved spots are offsets in the window's own, scaled units, so a new size
--- would move it on screen. Changed from `from` percent to `to`, the keys
--- named are converted so the window's anchor stays where it is.
function SettingsUI.KeepSpot(keys, from, to)
    local db = ns.db
    if not (type(from) == "number" and type(to) == "number" and from > 0 and to > 0)
        or from == to then
        return
    end

    local ratio = from / to
    for _, key in ipairs(keys) do
        if type(db[key]) == "number" then db[key] = db[key] * ratio end
    end
end

--- `previous` is the size it had, when a player has just changed it; the
--- window then stays where it is on screen. Without it (at login) the saved
--- spot is already in the saved size's units.
function SettingsUI:ApplyWindowScale(previous)
    -- Converted even while the window is not built yet: it opens at the new size.
    if previous then SettingsUI.KeepSpot({ "x", "y" }, previous, ns.db.windowScale or 100) end

    local UI = ns.UI
    if UI and UI.frame then
        UI.frame:SetScale((ns.db.windowScale or 100) / 100)
        if previous and UI.RestorePosition then UI:RestorePosition() end

        -- Its columns are capped to what fits on screen at its size: drawn
        -- again, or a bigger window runs off the edge until the next search.
        if previous and UI.frame:IsShown() then
            if UI.tab == "rankings" and ns.RankingsUI then
                pcall(ns.RankingsUI.Render, ns.RankingsUI)
            elseif UI.Render then
                pcall(UI.Render, UI)
            end
        end
    end
end

--- `previous` is the size it had, when a player has just changed it; the
--- panel then stays where it is on screen. Without it (at login) the saved
--- spot is already in the saved size's units.
function SettingsUI:ApplyTrackerScale(previous)
    local TrackerUI = ns.TrackerUI
    if not TrackerUI then return end

    -- The tally panel is built lazily on some versions of it; building it
    -- early is harmless (it starts hidden) and means the size is right the
    -- first time it appears.
    local frame = TrackerUI.frame or (TrackerUI.Build and TrackerUI:Build())
    if frame then
        -- The saved size, kept on the screen (TrackerUI:DrawnPercent).
        local percent = TrackerUI.DrawnPercent and TrackerUI:DrawnPercent() or (ns.db.trackerScale or 100)
        if previous then
            SettingsUI.KeepSpot({ "trackerX", "trackerY", "trackerGroupX", "trackerGroupY" },
                previous, percent)
        end
        frame:SetScale(percent / 100)
        -- A new size can change whether it overlaps the group frames.
        if TrackerUI.Place then TrackerUI:Place() end
        -- The docked goals panel is as wide as this one is on screen.
        if TrackerUI.FollowGoals then TrackerUI:FollowGoals() end
    end
end

--- Show or put away the kill tally panel, exactly as /farm tracker does.
function SettingsUI:SetTrackerShown(shown)
    ns.db.trackerHidden = not shown

    local TrackerUI = ns.TrackerUI
    if not TrackerUI then return end

    if TrackerUI.Refresh then
        -- The docked panel decides for itself whether it has anything to show.
        TrackerUI:Refresh()
    elseif not shown then
        TrackerUI:Hide()
    elseif ns.Tracker and ns.Tracker.current and TrackerUI.ShowMob then
        TrackerUI:ShowMob(ns.Tracker.current)
    end
end

--- Pause or resume loot recording, and remember the choice across sessions.
function SettingsUI:SetRecording(on)
    ns.db.harvestPaused = not on

    if ns.Harvest:Capabilities().usable then
        ns.Harvest.enabled = on and true or false
    end
end

--- Put the search window and the tally panel back where, and how big, they
--- started.
function SettingsUI:ResetPositions()
    local defaults = ns.DEFAULTS
    local db = ns.db

    for _, key in ipairs({ "point", "relativePoint", "x", "y",
        "trackerPoint", "trackerX", "trackerY" }) do
        db[key] = defaults[key]
    end

    -- This window too: it goes back to the middle of the screen.
    db.settingsPoint = nil
    db.settingsRelativePoint = nil
    db.settingsX = nil
    db.settingsY = nil

    -- Not in the defaults: the tally anchors to its own point when this is
    -- absent, which is where it started.
    db.trackerRelativePoint = nil

    -- And its size, back to where it started.
    db.trackerWidth = nil
    db.trackerHeight = nil

    -- A spot picked for groups goes too; it goes back beside the group frames.
    db.trackerGroupX = nil
    db.trackerGroupY = nil

    if ns.UI and ns.UI.frame then ns.UI:RestorePosition() end

    if ns.TrackerUI and ns.TrackerUI.frame and ns.TrackerUI.RestorePosition then
        ns.TrackerUI:RestorePosition()
        if ns.TrackerUI.Place then ns.TrackerUI:Place() end
        if ns.TrackerUI.Refresh then ns.TrackerUI:Refresh() end
    end

    -- The goals panel goes back under the kills panel.
    if ns.GoalsUI and ns.GoalsUI.frame then ns.GoalsUI:Dock() end

    -- The goal arrow goes back to the top middle.
    if ns.ArrowUI then ns.ArrowUI:ResetPosition() end

    self:RestorePosition()
end

--------------------------------------------------------------------------------
-- Construction
--------------------------------------------------------------------------------

function SettingsUI:Build()
    if self.frame then return self.frame end

    local frame = CreateFrame("Frame", "BlackthornesFarmerSettings", UIParent)
    frame:SetSize(COLUMN_WIDTH * 2 + COLUMN_GAP + PADDING * 2, 600)
    frame:SetFrameStrata("DIALOG")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")

    Theme.Fill(frame, "window")
    -- The house frame (UI/Titanforged.lua): the gold rim and corner gems,
    -- the name on a plate across the top and a red close gem.
    if ns.Titanforged then
        self.trim = ns.Titanforged:Dress(frame, {
            title = L["Farmer Settings"],
            close = function() SettingsUI:Hide() end,
        })
        local left, right, top, bottom = ns.Titanforged.Reach(self.trim)
        if frame.SetClampRectInsets then
            pcall(frame.SetClampRectInsets, frame, -left, right, top, -bottom)
        end
    else
        Theme.Border(frame, "borderLit")
    end
    Theme.Halo(frame, 8, 0.10)

    frame:SetScript("OnDragStart", function(self)
        -- Land an opening still running, or it would pull the window back.
        ns.Motion:Stop(self, "open", true)
        self:StartMoving()
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SettingsUI:SavePosition()
    end)

    -- Escape closes it, like the game's own windows (see UI/Main.lua for
    -- why the keyboard is not taken instead).
    if type(UISpecialFrames) == "table" then
        table.insert(UISpecialFrames, "BlackthornesFarmerSettings")
    end

    self.frame = frame
    self.controls = {}

    self:BuildHeader()

    self.pages = ns.SettingsPages.New(frame, {
        pages = PAGES,
        top = HEADER + 4,
        bottom = 48,
        padding = PADDING,
        columnWidth = COLUMN_WIDTH,
        columnGap = COLUMN_GAP,
        controlX = CONTROL_X,
        db = function() return ns.db end,
    })
    self:BuildWindowsPage()
    self:BuildTallyPage()
    self:BuildLootPage()
    self:BuildMapPage()
    self:BuildSharingPage()
    self:BuildAdvancedPage()
    self:BuildAboutPage()
    self.pages:Fit()

    -- The house size grip under the bottom right corner
    -- (Widgets.CreateSizeGrip), saved as `settingsScale`.
    local below = 0
    if self.trim and ns.Titanforged and ns.Titanforged.Reach then
        local _, _, _, bottom = ns.Titanforged.Reach(self.trim)
        if type(bottom) == "number" then below = bottom end
    end
    Widgets.ApplySize(frame, ns.db and ns.db.settingsScale)
    self.sizeGrip = Widgets.CreateSizeGrip(frame, {
        below = below,
        get = function() return ns.db and ns.db.settingsScale end,
        save = function(percent) if ns.db then ns.db.settingsScale = percent end end,
        done = function() SettingsUI:SavePosition() end,
    })

    local footer = Theme.CreateLabel(frame, "tiny", "dim")
    footer:SetPoint("BOTTOMLEFT", PADDING, 10)
    footer:SetPoint("BOTTOMRIGHT", -PADDING, 10)
    -- Two lines if it needs them, rather than cut off.
    footer:SetHeight(26)
    footer:SetWordWrap(true)
    footer:SetJustifyV("BOTTOM")
    footer:SetText(L["Changes save as you make them. Nothing here can delete your data. Clearing tallies or recorded loot takes a typed command."])
    self.footer = footer

    frame:Hide()
    return frame
end

function SettingsUI:BuildHeader()
    local frame = self.frame

    -- The window's name is on the plate across the top edge and the close
    -- gem on its corner (UI/Titanforged.lua), so the header keeps only the
    -- version, under the gem, over a gold rule fading from the left. Inside
    -- the rim, which a header out to the edge would cover.
    local header = CreateFrame("Frame", nil, frame)
    header:SetPoint("TOPLEFT", 8, -8)
    header:SetPoint("TOPRIGHT", -8, -8)
    header:SetHeight(HEADER - 8)

    local version = Theme.CreateLabel(header, "tiny", "dim", "RIGHT")
    version:SetPoint("BOTTOMRIGHT", -PADDING + 8, 6)
    version:SetText(ns.VersionLabel())

    local rule = header:CreateTexture(nil, "ARTWORK")
    rule:SetPoint("BOTTOMLEFT")
    rule:SetPoint("BOTTOMRIGHT")
    rule:SetHeight(1)
    Theme.SetGradientAlpha(rule, "HORIZONTAL", "accent", 0.6, 0.05)
end

--- Windows: how the addon looks and where things sit.
function SettingsUI:BuildWindowsPage()
    local controls = self.controls
    local pages = self.pages

    pages:Section("windows", 1, L["WINDOWS"])

    local minimapRow = pages:Row("windows", 1, L["Minimap button"],
        L["Left-click it to search, right-click for this page. Drag it round the edge to move it. Same as /farm minimap."])

    controls.minimap = Widgets.CreateCheckbox(minimapRow, L["Show it"], function(checked)
        ns.db.minimapHidden = not checked
        if ns.UI then ns.UI:ApplyMinimapVisibility() end
    end, true)
    controls.minimap:SetPoint("TOPLEFT", CONTROL_X, -2)

    local windowScaleRow = pages:Row("windows", 1, L["Search window size"],
        L["Bigger for a high-resolution screen, smaller for a laptop. You can also drag the gold corner under its bottom right, and right-click it for the normal size."])

    -- Any percent the window's grip can drag to, one dragged to shown as it is.
    controls.windowScale = Widgets.CreateStepper(windowScaleRow, {
        min = Widgets.SIZE_MIN or SCALE_MIN, max = Widgets.SIZE_MAX or SCALE_MAX,
        step = SCALE_STEP, value = 100, exact = true,
        format = Percent,
        onChange = function(value)
            local previous = ns.db.windowScale or 100
            ns.db.windowScale = value
            SettingsUI:ApplyWindowScale(previous)
        end,
    })
    controls.windowScale:SetPoint("TOPLEFT", CONTROL_X, 0)

    -- The kills and loot panel's size, which its gold corner grip and
    -- /farm tracker size set too (the owner asked 2026-10-07): any percent
    -- from 50 to 150 on the stepper, one dragged to shown as it is, and
    -- Small, Normal and Large under it, the one in use lit green.
    local TrackerUI = ns.TrackerUI
    local trackerScaleRow = pages:Row("windows", 1, L["Kill tally size"],
        L["Sizes the kills and loot panel on its own. You can also drag the gold corner beside its bottom right, and right-click it for Normal. Same as /farm tracker size."])

    controls.trackerScale = Widgets.CreateStepper(trackerScaleRow, {
        min = TrackerUI and TrackerUI.SCALE_MIN or SCALE_MIN,
        max = TrackerUI and TrackerUI.SCALE_MAX or SCALE_MAX,
        step = SCALE_STEP, value = 100, exact = true,
        format = Percent,
        onChange = function(value)
            if TrackerUI and TrackerUI.SetScalePercent then
                TrackerUI:SetScalePercent(value)
            else
                local previous = ns.db.trackerScale or 100
                ns.db.trackerScale = value
                SettingsUI:ApplyTrackerScale(previous)
            end
        end,
    })
    controls.trackerScale:SetPoint("TOPLEFT", CONTROL_X, 0)

    -- The three named sizes, in a line under the stepper, ending where it
    -- ends. The row grows to fit them over its description.
    controls.trackerSizes = {}
    local after
    for index = #(TrackerUI and TrackerUI.SIZES or {}), 1, -1 do
        local size = TrackerUI.SIZES[index]
        local button = Widgets.CreateButton(trackerScaleRow, size.text, function()
            ns.HandleSlash("tracker size " .. size.key)
        end, { width = 44, height = 18 })
        if after then
            button:SetPoint("RIGHT", after, "LEFT", -4, 0)
        else
            button:SetPoint("TOPRIGHT", controls.trackerScale, "BOTTOMRIGHT", 0, -4)
        end
        Explain(button, L.Format("%s kill tally", size.text),
            L.Format("Draws the kills and loot panel at %d%%, text and all. Same as /farm tracker size %s.",
                size.percent, size.key))
        button.percent = size.percent
        controls.trackerSizes[index] = button
        after = button
    end
    if after then GrowRow(trackerScaleRow, 24) end

    local positionRow = pages:Row("windows", 1, L["Window positions"],
        L["Moves every Farmer window back to where it started, if one ends up off screen."])

    local reset = Widgets.CreateButton(positionRow, L["Put them back"], function()
        SettingsUI:ResetPositions()
        ns.Print(L["windows moved back to where they started."])
    end, { width = 110, height = 20 })
    reset:SetPoint("TOPLEFT", CONTROL_X, 0)
    controls.resetPositions = reset

    pages:Section("windows", 2, L["LOOK"])

    -- Every window and both panels follow it, so it sits with the windows
    -- rather than under the kill tally. The saved key keeps its old name.
    local effectsRow = pages:Row("windows", 2, L["Window effects"],
        L["Full: windows fade up and glow, and loot floats off the kill panel. Subtle: shorter fades, and nothing floats. Off: no movement at all. Same as /farm effects."])

    local FX = ns.TrackerFX
    controls.effects = Widgets.CreateStepper(effectsRow, {
        min = 1, max = #FX.LEVELS, step = 1, value = #FX.LEVELS,
        format = function(index) return FX.LEVEL_NAMES[FX.LEVELS[index]] end,
        onChange = function(index) FX:SetLevel(FX.LEVELS[index]) end,
    })
    controls.effects:SetPoint("TOPLEFT", CONTROL_X, 0)

    -- Bigger letters in the same windows, as Tradeskills has. Every size
    -- is read as text is drawn, so it waits for /reload.
    local textRow = pages:Row("windows", 2, L["Text size"],
        L["Large and Larger make all of Farmer's text a little bigger. Takes effect after /reload."])
    controls.textSize = ns.SettingsPages.TextSizeControl(textRow, CONTROL_X, function() return ns.db end)

    -- Asked 2026-10-10: the game's own look for players who would rather
    -- the windows matched the rest of their screen. Read at login, so it
    -- waits for /reload as Text size does. See UI/BlizzardLook.lua.
    local styleRow = pages:Row("windows", 2, L["Window style"],
        L["Titanforged is the house look, with a gold rim and glowing edges. Blizzard uses the game's own frames, red buttons, tabs and tick boxes. Takes effect after /reload."])
    controls.windowStyle = SettingsUI:WindowStyleControl(styleRow)

    pages:Section("windows", 2, L["OPEN"])

    local _, searchButton = CommandRow(pages, "windows", 2, L["Search window"],
        L["Search for something to farm and see where it drops. Same as /farm on its own, or /farm and what you are after."], L["Open it"], function()
            -- /farm on its own toggles the window, so with it already open
            -- this closed it. It opens it, on the Search tab.
            ns.UI:Show()
            ns.UI:ShowTab("search")
        end)
    controls.openSearch = searchButton

    local _, rankingsButton = CommandRow(pages, "windows", 2, L["Rankings"],
        L["Mobs ranked by what a kill is worth. Same as /farm rankings."], L["Open it"], "rankings")
    controls.rankings = rankingsButton

    -- The owner, 2026-10-14: Rankings without the mobs found only in dungeons.
    local outsideRow = pages:Row("windows", 2, L["Outside dungeons only"],
        L["Rankings leave out mobs you found only in dungeons and raids, and so do the rank-up pop-up and the top 15 after an auction scan. The same tick box is on the Rankings tab. Same as /farm rankings outside."])
    controls.rankingsOutside = Widgets.CreateCheckbox(outsideRow, L["Leave them out"], function(checked)
        ns.Rankings:SetOutsideOnly(checked)
    end, false)
    controls.rankingsOutside:SetPoint("TOPLEFT", CONTROL_X, -2)

    local _, statsButton = CommandRow(pages, "windows", 2, L["Stats"],
        L["Your farming in charts: gold an hour by session, where it came from, your best mobs, luck, the days you farmed and your levels. Same as /farm charts."], L["Open it"], "charts")
    controls.statsTab = statsButton
end

-- The window styles in the order the stepper steps through them.
local WINDOW_STYLES = { "titanforged", "blizzard" }
local WINDOW_STYLE_NAMES = { titanforged = "Titanforged", blizzard = "Blizzard" }

--- The Window style row's control: a stepper between Titanforged and
--- Blizzard (Farmer has no dropdown, and Text size beside it is a stepper
--- too), with Reload under it while the pick differs from what is
--- drawn. :Sync() reads the saved pick back.
function SettingsUI:WindowStyleControl(row)
    local Look = ns.BlizzardLook
    local function Drawn() return Look and Look.Style() or "titanforged" end

    local reload
    local stepper = Widgets.CreateStepper(row, {
        min = 1, max = #WINDOW_STYLES, step = 1,
        format = function(value) return WINDOW_STYLE_NAMES[WINDOW_STYLES[value]] end,
        onChange = function(value)
            ns.db.windowStyle = WINDOW_STYLES[value]
            reload:SetShown(WINDOW_STYLES[value] ~= Drawn())
        end,
    })
    ns.SettingsPages.FitStepper(stepper, WINDOW_STYLE_NAMES)
    stepper:SetPoint("TOPLEFT", CONTROL_X, -2)

    -- ReloadUI is allowed from a click, and saves everything first.
    reload = Widgets.CreateButton(row, L["Reload"], function()
        if ReloadUI then ReloadUI() end
    end, { width = 60, height = 20 })
    ns.SettingsPages.ReloadUnder(row, stepper, reload)
    Explain(reload, L["Reload"], L["Reload the interface so the new window style shows (/reload)."])
    reload:Hide()
    stepper.reload = reload

    function stepper:Sync()
        local wanted = Look and Look.Wanted() or "titanforged"
        local index = 1
        for i, key in ipairs(WINDOW_STYLES) do
            if key == wanted then index = i end
        end
        self:SetValue(index, true)
        reload:SetShown(wanted ~= Drawn())
    end

    return stepper
end

--- Kill tally: the kills and loot panel and what it says.
function SettingsUI:BuildTallyPage()
    local controls = self.controls
    local pages = self.pages

    pages:Section("tally", 1, L["KILL TALLY"])

    local trackerRow = pages:Row("tally", 1, L["Tally panel"],
        L["Shows what you have killed and what dropped. Same as /farm tracker."])

    controls.tracker = Widgets.CreateCheckbox(trackerRow, L["Show it"], function(checked)
        SettingsUI:SetTrackerShown(checked)
    end, true)
    controls.tracker:SetPoint("TOPLEFT", CONTROL_X, -2)

    -- Only what the panel shows: every tally stays, so it is no reset.
    local clearRow = pages:Row("tally", 1, L["Clear panel"],
        L["Click twice to empty the panel and start a new run. Your kill tallies, drop rates and Rankings are kept. Same as /farm tracker clear."])

    controls.clearPanel = ns.TrackerUI.ClearButton(clearRow, 64, 20)
    controls.clearPanel:SetPoint("TOPLEFT", CONTROL_X, 0)

    -- Off by default: the panel starts empty at every login and /reload.
    local keepRow = pages:Row("tally", 1, L["Between sessions"],
        L["The panel starts empty each time you log in or reload. Tick this to keep each character's kills and loot until you clear it. Your kill tallies, drop rates and Rankings are always kept. Same as /farm tracker keep."])

    controls.keepPanel = Widgets.CreateCheckbox(keepRow, L["Keep it"], function(checked)
        ns.db.keepPanel = checked
    end, false)
    controls.keepPanel:SetPoint("TOPLEFT", CONTROL_X, -2)

    local groupRow = pages:Row("tally", 1, L["In a group"],
        L["Moves the panel out of the way of the party and raid frames. Drag it while you're in a group to pick its spot. Same as /farm tracker group."])

    controls.dodgeGroup = Widgets.CreateCheckbox(groupRow, L["Move aside"], function(checked)
        ns.TrackerUI:SetDodgeGroup(checked)
    end, true)
    controls.dodgeGroup:SetPoint("TOPLEFT", CONTROL_X, -2)

    local reportRow = pages:Row("tally", 1, L["Chat report"],
        L["One line per kill in your own chat window. Nobody else can see it. Same as /farm report."])

    controls.report = Widgets.CreateCheckbox(reportRow, L["Report kills"], function(checked)
        ns.db.trackerReport = checked
    end, false)
    controls.report:SetPoint("TOPLEFT", CONTROL_X, -2)

    local celebrateRow = pages:Row("tally", 1, L["Milestone fanfare"],
        L["A sound and a cheer when a mob's 20th kill, a fishing spot's 20th cast or a node's 20th gather unlocks its rates. Same as /farm celebrate."])

    controls.celebrate = Widgets.CreateCheckbox(celebrateRow, L["Play it"], function(checked)
        ns.db.trackerCelebrate = checked
    end, true)
    controls.celebrate:SetPoint("TOPLEFT", CONTROL_X, -2)

    local rareRow = pages:Row("tally", 1, L["Rare drop sound"],
        L["A chime when something green or better drops. Only you hear it. Same as /farm raresound."])

    controls.rareSound = Widgets.CreateCheckbox(rareRow, L["Play it"], function(checked)
        ns.db.trackerRareSound = checked
    end, true)
    controls.rareSound:SetPoint("TOPLEFT", CONTROL_X, -2)

    local rankUpRow = pages:Row("tally", 1, L["Rank-up pop-up"],
        L["When a kill moves a mob onto your top 15 by worth per kill, or up it, the list pops up beside the panel for a few seconds to show the move. It never shows during a fight. Same as /farm rankup."])

    controls.rankUp = Widgets.CreateCheckbox(rankUpRow, L["Show it"], function(checked)
        ns.db.rankUpPopup = checked
        if not checked and ns.RankUpUI then ns.RankUpUI:Hide() end
    end, true)
    controls.rankUp:SetPoint("TOPLEFT", CONTROL_X, -2)

    local rankUpSoundRow = pages:Row("tally", 1, L["Rank-up sound"],
        L["A short chime as the mob lands in its new place. Only you hear it, and never on top of the milestone fanfare. Same as /farm rankup sound."])

    controls.rankUpSound = Widgets.CreateCheckbox(rankUpSoundRow, L["Play it"], function(checked)
        ns.db.rankUpSound = checked
    end, true)
    controls.rankUpSound:SetPoint("TOPLEFT", CONTROL_X, -2)

    local bestRow = pages:Row("tally", 1, L["Best session cheer"],
        L["A line in chat and a chime when a session's gold an hour beats every one before it, once a session. Same as /farm charts cheer."])

    controls.statsBestCheer = Widgets.CreateCheckbox(bestRow, L["Play it"], function(checked)
        ns.db.statsBestCheer = checked
    end, true)
    controls.statsBestCheer:SetPoint("TOPLEFT", CONTROL_X, -2)

    local voiceRow = pages:Row("tally", 1, L["Voice lines"],
        L["A goblin cheers a blue or better drop, and a peon says \"Work complete!\" when a goal is done. The game's own voices, a few minutes apart. Same as /farm voice."])

    controls.voice = Widgets.CreateCheckbox(voiceRow, L["Say them"], function(checked)
        ns.db.trackerVoice = checked
    end, true)
    controls.voice:SetPoint("TOPLEFT", CONTROL_X, -2)

    -- The mob you last looted, as the commands read it with no name.
    pages:Section("tally", 2, L["YOUR LAST MOB"])

    local _, killsButton = CommandRow(pages, "tally", 2, L["Kills and drops"],
        L["Lists in chat how often you have killed the mob you last looted, and its drop rates. Same as /farm kills, or /farm kills and a mob's name."], L["List them"], "kills")
    controls.kills = killsButton

    local _, lootButton = CommandRow(pages, "tally", 2, L["Loot table"],
        L["Opens the full loot table of the mob you last looted. Same as /farm loot, or /farm loot and a mob's name."], L["Open it"], "loot")
    controls.lootTable = lootButton

    local _, valueButton = CommandRow(pages, "tally", 2, L["Worth per kill"],
        L["What a kill of the mob you last looted is worth, from Tradeskills' prices. Same as /farm value, or /farm value and a mob's name."], L["Work it out"], "value")
    controls.value = valueButton

    pages:Section("tally", 2, L["YOUR TOP 15"])

    local _, topButton = CommandRow(pages, "tally", 2, L["Your top 15"],
        L["Shows your best mobs by worth per kill, from your own kills, the way the rank-up pop-up does. Same as /farm rankup show."], L["Show it"], "rankup show")
    controls.rankUpShow = topButton

    -- After an auction scan (Logic/TopFarm.lua, the owner asked 2026-10-14).
    local topFarmRow = pages:Row("tally", 2, L["After an auction scan"],
        L["When new auction prices change the order of your top 15, it pops up and shuffles to the new order. If a different mob takes first place and is worth at least 10% more a kill, it's called out as your new top farm. Only mobs you've killed 20 times count. It plays the rank-up sound if that's on. Same as /farm topfarm."])
    controls.topFarm = Widgets.CreateCheckbox(topFarmRow, L["Show it"], function(checked)
        ns.TopFarm:SetOn(checked)
    end, true)
    controls.topFarm:SetPoint("TOPLEFT", CONTROL_X, -2)
    controls.topFarmTry = CommandButton(topFarmRow, L["Try it"], "topfarm test", 60, CONTROL_X + 70)

    -- The XP bar (UI/XPBar.lua, the owner asked 2026-10-13).
    pages:Section("tally", 2, L["XP BAR"])

    local xpRow = pages:Row("tally", 2, L["XP bar"],
        L["A bar that shows your level, what finished quests and rested XP are worth, and when you reach the next level at your pace. Hover it to see how to finish the level, and drag it to move it. Same as /farm xpbar."])
    controls.xpBar = Widgets.CreateCheckbox(xpRow, L["Show it"], function(checked)
        ns.XPBarUI:SetOn(checked)
    end, true)
    controls.xpBar:SetPoint("TOPLEFT", CONTROL_X, -2)

    local cheerRow = pages:Row("tally", 2, L["Level-up cheer"],
        L["When you level up, a card shows how long the level took. Every tenth level gets a bigger one. Same as /farm xpbar cheer."])
    controls.xpBarCheer = Widgets.CreateCheckbox(cheerRow, L["Show it"], function(checked)
        ns.db.xpBarCheer = checked
    end, true)
    controls.xpBarCheer:SetPoint("TOPLEFT", CONTROL_X, -2)
    controls.xpBarTry = CommandButton(cheerRow, L["Try it"], "xpbar try", 60, CONTROL_X + 70)

    local chimeRow = pages:Row("tally", 2, L["Chime every tenth"],
        L["A soft chime as the bar crosses each tenth of the level. Same as /farm xpbar chime."])
    controls.xpBarChime = Widgets.CreateCheckbox(chimeRow, L["Play it"], function(checked)
        ns.db.xpBarChime = checked
    end, true)
    controls.xpBarChime:SetPoint("TOPLEFT", CONTROL_X, -2)

    local gameRow = pages:Row("tally", 2, L["Game's XP bar"],
        L["Makes the game's own XP bar, and a reputation bar beside it, see-through while yours shows. Untick it to bring them back as they were. Same as /farm xpbar game."])
    controls.xpBarHideGame = Widgets.CreateCheckbox(gameRow, L["Hide it"], function(checked)
        ns.XPBarUI:SetHideGame(checked)
    end, false)
    controls.xpBarHideGame:SetPoint("TOPLEFT", CONTROL_X, -2)

    local _, resetButton = CommandRow(pages, "tally", 2, L["XP bar place"],
        L["Puts the XP bar back at the top of the screen, at its normal size. Same as /farm xpbar reset."], L["Put it back"], "xpbar reset")
    controls.xpBarReset = resetButton
end

--- Loot: recording what drops, its export, fishing and gathering.
function SettingsUI:BuildLootPage()
    local controls = self.controls
    local pages = self.pages

    pages:Section("loot", 1, L["LOOT RECORDING"])

    local recordRow = pages:Row("loot", 1, L["Record what drops"],
        L["Counts what every corpse held, so drop rates come from Forever itself. It all stays on this computer. Same as /farm harvest on and off."])

    controls.record = Widgets.CreateCheckbox(recordRow, L["Recording"], function(checked)
        SettingsUI:SetRecording(checked)
    end, true)
    controls.record:SetPoint("TOPLEFT", CONTROL_X, -2)

    self.recordRow = recordRow

    -- How much is recorded, and the button that hands it back.
    local block = CreateFrame("Frame", nil, pages.pages.loot.content)
    block:SetSize(COLUMN_WIDTH, 44)
    block.fixedHeight = 44
    pages:Place("loot", 1, block, -4)

    local summary = Theme.CreateLabel(block, "small", "text")
    summary:SetPoint("TOPLEFT", 0, 0)
    summary:SetWidth(COLUMN_WIDTH)
    self.harvestSummary = summary

    local export = Widgets.CreateButton(block, L["Export"], function()
        ns.UI:ShowExport(ns.Harvest:ExportAll(), L["Export: everything you looted"])
    end, { width = 80, height = 20 })
    export:SetPoint("TOPLEFT", 0, -22)
    controls.export = export

    -- Kept to the column beside the button, on two lines if the font needs
    -- them: on one it ran past the window's right edge.
    local exportHint = Theme.CreateLabel(block, "tiny", "dim")
    exportHint:SetPoint("LEFT", export, "RIGHT", 8, 0)
    exportHint:SetWidth(COLUMN_WIDTH - export:GetWidth() - 8)
    exportHint:SetWordWrap(true)
    exportHint:SetText(L["Your recorded loot, as a data file. Same as /farm export."])
    self.exportHint = exportHint
    pages:Searchable("loot", block, L["export recorded loot data file"])

    local _, csvButton = CommandRow(pages, "loot", 1, L["Spreadsheet (CSV)"],
        L["Your loot, kills, gathering and fishing counts as CSV, one sheet each, to paste into Notepad or a spreadsheet. It only holds counts. Same as /farm export csv."],
        L["Export"], "export csv")
    controls.exportCsv = csvButton

    local _, harvestButton = CommandRow(pages, "loot", 1, L["What you recorded"],
        L["Lists in chat the items you have looted most, and from how many corpses. Same as /farm harvest."], L["List it"], "harvest")
    controls.harvest = harvestButton

    local _, lootCheckButton = CommandRow(pages, "loot", 1, L["Loot check"],
        L["Sets up a check for the next corpse you loot. It lists in chat what the game lets Farmer read there, which helps when a dungeon records nothing. It only reads. Same as /farm harvest check."],
        L["Ready"], "harvest check")
    controls.harvestCheck = lootCheckButton

    -- Without Tradeskills (the owner asked 2026-10-12).
    pages:Section("loot", 1, L["PRICES"])

    local otherRow = pages:Row("loot", 1, L["TSM and Auctionator"],
        L["When Blackthornes Tradeskills isn't loaded, Farmer prices drops with TradeSkillMaster's or Auctionator's auction prices, if either is loaded. Tradeskills always comes first when it is."])

    controls.otherPriceAddons = Widgets.CreateCheckbox(otherRow, L["Use them"], function(checked)
        ns.Value:SetUsesOtherAddons(checked)
    end, true)
    controls.otherPriceAddons:SetPoint("TOPLEFT", CONTROL_X, -2)

    -- How often green gear and better drops, by mob level (2026-10-13).
    pages:Section("loot", 1, L["WORLD DROPS"])

    local worldRow = pages:Row("loot", 1, L["World drops"],
        L["How often a kill drops green gear or better, by the mob's level, from the kills Farmer has recorded. It shows under the open mob in the kills panel, on a mob's tooltip, on Rankings and when you search for greens. Same as /farm worlddrops on or off."])
    controls.worldDrops = Widgets.CreateCheckbox(worldRow, L["Show them"], function(checked)
        ns.WorldDrops:SetEnabled(checked)
    end, true)
    controls.worldDrops:SetPoint("TOPLEFT", CONTROL_X, -2)

    local _, worldButton = CommandRow(pages, "loot", 1, L["Chances by level"],
        L["Lists in chat the chance of green, blue, purple and orange gear for each band of mob levels. Same as /farm worlddrops."],
        L["List them"], "worlddrops")
    controls.worldDropsList = worldButton

    pages:Section("loot", 2, L["FISHING AND GATHERING"])

    local fishingRow = pages:Row("loot", 2, L["Fishing"],
        L["Lists in chat what you have caught in this zone, or everywhere. Same as /farm fishing and /farm fishing all."])
    controls.fishing = CommandButton(fishingRow, L["Here"], "fishing", 50)
    controls.fishingAll = CommandButton(fishingRow, L["Everywhere"], "fishing all", 82, CONTROL_X + 56)

    local gatheringRow = pages:Row("loot", 2, L["Gathering"],
        L["Lists in chat the herbs and ore you have gathered in this zone, or everywhere. Same as /farm gathering and /farm gathering all."])
    controls.gathering = CommandButton(gatheringRow, L["Here"], "gathering", 50)
    controls.gatheringAll = CommandButton(gatheringRow, L["Everywhere"], "gathering all", 82, CONTROL_X + 56)

    local _, checkButton = CommandRow(pages, "loot", 2, L["Odd gathers"],
        L["Lists in chat any gathers that look like they were counted wrong, to help track down a problem. It only reads. Same as /farm gathering check."], L["Check"], "gathering check")
    controls.gatheringCheck = checkButton

    -- Drops only (a player asked, the owner agreed 2026-10-11).
    pages:Section("loot", 2, L["SKINNING"])

    local skinningRow = pages:Row("loot", 2, L["Hide skinning"],
        L["When ticked, Farmer shows only drops. Skinning spots stay out of search, Rankings and Grind, and leather, hides and scales stay out of a mob's drops and what a kill is worth. Untick it to see skinning. Nothing you recorded is lost. Same as /farm skinning."])

    controls.hideSkinning = Widgets.CreateCheckbox(skinningRow, L["Hide it"], function(checked)
        ns.DB:SetShowSkinning(not checked)
    end, true)
    controls.hideSkinning:SetPoint("TOPLEFT", CONTROL_X, -2)

    -- The hide list (the owner asked 2026-10-11 for a blacklist).
    local _, hiddenButton = CommandRow(pages, "loot", 2, L["Hidden"],
        L["Mobs, nodes and items you hid. Right-click one in the search, Rankings, Grind or the kills panel to hide it. The list has a Show again button for each. Same as /farm hidden, /farm hide and /farm unhide."], L["Show list"], "hidden")
    controls.hidden = hiddenButton

    local trashRow = pages:Row("loot", 2, L["Trash can when full"],
        L["When your bags are full, a small gold can sits on the item worth the least. It's never a goal's item, a quest item or gear you could wear. Click it to pick the item up, then drop it outside your bags, and the game asks before anything is destroyed. With Blackthornes Butler loaded, Butler's can shows instead. Same as /farm trash."])
    controls.trashCan = Widgets.CreateCheckbox(trashRow, L["Show it"], function(checked)
        ns.Trash:SetEnabled(checked)
    end, true)
    controls.trashCan:SetPoint("TOPLEFT", CONTROL_X, -2)

    local openRow = pages:Row("loot", 2, L["Clams and sacks"],
        L["A small note shows each time you open a clam, sack or lockbox, with how many you've opened. Once you've opened 20, it shows what one is worth. Same as /farm opennote."])
    controls.openNote = Widgets.CreateCheckbox(openRow, L["Show a note"], function(checked)
        ns.OpenNote:SetEnabled(checked)
    end, true)
    controls.openNote:SetPoint("TOPLEFT", CONTROL_X, -2)
    local bagsFullRow = pages:Row("loot", 2, L["Bags full notice"],
        L["A short notice on screen when your bags fill up. It shows once each time they fill, not on every loot, and waits until a fight is over. Same as /farm bagsfull."])
    controls.bagsFull = Widgets.CreateCheckbox(bagsFullRow, L["Show it"], function(checked)
        ns.BagsFull:SetEnabled(checked)
    end, true)
    controls.bagsFull:SetPoint("TOPLEFT", CONTROL_X, -2)
    controls.bagsFullTry = CommandButton(bagsFullRow, L["Try it"], "bagsfull test", 60, CONTROL_X + 70)
    local openButtonRow = pages:Row("loot", 2, L["Open button"],
        L["A small button on the Kills & Loot panel opens your clams, sacks and lockboxes, one a click. It leaves alone anything a goal, quest or craft needs, anything Butler keeps and locked lockboxes. Test it checks whether the game lets Farmer open them by itself. Same as /farm openbutton."])
    controls.openButton = Widgets.CreateCheckbox(openButtonRow, L["Show it"], function(checked)
        ns.OpenButton:SetEnabled(checked)
    end, true)
    controls.openButton:SetPoint("TOPLEFT", CONTROL_X, -2)
    controls.openTest = CommandButton(openButtonRow, L["Test it"], "openbutton test", 60, CONTROL_X + 70)
    local autoOpenRow = pages:Row("loot", 2, L["Open after loot"],
        L["Each time you close a loot window, the next clam, sack or lockbox opens by itself, never in a fight or at a vendor, bank or mailbox. Works once Test it says the game allows it. Same as /farm openbutton auto."])
    controls.autoOpen = Widgets.CreateCheckbox(autoOpenRow, L["Open them"], function(checked)
        ns.OpenButton:SetAuto(checked)
    end, false)
    controls.autoOpen:SetPoint("TOPLEFT", CONTROL_X, -2)
end

--- Map and goals: what is drawn on the maps, and the goals and their arrow.
function SettingsUI:BuildMapPage()
    local controls = self.controls
    local pages = self.pages

    pages:Section("map", 1, L["GATHERED NODE MARKERS"])

    local worldRow = pages:Row("map", 1, L["World map"],
        L["Greyed icons with a gold ring and a check where you gathered. Same as /farm markers."])

    controls.markersWorld = Widgets.CreateCheckbox(worldRow, L["Show them"], function(checked)
        ns.MapMarkers:SetWorld(checked)
    end, true)
    controls.markersWorld:SetPoint("TOPLEFT", CONTROL_X, -2)

    local minimapMarkersRow = pages:Row("map", 1, L["Minimap"],
        L["The same markers around you. Hover one to see when you gathered it."])

    controls.markersMinimap = Widgets.CreateCheckbox(minimapMarkersRow, L["Show them"], function(checked)
        ns.MapMarkers:SetMinimap(checked)
    end, true)
    controls.markersMinimap:SetPoint("TOPLEFT", CONTROL_X, -2)

    -- Sparkles on the node you face (the owner asked 2026-10-13).
    local sparkleRow = pages:Row("map", 1, L["Sparkles in the world"],
        L["Gold sparkles on the herb, ore node, fishing school, chest, quest object or fishing bobber near you, one at a time, up to 15 yards away, with the game's own icon above it. To do this it turns on the game's interact target, icon and name, and puts them back when you untick it. Same as /farm sparkle. Check lists what the game lets it read (/farm sparkle check)."])

    controls.nodeSparkle = Widgets.CreateCheckbox(sparkleRow, L["Show them"], function(checked)
        ns.NodeSparkle:SetEnabled(checked)
    end, true)
    controls.nodeSparkle:SetPoint("TOPLEFT", CONTROL_X, -2)

    -- Through the command, so the result is kept for "read the probe".
    local sparkleCheck = Widgets.CreateButton(sparkleRow, L["Check"], function()
        ns.HandleSlash("sparkle check")
    end, { width = 60, height = 20 })
    sparkleCheck:SetPoint("TOPRIGHT", sparkleRow, "TOPRIGHT", 0, 0)
    controls.sparkleCheck = sparkleCheck

    -- Sparkles or a beacon, a beam of light rising off the spot (the owner
    -- asked 2026-10-13).
    local styleNames = { sparkles = L["Sparkles"], beacon = L["Beacon"] }
    local sparkleStyleRow = pages:Row("map", 1, L["Sparkle look"],
        L["A beacon is a beam of gold light rising off the spot, easy to see from far off. Sparkles twinkle round it instead. Same as /farm sparkle beacon or /farm sparkle sparkles."])
    controls.sparkleStyle = Widgets.CreateStepper(sparkleStyleRow, {
        min = 1, max = #ns.NodeSparkle.STYLES, step = 1, value = 1,
        format = function(index) return styleNames[ns.NodeSparkle.STYLES[index]] end,
        onChange = function(index) ns.NodeSparkle:SetStyle(ns.NodeSparkle.STYLES[index]) end,
    })
    ns.SettingsPages.FitStepper(controls.sparkleStyle, styleNames)
    controls.sparkleStyle:SetPoint("TOPLEFT", CONTROL_X, -2)

    -- The game's interact icon, out of sight without a controller (the
    -- owner asked 2026-10-13).
    local sparkleIconRow = pages:Row("map", 1, L["Game's interact icon"],
        L["The game's own icon over the thing you face. When ticked, it stays out of sight unless you play with a controller. Same as /farm sparkle icon."])
    controls.nodeSparkleHideIcon = Widgets.CreateCheckbox(sparkleIconRow, L["Hide it"], function(checked)
        ns.NodeSparkle:SetHideIcon(checked)
    end, true)
    controls.nodeSparkleHideIcon:SetPoint("TOPLEFT", CONTROL_X, -2)

    -- The Grind tab (a player asked, the owner agreed 2026-10-09).
    pages:Section("map", 1, L["GRINDING"])

    local grindRow = pages:Row("map", 1, L["Grinding camps"],
        L["Where mobs of a level and type gather, on the window's Grind tab and the world map. Same as /farm grind and /farm grind pins."])

    controls.grindPins = Widgets.CreateCheckbox(grindRow, L["On map"], function(checked)
        ns.GrindPins:SetOn(checked)
    end, true)
    controls.grindPins:SetPoint("TOPLEFT", CONTROL_X, -2)

    local openGrind = Widgets.CreateButton(grindRow, L["Open"], function()
        ns.Grinding:Command("")
    end, { width = 50, height = 20 })
    openGrind:SetPoint("TOPRIGHT", grindRow, "TOPRIGHT", 0, 0)
    controls.grindOpen = openGrind

    pages:Section("map", 1, L["TOOLTIPS"])

    local tooltipRow = pages:Row("map", 1, L["Where to farm"],
        L["Hover a material for the best place to farm it from where you stand. Same as /farm tooltip."])

    controls.itemTooltip = Widgets.CreateCheckbox(tooltipRow, L["Show it"], function(checked)
        ns.db.itemTooltip = checked
        if ns.ItemTooltip then ns.ItemTooltip.ForgetKept() end
    end, true)
    controls.itemTooltip:SetPoint("TOPLEFT", CONTROL_X, -2)

    -- What crafting a material pays for your time, from Tradeskills
    -- (the owner said yes, 2026-10-15).
    local craftRow = pages:Row("map", 1, L["Craft or sell"],
        L["With Blackthornes Tradeskills, a material you farm shows what an hour of farming it pays sold as it is, and as the craft of yours that pays most. Same as /farm tooltip craft."])
    controls.itemTooltipCraft = Widgets.CreateCheckbox(craftRow, L["Show it"], function(checked)
        ns.ItemTooltip:SetCraftEnabled(checked)
    end, true)
    controls.itemTooltipCraft:SetPoint("TOPLEFT", CONTROL_X, -2)

    local killRow = pages:Row("map", 1, L["Kill count"],
        L["Hover a mob to see how many you've killed. It's red until 20, then shows your kills and what one is worth. Same as /farm killcount."])

    controls.killTooltip = Widgets.CreateCheckbox(killRow, L["Show it"], function(checked)
        ns.KillTooltip:SetEnabled(checked)
    end, true)
    controls.killTooltip:SetPoint("TOPLEFT", CONTROL_X, -2)

    -- The three drops worth most a kill, under the count (2026-10-14).
    local dropsRow = pages:Row("map", 1, L["Best drops"],
        L["Under the kill count, the three drops that add most to what a kill is worth, with how often each drops. Same as /farm killcount drops."])
    controls.killTooltipDrops = Widgets.CreateCheckbox(dropsRow, L["Show it"], function(checked)
        ns.KillTooltip:SetDropsEnabled(checked)
    end, true)
    controls.killTooltipDrops:SetPoint("TOPLEFT", CONTROL_X, -2)

    -- "3/8" beside a quest mob's name (the owner picked it 2026-10-13).
    local questCountRow = pages:Row("map", 1, L["Quest count"],
        L["Shows your count for a quest, like 3/8, in gold beside the name of a mob that quest still needs. Same as /farm questcount."])
    controls.questMobCount = Widgets.CreateCheckbox(questCountRow, L["Show it"], function(checked)
        ns.QuestMobs:SetEnabled(checked)
    end, true)
    controls.questMobCount:SetPoint("TOPLEFT", CONTROL_X, -2)

    -- Your kills beside a mob's nameplate (2026-10-15).
    local platesRow = pages:Row("map", 1, L["Kill count on nameplates"],
        L["Shows how many of a mob you've killed to the left of its nameplate. It's red until 20, then shows your kills. Same as /farm plates."])
    controls.killPlates = Widgets.CreateCheckbox(platesRow, L["Show it"], function(checked)
        ns.KillPlates:SetEnabled(checked)
    end, true)
    controls.killPlates:SetPoint("TOPLEFT", CONTROL_X, -2)

    local platesWorthRow = pages:Row("map", 1, L["Worth on nameplates"],
        L["Adds what one kill is worth after the count, once you have 20 kills. Same as /farm plates worth."])
    controls.killPlatesWorth = Widgets.CreateCheckbox(platesWorthRow, L["Show it"], function(checked)
        ns.KillPlates:SetWorthEnabled(checked)
    end, true)
    controls.killPlatesWorth:SetPoint("TOPLEFT", CONTROL_X, -2)

    -- It needs an item's name, so the button says how to type it.
    local _, whereButton = CommandRow(pages, "map", 1, L["Places for an item"],
        L["The best places near you to farm an item. Type /farm where and its name, like /farm where copper ore. The button shows you how."], L["How to"], "where")
    controls.where = whereButton

    pages:Section("map", 2, L["GOALS"])

    local goalsRow = pages:Row("map", 2, L["Goals panel"],
        L["Shows or hides the goals panel. Dock puts it back under the kills panel. Same as /farm goals and /farm goals dock."])
    controls.goals = CommandButton(goalsRow, L["Show"], "goals", 64)
    controls.goalsDock = CommandButton(goalsRow, L["Dock"], "goals dock", 64, CONTROL_X + 70)

    local _, goalButton = CommandRow(pages, "map", 2, L["Your goals"],
        L["Lists your goals in chat and opens the panel. Set one with /farm goal Copper Ore 40, or the Goal button on a search result. Same as /farm goal."], L["List them"], "goal")
    controls.goalList = goalButton

    local bankRow = pages:Row("map", 2, L["Count the bank"],
        L["Goals count what is in your bank as well as your bags. Same as /farm goal bank."])

    controls.goalsBank = Widgets.CreateCheckbox(bankRow, L["Count it"], function(checked)
        if ns.Goals then ns.Goals:SetCountsBank(checked) end
    end, false)
    controls.goalsBank:SetPoint("TOPLEFT", CONTROL_X, -2)

    pages:Section("map", 2, L["GOAL ARROW"])

    local arrowRow = pages:Row("map", 2, L["Goal arrow"],
        L["Points to the nearest place to gather a goal. Same as /farm arrow. Check lists what the game lets the arrow read here (/farm arrow check)."])

    controls.arrow = Widgets.CreateCheckbox(arrowRow, L["Show it"], function(checked)
        ns.Arrow:SetOn(checked)
    end, false)
    controls.arrow:SetPoint("TOPLEFT", CONTROL_X, -2)

    -- Through the command, so the result is kept for "read the probe"
    -- (ns.KeepCheck), as the typed `/farm arrow check` keeps it.
    local check = Widgets.CreateButton(arrowRow, L["Check"], function()
        ns.HandleSlash("arrow check")
    end, { width = 60, height = 20 })
    check:SetPoint("TOPRIGHT", arrowRow, "TOPRIGHT", 0, 0)
    controls.arrowCheck = check

    local _, nextButton = CommandRow(pages, "map", 2, L["Next place"],
        L["Points the arrow at the next place known for its goal. Same as /farm arrow next."],
        L["Next"], "arrow next")
    controls.arrowNext = nextButton

    local tomtomRow = pages:Row("map", 2, L["Use TomTom"],
        L["With TomTom installed, its arrow points the way instead of this one. Same as /farm arrow tomtom."])

    controls.tomtom = Widgets.CreateCheckbox(tomtomRow, L["When installed"], function(checked)
        ns.TomTom:SetOn(checked)
    end, true)
    controls.tomtom:SetPoint("TOPLEFT", CONTROL_X, -2)
end

--- Sharing: kills, drop rates and gathering with your other account.
function SettingsUI:BuildSharingPage()
    local controls = self.controls
    local pages = self.pages

    pages:Section("sharing", 1, L["YOUR OTHER ACCOUNT"])

    local shareRow = pages:Row("sharing", 1, L["Share with it"],
        L["Sends your kill tallies, drop rates, gathering and fishing to your other account and takes theirs, while both are logged in. Only counts go, never goals, settings or positions. Same as /farm share on and off."])
    controls.share = Widgets.CreateCheckbox(shareRow, L["Sharing"], function(checked)
        ns.Share:SetEnabled(checked)
        SettingsUI:Refresh()
    end, false)
    controls.share:SetPoint("TOPLEFT", CONTROL_X, -2)

    local namesRow = pages:Row("sharing", 1, L["Its characters"],
        L["Characters on your other account, first and last name, with commas between them. Name one of yours in Farmer on that account too. Sharing starts once each side names the other. Same as /farm share with."])
    GrowRow(namesRow, 26)
    local names = Widgets.CreateSearchBox(namesRow, L["Ana Smith, Bob Jones"], nil, function(text)
        ns.Share:SetNames(text)
        SettingsUI:Refresh()
    end, { plain = true })
    names:SetPoint("TOPLEFT", 0, -26)
    names:SetWidth(COLUMN_WIDTH)
    names:SetHeight(20)
    controls.shareNames = names

    local _, syncButton = CommandRow(pages, "sharing", 1, L["Sync now"],
        L["Asks your other account for anything new and sends what is new here. It also runs every ten minutes. Same as /farm share sync."], L["Sync"], "share sync")
    controls.shareSync = syncButton

    pages:Section("sharing", 1, L["WITH ANOTHER PLAYER"])

    local _, giveButton = CommandRow(pages, "sharing", 1, L["Give my data"],
        L["Turns your kills, drop rates, gathering and fishing into text you can copy and send to another player. A big collection comes in parts. It only holds counts, never names, goals or settings. Same as /farm give."],
        L["Make text"], "give")
    controls.shareGive = giveButton

    local _, takeButton = CommandRow(pages, "sharing", 1, L["Take someone's data"],
        L["Paste what another player gave you to add their counts to yours. You see what it adds before anything changes, the same text twice adds nothing, and you can take it back out later. Same as /farm take."], L["Paste"], "take")
    controls.shareTake = takeButton

    -- Logic/GuildShare.lua: the same with guildmates who use Farmer.
    pages:Section("sharing", 2, L["YOUR GUILD"])

    local guildRow = pages:Row("sharing", 2, L["Share with your guild"],
        L["Swaps the drops you've looted with guildmates who use Farmer and have this ticked. Their drop rates fill in the search and a mob's loot table until you've killed it enough for your own. Your kills, loot and rankings stay yours alone. Farmer keeps up to 20 guildmates, and /farm share guild forget confirm deletes what your guild gave. Same as /farm share guild on and off."])
    controls.shareGuild = Widgets.CreateCheckbox(guildRow, L["Sharing"], function(checked)
        ns.GuildShare:SetOn(checked)
        SettingsUI:Refresh()
    end, false)
    controls.shareGuild:SetPoint("TOPLEFT", CONTROL_X, -2)

    pages:Section("sharing", 2, L["HOW IT WORKS"])

    local block = CreateFrame("Frame", nil, pages.pages.sharing.content)
    block:SetSize(COLUMN_WIDTH, 190)
    block.fixedHeight = 190
    pages:Place("sharing", 2, block, -4)

    local summary = Theme.CreateLabel(block, "small", "text")
    summary:SetPoint("TOPLEFT", 0, 0)
    summary:SetWidth(COLUMN_WIDTH)
    summary:SetWordWrap(true)
    self.shareSummary = summary

    local about = Theme.CreateLabel(block, "tiny", "muted")
    about:SetPoint("TOPLEFT", 0, -90)
    about:SetWidth(COLUMN_WIDTH)
    about:SetWordWrap(true)
    about:SetText(L["WoW keeps each account's saved data apart, so Farmer sends it in whispers between two of your own characters. Both accounts end up with what both counted. Nothing is counted twice, and nothing goes to anyone else. The first sync of a big collection can take a while in the background. What comes in joins your own totals and can't be taken back out."])
    pages:Searchable("sharing", block, L["share sync other account second account kills drop rates gathering"])
end

--- Advanced: debug output, the data the addon carries, and the commands.
--- About (UI/About.lua): the note on how the addons are made, then the
--- version, the Discord and the other Blackthornes addons.
function SettingsUI:BuildAboutPage()
    local pages = self.pages
    local About = ns.About
    if not About then return end
    pages:Section("about", 1, L["HOW THESE ADDONS ARE MADE"])
    local note = pages:Place("about", 1, About:Note(pages.pages.about.content, COLUMN_WIDTH))
    pages:Searchable("about", note, note.words)
    pages:Section("about", 2, L["ABOUT"])
    local info = pages:Place("about", 2, About:Info(pages.pages.about.content, COLUMN_WIDTH))
    pages:Searchable("about", info, info.words)
end

function SettingsUI:BuildAdvancedPage()
    local controls = self.controls
    local pages = self.pages

    pages:Section("advanced", 1, L["ADVANCED"])

    local debugRow = pages:Row("advanced", 1, L["Debug output"],
        L["Extra messages in chat, to help track down a problem."])

    controls.debug = Widgets.CreateCheckbox(debugRow, L["Enabled"], function(checked)
        ns.db.debug = checked
    end, false)
    controls.debug:SetPoint("TOPLEFT", CONTROL_X, -2)

    -- Core/SisterNote.lua: one chat line, once, naming the Blackthornes
    -- addons the player does not have. Off here is off in all of them.
    local sistersRow = pages:Row("advanced", 1, L["Sister addons"],
        L["A few seconds after you log in, says once in chat which Blackthornes addons you don't have and what each one adds. Turning it off here turns it off in all of them. Same as /farm sisters."])

    controls.sisters = Widgets.CreateCheckbox(sistersRow, L["Mention them"], function(checked)
        ns.SisterNote:SetOn(checked)
    end, true)
    controls.sisters:SetPoint("TOPLEFT", CONTROL_X, -2)

    -- UI/WhatsNew.lua: one window after an update for every Blackthornes
    -- addon. Off here is off in all of them, as the sister note is.
    local _, whatsNewButton = CommandRow(pages, "advanced", 1, L["What's New"],
        L["Opens the What's New window: what changed in each of your Blackthornes addons. Same as /farm whatsnew."],
        L["Show it"], "whatsnew")
    controls.whatsnew = whatsNewButton

    local whatsNewRow = pages:Row("advanced", 1, L["After an update"],
        L["Brings up the What's New window the first time you play after a Blackthornes addon updates. Turning it off here turns it off in all of them."])
    controls.whatsNewPopup = Widgets.CreateCheckbox(whatsNewRow, L["Show What's New"], function(checked)
        ns.WhatsNew:SetOn(checked)
    end, true)
    controls.whatsNewPopup:SetPoint("TOPLEFT", CONTROL_X, -2)

    local whatsNewMotionRow = pages:Row("advanced", 1, L["What's New motion"],
        L["The What's New window rises in, and its news slides up and glows. Turning it off here turns it off in all of them."])
    controls.whatsNewMotion = Widgets.CreateCheckbox(whatsNewMotionRow, L["Motion"], function(checked)
        ns.WhatsNew:SetMotionOn(checked)
    end, true)
    controls.whatsNewMotion:SetPoint("TOPLEFT", CONTROL_X, -2)

    local _, helpButton = CommandRow(pages, "advanced", 1, L["Commands"],
        L["Lists every /farm command in chat. Same as /farm help."], L["List them"], "help")
    controls.help = helpButton

    -- It needs what to search for, so the button says how to type it.
    local _, chatButton = CommandRow(pages, "advanced", 1, L["Search to chat"],
        L["Puts a search's results in chat instead of the window, like /farm chat copper ore. The button shows you how."], L["How to"], "chat")
    controls.chat = chatButton

    pages:Section("advanced", 2, L["DATA"])

    local _, statsButton = CommandRow(pages, "advanced", 2, L["Data loaded"],
        L["Says in chat how many items and farming spots are loaded. Same as /farm stats."],
        L["Count it"], "stats")
    controls.stats = statsButton

    local _, dataButton = CommandRow(pages, "advanced", 2, L["Where it came from"],
        L["Lists in chat where the farming spots came from: Forever or Classic. Same as /farm data."], L["List it"], "data")
    controls.data = dataButton

    local _, listButton = CommandRow(pages, "advanced", 2, L["Every item"],
        L["Lists in chat every item the addon knows. A long list. Same as /farm list."],
        L["List them"], "list")
    controls.list = listButton
end

--------------------------------------------------------------------------------
-- Refresh
--------------------------------------------------------------------------------

--- Put every control back in step with what is saved.
--
-- Called whenever the page opens and after any /farm command, because each
-- of these can also be changed by typing, and a page showing a stale switch
-- is worse than no page.
function SettingsUI:Refresh()
    if not (self.frame and self.frame:IsShown() and ns.db) then return end

    local db = ns.db
    local controls = self.controls

    controls.minimap:SetChecked(not db.minimapHidden)
    controls.windowScale:SetValue(db.windowScale or 100, true)
    local tallyPercent = ns.TrackerUI and ns.TrackerUI.DrawnPercent and ns.TrackerUI:DrawnPercent()
        or db.trackerScale or 100
    controls.trackerScale:SetValue(tallyPercent, true)
    for _, button in ipairs(controls.trackerSizes or {}) do
        button:SetLabelColor(button.percent == tallyPercent and "good" or nil)
    end
    controls.debug:SetChecked(db.debug == true)
    controls.sisters:SetChecked(ns.SisterNote:IsOn())
    controls.whatsNewPopup:SetChecked(ns.WhatsNew:IsOn())
    controls.whatsNewMotion:SetChecked(ns.WhatsNew:IsMotionOn())
    controls.share:SetChecked(db.shareData == true)
    controls.shareNames:SetText(db.shareNames or "")
    controls.shareGuild:SetChecked(db.shareGuild == true)
    self.shareSummary:SetText(ns.Share:Describe() .. "\n\n" .. ns.GuildShare:Describe())
    controls.markersWorld:SetChecked(db.markersWorld ~= false)
    controls.markersMinimap:SetChecked(db.markersMinimap ~= false)
    controls.nodeSparkle:SetChecked(db.nodeSparkle ~= false)
    controls.sparkleStyle:SetValue(ns.NodeSparkle:Style() == "sparkles" and 1 or 2, true)
    controls.nodeSparkleHideIcon:SetChecked(db.nodeSparkleHideIcon ~= false)
    controls.itemTooltip:SetChecked(db.itemTooltip ~= false)
    controls.itemTooltipCraft:SetChecked(db.itemTooltipCraft ~= false)
    controls.killTooltip:SetChecked(db.killTooltip ~= false)
    controls.killTooltipDrops:SetChecked(db.killTooltipDrops ~= false)
    controls.questMobCount:SetChecked(db.questMobCount ~= false)
    controls.killPlates:SetChecked(db.killPlates ~= false)
    controls.killPlatesWorth:SetChecked(db.killPlatesWorth == true)
    controls.hideSkinning:SetChecked(db.hideSkinning ~= false)
    controls.otherPriceAddons:SetChecked(db.otherPriceAddons ~= false)
    controls.worldDrops:SetChecked(db.worldDrops ~= false)
    controls.rankingsOutside:SetChecked(db.rankingsOutside == true)
    controls.trashCan:SetChecked(db.trashCan ~= false)
    controls.openNote:SetChecked(db.openNote ~= false)
    controls.bagsFull:SetChecked(db.bagsFullNotice ~= false)
    controls.openButton:SetChecked(db.openButton ~= false)
    controls.autoOpen:SetChecked(db.autoOpen == true)
    controls.arrow:SetChecked(db.arrowShown == true)
    controls.tomtom:SetChecked(db.useTomTom ~= false)
    controls.grindPins:SetChecked(db.grindPins ~= false)

    controls.tracker:SetChecked(not db.trackerHidden)
    controls.dodgeGroup:SetChecked(db.trackerDodgeGroup ~= false)
    controls.keepPanel:SetChecked(db.keepPanel == true)
    controls.report:SetChecked(db.trackerReport == true)
    controls.celebrate:SetChecked(db.trackerCelebrate ~= false)

    local ok, bank = pcall(function() return ns.Goals:CountsBank() end)
    controls.goalsBank:SetChecked(ok and bank == true)

    local level = ns.TrackerFX.Level()
    for index, name in ipairs(ns.TrackerFX.LEVELS) do
        if name == level then controls.effects:SetValue(index, true) end
    end
    controls.rareSound:SetChecked(ns.TrackerFX.RareSoundOn())
    if ns.RankUp then
        controls.rankUp:SetChecked(ns.RankUp.On())
        controls.rankUpSound:SetChecked(ns.RankUp.SoundOn())
        controls.topFarm:SetChecked(ns.TopFarm.On())
        controls.statsBestCheer:SetChecked(ns.db.statsBestCheer ~= false)
    end
    controls.voice:SetChecked(ns.TrackerFX.VoiceOn())
    if ns.XPBarUI then
        controls.xpBar:SetChecked(ns.XPBarUI.On())
        controls.xpBarCheer:SetChecked(ns.XPBarUI.CheerOn())
        controls.xpBarChime:SetChecked(ns.XPBarUI.ChimeOn())
        controls.xpBarHideGame:SetChecked(ns.XPBarUI.HidesGame())
    end
    controls.textSize:Sync()
    controls.windowStyle:Sync()

    local usable = ns.Harvest:Capabilities().usable

    controls.record:SetChecked(usable and not db.harvestPaused)
    controls.record:SetDisabled(not usable)

    if not usable and not self.recordUnusable then
        self.recordUnusable = true
        self.recordRow:SetDescription(L["This client does not let addons read the loot window, so nothing can be recorded."])
        self.pages:Fit()
    end

    local corpses = ns.Harvest:CountCorpses()

    if corpses == 0 then
        self.harvestSummary:SetText(Util.Colored("muted", L["Nothing recorded yet."]))
    else
        self.harvestSummary:SetText(L.Format("%s recorded from %s.",
            Util.Plural(corpses, L["corpse"], L["corpses"]),
            Util.Plural(ns.Harvest:CountMobs(), L["mob"], L["mobs"])))
    end

    self.pages:Refresh()
end

--------------------------------------------------------------------------------
-- Position
--------------------------------------------------------------------------------

function SettingsUI:SavePosition()
    if not (ns.db and self.frame) then return end

    local point, _, relativePoint, x, y = self.frame:GetPoint()

    ns.db.settingsPoint = point
    ns.db.settingsRelativePoint = relativePoint
    ns.db.settingsX = x
    ns.db.settingsY = y
end

function SettingsUI:RestorePosition()
    if not self.frame then return end

    local db = ns.db or {}

    if ns.Motion then ns.Motion:Stop(self.frame, "open", true) end
    self.frame:ClearAllPoints()
    self.frame:SetPoint(db.settingsPoint or "CENTER", UIParent,
        db.settingsRelativePoint or "CENTER", db.settingsX or 0, db.settingsY or 0)
end

--------------------------------------------------------------------------------
-- Visibility
--------------------------------------------------------------------------------

function SettingsUI:Show()
    self:Build()

    if not self.frame:IsShown() then
        self:RestorePosition()
        self.frame:Show()
        ns.Motion:Open(self.frame)
    end

    self:Refresh()
end

function SettingsUI:Hide()
    if self.frame then self.frame:Hide() end
end

function SettingsUI:Toggle()
    if self.frame and self.frame:IsShown() then
        self:Hide()
    else
        self:Show()
    end
end

--------------------------------------------------------------------------------
-- The game's own AddOns options list
--
-- Forever runs retail's Settings panel, so the addon can have an entry under
-- Options > AddOns. That entry is a small launcher rather than this page
-- squeezed into Blizzard's frame: the page is built for its own dark window,
-- and a button that opens it is one click either way.
--
-- Every call is guarded: nothing documents which of these this client ships,
-- and a missing options entry is no reason for the addon to fail to load.
--------------------------------------------------------------------------------

function SettingsUI:RegisterGameOptions()
    if self.optionsPanel then return end

    local panel = CreateFrame("Frame")
    panel.name = TITLE

    local title = Theme.CreateLabel(panel, "title", "accent")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText(TITLE)

    local blurb = Theme.CreateLabel(panel, "normal", "text")
    blurb:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -10)
    blurb:SetText(L["Farmer's settings have a window of their own."])

    local open = Widgets.CreateButton(panel, L["Open Farmer settings"], function()
        -- The game's panel is left as it is: hiding a stock frame runs the
        -- game's own code as this addon and taints it (Equipment's Edit
        -- Mode error, 2026-10-10). Farmer's window is top level in the
        -- dialog layer, so it comes up over the panel.
        SettingsUI:Show()
    end, { width = 170, height = 24 })
    open:SetPoint("TOPLEFT", blurb, "BOTTOMLEFT", 0, -14)

    local hint = Theme.CreateLabel(panel, "small", "muted")
    hint:SetPoint("TOPLEFT", open, "BOTTOMLEFT", 0, -10)
    hint:SetText(L["Or type /farm settings, or right-click the minimap button."])

    self.optionsPanel = panel

    local registered = false

    if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
        registered = pcall(function()
            local category = Settings.RegisterCanvasLayoutCategory(panel, TITLE)
            Settings.RegisterAddOnCategory(category)
            SettingsUI.optionsCategory = category
        end)
    end

    -- The older options API, in case this client still has it instead.
    if not registered and type(InterfaceOptions_AddCategory) == "function" then
        registered = pcall(InterfaceOptions_AddCategory, panel)
    end

    if not registered then
        ns.Debug("no game options panel to register with; /farm settings still works")
    end

    return registered
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

function SettingsUI:OnEnable()
    -- Sizes are saved, so put them back before anything is seen.
    self:ApplyWindowScale()
    self:ApplyTrackerScale()

    local ok, err = pcall(self.RegisterGameOptions, self)
    if not ok then
        ns.Debug("could not add Farmer to the game's options:", tostring(err))
    end
end

ns.RegisterCommand("settings", L["open the settings window"], function()
    SettingsUI:Toggle()
end)

-- Common names for the same thing, so a guess works. Kept out of the help
-- list, which would otherwise print the same line three times.
ns.commands.options = ns.commands.settings
ns.commands.config = ns.commands.settings
