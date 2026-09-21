-- Blackthornes Farmer -- UI/Main.lua
-- The window -- a search box, a scrolling list of results, and a footer --
-- plus the minimap button that opens it.
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
    self:BuildMinimapButton()

    -- The minimap's final size is not always settled at login, and other addons
    -- resize it afterwards, so re-seat the button once things have calmed down.
    if C_Timer and C_Timer.After then
        C_Timer.After(1, function() UI:RepositionMinimapButton() end)
    end

    -- Cheap enough to check, and catches a minimap resized at any point.
    if C_Timer and C_Timer.NewTicker then
        self.ticker = C_Timer.NewTicker(5, function()
            if Minimap and UI.lastMinimapWidth ~= Minimap:GetWidth() then
                UI:RepositionMinimapButton()
            end
        end)
    end
end

--------------------------------------------------------------------------------
-- Minimap button
--
-- Ported from Blackthornes Tradeskills so the two behave identically: drag it
-- around the ring, left-click to open. The orbit radius is derived from the
-- minimap's real size rather than assumed, because a fixed radius only clears
-- the ring on a default 140px minimap and anyone running a larger one gets the
-- button sitting on top of the map.
--------------------------------------------------------------------------------

local DEFAULT_ANGLE = math.rad(200)

function UI:BuildMinimapButton()
    if self.minimapButton or not Minimap then return end

    local button = CreateFrame("Button", "BlackthornesFarmerMinimapButton", Minimap)
    button:SetSize(31, 31)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(8)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    local background = button:CreateTexture(nil, "BACKGROUND")
    background:SetSize(20, 20)
    background:SetPoint("CENTER")
    background:SetColorTexture(Theme.Unpack("window"))

    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetSize(18, 18)
    icon:SetPoint("CENTER")
    icon:SetTexture([[Interface\Icons\Trade_Mining]])
    icon:SetTexCoord(0.1, 0.9, 0.1, 0.9)

    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT")
    border:SetTexture([[Interface\Minimap\MiniMap-TrackingBorder]])

    local function GetOrbitRadius()
        local size = Minimap:GetWidth()
        if not size or size <= 0 then size = 140 end

        return (size / 2) + (ns.db and ns.db.minimapGap or 16)
    end

    local function UpdatePosition(angle)
        local radius = GetOrbitRadius()

        button:ClearAllPoints()
        button:SetPoint("CENTER", Minimap, "CENTER",
            math.cos(angle) * radius, math.sin(angle) * radius)
    end

    button.UpdatePosition = UpdatePosition
    UpdatePosition((ns.db and ns.db.minimapAngle) or DEFAULT_ANGLE)

    -- Dragging around the minimap edge is the expected behaviour for these.
    button:SetMovable(true)
    button:RegisterForDrag("LeftButton")

    button:SetScript("OnDragStart", function(self)
        self.dragging = true
        self:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            local cx, cy = GetCursorPosition()
            local scale = UIParent:GetEffectiveScale()

            local newAngle = math.atan2((cy / scale) - my, (cx / scale) - mx)
            UpdatePosition(newAngle)

            if ns.db then ns.db.minimapAngle = newAngle end
        end)
    end)

    button:SetScript("OnDragStop", function(self)
        self.dragging = false
        self:SetScript("OnUpdate", nil)
    end)

    button:SetScript("OnClick", function()
        UI:Toggle()
    end)

    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("Blackthornes Farmer")
        GameTooltip:AddLine("Click to open", 0.7, 0.7, 0.7)
        GameTooltip:AddLine("Drag to move it round the minimap", 0.5, 0.5, 0.5)
        GameTooltip:Show()
    end)

    button:SetScript("OnLeave", function() GameTooltip:Hide() end)

    self.minimapButton = button
    self.lastMinimapWidth = Minimap:GetWidth()

    self:ApplyMinimapVisibility()
end

--- Re-seat the button at its stored angle, using the current radius.
function UI:RepositionMinimapButton()
    local button = self.minimapButton
    if not button or not button.UpdatePosition then return end

    button.UpdatePosition((ns.db and ns.db.minimapAngle) or DEFAULT_ANGLE)
    self.lastMinimapWidth = Minimap and Minimap:GetWidth()
end

function UI:ApplyMinimapVisibility()
    local button = self.minimapButton
    if not button then return end

    if ns.db and ns.db.minimapHidden then
        button:Hide()
    else
        button:Show()
    end
end

--- Show or hide the button. Returns true when it ends up visible.
function UI:ToggleMinimapButton()
    if ns.db then
        ns.db.minimapHidden = not ns.db.minimapHidden
    end

    self:ApplyMinimapVisibility()
    return not (ns.db and ns.db.minimapHidden)
end

ns.RegisterCommand("minimap", "show or hide the minimap button", function()
    local shown = ns.UI:ToggleMinimapButton()

    if shown then
        ns.Print("minimap button shown.")
    else
        ns.Print("minimap button hidden. /farm minimap brings it back.")
    end
end)
