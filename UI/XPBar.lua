-- Blackthornes Farmer -- UI/XPBar.lua
-- The XP bar (the owner asked 2026-10-13, then "build it", dopamine
-- included): a bar in the house look that says more than how far into the
-- level you are, and makes earning XP feel good.
--
--   * The bar: gold for the level so far, a brighter stretch for what this
--     session earned (from a white tick), green for finished quests waiting
--     to be handed in, blue for rested XP, and a tick every tenth.
--   * Above it: played time and time on this level; what the finished
--     quests are worth and rested XP. Below it: when you reach the next
--     level at this pace, and this session's XP and XP an hour (or the kill
--     streak running).
--   * Hovering it: how to finish the level. Hand in these quests, then kill
--     about this many more of the mob you are fighting, the quests under
--     way, rested XP, this session, and the level cap at your usual pace.
--   * Small rewards: each kill's XP floats off the bar's tip, a handed-in
--     quest sends a green wave along it, each tenth crossed lights its tick
--     with a soft chime, the bar glows green while finished quests would
--     level you, your XP an hour turns gold when you beat your usual pace,
--     and a level up gets a cheer (bigger every tenth level and at the cap).
--
-- The game's own XP bar is never moved, hidden or touched by its own code.
-- "Game's XP bar" in Settings only makes it see-through (ns.Veil, SetAlpha
-- and the mouse calls, which run no game code), and puts it back.
--
-- Saved, account wide, never renamed: `xpBar`, `xpBarCheer`, `xpBarChime`
-- (on unless unticked), `xpBarHideGame` (off unless ticked), `xpBarScale`
-- and the bar's place (`xpBarPoint`, `xpBarRelPoint`, `xpBarX`, `xpBarY`).

local _, ns = ...
local L = ns.L

local XPBarUI = ns.NewModule("XPBarUI")

local Theme = ns.Theme
local Widgets = ns.Widgets
local Util = ns.Util

XPBarUI.WIDTH = 520
XPBarUI.BAR = 18
XPBarUI.LINE = 16
XPBarUI.CARD = 380
-- Seconds the cheer stays up while the mouse is away from it.
XPBarUI.HOLD = 6
XPBarUI.FADE = 0.8
XPBarUI.FLOAT = 1.3
-- How often the played time is written again while the bar shows.
XPBarUI.CLOCK = 30
-- The star at the tip breathes, and a faint light runs along the gold, by
-- Window effects: { star's grow, star's dim, seconds a breath, sweep's
-- light, sweep's speed in pixels a second, rest between sweeps }.
XPBarUI.MOTION = {
    full = { grow = 1.18, dim = 0.7, breath = 1.1, light = 0.32, speed = 90, rest = 1.5 },
    subtle = { grow = 1.07, dim = 0.88, breath = 1.6, light = 0.16, speed = 60, rest = 3 },
}
XPBarUI.SWEEP = 48
-- Where the bar sits until it is moved.
XPBarUI.HOME = { "TOP", "TOP", 0, -40 }

-- The game's XP bar, by the names the client may give it. The first found
-- is the one made see-through.
XPBarUI.GAME_BARS = { "MainStatusTrackingBarContainer", "StatusTrackingBarManager",
    "MainMenuExpBar", "MainMenuBarExpBar" }

local MEDIA = [[Interface\AddOns\Blackthornes_Farmer\Media\]]
XPBarUI.CHIME = MEDIA .. [[Sounds\xp-tick.ogg]]
local STAR = MEDIA .. [[Frame\Sparkle]]
local GLOW = MEDIA .. [[Frame\Glow]]
local COIN = [[Interface\Icons\INV_Misc_Coin_01]]

-- Rested XP's blue, the game's own colour for it.
local RESTED = { 0.35, 0.71, 1.0 }
local RESTED_HEX = "ff5ab4ff"
-- The words around the bar sit over the open world, so they are brighter
-- than the windows' text and outlined, to read on sand and snow too.
local GOLD_HEX = "fff1d488"
local GREEN_HEX = "ff6ff0a8"

local function Gold(text) return ("|c%s%s|r"):format(GOLD_HEX, text) end
local function Green(text) return ("|c%s%s|r"):format(GREEN_HEX, text) end

--- A line above or below the bar: light text, a black outline and a shadow.
local function InfoLabel(parent, justify)
    local label = Theme.CreateLabel(parent, "small", "text", justify)
    pcall(label.SetFont, label, Theme.FONT, Theme.sizes.small, "OUTLINE")
    pcall(label.SetShadowColor, label, 0, 0, 0, 0.9)
    pcall(label.SetShadowOffset, label, 1, -1)
    return label
end

--------------------------------------------------------------------------------
-- Settings
--------------------------------------------------------------------------------

function XPBarUI.On() return not (ns.db and ns.db.xpBar == false) end
function XPBarUI.CheerOn() return not (ns.db and ns.db.xpBarCheer == false) end
function XPBarUI.ChimeOn() return not (ns.db and ns.db.xpBarChime == false) end
function XPBarUI.HidesGame() return ns.db ~= nil and ns.db.xpBarHideGame == true end

--- "1 kill" for one, else the whole phrase already made with its number.
local function Count(count, single, many)
    if count == 1 then return single end
    return many
end

local function Level()
    return ns.Motion and ns.Motion.Level() or "full"
end

local Comma = function(value) return ns.XP.Comma(value) end

--------------------------------------------------------------------------------
-- Building the bar
--------------------------------------------------------------------------------

local function Texture(parent, layer, sub, r, g, b, a)
    local texture = parent:CreateTexture(nil, layer, nil, sub)
    texture:SetColorTexture(r, g, b, a)
    return texture
end

function XPBarUI:Build()
    if self.frame then return self.frame end
    local W, BAR, LINE = self.WIDTH, self.BAR, self.LINE

    local frame = CreateFrame("Frame", "BlackthornesFarmerXPBar", UIParent)
    frame:SetSize(W, LINE * 2 + BAR + 8)
    frame:SetFrameStrata("LOW")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    pcall(frame.RegisterForDrag, frame, "LeftButton")

    local topLeft = InfoLabel(frame)
    topLeft:SetPoint("TOPLEFT", frame, "TOPLEFT", 4, 0)
    local topRight = InfoLabel(frame, "RIGHT")
    topRight:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, 0)

    local bar = CreateFrame("Frame", nil, frame)
    bar:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -(LINE + 3))
    bar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, -(LINE + 3))
    bar:SetHeight(BAR)
    Theme.Fill(bar, "well", 0.95)
    Theme.Border(bar, "metal")
    Theme.Halo(bar, 7, 0.18)
    pcall(bar.SetClipsChildren, bar, true)
    self.bar = bar

    -- Gold for the level so far, with a light along its top and a shade
    -- along its bottom, so it reads as lit metal.
    self.fill = Texture(bar, "ARTWORK", 1, Theme.Unpack("accent"))
    self.sheen = Texture(bar, "ARTWORK", 3, 1, 1, 1, 0.22)
    self.shade = Texture(bar, "ARTWORK", 3, 0, 0, 0, 0.18)
    -- This session's stretch, a little brighter.
    self.session = Texture(bar, "ARTWORK", 4, 1, 1, 1, 0.16)
    -- Finished quests waiting, and rested XP after them.
    self.quest = Texture(bar, "ARTWORK", 1, Theme.Unpack("good", 0.45))
    self.rested = Texture(bar, "ARTWORK", 1, RESTED[1], RESTED[2], RESTED[3], 0.3)
    self.restedCap = Texture(bar, "ARTWORK", 5, RESTED[1], RESTED[2], RESTED[3], 1)
    self.restedCap:SetWidth(2)
    self.sessionMark = Texture(bar, "OVERLAY", 1, 1, 1, 1, 0.8)
    self.sessionMark:SetWidth(2)

    -- A tick every tenth, each with a flash for when it is crossed.
    self.ticks, self.flashes = {}, {}
    for index = 1, 9 do
        local tick = Texture(bar, "OVERLAY", 2, 0, 0, 0, 0.5)
        tick:SetWidth(1)
        self.ticks[index] = tick
        local flash = Texture(bar, "OVERLAY", 3, 1, 1, 1, 1)
        pcall(flash.SetBlendMode, flash, "ADD")
        flash:SetWidth(4)
        flash:SetAlpha(0)
        self.flashes[index] = flash
    end

    -- The spark at the tip, and the wave a quest sends along the bar.
    local spark = bar:CreateTexture(nil, "OVERLAY", nil, 4)
    spark:SetTexture(STAR)
    pcall(spark.SetBlendMode, spark, "ADD")
    spark:SetSize(BAR + 12, BAR + 12)
    self.spark = spark
    local sparkGlow = bar:CreateTexture(nil, "OVERLAY", nil, 3)
    sparkGlow:SetTexture(GLOW)
    pcall(sparkGlow.SetBlendMode, sparkGlow, "ADD")
    sparkGlow:SetSize(BAR * 2, BAR * 2)
    sparkGlow:SetPoint("CENTER", spark, "CENTER", 0, 0)
    sparkGlow:SetVertexColor(1, 0.92, 0.65, 0.5)
    self.sparkGlow = sparkGlow

    -- The light that runs along the gold, kept inside the gold.
    local sweepClip = CreateFrame("Frame", nil, bar)
    sweepClip:SetPoint("TOPLEFT", bar, "TOPLEFT", 1, -1)
    sweepClip:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 1, 1)
    sweepClip:SetWidth(1)
    pcall(sweepClip.SetClipsChildren, sweepClip, true)
    local sweep = sweepClip:CreateTexture(nil, "OVERLAY", nil, 2)
    sweep:SetTexture(GLOW)
    pcall(sweep.SetBlendMode, sweep, "ADD")
    sweep:SetSize(self.SWEEP, BAR * 2)
    sweep:SetPoint("CENTER", sweepClip, "LEFT", -self.SWEEP / 2, 0)
    sweep:SetVertexColor(1, 0.95, 0.8, 1)
    sweep:SetAlpha(0)
    self.sweepClip, self.sweep = sweepClip, sweep
    self:MakeMotion()

    local wave = bar:CreateTexture(nil, "OVERLAY", nil, 5)
    wave:SetTexture(GLOW)
    pcall(wave.SetBlendMode, wave, "ADD")
    wave:SetSize(60, BAR * 2)
    wave:SetAlpha(0)
    self.wave = wave

    -- The words on the bar sit on a frame above its textures.
    local over = CreateFrame("Frame", nil, bar)
    over:SetAllPoints(bar)
    over:SetFrameLevel((bar:GetFrameLevel() or 1) + 2)
    local label = Theme.CreateLabel(over, "normal", "text", "CENTER")
    pcall(label.SetFont, label, Theme.FONT, Theme.sizes.normal, "THICKOUTLINE")
    pcall(label.SetShadowColor, label, 0, 0, 0, 0.9)
    pcall(label.SetShadowOffset, label, 1, -1)
    label:SetPoint("CENTER", over, "CENTER", 0, 0)

    local bottomLeft = InfoLabel(frame)
    bottomLeft:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 4, 0)
    local bottomRight = InfoLabel(frame, "RIGHT")
    bottomRight:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -4, 0)

    self.labels = { topLeft = topLeft, topRight = topRight, bar = label,
        bottomLeft = bottomLeft, bottomRight = bottomRight }

    -- Numbers that float up off the tip.
    self.floats = {}
    for index = 1, 6 do
        local text = frame:CreateFontString(nil, "OVERLAY")
        pcall(text.SetFont, text, Theme.FONT, Theme.sizes.large, "OUTLINE")
        text:SetAlpha(0)
        self.floats[index] = text
    end
    self.nextFloat = 1

    frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        XPBarUI:SavePlace()
    end)
    frame:SetScript("OnEnter", function() XPBarUI:ShowCard() end)
    frame:SetScript("OnLeave", function() XPBarUI:HideCard() end)
    frame:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" then XPBarUI:OpenSettings() end
    end)
    frame:SetScript("OnUpdate", function(_, elapsed) XPBarUI:Tick(elapsed) end)

    Widgets.ApplySize(frame, ns.db and ns.db.xpBarScale)
    self.grip = Widgets.CreateSizeGrip(frame, {
        name = "panel",
        get = function() return ns.db and ns.db.xpBarScale end,
        save = function(percent) if ns.db then ns.db.xpBarScale = percent end end,
        done = function() XPBarUI:SavePlace() end,
    })
    self.grip:SetAlpha(0)
    self.grip:HookScript("OnEnter", function() XPBarUI.grip:SetAlpha(1) end)

    self.frame = frame
    self:Place()
    frame:Hide()
    return frame
end

--------------------------------------------------------------------------------
-- Where it sits
--------------------------------------------------------------------------------

function XPBarUI:Place()
    local frame, db = self.frame, ns.db or {}
    if not frame then return end
    frame:ClearAllPoints()
    local x, y = tonumber(db.xpBarX), tonumber(db.xpBarY)
    if type(db.xpBarPoint) == "string" and x and y then
        frame:SetPoint(db.xpBarPoint, UIParent, db.xpBarRelPoint or db.xpBarPoint, x, y)
    else
        local home = self.HOME
        frame:SetPoint(home[1], UIParent, home[2], home[3], home[4])
    end
end

function XPBarUI:SavePlace()
    local frame = self.frame
    if not (frame and ns.db) then return end
    local ok, point, _, relPoint, x, y = pcall(frame.GetPoint, frame)
    if ok and type(point) == "string" and type(x) == "number" and type(y) == "number" then
        ns.db.xpBarPoint, ns.db.xpBarRelPoint, ns.db.xpBarX, ns.db.xpBarY = point, relPoint, x, y
    end
end

--- Back where it started, at its normal size.
function XPBarUI:ResetPlace()
    if ns.db then
        ns.db.xpBarPoint, ns.db.xpBarRelPoint, ns.db.xpBarX, ns.db.xpBarY = nil, nil, nil, nil
        ns.db.xpBarScale = nil
    end
    if self.frame then
        Widgets.ApplySize(self.frame, 100)
        self:Place()
    end
end

function XPBarUI:OpenSettings()
    if not ns.SettingsUI then return end
    ns.SettingsUI:Show()
    local pages = ns.SettingsUI.pages
    if pages and pages.Show then pcall(pages.Show, pages, "tally") end
end

--------------------------------------------------------------------------------
-- Drawing
--------------------------------------------------------------------------------

--- `texture` from `from` to `to` of the bar (each 0 to 1).
function XPBarUI:Span(texture, from, to, top, bottom)
    local inner = self.WIDTH - 2
    from, to = math.max(0, math.min(1, from)), math.max(0, math.min(1, to))
    local width = (to - from) * inner
    if width < 1 then
        texture:Hide()
        return
    end
    texture:ClearAllPoints()
    texture:SetPoint("TOPLEFT", self.bar, "TOPLEFT", 1 + from * inner, -(top or 1))
    texture:SetPoint("BOTTOMLEFT", self.bar, "BOTTOMLEFT", 1 + from * inner, bottom or 1)
    texture:SetWidth(width)
    texture:Show()
end

--- A thin line at `at` of the bar.
function XPBarUI:Mark(texture, at)
    local inner = self.WIDTH - 2
    texture:ClearAllPoints()
    texture:SetPoint("TOP", self.bar, "TOPLEFT", 1 + at * inner, -1)
    texture:SetPoint("BOTTOM", self.bar, "BOTTOMLEFT", 1 + at * inner, 1)
    texture:Show()
end

--- Whether the bar should be up now.
function XPBarUI:Wanted()
    return XPBarUI.On() and ns.XP and ns.XP.started and ns.XP.Earning() or false
end

--- Draw the bar again from what XP knows. Cheap: a few words and widths.
function XPBarUI:Refresh()
    -- The bar coming or going mid-session (the level cap, XP turned off at
    -- a trainer) gives the game's bar back, or veils it again.
    local wanted = self:Wanted() and true or false
    if self.wasWanted ~= nil and self.wasWanted ~= wanted then self:ApplyGameBar() end
    self.wasWanted = wanted
    if not wanted then
        if self.frame then self.frame:Hide() end
        self:HideCard()
        return
    end
    local summary = ns.XP:Summary()
    if not summary then return end
    local frame = self:Build()
    frame:Show()
    self.summary = summary
    local labels = self.labels

    -- Above the bar.
    if summary.played then
        labels.topLeft:SetText(L.Format("Played %s  |  This level %s",
            ns.XP.Duration(summary.played), ns.XP.Duration(summary.levelPlayed)))
    else
        labels.topLeft:SetText(L.Format("This session %s", ns.XP.Duration(ns.XP:Seconds())))
    end

    local right = {}
    if summary.inReach then
        right[#right + 1] = Green(L["Hand in your quests to level up"])
    elseif summary.readyXP > 0 then
        right[#right + 1] = Green(L.Format("Ready to hand in: %s XP", Comma(summary.readyXP)))
    end
    if summary.rested > 0 then
        right[#right + 1] = ("|c%s%s|r"):format(RESTED_HEX, L.Format("Rested: %s XP", Comma(summary.rested)))
    end
    labels.topRight:SetText(table.concat(right, "  |  "))

    -- On the bar.
    labels.bar:SetText(L.Format("Level %d  |  %s / %s  (%.1f%%)", summary.level,
        Comma(summary.xp), Comma(summary.max), summary.share * 100))

    -- Below it.
    if summary.toLevel then
        local pace = summary.rate and L["at this session's pace"] or L["at your usual pace"]
        labels.bottomLeft:SetText(Gold(L.Format("Level %d in about %s", summary.level + 1,
            ns.XP.Duration(summary.toLevel))) .. " " .. pace)
    else
        labels.bottomLeft:SetText(L["Your pace shows after a few kills or quests"])
    end

    local streak = summary.streak
    if streak and streak.count >= 3 then
        labels.bottomRight:SetText(Gold(L.Format("%d kills in a row  |  +%s XP",
            streak.count, Comma(streak.xp))))
    else
        local parts = { L.Format("This session +%s XP", Comma(summary.session.gained)) }
        if summary.rate then
            local rate = L.Format("%s XP an hour", Comma(summary.rate))
            if summary.ahead then
                rate = Gold(rate .. " " .. L.Format("(up %d%%)", math.floor(summary.ahead * 100 + 0.5)))
            end
            parts[#parts + 1] = rate
        end
        labels.bottomRight:SetText(table.concat(parts, "  |  "))
    end

    -- The bar itself.
    local share = summary.share
    local ready = math.min(1, share + summary.readyXP / summary.max)
    local rested = math.min(1, ready + summary.rested / summary.max)
    local half = math.floor(self.BAR / 2)

    self:Span(self.fill, 0, share)
    self:Span(self.sheen, 0, share, 1, half)
    self:Span(self.shade, 0, share, half, 1)
    self:Span(self.session, summary.sessionFrom, share)
    self:Span(self.quest, share, ready)
    self:Span(self.rested, ready, rested)

    if summary.rested > 0 and rested < 1 then self:Mark(self.restedCap, rested) else self.restedCap:Hide() end
    if summary.sessionFrom > 0 and summary.sessionFrom < share then
        self:Mark(self.sessionMark, summary.sessionFrom)
    else
        self.sessionMark:Hide()
    end
    for index, tick in ipairs(self.ticks) do
        self:Mark(tick, index / 10)
        self:Mark(self.flashes[index], index / 10)
    end

    local inner = self.WIDTH - 2
    self.spark:ClearAllPoints()
    self.spark:SetPoint("CENTER", self.bar, "LEFT", 1 + share * inner, 0)
    self.spark:SetShown(share > 0)
    self.sparkGlow:SetShown(share > 0)
    self:FitSweep(share * inner)

    self.inReach = summary.inReach
    if not summary.inReach then Theme.SetHalo(self.bar, 0.18, "accent") end

    if self.card and self.card:IsShown() then self:FillCard() end
end

--- Every frame while shown: the green glow while the level is in reach,
--- the grip coming and going, and the played time now and then.
function XPBarUI:Tick(elapsed)
    elapsed = tonumber(elapsed) or 0
    self.clock = (self.clock or 0) + elapsed
    if Level() ~= self.motionLevel then self:ApplyMotion() end
    if self.clock >= self.CLOCK then
        self.clock = 0
        self:Refresh()
    end

    if self.inReach then
        self.pulse = (self.pulse or 0) + elapsed
        local glow = Level() == "full" and 0.3 + 0.2 * math.sin(self.pulse * 3) or 0.35
        Theme.SetHalo(self.bar, glow, "good")
    end

    if self.grip and self.grip:GetAlpha() > 0 then
        local ok, over = pcall(function() return self.frame:IsMouseOver() or self.grip:IsMouseOver() end)
        if ok and not over then self.grip:SetAlpha(0) end
    end
end

--------------------------------------------------------------------------------
-- The star's breath and the light along the gold
--------------------------------------------------------------------------------

-- Both are animations the game plays, so nothing here runs a frame at a
-- time; they are only set again when Window effects or the gold's width
-- moves.

local function Group(region, looping)
    local ok, group = pcall(region.CreateAnimationGroup, region)
    if not ok or type(group) ~= "table" then return nil end
    pcall(group.SetLooping, group, looping)
    return group
end

local function Anim(group, kind)
    local ok, anim = pcall(group.CreateAnimation, group, kind)
    if ok and type(anim) == "table" then return anim end
    return nil
end

function XPBarUI:MakeMotion()
    local breath = Group(self.spark, "BOUNCE")
    if breath then
        self.breath = breath
        self.breathScale = Anim(breath, "Scale")
        self.breathDim = Anim(breath, "Alpha")
    end
    local glow = Group(self.sparkGlow, "BOUNCE")
    if glow then
        self.glowBreath = glow
        self.glowDim = Anim(glow, "Alpha")
    end
    local sweep = Group(self.sweep, "REPEAT")
    if sweep then
        self.sweepGroup = sweep
        self.sweepMove = Anim(sweep, "Translation")
        self.sweepLight = Anim(sweep, "Alpha")
    end
    self.sweepWidth = 0
end

local function Stop(group)
    if group then pcall(group.Stop, group) end
end

local function Play(group)
    if group then pcall(group.Play, group) end
end

--- Sets the breath and the sweep for Window effects: Full, Subtle or none.
function XPBarUI:ApplyMotion()
    local level = Level()
    self.motionLevel = level
    local spec = self.MOTION[level]
    Stop(self.breath)
    Stop(self.glowBreath)
    Stop(self.sweepGroup)
    if self.sweep then self.sweep:SetAlpha(0) end
    if not spec then return end

    pcall(function()
        local scale = self.breathScale
        if scale then
            if scale.SetScaleFrom then
                scale:SetScaleFrom(1, 1)
                scale:SetScaleTo(spec.grow, spec.grow)
            else
                scale:SetScale(spec.grow, spec.grow)
            end
            scale:SetDuration(spec.breath)
            scale:SetSmoothing("IN_OUT")
        end
        local dim = self.breathDim
        if dim then
            dim:SetFromAlpha(1)
            dim:SetToAlpha(spec.dim)
            dim:SetDuration(spec.breath)
            dim:SetSmoothing("IN_OUT")
        end
        local glow = self.glowDim
        if glow then
            glow:SetFromAlpha(1)
            glow:SetToAlpha(0.35)
            glow:SetDuration(spec.breath)
            glow:SetSmoothing("IN_OUT")
        end
    end)
    Play(self.breath)
    Play(self.glowBreath)
    self:FitSweep(self.sweepWidth or 0, true)
end

--- The light runs the gold's width at an even pace, then rests.
function XPBarUI:FitSweep(width, force)
    width = math.floor(tonumber(width) or 0)
    if not self.sweepClip then return end
    if not force and math.abs(width - (self.sweepWidth or 0)) < 2 then return end
    self.sweepWidth = width
    self.sweepClip:SetWidth(math.max(1, width))

    local spec = self.MOTION[self.motionLevel or Level()]
    if not (spec and self.sweepGroup and self.sweepMove) or width < self.SWEEP then
        Stop(self.sweepGroup)
        return
    end
    local travel = width + self.SWEEP
    local seconds = travel / spec.speed
    pcall(function()
        local move = self.sweepMove
        move:SetOffset(travel, 0)
        move:SetDuration(seconds)
        move:SetOrder(1)
        local light = self.sweepLight
        if light then
            light:SetFromAlpha(spec.light)
            light:SetToAlpha(spec.light)
            light:SetDuration(seconds)
            light:SetOrder(1)
        end
        -- The rest: the light waits out of sight before the next run.
        move:SetEndDelay(spec.rest)
    end)
    Stop(self.sweepGroup)
    Play(self.sweepGroup)
end

--------------------------------------------------------------------------------
-- Small rewards
--------------------------------------------------------------------------------

--- A number floats up off the bar's tip and fades.
function XPBarUI:Float(text, key, size)
    if Level() ~= "full" or not (self.frame and self.frame:IsShown()) then return end
    local label = self.floats[self.nextFloat]
    self.nextFloat = self.nextFloat % #self.floats + 1

    pcall(label.SetFont, label, Theme.FONT, Theme.sizes[size or "large"], "OUTLINE")
    label:SetText(text)
    label:SetTextColor(Theme.Unpack(key or "accentHi"))
    local share = self.summary and self.summary.share or 0
    local x = 1 + share * (self.WIDTH - 2)

    ns.Motion:Run(label, "float", self.FLOAT, function(p)
        label:ClearAllPoints()
        label:SetPoint("BOTTOM", self.bar, "TOPLEFT", x, 2 + 28 * p)
        label:SetAlpha(p < 0.15 and p / 0.15 or 1 - (p - 0.15) / 0.85)
    end, { ease = false })
end

--- A light runs along the gold, for a quest handed in.
function XPBarUI:Wave()
    if Level() ~= "full" or not self.wave then return end
    local wave = self.wave
    local share = self.summary and self.summary.share or 1
    local inner = self.WIDTH - 2
    wave:SetVertexColor(Theme.Unpack("good"))
    ns.Motion:Run(wave, "wave", 0.9, function(p)
        wave:ClearAllPoints()
        wave:SetPoint("CENTER", self.bar, "LEFT", 1 + p * share * inner, 0)
        wave:SetAlpha(math.sin(p * math.pi) * 0.9)
    end, { ease = false })
end

--- A tenth of the level crossed: its tick lights up, with a soft chime.
function XPBarUI:TickCrossed(index)
    local flash = self.flashes and self.flashes[index]
    if flash and Level() ~= "off" then
        ns.Motion:Run(flash, "flash", 0.9, function(p) flash:SetAlpha(1 - p) end)
    end
    if XPBarUI.ChimeOn() and ns.Tracker then ns.Tracker.PlayFile(self.CHIME) end
end

--- XP moved (Logic/XP.lua calls this).
function XPBarUI:Changed(kind, amount, extra)
    if kind == "level" then
        self:Refresh()
        if XPBarUI.CheerOn() then self:Cheer(extra) end
        return
    end
    self:Refresh()
    if not (self.frame and self.frame:IsShown()) then return end

    if kind == "kill" then
        self:Float("+" .. Comma(amount), "accentHi", "large")
    elseif kind == "quest" then
        self:Float(L.Format("+%s XP", Comma(amount)), "good", "title")
        self:Wave()
    elseif kind == "tick" then
        self:TickCrossed(amount)
    end
end

--------------------------------------------------------------------------------
-- The card: how to finish the level
--------------------------------------------------------------------------------

local CARD_PAD = 12

function XPBarUI:BuildCard()
    if self.card then return self.card end
    local card = CreateFrame("Frame", "BlackthornesFarmerXPCard", UIParent)
    card:SetWidth(self.CARD)
    card:SetFrameStrata("TOOLTIP")
    card:SetClampedToScreen(true)
    Theme.Fill(card, "glassAlt", 0.97)
    Theme.Border(card, "metal")
    Theme.Halo(card, 8, 0.16)

    local header = Theme.CreatePanel(card, "header", false)
    header:SetPoint("TOPLEFT", 1, -1)
    header:SetPoint("TOPRIGHT", -1, -1)
    header:SetHeight(28)
    if Theme.HouseHeader then Theme.HouseHeader(header) end
    local title = Theme.CreateLabel(header, "normal", "accent")
    title:SetPoint("LEFT", header, "LEFT", CARD_PAD + 2, 0)
    card.title = title

    local foot = Theme.CreateLabel(card, "tiny", "dim")
    foot:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", CARD_PAD, 6)
    foot:SetText(L["Drag the bar to move it. Right-click for its settings."])
    card.foot = foot

    card.rows = {}
    card:Hide()
    self.card = card
    return card
end

function XPBarUI:CardRow(index)
    local card = self.card
    local row = card.rows[index]
    if row then return row end
    row = CreateFrame("Frame", nil, card)
    row.stripe = Texture(row, "BACKGROUND", 0, Theme.Unpack(index % 2 == 1 and "glass" or "glassAlt"))
    row.stripe:SetAllPoints(row)
    row.line = Texture(row, "BORDER", 0, Theme.Unpack("border", 0.6))
    row.line:SetPoint("BOTTOMLEFT")
    row.line:SetPoint("BOTTOMRIGHT")
    row.line:SetHeight(1)
    row.edge = Texture(row, "ARTWORK", 0, Theme.Unpack("accentHi"))
    row.edge:SetPoint("TOPLEFT")
    row.edge:SetPoint("BOTTOMLEFT")
    row.edge:SetWidth(2)

    row.title = Theme.CreateLabel(row, "normal", "text")
    row.title:SetPoint("TOPLEFT", row, "TOPLEFT", CARD_PAD, -6)
    row.right = Theme.CreateLabel(row, "normal", "text", "RIGHT")
    row.right:SetPoint("TOPRIGHT", row, "TOPRIGHT", -CARD_PAD, -6)
    row.sub = Theme.CreateLabel(row, "small", "muted")
    row.sub:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -2)
    row.sub:SetWordWrap(true)
    card.rows[index] = row
    return row
end

--- The lines of the card for `s`, XP:Summary's: { title, sub, right, key, picked }.
function XPBarUI.CardLines(s)
    local lines = {}
    local function Add(line) lines[#lines + 1] = line end

    if #s.ready > 0 then
        local names = {}
        for index, quest in ipairs(s.ready) do
            if index > 3 then
                names[#names + 1] = L.Format("and %d more", #s.ready - 3)
                break
            end
            names[#names + 1] = quest.title
        end
        local right
        if s.inReach then
            right = L.Format("+%s, enough to level", Comma(s.readyXP))
        else
            right = L.Format("+%s, %d%% of what is left", Comma(s.readyXP),
                math.floor(s.readyXP / math.max(1, s.left) * 100 + 0.5))
        end
        Add({ title = L.Format("Hand in %s", Count(#s.ready,
                L["1 finished quest"], L.Format("%d finished quests", #s.ready))),
            sub = table.concat(names, ", "), right = right, key = "good", picked = true })
    end

    if s.mob and not s.inReach then
        local count = s.mob.after or s.mob.kills
        local title = s.mob.after
            and L.Format("Then kill about %d more %s", count, s.mob.name)
            or L.Format("Kill about %d more %s", count, s.mob.name)
        Add({ title = title,
            sub = L.Format("%s XP each from your kills this session, double while rested lasts", Comma(s.mob.each)),
            right = s.mob.seconds and L.Format("about %s", ns.XP.Duration(s.mob.seconds)) or nil,
            picked = #s.ready == 0 })
    end

    if #s.near > 0 then
        local started = math.max(s.started or 0, #s.near)
        local subs = {}
        for _, quest in ipairs(s.near) do
            subs[#subs + 1] = quest.lines[1] or quest.title
        end
        if started > #s.near then
            subs[#subs + 1] = L.Format("and %d more", started - #s.near)
        end
        Add({ title = Count(started, L["1 quest in your log is partly done"],
                L.Format("%d quests in your log are partly done", started)),
            sub = table.concat(subs, ", "), right = "+" .. Comma(s.startedXP or 0), key = "good" })
    end

    if s.rested > 0 then
        Add({ title = L.Format("Rested: %s XP", Comma(s.rested)),
            sub = L["Kills give double XP until it runs out."] })
    end

    local session = s.session
    Add({ title = L["This session"],
        sub = L.Format("%s, %s (%s XP), %s (%s XP)", ns.XP.Duration(ns.XP:Seconds()),
            Count(session.kills, L["1 kill"], L.Format("%d kills", session.kills)), Comma(session.killXP),
            Count(session.quests, L["1 quest"], L.Format("%d quests", session.quests)), Comma(session.questXP)),
        right = "+" .. Comma(session.gained) })

    if s.level < s.cap then
        local levels = s.cap - s.level
        Add({ title = L.Format("Level %d", s.cap),
            sub = s.toCap and L.Format("about %s of play at your usual pace", ns.XP.Duration(s.toCap))
                or L["Your usual pace shows after an hour or so of play."],
            right = Count(levels, L["1 level to go"], L.Format("%d levels to go", levels)), key = "accent" })
    end
    return lines
end

function XPBarUI:FillCard()
    local s = self.summary
    if not s then return end
    local card = self:BuildCard()
    card.title:SetText(L.Format("%s XP TO LEVEL %d", Comma(s.left), s.level + 1))

    local lines = XPBarUI.CardLines(s)
    local width = self.CARD
    local y = 30
    for index, line in ipairs(lines) do
        local row = self:CardRow(index)
        row.title:SetText(line.title)
        row.right:SetText(line.right or "")
        row.right:SetTextColor(Theme.Unpack(line.key or "text"))
        local rightWidth = line.right and Theme.TextWidth("normal", line.right) + 10 or 0
        local subWidth = width - CARD_PAD * 2 - 4
        row.sub:SetWidth(subWidth)
        row.sub:SetText(line.sub or "")
        local subLines = (line.sub and line.sub ~= "")
            and math.max(1, math.ceil(Theme.TextWidth("small", line.sub) / subWidth)) or 0
        -- The title wraps under the right column's words rather than run into them.
        row.title:SetWidth(width - CARD_PAD * 2 - rightWidth)
        row.title:SetWordWrap(true)
        local titleLines = math.max(1, math.ceil(Theme.TextWidth("normal", line.title)
            / math.max(40, width - CARD_PAD * 2 - rightWidth)))
        local height = 10 + titleLines * 15 + subLines * 13
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", card, "TOPLEFT", 1, -y)
        row:SetPoint("TOPRIGHT", card, "TOPRIGHT", -1, -y)
        row:SetHeight(height)
        row.stripe:SetColorTexture(Theme.Unpack(line.picked and "glassActive"
            or (index % 2 == 1 and "glass" or "glassAlt")))
        row.edge:SetShown(line.picked and true or false)
        row:Show()
        y = y + height
    end
    for index = #lines + 1, #card.rows do card.rows[index]:Hide() end
    card:SetHeight(y + 22)
end

function XPBarUI:ShowCard()
    if self.grip then self.grip:SetAlpha(1) end
    if not self.summary then return end
    local card = self:BuildCard()
    self:FillCard()
    card:ClearAllPoints()
    local ok, _, cy = pcall(self.frame.GetCenter, self.frame)
    local ok2, height = pcall(UIParent.GetHeight, UIParent)
    if ok and ok2 and type(cy) == "number" and type(height) == "number" and cy < height / 2 then
        card:SetPoint("BOTTOM", self.frame, "TOP", 0, 8)
    else
        card:SetPoint("TOP", self.frame, "BOTTOM", 0, -8)
    end
    card:Show()
end

function XPBarUI:HideCard()
    if self.card then self.card:Hide() end
end

--------------------------------------------------------------------------------
-- The level-up cheer
--------------------------------------------------------------------------------

local RAYS = 8
local COINS = 10

--- The cheer's words sit over the open world with nothing behind them, so
--- they are outlined and shadowed, as the bar's own lines are.
function XPBarUI.CheerLabel(parent, justify, colorKey)
    local label = Theme.CreateLabel(parent, "normal", colorKey or "text", justify)
    pcall(label.SetFont, label, Theme.FONT, Theme.sizes.normal, "OUTLINE")
    pcall(label.SetShadowColor, label, 0, 0, 0, 1)
    pcall(label.SetShadowOffset, label, 1, -1)
    return label
end

function XPBarUI:BuildCheer()
    if self.cheer then return self.cheer end
    local cheer = CreateFrame("Frame", "BlackthornesFarmerLevelUp", UIParent)
    cheer:SetSize(360, 150)
    cheer:SetFrameStrata("FULLSCREEN_DIALOG")
    cheer:SetClampedToScreen(true)
    cheer:EnableMouse(true)
    -- No panel behind it: the light and the words float over the world.

    cheer.rays = {}
    for index = 1, RAYS do
        local ray = cheer:CreateTexture(nil, "BORDER")
        ray:SetTexture(GLOW)
        pcall(ray.SetBlendMode, ray, "ADD")
        ray:SetVertexColor(1, 0.75, 0.3)
        ray:SetSize(420, 40)
        ray:SetPoint("CENTER", cheer, "TOP", 0, -48)
        ray.angle = (index - 1) / RAYS * math.pi
        cheer.rays[index] = ray
    end

    local glow = cheer:CreateTexture(nil, "BORDER", nil, 1)
    glow:SetTexture(GLOW)
    pcall(glow.SetBlendMode, glow, "ADD")
    glow:SetVertexColor(1, 0.8, 0.35)
    glow:SetSize(300, 120)
    glow:SetPoint("CENTER", cheer, "TOP", 0, -48)
    cheer.glow = glow

    local big = cheer:CreateFontString(nil, "OVERLAY")
    pcall(big.SetFont, big, Theme.FONT, 34, "THICKOUTLINE")
    big:SetTextColor(1, 0.86, 0.5, 1)
    big:SetPoint("CENTER", cheer, "TOP", 0, -46)
    cheer.big = big

    local sub = XPBarUI.CheerLabel(cheer, "CENTER")
    sub:SetPoint("TOP", cheer, "TOP", 0, -76)
    sub:SetWidth(340)
    sub:SetWordWrap(true)
    cheer.sub = sub

    cheer.rows = {}
    for index = 1, 4 do
        local row = CreateFrame("Frame", nil, cheer)
        row:SetHeight(24)
        row.left = XPBarUI.CheerLabel(row)
        row.left:SetPoint("LEFT", row, "LEFT", 10, 0)
        row.right = XPBarUI.CheerLabel(row, "RIGHT", "good")
        row.right:SetPoint("RIGHT", row, "RIGHT", -10, 0)
        row:Hide()
        cheer.rows[index] = row
    end

    cheer.coins = {}
    for index = 1, COINS do
        local coin = cheer:CreateTexture(nil, "OVERLAY")
        coin:SetTexture(COIN)
        coin:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        coin:Hide()
        cheer.coins[index] = coin
    end

    cheer:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" then XPBarUI:HideCheer() end
    end)
    cheer:SetScript("OnUpdate", function(_, elapsed) XPBarUI:StepCheer(elapsed) end)
    cheer:Hide()
    self.cheer = cheer
    return cheer
end

--- The rows under the title for a level-up `info` (XP:LevelUp's).
function XPBarUI.CheerLines(info)
    local lines = {}
    if info.cap then
        if info.total then lines[#lines + 1] = { L["Played to get here"], ns.XP.Duration(info.total) } end
        if info.fastest then
            lines[#lines + 1] = { L.Format("Your fastest level was %d", info.fastestLevel), ns.XP.Duration(info.fastest) }
        end
    end
    if info.talents and info.talents > 0 then
        lines[#lines + 1] = { Count(info.talents, L["1 new talent point"],
            L.Format("%d new talent points", info.talents)), "" }
    end
    if info.training then
        local training = info.training
        local right = tostring(training.count)
        if training.cost > 0 then
            right = L.Format("%d for %s", training.count, ns.Value.Coins(training.cost))
        end
        lines[#lines + 1] = { L["New spells at your trainer"], right }
    end
    if info.upgrade then
        lines[#lines + 1] = { L["Gear in your bags you can wear now"], info.upgrade }
    end
    return lines
end

--- The words under the title.
function XPBarUI.CheerSub(info)
    if info.cap then return L["The top level. Well played."] end
    local parts = {}
    if info.took then
        parts[#parts + 1] = L.Format("Level %d took %s", info.level - 1, ns.XP.Duration(info.took))
    end
    if info.since and info.since.fastest then
        parts[#parts + 1] = L["your fastest level yet"]
    elseif info.since and info.since.since then
        parts[#parts + 1] = L.Format("your fastest since level %d", info.since.since)
    end
    return table.concat(parts, "  |  ")
end

function XPBarUI:Cheer(info)
    if type(info) ~= "table" or not info.level then return end
    local cheer = self:BuildCheer()
    self.cheerInfo = info

    cheer.big:SetText(L.Format("LEVEL %d", info.level))
    pcall(cheer.big.SetFont, cheer.big, Theme.FONT, info.milestone and 42 or 34, "THICKOUTLINE")
    cheer.sub:SetText(XPBarUI.CheerSub(info))
    self:LayCheerRows(info)

    cheer:ClearAllPoints()
    -- the game's own level-up banner sits near the top of the screen, so ours
    -- goes a good way below it, whatever the bar does
    local ok, height = pcall(UIParent.GetHeight, UIParent)
    if not ok or type(height) ~= "number" or height <= 0 then height = 1080 end
    cheer:SetPoint("TOP", UIParent, "TOP", 0, -math.floor(height * 0.3))
    cheer:SetAlpha(1)
    cheer:Show()
    if ns.Motion then ns.Motion:Open(cheer, 12) end

    self.cheerTime, self.cheerHold, self.cheerFading = 0, self.HOLD, false
    local full = Level() == "full"
    for _, ray in ipairs(cheer.rays) do ray:SetShown(full) end
    cheer.glow:SetShown(Level() ~= "off")
    if info.milestone and full then self:Rain() end
    if info.milestone and ns.Tracker then ns.Tracker.PlayFile(ns.Tracker.SOUNDS.unlock) end

    if not info.cap then self:FindUpgrade() end
    if C_Timer and C_Timer.After then
        local shown = info
        C_Timer.After(self.TRAIN_DELAY, function() XPBarUI:AddTraining(shown) end)
    end
end

--- Class spells to train come from Blackthornes Butler or Equipment, when
--- either is loaded and has class training (their Logic/ClassTraining.lua,
--- the same file in both): read only, inside a pcall. Farmer has no spell
--- list of its own, so without them the cheer says nothing about training.
XPBarUI.TRAIN_DELAY = 2
XPBarUI.TRAINING_FROM = { "BlackthornesButler", "BlackthornesEquipment" }

--- { count, cost } of the spells the character can train now, or nil.
function XPBarUI.Training()
    for _, name in ipairs(XPBarUI.TRAINING_FROM) do
        local addon = rawget(_G, name)
        local training = type(addon) == "table" and rawget(addon, "ClassTraining")
        if type(training) == "table" and type(training.Plan) == "function" then
            local ok, on = true, true
            if type(training.IsOn) == "function" then ok, on = pcall(training.IsOn, training) end
            if ok and on ~= false then
                local got, plan = pcall(training.Plan, training)
                if got and type(plan) == "table" and type(plan.ready) == "table" then
                    local count = #plan.ready
                    if count == 0 then return nil end
                    local cost = ns.XP.Number(plan.cost) or 0
                    local unknown = ns.XP.Number(plan.unknown) or 0
                    -- A cost with spells left unpriced would read as the whole.
                    if unknown > 0 then cost = 0 end
                    return { count = count, cost = cost }
                end
            end
        end
    end
    return nil
end

--- A moment after the level (the sisters wait for the client to list the
--- new spells), the training row joins the cheer still showing it.
function XPBarUI:AddTraining(info)
    if self.cheerInfo ~= info or not (self.cheer and self.cheer:IsShown()) then return end
    local training = XPBarUI.Training()
    if not training then return end
    info.training = training
    self:LayCheerRows(info)
end

function XPBarUI:LayCheerRows(info)
    local cheer = self.cheer
    local lines = XPBarUI.CheerLines(info)
    local y = 104
    for index, row in ipairs(cheer.rows) do
        local line = lines[index]
        if line then
            row.left:SetText(line[1])
            row.right:SetText(line[2] or "")
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", cheer, "TOPLEFT", 12, -y)
            row:SetPoint("TOPRIGHT", cheer, "TOPRIGHT", -12, -y)
            row:Show()
            y = y + 24
        else
            row:Hide()
        end
    end
    cheer:SetHeight(y + 12)
end

--- Coins tumble down the cheer, for every tenth level and the cap.
function XPBarUI:Rain()
    local cheer = self.cheer
    local okW, width = pcall(cheer.GetWidth, cheer)
    local okH, height = pcall(cheer.GetHeight, cheer)
    width = okW and tonumber(width) or 360
    height = okH and tonumber(height) or 150
    for index, coin in ipairs(cheer.coins) do
        coin.x = (index - 0.5) / COINS * width + math.random(-10, 10)
        coin.delay = math.random() * 0.8
        coin.size = 14 + math.random(0, 6)
        coin.spin = 6 + math.random() * 5
        coin:SetSize(coin.size, coin.size)
    end
    ns.Motion:Run(cheer, "coins", 2.2, function(p)
        local now = p * 2.2
        for _, coin in ipairs(cheer.coins) do
            local t = (now - coin.delay) / 1.4
            if t < 0 or t >= 1 then
                coin:Hide()
            else
                coin:ClearAllPoints()
                coin:SetPoint("CENTER", cheer, "TOPLEFT", coin.x, -(height + coin.size) * t * t)
                coin:SetWidth(math.max(2, coin.size * math.abs(math.cos(t * coin.spin))))
                coin:SetAlpha(t > 0.7 and (1 - t) / 0.3 or 1)
                coin:Show()
            end
        end
    end, { ease = false })
end

--- The rays turn, the hold runs down while the mouse is away, then it fades.
function XPBarUI:StepCheer(elapsed)
    local cheer = self.cheer
    if not cheer then return end
    elapsed = tonumber(elapsed) or 0
    self.cheerTime = (self.cheerTime or 0) + elapsed

    if Level() == "full" then
        for _, ray in ipairs(cheer.rays) do
            pcall(ray.SetRotation, ray, ray.angle + self.cheerTime * 0.25)
            ray:SetAlpha(0.18 + 0.08 * math.sin(self.cheerTime * 2 + ray.angle * 3))
        end
        cheer.glow:SetAlpha(0.5 + 0.2 * math.sin(self.cheerTime * 3))
    end

    if self.cheerFading or not self.cheerHold then return end
    local ok, over = pcall(function() return cheer:IsMouseOver() end)
    if not (ok and over) then self.cheerHold = self.cheerHold - elapsed end
    if self.cheerHold <= 0 then self:FadeCheer() end
end

function XPBarUI:FadeCheer()
    local cheer = self.cheer
    if not cheer or self.cheerFading then return end
    self.cheerFading = true
    ns.Motion:Run(cheer, "fade", self.FADE, function(p) cheer:SetAlpha(1 - p) end, {
        done = function() XPBarUI:HideCheer() end })
end

function XPBarUI:HideCheer()
    local cheer = self.cheer
    if not cheer then return end
    if ns.Motion then ns.Motion:Stop(cheer) end
    cheer:Hide()
    cheer:SetAlpha(1)
    for _, coin in ipairs(cheer.coins) do coin:Hide() end
    self.cheerHold, self.cheerFading = nil, false
    self.upgradeScan = nil
end

--- With Blackthornes Equipment loaded, the first gear in the bags it calls
--- an upgrade to wear now, read a few slots a frame.
XPBarUI.SCAN = 12

function XPBarUI:FindUpgrade()
    local equipment = _G.BlackthornesEquipment
    local compare = type(equipment) == "table" and rawget(equipment, "Compare")
    local container = _G.C_Container
    if not (type(compare) == "table" and type(compare.IsUpgrade) == "function"
        and type(container) == "table" and type(container.GetContainerNumSlots) == "function") then
        return
    end
    self.upgradeScan = { bag = 0, slot = 1, compare = compare }
    if not self.scanner then
        self.scanner = CreateFrame("Frame")
        self.scanner:SetScript("OnUpdate", function() XPBarUI:ScanStep(XPBarUI.SCAN) end)
    end
    self.scanner:Show()
end

function XPBarUI:ScanStep(budget)
    local scan = self.upgradeScan
    local container = _G.C_Container
    if not scan then
        if self.scanner then self.scanner:Hide() end
        return
    end
    while budget > 0 and scan.bag <= 4 do
        local ok, slots = pcall(container.GetContainerNumSlots, scan.bag)
        slots = ok and ns.XP.Number(slots) or 0
        if scan.slot > slots then
            scan.bag, scan.slot = scan.bag + 1, 1
        else
            budget = budget - 1
            local got, link = pcall(container.GetContainerItemLink, scan.bag, scan.slot)
            scan.slot = scan.slot + 1
            if got and type(link) == "string" then
                local asked, upgrade = pcall(scan.compare.IsUpgrade, scan.compare, link)
                if asked and upgrade == true then
                    self.upgradeScan = nil
                    if self.cheerInfo and self.cheer and self.cheer:IsShown() then
                        self.cheerInfo.upgrade = link
                        self:LayCheerRows(self.cheerInfo)
                    end
                    return
                end
            end
        end
    end
    if scan.bag > 4 then self.upgradeScan = nil end
end

--- The cheer as a level up would show it, with nothing changed (`/farm
--- xpbar try`, Settings).
function XPBarUI:TryCheer()
    local state = ns.XP.Read()
    local level = (state and state.level or 10) + 1
    local _, took = ns.XP:Played()
    self:Cheer({ level = level, took = took, milestone = level % 10 == 0 })
end

--------------------------------------------------------------------------------
-- The game's XP bar
--------------------------------------------------------------------------------

function XPBarUI:GameBar()
    for _, name in ipairs(self.GAME_BARS) do
        local frame = _G[name]
        if type(frame) == "table" then return frame end
    end
    return nil
end

--- Make the game's XP bar see-through while ours shows and the setting is
--- ticked; else put it back.
function XPBarUI:ApplyGameBar()
    local game = self:GameBar()
    if not (game and ns.Veil) then return end
    local done
    if XPBarUI.HidesGame() and self:Wanted() then
        done = ns.Veil:Cover(game)
    else
        done = ns.Veil:Uncover(game)
    end
    self.gameWaiting = not done
end

--------------------------------------------------------------------------------
-- Turning things on and off
--------------------------------------------------------------------------------

function XPBarUI:SetOn(on)
    ns.db.xpBar = on and true or false
    self:Refresh()
    self:ApplyGameBar()
end

function XPBarUI:SetHideGame(on)
    ns.db.xpBarHideGame = on and true or false
    self:ApplyGameBar()
end

local function Word(on)
    return on and L["on"] or L["off"]
end

ns.RegisterCommand("xpbar", L["the XP bar (on/off, cheer on/off, chime on/off, game show/hide, reset, try)"], function(rest)
    local word, value = (rest or ""):lower():match("^(%S*)%s*(%S*)")
    local function Flip(current)
        if value == "on" or value == "show" then return true end
        if value == "off" or value == "hide" then return false end
        return not current
    end

    if word == "cheer" then
        ns.db.xpBarCheer = Flip(XPBarUI.CheerOn())
        ns.Print(L.Format("level-up cheer %s.", Word(XPBarUI.CheerOn())))
    elseif word == "chime" then
        ns.db.xpBarChime = Flip(XPBarUI.ChimeOn())
        ns.Print(L.Format("chime every tenth of a level %s.", Word(XPBarUI.ChimeOn())))
    elseif word == "game" then
        local hide
        if value == "show" then hide = false elseif value == "hide" then hide = true else hide = not XPBarUI.HidesGame() end
        XPBarUI:SetHideGame(hide)
        ns.Print(hide and L["the game's XP bar is see-through while yours shows."]
            or L["the game's XP bar is back."])
    elseif word == "reset" then
        XPBarUI:ResetPlace()
        ns.Print(L["the XP bar is back in its place, at its normal size."])
    elseif word == "try" then
        XPBarUI:TryCheer()
    else
        local on
        if word == "on" then on = true elseif word == "off" then on = false else on = not XPBarUI.On() end
        XPBarUI:SetOn(on)
        ns.Print(L.Format("XP bar %s.", Word(on)))
    end
end)

function XPBarUI:OnEnable()
    ns.RegisterEvent(self, "PLAYER_ENTERING_WORLD", function()
        XPBarUI:Refresh()
        XPBarUI:ApplyGameBar()
    end)
    ns.RegisterEvent(self, "PLAYER_REGEN_ENABLED", function()
        if XPBarUI.gameWaiting then XPBarUI:ApplyGameBar() end
    end)
end
