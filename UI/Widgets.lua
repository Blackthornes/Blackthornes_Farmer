-- Blackthornes Farmer -- UI/Widgets.lua
-- The three controls this addon needs: a button, a search box, and a list of
-- text lines that recycles its rows.

local _, ns = ...

local Widgets = {}
ns.Widgets = Widgets

local Theme = ns.Theme

--------------------------------------------------------------------------------
-- Motion
--
-- Small tweens for the windows and controls: a button easing into its hover
-- colour, a window fading up as it opens, rows arriving one after another.
-- The kills panel and the goals panel keep their own clocks (TrackerFX,
-- GoalsUI); this one is for everything else, and follows the same
-- /farm effects setting. Off means every tween lands at its end at once.
--
-- One OnUpdate on one small frame, shown only while something is moving, so
-- an idle window costs nothing per frame. A tween that errors is dropped
-- rather than raised: a hover colour must never break a click.
--------------------------------------------------------------------------------

local Motion = {}
ns.Motion = Motion

Motion.tweens = {}

--- "full", "subtle" or "off", from the /farm effects setting.
function Motion.Level()
    if ns.TrackerFX and ns.TrackerFX.Level then return ns.TrackerFX.Level() end
    return "full"
end

function Motion.EaseOut(p)
    return 1 - (1 - p) ^ 3
end

--- Overshoots a touch and settles, for things that should feel like they
--- landed.
function Motion.EaseOutBack(p)
    local c = 1.4
    return 1 + (c + 1) * (p - 1) ^ 3 + c * (p - 1) ^ 2
end

function Motion.Lerp(from, to, p)
    return from + (to - from) * p
end

--- Two palette colours mixed, `p` of the way from `a` to `b`.
function Motion.Mix(a, b, p, alphaA, alphaB)
    local r1, g1, b1, a1 = Theme.Unpack(a, alphaA)
    local r2, g2, b2, a2 = Theme.Unpack(b, alphaB)
    return r1 + (r2 - r1) * p, g1 + (g2 - g1) * p, b1 + (b2 - b1) * p, a1 + (a2 - a1) * p
end

function Motion:Driver()
    if self.driver then return self.driver end

    local driver = CreateFrame("Frame", nil, UIParent)
    driver:SetScript("OnUpdate", function(_, elapsed) Motion:Step(elapsed) end)
    driver:Hide()

    self.driver = driver
    return driver
end

local function Finish(tween)
    pcall(tween.apply, 1)
    if tween.done then pcall(tween.done) end
end

--- Run `apply(p)` with p going 0 to 1 over `duration` seconds.
--
-- `owner` and `slot` name the tween: a new one for the same owner and slot
-- replaces the old, so hovering on and off quickly never leaves two fighting.
-- opts: delay (seconds before it starts), done (called at the end), ease
-- (a function of p; EaseOut unless given, false for linear).
function Motion:Run(owner, slot, duration, apply, opts)
    opts = opts or {}

    self:Stop(owner, slot)

    local tween = { owner = owner, slot = slot, duration = duration or 0.2,
        apply = apply, done = opts.done, age = -(opts.delay or 0) }

    local ease = opts.ease
    if ease == nil then ease = Motion.EaseOut end
    tween.ease = ease or nil

    if self.Level() == "off" or tween.duration <= 0 then
        Finish(tween)
        return
    end

    -- Drawn at its start now, so nothing flashes at its end for a frame
    -- before the first step.
    pcall(apply, 0)

    self.tweens[#self.tweens + 1] = tween
    self:Driver():Show()
end

--- Stop a running tween where it is. `finish` lands it at its end first.
function Motion:Stop(owner, slot, finish)
    for index = #self.tweens, 1, -1 do
        local tween = self.tweens[index]
        if tween.owner == owner and (slot == nil or tween.slot == slot) then
            table.remove(self.tweens, index)
            if finish then Finish(tween) end
        end
    end
end

--- Whether a tween is running for this owner (and slot, when given).
function Motion:Running(owner, slot)
    for _, tween in ipairs(self.tweens) do
        if tween.owner == owner and (slot == nil or tween.slot == slot) then return true end
    end
    return false
end

--- Land every running tween at its end. For the tests, and for a window
--- being hidden mid-animation.
function Motion:FinishAll()
    local tweens = self.tweens
    self.tweens = {}
    for _, tween in ipairs(tweens) do Finish(tween) end
    if self.driver then self.driver:Hide() end
end

function Motion:Step(elapsed)
    elapsed = tonumber(elapsed) or 0

    local live = {}
    local tweens = self.tweens
    self.tweens = live

    for _, tween in ipairs(tweens) do
        tween.age = tween.age + elapsed

        if tween.age >= 0 then
            local p = math.min(1, tween.age / tween.duration)
            local eased = tween.ease and tween.ease(p) or p
            local ok = pcall(tween.apply, eased)

            if not ok or p >= 1 then
                if ok and tween.done then pcall(tween.done) end
            else
                live[#live + 1] = tween
            end
        else
            live[#live + 1] = tween
        end
    end

    -- Tweens started from inside an apply or done landed in `live` already.
    if #self.tweens == 0 and self.driver then self.driver:Hide() end
end

--- Ease a number kept on `owner` toward `target`, calling `apply(value)` as
--- it goes. Starts from wherever the last one left it, so a hover that is
--- undone halfway turns round smoothly instead of jumping.
function Motion:Blend(owner, slot, target, duration, apply)
    local from = self:Value(owner, slot)
    if from == target and not self:Running(owner, slot) then
        apply(target)
        return
    end

    self:Run(owner, slot, duration, function(p)
        local value = from + (target - from) * p
        self:SetValue(owner, slot, value)
        apply(value)
    end, { ease = false })
end

-- Blended values, kept here rather than as fields on the frames so they never
-- collide with a frame's own keys.
Motion.values = setmetatable({}, { __mode = "k" })

--- Where Blend last left `owner`'s `slot`: 0 until it has moved.
function Motion:Value(owner, slot)
    local values = self.values[owner]
    return values and values[slot] or 0
end

function Motion:SetValue(owner, slot, value)
    local values = self.values[owner]
    if not values then
        values = {}
        self.values[owner] = values
    end
    values[slot] = value
end

--- Fade a window up as it opens: from clear, and a few pixels low.
--
-- Only the alpha and one point's offset move, so the window's saved spot is
-- never touched: the last step puts back exactly the point it started with.
function Motion:Open(frame, rise)
    if not frame then return end

    local level = self.Level()
    if level == "off" then
        frame:SetAlpha(1)
        return
    end

    rise = level == "full" and (rise or 8) or 0

    local point, relativeTo, relativePoint, x, y = frame:GetPoint(1)
    local canMove = rise ~= 0 and point ~= nil and type(x) == "number" and type(y) == "number"

    self:Run(frame, "open", level == "full" and 0.2 or 0.12, function(p)
        frame:SetAlpha(p)
        if canMove then
            frame:SetPoint(point, relativeTo, relativePoint, x, y - rise * (1 - p))
        end
    end)
end

--------------------------------------------------------------------------------
-- Button
--------------------------------------------------------------------------------

local HOVER_TIME = 0.12

--- A flat button in the house style.
--
-- opts: width, height; primary (gold-tinted, gold edge, gold text, for the
-- one button on a screen that does the main thing); danger (lights red under
-- the mouse, for a close button); labelKey (the label's resting colour).
function Widgets.CreateButton(parent, text, onClick, opts)
    opts = opts or {}

    local button = CreateFrame("Button", nil, parent)
    button:SetSize(opts.width or 80, opts.height or 22)

    local baseKey = opts.primary and "rowActive" or "row"
    local edgeKey = opts.primary and "accent" or "border"
    local edgeAlpha = opts.primary and 0.55 or 1
    local hotEdge = (opts.danger and "loss") or (opts.primary and "accent") or "borderLit"
    local labelKey = opts.labelKey or (opts.primary and "accent") or "text"

    button.background = Theme.Fill(button, baseKey)
    Theme.Border(button, edgeKey, opts.primary and edgeAlpha or nil)
    button.sheen = Theme.TopSheen(button)

    button.label = Theme.CreateLabel(button, "small", labelKey, "CENTER")
    button.label:SetPoint("CENTER")
    button.label:SetText(text)

    -- Never narrower than its text: the game's font runs wider than a width
    -- picked by eye.
    local function Fit(value)
        button:SetWidth(math.max(opts.width or 80, Theme.TextWidth("small", value) + 12))
    end
    Fit(text)

    --- How lit the button is: 0 at rest, 1 under the mouse.
    local function Light(p)
        button.background:SetColorTexture(Motion.Mix(baseKey, "rowHover", p))

        local r, g, b, a = Motion.Mix(edgeKey, hotEdge, p, edgeAlpha, 1)
        for _, edge in ipairs(button.borderTextures or {}) do
            edge:SetColorTexture(r, g, b, a)
        end

        if opts.danger then
            button.label:SetTextColor(Motion.Mix(labelKey, "loss", p))
        end
    end
    button.Light = Light

    button:SetScript("OnEnter", function(self)
        Motion:Blend(self, "hover", 1, HOVER_TIME, Light)
    end)

    button:SetScript("OnLeave", function(self)
        Motion:Blend(self, "hover", 0, HOVER_TIME * 1.5, Light)
    end)

    -- The label dips a pixel while held, so a click feels pressed. Wherever
    -- the label was put (a caller may have moved it beside an icon), it
    -- goes back to exactly there.
    button:SetScript("OnMouseDown", function(self)
        local point, relativeTo, relativePoint, x, y = self.label:GetPoint(1)
        if not (point and type(x) == "number" and type(y) == "number") then return end

        self.restPoint = { point, relativeTo, relativePoint, x, y }
        self.label:SetPoint(point, relativeTo, relativePoint, x, y - 1)
    end)

    button:SetScript("OnMouseUp", function(self)
        local rest = rawget(self, "restPoint")
        if not rest then return end

        self.restPoint = nil
        self.label:SetPoint(rest[1], rest[2], rest[3], rest[4], rest[5])
    end)

    if onClick then
        button:SetScript("OnClick", function(self, mouseButton)
            onClick(self, mouseButton)
        end)
    end

    function button:SetText(value)
        self.label:SetText(value)
        Fit(value)
    end

    --- The label's resting colour, for a button whose text means something
    --- (a goal's "23/40" in gold).
    function button:SetLabelColor(key)
        labelKey = key
        self.label:SetTextColor(Theme.Unpack(key))
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
    Theme.TopSheen(holder, 0.04)

    -- The game's own magnifier, so the box reads as search at a glance.
    local icon = holder:CreateTexture(nil, "ARTWORK")
    icon:SetSize(14, 14)
    icon:SetPoint("LEFT", 7, 0)
    icon:SetTexture([[Interface\Common\UI-Searchbox-Icon]])
    icon:SetVertexColor(Theme.Unpack("muted"))
    holder.icon = icon

    local box = CreateFrame("EditBox", nil, holder)
    box:SetPoint("TOPLEFT", 26, 0)
    box:SetPoint("BOTTOMRIGHT", -26, 0)
    box:SetAutoFocus(false)
    box:SetFont(Theme.FONT, Theme.sizes.normal, "")
    box:SetTextColor(Theme.Unpack("text"))
    box:SetMaxLetters(80)

    local hint = Theme.CreateLabel(holder, "normal", "dim")
    hint:SetPoint("LEFT", 26, 0)
    hint:SetText(placeholder or "")

    -- Clears what you typed in one click, and only shows when there is
    -- something to clear.
    local clear = CreateFrame("Button", nil, holder)
    clear:SetSize(20, 20)
    clear:SetPoint("RIGHT", -3, 0)
    local cross = Theme.CreateLabel(clear, "normal", "muted", "CENTER")
    cross:SetPoint("CENTER", 0, 0)
    cross:SetText("x")
    clear:SetScript("OnEnter", function() cross:SetTextColor(Theme.Unpack("text")) end)
    clear:SetScript("OnLeave", function() cross:SetTextColor(Theme.Unpack("muted")) end)
    clear:Hide()
    holder.clear = clear

    local function UpdateHint()
        local empty = box:GetText() == ""
        hint:SetShown(empty)
        clear:SetShown(not empty)
    end

    --- Gold edge and a brighter magnifier while it has the keyboard.
    local function Focus(p)
        local r, g, b, a = Motion.Mix("border", "accent", p, 1, 0.8)
        for _, edge in ipairs(holder.borderTextures or {}) do edge:SetColorTexture(r, g, b, a) end
        icon:SetVertexColor(Motion.Mix("muted", "accent", p))
    end

    box:SetScript("OnEditFocusGained", function()
        Motion:Blend(holder, "focus", 1, 0.15, Focus)
    end)

    box:SetScript("OnEditFocusLost", function()
        Motion:Blend(holder, "focus", 0, 0.2, Focus)
    end)

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

    clear:SetScript("OnClick", function()
        box:SetText("")
        UpdateHint()
        if onChange then onChange("") end
        box:SetFocus()
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

    function holder:ClearFocus()
        box:ClearFocus()
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
--   onEnter    function(row, data)      -- the mouse came onto a row
--   onLeave    function(row)
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

        -- A thin gold edge on the row under the mouse, easing in with the
        -- highlight, so your place in a long list is easy to keep.
        row.edge = row:CreateTexture(nil, "OVERLAY")
        row.edge:SetPoint("TOPLEFT")
        row.edge:SetPoint("BOTTOMLEFT")
        row.edge:SetWidth(2)
        row.edge:SetColorTexture(Theme.Unpack("accent"))
        row.edge:SetAlpha(0)

        if opts.createRow then
            opts.createRow(row)
        end

        local function Lit(value)
            row.highlight:SetAlpha(0.6 * value)
            row.edge:SetAlpha(value)
        end

        -- Callers hook hovering through opts rather than HookScript on the
        -- row: SetScript here would replace a hook set in createRow.
        row:SetScript("OnEnter", function(self)
            if self.data and self.data.type ~= "spacer" then
                Motion:Blend(self, "hover", 1, 0.08, Lit)
            end
            if self.data and opts.onEnter then opts.onEnter(self, self.data) end
        end)

        row:SetScript("OnLeave", function(self)
            Motion:Blend(self, "hover", 0, 0.18, Lit)
            if opts.onLeave then opts.onLeave(self) end
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

            -- A row handed new data under a still mouse starts unlit; the
            -- next OnEnter lights it again.
            Motion:Stop(row, "hover")
            Motion:SetValue(row, "hover", 0)
            row.highlight:SetAlpha(0)
            row.edge:SetAlpha(0)

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

    --- Bring the rows on screen in one after another, top down: a new set
    --- of results arriving rather than appearing. Full effects only.
    function list:Arrive()
        if Motion.Level() ~= "full" then return end

        local shown = 0
        for _, row in ipairs(self.rows) do
            if row:IsShown() and row.data then
                shown = shown + 1
                local delay = math.min(shown - 1, 14) * 0.02
                Motion:Run(row, "arrive", 0.22, function(p) row:SetAlpha(p) end,
                    { delay = delay })
            end
        end
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

    -- Two things light a chip, each eased on its own: being selected (gold)
    -- and being under the mouse (a lift, only while not selected).
    local function Paint()
        local on = Motion:Value(chip, "selected")
        local hover = Motion:Value(chip, "hover") * (1 - on)

        local r, g, b = Motion.Mix("row", "rowActive", on)
        local hr, hg, hb = Theme.Unpack("rowHover")
        chip.background:SetColorTexture(r + (hr - r) * hover, g + (hg - g) * hover,
            b + (hb - b) * hover, 1)

        local lr, lg, lb = Motion.Mix("muted", "accent", on)
        local tr, tg, tb = Theme.Unpack("text")
        chip.label:SetTextColor(lr + (tr - lr) * hover, lg + (tg - lg) * hover,
            lb + (tb - lb) * hover)

        local er, eg, eb, ea = Motion.Mix("border", "accent", on, 1, 0.6)
        for _, edge in ipairs(chip.borderTextures or {}) do
            edge:SetColorTexture(er, eg, eb, ea)
        end
    end

    function chip:SetSelected(selected)
        local was = self.selected
        self.selected = selected and true or false

        -- The first draw, and a chip that is already where it should be,
        -- land at once; only a change eases.
        if was == nil then
            Motion:SetValue(self, "selected", self.selected and 1 or 0)
            Paint()
            return
        end

        Motion:Blend(self, "selected", self.selected and 1 or 0, 0.15, Paint)
    end

    chip:SetScript("OnEnter", function(self)
        Motion:Blend(self, "hover", 1, 0.1, Paint)
    end)

    chip:SetScript("OnLeave", function(self)
        Motion:Blend(self, "hover", 0, 0.16, Paint)
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

        -- Ticking pops the mark in from small, a touch past size and back.
        if self.checked then
            Motion:Run(self, "tick", 0.22, function(p)
                local size = math.max(1, 8 * p)
                tick:SetSize(size, size)
            end, { ease = Motion.EaseOutBack })
        end

        if onToggle then onToggle(self.checked) end
    end)

    checkbox:SetScript("OnEnter", function(self)
        if not self.disabled then
            label:SetTextColor(Theme.Unpack("accent"))
            Theme.SetBorderColor(box, "accent", 0.7)
        end
    end)

    checkbox:SetScript("OnLeave", function(self)
        label:SetTextColor(Theme.Unpack(self.disabled and "dim" or "text"))
        Theme.SetBorderColor(box, "border")
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
