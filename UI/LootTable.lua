-- Blackthornes Farmer -- UI/LootTable.lua
-- One mob's whole loot table, in its own window.
--
-- The kills and loot panel has room for each mob's three most common drops.
-- Click a mob there (or its "Show all" line, or type /farm loot <mob>) and this
-- lists everything it has ever dropped for you: how many corpses held each
-- item, how many you took in all, the drop rate once there are enough kills
-- for one, and what each item adds to a kill when it can be priced.
--
-- It follows the tally as you farm: loot the mob with this open and the table
-- updates.

local _, ns = ...

local LootTableUI = ns.NewModule("LootTableUI")

local Theme = ns.Theme
local Widgets = ns.Widgets
local Util = ns.Util

-- At least this wide; wider when an item's name needs it, up to MAX_WIDTH.
local WIDTH = 460
local MAX_WIDTH = 760
-- It is as tall as its rows, between these, and scrolls past the tallest.
local MIN_HEIGHT = 240
local MAX_HEIGHT = 460
local PADDING = 14
local HEADER = 32
local ROW = 20
local ICON = 16

-- Header, the numbers, the status line, where it was killed and the column
-- titles above the list; the price note under it.
-- The status line has room for two lines of text, so it wraps rather than
-- being cut off.
local STATUS_TOP = HEADER + 50
local STATUS_HEIGHT = 30
local PLACES_TOP = STATUS_TOP + STATUS_HEIGHT + 2
local PLACES_HEIGHT = 14
local COLUMNS_TOP = PLACES_TOP + PLACES_HEIGHT + 6

-- How many places the "Killed at" line names before "+N more".
local PLACES_SHOWN = 3
local TOP = COLUMNS_TOP + ROW + 4
local BOTTOM = 34

-- The number columns, right to left, in pixels.
local COLUMNS = {
    { key = "perKill", title = "PER KILL", width = 70 },
    { key = "rate",    title = "RATE",     width = 50 },
    { key = "total",   title = "TOTAL",    width = 44 },
    { key = "dropped", title = "DROPPED",  width = 64 },
}
local GAP = 6

local FALLBACK_ICON = [[Interface\Icons\INV_Misc_QuestionMark]]

local function RateColor(chance)
    if chance >= 40 then return "good" end
    if chance >= 15 then return "accent" end
    return "muted"
end

local function HexColor(hex)
    if type(hex) ~= "string" or #hex ~= 8 then return nil end

    local r = tonumber(hex:sub(3, 4), 16)
    local g = tonumber(hex:sub(5, 6), 16)
    local b = tonumber(hex:sub(7, 8), 16)
    if not (r and g and b) then return nil end

    return r / 255, g / 255, b / 255, 1
end

--------------------------------------------------------------------------------
-- What goes in it
--
-- Worked out apart from the frame, so a test can read it without one.
--------------------------------------------------------------------------------

--- The table for `mobName`: { mob, kills, session, rated, needed, coinPerKill,
--- worth, basis, where, rows }, or nil for a mob never killed.
--
-- `where` is the "Killed at" line: its places, most kills first.
--
-- Each row: { name, id, dropped ("12 of 40"), total ("x57"), rate (text or
-- nil), chance (0-100 or nil), perKill (copper or nil) }. Rates and values
-- wait for MIN_KILLS, the same rule as everywhere else: before that a rate is
-- a guess, and a guess is never shown as a number.
function LootTableUI:Table(mobName)
    local Tracker = ns.Tracker
    local loot = Tracker and Tracker:LootTable(mobName)
    if not loot then return nil end

    local Value = ns.Value
    local out = {
        mob = loot.mob,
        kills = loot.kills,
        session = loot.session,
        rated = loot.rated,
        needed = loot.needed,
        rows = {},
    }

    -- Coin is measured, not a rate: it shows from the first kill that
    -- recorded any.
    out.coinPerKill = loot.coinPerKill
    out.coinKills = loot.coinKills

    -- Kills from before places were kept have none, and say so rather than
    -- being shared out among the places that are known.
    local places = Tracker.PlacesText(loot.places, PLACES_SHOWN)
    if places then
        out.where = "Killed at: " .. places .. "."
        if loot.unplaced > 0 then
            out.where = out.where .. (" %s with no place.")
                :format(Util.Plural(loot.unplaced, "kill"))
        end
    else
        out.where = "Killed at: noted from your next kill."
    end

    if Value then
        local worth, details = Value:ForMob(mobName)
        out.worth = worth
        out.basis = details and details.basis
    end

    for _, item in ipairs(loot.items) do
        local id = Value and Value:ItemID(item.name)
        local row = {
            name = item.name,
            id = id,
            dropped = ("%d of %d"):format(item.corpses, loot.kills),
            total = ("x%d"):format(item.amount),
        }

        if loot.rated then
            row.chance = item.chance
            row.rate = Tracker.FormatChance(item.chance)

            local unit = Value and Value:UnitPrice(id)
            if unit then row.perKill = item.corpses / loot.kills * item.perCorpse * unit end
        end

        out.rows[#out.rows + 1] = row
    end

    return out
end

--------------------------------------------------------------------------------
-- Construction
--------------------------------------------------------------------------------

local function Stat(parent, x, caption)
    local label = Theme.CreateLabel(parent, "tiny", "muted")
    label:SetPoint("TOPLEFT", x, -(HEADER + 10))
    label:SetText(caption)

    local value = Theme.CreateLabel(parent, "large", "text")
    value:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -3)

    return value
end

local function CreateRow(row)
    row.hooked = false

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(ICON, ICON)
    row.icon:SetPoint("LEFT", 4, 0)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    row.cells = {}
    local right = 0

    for _, column in ipairs(COLUMNS) do
        local cell = Theme.CreateLabel(row, "small", "text", "RIGHT")
        cell:SetPoint("RIGHT", -right, 0)
        cell:SetWidth(column.width)
        row.cells[column.key] = cell
        right = right + column.width + GAP
    end

    row.name = Theme.CreateLabel(row, "small", "text")
    row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
    row.name:SetPoint("RIGHT", -right, 0)

    -- A thin bar under the rate, as on the panel.
    local rate = row.cells.rate
    row.track = row:CreateTexture(nil, "BORDER")
    row.track:SetPoint("BOTTOMRIGHT", rate, "BOTTOMRIGHT", 0, -3)
    row.track:SetSize(COLUMNS[2].width - 10, 2)
    row.track:SetColorTexture(Theme.Unpack("rowAlt"))

    row.fill = row:CreateTexture(nil, "ARTWORK")
    row.fill:SetPoint("BOTTOMLEFT", row.track, "BOTTOMLEFT")
    row.fill:SetHeight(2)
end

local function ShowItemTooltip(row)
    local data = row.data
    if not (data and GameTooltip) then return end

    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")

    local shown = data.id and pcall(GameTooltip.SetItemByID, GameTooltip, data.id)
    if not shown then GameTooltip:AddLine(data.name) end

    GameTooltip:Show()
end

local function UpdateRow(row, data)
    -- The list sets its own enter and leave the first time a row is made;
    -- add the item tooltip to them once.
    if not row.hooked then
        row:HookScript("OnEnter", ShowItemTooltip)
        row:HookScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        row.hooked = true
    end

    local look = ns.Tracker:LookOf(data.name)
    row.icon:SetTexture(look.icon or FALLBACK_ICON)

    local r, g, b, a = HexColor(look.color)
    if r then
        row.name:SetTextColor(r, g, b, a)
    else
        row.name:SetTextColor(Theme.Unpack("text"))
    end
    row.name:SetText(data.name)

    row.cells.dropped:SetText(data.dropped)
    row.cells.dropped:SetTextColor(Theme.Unpack("muted"))
    row.cells.total:SetText(data.total)

    if data.chance then
        local color = RateColor(data.chance)
        row.cells.rate:SetText(data.rate)
        row.cells.rate:SetTextColor(Theme.Unpack(color))
        row.fill:SetColorTexture(Theme.Unpack(color))
        row.fill:SetWidth(math.max(1, (COLUMNS[2].width - 10) * math.min(1, data.chance / 100)))
        row.track:Show()
        row.fill:Show()
    else
        row.cells.rate:SetText("--")
        row.cells.rate:SetTextColor(Theme.Unpack("dim"))
        row.track:Hide()
        row.fill:Hide()
    end

    if data.perKill then
        row.cells.perKill:SetText(ns.Value.Money(data.perKill))
        row.cells.perKill:SetTextColor(Theme.Unpack("good"))
    else
        row.cells.perKill:SetText("--")
        row.cells.perKill:SetTextColor(Theme.Unpack("dim"))
    end
end

function LootTableUI:Build()
    if self.frame then return self.frame end

    local frame = CreateFrame("Frame", "BlackthornesFarmerLootTable", UIParent)
    frame:SetSize(WIDTH, MAX_HEIGHT)
    frame:SetPoint("TOP", UIParent, "TOP", 0, -140)
    frame:SetFrameStrata("DIALOG")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")

    Theme.Fill(frame, "window", 0.96)
    Theme.Border(frame, "borderLit")

    frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        LootTableUI:AnchorTop()
    end)

    -- Escape closes it, like the game's own windows.
    if type(UISpecialFrames) == "table" then
        table.insert(UISpecialFrames, "BlackthornesFarmerLootTable")
    end

    local header = Theme.CreatePanel(frame, "header", false)
    header:SetPoint("TOPLEFT")
    header:SetPoint("TOPRIGHT")
    header:SetHeight(HEADER)

    local stripe = header:CreateTexture(nil, "ARTWORK")
    stripe:SetPoint("TOPLEFT")
    stripe:SetPoint("BOTTOMLEFT")
    stripe:SetWidth(3)
    stripe:SetColorTexture(Theme.Unpack("accent"))

    local title = Theme.CreateLabel(header, "large", "accent")
    title:SetPoint("LEFT", PADDING, 0)
    title:SetPoint("RIGHT", -40, 0)

    local close = Widgets.CreateButton(header, "X", function() LootTableUI:Hide() end,
        { width = 22, height = 20 })
    close:SetPoint("RIGHT", -8, 0)

    local rule = Theme.CreateDivider(frame, "borderLit")
    rule:SetPoint("TOPLEFT", header, "BOTTOMLEFT")
    rule:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT")

    -- Three numbers across the top.
    self.kills = Stat(frame, PADDING, "KILLS")
    self.worth = Stat(frame, PADDING + 130, "WORTH PER KILL")
    self.coin = Stat(frame, PADDING + 280, "COIN PER KILL")

    local status = Theme.CreateLabel(frame, "small", "muted")
    status:SetPoint("TOPLEFT", PADDING, -STATUS_TOP)
    status:SetPoint("TOPRIGHT", -PADDING, -STATUS_TOP)
    status:SetHeight(STATUS_HEIGHT)
    status:SetWordWrap(true)
    status:SetJustifyV("TOP")

    local where = Theme.CreateLabel(frame, "small", "muted")
    where:SetPoint("TOPLEFT", PADDING, -PLACES_TOP)
    where:SetPoint("TOPRIGHT", -PADDING, -PLACES_TOP)
    where:SetHeight(PLACES_HEIGHT)

    -- Column titles, on a band.
    local columns = Theme.CreatePanel(frame, "header", false)
    columns:SetPoint("TOPLEFT", 1, -COLUMNS_TOP)
    columns:SetPoint("TOPRIGHT", -1, -COLUMNS_TOP)
    columns:SetHeight(ROW)

    local itemTitle = Theme.CreateLabel(columns, "tiny", "muted")
    itemTitle:SetPoint("LEFT", PADDING - 1 + 4, 0)
    itemTitle:SetText("ITEM")

    -- The list's rows stop 14 short of its right edge for the scrollbar.
    local right = PADDING - 1 + 14
    for _, column in ipairs(COLUMNS) do
        local label = Theme.CreateLabel(columns, "tiny", "muted", "RIGHT")
        label:SetPoint("RIGHT", -right, 0)
        label:SetWidth(column.width)
        label:SetText(column.title)
        right = right + column.width + GAP
    end

    local list = Widgets.CreateRowList(frame, {
        rowHeight = ROW,
        createRow = CreateRow,
        updateRow = UpdateRow,
    })
    list:SetPoint("TOPLEFT", PADDING, -TOP)
    list:SetPoint("BOTTOMRIGHT", -PADDING, BOTTOM)

    local empty = Theme.CreateLabel(frame, "small", "muted")
    empty:SetPoint("TOPLEFT", list, "TOPLEFT", 4, -6)
    empty:SetText("Nothing has dropped from it yet.")

    local footer = Theme.CreateLabel(frame, "tiny", "dim")
    footer:SetPoint("BOTTOMLEFT", PADDING, 12)
    footer:SetPoint("BOTTOMRIGHT", -PADDING, 12)

    self.frame = frame
    self.title = title
    self.status = status
    self.where = where
    self.list = list
    self.empty = empty
    self.footer = footer

    frame:Hide()
    return frame
end

--------------------------------------------------------------------------------
-- Showing
--------------------------------------------------------------------------------

function LootTableUI:Render()
    local data = self.mob and self:Table(self.mob)

    if not data then
        self:Hide()
        return
    end

    self.data = data
    self.title:SetText(data.mob)

    self.kills:SetText(data.session > 0
        and ("%d  %s"):format(data.kills, Util.Colored("good", ("+%d"):format(data.session)))
        or tostring(data.kills))

    local Money = ns.Value and ns.Value.Money
    if data.worth and Money then
        self.worth:SetText(Money(data.worth) .. (data.basis == "tally" and "" or " (est.)"))
        self.worth:SetTextColor(Theme.Unpack("good"))
    else
        self.worth:SetText("--")
        self.worth:SetTextColor(Theme.Unpack("dim"))
    end

    if data.coinPerKill and Money then
        self.coin:SetText(Money(data.coinPerKill))
        self.coin:SetTextColor(Theme.Unpack("text"))
    else
        self.coin:SetText("--")
        self.coin:SetTextColor(Theme.Unpack("dim"))
    end

    local status
    if data.rated then
        status = ("%s, every one it has dropped. Rates are from your own kills.")
            :format(Util.Plural(#data.rows, "item"))
    else
        status = ("%s so far. Drop rates and values after %s more %s.")
            :format(Util.Plural(#data.rows, "item"), data.needed,
                data.needed == 1 and "kill" or "kills")
    end

    -- Coin started being counted after some of these kills; say how many
    -- it is from, so a short average is not mistaken for the whole tally.
    if data.coinKills < data.kills then
        status = status .. (data.coinKills > 0
            and (" Coin is from your last %s."):format(Util.Plural(data.coinKills, "kill"))
            or " Coin is counted from your next kill.")
    end
    self.status:SetText(status)
    self.where:SetText(data.where)
    self.frame:SetWidth(self:WidthFor(data.rows, status, data.where))

    self.footer:SetText(ns.Value and ns.Value:HasAuctionPrices()
        and "Prices: Blackthornes Tradeskills market value, or the vendor price if higher."
        or "Prices: vendor price. Load Blackthornes Tradeskills for market prices.")

    self.empty:SetShown(#data.rows == 0)
    self.frame:SetHeight(self:HeightFor(#data.rows))

    local offset = self.list.offset
    self.list:SetData(data.rows)

    -- A redraw after new loot keeps your place in a long list.
    if self.shownMob == data.mob then
        self.list.offset = offset
        self.list:Refresh()
    end
    self.shownMob = data.mob
end

--- Wide enough for the longest item name on one line, the status in two and
--- the places on one, between WIDTH and MAX_WIDTH.
--
-- Everything but the name column is a fixed width: the padding, the list's
-- scrollbar, the icon, and the number columns.
function LootTableUI:WidthFor(rows, status, where)
    local fixed = PADDING * 2 + 14 + 4 + ICON + 6 + 4
    for _, column in ipairs(COLUMNS) do fixed = fixed + column.width + GAP end

    local needs = 0
    for _, row in ipairs(rows or {}) do
        needs = math.max(needs, fixed + Theme.TextWidth("small", row.name))
    end

    -- Two lines of wrapped text, with some slack for where the words break.
    needs = math.max(needs, PADDING * 2 + Theme.TextWidth("small", status) / 2 + 40)

    -- The places on one line.
    needs = math.max(needs, PADDING * 2 + Theme.TextWidth("small", where) + 4)

    return math.min(MAX_WIDTH, math.max(WIDTH, math.ceil(needs)))
end

--- Tall enough for `count` rows, within MIN_HEIGHT and MAX_HEIGHT.
function LootTableUI:HeightFor(count)
    return math.max(MIN_HEIGHT, math.min(MAX_HEIGHT, TOP + count * ROW + 6 + BOTTOM))
end

-- The height follows the rows, so the window hangs from its top edge: a new
-- item lengthens it downward instead of moving it. After a drag the client
-- re-anchors to the nearest point, so pin it by its top-left again.
function LootTableUI:AnchorTop()
    local frame = self.frame
    if not frame then return end

    local ok, left, top = pcall(function() return frame:GetLeft(), frame:GetTop() end)
    if not (ok and type(left) == "number" and type(top) == "number") then return end

    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
end

--- Open the window on `mobName`. Returns false for a mob never killed.
function LootTableUI:Show(mobName)
    if not (mobName and ns.Tracker:Summary(mobName)) then return false end

    self:Build()
    self.mob = mobName
    self:Render()
    self.frame:Show()

    return true
end

function LootTableUI:Hide()
    if self.frame then self.frame:Hide() end
end

function LootTableUI:IsShown()
    return self.frame ~= nil and self.frame:IsShown()
end

--- Clicking the mob that is already open closes it again.
function LootTableUI:Toggle(mobName)
    if self:IsShown() and self.mob == mobName then
        self:Hide()
        return false
    end

    return self:Show(mobName)
end

--- Redraw if open, after new loot or a reset.
function LootTableUI:Refresh()
    if self:IsShown() then self:Render() end
end

ns.RegisterCommand("loot", "open a mob's full loot table", function(rest)
    local Tracker = ns.Tracker
    local mobName = Tracker:ResolveMob(rest or "")

    if not (mobName and LootTableUI:Show(mobName)) then
        local wanted = Util.Trim(rest or "")
        if wanted == "" then
            ns.Print("nothing killed yet. Loot something and try again.")
        else
            ns.Print(("no kills of %s yet."):format(wanted))
        end
    end
end)
