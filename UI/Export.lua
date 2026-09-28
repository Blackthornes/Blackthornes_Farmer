-- Blackthornes Farmer -- UI/Export.lua
-- A window that hands text back to you so it can leave the game.
--
-- Why a window and not a file: an addon cannot write files. The harvest is
-- kept in SavedVariables, and tools/harvest_import.py reads it from outside;
-- this window is the way out that needs nothing but the game itself.
--
-- The text is selected the moment the window opens, so the whole interaction
-- is: run the command, press Ctrl+C, paste into your editor.

local _, ns = ...

local UI = ns.UI

local Theme = ns.Theme
local Widgets = ns.Widgets

local WIDTH = 560
local HEIGHT = 420
local PADDING = 14

--------------------------------------------------------------------------------
-- Construction
--------------------------------------------------------------------------------

function UI:BuildExport()
    if self.exportFrame then return self.exportFrame end

    local frame = CreateFrame("Frame", "BlackthornesFarmerExportFrame", UIParent)
    frame:SetSize(WIDTH, HEIGHT)
    frame:SetPoint("CENTER", 0, 20)
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")

    Theme.Fill(frame, "window")
    Theme.Border(frame, "borderLit")

    frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)

    self.exportFrame = frame

    -- Header.
    local header = Theme.CreatePanel(frame, "header", false)
    header:SetPoint("TOPLEFT")
    header:SetPoint("TOPRIGHT")
    header:SetHeight(32)
    Theme.HouseHeader(header)

    local title = Theme.CreateLabel(header, "large", "accent")
    title:SetPoint("LEFT", PADDING, 0)
    title:SetText("Export")
    self.exportTitle = title

    local close = Widgets.CreateButton(header, "X", function() UI:HideExport() end,
        { width = 22, height = 20, danger = true })
    close:SetPoint("RIGHT", -PADDING + 2, 0)

    local divider = Theme.CreateDivider(frame, "borderLit")
    divider:SetPoint("TOPLEFT", header, "BOTTOMLEFT")
    divider:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT")

    local hint = Theme.CreateLabel(frame, "small", "muted")
    hint:SetPoint("TOPLEFT", PADDING, -42)
    hint:SetPoint("TOPRIGHT", -PADDING, -42)
    hint:SetText("Already selected. Press Ctrl+C, then paste it into your editor.")

    -- The box itself.
    local panel = Theme.CreatePanel(frame, "panel", "border")
    panel:SetPoint("TOPLEFT", PADDING, -62)
    panel:SetPoint("BOTTOMRIGHT", -PADDING, 42)

    local scroll = CreateFrame("ScrollFrame", nil, panel)
    scroll:SetPoint("TOPLEFT", 8, -8)
    scroll:SetPoint("BOTTOMRIGHT", -24, 8)
    scroll:EnableMouseWheel(true)

    local edit = CreateFrame("EditBox", nil, scroll)
    edit:SetMultiLine(true)
    edit:SetAutoFocus(false)
    edit:SetMaxLetters(0)
    edit:SetFont(Theme.FONT, Theme.sizes.small, "")
    edit:SetTextColor(Theme.Unpack("text"))
    edit:SetWidth(WIDTH - PADDING * 2 - 34)
    edit:SetScript("OnEscapePressed", function() UI:HideExport() end)

    -- The text is a handout, not a form. Anything typed into it would be lost
    -- on the next export and would break a copy half-made, so put it back.
    edit:SetScript("OnTextChanged", function(self, userInput)
        if userInput and UI.exportText then
            self:SetText(UI.exportText)
            self:HighlightText()
        end
    end)

    scroll:SetScrollChild(edit)
    self.exportEdit = edit
    self.exportScroll = scroll

    local slider = CreateFrame("Slider", nil, panel)
    slider:SetPoint("TOPRIGHT", -8, -8)
    slider:SetPoint("BOTTOMRIGHT", -8, 8)
    slider:SetWidth(10)
    slider:SetOrientation("VERTICAL")
    slider:SetMinMaxValues(0, 0)
    slider:SetValue(0)
    slider:SetValueStep(1)
    slider:SetObeyStepOnDrag(true)
    Theme.Fill(slider, "row")

    local thumb = slider:CreateTexture(nil, "ARTWORK")
    thumb:SetColorTexture(Theme.Unpack("borderLit"))
    thumb:SetSize(10, 40)
    slider:SetThumbTexture(thumb)

    slider:SetScript("OnValueChanged", function(self, value)
        scroll:SetVerticalScroll(value)
    end)

    scroll:SetScript("OnScrollRangeChanged", function(self, _, vertical)
        vertical = vertical or self:GetVerticalScrollRange() or 0
        slider:SetMinMaxValues(0, math.max(vertical, 0))
        if slider:GetValue() > vertical then slider:SetValue(vertical) end
    end)

    scroll:SetScript("OnMouseWheel", function(self, delta)
        slider:SetValue(slider:GetValue() - delta * 40)
    end)

    self.exportSlider = slider

    -- Footer buttons.
    local selectAll = Widgets.CreateButton(frame, "Select all", function()
        UI:FocusExport()
    end, { width = 90, height = 22 })
    selectAll:SetPoint("BOTTOMLEFT", PADDING, 12)

    local done = Widgets.CreateButton(frame, "Close", function() UI:HideExport() end,
        { width = 70, height = 22 })
    done:SetPoint("BOTTOMRIGHT", -PADDING, 12)

    local count = Theme.CreateLabel(frame, "tiny", "dim", "RIGHT")
    count:SetPoint("BOTTOMRIGHT", done, "BOTTOMLEFT", -10, 4)
    count:SetWidth(240)
    self.exportCount = count

    frame:Hide()
    return frame
end

--------------------------------------------------------------------------------
-- Showing
--------------------------------------------------------------------------------

--- Put the edit box's whole contents under the cursor, ready for Ctrl+C.
function UI:FocusExport()
    local edit = self.exportEdit
    if not edit then return end

    edit:SetFocus()
    edit:HighlightText()
end

--- Show `text` in the export window.
--
-- `title` is optional and names what is being handed over, so a single-item
-- export and a whole-session export do not look identical.
function UI:ShowExport(text, title)
    text = tostring(text or "")

    self:BuildExport()

    self.exportText = text
    self.exportTitle:SetText(title or "Export")

    self.exportEdit:SetText(text)
    self.exportEdit:SetCursorPosition(0)
    self.exportScroll:SetVerticalScroll(0)
    self.exportSlider:SetValue(0)

    local lines = 1
    for _ in text:gmatch("\n") do lines = lines + 1 end
    self.exportCount:SetText(("%d lines, %d characters"):format(lines, #text))

    if not self.exportFrame:IsShown() then
        self.exportFrame:Show()
        ns.Motion:Open(self.exportFrame)
    end

    -- One frame later: the edit box has to have laid out its text before
    -- highlighting it covers the whole thing.
    if C_Timer and C_Timer.After then
        C_Timer.After(0, function() UI:FocusExport() end)
    else
        self:FocusExport()
    end

    return self.exportFrame
end

function UI:HideExport()
    if not self.exportFrame then return end

    if self.exportEdit then
        self.exportEdit:ClearFocus()
    end

    self.exportFrame:Hide()
end

function UI:ToggleExport(text, title)
    if self.exportFrame and self.exportFrame:IsShown() then
        self:HideExport()
    else
        self:ShowExport(text, title)
    end
end
