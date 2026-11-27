-- Blackthornes Farmer -- UI/RaresView.lua
-- The Grind tab's Rares and Treasures views (Logic/Rares.lua).
--
-- A line on top ("The Barrens, your level 22. Rares near your level
-- first."), then a dark glass row a rare or chest: its icon, name and
-- spots with what it can give under them, its level, when you last saw,
-- killed or opened it, and Show Way, which points the arrow at its spots.
-- The rares of your zone are listed, near your level first; a zone with
-- none lists every one. Chests are nearest first. No drop rates.
--
-- Drawn over the Grind tab's list the way UI/GatherRoute.lua is, and only
-- while the view shows; the rows are filled again only when the list or
-- your log moved (a key per draw).

local _, ns = ...
local L = ns.L

local RaresView = ns.NewModule("RaresView")

local Theme = ns.Theme
local Widgets = ns.Widgets

RaresView.HEAD_H = 18
RaresView.HEADING_H = 18
RaresView.ROW_H = 36
RaresView.ICON = 22
RaresView.LEVEL_W = 58
RaresView.SEEN_W = 120
RaresView.BUTTON_GAP = 8

RaresView.ICONS = {
    rare = [[Interface\TargetingFrame\UI-TargetingFrame-Skull]],
    treasure = [[Interface\Icons\INV_Box_02]],
}

local function Upper(text)
    return (tostring(text or ""):upper():gsub("ä", "Ä"):gsub("ö", "Ö"):gsub("ü", "Ü"))
end

local function ButtonWidth(text)
    return math.ceil(Theme.TextWidth("small", text or "")) + 24
end

local function Rares() return ns.Rares end

--------------------------------------------------------------------------------
-- Words
--------------------------------------------------------------------------------

--- The line on top.
function RaresView.HeadText(kind, zone, level, here)
    local shown = zone and ns.Spots.Show(zone) or nil
    if kind == "treasure" then
        if here then return L.Format("%s. Treasures nearest you first.", shown) end
        if shown then return L.Format("No treasures known in %s. Every treasure we know, by zone.", shown) end
        return L["Every treasure we know, by zone."]
    end
    if here then
        if level then return L.Format("%s, your level %d. Rares near your level first.", shown, level) end
        return L.Format("%s. Rares near your level first.", shown)
    end
    if shown then return L.Format("No rares known in %s. Rares near your level first.", shown) end
    return L["Rares near your level first."]
end

--- "49.1, 33.9" for one spot, "5 spots, near 54.6, 46.2" for more; with
--- the zone in front when the list is not the zone's own.
function RaresView.SpotText(entry, zone)
    local spots = Rares().SpotsIn(entry, zone)
    local first = spots[1]
    local where = ("%.1f, %.1f"):format(first.x, first.y)
    local text = #spots > 1 and L.Format("%d spots, near %s", #spots, where) or where
    if first.zone ~= zone then text = ("%s, %s"):format(ns.Spots.Show(first.zone), text) end
    return text
end

--- The second line of a row: its spots, then what it can give.
function RaresView.SubText(entry, zone)
    local items = Rares().ItemsText(entry, 3)
    local spot = RaresView.SpotText(entry, zone)
    if items == "" then return spot end
    return ("%s  ·  %s"):format(spot, items)
end

function RaresView.LevelText(entry)
    if not entry.low then return "" end
    if entry.high and entry.high ~= entry.low then return ("%d-%d"):format(entry.low, entry.high) end
    return tostring(entry.low)
end

--- The hover, as on the map pin: "Boahn, level 19 rare", where, what it
--- can drop and when you last killed it.
function RaresView.FillTooltip(tooltip, entry, zone)
    local name = Rares().Name(entry)
    if entry.kind == "rare" then
        local level = RaresView.LevelText(entry)
        tooltip:AddLine(level ~= "" and L.Format("%s, level %s rare", name, level) or L.Format("%s, rare", name),
            Theme.Unpack("accent"))
    else
        tooltip:AddLine(name, Theme.Unpack("accent"))
    end
    tooltip:AddLine(RaresView.SpotText(entry, zone), 1, 1, 1)
    local items = Rares().ItemsText(entry)
    if items ~= "" then
        tooltip:AddLine(L.Format(entry.kind == "rare" and "Can drop: %s" or "Holds: %s", items), 1, 1, 1, true)
    end
    local last = Rares().TipText(entry)
    if last then tooltip:AddLine(last, Theme.Unpack("muted")) end
    tooltip:AddLine(L["Click to point the arrow here."], Theme.Unpack("good"))
end

--------------------------------------------------------------------------------
-- Building
--------------------------------------------------------------------------------

function RaresView:Build(panel)
    if self.frame then return self.frame end
    local frame = CreateFrame("Frame", nil, panel)
    frame:SetPoint("TOPLEFT", 8, -8)
    frame:SetPoint("BOTTOMRIGHT", -8, 26)
    frame:Hide()
    self.frame = frame

    local head = Theme.CreateLabel(frame, "small", "muted")
    head:SetPoint("TOPLEFT", 2, 0)
    head:SetPoint("TOPRIGHT", -2, 0)
    head:SetHeight(self.HEAD_H)
    self.head = head

    -- The headings, over the columns the rows draw.
    local headings = CreateFrame("Frame", nil, frame)
    headings:SetPoint("TOPLEFT", 0, -(self.HEAD_H + 4))
    headings:SetPoint("TOPRIGHT", 0, -(self.HEAD_H + 4))
    headings:SetHeight(self.HEADING_H)
    Theme.Fill(headings, "glassActive")
    self.headings = headings
    local function Heading(justify)
        local label = Theme.CreateLabel(headings, "tiny", "accent", justify)
        label:SetHeight(self.HEADING_H)
        return label
    end
    self.nameHeading = Heading()
    self.nameHeading:SetPoint("LEFT", 10 + self.ICON + 8, 0)
    self.levelHeading = Heading("CENTER")
    self.levelHeading:SetWidth(self.LEVEL_W)
    self.seenHeading = Heading()
    self.seenHeading:SetWidth(self.SEEN_W)
    self.levelHeading:SetText(L["LEVEL"])
    self.seenHeading:SetText(L["LAST SEEN"])

    self.buttonW = ButtonWidth(L["Show Way"])

    local list = Widgets.CreateRowList(frame, {
        rowHeight = self.ROW_H,
        createRow = function(row) RaresView:CreateRow(row) end,
        updateRow = function(row, entry) RaresView:FillRow(row, entry) end,
        onClick = function(entry, button)
            if button == "LeftButton" then RaresView:ShowWay(entry) end
        end,
        onEnter = function(row, entry)
            if not GameTooltip then return end
            pcall(GameTooltip.SetOwner, GameTooltip, row, "ANCHOR_RIGHT")
            RaresView.FillTooltip(GameTooltip, entry, RaresView.zone)
            GameTooltip:Show()
        end,
        onLeave = function() if GameTooltip then GameTooltip:Hide() end end,
    })
    list:SetPoint("TOPLEFT", headings, "BOTTOMLEFT", 0, -2)
    list:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    self.list = list

    local empty = Theme.CreateLabel(frame, "small", "muted", "CENTER")
    empty:SetPoint("TOP", headings, "BOTTOM", 0, -30)
    empty:Hide()
    self.empty = empty

    -- A kill, a sighting or a chest opened moves a row's LAST SEEN.
    Rares().onChange = function()
        if RaresView.frame and RaresView.frame:IsShown() then
            RaresView.key = nil
            RaresView:Update()
        end
    end
    return frame
end

--- Point the arrow at `entry`, and light its row.
function RaresView:ShowWay(entry)
    Rares():ShowWay(entry, self.zone)
    if self.list then self.list:Refresh() end
end

--- Place the level and seen headings over the rows' columns.
function RaresView:PlaceHeadings()
    local right = self.buttonW + self.BUTTON_GAP + 22
    self.seenHeading:ClearAllPoints()
    self.seenHeading:SetPoint("RIGHT", self.headings, "RIGHT", -right, 0)
    self.levelHeading:ClearAllPoints()
    self.levelHeading:SetPoint("RIGHT", self.seenHeading, "LEFT", -6, 0)
end

function RaresView:CreateRow(row)
    -- The one the arrow follows: a bright gold edge down its left.
    row.active = row:CreateTexture(nil, "OVERLAY", nil, 1)
    row.active:SetPoint("TOPLEFT")
    row.active:SetPoint("BOTTOMLEFT")
    row.active:SetWidth(2)
    row.active:SetColorTexture(Theme.Unpack("accentHi"))

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(self.ICON, self.ICON)
    row.icon:SetPoint("LEFT", 10, 0)

    row.button = Widgets.CreateButton(row, L["Show Way"], function(button)
        local entry = button:GetParent().data
        if entry then RaresView:ShowWay(entry) end
    end, { primary = true, width = self.buttonW, height = 20 })
    row.button:SetPoint("RIGHT", row, "RIGHT", -self.BUTTON_GAP, 0)

    row.seen = Theme.CreateLabel(row, "small", "muted")
    row.seen:SetWidth(self.SEEN_W)
    row.seen:SetPoint("RIGHT", row.button, "LEFT", -self.BUTTON_GAP, 0)

    row.level = Theme.CreateLabel(row, "small", "text", "CENTER")
    row.level:SetWidth(self.LEVEL_W)
    row.level:SetPoint("RIGHT", row.seen, "LEFT", -6, 0)

    row.name = Theme.CreateLabel(row, "small", "text")
    row.name:SetPoint("TOPLEFT", 10 + self.ICON + 8, -4)
    row.name:SetPoint("RIGHT", row.level, "LEFT", -6, 0)
    row.name:SetHeight(14)

    row.sub = Theme.CreateLabel(row, "tiny", "muted")
    row.sub:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -2)
    row.sub:SetPoint("RIGHT", row.level, "LEFT", -6, 0)
    row.sub:SetHeight(14)
    if row.sub.SetWordWrap then row.sub:SetWordWrap(false) end
end

function RaresView:FillRow(row, entry)
    local camp = ns.Arrow and ns.Arrow.grind
    local followed = type(camp) == "table" and camp.rare == entry
    row.active:SetShown(followed)
    if followed then row.stripe:SetColorTexture(Theme.Unpack("glassActive")) end
    row.icon:SetTexture(self.ICONS[entry.kind])
    row.name:SetText(Rares().Name(entry))
    row.sub:SetText(RaresView.SubText(entry, self.zone))
    row.level:SetText(RaresView.LevelText(entry))
    local gap = Rares().LevelGap(entry, self.level)
    row.level:SetTextColor(Theme.Unpack(gap == 0 and "text" or (entry.low and self.level and entry.low > self.level + 2)
        and "warn" or "muted"))
    local words, color = Rares().SeenText(entry, self.now)
    row.seen:SetText(words)
    row.seen:SetTextColor(Theme.Unpack(color))
end

--------------------------------------------------------------------------------
-- Drawing
--------------------------------------------------------------------------------

--- Show or hide the view (`kind` "rares" or "treasures", nil to hide),
--- and the Grind tab's own list with it.
function RaresView:Toggle(grinding, layout)
    if not self.frame then return end
    local on = layout ~= nil
    local wasOn = self.frame:IsShown()
    self.frame:SetShown(on)
    self.kind = layout == "treasures" and "treasure" or (on and "rare" or nil)
    if grinding and (on or wasOn) then
        -- The Gather Route covers the list too: leave it hidden for it.
        local listOn = not on and not grinding.routeShown
        for _, piece in ipairs({ grinding.list, grinding.rule }) do
            if type(piece) == "table" and piece.SetShown then piece:SetShown(listOn) end
        end
        if on then
            for _, label in pairs(type(grinding.headings) == "table" and grinding.headings or {}) do
                if type(label) == "table" and label.Hide then label:Hide() end
            end
            local buttons = type(grinding.sorter) == "table" and grinding.sorter.buttons
            for _, button in pairs(type(buttons) == "table" and buttons or {}) do
                if type(button) == "table" and button.Hide then button:Hide() end
            end
        end
    end
    self.key = nil
end

--- Draw the view. Returns the footer's words.
function RaresView:Update()
    if not (self.frame and self.kind) then return "" end
    local zone, level = Rares().Here()
    local mapID, x, y
    if self.kind == "treasure" and ns.Harvest then
        local ok, m, px, py = pcall(ns.Harvest.PlayerMapPosition, ns.Harvest)
        if ok then mapID, x, y = m, px, py end
    end
    self.zone, self.level, self.now = zone, level, Rares().Clock()
    local key = table.concat({ self.kind, tostring(zone), tostring(level), tostring(Rares().version),
        tostring(mapID), x and ("%.2f,%.2f"):format(x, y) or "" }, "|")
    if key == self.key then return self.footer or "" end
    self.key = key

    local list, here = Rares():List(self.kind, zone, level, mapID, x, y)
    self.entries = list
    self.head:SetText(RaresView.HeadText(self.kind, zone, level, here))
    self.nameHeading:SetText(self.kind == "treasure" and L["TREASURE"] or L["RARE"])
    self.levelHeading:SetShown(self.kind == "rare")
    self:PlaceHeadings()
    self.list:SetData(list, true)
    self.empty:SetShown(#list == 0)
    self.empty:SetText(#list == 0 and L["Nothing known yet."] or "")

    if self.kind == "treasure" then
        self.footer = L["Tick Treasures on the Map in Settings to see them on your world map."]
    else
        self.footer = L["Tick Rares on the Map in Settings to see them on your world map."]
    end
    if Rares().PinsOn(self.kind) then self.footer = "" end
    return self.footer
end

-- An item's rarity came in late: the rows on screen take its colour.
ns.Util.OnRarity("rares", function()
    local list = RaresView.list
    if RaresView.frame and RaresView.frame:IsShown() and list then list:Refresh() end
end)
