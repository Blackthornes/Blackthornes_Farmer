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

    -- Opened again before the last opening finished: land that one first,
    -- which puts its point back, or the window would start from the
    -- lowered spot and settle a few pixels further down every time.
    self:Stop(frame, "open", true)

    -- A window with the house glow round it flares as it opens.
    local rest = frame.haloTextures and frame.haloRest
    if rest then
        self:Run(frame, "halo", 0.7, function(p)
            Theme.SetHalo(frame, rest * 3.2 + (rest - rest * 3.2) * p)
        end)
    end

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
-- Reading the client
--------------------------------------------------------------------------------

--- Whether the mouse is on `frame` and the frame is on screen. Read in a
--- pcall, as every client value is; a client that cannot say answers no.
local function UnderMouse(frame)
    local ok, over = pcall(function() return frame:IsVisible() and frame:IsMouseOver() end)
    return ok and over and true or false
end

--- Every point `region` hangs from, as SetPoint takes them, or nil when one
--- of them cannot be read. A client that will not count them gets the
--- first, which is all most labels have.
local function Points(region)
    local ok, count = pcall(function() return region:GetNumPoints() end)
    count = ok and tonumber(count) or 1

    local points = {}
    for index = 1, math.max(1, count) do
        local point, relativeTo, relativePoint, x, y = region:GetPoint(index)
        if not (point and type(x) == "number" and type(y) == "number") then return nil end
        points[index] = { point, relativeTo, relativePoint, x, y }
    end
    return points
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

    -- The one button on a screen that does the main thing glows gold
    -- round its edge under the mouse.
    if opts.primary then Theme.Halo(button, 4, 0) end

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

        if opts.primary then Theme.SetHalo(button, 0.32 * p) end
    end
    button.Light = Light

    button:SetScript("OnEnter", function(self)
        Motion:Blend(self, "hover", 1, HOVER_TIME, Light)
    end)

    button:SetScript("OnLeave", function(self)
        Motion:Blend(self, "hover", 0, HOVER_TIME * 1.5, Light)
    end)

    -- The label dips a pixel while held, so a click feels pressed. Every
    -- point it hangs from moves together, or a label held at both ends
    -- would tilt; and wherever it was put (a caller may have moved it
    -- beside an icon), it goes back to exactly there.
    button:SetScript("OnMouseDown", function(self)
        -- Already held with another mouse button: dipped once is enough.
        -- Taking the dipped spot as the rest sank the label a pixel a time.
        if rawget(self, "restPoints") then return end

        local points = Points(self.label)
        if not points then return end

        self.restPoints = points
        for _, p in ipairs(points) do self.label:SetPoint(p[1], p[2], p[3], p[4], p[5] - 1) end
    end)

    local function Release(self)
        local rest = rawget(self, "restPoints")
        if not rest then return end

        self.restPoints = nil
        for _, p in ipairs(rest) do self.label:SetPoint(p[1], p[2], p[3], p[4], p[5]) end
    end

    button:SetScript("OnMouseUp", Release)
    -- Hidden while held (the click closed its window), the mouse-up never
    -- comes: let go, or the label would stay a pixel low from then on.
    button:SetScript("OnHide", Release)

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
--
-- opts.plain leaves out the magnifier and the clear button, for a small box
-- that is not a search: the room they keep is most of a narrow box.
function Widgets.CreateSearchBox(parent, placeholder, onChange, onAccept, opts)
    opts = opts or {}
    local inset = opts.plain and 6 or 26

    local holder = Theme.CreatePanel(parent, "row", "border")
    holder:SetHeight(24)
    Theme.TopSheen(holder, 0.04)

    -- The game's own magnifier, so the box reads as search at a glance.
    local icon = holder:CreateTexture(nil, "ARTWORK")
    icon:SetSize(14, 14)
    icon:SetPoint("LEFT", 7, 0)
    icon:SetTexture([[Interface\Common\UI-Searchbox-Icon]])
    icon:SetVertexColor(Theme.Unpack("muted"))
    icon:SetShown(not opts.plain)
    holder.icon = icon

    local box = CreateFrame("EditBox", nil, holder)
    box:SetPoint("TOPLEFT", inset, 0)
    box:SetPoint("BOTTOMRIGHT", -inset, 0)
    box:SetAutoFocus(false)
    box:SetFont(Theme.FONT, Theme.sizes.normal, "")
    box:SetTextColor(Theme.Unpack("text"))
    box:SetMaxLetters(80)

    local hint = Theme.CreateLabel(holder, "normal", "dim")
    hint:SetPoint("LEFT", inset, 0)
    hint:SetText(placeholder or "")

    -- Clears what you typed in one click, and only shows when there is
    -- something to clear.
    local clear = CreateFrame("Button", nil, holder)
    clear:SetSize(20, 20)
    clear:SetPoint("RIGHT", -3, 0)
    local cross = Theme.CreateLabel(clear, "normal", "muted", "CENTER")
    cross:SetPoint("CENTER", 0, 0)
    cross:SetText("x")
    clear:Hide()
    holder.clear = clear

    local function UpdateHint()
        local empty = box:GetText() == ""
        hint:SetShown(empty)
        clear:SetShown(not empty and not opts.plain)
    end

    --- The edge and the magnifier, from how far the mouse and the keyboard
    --- have each eased in: the edge lifts under the mouse and turns gold
    --- while the box has the keyboard, and the keyboard's gold wins.
    local function Paint()
        local hover = Motion:Value(holder, "hover")
        local focus = Motion:Value(holder, "focus")

        local r1, g1, b1 = Motion.Mix("border", "borderLit", hover)
        local r2, g2, b2 = Theme.Unpack("accent")
        local r, g, b = r1 + (r2 - r1) * focus, g1 + (g2 - g1) * focus, b1 + (b2 - b1) * focus
        for _, edge in ipairs(holder.borderTextures or {}) do
            edge:SetColorTexture(r, g, b, 1 - 0.2 * focus)
        end

        icon:SetVertexColor(Motion.Mix("muted", "accent", math.max(focus, hover * 0.4)))
    end

    --- The mouse came onto part of the box or left it. Lit while it is
    --- anywhere on the box: going from the margin onto the text, or onto
    --- the x, is a leave and an enter of their own.
    local function Hover()
        local over = UnderMouse(holder)
        Motion:Blend(holder, "hover", over and 1 or 0, over and 0.12 or 0.18, Paint)
    end

    holder:EnableMouse(true)
    holder:SetScript("OnEnter", Hover)
    holder:SetScript("OnLeave", Hover)
    box:SetScript("OnEnter", Hover)
    box:SetScript("OnLeave", Hover)
    -- The margin answers the mouse now, so a click there (on the
    -- magnifier, say) gives the box the keyboard rather than nothing.
    holder:SetScript("OnMouseDown", function() box:SetFocus() end)

    -- The x lifts to the text colour under the mouse, eased like the rest.
    local function LightCross(p)
        cross:SetTextColor(Motion.Mix("muted", "text", p))
    end
    clear:SetScript("OnEnter", function(self)
        Motion:Blend(self, "hover", 1, 0.12, LightCross)
        Hover()
    end)
    clear:SetScript("OnLeave", function(self)
        Motion:Blend(self, "hover", 0, 0.18, LightCross)
        Hover()
    end)

    -- Hidden under the mouse (its window closing, or the x going with the
    -- text it cleared), no leave may come: let go, or it shows again lit.
    local function LetGo(frame, apply)
        Motion:Stop(frame, "hover")
        Motion:SetValue(frame, "hover", 0)
        apply(0)
    end
    holder:SetScript("OnHide", function() LetGo(holder, Paint) end)
    clear:SetScript("OnHide", function() LetGo(clear, LightCross) end)

    box:SetScript("OnEditFocusGained", function()
        Motion:Blend(holder, "focus", 1, 0.15, Paint)
    end)

    box:SetScript("OnEditFocusLost", function()
        Motion:Blend(holder, "focus", 0, 0.2, Paint)
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
-- Scrollbar
--------------------------------------------------------------------------------

--- The thin bar down a list's right edge: a dark track, and a thumb that is
--- as long as the part of the list on screen and lights gold under the
--- mouse or while dragged.
local function CreateScrollbar(list, thumbKey)
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
    thumb:SetColorTexture(Theme.Unpack(thumbKey))
    thumb:SetSize(8, 40)
    scrollbar:SetThumbTexture(thumb)
    scrollbar.thumb = thumb

    local function Light(p)
        thumb:SetColorTexture(Motion.Mix(thumbKey, "accent", p, 1, 0.9))
    end

    scrollbar:SetScript("OnEnter", function(self) Motion:Blend(self, "hover", 1, 0.12, Light) end)
    scrollbar:SetScript("OnLeave", function(self)
        if not self.held then Motion:Blend(self, "hover", 0, 0.2, Light) end
    end)
    scrollbar:SetScript("OnMouseDown", function(self)
        self.held = true
        Motion:Blend(self, "hover", 1, 0.08, Light)
    end)
    scrollbar:SetScript("OnMouseUp", function(self)
        self.held = false
        local over = type(self.IsMouseOver) == "function" and self:IsMouseOver()
        if not over then Motion:Blend(self, "hover", 0, 0.2, Light) end
    end)

    -- Hidden mid-drag (the list shrank), the mouse-up never comes: let go.
    scrollbar:SetScript("OnHide", function(self)
        self.held = false
        Motion:Stop(self, "hover")
        Motion:SetValue(self, "hover", 0)
        Light(0)
    end)

    --- Size the thumb for `visible` of `total` rows on screen.
    function scrollbar:SizeThumb(visible, total)
        local height = tonumber(self:GetHeight())
        if not (height and height > 0 and total and total > 0) then return end
        thumb:SetHeight(math.max(18, math.min(height, height * visible / total)))
    end

    return scrollbar
end

--------------------------------------------------------------------------------
-- Fade
--------------------------------------------------------------------------------

--- A soft fade over one cut edge of a scrolling list, drawn above its rows
--- in the colour behind them (`key`), so a list with more above or below
--- fades out rather than stopping hard. The caller anchors it. Nil where
--- the client has no gradients: a flat band would only hide a row.
function Widgets.CreateFade(parent, side, key, height)
    if type(CreateColor) ~= "function" then return nil end

    local fade = CreateFrame("Frame", nil, parent)
    fade:SetFrameLevel(parent:GetFrameLevel() + 12)
    fade:SetHeight(height or 16)

    local texture = fade:CreateTexture(nil, "OVERLAY")
    texture:SetAllPoints(fade)
    texture:SetColorTexture(1, 1, 1, 1)

    local r, g, b = Theme.Unpack(key or "panel")
    local solid, clear = CreateColor(r, g, b, 0.95), CreateColor(r, g, b, 0)
    local ok
    if side == "TOP" then
        ok = pcall(texture.SetGradient, texture, "VERTICAL", clear, solid)
    else
        ok = pcall(texture.SetGradient, texture, "VERTICAL", solid, clear)
    end
    if not ok then return nil end

    fade:EnableMouse(false)
    fade:Hide()
    return fade
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

    local scrollbar = CreateScrollbar(list, "border")

    list.scrollbar = scrollbar

    -- True while Refresh sets the scrollbar itself (see there).
    local syncing = false

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

        -- The client clamps the slider's value to a new range and reports
        -- that as the player moving it. Taken as a move, a new list that was
        -- shorter than the last one opened scrolled to its end.
        syncing = true
        scrollbar:SetMinMaxValues(0, maxOffset)
        scrollbar:SetValue(self.offset)
        syncing = false
        scrollbar:SetShown(maxOffset > 0)
        scrollbar:SizeThumb(visible, #(self.data or self.lines))

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
        if syncing then return end

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

--- The light a row wears under the mouse, built on `row` once: a lifted
--- wash, a thin gold edge down its left so your place in a long list is easy
--- to keep, and a soft gold light bleeding off that edge into the row.
--- Unlit until Widgets.SetRowLight lights it.
function Widgets.RowLight(row)
    -- Filled at full strength and hidden with SetAlpha: a texture whose
    -- colour is clear stays clear whatever alpha it is given later, which
    -- is how the hover went missing.
    row.highlight = Theme.Fill(row, "rowHover", nil, "BORDER")
    row.highlight:SetAlpha(0)

    row.edge = row:CreateTexture(nil, "OVERLAY")
    row.edge:SetPoint("TOPLEFT")
    row.edge:SetPoint("BOTTOMLEFT")
    row.edge:SetWidth(2)
    row.edge:SetColorTexture(Theme.Unpack("accent"))
    row.edge:SetAlpha(0)

    row.bleed = row:CreateTexture(nil, "BORDER", nil, 1)
    row.bleed:SetPoint("TOPLEFT", 2, 0)
    row.bleed:SetPoint("BOTTOMLEFT", 2, 0)
    row.bleed:SetWidth(18)
    Theme.SetGradientAlpha(row.bleed, "HORIZONTAL", "accent", 0.22, 0)
    pcall(row.bleed.SetBlendMode, row.bleed, "ADD")
    row.bleed:SetAlpha(0)
end

--- How lit a row from Widgets.RowLight is: 0 at rest, 1 under the mouse.
function Widgets.SetRowLight(row, value)
    row.highlight:SetAlpha(0.6 * value)
    row.edge:SetAlpha(value)
    row.bleed:SetAlpha(value)
end

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

    local scrollbar = CreateScrollbar(list, "borderLit")

    list.scrollbar = scrollbar

    -- The cut edges fade while there is more above or below.
    local fadeTop = Widgets.CreateFade(list, "TOP", opts.fadeKey, 14)
    local fadeBottom = fadeTop and Widgets.CreateFade(list, "BOTTOM", opts.fadeKey, 14)
    if fadeBottom then
        fadeTop:SetPoint("TOPLEFT", list, "TOPLEFT", 0, 0)
        fadeTop:SetPoint("TOPRIGHT", scrollbar, "TOPLEFT", -6, 0)
        fadeBottom:SetPoint("BOTTOMLEFT", list, "BOTTOMLEFT", 0, 0)
        fadeBottom:SetPoint("BOTTOMRIGHT", scrollbar, "BOTTOMLEFT", -6, 0)
        list.fadeTop, list.fadeBottom = fadeTop, fadeBottom
    end

    local function VisibleRowCount()
        local height = list:GetHeight()
        if not height or height <= 0 then return 0 end
        return math.floor(height / rowHeight)
    end

    -- True while Refresh sets the scrollbar itself (see there).
    local syncing = false

    -- The row under the mouse, from its OnEnter to its OnLeave.
    local hovered

    --- How lit a row is: 0 at rest, 1 under the mouse.
    local Lit = Widgets.SetRowLight

    local function Unlight(row)
        Motion:Stop(row, "hover")
        Motion:SetValue(row, "hover", 0)
        Lit(row, 0)
    end

    --- The mouse is on `row`: light it, and let the caller show its tooltip.
    local function Enter(row)
        hovered = row
        if row.data and row.data.type ~= "spacer" then
            Motion:Blend(row, "hover", 1, 0.08, function(value) Lit(row, value) end)
        else
            Unlight(row)
        end
        if row.data and opts.onEnter then opts.onEnter(row, row.data) end
    end

    local function AcquireRow(index)
        local row = list.rows[index]
        if row then return row end

        row = CreateFrame("Button", nil, list)
        row:SetHeight(rowHeight)
        row:SetPoint("TOPLEFT", 0, -(index - 1) * rowHeight)
        row:SetPoint("RIGHT", scrollbar, "LEFT", -6, 0)
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")

        -- Filled at full strength and hidden with SetAlpha: a texture whose
        -- colour is clear stays clear whatever alpha it is given later, which
        -- is how the hover and the banding went missing.
        row.stripe = Theme.Fill(row, "rowAlt")
        row.stripe:SetAlpha(0)

        -- The wash, the gold edge and the gold light that come up under the
        -- mouse.
        Widgets.RowLight(row)

        if opts.createRow then
            opts.createRow(row)
        end

        -- Callers hook hovering through opts rather than HookScript on the
        -- row: SetScript here would replace a hook set in createRow.
        row:SetScript("OnEnter", Enter)

        row:SetScript("OnLeave", function(self)
            if hovered == self then hovered = nil end
            Motion:Blend(self, "hover", 0, 0.18, function(value) Lit(self, value) end)
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

        -- Asked before the rows change: one emptied below is hidden, and a
        -- hidden row is under no mouse.
        local stillOver = hovered and UnderMouse(hovered)

        for index = 1, visible do
            local row = AcquireRow(index)
            local data = self.data[index + self.offset]

            row.data = data
            row.dataIndex = index + self.offset

            -- A row handed new data starts unlit, except the one under the
            -- mouse, which is lit again for its new data below.
            if not (stillOver and row == hovered) then Unlight(row) end

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

        -- A scroll or a redraw hands the row under a still mouse new data,
        -- and no OnEnter comes for that: it went dark, and its tooltip
        -- still spoke of the last row. Leave and enter it again, as if the
        -- mouse had just come onto what it shows now.
        if hovered then
            local row = hovered
            hovered = nil
            if stillOver and opts.onLeave then opts.onLeave(row) end
            if stillOver and row.data and row:IsShown() then
                Enter(row)
            else
                Unlight(row)
            end
        end

        -- The client clamps the slider's value to a new range and reports
        -- that as the player moving it. Taken as a move, a new list that was
        -- shorter than the last one opened scrolled to its end.
        syncing = true
        scrollbar:SetMinMaxValues(0, maxOffset)
        scrollbar:SetValue(self.offset)
        syncing = false
        scrollbar:SetShown(maxOffset > 0)
        scrollbar:SizeThumb(visible, #(self.data or self.lines))

        if fadeBottom then
            fadeTop:SetShown(self.offset > 0)
            fadeBottom:SetShown(self.offset < maxOffset)
        end

        if opts.onRefresh then
            opts.onRefresh(self, #self.data, visible)
        end
    end

    --- New rows. `keepPlace` keeps the list scrolled where it was (a redraw
    --- of the same results after a kill, a heading folded); otherwise it
    --- starts from the top.
    function list:SetData(data, keepPlace)
        self.data = data or {}
        if not keepPlace then self.offset = 0 end
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
        if syncing then return end

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

--- A small toggle used in a row of filters. Selected chips carry the accent,
--- and a gold line with a soft glow along their foot (opts.noUnderline for
--- chips that have a sliding line of their own, like the window's tabs).
function Widgets.CreateChip(parent, text, onClick, opts)
    opts = opts or {}
    local chip = CreateFrame("Button", nil, parent)
    chip:SetHeight(18)

    chip.background = Theme.Fill(chip, "row")
    Theme.Border(chip, "border")

    chip.label = Theme.CreateLabel(chip, "tiny", "muted", "CENTER")
    chip.label:SetPoint("CENTER")
    chip.label:SetText(text)

    local under, glow
    if not opts.noUnderline then
        under = chip:CreateTexture(nil, "OVERLAY")
        under:SetHeight(1)
        under:SetPoint("BOTTOMLEFT", 3, 1)
        under:SetPoint("BOTTOMRIGHT", -3, 1)
        under:SetColorTexture(Theme.Unpack("accent"))
        under:SetAlpha(0)

        glow = chip:CreateTexture(nil, "ARTWORK")
        glow:SetHeight(5)
        glow:SetPoint("BOTTOMLEFT", 1, 1)
        glow:SetPoint("BOTTOMRIGHT", -1, 1)
        glow:SetColorTexture(1, 1, 1, 1)
        pcall(glow.SetBlendMode, glow, "ADD")
        local r, g, b = Theme.Unpack("accent")
        local ok = type(CreateColor) == "function" and pcall(glow.SetGradient, glow, "VERTICAL",
            CreateColor(r, g, b, 0.3), CreateColor(r, g, b, 0))
        if not ok then glow:SetColorTexture(r, g, b, 0.1) end
        glow:SetAlpha(0)
    end

    -- Sized to its text, so a row of chips packs tightly whatever the labels.
    chip:SetWidth(math.max(34, Theme.TextWidth("tiny", text) + 16))

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

        if under then
            under:SetAlpha(on)
            glow:SetAlpha(on)
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
    -- A faint sheen along its top, as the buttons have.
    Theme.TopSheen(box)

    local tick = box:CreateTexture(nil, "OVERLAY")
    tick:SetPoint("CENTER")
    tick:SetSize(8, 8)
    tick:SetColorTexture(Theme.Unpack("accent"))

    local label = Theme.CreateLabel(checkbox, "small", "text")
    label:SetPoint("LEFT", box, "RIGHT", 6, 0)
    label:SetText(text)

    checkbox.label = label
    checkbox.box = box
    checkbox:SetWidth(Theme.TextWidth("small", text) + 24)
    checkbox.checked = initial and true or false
    checkbox.disabled = false

    --- The box and its label, from its state and from how far the mouse has
    --- eased in. A ticked box wears a gold edge, so its state shows at a
    --- glance and not only by the small mark; an unticked one lifts under
    --- the mouse; the label eases to gold. A disabled one does not answer
    --- the mouse.
    local function Paint()
        local hover = checkbox.disabled and 0 or Motion:Value(checkbox, "hover")
        tick:SetShown(checkbox.checked)

        local r, g, b, a
        if checkbox.checked then
            r, g, b, a = Theme.Unpack("accent", checkbox.disabled and 0.4 or 1)
        else
            r, g, b, a = Motion.Mix("border", "borderLit", hover)
        end
        for _, edge in ipairs(box.borderTextures or {}) do edge:SetColorTexture(r, g, b, a) end

        label:SetTextColor(Motion.Mix(checkbox.disabled and "dim" or "text", "accent", hover))
    end

    function checkbox:SetChecked(value)
        self.checked = value and true or false
        Paint()
    end

    function checkbox:GetChecked()
        return self.checked
    end

    --- A disabled box keeps showing its state but ignores clicks, for a
    --- setting this client cannot honour.
    function checkbox:SetDisabled(disabled)
        self.disabled = disabled and true or false
        tick:SetAlpha(self.disabled and 0.4 or 1)
        Paint()
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
        Motion:Blend(self, "hover", 1, 0.12, Paint)
    end)

    checkbox:SetScript("OnLeave", function(self)
        Motion:Blend(self, "hover", 0, 0.18, Paint)
    end)

    Paint()
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
