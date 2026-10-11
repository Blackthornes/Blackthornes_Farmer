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
    { key = "windows", text = "WINDOWS",
      tip = "The minimap button, window sizes and places, effects and text size" },
    { key = "tally", text = "KILL TALLY",
      tip = "The kills and loot panel, what it says in chat, and your kills" },
    { key = "loot", text = "LOOT",
      tip = "Recording what drops and its export, and your fishing and gathering" },
    { key = "map", text = "MAP & GOALS",
      tip = "Node markers, grinding camps, goals and the goal arrow" },
    { key = "advanced", text = "ADVANCED",
      tip = "Debug output, the data loaded and the list of commands" },
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
            title = "Farmer Settings",
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
    self:BuildAdvancedPage()
    self.pages:Fit()

    local footer = Theme.CreateLabel(frame, "tiny", "dim")
    footer:SetPoint("BOTTOMLEFT", PADDING, 10)
    footer:SetPoint("BOTTOMRIGHT", -PADDING, 10)
    -- Two lines if it needs them, rather than cut off.
    footer:SetHeight(26)
    footer:SetWordWrap(true)
    footer:SetJustifyV("BOTTOM")
    footer:SetText("Changes save as you make them. Clearing tallies or recorded loot "
        .. "is left to typed commands, so nothing here can delete your data.")
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

    pages:Section("windows", 1, "WINDOWS")

    local minimapRow = pages:Row("windows", 1, "Minimap button",
        "Left-click it to search, right-click for this page. Drag it round the edge "
        .. "to move it. Same as /farm minimap.")

    controls.minimap = Widgets.CreateCheckbox(minimapRow, "Show it", function(checked)
        ns.db.minimapHidden = not checked
        if ns.UI then ns.UI:ApplyMinimapVisibility() end
    end, true)
    controls.minimap:SetPoint("TOPLEFT", CONTROL_X, -2)

    local windowScaleRow = pages:Row("windows", 1, "Search window size",
        "Bigger for a high-resolution screen, smaller for a laptop.")

    controls.windowScale = Widgets.CreateStepper(windowScaleRow, {
        min = SCALE_MIN, max = SCALE_MAX, step = SCALE_STEP, value = 100,
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
    local trackerScaleRow = pages:Row("windows", 1, "Kill tally size",
        "The kills and loot panel, sized on its own. Or drag the gold corner "
        .. "beside its bottom right; right-click it for Normal. Same as /farm tracker size.")

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
        Explain(button, ("%s kill tally"):format(size.text),
            ("Draws the kills and loot panel at %d%%, text and all. Same as /farm tracker size %s."):format(
                size.percent, size.key))
        button.percent = size.percent
        controls.trackerSizes[index] = button
        after = button
    end
    if after then GrowRow(trackerScaleRow, 24) end

    local positionRow = pages:Row("windows", 1, "Window positions",
        "Moves every Farmer window back to where it started, if one ends up off screen.")

    local reset = Widgets.CreateButton(positionRow, "Put them back", function()
        SettingsUI:ResetPositions()
        ns.Print("windows moved back to where they started.")
    end, { width = 110, height = 20 })
    reset:SetPoint("TOPLEFT", CONTROL_X, 0)
    controls.resetPositions = reset

    pages:Section("windows", 2, "LOOK")

    -- Every window and both panels follow it, so it sits with the windows
    -- rather than under the kill tally. The saved key keeps its old name.
    local effectsRow = pages:Row("windows", 2, "Window effects",
        "Full: windows fade up and glow, and loot floats off the kill panel. "
        .. "Subtle: shorter fades, and nothing floats. Off: no movement at all. "
        .. "Same as /farm effects.")

    local FX = ns.TrackerFX
    controls.effects = Widgets.CreateStepper(effectsRow, {
        min = 1, max = #FX.LEVELS, step = 1, value = #FX.LEVELS,
        format = function(index) return FX.LEVEL_NAMES[FX.LEVELS[index]] end,
        onChange = function(index) FX:SetLevel(FX.LEVELS[index]) end,
    })
    controls.effects:SetPoint("TOPLEFT", CONTROL_X, 0)

    -- Bigger letters in the same windows, as Tradeskills has. Every size
    -- is read as text is drawn, so it waits for /reload.
    local textRow = pages:Row("windows", 2, "Text size",
        "Large and Larger add a point or two to all of this addon's text. "
        .. "Takes effect after /reload.")
    controls.textSize = ns.SettingsPages.TextSizeControl(textRow, CONTROL_X, function() return ns.db end)

    -- Asked 2026-10-10: the game's own look for players who would rather
    -- the windows matched the rest of their screen. Read at login, so it
    -- waits for /reload as Text size does. See UI/BlizzardLook.lua.
    local styleRow = pages:Row("windows", 2, "Window style",
        "Titanforged is the house look, with a gold rim and glowing edges. "
        .. "Blizzard uses the game's own frames, red buttons, tabs and tick boxes. "
        .. "Takes effect after /reload.")
    controls.windowStyle = SettingsUI:WindowStyleControl(styleRow)

    pages:Section("windows", 2, "OPEN")

    local _, searchButton = CommandRow(pages, "windows", 2, "Search window",
        "Search for something to farm and see where it drops. Same as /farm on its own, "
        .. "or /farm and what you are after.", "Open it", function()
            -- /farm on its own toggles the window, so with it already open
            -- this closed it. It opens it, on the Search tab.
            ns.UI:Show()
            ns.UI:ShowTab("search")
        end)
    controls.openSearch = searchButton

    local _, rankingsButton = CommandRow(pages, "windows", 2, "Rankings",
        "Mobs ranked by what a kill is worth. Same as /farm rankings.", "Open it", "rankings")
    controls.rankings = rankingsButton
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
    reload = Widgets.CreateButton(row, "Reload", function()
        if ReloadUI then ReloadUI() end
    end, { width = 60, height = 20 })
    ns.SettingsPages.ReloadUnder(row, stepper, reload)
    Explain(reload, "Reload", "Reload the interface so the new window style shows (/reload).")
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

    pages:Section("tally", 1, "KILL TALLY")

    local trackerRow = pages:Row("tally", 1, "Tally panel",
        "Shows what you have killed and what dropped. Same as /farm tracker.")

    controls.tracker = Widgets.CreateCheckbox(trackerRow, "Show it", function(checked)
        SettingsUI:SetTrackerShown(checked)
    end, true)
    controls.tracker:SetPoint("TOPLEFT", CONTROL_X, -2)

    local groupRow = pages:Row("tally", 1, "In a group",
        "Moves the panel beside the party and raid frames. Drag it in a "
        .. "group to pick a spot. Same as /farm tracker group.")

    controls.dodgeGroup = Widgets.CreateCheckbox(groupRow, "Move aside", function(checked)
        ns.TrackerUI:SetDodgeGroup(checked)
    end, true)
    controls.dodgeGroup:SetPoint("TOPLEFT", CONTROL_X, -2)

    local reportRow = pages:Row("tally", 1, "Chat report",
        "One line per kill in your own chat window. Nobody else can see it. "
        .. "Same as /farm report.")

    controls.report = Widgets.CreateCheckbox(reportRow, "Report kills", function(checked)
        ns.db.trackerReport = checked
    end, false)
    controls.report:SetPoint("TOPLEFT", CONTROL_X, -2)

    local announceRow = pages:Row("tally", 1, "Share milestones",
        "A mob's 20th kill, a fishing spot's 20th cast or a node's 20th gather: "
        .. "an /emote players near you see. Your chat always gets it. Same as /farm announce.")

    controls.announce = Widgets.CreateCheckbox(announceRow, "Emote it", function(checked)
        ns.db.trackerAnnounce = checked
    end, true)
    controls.announce:SetPoint("TOPLEFT", CONTROL_X, -2)

    local celebrateRow = pages:Row("tally", 1, "Milestone fanfare",
        "A sound and a cheer when a mob's 20th kill, a fishing spot's 20th cast or "
        .. "a node's 20th gather unlocks its rates. Same as /farm celebrate.")

    controls.celebrate = Widgets.CreateCheckbox(celebrateRow, "Play it", function(checked)
        ns.db.trackerCelebrate = checked
    end, true)
    controls.celebrate:SetPoint("TOPLEFT", CONTROL_X, -2)

    local rareRow = pages:Row("tally", 1, "Rare drop sound",
        "A chime when something green or better drops. Only you hear it. "
        .. "Same as /farm raresound.")

    controls.rareSound = Widgets.CreateCheckbox(rareRow, "Play it", function(checked)
        ns.db.trackerRareSound = checked
    end, true)
    controls.rareSound:SetPoint("TOPLEFT", CONTROL_X, -2)

    -- The mob you last looted, as the commands read it with no name.
    pages:Section("tally", 2, "YOUR LAST MOB")

    local _, killsButton = CommandRow(pages, "tally", 2, "Kills and drops",
        "Lists in chat how often you have killed the mob you last looted, and its drop "
        .. "rates. Same as /farm kills, or /farm kills and a mob's name.", "List them", "kills")
    controls.kills = killsButton

    local _, lootButton = CommandRow(pages, "tally", 2, "Loot table",
        "Opens the full loot table of the mob you last looted. Same as /farm loot, "
        .. "or /farm loot and a mob's name.", "Open it", "loot")
    controls.lootTable = lootButton

    local _, valueButton = CommandRow(pages, "tally", 2, "Worth per kill",
        "What a kill of the mob you last looted is worth, from Tradeskills' prices. "
        .. "Same as /farm value, or /farm value and a mob's name.", "Work it out", "value")
    controls.value = valueButton
end

--- Loot: recording what drops, its export, fishing and gathering.
function SettingsUI:BuildLootPage()
    local controls = self.controls
    local pages = self.pages

    pages:Section("loot", 1, "LOOT RECORDING")

    local recordRow = pages:Row("loot", 1, "Record what drops",
        "Counts what every corpse held, so drop rates are measured on Forever. "
        .. "Kept on this computer only. Same as /farm harvest on and off.")

    controls.record = Widgets.CreateCheckbox(recordRow, "Recording", function(checked)
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

    local export = Widgets.CreateButton(block, "Export", function()
        ns.UI:ShowExport(ns.Harvest:ExportAll(), "Export: everything harvested")
    end, { width = 80, height = 20 })
    export:SetPoint("TOPLEFT", 0, -22)
    controls.export = export

    -- Kept to the column beside the button, on two lines if the font needs
    -- them: on one it ran past the window's right edge.
    local exportHint = Theme.CreateLabel(block, "tiny", "dim")
    exportHint:SetPoint("LEFT", export, "RIGHT", 8, 0)
    exportHint:SetWidth(COLUMN_WIDTH - export:GetWidth() - 8)
    exportHint:SetWordWrap(true)
    exportHint:SetText("Your recorded loot, as a data file. Same as /farm export.")
    self.exportHint = exportHint
    pages:Searchable("loot", block, "export recorded loot data file")

    local _, harvestButton = CommandRow(pages, "loot", 1, "What you recorded",
        "Lists in chat the items you have looted most, and from how many corpses. "
        .. "Same as /farm harvest.", "List it", "harvest")
    controls.harvest = harvestButton

    local _, lootCheckButton = CommandRow(pages, "loot", 1, "Loot check",
        "Readies a check that runs on the next corpse you loot and lists in chat "
        .. "what the game lets the addon read there, to help with a dungeon "
        .. "that records nothing. It only reads. Same as /farm harvest check.",
        "Ready", "harvest check")
    controls.harvestCheck = lootCheckButton

    pages:Section("loot", 2, "FISHING AND GATHERING")

    local fishingRow = pages:Row("loot", 2, "Fishing",
        "Lists in chat what you have caught in this zone, or everywhere. "
        .. "Same as /farm fishing and /farm fishing all.")
    controls.fishing = CommandButton(fishingRow, "Here", "fishing", 50)
    controls.fishingAll = CommandButton(fishingRow, "Everywhere", "fishing all", 82, CONTROL_X + 56)

    local gatheringRow = pages:Row("loot", 2, "Gathering",
        "Lists in chat the herbs and ore you have gathered in this zone, or everywhere. "
        .. "Same as /farm gathering and /farm gathering all.")
    controls.gathering = CommandButton(gatheringRow, "Here", "gathering", 50)
    controls.gatheringAll = CommandButton(gatheringRow, "Everywhere", "gathering all", 82, CONTROL_X + 56)

    local _, checkButton = CommandRow(pages, "loot", 2, "Odd gathers",
        "Lists in chat gathers that look recorded wrong, to help track down a problem. "
        .. "It only reads. Same as /farm gathering check.", "Check", "gathering check")
    controls.gatheringCheck = checkButton
end

--- Map and goals: what is drawn on the maps, and the goals and their arrow.
function SettingsUI:BuildMapPage()
    local controls = self.controls
    local pages = self.pages

    pages:Section("map", 1, "GATHERED NODE MARKERS")

    local worldRow = pages:Row("map", 1, "World map",
        "Greyed icons with a gold ring and a check where you gathered. "
        .. "Same as /farm markers.")

    controls.markersWorld = Widgets.CreateCheckbox(worldRow, "Show them", function(checked)
        ns.MapMarkers:SetWorld(checked)
    end, true)
    controls.markersWorld:SetPoint("TOPLEFT", CONTROL_X, -2)

    local minimapMarkersRow = pages:Row("map", 1, "Minimap",
        "The same markers around you. Hover one to see when you gathered it.")

    controls.markersMinimap = Widgets.CreateCheckbox(minimapMarkersRow, "Show them", function(checked)
        ns.MapMarkers:SetMinimap(checked)
    end, true)
    controls.markersMinimap:SetPoint("TOPLEFT", CONTROL_X, -2)

    -- The Grind tab (a player asked, the owner agreed 2026-10-09).
    pages:Section("map", 1, "GRINDING")

    local grindRow = pages:Row("map", 1, "Grinding camps",
        "Where mobs of a level and type gather, on the window's Grind tab and "
        .. "the world map. Same as /farm grind and /farm grind pins.")

    controls.grindPins = Widgets.CreateCheckbox(grindRow, "On map", function(checked)
        ns.GrindPins:SetOn(checked)
    end, true)
    controls.grindPins:SetPoint("TOPLEFT", CONTROL_X, -2)

    local openGrind = Widgets.CreateButton(grindRow, "Open", function()
        ns.Grinding:Command("")
    end, { width = 50, height = 20 })
    openGrind:SetPoint("TOPRIGHT", grindRow, "TOPRIGHT", 0, 0)
    controls.grindOpen = openGrind

    pages:Section("map", 1, "TOOLTIPS")

    local tooltipRow = pages:Row("map", 1, "Where to farm",
        "Hover a material for the best place to farm it from where you stand. "
        .. "Same as /farm tooltip.")

    controls.itemTooltip = Widgets.CreateCheckbox(tooltipRow, "Show it", function(checked)
        ns.db.itemTooltip = checked
        if ns.ItemTooltip then ns.ItemTooltip.ForgetKept() end
    end, true)
    controls.itemTooltip:SetPoint("TOPLEFT", CONTROL_X, -2)

    -- It needs an item's name, so the button says how to type it.
    local _, whereButton = CommandRow(pages, "map", 1, "Places for an item",
        "The best places near you to farm an item, typed with its name: "
        .. "/farm where copper ore. The button says how.", "How to", "where")
    controls.where = whereButton

    pages:Section("map", 2, "GOALS")

    local goalsRow = pages:Row("map", 2, "Goals panel",
        "Shows or hides the goals panel; Dock puts it back under the kills panel. "
        .. "Same as /farm goals and /farm goals dock.")
    controls.goals = CommandButton(goalsRow, "Show", "goals", 64)
    controls.goalsDock = CommandButton(goalsRow, "Dock", "goals dock", 64, CONTROL_X + 70)

    local _, goalButton = CommandRow(pages, "map", 2, "Your goals",
        "Lists your goals in chat and opens the panel. Set one with /farm goal Copper Ore 40, "
        .. "or the Goal button on a search result. Same as /farm goal.", "List them", "goal")
    controls.goalList = goalButton

    local bankRow = pages:Row("map", 2, "Count the bank",
        "Goals count what is in your bank as well as your bags. Same as /farm goal bank.")

    controls.goalsBank = Widgets.CreateCheckbox(bankRow, "Count it", function(checked)
        if ns.Goals then ns.Goals:SetCountsBank(checked) end
    end, false)
    controls.goalsBank:SetPoint("TOPLEFT", CONTROL_X, -2)

    pages:Section("map", 2, "GOAL ARROW")

    local arrowRow = pages:Row("map", 2, "Goal arrow",
        "Points to the nearest place to gather a goal. Same as /farm arrow. "
        .. "Check lists what the game lets it read here (/farm arrow check).")

    controls.arrow = Widgets.CreateCheckbox(arrowRow, "Show it", function(checked)
        ns.Arrow:SetOn(checked)
    end, false)
    controls.arrow:SetPoint("TOPLEFT", CONTROL_X, -2)

    -- Through the command, so the result is kept for "read the probe"
    -- (ns.KeepCheck), as the typed `/farm arrow check` keeps it.
    local check = Widgets.CreateButton(arrowRow, "Check", function()
        ns.HandleSlash("arrow check")
    end, { width = 60, height = 20 })
    check:SetPoint("TOPRIGHT", arrowRow, "TOPRIGHT", 0, 0)
    controls.arrowCheck = check

    local _, nextButton = CommandRow(pages, "map", 2, "Next place",
        "Points the arrow at the next place known for its goal. Same as /farm arrow next.",
        "Next", "arrow next")
    controls.arrowNext = nextButton

    local tomtomRow = pages:Row("map", 2, "Use TomTom",
        "With TomTom installed, its arrow points the way instead of this one. "
        .. "Same as /farm arrow tomtom.")

    controls.tomtom = Widgets.CreateCheckbox(tomtomRow, "When installed", function(checked)
        ns.TomTom:SetOn(checked)
    end, true)
    controls.tomtom:SetPoint("TOPLEFT", CONTROL_X, -2)
end

--- Advanced: debug output, the data the addon carries, and the commands.
function SettingsUI:BuildAdvancedPage()
    local controls = self.controls
    local pages = self.pages

    pages:Section("advanced", 1, "ADVANCED")

    local debugRow = pages:Row("advanced", 1, "Debug output",
        "Extra messages in chat, to help track down a problem.")

    controls.debug = Widgets.CreateCheckbox(debugRow, "Enabled", function(checked)
        ns.db.debug = checked
    end, false)
    controls.debug:SetPoint("TOPLEFT", CONTROL_X, -2)

    local _, helpButton = CommandRow(pages, "advanced", 1, "Commands",
        "Lists every /farm command in chat. Same as /farm help.", "List them", "help")
    controls.help = helpButton

    -- It needs what to search for, so the button says how to type it.
    local _, chatButton = CommandRow(pages, "advanced", 1, "Search to chat",
        "Prints a search's results in chat instead of the window: /farm chat copper ore. "
        .. "The button says how.", "How to", "chat")
    controls.chat = chatButton

    pages:Section("advanced", 2, "DATA")

    local _, statsButton = CommandRow(pages, "advanced", 2, "Data loaded",
        "Says in chat how many items and farming spots are loaded. Same as /farm stats.",
        "Count it", "stats")
    controls.stats = statsButton

    local _, dataButton = CommandRow(pages, "advanced", 2, "Where it came from",
        "Lists in chat where the farming spots came from: Forever or Classic. "
        .. "Same as /farm data.", "List it", "data")
    controls.data = dataButton

    local _, listButton = CommandRow(pages, "advanced", 2, "Every item",
        "Lists in chat every item the addon knows. A long list. Same as /farm list.",
        "List them", "list")
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
    controls.markersWorld:SetChecked(db.markersWorld ~= false)
    controls.markersMinimap:SetChecked(db.markersMinimap ~= false)
    controls.itemTooltip:SetChecked(db.itemTooltip ~= false)
    controls.arrow:SetChecked(db.arrowShown == true)
    controls.tomtom:SetChecked(db.useTomTom ~= false)
    controls.grindPins:SetChecked(db.grindPins ~= false)

    controls.tracker:SetChecked(not db.trackerHidden)
    controls.dodgeGroup:SetChecked(db.trackerDodgeGroup ~= false)
    controls.report:SetChecked(db.trackerReport == true)
    controls.announce:SetChecked(db.trackerAnnounce ~= false)
    controls.celebrate:SetChecked(db.trackerCelebrate ~= false)

    local ok, bank = pcall(function() return ns.Goals:CountsBank() end)
    controls.goalsBank:SetChecked(ok and bank == true)

    local level = ns.TrackerFX.Level()
    for index, name in ipairs(ns.TrackerFX.LEVELS) do
        if name == level then controls.effects:SetValue(index, true) end
    end
    controls.rareSound:SetChecked(ns.TrackerFX.RareSoundOn())
    controls.textSize:Sync()
    controls.windowStyle:Sync()

    local usable = ns.Harvest:Capabilities().usable

    controls.record:SetChecked(usable and not db.harvestPaused)
    controls.record:SetDisabled(not usable)

    if not usable and not self.recordUnusable then
        self.recordUnusable = true
        self.recordRow:SetDescription("This client does not let addons read the loot window, "
            .. "so nothing can be recorded.")
        self.pages:Fit()
    end

    local corpses = ns.Harvest:CountCorpses()

    if corpses == 0 then
        self.harvestSummary:SetText(Util.Colored("muted", "Nothing recorded yet."))
    else
        self.harvestSummary:SetText(("%s recorded from %s."):format(
            Util.Plural(corpses, "corpse"), Util.Plural(ns.Harvest:CountMobs(), "mob")))
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
    blurb:SetText("Farmer's settings have a window of their own.")

    local open = Widgets.CreateButton(panel, "Open Farmer settings", function()
        -- The game's panel is left as it is: hiding a stock frame runs the
        -- game's own code as this addon and taints it (Equipment's Edit
        -- Mode error, 2026-10-10). Farmer's window is top level in the
        -- dialog layer, so it comes up over the panel.
        SettingsUI:Show()
    end, { width = 170, height = 24 })
    open:SetPoint("TOPLEFT", blurb, "BOTTOMLEFT", 0, -14)

    local hint = Theme.CreateLabel(panel, "small", "muted")
    hint:SetPoint("TOPLEFT", open, "BOTTOMLEFT", 0, -10)
    hint:SetText("Or type /farm settings, or right-click the minimap button.")

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

ns.RegisterCommand("settings", "open the settings window", function()
    SettingsUI:Toggle()
end)

-- Common names for the same thing, so a guess works. Kept out of the help
-- list, which would otherwise print the same line three times.
ns.commands.options = ns.commands.settings
ns.commands.config = ns.commands.settings
