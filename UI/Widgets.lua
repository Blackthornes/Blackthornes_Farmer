-- Blackthornes Farmer -- UI/Widgets.lua
-- The three controls this addon needs: a button, a search box, and a list of
-- text lines that recycles its rows.

local _, ns = ...

local Widgets = {}
ns.Widgets = Widgets

local Theme = ns.Theme

--------------------------------------------------------------------------------
-- Button
--------------------------------------------------------------------------------

function Widgets.CreateButton(parent, text, onClick, opts)
    opts = opts or {}

    local button = CreateFrame("Button", nil, parent)
    button:SetSize(opts.width or 80, opts.height or 22)

    button.background = Theme.Fill(button, "row")
    Theme.Border(button, "border")

    button.label = Theme.CreateLabel(button, "small", "text", "CENTER")
    button.label:SetPoint("CENTER")
    button.label:SetText(text)

    button:SetScript("OnEnter", function(self)
        self.background:SetColorTexture(Theme.Unpack("rowHover"))
    end)

    button:SetScript("OnLeave", function(self)
        self.background:SetColorTexture(Theme.Unpack("row"))
    end)

    if onClick then
        button:SetScript("OnClick", function(self, mouseButton)
            onClick(self, mouseButton)
        end)
    end

    function button:SetText(value)
        self.label:SetText(value)
    end

    return button
end

--------------------------------------------------------------------------------
-- Search box
--------------------------------------------------------------------------------

--- An edit box with placeholder text.
--
-- onChange fires on every keystroke so results follow typing; onAccept fires on
-- Enter. Escape clears focus rather than the text, because losing what you
-- typed on a mis-key is worse than an extra keystroke.
function Widgets.CreateSearchBox(parent, placeholder, onChange, onAccept)
    local holder = Theme.CreatePanel(parent, "row", "border")
    holder:SetHeight(24)

    local box = CreateFrame("EditBox", nil, holder)
    box:SetPoint("TOPLEFT", 8, 0)
    box:SetPoint("BOTTOMRIGHT", -8, 0)
    box:SetAutoFocus(false)
    box:SetFont(Theme.FONT, Theme.sizes.normal, "")
    box:SetTextColor(Theme.Unpack("text"))
    box:SetMaxLetters(80)

    local hint = Theme.CreateLabel(holder, "normal", "dim")
    hint:SetPoint("LEFT", 8, 0)
    hint:SetText(placeholder or "")

    local function UpdateHint()
        hint:SetShown(box:GetText() == "")
    end

    box:SetScript("OnTextChanged", function(self, userInput)
        UpdateHint()
        if userInput and onChange then
            onChange(self:GetText())
        end
    end)

    box:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
        if onAccept then onAccept(self:GetText()) end
    end)

    box:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)

    holder.editBox = box

    function holder:SetText(value)
        box:SetText(value or "")
        UpdateHint()
    end

    function holder:GetText()
        return box:GetText()
    end

    function holder:SetFocus()
        box:SetFocus()
    end

    UpdateHint()
    return holder
end

--------------------------------------------------------------------------------
-- Line list
--------------------------------------------------------------------------------

--- A scrolling list of preformatted text lines.
--
-- Distinct from the tradeskills addon's CreateScrollList, which recycles rows
-- of columns: results here are already formatted strings of varying shape --
-- an item heading, a note, a source -- so a row is one label and the list only
-- has to decide which lines are on screen.
function Widgets.CreateLineList(parent, opts)
    opts = opts or {}

    local list = CreateFrame("Frame", nil, parent)
    local rowHeight = opts.rowHeight or 15

    list.lines = {}
    list.rows = {}
    list.offset = 0

    local scrollbar = CreateFrame("Slider", nil, list)
    scrollbar:SetOrientation("VERTICAL")
    scrollbar:SetWidth(8)
    scrollbar:SetPoint("TOPRIGHT", 0, 0)
    scrollbar:SetPoint("BOTTOMRIGHT", 0, 0)
    scrollbar:SetValueStep(1)
    scrollbar:SetObeyStepOnDrag(true)

    local track = scrollbar:CreateTexture(nil, "BACKGROUND")
    track:SetAllPoints(scrollbar)
    track:SetColorTexture(Theme.Unpack("panel"))

    local thumb = scrollbar:CreateTexture(nil, "ARTWORK")
    thumb:SetColorTexture(Theme.Unpack("border"))
    thumb:SetSize(8, 40)
    scrollbar:SetThumbTexture(thumb)

    list.scrollbar = scrollbar

    local function VisibleRowCount()
        local height = list:GetHeight()
        if not height or height <= 0 then return 0 end
        return math.floor(height / rowHeight)
    end

    local function AcquireRow(index)
        local row = list.rows[index]
        if row then return row end

        row = Theme.CreateLabel(list, opts.size or "small", "text")
        row:SetHeight(rowHeight)
        row:SetPoint("TOPLEFT", 0, -(index - 1) * rowHeight)
        row:SetPoint("RIGHT", scrollbar, "LEFT", -6, 0)

        list.rows[index] = row
        return row
    end

    function list:MaxOffset()
        return math.max(0, #self.lines - VisibleRowCount())
    end

    function list:Refresh()
        local visible = VisibleRowCount()
        local maxOffset = self:MaxOffset()

        if self.offset > maxOffset then self.offset = maxOffset end
        if self.offset < 0 then self.offset = 0 end

        for index = 1, visible do
            local row = AcquireRow(index)
            row:SetText(self.lines[index + self.offset] or "")
            row:Show()
        end

        -- Rows built for a taller window stay allocated but must not linger.
        for index = visible + 1, #self.rows do
            self.rows[index]:Hide()
        end

        scrollbar:SetMinMaxValues(0, maxOffset)
        scrollbar:SetValue(self.offset)
        scrollbar:SetShown(maxOffset > 0)

        if opts.onRefresh then
            opts.onRefresh(self, #self.lines, visible)
        end
    end

    function list:SetLines(lines)
        self.lines = lines or {}
        self.offset = 0
        self:Refresh()
    end

    function list:Scroll(delta)
        self.offset = self.offset - (delta * 3)
        self:Refresh()
    end

    scrollbar:SetScript("OnValueChanged", function(_, value)
        local wanted = math.floor(value + 0.5)
        if wanted ~= list.offset then
            list.offset = wanted
            list:Refresh()
        end
    end)

    list:EnableMouseWheel(true)
    list:SetScript("OnMouseWheel", function(_, delta)
        list:Scroll(delta)
    end)

    return list
end

--------------------------------------------------------------------------------
-- Row list
--------------------------------------------------------------------------------

--- A scrolling list that recycles row frames.
--
-- Where CreateLineList draws one label per line, this gives each row a set of
-- children the caller builds once and fills per row, which is what a table of
-- columns needs. Only the rows on screen exist, so the length of the data does
-- not change the cost of drawing it.
--
-- @param opts
--   rowHeight  pixel height of one row
--   createRow  function(row)            -- build the row's children once
--   updateRow  function(row, data, i)   -- fill a row with data
--   onClick    function(data, button)
--   onRefresh  function(list, shown, visible)
function Widgets.CreateRowList(parent, opts)
    opts = opts or {}

    local list = CreateFrame("Frame", nil, parent)
    local rowHeight = opts.rowHeight or 20

    list.data = {}
    list.rows = {}
    list.offset = 0

    local scrollbar = CreateFrame("Slider", nil, list)
    scrollbar:SetOrientation("VERTICAL")
    scrollbar:SetWidth(8)
    scrollbar:SetPoint("TOPRIGHT", 0, 0)
    scrollbar:SetPoint("BOTTOMRIGHT", 0, 0)
    scrollbar:SetValueStep(1)
    scrollbar:SetObeyStepOnDrag(true)

    local track = scrollbar:CreateTexture(nil, "BACKGROUND")
    track:SetAllPoints(scrollbar)
    track:SetColorTexture(Theme.Unpack("panel"))

    local thumb = scrollbar:CreateTexture(nil, "ARTWORK")
    thumb:SetColorTexture(Theme.Unpack("borderLit"))
    thumb:SetSize(8, 40)
    scrollbar:SetThumbTexture(thumb)

    list.scrollbar = scrollbar

    local function VisibleRowCount()
        local height = list:GetHeight()
        if not height or height <= 0 then return 0 end
        return math.floor(height / rowHeight)
    end

    local function AcquireRow(index)
        local row = list.rows[index]
        if row then return row end

        row = CreateFrame("Button", nil, list)
        row:SetHeight(rowHeight)
        row:SetPoint("TOPLEFT", 0, -(index - 1) * rowHeight)
        row:SetPoint("RIGHT", scrollbar, "LEFT", -6, 0)
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")

        row.stripe = Theme.Fill(row, "rowAlt", 0)
        row.highlight = Theme.Fill(row, "rowHover", 0, "BORDER")

        if opts.createRow then
            opts.createRow(row)
        end

        row:SetScript("OnEnter", function(self)
            if self.data and self.data.type ~= "spacer" then
                self.highlight:SetAlpha(0.6)
            end
        end)

        row:SetScript("OnLeave", function(self)
            self.highlight:SetAlpha(0)
        end)

        row:SetScript("OnClick", function(self, button)
            if self.data and opts.onClick then
                opts.onClick(self.data, button)
            end
        end)

        list.rows[index] = row
        return row
    end

    function list:MaxOffset()
        return math.max(0, #self.data - VisibleRowCount())
    end

    function list:Refresh()
        local visible = VisibleRowCount()
        local maxOffset = self:MaxOffset()

        if self.offset > maxOffset then self.offset = maxOffset end
        if self.offset < 0 then self.offset = 0 end

        for index = 1, visible do
            local row = AcquireRow(index)
            local data = self.data[index + self.offset]

            row.data = data
            row.dataIndex = index + self.offset
            row.highlight:SetAlpha(0)

            if data then
                -- Banding follows the row's place on screen rather than its
                -- index in the data, so the stripes do not crawl as you scroll.
                row.stripe:SetAlpha(index % 2 == 0 and 0.5 or 0)

                if opts.updateRow then
                    opts.updateRow(row, data, index + self.offset)
                end

                row:Show()
            else
                row:Hide()
            end
        end

        for index = visible + 1, #self.rows do
            self.rows[index]:Hide()
        end

        scrollbar:SetMinMaxValues(0, maxOffset)
        scrollbar:SetValue(self.offset)
        scrollbar:SetShown(maxOffset > 0)

        if opts.onRefresh then
            opts.onRefresh(self, #self.data, visible)
        end
    end

    function list:SetData(data)
        self.data = data or {}
        self.offset = 0
        self:Refresh()
    end

    function list:Scroll(delta)
        self.offset = self.offset - (delta * 3)
        self:Refresh()
    end

    scrollbar:SetScript("OnValueChanged", function(_, value)
        local wanted = math.floor(value + 0.5)
        if wanted ~= list.offset then
            list.offset = wanted
            list:Refresh()
        end
    end)

    list:EnableMouseWheel(true)
    list:SetScript("OnMouseWheel", function(_, delta)
        list:Scroll(delta)
    end)

    return list
end

--------------------------------------------------------------------------------
-- Filter chip
--------------------------------------------------------------------------------

--- A small toggle used in a row of filters. Selected chips carry the accent.
function Widgets.CreateChip(parent, text, onClick)
    local chip = CreateFrame("Button", nil, parent)
    chip:SetHeight(18)

    chip.background = Theme.Fill(chip, "row")
    Theme.Border(chip, "border")

    chip.label = Theme.CreateLabel(chip, "tiny", "muted", "CENTER")
    chip.label:SetPoint("CENTER")
    chip.label:SetText(text)

    -- Sized to its text, so a row of chips packs tightly whatever the labels.
    chip:SetWidth(math.max(34, (chip.label:GetStringWidth() or 30) + 16))

    -- The All chip holds false; everything else holds a kind. Either way the
    -- caller gets nil or a string back, never an absent field.
    function chip:GetFilterKind()
        return self.filterKind or nil
    end

    function chip:SetSelected(selected)
        self.selected = selected and true or false

        if self.selected then
            self.background:SetColorTexture(Theme.Unpack("accent", 0.22))
            self.label:SetTextColor(Theme.Unpack("accent"))
        else
            self.background:SetColorTexture(Theme.Unpack("row"))
            self.label:SetTextColor(Theme.Unpack("muted"))
        end
    end

    chip:SetScript("OnEnter", function(self)
        if not self.selected then
            self.background:SetColorTexture(Theme.Unpack("rowHover"))
        end
    end)

    chip:SetScript("OnLeave", function(self)
        self:SetSelected(self.selected)
    end)

    chip:SetScript("OnClick", function(self)
        if onClick then onClick(self) end
    end)

    chip:SetSelected(false)
    return chip
end

--------------------------------------------------------------------------------
-- Checkbox
--------------------------------------------------------------------------------

--- A square toggle with its label beside it. Ported from the tradeskills addon
--- so the two settings pages feel the same under the mouse.
function Widgets.CreateCheckbox(parent, text, onToggle, initial)
    local checkbox = CreateFrame("Button", nil, parent)
    checkbox:SetHeight(18)

    local box = CreateFrame("Frame", nil, checkbox)
    box:SetSize(14, 14)
    box:SetPoint("LEFT")
    box.background = Theme.Fill(box, "row")
    Theme.Border(box, "border")

    local tick = box:CreateTexture(nil, "OVERLAY")
    tick:SetPoint("CENTER")
    tick:SetSize(8, 8)
    tick:SetColorTexture(Theme.Unpack("accent"))

    local label = Theme.CreateLabel(checkbox, "small", "text")
    label:SetPoint("LEFT", box, "RIGHT", 6, 0)
    label:SetText(text)

    checkbox.label = label
    checkbox:SetWidth((label:GetStringWidth() or 60) + 24)
    checkbox.checked = initial and true or false
    checkbox.disabled = false
    tick:SetShown(checkbox.checked)

    function checkbox:SetChecked(value)
        self.checked = value and true or false
        tick:SetShown(self.checked)
    end

    function checkbox:GetChecked()
        return self.checked
    end

    --- A disabled box keeps showing its state but ignores clicks, for a
    --- setting this client cannot honour.
    function checkbox:SetDisabled(disabled)
        self.disabled = disabled and true or false
        label:SetTextColor(Theme.Unpack(self.disabled and "dim" or "text"))
        tick:SetAlpha(self.disabled and 0.4 or 1)
    end

    checkbox:SetScript("OnClick", function(self)
        if self.disabled then return end
        self:SetChecked(not self.checked)
        if onToggle then onToggle(self.checked) end
    end)

    checkbox:SetScript("OnEnter", function(self)
        if not self.disabled then label:SetTextColor(Theme.Unpack("accent")) end
    end)

    checkbox:SetScript("OnLeave", function(self)
        label:SetTextColor(Theme.Unpack(self.disabled and "dim" or "text"))
    end)

    return checkbox
end

--------------------------------------------------------------------------------
-- Stepper
--------------------------------------------------------------------------------

--- [-] value [+], for a number with a small sensible range such as a scale.
--
-- Chosen over a slider: a slider on this client needs a thumb texture and a
-- drag to land on a round number, and a stepper only ever holds values from
-- its own list of steps.
--
-- @param opts
--   min, max, step  the range, in the stored unit
--   format          function(value) -> text shown between the buttons
--   onChange        function(value)
function Widgets.CreateStepper(parent, opts)
    opts = opts or {}

    local stepper = CreateFrame("Frame", nil, parent)
    stepper:SetSize(118, 20)

    local minus = Widgets.CreateButton(stepper, "-", nil, { width = 22, height = 20 })
    minus:SetPoint("LEFT")

    local plus = Widgets.CreateButton(stepper, "+", nil, { width = 22, height = 20 })
    plus:SetPoint("RIGHT")

    local well = Theme.CreatePanel(stepper, "panel", "border")
    well:SetPoint("LEFT", minus, "RIGHT", 4, 0)
    well:SetPoint("RIGHT", plus, "LEFT", -4, 0)
    well:SetHeight(20)

    local text = Theme.CreateLabel(well, "small", "text", "CENTER")
    text:SetPoint("CENTER")

    stepper.minus = minus
    stepper.plus = plus
    stepper.text = text

    local step = opts.step or 1
    local low = opts.min or 0
    local high = opts.max or 100

    local function Clamp(value)
        -- Snapped to a whole number of steps, so repeated presses never drift
        -- to 0.8999999 and show a value that is not on the list.
        value = low + math.floor((value - low) / step + 0.5) * step
        return math.max(low, math.min(high, value))
    end

    function stepper:SetValue(value, silent)
        self.value = Clamp(tonumber(value) or low)
        text:SetText(opts.format and opts.format(self.value) or tostring(self.value))

        minus.label:SetTextColor(Theme.Unpack(self.value <= low and "dim" or "text"))
        plus.label:SetTextColor(Theme.Unpack(self.value >= high and "dim" or "text"))

        if not silent and opts.onChange then opts.onChange(self.value) end
    end

    function stepper:GetValue()
        return self.value
    end

    local function Nudge(direction)
        local wanted = Clamp((stepper.value or low) + direction * step)
        if wanted ~= stepper.value then stepper:SetValue(wanted) end
    end

    minus:SetScript("OnClick", function() Nudge(-1) end)
    plus:SetScript("OnClick", function() Nudge(1) end)

    stepper:SetValue(opts.value or low, true)
    return stepper
end
