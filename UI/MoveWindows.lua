-- Blackthornes -- UI/MoveWindows.lua
-- Move Windows (the owner said yes to the mockup, 2026-11-26): one screen
-- that shows a stand-in box for every Farmer piece at once, even pieces that
-- are hidden right now or show for only a few seconds, so each can be
-- dragged into place. Opened by "Move Windows:" Move on the WINDOWS page of
-- Settings and by /farm move.
--
-- Each drop saves at once, in the same saved key the piece uses when it is
-- dragged by itself (trackerX, goalsX, lootFeedX, rankUpX, arrowX, xpBarX,
-- windowSpots), so nothing new is kept for pieces that could move before.
-- Run Recap and the note stack (Bags Full, Opening) get a spot for the first
-- time: windowSpots["farmer.recap"] and windowSpots["shared.notice"], both
-- cleared by Window Locations: Set Default like every window spot. Never
-- rename them. Only boxes that were dropped are saved; the rest stay as
-- they were.
--
-- Boxes snap to each other's edges and to the screen's middle lines. Put
-- Everything Back asks to Confirm, then does what Window Locations: Set
-- Default does. The screen closes when a fight starts and won't open in
-- one. Escape closes it. Only Farmer's own frames are touched.

local _, ns = ...
local L = ns.L

local MoveWindows = {}
ns.MoveWindows = MoveWindows

MoveWindows.SNAP = 12          -- how close an edge must be to snap, in UI units
MoveWindows.RECAP_KEY = "farmer.recap"
MoveWindows.NOTICE_KEY = "shared.notice"

local BAR_HEIGHT = 44
local PAD = 12

--------------------------------------------------------------------------------
-- Screen units
--------------------------------------------------------------------------------

local function UIScale()
    local ok, scale = pcall(UIParent.GetEffectiveScale, UIParent)
    if ok and type(scale) == "number" and scale > 0 then return scale end
    return 1
end

local function ScreenSize()
    local ok, width, height = pcall(function() return UIParent:GetWidth(), UIParent:GetHeight() end)
    if not ok then return 1920, 1080 end
    return tonumber(width) or 1920, tonumber(height) or 1080
end

--- A frame's scale against UIParent's: its own units times this are UI units.
local function Ratio(frame)
    if type(frame) ~= "table" then return 1 end
    local ok, scale = pcall(frame.GetEffectiveScale, frame)
    if not (ok and type(scale) == "number" and scale > 0) then return 1 end
    return scale / UIScale()
end
MoveWindows.Ratio = Ratio

--- A frame's top left and size in UI units, or nil before it is laid out.
local function FrameRect(frame)
    if type(frame) ~= "table" then return nil end
    local ok, left, top, width, height = pcall(function()
        return frame:GetLeft(), frame:GetTop(), frame:GetWidth(), frame:GetHeight()
    end)
    if not (ok and type(left) == "number" and type(top) == "number") then return nil end
    local r = Ratio(frame)
    return left * r, top * r, (tonumber(width) or 0) * r, (tonumber(height) or 0) * r
end

local function FrameSize(frame, width, height)
    if type(frame) == "table" then
        local ok, w, h = pcall(function() return frame:GetWidth(), frame:GetHeight() end)
        local r = Ratio(frame)
        if ok and type(w) == "number" and w > 0 then width = w * r end
        if ok and type(h) == "number" and h > 0 then height = h * r end
    end
    return width, height
end

--------------------------------------------------------------------------------
-- Spots kept in windowSpots (screen pixels, read and written in every save)
--------------------------------------------------------------------------------

function MoveWindows.Spot(key)
    local sw = ns.SharedWindow
    local spots = sw and sw.ReadSave and sw.ReadSave("windowSpots")
    if type(spots) ~= "table" and ns.db then spots = ns.db.windowSpots end
    local spot = type(spots) == "table" and spots[key]
    if type(spot) == "table" and type(spot.x) == "number" and type(spot.y) == "number" then
        return spot
    end
    return nil
end

function MoveWindows.SetSpot(key, x, y)
    local sw = ns.SharedWindow
    local copy, old = {}, sw and sw.ReadSave and sw.ReadSave("windowSpots")
    if type(old) ~= "table" and ns.db then old = ns.db.windowSpots end
    if type(old) == "table" then for k, v in pairs(old) do copy[k] = v end end
    copy[key] = { x = x, y = y }
    local count = sw and sw.WriteSave and sw.WriteSave("windowSpots", copy) or 0
    if count == 0 and ns.db then ns.db.windowSpots = copy end
end

local function PutFrame(frame, left, top)
    if type(frame) ~= "table" then return end
    local r = Ratio(frame)
    pcall(function()
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left / r, top / r)
    end)
end

--------------------------------------------------------------------------------
-- The pieces
--
-- Each answers its frame (nil when not built yet), its size, where it sits
-- now (nil when that can't be told), where its box starts when it can't
-- (`home`, fractions of the screen for its top left), and `put`, which
-- saves a top left in UI units and moves the piece there.
--------------------------------------------------------------------------------

local function DB() return ns.db or {} end

MoveWindows.PIECES = {
    {
        key = "arrow", label = L["Goal Arrow"], size = { 220, 40 }, home = { 0.42, 0.86 },
        frame = function() return ns.ArrowUI and ns.ArrowUI.frame end,
        saved = function(w, h)
            local db = DB()
            local x, y = tonumber(db.arrowX), tonumber(db.arrowY)
            if x and y then return x - w / 2, y + h / 2 end
        end,
        put = function(left, top, w, h)
            ns.db.arrowX, ns.db.arrowY = left + w / 2, top - h / 2
            local ui = ns.ArrowUI
            if ui and ui.frame then
                pcall(ui.RestorePosition, ui)
            end
        end,
    },
    {
        key = "notes", label = L["Notes"], sub = L["Bags Full, Opening"], size = { 300, 40 }, home = { 0.41, 0.78 },
        saved = function(w)
            local spot = MoveWindows.Spot(MoveWindows.NOTICE_KEY)
            if spot then local s = UIScale() return spot.x / s - w / 2, spot.y / s end
        end,
        put = function(left, top, w)
            local s = UIScale()
            MoveWindows.SetSpot(MoveWindows.NOTICE_KEY, (left + w / 2) * s, top * s)
            if ns.Notice and ns.Notice.Layout then pcall(ns.Notice.Layout) end
        end,
    },
    {
        key = "recap", label = L["Run Recap"], size = { 280, 200 }, home = { 0.39, 0.62 },
        frame = function() return ns.RecapUI and ns.RecapUI.frame end,
        saved = function()
            local spot = MoveWindows.Spot(MoveWindows.RECAP_KEY)
            if spot then local s = UIScale() return spot.x / s, spot.y / s end
        end,
        put = function(left, top)
            local s = UIScale()
            MoveWindows.SetSpot(MoveWindows.RECAP_KEY, left * s, top * s)
            local ui = ns.RecapUI
            if ui and ui.frame then pcall(ui.Place, ui) end
        end,
    },
    {
        key = "rankup", label = L["Rank Up"], size = { 300, 80 }, home = { 0.42, 0.30 },
        frame = function() return ns.RankUpUI and ns.RankUpUI.frame end,
        saved = function(_, _, frame)
            local db, r = DB(), Ratio(frame)
            local x, y = tonumber(db.rankUpX), tonumber(db.rankUpY)
            if x and y then return x * r, y * r end
        end,
        put = function(left, top, _, _, frame)
            local r = Ratio(frame)
            ns.db.rankUpX, ns.db.rankUpY = left / r, top / r
            local ui = ns.RankUpUI
            if ui and ui.frame then pcall(ui.Place, ui) end
        end,
    },
    {
        key = "tracker", label = L["Kills & Loot"], size = { 260, 360 }, home = { 0.77, 0.80 },
        frame = function() return ns.TrackerUI and ns.TrackerUI.frame end,
        put = function(left, top, _, _, frame)
            local ui = ns.TrackerUI
            if not ui then return end
            frame = frame or (ui.Build and ui:Build())
            if not frame then return end
            -- As a drag would: placed, then kept for solo or for groups.
            PutFrame(frame, left, top)
            pcall(ui.SavePosition, ui)
            if ns.PanelSnap and ns.PanelSnap.TrackerDropped then pcall(ns.PanelSnap.TrackerDropped, ns.PanelSnap) end
        end,
    },
    {
        key = "goals", label = L["Goals"], size = { 236, 140 }, home = { 0.77, 0.34 },
        frame = function() return ns.GoalsUI and ns.GoalsUI.frame end,
        saved = function(_, _, frame)
            local db, r = DB(), Ratio(frame)
            local x, y = tonumber(db.goalsX), tonumber(db.goalsY)
            if x and y then return x * r, y * r end
        end,
        put = function(left, top, _, _, frame)
            local r = Ratio(frame)
            ns.db.goalsX, ns.db.goalsY = left / r, top / r
            local ui = ns.GoalsUI
            if ui and ui.frame then
                pcall(ui.RestorePosition, ui)
                -- Dropped under Kills & Loot, it hangs there again.
                if ns.PanelSnap and ns.PanelSnap.GoalsDropped then pcall(ns.PanelSnap.GoalsDropped, ns.PanelSnap) end
            end
        end,
    },
    {
        key = "lootfeed", label = L["Loot Feed"], size = { 260, 160 }, home = { 0.03, 0.40 },
        frame = function() return ns.LootFeed and ns.LootFeed.frame end,
        saved = function(_, _, frame)
            local db, r = DB(), Ratio(frame)
            local x, y = tonumber(db.lootFeedX), tonumber(db.lootFeedY)
            if x and y then return x * r, y * r end
        end,
        put = function(left, top, _, _, frame)
            local r = Ratio(frame)
            ns.db.lootFeedX, ns.db.lootFeedY = left / r, top / r
            local ui = ns.LootFeed
            if ui and ui.frame then pcall(ui.Place, ui) end
        end,
    },
    {
        key = "fishing", label = L["Fishing Panel"], size = { 340, 400 }, home = { 0.03, 0.80 },
        frame = function() return ns.FishingPanel and ns.FishingPanel.frame end,
        saved = function()
            local spot = MoveWindows.Spot("farmer.fishingpanel")
            if spot then local s = UIScale() return spot.x / s, spot.y / s end
        end,
        put = function(left, top, _, _, frame)
            local s = UIScale()
            MoveWindows.SetSpot("farmer.fishingpanel", left * s, top * s)
            if frame then PutFrame(frame, left, top) end
        end,
    },
    {
        key = "zoneboard", label = L["Zone Board"], size = { 340, 200 }, home = { 0.24, 0.24 },
        frame = function() return ns.ZoneBoardUI and ns.ZoneBoardUI.frame end,
        saved = function()
            local key = ns.ZoneBoardUI and ns.ZoneBoardUI.SPOT_KEY or "farmer.zoneboard"
            local spot = MoveWindows.Spot(key)
            if spot then local s = UIScale() return spot.x / s, spot.y / s end
        end,
        put = function(left, top, _, _, frame)
            local s = UIScale()
            MoveWindows.SetSpot(ns.ZoneBoardUI and ns.ZoneBoardUI.SPOT_KEY or "farmer.zoneboard", left * s, top * s)
            if frame then PutFrame(frame, left, top) end
        end,
    },
    {
        key = "xpbar", label = L["XP Bar"], size = { 520, 22 }, home = { 0.36, 0.06 },
        frame = function() return ns.XPBarUI and ns.XPBarUI.frame end,
        saved = function(_, _, frame)
            local db, r = DB(), Ratio(frame)
            local x, y = tonumber(db.xpBarX), tonumber(db.xpBarY)
            if db.xpBarPoint == "TOPLEFT" and db.xpBarRelPoint == "BOTTOMLEFT" and x and y then
                return x * r, y * r
            end
        end,
        put = function(left, top, _, _, frame)
            local r = Ratio(frame)
            ns.db.xpBarPoint, ns.db.xpBarRelPoint = "TOPLEFT", "BOTTOMLEFT"
            ns.db.xpBarX, ns.db.xpBarY = left / r, top / r
            local ui = ns.XPBarUI
            if ui and ui.frame then pcall(ui.Place, ui) end
            -- The arrow keeps clear of the bar.
            local arrow = ns.ArrowUI
            if arrow and arrow.frame and arrow.AvoidXPBar then pcall(arrow.AvoidXPBar, arrow) end
        end,
    },
}

--- Where a piece's box starts: the piece itself, else its saved spot, else
--- its home on the screen. Left, top, width, height in UI units.
function MoveWindows.StartRect(piece)
    local frame = piece.frame and piece.frame() or nil
    local w, h = FrameSize(frame, piece.size[1], piece.size[2])
    if piece.saved then
        local left, top = piece.saved(w, h, frame)
        if left and top then return left, top, w, h end
    end
    local left, top = FrameRect(frame)
    if left and top then return left, top, w, h end
    local sw, sh = ScreenSize()
    return sw * piece.home[1], sh * piece.home[2], w, h
end

--------------------------------------------------------------------------------
-- Snapping
--------------------------------------------------------------------------------

--- The nearest of `targets` to `value` within SNAP, else nil.
local function Nearest(value, targets)
    local best, gap
    for _, target in ipairs(targets) do
        local d = math.abs(value - target)
        if d <= MoveWindows.SNAP and (not gap or d < gap) then best, gap = target, d end
    end
    return best, gap
end

--- A dropped box's top left, snapped to the screen's middle lines and to
--- the other boxes' edges, and kept on screen. `others` holds { left, top,
--- width, height } for each other box.
function MoveWindows.Snap(left, top, w, h, others)
    local sw, sh = ScreenSize()

    -- Left edge, right edge and middle against lines on the screen.
    local xs, ys = {}, {}
    local function AddX(line, offset) xs[#xs + 1] = { line, offset } end
    local function AddY(line, offset) ys[#ys + 1] = { line, offset } end
    AddX(sw / 2, w / 2)
    AddY(sh / 2, -h / 2)
    for _, o in ipairs(others or {}) do
        local ol, ot, ow, oh = o[1], o[2], o[3], o[4]
        -- My left on its left or right; my right on its left or right.
        AddX(ol, 0) AddX(ol + ow, 0) AddX(ol, w) AddX(ol + ow, w)
        -- My top on its top or bottom; my bottom on its top or bottom.
        AddY(ot, 0) AddY(ot - oh, 0) AddY(ot, -h) AddY(ot - oh, -h)
    end

    local bestX, gapX
    for _, line in ipairs(xs) do
        local candidate = line[1] - line[2]
        local hit, gap = Nearest(left, { candidate })
        if hit and (not gapX or gap < gapX) then bestX, gapX = hit, gap end
    end
    local bestY, gapY
    for _, line in ipairs(ys) do
        local candidate = line[1] - line[2]
        local hit, gap = Nearest(top, { candidate })
        if hit and (not gapY or gap < gapY) then bestY, gapY = hit, gap end
    end
    left, top = bestX or left, bestY or top

    -- On screen.
    left = math.max(0, math.min(left, sw - w))
    top = math.min(sh, math.max(top, h))
    return left, top
end

--------------------------------------------------------------------------------
-- The screen
--------------------------------------------------------------------------------

local function InFight()
    local fn = rawget(_G, "InCombatLockdown")
    if type(fn) ~= "function" then return false end
    local ok, fighting = pcall(fn)
    return ok and fighting == true
end

local function Box(parent, piece)
    local Theme = ns.Theme
    local box = CreateFrame("Frame", nil, parent)
    box:SetFrameLevel((parent:GetFrameLevel() or 1) + 5)
    box:EnableMouse(true)
    box:SetMovable(true)
    box:SetClampedToScreen(true)
    box:RegisterForDrag("LeftButton")
    box.piece = piece

    box.fill = Theme.Fill(box, "glass", 0.82)
    Theme.Border(box, "accent", 0.75)

    local label = Theme.CreateLabel(box, "normal", "gilt")
    label:SetPoint("CENTER", box, "CENTER", 0, piece.sub and 7 or 0)
    label:SetText(piece.label)
    box.label = label
    if piece.sub then
        local sub = Theme.CreateLabel(box, "small", "muted")
        sub:SetPoint("TOP", label, "BOTTOM", 0, -2)
        sub:SetText(piece.sub)
        box.sub = sub
    end

    box:SetScript("OnEnter", function(self)
        self.fill:SetColorTexture(Theme.Unpack("glassHover", 0.9))
        Theme.SetBorderColor(self, "accentHi", 1)
    end)
    box:SetScript("OnLeave", function(self)
        self.fill:SetColorTexture(Theme.Unpack("glass", 0.82))
        Theme.SetBorderColor(self, "accent", 0.75)
    end)
    box:SetScript("OnDragStart", function(self) self:StartMoving() end)
    box:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        MoveWindows:Dropped(self)
    end)
    return box
end

local function LayBox(box, left, top, w, h)
    box.rect = { left, top, w, h }
    box:SetSize(w, h)
    box:ClearAllPoints()
    box:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
end

function MoveWindows:Build()
    if self.frame then return self.frame end
    local Theme, Widgets = ns.Theme, ns.Widgets

    local frame = CreateFrame("Frame", "BlackthornesFarmerMoveWindows", UIParent)
    frame:SetAllPoints(UIParent)
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:EnableMouse(true)
    frame:Hide()
    Theme.Fill(frame, "window", 0.35)

    -- The middle lines the boxes snap to.
    local across = frame:CreateTexture(nil, "ARTWORK")
    across:SetColorTexture(Theme.Unpack("accent", 0.25))
    across:SetPoint("LEFT") across:SetPoint("RIGHT") across:SetHeight(1)
    local down = frame:CreateTexture(nil, "ARTWORK")
    down:SetColorTexture(Theme.Unpack("accent", 0.25))
    down:SetPoint("TOP") down:SetPoint("BOTTOM") down:SetWidth(1)

    -- The bar across the top: the name, what to do, and two buttons.
    local bar = CreateFrame("Frame", nil, frame)
    bar:SetFrameLevel((frame:GetFrameLevel() or 1) + 20)
    bar:EnableMouse(true)
    Theme.Fill(bar, "window", 0.96)
    Theme.Border(bar, "borderLit")
    Theme.Halo(bar, 8, 0.15)

    local title = Theme.CreateLabel(bar, "normal", "accent")
    title:SetPoint("LEFT", bar, "LEFT", PAD + 4, 0)
    title:SetText(L["MOVE WINDOWS"])
    local hint = Theme.CreateLabel(bar, "normal", "muted")
    hint:SetPoint("LEFT", title, "RIGHT", 12, 0)
    hint:SetText(L["Drag any piece where you like."])

    local done = Widgets.CreateButton(bar, L["Done"], function() MoveWindows:Close() end,
        { primary = true, width = math.max(70, Theme.TextWidth("normal", L["Done"]) + 28), height = 24 })
    done:SetPoint("RIGHT", bar, "RIGHT", -PAD, 0)
    self.doneButton = done

    local backText = L["Put Everything Back"]
    local backWidth = math.max(Theme.TextWidth("normal", backText), Theme.TextWidth("normal", L["Confirm"])) + 28
    local back
    local function PutBack()
        if ns.SettingsUI and ns.SettingsUI.ResetAllWindows then
            ns.SettingsUI:ResetAllWindows()
        end
        MoveWindows:LayAll()
    end
    if ns.SettingsUI and ns.SettingsUI.ConfirmButton then
        back = ns.SettingsUI.ConfirmButton(bar, backText, PutBack, backWidth)
    else
        back = Widgets.CreateButton(bar, backText, PutBack, { width = backWidth, height = 24 })
    end
    back:SetPoint("RIGHT", done, "LEFT", -10, 0)
    self.backButton = back

    local width = PAD * 2 + 4 + Theme.TextWidth("normal", L["MOVE WINDOWS"]) + 12
        + Theme.TextWidth("normal", L["Drag any piece where you like."]) + 20 + backWidth + 10
        + math.max(70, Theme.TextWidth("normal", L["Done"]) + 28)
    bar:SetSize(width, BAR_HEIGHT)
    bar:SetPoint("TOP", frame, "TOP", 0, -24)
    self.bar = bar

    self.boxes = {}
    for _, piece in ipairs(self.PIECES) do
        self.boxes[#self.boxes + 1] = Box(frame, piece)
    end

    frame:SetScript("OnHide", function() MoveWindows.open = false end)
    if type(UISpecialFrames) == "table" then
        table.insert(UISpecialFrames, "BlackthornesFarmerMoveWindows")
    end

    self.frame = frame
    return frame
end

--- Every box where its piece is now.
function MoveWindows:LayAll()
    for _, box in ipairs(self.boxes or {}) do
        LayBox(box, MoveWindows.StartRect(box.piece))
    end
end

function MoveWindows:BoxFor(key)
    for _, box in ipairs(self.boxes or {}) do
        if box.piece.key == key then return box end
    end
end

--- A box was dropped: snap it, save it, and move its piece there.
function MoveWindows:Dropped(box)
    local ok, left, top = pcall(function() return box:GetLeft(), box:GetTop() end)
    if not (ok and type(left) == "number" and type(top) == "number") then return end
    local w, h = box.rect[3], box.rect[4]
    local others = {}
    for _, other in ipairs(self.boxes) do
        if other ~= box and other.rect then others[#others + 1] = other.rect end
    end
    left, top = MoveWindows.Snap(left, top, w, h, others)
    LayBox(box, left, top, w, h)
    local piece = box.piece
    local frame = piece.frame and piece.frame() or nil
    pcall(piece.put, left, top, w, h, frame)
    -- Goals hanging under Kills & Loot move with it.
    if piece.key == "tracker" or piece.key == "goals" then
        local goals = self:BoxFor("goals")
        if goals then LayBox(goals, MoveWindows.StartRect(goals.piece)) end
    end
end

function MoveWindows:Open()
    if InFight() then
        ns.Print(L["You can move windows after the fight."])
        return false
    end
    local frame = self:Build()
    self:LayAll()
    frame:Show()
    self.open = true
    return true
end

function MoveWindows:Close()
    if self.frame then self.frame:Hide() end
    self.open = false
end

function MoveWindows:IsOpen()
    return self.open == true and self.frame ~= nil and self.frame:IsShown()
end

function MoveWindows:Toggle()
    if self:IsOpen() then self:Close() else self:Open() end
end

-- Closed when a fight starts, so it is never in the way.
ns.RegisterEvent(MoveWindows, "PLAYER_REGEN_DISABLED", function(self)
    if self.open then self:Close() end
end)
