-- Blackthornes Farmer -- UI/GrindTo60.lua
-- The Grind tab's Grind to 60 view (Logic/GrindTo60.lua works the path out;
-- a test feature, off unless ticked on the Experimental page).
--
-- Who is playing and Pick By, then a dark glass row a step (LEVELS, WHERE,
-- XP, GOLD), done steps ticked and dimmed, the step you are on lit with a
-- gold edge. One step is open at a time: its mobs, good drops, herbs and
-- skins, why it was picked, Show the Way and Skip Step. A right-click
-- offers the way there and to hide the area or one of its mobs.
--
-- Kill rewards stay secret: gold and XP are dots that only compare the
-- steps, and drops are names, never a coin, a rate or a percent.
--
-- Drawn only while the view shows, and only when the plan, the open step
-- or the scroll moved (a key per draw). Nothing here runs on a timer.

local _, ns = ...
local L = ns.L

local GrindTo60UI = ns.NewModule("GrindTo60UI")

local Theme = ns.Theme
local Widgets = ns.Widgets
local Util = ns.Util

GrindTo60UI.HEAD_H = 24
GrindTo60UI.SUB_H = 16
GrindTo60UI.HEADING_H = 18
GrindTo60UI.ROW_H = 24
GrindTo60UI.TALL_ROW_H = 38
GrindTo60UI.FOOT_H = 24
GrindTo60UI.LEVELS_X = 28
GrindTo60UI.WHERE_X = 112
-- The dots: how many, how big, and where each column starts from the right.
GrindTo60UI.DOTS = 4
GrindTo60UI.DOT = 8
GrindTo60UI.DOT_GAP = 3
GrindTo60UI.GOLD_RIGHT = 14
GrindTo60UI.XP_RIGHT = 84
-- Mobs a step's right-click offers to hide.
GrindTo60UI.MENU_MOBS = 3

local CHECK = [[Interface\RaidFrame\ReadyCheck-Ready]]
local ROUND = [[Interface\CharacterFrame\TempPortraitAlphaMask]]
local XP_COLOR = { 0.706, 0.549, 1.0 }
local GOLD_COLOR = { 1.0, 0.82, 0.0 }
local EMPTY_COLOR = { 0.29, 0.235, 0.141 }

local function Path() return ns.GrindTo60 end

local function Upper(text)
    return (tostring(text or ""):upper():gsub("ä", "Ä"):gsub("ö", "Ö"):gsub("ü", "Ü"))
end

local function ButtonWidth(text)
    return math.ceil(Theme.TextWidth("small", text or "")) + 24
end

--- `text` in a Theme colour, for a label that mixes colours.
local function Tint(key, text)
    local r, g, b = Theme.Unpack(key)
    return ("|cff%02x%02x%02x%s|r"):format(math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5),
        math.floor(b * 255 + 0.5), text)
end

local function Refresh()
    if ns.GrindingUI and ns.GrindingUI.Refresh then ns.GrindingUI:Refresh() end
end

--------------------------------------------------------------------------------
-- Words
--------------------------------------------------------------------------------

--- "Level 23 Orc Hunter".
function GrindTo60UI.WhoText(who)
    if not (who and who.level) then return "" end
    return L.Format("Level %d %s %s", who.level, who.raceName or "", who.className or "")
end

--- "Horde, from Durotar. Skinning 140, Herbalism 125".
function GrindTo60UI.SubText(who, skills)
    local parts = {}
    if who and who.factionName and who.start then
        parts[#parts + 1] = L.Format("%s, from %s.", who.factionName, ns.Spots.Show(who.start))
    end
    local known = {}
    if skills and skills.Skinning then known[#known + 1] = ("%s %d"):format(L["Skinning"], skills.Skinning) end
    if skills and skills.Herbalism then known[#known + 1] = ("%s %d"):format(L["Herbalism"], skills.Herbalism) end
    if #known > 0 then parts[#parts + 1] = table.concat(known, ", ") end
    return table.concat(parts, " ")
end

--- A step's zone and place, the place in grey.
function GrindTo60UI.WhereText(step)
    local zone = ns.Spots.Show(step.zone)
    if step.label and step.label ~= zone then
        return zone .. "  " .. Tint("muted", step.label), zone .. "  " .. step.label
    end
    return zone, zone
end

--- A step's tags, coloured, and the same words plain.
function GrindTo60UI.TagsText(step)
    local colored, plain = {}, {}
    local function Add(key, words)
        colored[#colored + 1] = Tint(key, words)
        plain[#plain + 1] = words
    end
    if step.estimate then Add("muted", L["estimate"]) end
    if #(step.herbs or {}) > 0 then Add("good", L["HERBS"]) end
    if #(step.skinnable or {}) > 0 then Add("accent", L["SKINS"]) end
    if step.both then Add("warn", L["BOTH SIDES"]) end
    if step.elites then Add("loss", L["ELITES NEAR"]) end
    return table.concat(colored, "  "), table.concat(plain, "  ")
end

local function Names(list, most, field)
    local out = {}
    for index = 1, math.min(most or #list, #list) do
        local each = list[index]
        out[#out + 1] = field and each[field] or each
    end
    return out
end

--- "Galak Scout, Galak Wrangler, levels 24 to 27".
function GrindTo60UI.MobsText(step)
    local low, high
    for _, mob in ipairs(step.mobs or {}) do
        low = math.min(low or mob.minLevel, mob.minLevel)
        high = math.max(high or mob.minLevel, mob.maxLevel or mob.minLevel)
    end
    local names = table.concat(Names(step.mobs or {}, nil, "name"), ", ")
    if not low then return names end
    return names .. "  " .. Tint("muted", L.Format("levels %d to %d", low, high))
end

function GrindTo60UI.DropsText(step)
    local out = {}
    for _, name in ipairs(step.drops or {}) do out[#out + 1] = Util.ColorItem(name) end
    return table.concat(out, ", ")
end

--- Herbs to pick and mobs to skin near the step, or "" with neither.
function GrindTo60UI.AlsoText(step)
    local herbs = {}
    for _, row in ipairs(step.herbs or {}) do
        if #herbs < 3 then herbs[#herbs + 1] = Util.ColorItem(row.item) end
    end
    local skins = Names(step.skinnable or {}, 3, "name")
    local leathers = {}
    for name in pairs(step.leathers or {}) do leathers[#leathers + 1] = name end
    table.sort(leathers)
    for index, name in ipairs(leathers) do leathers[index] = Util.ColorItem(name) end

    local pick = #herbs > 0 and table.concat(herbs, ", ") or nil
    local skin = #skins > 0 and table.concat(skins, ", ") or nil
    local leather = #leathers > 0 and table.concat(leathers, ", ") or nil
    if pick and skin and leather then
        return L.Format("%s to pick, and %s to skin for %s.", pick, skin, leather)
    elseif pick and skin then
        return L.Format("%s to pick, and %s to skin.", pick, skin)
    elseif pick then
        return L.Format("%s to pick.", pick)
    elseif skin and leather then
        return L.Format("%s to skin for %s.", skin, leather)
    elseif skin then
        return L.Format("%s to skin.", skin)
    end
    return ""
end

function GrindTo60UI.WhyText(step)
    return table.concat(step.reasons or {}, " ")
end

function GrindTo60UI.PaceText(step, level)
    local seconds = Path().Seconds(step, level)
    if not seconds then return "" end
    return L.Format("About %s of play at your pace.", ns.Respawn.Duration(seconds))
end

--- The Grind tab's footer while the path shows.
function GrindTo60UI.FooterText(plan)
    local parts = { L["Experimental."] }
    if plan and plan.who and plan.who.level and plan.current then
        parts[#parts + 1] = L.Format("Level %d", plan.who.level) .. ", "
            .. L.Format("Step %d of %d", plan.current, #plan.steps) .. "."
    end
    parts[#parts + 1] = L["Built from mobs Farmer has seen. It gets better as you play."]
    return table.concat(parts, " ")
end

--------------------------------------------------------------------------------
-- Building
--------------------------------------------------------------------------------

--- A row of dots, right to left from `right`.
local function CreateDots(row, right, color)
    local dots = { color = color }
    local step = GrindTo60UI.DOT + GrindTo60UI.DOT_GAP
    for index = 1, GrindTo60UI.DOTS do
        local dot = row:CreateTexture(nil, "ARTWORK")
        dot:SetSize(GrindTo60UI.DOT, GrindTo60UI.DOT)
        dot:SetTexture(ROUND)
        dot:SetPoint("TOPRIGHT", -(right + (GrindTo60UI.DOTS - index) * step), -8)
        -- A hollow dot is the same dot with the row's dark in its middle.
        local hole = row:CreateTexture(nil, "ARTWORK", nil, 1)
        hole:SetSize(GrindTo60UI.DOT - 3, GrindTo60UI.DOT - 3)
        hole:SetTexture(ROUND)
        hole:SetPoint("CENTER", dot, "CENTER", 0, 0)
        hole:Hide()
        dot.hole = hole
        dots[index] = dot
    end
    return dots
end

local function FillDots(dots, count, hollow, alpha, back)
    for index, dot in ipairs(dots) do
        local color = index <= (count or 0) and dots.color or EMPTY_COLOR
        dot:SetVertexColor(color[1], color[2], color[3], alpha)
        dot.hole:SetShown(hollow and true or false)
        if hollow then dot.hole:SetVertexColor(back[1], back[2], back[3], 1) end
    end
end

local function DotsLeft(right)
    return right + GrindTo60UI.DOTS * (GrindTo60UI.DOT + GrindTo60UI.DOT_GAP)
end

function GrindTo60UI:Build(panel)
    if self.frame then return self.frame end
    local frame = CreateFrame("Frame", nil, panel)
    frame:SetPoint("TOPLEFT", 8, -8)
    frame:SetPoint("BOTTOMRIGHT", -8, 8)
    frame:Hide()
    self.frame = frame
    self.offset = 0

    -- Who is playing, and what the path is picked by.
    local who = Theme.CreateLabel(frame, "normal", "text")
    who:SetPoint("TOPLEFT", 2, 0)
    who:SetHeight(self.HEAD_H)
    self.who = who

    local options, widest = {}, 0
    for _, entry in ipairs(Path().PICKS) do
        options[#options + 1] = { value = entry.key, text = entry.label }
        widest = math.max(widest, Theme.TextWidth("small", entry.label) or 0)
    end
    local pick = Widgets.CreateDropdown(frame, options, function(value)
        Path():SetPick(value)
        Refresh()
    end, { width = math.max(110, math.ceil(widest) + 34), glass = true })
    pick:SetPoint("TOPRIGHT", -2, -1)
    self.pick = pick
    local pickLabel = Theme.CreateLabel(frame, "small", "muted", "RIGHT")
    pickLabel:SetPoint("RIGHT", pick, "LEFT", -6, 0)
    pickLabel:SetText(L["Pick By:"])
    self.pickLabel = pickLabel
    who:SetPoint("RIGHT", pickLabel, "LEFT", -8, 0)

    local sub = Theme.CreateLabel(frame, "small", "muted")
    sub:SetPoint("TOPLEFT", 2, -self.HEAD_H)
    sub:SetPoint("TOPRIGHT", -2, -self.HEAD_H)
    sub:SetHeight(self.SUB_H)
    self.sub = sub

    -- Column headings.
    local headings = CreateFrame("Frame", nil, frame)
    headings:SetHeight(self.HEADING_H)
    headings:SetPoint("TOPLEFT", 0, -(self.HEAD_H + self.SUB_H + 4))
    headings:SetPoint("TOPRIGHT", 0, -(self.HEAD_H + self.SUB_H + 4))
    local function Heading(text, justify)
        local label = Theme.CreateLabel(headings, "tiny", "dim", justify)
        label:SetText(text)
        return label
    end
    Heading(L["LEVELS"]):SetPoint("LEFT", self.LEVELS_X, 0)
    Heading(L["WHERE"]):SetPoint("LEFT", self.WHERE_X, 0)
    Heading(L["XP"], "RIGHT"):SetPoint("RIGHT", -self.XP_RIGHT, 0)
    Heading(L["GOLD"], "RIGHT"):SetPoint("RIGHT", -self.GOLD_RIGHT, 0)
    local rule = Theme.CreateDivider(headings, "border")
    rule:SetPoint("BOTTOMLEFT", 0, 0)
    rule:SetPoint("BOTTOMRIGHT", 0, 0)
    self.headings = headings

    -- The steps.
    local list = CreateFrame("Frame", nil, frame)
    list:EnableMouseWheel(true)
    list:SetScript("OnMouseWheel", function(_, delta) GrindTo60UI:Scroll(delta) end)
    if list.SetClipsChildren then pcall(list.SetClipsChildren, list, true) end
    self.list = list
    self.rows = {}
    self:BuildDetail(list)

    -- The foot: what is hidden from here, and Show Again.
    local foot = CreateFrame("Frame", nil, frame)
    foot:SetPoint("BOTTOMLEFT", 0, 0)
    foot:SetPoint("BOTTOMRIGHT", 0, 0)
    foot:SetHeight(self.FOOT_H)
    foot.text = Theme.CreateLabel(foot, "small", "muted")
    foot.text:SetPoint("LEFT", 2, 0)
    foot.button = Widgets.CreateButton(foot, L["Show Again"], function()
        Path():ShowAgain()
        Refresh()
    end, { width = ButtonWidth(L["Show Again"]), height = 20 })
    foot.button:SetPoint("LEFT", foot.text, "RIGHT", 8, 0)
    foot:Hide()
    self.foot = foot

    -- Nothing to show: too few mobs seen, or the top level reached.
    local empty = Theme.CreateLabel(frame, "normal", "text", "CENTER")
    empty:SetPoint("TOPLEFT", 20, -(self.HEAD_H + self.SUB_H + 40))
    empty:SetPoint("TOPRIGHT", -20, -(self.HEAD_H + self.SUB_H + 40))
    empty:SetWordWrap(true)
    empty:Hide()
    self.empty = empty

    return frame
end

--- The open step's card: a heading and its words a line, then the buttons.
function GrindTo60UI:BuildDetail(list)
    local detail = CreateFrame("Frame", nil, list)
    detail:EnableMouseWheel(true)
    detail:SetScript("OnMouseWheel", function(_, delta) GrindTo60UI:Scroll(delta) end)
    detail.stripe = Theme.Fill(detail, "glassActive")
    detail.active = detail:CreateTexture(nil, "OVERLAY", nil, 1)
    detail.active:SetPoint("TOPLEFT")
    detail.active:SetPoint("BOTTOMLEFT")
    detail.active:SetWidth(2)
    detail.active:SetColorTexture(Theme.Unpack("accentHi"))
    detail.line = detail:CreateTexture(nil, "BACKGROUND", nil, 1)
    detail.line:SetPoint("BOTTOMLEFT")
    detail.line:SetPoint("BOTTOMRIGHT")
    detail.line:SetHeight(1)
    detail.line:SetColorTexture(Theme.Unpack("border", 0.6))

    local heads = { L["Mobs:"], L["Good Drops:"], L["Also Here:"], L["Why Here:"] }
    local headWidth = 0
    for _, text in ipairs(heads) do
        headWidth = math.max(headWidth, math.ceil(Theme.TextWidth("small", text) or 0))
    end
    self.bodyX = self.LEVELS_X + headWidth + 10

    detail.lines = {}
    self.detailTexts = {}
    for index, text in ipairs(heads) do
        local head = Theme.CreateLabel(detail, "small", "accent")
        head:SetText(text)
        local body = Theme.CreateLabel(detail, "small", "text")
        body:SetWordWrap(true)
        if body.SetJustifyV then body:SetJustifyV("TOP") end
        detail.lines[index] = { head = head, body = body }
        self.detailTexts[index] = body
    end

    detail.way = Widgets.CreateButton(detail, L["Show the Way"], function()
        GrindTo60UI:ShowTheWay(detail.step)
    end, { primary = true, width = ButtonWidth(L["Show the Way"]), height = 20 })
    detail.skip = Widgets.CreateButton(detail, L["Skip Step"], function()
        if not detail.step then return end
        Path():Skip(detail.step)
        Refresh()
    end, { width = ButtonWidth(L["Skip Step"]), height = 20 })
    detail.skip:SetPoint("LEFT", detail.way, "RIGHT", 6, 0)
    detail.pace = Theme.CreateLabel(detail, "small", "muted", "RIGHT")
    detail.pace:SetPoint("LEFT", detail.skip, "RIGHT", 10, 0)
    self.detailTexts[#self.detailTexts + 1] = detail.pace

    detail:Hide()
    self.detail = detail
    return detail
end

--- The words on the open step's card, as shown.
function GrindTo60UI:DetailWords()
    local out = {}
    if not (self.detail and self.detail:IsShown()) then return out end
    for _, label in ipairs(self.detailTexts or {}) do
        if label:IsShown() then out[#out + 1] = label:GetText() or "" end
    end
    return out
end

function GrindTo60UI:Row(index)
    local row = self.rows[index]
    if row then return row end
    row = CreateFrame("Frame", nil, self.list)
    row:SetHeight(self.ROW_H)
    row:EnableMouse(true)
    row:EnableMouseWheel(true)
    row:SetScript("OnMouseWheel", function(_, delta) GrindTo60UI:Scroll(delta) end)

    row.stripe = Theme.Fill(row, "glass")
    row.line = row:CreateTexture(nil, "BACKGROUND", nil, 1)
    row.line:SetPoint("BOTTOMLEFT")
    row.line:SetPoint("BOTTOMRIGHT")
    row.line:SetHeight(1)
    row.line:SetColorTexture(Theme.Unpack("border", 0.6))
    Widgets.RowLight(row)

    row.active = row:CreateTexture(nil, "OVERLAY", nil, 1)
    row.active:SetPoint("TOPLEFT")
    row.active:SetPoint("BOTTOMLEFT")
    row.active:SetWidth(2)
    row.active:SetColorTexture(Theme.Unpack("accentHi"))

    row.check = row:CreateTexture(nil, "ARTWORK")
    row.check:SetSize(14, 14)
    row.check:SetTexture(CHECK)
    row.check:SetPoint("TOPLEFT", 8, -5)

    row.levels = Theme.CreateLabel(row, "small", "text")
    row.levels:SetPoint("TOPLEFT", self.LEVELS_X, 0)
    row.levels:SetHeight(self.ROW_H)
    row.where = Theme.CreateLabel(row, "small", "text")
    row.where:SetPoint("TOPLEFT", self.WHERE_X, 0)
    row.where:SetHeight(self.ROW_H)
    row.tags = Theme.CreateLabel(row, "tiny", "muted", "RIGHT")
    row.tags:SetPoint("TOPRIGHT", -(DotsLeft(self.XP_RIGHT) + 10), 0)
    row.tags:SetHeight(self.ROW_H)
    row.texts = { row.levels, row.where, row.tags }

    row.xp = CreateDots(row, self.XP_RIGHT, XP_COLOR)
    row.gold = CreateDots(row, self.GOLD_RIGHT, GOLD_COLOR)

    row:SetScript("OnEnter", function(self)
        Widgets.SetRowLight(self, 1)
        GrindTo60UI:ShowTip(self)
    end)
    row:SetScript("OnLeave", function(self)
        Widgets.SetRowLight(self, 0)
        if GameTooltip then GameTooltip:Hide() end
    end)
    row:SetScript("OnMouseUp", function(self, button)
        if not self.step then return end
        if button == "RightButton" then
            GrindTo60UI:OpenMenu(self.step)
        else
            GrindTo60UI:OpenStep(self.step)
        end
    end)

    self.rows[index] = row
    return row
end

--------------------------------------------------------------------------------
-- Acting
--------------------------------------------------------------------------------

--- Point the goal arrow at a step's camp.
function GrindTo60UI:ShowTheWay(step)
    if not (step and step.camp and ns.Arrow) then return false end
    return ns.Arrow:Grind(step.camp)
end

--- Is `step` the open one? The step you are on, until another is picked.
function GrindTo60UI:IsOpen(step, plan)
    if self.open == false then return false end
    if self.open ~= nil then return self.open == step.low end
    return plan.current ~= nil and plan.steps[plan.current] == step
end

--- A click on a step: open it, or shut it if it is the open one.
function GrindTo60UI:OpenStep(step)
    local plan = self.plan or Path():Plan()
    if self:IsOpen(step, plan) then self.open = false else self.open = step.low end
    self.key = nil
    self:Update()
end

--- The step's right-click menu: the way there, hide the area, hide a mob,
--- Cancel.
function GrindTo60UI:OpenMenu(step)
    local choices = {
        { kind = "action", text = L["Show the Way"], run = function() GrindTo60UI:ShowTheWay(step) end },
        { kind = "action", text = L["Hide This Area"], run = function() Path():HideArea(step) end },
    }
    for index, mob in ipairs(step.mobs or {}) do
        if index > self.MENU_MOBS then break end
        local name = mob.name
        choices[#choices + 1] = { kind = "action", text = L.Format("Hide %s", name),
            run = function() Path():HideMob(name) end }
    end
    choices[#choices + 1] = { kind = "action", text = L["Cancel"], run = function() end }
    return ns.HideMenu:Open(choices, #choices)
end

function GrindTo60UI:ShowTip(row)
    local step = row.step
    if not (step and GameTooltip) then return end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:SetText(ns.Spots.Show(step.zone), 1, 0.82, 0)
    GameTooltip:AddLine(L.Format("%s, levels %d to %d", step.label or ns.Spots.Show(step.zone), step.low, step.high),
        1, 1, 1, true)
    if step.both then
        GameTooltip:AddLine(L["Players from both sides come here. Keep an eye out."], Theme.Unpack("warn"))
    end
    if step.estimate then
        GameTooltip:AddLine(L["Farmer hasn't seen many kills here yet, so this step is a guess."], 1, 1, 1, true)
    end
    GameTooltip:AddLine(L["Gold and XP dots compare the steps on this path."], 1, 1, 1, true)
    if (step.kills or 0) > 0 then
        GameTooltip:AddLine(L.Format("Farmer has seen %d kills here.", step.kills), 1, 1, 1, true)
    end
    local r, g, b = Theme.Unpack("dim")
    GameTooltip:AddLine(L["Right-click to hide a mob or this area."], r, g, b, true)
    GameTooltip:AddLine(L["Click to open this step."], r, g, b, true)
    GameTooltip:Show()
end

--------------------------------------------------------------------------------
-- Drawing
--------------------------------------------------------------------------------

function GrindTo60UI:Scroll(delta)
    local plan = self.plan
    if not plan then return end
    local most = math.max(0, #plan.steps - 1)
    local to = math.max(0, math.min(most, (self.offset or 0) - delta))
    if to == self.offset then return end
    self.offset = to
    self.scrolled = true
    self.key = nil
    self:Update()
end

--- Show or hide the view, and the Grind tab's own list with it.
function GrindTo60UI:Toggle(grinding, on)
    if not self.frame then return end
    self.frame:SetShown(on and true or false)
    if not (grinding and on) then return end
    for _, piece in ipairs({ grinding.list, grinding.rule }) do
        if type(piece) == "table" and piece.SetShown then piece:SetShown(false) end
    end
    for _, label in pairs(type(grinding.headings) == "table" and grinding.headings or {}) do
        if type(label) == "table" and label.Hide then label:Hide() end
    end
    local buttons = type(grinding.sorter) == "table" and grinding.sorter.buttons
    for _, button in pairs(type(buttons) == "table" and buttons or {}) do
        if type(button) == "table" and button.Hide then button:Hide() end
    end
end

local function Size(frame, fallbackW, fallbackH)
    local w, h = frame:GetWidth(), frame:GetHeight()
    if type(w) ~= "number" or w <= 0 then w = fallbackW end
    if type(h) ~= "number" or h <= 0 then h = fallbackH end
    return w, h
end

--- How tall `label`'s words are once wrapped into `room`.
local function TextHeight(label, room)
    local ok, drawn = pcall(label.GetStringHeight, label)
    if ok and type(drawn) == "number" and drawn > 0 then return math.ceil(drawn) end
    local plain = (label:GetText() or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    local width = Theme.TextWidth("small", plain) or 0
    return math.max(1, math.ceil(width / math.max(40, room))) * 14
end

--- Fill the open step's card and return its height.
function GrindTo60UI:FillDetail(step, plan, width)
    local detail = self.detail
    detail.step = step
    local words = {
        GrindTo60UI.MobsText(step), GrindTo60UI.DropsText(step),
        GrindTo60UI.AlsoText(step), GrindTo60UI.WhyText(step),
    }
    local room = width - self.bodyX - 12
    local y = 8
    for index, line in ipairs(detail.lines) do
        local shown = words[index] ~= ""
        line.head:SetShown(shown)
        line.body:SetShown(shown)
        if shown then
            line.head:ClearAllPoints()
            line.head:SetPoint("TOPLEFT", self.LEVELS_X, -y)
            line.body:ClearAllPoints()
            line.body:SetPoint("TOPLEFT", self.bodyX, -y)
            line.body:SetWidth(room)
            line.body:SetText(words[index])
            y = y + TextHeight(line.body, room) + 6
        end
    end
    detail.way:ClearAllPoints()
    detail.way:SetPoint("TOPLEFT", self.LEVELS_X, -(y + 2))
    -- A step behind you has nothing to skip to.
    detail.skip:SetShown(not step.done)
    local pace = step.done and "" or GrindTo60UI.PaceText(step, plan.who and plan.who.level)
    detail.pace:SetText(pace)
    detail.pace:SetShown(pace ~= "")
    return y + 2 + 20 + 10
end

local function Key(self, plan, width, height)
    return table.concat({ tostring(plan), tostring(self.open), tostring(self.offset), tostring(width),
        tostring(height), tostring(Path().HiddenCount()), Path().Pick(),
        tostring(Path().Seconds(plan.steps[plan.current or 0], plan.who and plan.who.level)) }, "|")
end

--- Draw the view. Returns the Grind tab's footer words.
function GrindTo60UI:Update()
    if not self.frame then return "" end
    local plan = Path():Plan()
    local moved = plan ~= self.plan
    self.plan = plan
    local footer = GrindTo60UI.FooterText(plan)

    -- What is hidden from here, with Show Again.
    local hidden = Path().HiddenCount()
    self.foot:SetShown(hidden > 0)
    if hidden > 0 then self.foot.text:SetText(L.Format("%d hidden.", hidden)) end
    self.list:ClearAllPoints()
    self.list:SetPoint("TOPLEFT", 0, -(self.HEAD_H + self.SUB_H + 4 + self.HEADING_H))
    self.list:SetPoint("BOTTOMRIGHT", 0, hidden > 0 and self.FOOT_H + 2 or 0)

    local width, height = Size(self.list, 680, 12 * self.ROW_H)
    -- A new plan starts on the step you are on, a little way down the list.
    if moved and not self.scrolled then
        self.offset = math.max(0, (plan.current or 1) - 3)
    end
    self.offset = math.max(0, math.min(self.offset or 0, math.max(0, #plan.steps - 1)))

    local key = Key(self, plan, width, height)
    if key == self.key then return footer end
    self.key = key

    self.who:SetText(GrindTo60UI.WhoText(plan.who))
    self.sub:SetText(GrindTo60UI.SubText(plan.who, plan.skills))
    self.pick:SetValue(Path().Pick())

    local nothing = plan.top or plan.empty
    self.empty:SetShown(nothing and true or false)
    self.headings:SetShown(not nothing)
    self.list:SetShown(not nothing)
    if nothing then
        self.empty:SetText(plan.top and L["You made it to 60."]
            or L["Farmer hasn't seen enough mobs near your level yet. Go kill a few and check back."])
        self.empty:SetTextColor(Theme.Unpack(plan.top and "accent" or "text"))
        for _, row in ipairs(self.rows) do row:Hide() end
        self.detail:Hide()
        return footer
    end

    local whereRoom = width - self.WHERE_X - DotsLeft(self.XP_RIGHT) - 10
    local y, used, opened = 0, 0, false
    for index = self.offset + 1, #plan.steps do
        if y >= height then break end
        local step = plan.steps[index]
        used = used + 1
        local row = self:Row(used)
        row.step = step

        local open = self:IsOpen(step, plan)
        local back = step.current and "glassActive" or (index % 2 == 1 and "glass" or "glassAlt")
        row.stripe:SetColorTexture(Theme.Unpack(back))
        row.active:SetShown(step.current or open)
        Widgets.SetRowLight(row, 0)
        row.check:SetShown(step.done and true or false)
        row.levels:SetText(L.Format("%d to %d", step.low, step.high))
        row.levels:SetTextColor(Theme.Unpack(step.current and "accentHi" or "text"))

        -- The place wraps under the zone rather than run into the tags.
        local where, plainWhere = GrindTo60UI.WhereText(step)
        local tags, plainTags = GrindTo60UI.TagsText(step)
        local tagsWidth = plainTags ~= "" and math.ceil(Theme.TextWidth("tiny", plainTags) or 0) + 12 or 0
        local room = math.max(80, whereRoom - tagsWidth)
        local tall = (Theme.TextWidth("small", plainWhere) or 0) > room
        local rowHeight = tall and self.TALL_ROW_H or self.ROW_H
        row:SetHeight(rowHeight)
        row.where:SetWidth(room)
        row.where:SetHeight(rowHeight)
        row.where:SetWordWrap(tall)
        row.where:SetText(where)
        row.tags:SetText(tags)

        local r, g, b = Theme.Unpack(back)
        local alpha = step.done and 0.5 or 1
        FillDots(row.xp, step.xpDots, step.estimate, alpha, { r, g, b })
        FillDots(row.gold, step.goldDots, step.estimate, alpha, { r, g, b })
        for _, region in ipairs({ row.levels, row.where, row.tags, row.check }) do region:SetAlpha(alpha) end

        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 0, -y)
        row:SetPoint("TOPRIGHT", 0, -y)
        row:Show()
        y = y + rowHeight

        if open then
            opened = true
            local tallness = self:FillDetail(step, plan, width)
            self.detail:ClearAllPoints()
            self.detail:SetPoint("TOPLEFT", 0, -y)
            self.detail:SetPoint("TOPRIGHT", 0, -y)
            self.detail:SetHeight(tallness)
            self.detail:Show()
            y = y + tallness
        end
    end
    for index = used + 1, #self.rows do self.rows[index]:Hide() end
    if not opened then self.detail:Hide() end

    return footer
end
