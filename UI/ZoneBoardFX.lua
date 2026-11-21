local ADDON, ns = ...
local L = ns.L

-- The Zone Board's good moments (the owner said build them from a mockup
-- whose words he approved, 2026-11-18):
--
--   The card: at a mob's 20th kill in the zone, after the 20 kill fanfare,
--   a "?" card turns over to "<mob> Unlocked!" and its best drop.
--   Zone Done: the last mob here unlocked. "<zone> Done!", its own sound
--   (Media/Sounds/zone-done.ogg, tools/make_sounds.py), off with "Zone Done
--   Banner:". The chat line and the stamp come from Logic/ZoneBoard.lua.
--   New Best: a mob just unlocked tops the zone's BEST list. A crown banner,
--   and the BEST rows slide into their new order.
--
-- Every sound asks ns.Muted() first (through Tracker.PlayFile). With
-- Effects Off nothing turns or fades: each shows and goes. Nothing is
-- saved here. One banner at a time; the next waits its turn.

local ZoneBoardFX = ns.NewModule("ZoneBoardFX")
ns.ZoneBoardFX = ZoneBoardFX

ZoneBoardFX.CARD_W, ZoneBoardFX.CARD_H = 200, 92
ZoneBoardFX.BANNER_W, ZoneBoardFX.BANNER_H = 340, 84
ZoneBoardFX.HOLD = 4          -- seconds a card or banner stays
ZoneBoardFX.FLIP = 0.5        -- seconds the card takes to turn over
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

local function Play(path)
    if ns.Tracker and ns.Tracker.PlayFile then return ns.Tracker.PlayFile(path) end
    return false
end

--- A gold edged dark box with a soft glow, the mockup's moments.
local function Box(name, width, height)
    local frame = CreateFrame("Frame", name, UIParent)
    frame:SetSize(width, height)
    frame:SetFrameStrata("HIGH")
    frame:EnableMouse(true)
    Theme.Fill(frame, "window", 0.96)
    Theme.Border(frame, "accent")
    if Theme.Halo then Theme.Halo(frame, 10, 0.5, "accent") end
    frame:SetScript("OnMouseUp", function(self) self:Hide() end)
    frame:Hide()
    return frame
end

local function Line(frame, size, key, y)
    local label = Theme.CreateLabel(frame, size, key, "CENTER")
    label:SetPoint("TOPLEFT", 10, y)
    label:SetPoint("TOPRIGHT", -10, y)
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

--- Hold, then fade and hide.
local function HoldThenGo(frame, done)
    local M = Motion()
    frame:SetAlpha(1)
    After(ZoneBoardFX.HOLD, function()
        if not frame:IsShown() then if done then done() end; return end
        if M then
            M:Run(frame, "fade", 0.4, function(p) frame:SetAlpha(1 - p) end, {
                done = function() frame:Hide(); frame:SetAlpha(1); if done then done() end end })
        else
            frame:Hide()
            if done then done() end
        end
    end)
end

--------------------------------------------------------------------------------
-- The card
--------------------------------------------------------------------------------

--- The card's words, front and back: the mob, "Unlocked!" and its best
--- drop when it has one.
function ZoneBoardFX.CardLines(entry, ranked)
    local best
    if ranked and ranked.best then
        best = L.Format("Best drop: %s", Util.ColorItem(ranked.best, ranked.bestID))
    end
    return entry.name, L["Unlocked!"], best
end

function ZoneBoardFX:BuildCard()
    if self.card then return self.card end
    local card = Box("BlackthornesFarmerZoneCard", self.CARD_W, self.CARD_H)
    card.mark = Theme.CreateLabel(card, "title", "accent", "CENTER")
    card.mark:SetPoint("CENTER")
    card.mark:SetText("?")
    card.name = Line(card, "normal", "accentHi", -18)
    card.done = Line(card, "normal", "text", -38)
    card.best = Line(card, "small", "muted", -60)
    self.card = card
    return card
end

--- The 20th kill: the card shows a "?" and turns over, CARD_DELAY seconds
--- after the fanfare. Off with /farm celebrate off, as the fanfare is.
function ZoneBoardFX:Card(entry, ranked)
    if ns.db and ns.db.trackerCelebrate == false then return end
    local name, done, best = ZoneBoardFX.CardLines(entry, ranked)
    After(ns.ZoneBoard.CARD_DELAY, function()
        local card = ZoneBoardFX:BuildCard()
        card.name:SetText(name)
        card.done:SetText(done)
        card.best:SetText(best or "")
        local function Face(back)
            card.mark:SetShown(not back)
            card.name:SetShown(back)
            card.done:SetShown(back)
            card.best:SetShown(back)
        end
        Face(false)
        ZoneBoardFX.Anchor(card)
        card:SetWidth(ZoneBoardFX.CARD_W)
        card:Show()
        local M = Motion()
        if M and M.Level() ~= "off" then
            -- Narrows to an edge, swaps faces, opens again.
            M:Run(card, "flip", ZoneBoardFX.FLIP, function(p)
                local w = math.abs(math.cos(p * math.pi))
                card:SetWidth(math.max(2, ZoneBoardFX.CARD_W * w))
                Face(p >= 0.5)
            end, { delay = 0.4, ease = false, done = function()
                card:SetWidth(ZoneBoardFX.CARD_W)
                Face(true)
                HoldThenGo(card)
            end })
        else
            Face(true)
            HoldThenGo(card)
        end
    end)
end

--------------------------------------------------------------------------------
-- Banners
--------------------------------------------------------------------------------

function ZoneBoardFX:BuildBanner()
    if self.banner then return self.banner end
    local banner = Box("BlackthornesFarmerZoneBanner", self.BANNER_W, self.BANNER_H)
    banner.title = Line(banner, "title", "accentHi", -12)
    banner.line = Line(banner, "normal", "text", -38)
    banner.foot = Line(banner, "small", "muted", -60)
    self.banner = banner
    return banner
end

--- Show the next banner waiting, if none shows.
function ZoneBoardFX:Next()
    if self.showing then return end
    local queue = self.queue
    local item = queue and table.remove(queue, 1)
    if not item then return end
    self.showing = true
    local banner = self:BuildBanner()
    banner.title:SetText(item.title)
    banner.line:SetText(item.line)
    banner.foot:SetText(item.foot or "")
    ZoneBoardFX.Anchor(banner)
    banner:SetAlpha(0)
    banner:Show()
    if item.sound then Play(item.sound) end
    local M = Motion()
    local function Land()
        HoldThenGo(banner, function()
            ZoneBoardFX.showing = false
            ZoneBoardFX:Next()
        end)
    end
    if M then
        M:Run(banner, "rise", 0.35, function(p) banner:SetAlpha(p) end, { done = Land })
    else
        banner:SetAlpha(1)
        Land()
    end
end

function ZoneBoardFX:Queue(item, delay)
    self.queue = self.queue or {}
    After(delay or 0, function()
        table.insert(ZoneBoardFX.queue, item)
        ZoneBoardFX:Next()
    end)
end

--- The Zone Done banner's words.
function ZoneBoardFX.DoneLines(zone, total, best)
    local foot
    if best then
        foot = L.Format("Best farm here: %s, %s a kill.", best.entry.name, ns.Value.Coins(best.value))
    end
    return L.Format("%s Done!", ns.Spots.Show(zone)), L.Format("All %d mobs unlocked.", total), foot
end

--- The last mob here unlocked. Off with "Zone Done Banner:".
function ZoneBoardFX:ZoneDone(zone, total, best)
    if not ns.ZoneBoard.BannerOn() then return end
    local title, line, foot = ZoneBoardFX.DoneLines(zone, total, best)
    self:Queue({ title = title, line = line, foot = foot, sound = self.SOUND_DONE },
        ns.ZoneBoard.CARD_DELAY + self.FLIP + 1)
end

--- The New Best banner's words.
function ZoneBoardFX.BestLines(zone, ranked, beaten)
    local crown = ns.TrackerUI and ns.TrackerUI.CROWN or ""
    local title = crown .. " " .. L.Format("New Best in %s!", ns.Spots.Show(zone))
    local line = L.Format("%s, %s a kill.", ranked.entry.name, ns.Value.Coins(ranked.value))
    local foot = L.Format("It beats %s by %s.", beaten.entry.name,
        ns.Value.Coins(math.max(0, ranked.value - beaten.value)))
    return title, line, foot
end

--- A mob just unlocked tops the BEST list: the crown banner, and the rows
--- slide when BEST next draws.
function ZoneBoardFX:NewBest(zone, ranked, beaten)
    if not (ranked and beaten) then return end
    local title, line, foot = ZoneBoardFX.BestLines(zone, ranked, beaten)
    if ns.ZoneBoardUI then ns.ZoneBoardUI.shuffle = ranked.entry.name end
    self:Queue({ title = title, line = line, foot = foot, sound = self.SOUND_BEST },
        ns.ZoneBoard.CARD_DELAY + self.FLIP + 1)
end
