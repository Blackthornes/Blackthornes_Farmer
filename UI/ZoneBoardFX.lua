local ADDON, ns = ...
local L = ns.L

-- The Zone Board's good moments (the owner said build them from a mockup
-- whose words he approved, 2026-11-18), shown on one gold plaque placard
-- (the owner said build it from a second mockup, 2026-11-22: the card and
-- the New Best banner had landed on top of each other):
--
--   Unlocked: at a mob's 20th kill in the zone, after the 20 kill fanfare,
--   a "?" turns over to the "Unlocked!" ribbon, the mob and its best drop.
--   When that mob also tops the zone's BEST list, a crown line joins the
--   same placard ("New Best in %s!", "Beats %s."), with the rank-up sound,
--   and the BEST rows slide into their new order. One placard, never two.
--   Zone Done: the last mob here unlocked. "<zone> Done!", its own sound
--   (Media/Sounds/zone-done.ogg, tools/make_sounds.py), off with "Zone Done
--   Banner:". It waits until the placard before it has gone. The chat line
--   and the stamp come from Logic/ZoneBoard.lua.
--
-- Every moment goes through one queue and shows on one frame, one at a
-- time. The look is the gold plaque's (UI/Plaque.lua): gold rim, warm dark
-- glass, a soft gold glow and a small red close X. No red gems on the ends
-- (the owner, 2026-11-22). A click anywhere closes it. Kill worth stays on
-- the board and the Grind tab; the placard shows no coins. Every sound asks
-- ns.Muted() first (through Tracker.PlayFile). With Effects Off nothing
-- turns, fades or glows: each shows and goes. Nothing is saved here.

local ZoneBoardFX = ns.NewModule("ZoneBoardFX")
ns.ZoneBoardFX = ZoneBoardFX

ZoneBoardFX.WIDTH = 270
ZoneBoardFX.PAD = 14
ZoneBoardFX.ICON = 26
ZoneBoardFX.HOLD = 4          -- seconds a placard stays
ZoneBoardFX.FLIP = 0.5        -- seconds the "?" takes to turn over
ZoneBoardFX.SOUND_DONE = ([[Interface\AddOns\%s\Media\Sounds\zone-done.ogg]]):format(ADDON)
ZoneBoardFX.SOUND_BEST = ([[Interface\AddOns\%s\Media\Sounds\rank-up.ogg]]):format(ADDON)

local Theme, Util = ns.Theme, ns.Util

local function After(seconds, fn)
    if type(C_Timer) == "table" and type(C_Timer.After) == "function" then
        C_Timer.After(seconds, fn)
    else
        fn()
    end
end

local function Motion() return ns.Motion end

local function Level()
    local M = Motion()
    return M and M.Level and M.Level() or "full"
end

local function Play(path)
    if ns.Tracker and ns.Tracker.PlayFile then return ns.Tracker.PlayFile(path) end
    return false
end

local function Gradient(texture, bottom, top)
    local Plaque = ns.Plaque
    if Plaque and Plaque.Gradient then return Plaque.Gradient(texture, bottom, top) end
    texture:SetColorTexture(top[1], top[2], top[3], top[4] or 1)
end

local function Colors()
    local P = ns.Plaque or {}
    return P.RIM_TOP or { 0.98, 0.89, 0.60 }, P.RIM_MID or { 0.79, 0.57, 0.18 },
        P.RIM_WAIST or { 0.54, 0.35, 0.09 }, P.RIM_FOOT or { 0.89, 0.72, 0.35 },
        P.GLASS_TOP or { 0.157, 0.125, 0.086, 0.96 }, P.GLASS_FOOT or { 0.055, 0.043, 0.031, 0.96 }
end

--- The item's icon from the client, nil when it won't say.
local function ItemIcon(itemID)
    if not itemID then return nil end
    if type(C_Item) == "table" and type(C_Item.GetItemIconByID) == "function" then
        local ok, icon = pcall(C_Item.GetItemIconByID, itemID)
        if ok and icon then return icon end
    end
    if type(GetItemIcon) == "function" then
        local ok, icon = pcall(GetItemIcon, itemID)
        if ok and icon then return icon end
    end
    return nil
end
ZoneBoardFX.ItemIcon = ItemIcon

local function Line(frame, size, key)
    local label = Theme.CreateLabel(frame, size, key, "CENTER")
    label:SetWordWrap(true)
    return label
end

--- Where a moment shows: over the board, else high in the middle of the
--- screen.
function ZoneBoardFX.Anchor(frame)
    frame:ClearAllPoints()
    local board = ns.ZoneBoardUI and ns.ZoneBoardUI.frame
    if board and board:IsShown() then
        frame:SetPoint("BOTTOM", board, "TOP", 0, 18)
    else
        frame:SetPoint("TOP", UIParent, "TOP", 0, -220)
    end
end

--------------------------------------------------------------------------------
-- The placard
--------------------------------------------------------------------------------

--- The gold plaque placard, built once.
function ZoneBoardFX:Build()
    if self.placard then return self.placard end
    local RIM_TOP, RIM_MID, RIM_WAIST, RIM_FOOT, GLASS_TOP, GLASS_FOOT = Colors()
    local f = CreateFrame("Frame", "BlackthornesFarmerZonePlacard", UIParent)
    f:SetSize(self.WIDTH, 100)
    f:SetFrameStrata("HIGH")
    f:EnableMouse(true)
    f:SetScript("OnMouseUp", function() ZoneBoardFX:Close() end)

    -- A soft gold glow on a frame of its own, off with Effects Off.
    local glow = CreateFrame("Frame", nil, f)
    glow:SetAllPoints(f)
    if Theme.Halo then Theme.Halo(glow, 10, 0.5, "accent") end
    f.glow = glow

    -- The rim, two halves so the gold has a waist, round warm dark glass.
    local rimTop = f:CreateTexture(nil, "BACKGROUND", nil, 1)
    rimTop:SetPoint("TOPLEFT")
    rimTop:SetPoint("TOPRIGHT")
    rimTop:SetPoint("BOTTOM", f, "CENTER")
    Gradient(rimTop, RIM_MID, RIM_TOP)
    local rimFoot = f:CreateTexture(nil, "BACKGROUND", nil, 1)
    rimFoot:SetPoint("BOTTOMLEFT")
    rimFoot:SetPoint("BOTTOMRIGHT")
    rimFoot:SetPoint("TOP", f, "CENTER")
    Gradient(rimFoot, RIM_FOOT, RIM_WAIST)
    local glass = f:CreateTexture(nil, "BACKGROUND", nil, 2)
    glass:SetPoint("TOPLEFT", 2, -2)
    glass:SetPoint("BOTTOMRIGHT", -2, 2)
    Gradient(glass, GLASS_FOOT, GLASS_TOP)
    local shine = f:CreateTexture(nil, "BACKGROUND", nil, 3)
    shine:SetPoint("TOPLEFT", glass, "TOPLEFT")
    shine:SetPoint("TOPRIGHT", glass, "TOPRIGHT")
    shine:SetHeight(1)
    shine:SetColorTexture(1, 0.9, 0.63, 0.18)

    -- The small red close X at the top right. No gems on the ends.
    if ns.Widgets and ns.Widgets.HeaderCloseGem then
        local ok, close = pcall(ns.Widgets.HeaderCloseGem, f, function() ZoneBoardFX:Close() end, 16)
        if ok and close then
            close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -5, -5)
            f.close = close
        end
    end

    -- The "?" before it turns over.
    f.mark = Theme.CreateLabel(f, "title", "accent", "CENTER")
    f.mark:SetPoint("CENTER")
    f.mark:SetText("?")

    -- The ribbon: a small gold band with dark lettering.
    local ribbon = CreateFrame("Frame", nil, f)
    ribbon:SetHeight(18)
    local band = ribbon:CreateTexture(nil, "BACKGROUND")
    band:SetAllPoints(ribbon)
    Gradient(band, RIM_WAIST, RIM_TOP)
    local ink = ribbon:CreateTexture(nil, "BORDER")
    ink:SetPoint("TOPLEFT", 1, -1)
    ink:SetPoint("BOTTOMRIGHT", -1, 1)
    Gradient(ink, RIM_MID, RIM_TOP)
    ribbon.text = Theme.CreateLabel(ribbon, "small", "text", "CENTER")
    ribbon.text:SetPoint("CENTER")
    pcall(ribbon.text.SetTextColor, ribbon.text, 0.16, 0.10, 0.03, 1)
    f.ribbon = ribbon

    f.title = Line(f, "title", "accentHi")

    -- The best drop row: the item's icon in a small gold frame, then words.
    local drop = CreateFrame("Frame", nil, f)
    drop:SetHeight(self.ICON + 4)
    local iconFrame = drop:CreateTexture(nil, "BORDER", nil, 1)
    iconFrame:SetSize(self.ICON + 4, self.ICON + 4)
    iconFrame:SetPoint("LEFT")
    Gradient(iconFrame, RIM_WAIST, RIM_TOP)
    local well = drop:CreateTexture(nil, "BORDER", nil, 2)
    well:SetPoint("TOPLEFT", iconFrame, "TOPLEFT", 2, -2)
    well:SetPoint("BOTTOMRIGHT", iconFrame, "BOTTOMRIGHT", -2, 2)
    well:SetColorTexture(0.105, 0.078, 0.051, 1)
    local icon = drop:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", well, "TOPLEFT", 1, -1)
    icon:SetPoint("BOTTOMRIGHT", well, "BOTTOMRIGHT", -1, 1)
    pcall(icon.SetTexCoord, icon, 0.08, 0.92, 0.08, 0.92)
    drop.icon, drop.iconFrame, drop.well = icon, iconFrame, well
    drop.text = Theme.CreateLabel(drop, "normal", "text", "LEFT")
    drop.text:SetWordWrap(true)
    f.drop = drop

    -- The crown line and what it beat, or the Zone Done lines.
    f.divider = f:CreateTexture(nil, "ARTWORK")
    f.divider:SetHeight(1)
    f.divider:SetColorTexture(RIM_MID[1], RIM_MID[2], RIM_MID[3], 0.5)
    f.line = Line(f, "normal", "accent")
    f.foot = Line(f, "small", "muted")

    f:Hide()
    self.placard = f
    return f
end

--- Put the words of `item` on the placard and stack what shows, top down.
function ZoneBoardFX:Fill(item)
    local f = self:Build()
    local PAD, W = self.PAD, self.WIDTH
    local inner = W - PAD * 2
    local y = -12

    local function Place(region, height)
        region:ClearAllPoints()
        region:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, y)
        region:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD, y)
        y = y - height
    end
    local function HeightOf(label, size)
        local text = label:GetText()
        if type(text) ~= "string" or text == "" then return 0 end
        local base = ((Theme.sizes and Theme.sizes[size]) or 12) + 4
        local ok, h = pcall(label.GetStringHeight, label)
        h = ok and tonumber(h) or 0
        return math.max(base, math.ceil(h) + 2)
    end

    f.ribbon.text:SetText(item.ribbon or "")
    local ribbonW = 90
    if ns.Plaque and ns.Plaque.TextWidth then
        ribbonW = math.max(ribbonW, ns.Plaque.TextWidth("small", item.ribbon or "") + 24)
    end
    f.ribbon:SetWidth(math.min(inner, ribbonW))
    f.ribbon:ClearAllPoints()
    f.ribbon:SetPoint("TOP", f, "TOP", 0, y)
    y = y - 24

    f.title:SetText(item.title or "")
    Place(f.title, HeightOf(f.title, "title") + 4)

    if item.drop then
        f.drop:Show()
        f.drop.text:SetText(item.drop)
        local icon = item.icon
        f.drop.icon:SetTexture(icon or [[Interface\Icons\INV_Misc_QuestionMark]])
        f.drop.text:ClearAllPoints()
        f.drop.text:SetPoint("LEFT", f.drop.iconFrame, "RIGHT", 8, 0)
        f.drop.text:SetPoint("RIGHT", f.drop, "RIGHT", 0, 0)
        Place(f.drop, self.ICON + 10)
    else
        f.drop:Hide()
    end

    local hasLine = item.line and item.line ~= ""
    f.divider:SetShown(hasLine and true or false)
    if hasLine then
        f.divider:ClearAllPoints()
        f.divider:SetPoint("TOPLEFT", f, "TOPLEFT", PAD + 20, y - 2)
        f.divider:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD - 20, y - 2)
        y = y - 8
    end
    f.line:SetText(item.line or "")
    f.line:SetShown(hasLine and true or false)
    if hasLine then Place(f.line, HeightOf(f.line, "normal")) end
    f.foot:SetText(item.foot or "")
    f.foot:SetShown((item.foot and item.foot ~= "") and true or false)
    if item.foot and item.foot ~= "" then Place(f.foot, HeightOf(f.foot, "small")) end

    f.height = math.max(80, -y + 12)
    f:SetSize(W, f.height)
    return f
end

--- One face or the other: the "?" or the words.
local function Face(f, back)
    f.mark:SetShown(not back)
    f.ribbon:SetShown(back)
    f.title:SetShown(back)
    f.drop:SetShown(back and f.hasDrop or false)
    f.divider:SetShown(back and f.hasLine or false)
    f.line:SetShown(back and f.hasLine or false)
    f.foot:SetShown(back and f.hasFoot or false)
    if f.close then f.close:SetShown(back) end
end

--- Close the placard now, and let the next moment show.
function ZoneBoardFX:Close()
    local f = self.placard
    if f then
        local M = Motion()
        if M and M.Stop then M:Stop(f, "flip"); M:Stop(f, "fade"); M:Stop(f, "rise") end
        f:Hide()
        f:SetAlpha(1)
        f:SetWidth(self.WIDTH)
    end
    self.token = (self.token or 0) + 1
    if self.showing then
        self.showing = false
        self:Next()
    end
end

--- Hold, then fade and hide, then the next one.
function ZoneBoardFX:HoldThenGo(f, token)
    After(self.HOLD, function()
        if token ~= ZoneBoardFX.token then return end
        local M = Motion()
        if M and f:IsShown() and Level() ~= "off" then
            M:Run(f, "fade", 0.4, function(p) f:SetAlpha(1 - p) end, {
                done = function()
                    if token == ZoneBoardFX.token then ZoneBoardFX:Close() end
                end })
        else
            ZoneBoardFX:Close()
        end
    end)
end

--- Show the next moment waiting, if none shows.
function ZoneBoardFX:Next()
    if self.showing then return end
    local item = self.queue and table.remove(self.queue, 1)
    if not item then return end
    self.showing = true
    self.token = (self.token or 0) + 1
    local token = self.token
    self.shown = item

    local f = self:Fill(item)
    f.hasDrop = item.drop and true or false
    f.hasLine = (item.line and item.line ~= "") and true or false
    f.hasFoot = (item.foot and item.foot ~= "") and true or false
    ZoneBoardFX.Anchor(f)
    f:SetAlpha(1)
    f:SetWidth(self.WIDTH)
    local level = Level()
    f.glow:SetShown(level ~= "off")
    if item.sound then Play(item.sound) end

    local M = Motion()
    if item.flip and M and level ~= "off" then
        -- Narrows to an edge, swaps faces, opens again.
        Face(f, false)
        f:Show()
        M:Run(f, "flip", self.FLIP, function(p)
            local w = math.abs(math.cos(p * math.pi))
            f:SetWidth(math.max(2, ZoneBoardFX.WIDTH * w))
            Face(f, p >= 0.5)
        end, { delay = 0.4, ease = false, done = function()
            f:SetWidth(ZoneBoardFX.WIDTH)
            Face(f, true)
            ZoneBoardFX:HoldThenGo(f, token)
        end })
    elseif M and level ~= "off" then
        Face(f, true)
        f:SetAlpha(0)
        f:Show()
        M:Run(f, "rise", 0.35, function(p) f:SetAlpha(p) end, {
            done = function() ZoneBoardFX:HoldThenGo(f, token) end })
    else
        Face(f, true)
        f:Show()
        self:HoldThenGo(f, token)
    end
end

--- Add a moment to the one queue after `delay` seconds. A mob's placard
--- goes before any Zone Done waiting, so the zone's cheer is always last.
function ZoneBoardFX:Queue(item, delay)
    self.queue = self.queue or {}
    After(delay or 0, function()
        local queue = ZoneBoardFX.queue
        local at = #queue + 1
        if item.kind ~= "done" then
            for index, waiting in ipairs(queue) do
                if waiting.kind == "done" then at = index; break end
            end
        end
        table.insert(queue, at, item)
        ZoneBoardFX:Next()
    end)
end

--------------------------------------------------------------------------------
-- The moments
--------------------------------------------------------------------------------

--- The unlock placard's words: the ribbon, the mob, its best drop (and the
--- drop's icon) when it has one.
function ZoneBoardFX.CardLines(entry, ranked)
    local best, icon
    if ranked and ranked.best then
        best = L.Format("Best drop: %s", Util.ColorItem(ranked.best, ranked.bestID))
        icon = ItemIcon(ranked.bestID)
    end
    return L["Unlocked!"], entry.name, best, icon
end

--- The crown line and what it beat. No coins: kill worth lives on the
--- board and the Grind tab.
function ZoneBoardFX.BestLines(zone, ranked, beaten)
    local crown = ns.TrackerUI and ns.TrackerUI.CROWN or ""
    local line = L.Format("New Best in %s!", ns.Spots.Show(zone))
    if crown ~= "" then line = crown .. " " .. line end
    return line, L.Format("Beats %s.", beaten.entry.name)
end

--- The 20th kill here: one placard, CARD_DELAY seconds after the fanfare.
--- When the mob also tops BEST (`zone` and `beaten` given), the crown line
--- joins it with the rank-up sound, and the BEST rows slide when BEST next
--- draws. With /farm celebrate off there is no "?" to turn, only the
--- crown placard when there is a new best.
function ZoneBoardFX:Card(entry, ranked, zone, beaten)
    local celebrate = not (ns.db and ns.db.trackerCelebrate == false)
    local newBest = zone and ranked and beaten
    if not celebrate and not newBest then return end
    local item = { kind = "unlock" }
    if celebrate then
        item.ribbon, item.title, item.drop, item.icon = ZoneBoardFX.CardLines(entry, ranked)
        item.flip = true
    else
        item.ribbon, item.title = L["Unlocked!"], entry.name
    end
    if newBest then
        item.line, item.foot = ZoneBoardFX.BestLines(zone, ranked, beaten)
        item.sound = self.SOUND_BEST
        if ns.ZoneBoardUI then ns.ZoneBoardUI.shuffle = ranked.entry.name end
    end
    self:Queue(item, ns.ZoneBoard.CARD_DELAY)
end

--- The Zone Done placard's words: ribbon, title, line, foot.
function ZoneBoardFX.DoneLines(zone, total, best)
    local foot
    if best then foot = L.Format("Best farm here: %s.", best.entry.name) end
    return L["Zone Done"], L.Format("%s Done!", ns.Spots.Show(zone)),
        L.Format("All %d mobs unlocked.", total), foot
end

--- The last mob here unlocked. Off with "Zone Done Banner:". It waits its
--- turn behind any placard showing or waiting.
function ZoneBoardFX:ZoneDone(zone, total, best)
    if not ns.ZoneBoard.BannerOn() then return end
    local ribbon, title, line, foot = ZoneBoardFX.DoneLines(zone, total, best)
    self:Queue({ kind = "done", ribbon = ribbon, title = title, line = line, foot = foot,
        sound = self.SOUND_DONE }, ns.ZoneBoard.CARD_DELAY + 0.1)
end
