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
