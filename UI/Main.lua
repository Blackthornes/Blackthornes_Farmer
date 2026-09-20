-- Blackthornes Farmer -- UI/Main.lua
-- The window: a search box, a scrolling list of results, and a footer.
--
-- Results follow typing rather than waiting for Enter. The database is small
-- enough to search on every keystroke, and watching the list narrow as you
-- type is how you find the thing you half-remember the name of.

local _, ns = ...

local UI = ns.NewModule("UI")

local Theme = ns.Theme
local Widgets = ns.Widgets
local Util = ns.Util

local WIDTH = 540
local HEIGHT = 420
local PADDING = 14

--------------------------------------------------------------------------------
-- Construction
--------------------------------------------------------------------------------

function UI:Build()
    if self.frame then return self.frame end

    local frame = CreateFrame("Frame", "BlackthornesFarmerFrame", UIParent)
    frame:SetSize(WIDTH, HEIGHT)
    frame:SetFrameStrata("DIALOG")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")

    Theme.Fill(frame, "window")
    Theme.Border(frame, "borderLit")

    frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        UI:SavePosition()
    end)

    -- Escape closes the window like any other panel.
    frame:SetScript("OnKeyDown", function(self, key)
        if key == "ESCAPE" then
            self:SetPropagateKeyboardInput(false)
            UI:Hide()
        else
            self:SetPropagateKeyboardInput(true)
        end
    end)
    frame:EnableKeyboard(true)
    frame:SetPropagateKeyboardInput(true)

    self.frame = frame

    self:BuildHeader()
    self:BuildBody()

    frame:Hide()
    return frame
end

function UI:BuildHeader()
    local frame = self.frame

    local header = Theme.CreatePanel(frame, "header", false)
    header:SetPoint("TOPLEFT")
    header:SetPoint("TOPRIGHT")
    header:SetHeight(34)

    local title = Theme.CreateLabel(header, "title", "accent")
    title:SetPoint("LEFT", PADDING, 0)
    title:SetText("Blackthornes Farmer")

    local close = Widgets.CreateButton(header, "X", function() UI:Hide() end,
        { width = 22, height = 20 })
    close:SetPoint("RIGHT", -PADDING + 2, 0)

    local divider = Theme.CreateDivider(frame, "border")
    divider:SetPoint("TOPLEFT", header, "BOTTOMLEFT")
    divider:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT")

    self.header = header
end

function UI:BuildBody()
    local frame = self.frame

    local search = Widgets.CreateSearchBox(frame,
        "an item, a zone, or a profession",
        function(text) UI:Search(text, true) end)

    search:SetPoint("TOPLEFT", PADDING, -46)
    search:SetPoint("TOPRIGHT", -PADDING, -46)
    self.searchBox = search

    local summary = Theme.CreateLabel(frame, "small", "muted")
    summary:SetPoint("TOPLEFT", search, "BOTTOMLEFT", 2, -8)
    summary:SetPoint("TOPRIGHT", search, "BOTTOMRIGHT", -2, -8)
    self.summary = summary

    local panel = Theme.CreatePanel(frame, "panel", "border")
    panel:SetPoint("TOPLEFT", summary, "BOTTOMLEFT", -2, -8)
    panel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -PADDING, 34)
    self.panel = panel

    local list = Widgets.CreateLineList(panel, { rowHeight = 15, size = "small" })
    list:SetPoint("TOPLEFT", 8, -8)
    list:SetPoint("BOTTOMRIGHT", -8, 8)
    self.list = list

    local footer = Theme.CreateLabel(frame, "tiny", "dim")
    footer:SetPoint("BOTTOMLEFT", PADDING, 12)
    footer:SetPoint("BOTTOMRIGHT", -PADDING, 12)
    footer:SetText("Unmarked spots come from Classic data and are not confirmed on Forever yet.")
    self.footer = footer
end

--------------------------------------------------------------------------------
-- Searching
--------------------------------------------------------------------------------

--- Run a search and show the results.
-- @param typed  true when this came from the search box, so the box is not
--               rewritten underneath the cursor
function UI:Search(query, typed)
    self:Build()
    self:Show()

    query = Util.Trim(query or "")

    if not typed then
        self.searchBox:SetText(query)
    end

    if ns.db then
        ns.db.lastSearch = query
    end

    if query == "" then
        self.list:SetLines({})
        self.summary:SetText(("%s and %s loaded. Type to search."):format(
            Util.Plural(ns.DB:CountItems(), "item"),
            Util.Plural(ns.DB:CountSources(), "spot")))
        return
    end

    local lines, total = ns.Search:BuildLines(query, 12)
    self.list:SetLines(lines)

    self.summary:SetText(("%s matching \"%s\""):format(Util.Plural(total, "item"), query))
end

function UI:Refresh()
    if self.frame and self.frame:IsShown() then
        self:Search(self.searchBox:GetText(), true)
    end
end

--------------------------------------------------------------------------------
-- Position
--------------------------------------------------------------------------------

function UI:SavePosition()
    if not (ns.db and self.frame) then return end

    local point, _, relativePoint, x, y = self.frame:GetPoint()

    ns.db.point = point
    ns.db.relativePoint = relativePoint
    ns.db.x = x
    ns.db.y = y
end

function UI:RestorePosition()
    if not self.frame then return end

    local db = ns.db or {}

    self.frame:ClearAllPoints()
    self.frame:SetPoint(db.point or "CENTER", UIParent,
        db.relativePoint or "CENTER", db.x or 0, db.y or 40)
end

--------------------------------------------------------------------------------
-- Visibility
--------------------------------------------------------------------------------

function UI:Show()
    self:Build()

    if self.frame:IsShown() then return end

    self:RestorePosition()
    self.frame:Show()
end

function UI:Hide()
    if self.frame then
        self.frame:Hide()
    end
end

function UI:Toggle()
    self:Build()

    if self.frame:IsShown() then
        self:Hide()
        return
    end

    self:Show()
    self:Search(ns.db and ns.db.lastSearch or "")
    self.searchBox:SetFocus()
end

function UI:OnEnable()
    self:Build()
end
