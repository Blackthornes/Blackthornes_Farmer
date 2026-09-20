--[[--------------------------------------------------------------------------
  Blackthorne's Farmer -- Window

  A movable frame with a search box and a scrollable list of result lines.
  Scrolling is done by hand (mouse wheel + an offset) rather than with
  FauxScrollFrame, because the faux-scroll helper's signature changed between
  client versions and this way the window behaves the same everywhere.
----------------------------------------------------------------------------]]

local BF = BlackthornesFarmer

local ROW_HEIGHT = 14
local MAX_ROWS = 20
local FRAME_WIDTH = 520
local FRAME_HEIGHT = 400

BF.UI = BF.UI or { lines = {}, offset = 0, rows = {} }
local UI = BF.UI

-- 1.12 calls script handlers with no arguments and sets the global "arg1"
-- instead; later clients pass the value in. Take whichever we were given.
-- Frames themselves come from the enclosing closure, so "this" is never needed.
local function Delta(value)
	return value or arg1
end

function UI:UpdateRows()
	local total = table.getn(self.lines)
	local maxOffset = total - MAX_ROWS
	if maxOffset < 0 then maxOffset = 0 end
	if self.offset > maxOffset then self.offset = maxOffset end
	if self.offset < 0 then self.offset = 0 end

	local i
	for i = 1, MAX_ROWS do
		local line = self.lines[i + self.offset]
		self.rows[i]:SetText(line or "")
	end

	if total > MAX_ROWS then
		self.status:SetText(BF.COLOR.dim .. "lines " .. (self.offset + 1) .. "-"
			.. (self.offset + MAX_ROWS) .. " of " .. total .. "  (mouse wheel to scroll)" .. BF.COLOR.off)
	elseif total > 0 then
		self.status:SetText(BF.COLOR.dim .. total .. " lines" .. BF.COLOR.off)
	else
		self.status:SetText(BF.COLOR.dim .. "Search an item (\"copper ore\"), a zone (\"Westfall\") "
			.. "or a category (\"herbalism\")." .. BF.COLOR.off)
	end
end

function UI:Scroll(delta)
	if not delta then return end
	self.offset = self.offset - (delta * 3)
	self:UpdateRows()
end

function UI:Run(query)
	query = BF.Trim(query or "")
	self.searchBox:SetText(query)
	if BF.db then BF.db.lastSearch = query end

	if query == "" then
		self.lines = {}
		self.offset = 0
		self:UpdateRows()
		return
	end

	local lines, total = BF:BuildLines(query, 12)
	self.lines = lines
	self.offset = 0
	self.header:SetText(BF.COLOR.item .. total .. BF.COLOR.off
		.. (total == 1 and " item matching " or " items matching ") .. "\"" .. query .. "\"")
	self:UpdateRows()
end

local function SavePosition(frame)
	if not BF.db then return end
	local point, _, relPoint, x, y = frame:GetPoint()
	BF.db.point, BF.db.relPoint, BF.db.x, BF.db.y = point, relPoint, x, y
end

function UI:Create()
	if self.frame then return self.frame end
	local C = BF.COLOR

	local f = CreateFrame("Frame", "BlackthornesFarmerFrame", UIParent)
	f:SetWidth(FRAME_WIDTH)
	f:SetHeight(FRAME_HEIGHT)
	f:SetFrameStrata("DIALOG")
	f:SetMovable(true)
	f:EnableMouse(true)
	f:EnableMouseWheel(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", function() f:StartMoving() end)
	f:SetScript("OnDragStop", function()
		f:StopMovingOrSizing()
		SavePosition(f)
	end)
	f:SetScript("OnMouseWheel", function(_, value) UI:Scroll(Delta(value)) end)

	if f.SetBackdrop then
		f:SetBackdrop({
			bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
			edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
			tile = true, tileSize = 32, edgeSize = 32,
			insets = { left = 11, right = 12, top = 12, bottom = 11 },
		})
	end

	local title = f:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	title:SetPoint("TOP", f, "TOP", 0, -16)
	title:SetText(BF.addonName)

	local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -8, -8)

	local box = CreateFrame("EditBox", "BlackthornesFarmerSearchBox", f, "InputBoxTemplate")
	box:SetWidth(330)
	box:SetHeight(20)
	box:SetAutoFocus(false)
	box:SetPoint("TOPLEFT", f, "TOPLEFT", 28, -42)
	box:SetScript("OnEnterPressed", function()
		box:ClearFocus()
		UI:Run(box:GetText())
	end)
	box:SetScript("OnEscapePressed", function()
		box:ClearFocus()
	end)
	self.searchBox = box

	local go = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	go:SetWidth(80)
	go:SetHeight(22)
	go:SetPoint("LEFT", box, "RIGHT", 12, 0)
	go:SetText("Search")
	go:SetScript("OnClick", function() UI:Run(box:GetText()) end)

	local clear = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	clear:SetWidth(60)
	clear:SetHeight(22)
	clear:SetPoint("LEFT", go, "RIGHT", 6, 0)
	clear:SetText("Clear")
	clear:SetScript("OnClick", function() UI:Run("") end)

	local header = f:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
	header:SetPoint("TOPLEFT", f, "TOPLEFT", 28, -70)
	header:SetWidth(FRAME_WIDTH - 56)
	header:SetJustifyH("LEFT")
	header:SetText("")
	self.header = header

	local i
	for i = 1, MAX_ROWS do
		local row = f:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
		row:SetPoint("TOPLEFT", f, "TOPLEFT", 28, -86 - ((i - 1) * ROW_HEIGHT))
		row:SetWidth(FRAME_WIDTH - 56)
		row:SetHeight(ROW_HEIGHT)
		row:SetJustifyH("LEFT")
		row:SetText("")
		self.rows[i] = row
	end

	local status = f:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	status:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 28, 20)
	status:SetWidth(FRAME_WIDTH - 56)
	status:SetJustifyH("LEFT")
	self.status = status

	f:Hide()
	self.frame = f
	return f
end

function UI:Position()
	if not self.frame then return end
	local db = BF.db
	self.frame:ClearAllPoints()
	if db then
		self.frame:SetPoint(db.point or "CENTER", UIParent, db.relPoint or "CENTER", db.x or 0, db.y or 40)
	else
		self.frame:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
	end
end

function BF:ShowUI(query)
	local f = self.UI:Create()
	self.UI:Position()
	f:Show()
	if query and query ~= "" then
		self.UI:Run(query)
	else
		self.UI:UpdateRows()
		self.UI.searchBox:SetFocus()
	end
end

function BF:ToggleUI()
	local f = self.UI:Create()
	if f:IsShown() then
		f:Hide()
	else
		self:ShowUI(self.db and self.db.lastSearch or "")
	end
end
