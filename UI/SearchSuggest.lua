-- Blackthornes Farmer -- UI/SearchSuggest.lua
-- The list of names under a search box, as you type.
--
-- The owner said build it (2026-11-26, Docs/mockups/farmer-improve-8 in the
-- project files). Search:Suggest finds the names; this draws up to eight of
-- them in dark glass lines under the box, each tagged Item, Mob or Zone.
-- Arrow keys pick a line and Enter opens it; a click opens it too. Enter
-- with no line picked does what it did before. The list goes when you pick,
-- press Escape, clear the box or click away.
--
-- It is drawn only when the typed word changes, and nothing runs on a
-- timer. Attached to the Search tab's box.

local _, ns = ...
local L = ns.L

local SuggestUI = {}
ns.SuggestUI = SuggestUI

local Theme = ns.Theme

local ROW_H = 22
local HINT_H = 20
local ICON = 16

-- A glyph for a mob or a zone, where an item shows its icon.
local GLYPH = { mob = "D", zone = "Z" }

local function Paint(row)
    local state = row.state
    local lit = state.picked or state.hover
    row.fill:SetColorTexture(Theme.Unpack(state.picked and "glassActive"
        or (row.index % 2 == 1 and "glass" or "glassAlt")))
    if ns.Widgets.SetRowLight then ns.Widgets.SetRowLight(row, lit and 1 or 0) end
end

local function MakeRow(list, index)
    local row = CreateFrame("Button", nil, list)
    row:SetHeight(ROW_H)
    row:SetPoint("TOPLEFT", 1, -(1 + (index - 1) * ROW_H))
    row:SetPoint("TOPRIGHT", -1, -(1 + (index - 1) * ROW_H))
    row.index = index
    -- What may be unset lives in its own table, never on the frame.
    row.state = {}
    row.fill = Theme.Fill(row, index % 2 == 1 and "glass" or "glassAlt", nil, "BACKGROUND")
    local line = row:CreateTexture(nil, "BORDER")
    line:SetPoint("BOTTOMLEFT")
    line:SetPoint("BOTTOMRIGHT")
    line:SetHeight(1)
    line:SetColorTexture(Theme.Unpack("border", 0.6))
    if ns.Widgets.RowLight then ns.Widgets.RowLight(row) end

    row.icon = Theme.CreateItemIcon(row, ICON)
    row.icon:SetPoint("LEFT", 8, 0)
    row.glyph = Theme.CreatePanel(row, "header", "border")
    row.glyph:SetSize(ICON, ICON)
    row.glyph:SetPoint("LEFT", 8, 0)
    row.glyph.text = Theme.CreateLabel(row.glyph, "tiny", "accent", "CENTER")
    row.glyph.text:SetPoint("CENTER", 0, 0)

    row.tag = Theme.CreateLabel(row, "small", "muted", "RIGHT")
    row.tag:SetPoint("RIGHT", -8, 0)
    row.name = Theme.CreateLabel(row, "small", "text")
    row.name:SetPoint("LEFT", 8 + ICON + 6, 0)
    row.name:SetPoint("RIGHT", row.tag, "LEFT", -8, 0)

    row:SetScript("OnEnter", function(self) self.state.hover = true Paint(self) end)
    row:SetScript("OnLeave", function(self) self.state.hover = nil Paint(self) end)
    row:SetScript("OnClick", function(self) list.Open(self.state.entry) end)
    return row
end

--- Fill one line from a name Search:Suggest gave.
local function FillRow(row, entry)
    row.state.entry = entry
    row.name:SetText(entry.name)
    row.tag:SetText(ns.Search.SuggestTag(entry))
    if entry.kind == "item" then
        row.glyph:Hide()
        Theme.SetItemIcon(row.icon, entry.id)
        local quality = ns.Util.ItemQuality and ns.Util.ItemQuality(entry.name, entry.id)
        local hex = quality and ns.Util.QualityHex(quality)
        if hex then
            row.name:SetTextColor(tonumber(hex:sub(3, 4), 16) / 255,
                tonumber(hex:sub(5, 6), 16) / 255, tonumber(hex:sub(7, 8), 16) / 255)
        else
            row.name:SetTextColor(Theme.Unpack("text"))
        end
    else
        row.icon:Hide()
        row.glyph:Show()
        row.glyph.text:SetText(GLYPH[entry.kind] or "")
        row.name:SetTextColor(Theme.Unpack(entry.kind == "mob" and "accent" or "text"))
    end
    row:Show()
    Paint(row)
end

--- Put the list under `holder` (a Widgets.CreateSearchBox). `onPick(name)`
--- runs with the picked line's name, after the box is set to it.
function SuggestUI:Attach(holder, onPick)
    local box = holder.editBox
    local parent = holder:GetParent()

    local list = Theme.CreatePanel(parent, "glassAlt", "accent")
    list:SetPoint("TOPLEFT", holder, "BOTTOMLEFT", 0, -2)
    list:SetPoint("TOPRIGHT", holder, "BOTTOMRIGHT", 0, -2)
    list:SetFrameStrata("DIALOG")
    list:SetFrameLevel((holder:GetFrameLevel() or 1) + 20)
    list:EnableMouse(true)
    list:Hide()
    list.rows = {}
    -- What may be unset lives in its own table, never on the frame.
    local state = { found = {} }
    list.state = state
    holder.suggest = list

    list.hint = Theme.CreateLabel(list, "tiny", "dim")
    list.hint:SetText(L["Arrow keys pick a line, Enter opens it."])

    function list.Close()
        state.picked = nil
        state.query = nil
        list:Hide()
    end

    function list.Open(entry)
        if not entry then return end
        list.Close()
        holder:SetText(entry.name)
        box:ClearFocus()
        if onPick then onPick(entry.name, entry) end
    end

    function list.Pick(index)
        state.picked = index
        for i, row in ipairs(list.rows) do
            row.state.picked = (i == index) or nil
            if row:IsShown() then Paint(row) end
        end
    end

    --- Draw the names for what is typed now; nothing when it is the same
    --- word as the last draw.
    function list.Update(text)
        if not ns.Search.SuggestOn() then list.Close() return end
        local query = ns.Util.Trim(text or ""):lower()
        if query == state.query and list:IsShown() then return end
        state.query = query
        local found = ns.Search:Suggest(query)
        state.found = found
        state.picked = nil
        if #found == 0 then list:Hide() return end
        for index, entry in ipairs(found) do
            local row = list.rows[index] or MakeRow(list, index)
            list.rows[index] = row
            row.state.picked = nil
            FillRow(row, entry)
        end
        for index = #found + 1, #list.rows do list.rows[index]:Hide() end
        list.hint:ClearAllPoints()
        list.hint:SetPoint("TOPLEFT", 9, -(1 + #found * ROW_H + 4))
        list:SetHeight(2 + #found * ROW_H + HINT_H)
        list:Show()
    end

    box:HookScript("OnTextChanged", function(self, userInput)
        if userInput then list.Update(self:GetText()) end
        if self:GetText() == "" then list.Close() end
    end)

    -- Enter opens the line picked with the arrow keys; with none picked it
    -- does what it always did.
    local enter = box:GetScript("OnEnterPressed")
    box:SetScript("OnEnterPressed", function(self, ...)
        local entry = list:IsShown() and state.picked and state.found[state.picked]
        if entry then
            list.Open(entry)
            return
        end
        list.Close()
        if enter then enter(self, ...) end
    end)

    box:SetScript("OnArrowPressed", function(_, key)
        if not list:IsShown() or #state.found == 0 then return end
        local count = #state.found
        local at = state.picked or 0
        if key == "DOWN" then
            at = at % count + 1
        elseif key == "UP" then
            at = at <= 1 and count or at - 1
        else
            return
        end
        list.Pick(at)
    end)

    box:HookScript("OnEscapePressed", function() list.Close() end)

    -- Clicking a line takes the keyboard from the box first: the list
    -- stays while the mouse is on it, so the click lands.
    box:HookScript("OnEditFocusLost", function()
        if not list:IsMouseOver() then list.Close() end
    end)
    holder:HookScript("OnHide", function() list.Close() end)
    parent:HookScript("OnHide", function() list.Close() end)

    return list
end
