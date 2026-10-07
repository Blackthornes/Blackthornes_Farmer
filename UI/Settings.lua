-- Blackthornes Farmer -- UI/Settings.lua
-- The settings window: every switch the addon has, in one place.
--
-- Until now each option lived behind its own chat command, which is fine once
-- you know it exists and useless until then. This gathers them onto one page
-- with a line under each saying what it actually does, the same way the
-- tradeskills addon's Settings tab does, so the two read as one set.
--
-- Open it with /farm settings, right-click on the minimap button, the Settings
-- button in the search window, or from the game's own AddOns options list.
--
-- Nothing here deletes anything. Wiping kill tallies or recorded loot stays a
-- typed two-word command, so a stray click on this page can never cost data.
--
-- Layout rule, borrowed from the tradeskills addon: a row is [label .. control]
-- on one line with its description underneath across the whole column. Rows
-- are a fixed height, so nothing can slide under the control beside it.

local _, ns = ...

local SettingsUI = ns.NewModule("SettingsUI")

local Theme = ns.Theme
local Widgets = ns.Widgets
local Util = ns.Util

local PADDING = 18
local HEADER = 36

local COLUMN_WIDTH = 310
local COLUMN_TWO_X = PADDING * 2 + COLUMN_WIDTH
-- Where the controls start: room for a label like "Search window size" in the
-- game's font, which runs wider than it looks.
local CONTROL_X = 170

local WIDTH = COLUMN_WIDTH * 2 + PADDING * 3
-- Tall enough for the left column, the taller: five window rows, the two
-- marker rows and debug output, over the footer.
local HEIGHT = 668

local ROW_HEIGHT = 50
local ROW_GAP = -6
local SECTION_GAP = -16

-- Window sizes, in percent. Wide enough to matter on a 4K screen or a laptop,
-- narrow enough that neither end breaks the layout.
local SCALE_MIN = 70
local SCALE_MAX = 150
local SCALE_STEP = 10

local TITLE = "Blackthornes Farmer"

--------------------------------------------------------------------------------
-- Layout helpers
--------------------------------------------------------------------------------

--- Section heading with a rule underneath. Returns a frame to anchor rows to.
local function CreateSection(parent, text, opts)
    local section = CreateFrame("Frame", nil, parent)
    section:SetSize(COLUMN_WIDTH, 18)
    -- Which column it sits in, so each column's extra height is counted
    -- apart: they stand side by side, and the taller one sets the window.
    section.column = opts.x or (opts.anchor and opts.anchor.column) or 0

    if opts.anchor then
        section:SetPoint("TOPLEFT", opts.anchor, "BOTTOMLEFT", 0, SECTION_GAP)
    else
        section:SetPoint("TOPLEFT", opts.x, opts.y)
    end

    local heading = Theme.CreateLabel(section, "tiny", "accent")
    heading:SetPoint("TOPLEFT", 0, 0)
    heading:SetText(text)

    local divider = Theme.CreateDivider(section, "border")
    divider:SetPoint("TOPLEFT", 0, -14)
    divider:SetWidth(COLUMN_WIDTH)

    return section
end

--- One setting: label and control on a line, what it does underneath.
-- The description may wrap to a second line; the row is sized for two.
local function CreateRow(parent, anchor, labelText, description)
    local row = CreateFrame("Frame", nil, parent)
    row:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, ROW_GAP)
    row:SetSize(COLUMN_WIDTH, ROW_HEIGHT)

    local label = Theme.CreateLabel(row, "small", "text")
    label:SetPoint("TOPLEFT", 0, -4)
    label:SetWidth(CONTROL_X - 8)
    label:SetText(labelText)

    local hint = Theme.CreateLabel(row, "tiny", "dim")
    hint:SetPoint("TOPLEFT", 0, -25)
    hint:SetWidth(COLUMN_WIDTH)
    hint:SetWordWrap(true)
    hint:SetText(description or "")

    -- Sized for two lines of description; a longer one gets the room it
    -- needs rather than running into the row below. The height the game
    -- wrapped it to where it says, else a guess that allows for words
    -- breaking early.
    local height
    local ok, value = pcall(hint.GetStringHeight, hint)
    if ok and type(value) == "number" and value > 0 then height = value end
    local lines = height and math.ceil(height / 12 - 0.1)
        or math.ceil(Theme.TextWidth("tiny", description or "") / (COLUMN_WIDTH * 0.9))
    row.extra = math.max(0, lines - 2) * 12
    row:SetHeight(ROW_HEIGHT + row.extra)
    row.hintLines = lines
    row.column = anchor.column or 0
    local columns = SettingsUI.columnExtra or {}
    SettingsUI.columnExtra = columns
    columns[row.column] = (columns[row.column] or 0) + row.extra
    SettingsUI.rowsExtra = math.max(SettingsUI.rowsExtra or 0, columns[row.column])

    row.label = label
    row.hint = hint
    return row
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
        if previous then
            SettingsUI.KeepSpot({ "trackerX", "trackerY", "trackerGroupX", "trackerGroupY" },
                previous, ns.db.trackerScale or 100)
        end
        frame:SetScale((ns.db.trackerScale or 100) / 100)
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

    self:RestorePosition()
end

--------------------------------------------------------------------------------
-- Construction
--------------------------------------------------------------------------------

function SettingsUI:Build()
    if self.frame then return self.frame end

    local frame = CreateFrame("Frame", "BlackthornesFarmerSettings", UIParent)
    frame:SetSize(WIDTH, HEIGHT)
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
    self:BuildWindowsColumn()
    self:BuildTrackingColumn()

    -- Room for any description that wrapped past two lines.
    frame:SetHeight(HEIGHT + (SettingsUI.rowsExtra or 0))

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

--- Left column: how the addon looks and where things sit.
function SettingsUI:BuildWindowsColumn()
    local frame = self.frame
    local controls = self.controls

    local windows = CreateSection(frame, "WINDOWS", { x = PADDING, y = -(HEADER + 16) })

    local minimapRow = CreateRow(frame, windows, "Minimap button",
        "Left-click it to search, right-click for this page. Drag it round the edge to move it.")

    controls.minimap = Widgets.CreateCheckbox(minimapRow, "Show it", function(checked)
        ns.db.minimapHidden = not checked
        if ns.UI then ns.UI:ApplyMinimapVisibility() end
    end, true)
    controls.minimap:SetPoint("TOPLEFT", CONTROL_X, -2)

    local windowScaleRow = CreateRow(frame, minimapRow, "Search window size",
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

    local trackerScaleRow = CreateRow(frame, windowScaleRow, "Kill tally size",
        "The panel that follows your farming. Sized on its own, since it stays on screen.")

    controls.trackerScale = Widgets.CreateStepper(trackerScaleRow, {
        min = SCALE_MIN, max = SCALE_MAX, step = SCALE_STEP, value = 100,
        format = Percent,
        onChange = function(value)
            local previous = ns.db.trackerScale or 100
            ns.db.trackerScale = value
            SettingsUI:ApplyTrackerScale(previous)
        end,
    })
    controls.trackerScale:SetPoint("TOPLEFT", CONTROL_X, 0)

    local positionRow = CreateRow(frame, trackerScaleRow, "Window positions",
        "Moves every Farmer window back to where it started, if one ends up off screen.")

    local reset = Widgets.CreateButton(positionRow, "Put them back", function()
        SettingsUI:ResetPositions()
        ns.Print("windows moved back to where they started.")
    end, { width = 110, height = 20 })
    reset:SetPoint("TOPLEFT", CONTROL_X, 0)

    -- Every window and both panels follow it, so it sits with the windows
    -- rather than under the kill tally. The saved key keeps its old name.
    local effectsRow = CreateRow(frame, positionRow, "Window effects",
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

    local markers = CreateSection(frame, "GATHERED NODE MARKERS", { anchor = effectsRow })

    local worldRow = CreateRow(frame, markers, "World map",
        "Greyed icons with a gold ring and a check where you gathered. "
        .. "Same as /farm markers.")

    controls.markersWorld = Widgets.CreateCheckbox(worldRow, "Show them", function(checked)
        ns.MapMarkers:SetWorld(checked)
    end, true)
    controls.markersWorld:SetPoint("TOPLEFT", CONTROL_X, -2)

    local minimapMarkersRow = CreateRow(frame, worldRow, "Minimap",
        "The same markers around you. Hover one to see when you gathered it.")

    controls.markersMinimap = Widgets.CreateCheckbox(minimapMarkersRow, "Show them", function(checked)
        ns.MapMarkers:SetMinimap(checked)
    end, true)
    controls.markersMinimap:SetPoint("TOPLEFT", CONTROL_X, -2)

    local advanced = CreateSection(frame, "ADVANCED", { anchor = minimapMarkersRow })

    local debugRow = CreateRow(frame, advanced, "Debug output",
        "Extra messages in chat, to help track down a problem.")

    controls.debug = Widgets.CreateCheckbox(debugRow, "Enabled", function(checked)
        ns.db.debug = checked
    end, false)
    controls.debug:SetPoint("TOPLEFT", CONTROL_X, -2)
end

--- Right column: what the addon keeps track of while you play.
function SettingsUI:BuildTrackingColumn()
    local frame = self.frame
    local controls = self.controls

    local tally = CreateSection(frame, "KILL TALLY", { x = COLUMN_TWO_X, y = -(HEADER + 16) })

    local trackerRow = CreateRow(frame, tally, "Tally panel",
        "Shows what you have killed and what dropped. Same as /farm tracker.")

    controls.tracker = Widgets.CreateCheckbox(trackerRow, "Show it", function(checked)
        SettingsUI:SetTrackerShown(checked)
    end, true)
    controls.tracker:SetPoint("TOPLEFT", CONTROL_X, -2)

    local groupRow = CreateRow(frame, trackerRow, "In a group",
        "Moves the panel beside the party and raid frames. Drag it in a "
        .. "group to pick a spot.")

    controls.dodgeGroup = Widgets.CreateCheckbox(groupRow, "Move aside", function(checked)
        ns.TrackerUI:SetDodgeGroup(checked)
    end, true)
    controls.dodgeGroup:SetPoint("TOPLEFT", CONTROL_X, -2)

    local reportRow = CreateRow(frame, groupRow, "Chat report",
        "One line per kill in your own chat window. Nobody else can see it.")

    controls.report = Widgets.CreateCheckbox(reportRow, "Report kills", function(checked)
        ns.db.trackerReport = checked
    end, false)
    controls.report:SetPoint("TOPLEFT", CONTROL_X, -2)

    local announceRow = CreateRow(frame, reportRow, "Share milestones",
        "A mob's 20th kill, a fishing spot's 20th cast or a node's 20th gather: "
        .. "an /emote players near you see. Your chat always gets it.")

    controls.announce = Widgets.CreateCheckbox(announceRow, "Emote it", function(checked)
        ns.db.trackerAnnounce = checked
    end, true)
    controls.announce:SetPoint("TOPLEFT", CONTROL_X, -2)

    local rareRow = CreateRow(frame, announceRow, "Rare drop sound",
        "A chime when something green or better drops. Only you hear it.")

    controls.rareSound = Widgets.CreateCheckbox(rareRow, "Play it", function(checked)
        ns.db.trackerRareSound = checked
    end, true)
    controls.rareSound:SetPoint("TOPLEFT", CONTROL_X, -2)

    local recording = CreateSection(frame, "LOOT RECORDING", { anchor = rareRow })

    local recordRow = CreateRow(frame, recording, "Record what drops",
        "Counts what every corpse held, so drop rates are measured on Forever. "
        .. "Kept on this computer only.")

    controls.record = Widgets.CreateCheckbox(recordRow, "Recording", function(checked)
        SettingsUI:SetRecording(checked)
    end, true)
    controls.record:SetPoint("TOPLEFT", CONTROL_X, -2)

    self.recordRow = recordRow

    local summary = Theme.CreateLabel(frame, "small", "text")
    summary:SetPoint("TOPLEFT", recordRow, "BOTTOMLEFT", 0, -4)
    summary:SetWidth(COLUMN_WIDTH)
    self.harvestSummary = summary

    local export = Widgets.CreateButton(frame, "Export", function()
        ns.UI:ShowExport(ns.Harvest:ExportAll(), "Export: everything harvested")
    end, { width = 80, height = 20 })
    export:SetPoint("TOPLEFT", summary, "BOTTOMLEFT", 0, -8)

    -- Kept to the column beside the button, on two lines if the font needs
    -- them: on one it ran past the window's right edge.
    local exportHint = Theme.CreateLabel(frame, "tiny", "dim")
    exportHint:SetPoint("LEFT", export, "RIGHT", 8, 0)
    exportHint:SetWidth(COLUMN_WIDTH - export:GetWidth() - 8)
    exportHint:SetWordWrap(true)
    exportHint:SetText("Your recorded loot, as a data file.")
    self.exportHint = exportHint

    -- Under the export button, in the room the right column has spare.
    export.column = COLUMN_TWO_X
    local tooltips = CreateSection(frame, "TOOLTIPS", { anchor = export })

    local tooltipRow = CreateRow(frame, tooltips, "Where to farm",
        "Hover a material for the best place to farm it from where you stand. "
        .. "Same as /farm tooltip.")

    controls.itemTooltip = Widgets.CreateCheckbox(tooltipRow, "Show it", function(checked)
        ns.db.itemTooltip = checked
        if ns.ItemTooltip then ns.ItemTooltip.ForgetKept() end
    end, true)
    controls.itemTooltip:SetPoint("TOPLEFT", CONTROL_X, -2)
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
    controls.trackerScale:SetValue(db.trackerScale or 100, true)
    controls.debug:SetChecked(db.debug == true)
    controls.markersWorld:SetChecked(db.markersWorld ~= false)
    controls.markersMinimap:SetChecked(db.markersMinimap ~= false)
    controls.itemTooltip:SetChecked(db.itemTooltip ~= false)

    controls.tracker:SetChecked(not db.trackerHidden)
    controls.dodgeGroup:SetChecked(db.trackerDodgeGroup ~= false)
    controls.report:SetChecked(db.trackerReport == true)
    controls.announce:SetChecked(db.trackerAnnounce ~= false)

    local level = ns.TrackerFX.Level()
    for index, name in ipairs(ns.TrackerFX.LEVELS) do
        if name == level then controls.effects:SetValue(index, true) end
    end
    controls.rareSound:SetChecked(ns.TrackerFX.RareSoundOn())

    local usable = ns.Harvest:Capabilities().usable

    controls.record:SetChecked(usable and not db.harvestPaused)
    controls.record:SetDisabled(not usable)

    if not usable then
        self.recordRow.hint:SetText("This client does not let addons read the loot window, "
            .. "so nothing can be recorded.")
    end

    local corpses = ns.Harvest:CountCorpses()

    if corpses == 0 then
        self.harvestSummary:SetText(Util.Colored("muted", "Nothing recorded yet."))
    else
        self.harvestSummary:SetText(("%s recorded from %s."):format(
            Util.Plural(corpses, "corpse"), Util.Plural(ns.Harvest:CountMobs(), "mob")))
    end
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
        -- Close the game's panel first, or the two windows sit on top of one
        -- another fighting for the keyboard.
        if SettingsPanel and HideUIPanel then
            pcall(HideUIPanel, SettingsPanel)
        end
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
