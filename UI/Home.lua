-- Blackthornes Farmer -- UI/Home.lua
-- The Home tab: what do you want to do, and a click takes you there.
--
-- The owner said build it (2026-11-26) from a mockup whose words he
-- approved (Docs/mockups/farmer-improve-2-home-tab in the project files).
-- Farmer had grown to about fifty features and still opened on an empty
-- search box. Home is the first tab: a search box, a card for each thing
-- you can do, the best mob where you stand and your last run.
--
-- Every card opens something Farmer already has (no new data): Find an
-- Item the Search tab, Best Mobs for Me Rankings with Near My Level ticked
-- for now (the saved box is left alone), Gather the Grind tab on your best
-- gathering skill, Fish the Grind tab's Fish page, Repeat a Farm the Farms
-- tab, Level Up Grind to 60's path. A card you can't use is left out: no
-- Gather without a gathering skill, no Fish without Fishing, no Repeat a
-- Farm with Saved Farms off, no Level Up at the cap or with Grind to 60 off.
--
-- HERE reads the Zone Board's list for the zone you stand in (Logic/
-- ZoneBoard.lua) and your own gathered spots on this map. LAST RUN is the
-- newest of your saved farm runs (Logic/SavedFarms.lua, with Do It Again)
-- and your Stats sessions (Logic/Stats.lua). Home draws when it opens and
-- nothing on it runs on a timer; it only waits a moment for the Zone
-- Board's list when that is still being laid out.
--
-- Farmer opens on Home the first time (no `lastTab` saved yet). After that
-- it opens on the tab you last used, as before.

local _, ns = ...
local L = ns.L

local HomeUI = {}
ns.HomeUI = HomeUI

local Theme = ns.Theme
local Widgets = ns.Widgets

local PADDING = 14
local GAP = 8
local CARD_H = 60
local COLUMNS = 3
local HEAD_H = 22
local ROW_H = 26
local ICON = 26

-- Tries at a Zone Board list still being laid out, a moment apart.
HomeUI.WAIT_TRIES = 8
HomeUI.WAIT = 0.25

-- Each card's tile: a glyph on a colour, as on the mockup.
local TILES = {
    find = { glyph = "?", color = { 0.93, 0.90, 0.84 } },
    best = { glyph = "*", color = { 0.91, 0.76, 0.35 } },
    gather = { glyph = "H", color = { 0.20, 0.78, 0.30 } },
    fish = { glyph = "~", color = { 0.24, 0.55, 0.92 } },
    farm = { glyph = "R", color = { 0.64, 0.33, 0.90 } },
    level = { glyph = "60", color = { 0.55, 0.55, 0.55 } },
}

-- The Grind page for each gathering skill, best skill first on a tie in
-- this order.
local GATHER_PAGES = {
    { skill = "Herbalism", page = "herbs" },
    { skill = "Mining", page = "ore" },
    { skill = "Skinning", page = "skinning" },
}

local function Coins(copper)
    return ns.Coins and ns.Coins.Text(math.floor(tonumber(copper) or 0)) or tostring(copper)
end

local function Level()
    return ns.Rankings and ns.Rankings.PlayerLevel and ns.Rankings.PlayerLevel() or nil
end

local function ButtonWidth(text)
    return math.max(60, math.ceil(Theme.TextWidth("small", text)) + 24)
end

--------------------------------------------------------------------------------
-- What Home shows (no frames, so the tests can read it)
--------------------------------------------------------------------------------

--- Your gathering skills, { Herbalism = 120 }, and whether the client said.
local function Skills()
    local ok, skills = pcall(function() return ns.Spots.Skills() end)
    if not ok or type(skills) ~= "table" then return nil, false end
    return skills, true
end

--- The Grind page for your best gathering skill, or nil when you have none.
--- A client that won't say gives the page the Grind tab is on (nil).
function HomeUI.GatherPage()
    local skills, read = Skills()
    if not read then return nil, true end
    local best, page = -1, nil
    for _, entry in ipairs(GATHER_PAGES) do
        local rank = tonumber(skills[entry.skill])
        if rank and rank > best then best, page = rank, entry.page end
    end
    return page, page ~= nil
end

local function KnowsFishing()
    local ok, skill = pcall(function() return ns.Fishing:Skill() end)
    return ok and skill ~= nil
end

local function LevelUpShown()
    local To60 = ns.GrindTo60
    if not (To60 and To60.IsOn and To60.IsOn()) then return false end
    local level = Level()
    local cap = ns.XP and ns.XP.MaxLevel and ns.XP.MaxLevel() or 60
    return not (level and level >= cap)
end

--- The cards to show, in order: { key, title, text }.
function HomeUI.Cards()
    local cards = {}
    local function Add(key, title, text) cards[#cards + 1] = { key = key, title = title, text = text } end
    Add("find", L["Find an Item"], L["See which mobs drop it and where they are."])
    local level = Level()
    Add("best", L["Best Mobs for Me"], level and L.Format("The mobs worth the most near level %d.", level)
        or L["The mobs worth the most near your level."])
    local _, gathers = HomeUI.GatherPage()
    if gathers then Add("gather", L["Gather"], L["Herbs, ore and leather for your skill."]) end
    if KnowsFishing() then Add("fish", L["Fish"], L["Schools and open water near you."]) end
    if ns.SavedFarms and ns.SavedFarms.On() then
        Add("farm", L["Repeat a Farm"], L["Start one of your saved farms again."])
    end
    if LevelUpShown() then Add("level", L["Level Up"], L["Grind spots from here to 60."]) end
    return cards
end

--- The zone's name as the client says it, for the heading.
local function ClientZone()
    local ok, zone = pcall(GetRealZoneText)
    zone = ok and ns.Harvest.Readable(zone) or nil
    if zone == "" then zone = nil end
    return zone
end

--- Your herb and ore spots on the map you stand on: herbs, veins, map.
function HomeUI.SpotsHere()
    local map = ns.GatherRoute and ns.GatherRoute.Here and ns.GatherRoute.Here()
    if not map then return 0, 0, nil end
    local herbs, veins = 0, 0
    local ok, spots = pcall(ns.Gathering.SpotsOn, ns.Gathering, map)
    for _, spot in ipairs(ok and spots or {}) do
        local hidden = ns.DB and ns.DB.HidesSource and spot.node and ns.DB:HidesSource(spot.node)
        if not hidden then
            if spot.kind == "herb" then herbs = herbs + 1 elseif spot.kind == "ore" then veins = veins + 1 end
        end
    end
    return herbs, veins, map
end

--- What HERE shows: { zone, level, ready, best = { name, value },
--- locked, herbs, veins }. `ready` is false while the Zone Board's list is
--- still being laid out.
function HomeUI.Here()
    local here = { zone = ClientZone(), level = Level(), ready = true, locked = 0 }
    local ZoneBoard = ns.ZoneBoard
    local english = ZoneBoard and ZoneBoard.Here and ZoneBoard.Here()
    if english then
        here.zone = here.zone or english
        local ok, list = pcall(ZoneBoard.List, ZoneBoard, english)
        list = ok and list or nil
        if list and list.ready then
            local okRows, _, unlocked, total = pcall(ZoneBoard.Rows, ZoneBoard, list)
            if okRows then here.locked = math.max(0, (total or 0) - (unlocked or 0)) end
            local okBest, worth = pcall(ZoneBoard.Best, ZoneBoard, list)
            local top = okBest and worth and worth.ranked and worth.ranked[1]
            if top then here.best = { name = top.entry.name, value = top.value } end
        else
            here.ready = false
        end
    end
    here.herbs, here.veins = HomeUI.SpotsHere()
    return here
end

local function SavedFarmRun()
    local Farms = ns.SavedFarms
    if not (Farms and Farms.On and Farms.On()) then return nil end
    local ok, last = pcall(Farms.LastFarm, Farms)
    if not (ok and last and last.run) then return nil end
    local run, farm = last.run, last.farm
    local seconds = tonumber(run.seconds) or 0
    local out = { at = tonumber(run.at), seconds = seconds, copper = tonumber(run.copper) or 0,
        where = farm.zone, farm = farm }
    if seconds > 0 then out.rate = out.copper / seconds * 3600 end
    if farm.item and not run.kills and (tonumber(run.got) or 0) > 0 then
        out.item, out.count, out.itemCopper = farm.item, tonumber(run.got), tonumber(run.itemsCopper) or 0
    end
    return out
end

local function StatsRun()
    local Stats = ns.Stats
    local ok, store = pcall(function() return Stats and Stats:Store() end)
    if not (ok and store and type(store.sessions) == "table") then return nil end
    for index = #store.sessions, 1, -1 do
        local session = store.sessions[index]
        if type(session) == "table" and session ~= Stats.current
            and (tonumber(session.seconds) or 0) >= (Stats.SESSION_MIN or 300) then
            local seconds = tonumber(session.seconds)
            return { at = (tonumber(session.at) or 0) + seconds, seconds = seconds,
                copper = tonumber(session.copper) or 0, rate = Stats.Rate(session) }
        end
    end
    return nil
end

--- Your last run: the newer of your last saved farm run and your last
--- finished Stats session, or nil. { at, seconds, copper, rate, item,
--- count, itemCopper, where, farm }.
function HomeUI.LastRun()
    local farm, session = SavedFarmRun(), StatsRun()
    if farm and session then
        return (session.at or 0) > (farm.at or 0) and session or farm
    end
    return farm or session
end

--------------------------------------------------------------------------------
-- Where each card goes
--------------------------------------------------------------------------------

local function Tab(key)
    if ns.UI and ns.UI.ShowTab then ns.UI:ShowTab(key) end
end

HomeUI.GO = {
    find = function()
        Tab("search")
        if ns.UI.searchBox then ns.UI.searchBox:SetFocus() end
    end,
    best = function()
        -- Ticked for now, not saved: the box on Rankings unticks it.
        if ns.Rankings and not ns.Rankings.NearLevel() then ns.Rankings.nearForNow = true end
        Tab("rankings")
    end,
    gather = function()
        local page = HomeUI.GatherPage()
        if page and ns.Grinding then ns.Grinding:SetGives(page) end
        if ns.GrindTo60 and ns.GrindTo60.SetShown then ns.GrindTo60:SetShown(false) end
        Tab("grind")
    end,
    fish = function()
        if ns.Grinding then ns.Grinding:SetGives("fish") end
        if ns.GrindTo60 and ns.GrindTo60.SetShown then ns.GrindTo60:SetShown(false) end
        Tab("grind")
    end,
    farm = function() Tab("farms") end,
    level = function()
        if ns.GrindTo60 then ns.GrindTo60:SetShown(true) end
        Tab("grind")
    end,
}

--- Show Route: the Grind page for the spots you have most of here, with
--- the Gather Route walking them when it is on. Route Mode is left as it is.
function HomeUI.ShowRoute()
    local herbs, veins = HomeUI.SpotsHere()
    local page = veins > herbs and "ore" or "herbs"
    if ns.Grinding then ns.Grinding:SetGives(page) end
    if ns.GrindTo60 and ns.GrindTo60.SetShown then ns.GrindTo60:SetShown(false) end
    local Route = ns.GatherRoute
    if Route and Route.IsOn() and Route.PAGES[page] then
        pcall(Route.SetPage, Route, Route.PAGES[page])
        pcall(Route.Start, Route)
    end
    Tab("grind")
end

--------------------------------------------------------------------------------
-- Frames
--------------------------------------------------------------------------------

local function Hover(card, on)
    card.background:SetColorTexture(Theme.Unpack(on and "glassHover" or "glass"))
    Theme.SetBorderColor(card, (on or card.lit) and "accent" or "border")
end

function HomeUI:MakeCard(view)
    local card = CreateFrame("Button", nil, view)
    card:SetHeight(CARD_H)
    card.background = Theme.Fill(card, "glass")
    Theme.Border(card, "border")
    if Theme.Halo then Theme.Halo(card, 5, 0) end
    local tile = CreateFrame("Frame", nil, card)
    tile:SetSize(ICON, ICON)
    tile:SetPoint("TOPLEFT", 10, -10)
    tile.fill = tile:CreateTexture(nil, "ARTWORK")
    tile.fill:SetAllPoints(tile)
    Theme.Border(tile, "ink")
    tile.glyph = Theme.CreateLabel(tile, "normal", "ink", "CENTER")
    tile.glyph:SetPoint("CENTER", 0, 0)
    card.tile = tile
    card.title = Theme.CreateLabel(card, "normal", "heading")
    card.title:SetPoint("TOPLEFT", tile, "TOPRIGHT", 10, 1)
    card.title:SetPoint("RIGHT", -8, 0)
    card.text = Theme.CreateLabel(card, "small", "muted")
    card.text:SetPoint("TOPLEFT", card.title, "BOTTOMLEFT", 0, -3)
    card.text:SetPoint("RIGHT", -8, 0)
    card.text:SetWordWrap(true)
    card.text:SetJustifyV("TOP")
    card:SetScript("OnEnter", function(self) Hover(self, true) end)
    card:SetScript("OnLeave", function(self) Hover(self, false) end)
    card:SetScript("OnClick", function(self)
        local go = self.key and HomeUI.GO[self.key]
        if go then go() end
    end)
    return card
end

function HomeUI:SetCard(card, entry)
    card.key = entry.key
    local tile = TILES[entry.key] or TILES.find
    card.tile.fill:SetColorTexture(tile.color[1], tile.color[2], tile.color[3], 1)
    card.tile.glyph:SetText(tile.glyph)
    card.title:SetText(entry.title)
    card.text:SetText(entry.text)
    -- Best Mobs for Me wears the gold edge, as the one most players want.
    card.lit = entry.key == "best"
    Theme.SetBorderColor(card, card.lit and "accent" or "border")
    if Theme.SetHalo then Theme.SetHalo(card, card.lit and 0.12 or 0) end
end

--- A box with a gold heading and dark glass lines under it.
function HomeUI:MakeBox(view, rows)
    local box = Theme.CreatePanel(view, "glassAlt", "border")
    box.head = CreateFrame("Frame", nil, box)
    box.head:SetPoint("TOPLEFT", 1, -1)
    box.head:SetPoint("TOPRIGHT", -1, -1)
    box.head:SetHeight(HEAD_H)
    Theme.Fill(box.head, "header")
    box.title = Theme.CreateLabel(box.head, "small", "accent")
    box.title:SetPoint("LEFT", 8, 0)
    box.side = Theme.CreateLabel(box.head, "tiny", "muted", "RIGHT")
    box.side:SetPoint("RIGHT", -8, 0)
    box.title:SetPoint("RIGHT", box.side, "LEFT", -8, 0)
    box.rows = {}
    for index = 1, rows do
        local row = CreateFrame("Frame", nil, box)
        row:SetHeight(ROW_H)
        row:SetPoint("TOPLEFT", 1, -(1 + HEAD_H + (index - 1) * ROW_H))
        row:SetPoint("TOPRIGHT", -1, -(1 + HEAD_H + (index - 1) * ROW_H))
        row.fill = Theme.Fill(row, index % 2 == 1 and "glass" or "glassAlt")
        local line = row:CreateTexture(nil, "BORDER")
        line:SetPoint("BOTTOMLEFT")
        line:SetPoint("BOTTOMRIGHT")
        line:SetHeight(1)
        line:SetColorTexture(Theme.Unpack("border", 0.6))
        row.label = Theme.CreateLabel(row, "small", "dim")
        row.label:SetPoint("LEFT", 8, 0)
        row.icon = Theme.CreateItemIcon(row, 16)
        row.value = Theme.CreateLabel(row, "small", "text")
        row.right = Theme.CreateLabel(row, "small", "text", "RIGHT")
        row.right:SetPoint("RIGHT", -8, 0)
        row.button = Widgets.CreateButton(row, "", function(button)
            if button.go then button.go() end
        end, { height = 18 })
        row.button:SetPoint("RIGHT", -4, 0)
        box.rows[index] = row
    end
    box.empty = Theme.CreateLabel(box, "small", "dim", "CENTER")
    box.empty:SetPoint("TOPLEFT", 8, -(HEAD_H + 10))
    box.empty:SetPoint("TOPRIGHT", -8, -(HEAD_H + 10))
    return box
end

--- Fill one line: a dim label, a value (with an item icon when `item`), and
--- on the right either words or a button.
local function SetRow(row, label, value, opts)
    opts = opts or {}
    row:Show()
    row.label:SetText(label)
    local width = math.ceil(Theme.TextWidth("small", label)) + 8
    row.value:ClearAllPoints()
    if opts.itemID then
        row.icon:ClearAllPoints()
        row.icon:SetPoint("LEFT", 8 + width, 0)
        Theme.SetItemIcon(row.icon, opts.itemID)
        row.value:SetPoint("LEFT", row.icon, "RIGHT", 4, 0)
    else
        row.icon:Hide()
        row.value:SetPoint("LEFT", 8 + width, 0)
    end
    row.value:SetText(value or "")
    if opts.color then row.value:SetTextColor(opts.color[1], opts.color[2], opts.color[3])
    else row.value:SetTextColor(Theme.Unpack(opts.valueKey or "text")) end
    if opts.button then
        row.right:Hide()
        row.button:Show()
        row.button:SetText(opts.button)
        row.button:SetWidth(ButtonWidth(opts.button))
        row.button.go = opts.go
        row.value:SetPoint("RIGHT", row.button, "LEFT", -6, 0)
    else
        row.button:Hide()
        row.button.go = nil
        row.right:Show()
        row.right:SetText(opts.right or "")
        row.value:SetPoint("RIGHT", row.right, "LEFT", -6, 0)
    end
end

function HomeUI:Build(frame)
    if self.view then return self.view end
    local view = CreateFrame("Frame", nil, frame)
    view:SetAllPoints(frame)
    view:Hide()
    self.view = view

    local headTop = ns.UI and ns.UI.HEAD_TOP or 26
    local headLeft = ns.UI and ns.UI.HEAD_LEFT or 58
    local function Go(text)
        if ns.UI then ns.UI:Search(text or "") end
    end
    local go = Widgets.CreateButton(view, L["Search"], function()
        Go(HomeUI.searchBox:GetText())
    end, { primary = true, width = ButtonWidth(L["Search"]), height = 24 })
    go:SetPoint("TOPRIGHT", -PADDING, -headTop)
    self.goButton = go
    local search = Widgets.CreateSearchBox(view, L["Type an item, a mob or a zone"], nil, Go)
    search:SetPoint("TOPLEFT", headLeft, -headTop)
    search:SetPoint("RIGHT", go, "LEFT", -GAP, 0)
    self.searchBox = search

    self.cards = {}
    for index = 1, 6 do self.cards[index] = self:MakeCard(view) end

    self.here = self:MakeBox(view, 3)
    self.last = self:MakeBox(view, 3)
    self.last.title:SetText(L["LAST RUN"])
    return view
end

local function ViewWidth(view)
    local width = view:GetWidth()
    if type(width) ~= "number" or width <= 0 then
        width = ns.UI and ns.UI.WindowWidth and ns.UI:WindowWidth() or 724
    end
    return width
end

function HomeUI:LayoutCards(width)
    local cards = HomeUI.Cards()
    local top = (ns.UI and ns.UI.HEAD_TOP or 26) + 24 + 12
    local cardW = (width - 2 * PADDING - (COLUMNS - 1) * GAP) / COLUMNS
    for index, card in ipairs(self.cards) do
        local entry = cards[index]
        card:ClearAllPoints()
        if entry then
            local col = (index - 1) % COLUMNS
            local line = math.floor((index - 1) / COLUMNS)
            card:SetPoint("TOPLEFT", self.view, "TOPLEFT", PADDING + col * (cardW + GAP),
                -(top + line * (CARD_H + GAP)))
            card:SetWidth(cardW)
            self:SetCard(card, entry)
            card:Show()
        else
            card:Hide()
        end
    end
    local lines = math.max(1, math.ceil(#cards / COLUMNS))
    return top + lines * (CARD_H + GAP) + 4
end

function HomeUI:RenderHere(here)
    local box = self.here
    box.title:SetText(here.zone and L.Format("HERE IN %s", here.zone:upper()) or L["HERE"])
    box.side:SetText(here.level and L.Format("Level %d", here.level) or "")
    local used = 0
    local function Next() used = used + 1; return box.rows[used] end
    if here.best then
        SetRow(Next(), L["Best mob"], here.best.name,
            { valueKey = "heading", right = L.Format("%s a kill", Coins(here.best.value)) })
    end
    if here.locked > 0 then
        local zoneBoard = ns.ZoneBoard and ns.ZoneBoard.IsOn() and ns.ZoneBoardUI
        SetRow(Next(), L["Not unlocked"], here.locked == 1 and L.Format("%d mob under 20 kills", 1)
            or L.Format("%d mobs under 20 kills", here.locked),
            { button = zoneBoard and L["Zone Board"] or nil,
              go = function() if ns.ZoneBoardUI then ns.ZoneBoardUI:Toggle() end end })
    end
    if here.herbs + here.veins > 0 then
        local parts = {}
        if here.herbs > 0 then parts[#parts + 1] = (here.herbs == 1 and L.Format("%d herb", 1)
            or L.Format("%d herbs", here.herbs)) end
        if here.veins > 0 then parts[#parts + 1] = (here.veins == 1 and L.Format("%d vein", 1)
            or L.Format("%d veins", here.veins)) end
        local route = ns.GatherRoute and ns.GatherRoute.IsOn()
        SetRow(Next(), L["Your spots"], table.concat(parts, ", "),
            { button = route and L["Show Route"] or nil, go = HomeUI.ShowRoute })
    end
    for index = used + 1, #box.rows do box.rows[index]:Hide() end
    box.empty:SetShown(used == 0)
    box.empty:SetText(here.ready and L["Nothing to show here yet."] or "")
    return used
end

function HomeUI:RenderLast(run)
    local box = self.last
    local used = 0
    local function Next() used = used + 1; return box.rows[used] end
    if run then
        local Farms = ns.SavedFarms
        box.side:SetText(L.Format("%s, %s", Farms.When(run.at), Farms.Duration(run.seconds)))
        SetRow(Next(), L["Made"], Coins(run.copper),
            { right = run.rate and L.Format("%s an hour", Coins(run.rate)) or "" })
        if run.item then
            local id = ns.Value and ns.Value.ItemID and ns.Value:ItemID(run.item)
            local quality = id and ns.ItemLook and ns.ItemLook.QualityOf(id)
            local r, g, b
            if quality and ns.ItemLook then r, g, b = ns.ItemLook.Color(quality) end
            local name = (run.count or 0) > 1 and L.Format("%d %s", run.count, run.item) or run.item
            SetRow(Next(), L["Best drop"], name,
                { itemID = id, color = r and { r, g, b } or nil, right = Coins(run.itemCopper) })
        end
        if run.farm then
            local farm = run.farm
            SetRow(Next(), L["Where"], farm.zone or farm.name or "",
                { button = L["Do It Again"], go = function()
                    if ns.SavedFarms then ns.SavedFarms:Start(farm.id) end
                    HomeUI:Render()
                end })
        end
    else
        box.side:SetText("")
    end
    for index = used + 1, #box.rows do box.rows[index]:Hide() end
    box.empty:SetShown(used == 0)
    box.empty:SetText(L["Your runs show here once you finish one."])
    return used
end

--- Draw Home. Called when the tab shows (`fresh`), never on a timer.
function HomeUI:Render(fresh)
    local view = self.view
    if not (view and view:IsShown()) then return end
    if fresh then self.tries = nil end
    local width = ViewWidth(view)
    local top = self:LayoutCards(width)

    local here = HomeUI.Here()
    local hereRows = self:RenderHere(here)
    local lastRows = self:RenderLast(HomeUI.LastRun())
    local rows = math.max(1, hereRows, lastRows)
    local boxW = (width - 2 * PADDING - 2 * GAP) / 2
    local boxH = 2 + HEAD_H + rows * ROW_H
    for index, box in ipairs({ self.here, self.last }) do
        box:ClearAllPoints()
        box:SetPoint("TOPLEFT", view, "TOPLEFT", PADDING + (index - 1) * (boxW + 2 * GAP), -top)
        box:SetSize(boxW, boxH)
    end

    -- The Zone Board's list is laid out over a few frames: look again in a
    -- moment, a few times at most, while Home still shows.
    if here.ready then
        self.tries = nil
    elseif (self.tries or 0) < HomeUI.WAIT_TRIES and C_Timer and type(C_Timer.After) == "function" then
        self.tries = (self.tries or 0) + 1
        C_Timer.After(HomeUI.WAIT, function()
            if HomeUI.view and HomeUI.view:IsShown() then HomeUI:Render() end
        end)
    end
end
