-- Blackthornes Farmer -- UI/DamageNumbers.lua
-- Big damage numbers that pop off a mob each time it's hit, in place of
-- the game's own.
--
--   a hit       a number that bounces up and fades, coloured by its kind
--               of damage, with a few of that kind's motes
--   a crit      bigger, a ring and a burst of that kind's motes, a shake
--   a combo     COMBO x5 over the mob, warming gold to orange to violet as
--               the hits keep coming, a ring every fifth
--   the kill    bigger still and hot orange, two rings, sparks, coins, a moment of slow
--               motion, and the kill count ("8/20") and what a kill is worth
--
-- The owner asked (2026-10-19, from a mockup) for the game's numbers with
-- "massive levels of dopamine", and picked where they show: on the mob
-- when it has a nameplate, else (for the target) at one spot just above
-- the character, with no setting for it (the owner, the same day). Never
-- announced. No words over the numbers but COMBO: "Let the numbers do
-- the talking" (the owner, the same day).
--
-- Kinds of damage (the owner said build it, 2026-10-19, from a mockup:
-- "cool dopamine for each class"): UNIT_COMBAT's school picks the colour
-- and the motes. Physical is steel with sparks, Holy gold with rays, Fire
-- orange with embers, Nature green with leaves, Frost blue with shards,
-- Shadow violet with smoke (its ring pulls in), Arcane pink with stars. A
-- mixed school takes the first magic one in SCHOOL_ORDER; one the client
-- won't say is Physical. The kill stays gold for everyone.
--
-- How a hit is heard: Forever keeps the combat log from addons, so it is
-- UNIT_COMBAT, which names the unit hit, "WOUND", the amount and
-- "CRITICAL". Only nameplate units and the target are read, and the
-- target only when it has no nameplate, so a hit never shows twice. It
-- does not say who hit, so a mob tapped by someone else is left out
-- (UnitIsTapDenied). A kill is a hit after which the unit reads dead,
-- looked at for KILL_LOOK seconds and when its nameplate goes.
--
-- The game's own numbers: while this is ticked, the game setting that
-- shows them (`floatingCombatTextCombatDamage`, or its `_v2` where the
-- client has it) is set to 0, the player's value kept in
-- `damageNumbersCVars` and put back when it is unticked (also at login,
-- if a value was left there). Never in a fight: it waits for the fight to
-- end. Saved, account wide, never renamed: `damageNumbers` (off unless
-- ticked), `damageNumbersSize` ("some", "more", "most"; "most" to start),
-- `damageNumbersCombo` (on unless unticked) and `damageNumbersCVars`.
--
-- Smooth play: every number, spark, ring and coin is Farmer's own frame or
-- texture on UIParent, made once and used again from a pool with a cap
-- (MOST_*). One OnUpdate drives them all and runs only while something is
-- showing. Nothing is written on a game frame, and every client value is
-- read in a pcall (a secret amount is shown as it is, never compared).
-- Window effects (Motion.Level) Subtle keeps the pop and rings, Off only
-- the numbers.

local _, ns = ...
local L = ns.L

local DamageNumbers = ns.NewModule("DamageNumbers")

local MEDIA = [[Interface\AddOns\Blackthornes_Farmer\Media\Frame\]]
local RING = MEDIA .. "HitRing.tga"
local SPARK = MEDIA .. "HitSpark.tga"
local COIN = MEDIA .. "HitCoin.tga"
local MOTE_ART = {
    steel = SPARK, rays = SPARK,
    embers = MEDIA .. "HitEmber.tga", shards = MEDIA .. "HitShard.tga",
    leaves = MEDIA .. "HitLeaf.tga", smoke = MEDIA .. "HitSmoke.tga",
    stars = MEDIA .. "HitStar.tga",
}
local GLOW = MEDIA .. "Glow.tga"

DamageNumbers.SIZES = { "some", "more", "most" }
DamageNumbers.SCALE = { some = 0.55, more = 0.8, most = 1 }
DamageNumbers.CVARS = { "floatingCombatTextCombatDamage_v2", "floatingCombatTextCombatDamage" }

DamageNumbers.MOST_NUMBERS = 16
DamageNumbers.MOST_SPARKS = 48
DamageNumbers.MOST_RINGS = 6
DamageNumbers.MOST_COINS = 14
DamageNumbers.MOST_MOTES = 40
DamageNumbers.COMBO_WINDOW = 2.4    -- seconds between hits that keep a combo going
DamageNumbers.KILL_LOOK = 0.5       -- seconds after a hit to see whether it killed
DamageNumbers.SLOW = 0.25           -- how slow the moment after a kill runs
DamageNumbers.SLOW_FOR = 0.45       -- for this long, in real seconds
DamageNumbers.SPOT_X, DamageNumbers.SPOT_Y = 0, 140

-- How each kind of number looks, at Most.
local STYLES = {
    hit  = { size = 26, life = 0.95, pop = 1.45, rise = 64, color = { 1, 0.95, 0.82 } },
    crit = { size = 40, life = 1.35, pop = 2.3,  rise = 84, color = { 1, 0.84, 0.3 }, glow = { 1, 0.75, 0.2 } },
    kill = { size = 50, life = 1.9,  pop = 2.6,  rise = 70, color = { 1, 0.56, 0.2 }, glow = { 1, 0.45, 0.12 } },
}
DamageNumbers.STYLES = STYLES

-- The combo's colour as it heats: gold, then orange from 5, violet from 10.
local HEAT = {
    { from = 10, color = { 0.824, 0.482, 1 } },
    { from = 5,  color = { 1, 0.541, 0.165 } },
    { from = 0,  color = { 1, 0.843, 0.353 } },
}

-- Each kind of damage: the number's colour, its glow and ring, its motes.
local SCHOOLS = {
    physical = { color = { 0.95, 0.96, 1 },    crit = { 1, 0.93, 0.72 }, glow = { 0.81, 0.84, 0.9 },  mote = { 0.95, 0.96, 1 },    fx = "steel" },
    holy     = { color = { 1, 0.95, 0.66 },    crit = { 1, 0.91, 0.54 }, glow = { 1, 0.9, 0.5 },      mote = { 1, 0.91, 0.54 },    fx = "rays" },
    fire     = { color = { 1, 0.66, 0.24 },    crit = { 1, 0.56, 0.14 }, glow = { 1, 0.48, 0.13 },    mote = { 1, 0.6, 0.16 },     fx = "embers" },
    nature   = { color = { 0.66, 0.92, 0.45 }, crit = { 0.56, 0.88, 0.35 }, glow = { 0.5, 0.88, 0.35 }, mote = { 0.56, 0.88, 0.35 }, fx = "leaves" },
    frost    = { color = { 0.72, 0.91, 1 },    crit = { 0.62, 0.87, 1 }, glow = { 0.5, 0.82, 1 },     mote = { 0.72, 0.91, 1 },    fx = "shards" },
    shadow   = { color = { 0.74, 0.55, 0.95 }, crit = { 0.66, 0.42, 0.9 }, glow = { 0.54, 0.23, 0.85 }, mote = { 0.42, 0.2, 0.62 },  fx = "smoke" },
    arcane   = { color = { 1, 0.62, 0.93 },    crit = { 1, 0.52, 0.9 },  glow = { 1, 0.48, 0.88 },    mote = { 1, 0.75, 0.96 },    fx = "stars" },
}
DamageNumbers.SCHOOLS = SCHOOLS
-- UNIT_COMBAT's school bits; a mixed one takes the first here.
local SCHOOL_ORDER = {
    { 4, "fire" }, { 16, "frost" }, { 32, "shadow" }, { 64, "arcane" }, { 8, "nature" }, { 2, "holy" },
}

--- The kind of damage a school mask is, "physical" when the client won't say.
function DamageNumbers.School(mask)
    local ok, kind = pcall(function()
        if type(mask) ~= "number" then return "physical" end
        for _, each in ipairs(SCHOOL_ORDER) do
            if math.floor(mask / each[1]) % 2 == 1 then return each[2] end
        end
        return "physical"
    end)
    return ok and kind or "physical"
end

local numbers, sparks, rings, coins, motes = {}, {}, {}, {}, {}
local combos = {}       -- [guid] = { count, last }
local lastHit = {}      -- [guid] = { at, unit, crit, amount }, to show a hit once
local pending = {}      -- [unit] = { guid, number, untilAt }
local combo             -- the one combo label
local driver
local clock = 0         -- our own time, slowed for a moment after a kill
local slowUntil = 0
local active = 0

local function Field(object, key)
    if type(object) ~= "table" then return nil end
    local ok, value = pcall(function() return object[key] end)
    if ok then return value end
    return nil
end

local function Now()
    if type(GetTime) ~= "function" then return 0 end
    local ok, value = pcall(GetTime)
    return ok and tonumber(value) or 0
end

local function InCombat()
    if type(InCombatLockdown) ~= "function" then return false end
    local ok, value = pcall(InCombatLockdown)
    return ok and value == true
end

--- A value the client won't let us compare (inside a dungeon).
local function IsSecret(value)
    local check = _G.issecretvalue
    if type(check) ~= "function" then return false end
    local ok, secret = pcall(check, value)
    return ok and secret == true
end

--- Asks the client something about a unit, nil when it won't say.
local function Ask(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, value = pcall(fn, ...)
    if not ok or IsSecret(value) then return nil end
    return value
end

--- What the hits did, for `/farm numbers check`.
DamageNumbers.seen = {}
--- Units besides plates whose hits count.
DamageNumbers.OTHER_UNITS = { target = true, focus = true, softenemy = true }

local function Dropped(why)
    local seen = DamageNumbers.seen
    seen[why] = (seen[why] or 0) + 1
    return nil
end

--------------------------------------------------------------------------------
-- Settings
--------------------------------------------------------------------------------

function DamageNumbers:IsEnabled()
    return ns.db ~= nil and ns.db.damageNumbers == true
end

function DamageNumbers:Size()
    local size = ns.db and ns.db.damageNumbersSize
    if self.SCALE[size] then return size end
    return "most"
end

function DamageNumbers:Scale()
    return self.SCALE[self:Size()]
end

function DamageNumbers:ComboOn()
    return not (ns.db and ns.db.damageNumbersCombo == false)
end

--- The spot's offset from the middle of the screen: just above your
--- character, where the target stands in front of you.
function DamageNumbers:Spot()
    return self.SPOT_X, self.SPOT_Y
end

--------------------------------------------------------------------------------
-- The game's own numbers
--------------------------------------------------------------------------------

local function GetCVarValue(name)
    local cvar = _G.C_CVar
    local get = Field(cvar, "GetCVar") or _G.GetCVar
    if type(get) ~= "function" then return nil end
    local ok, value = pcall(get, name)
    if not ok or value == nil then return nil end
    return tostring(value)
end

local function SetCVarValue(name, value)
    local cvar = _G.C_CVar
    local set = Field(cvar, "SetCVar") or _G.SetCVar
    if type(set) ~= "function" then return false end
    local ok, result = pcall(set, name, value)
    return ok and result ~= false
end
DamageNumbers.GetCVar, DamageNumbers.SetCVar = GetCVarValue, SetCVarValue

--- Turn the game's damage numbers off, keeping what the player had.
function DamageNumbers:HideGameNumbers()
    if not (ns.db and self:IsEnabled()) then return false end
    if InCombat() then
        self.hideAfterCombat, self.restoreAfterCombat = true, nil
        return false
    end
    self.hideAfterCombat = nil
    if type(ns.db.damageNumbersCVars) ~= "table" then ns.db.damageNumbersCVars = {} end
    local saved = ns.db.damageNumbersCVars
    for _, name in ipairs(self.CVARS) do
        local now = GetCVarValue(name)
        if now ~= nil and now ~= "0" then
            if saved[name] == nil then saved[name] = now end
            SetCVarValue(name, "0")
        end
    end
    return true
end

--- Put the player's own value back.
function DamageNumbers:ShowGameNumbers()
    local saved = ns.db and ns.db.damageNumbersCVars
    if type(saved) ~= "table" or next(saved) == nil then return true end
    if InCombat() then
        self.restoreAfterCombat, self.hideAfterCombat = true, nil
        return false
    end
    self.restoreAfterCombat = nil
    for name, value in pairs(saved) do
        if SetCVarValue(name, value) then saved[name] = nil end
    end
    return true
end

--------------------------------------------------------------------------------
-- Where a number sits
--------------------------------------------------------------------------------

local function PlateFor(unit)
    local forUnit = Field(_G.C_NamePlate, "GetNamePlateForUnit")
    if type(forUnit) ~= "function" then return nil end
    local ok, plate = pcall(forUnit, unit)
    if ok and type(plate) == "table" then return plate end
    return nil
end
DamageNumbers.PlateFor = PlateFor

local function UIScale()
    local ok, scale = pcall(UIParent.GetEffectiveScale, UIParent)
    return ok and tonumber(scale) or 1
end

--- The middle top of a plate in UIParent's units from its bottom left, or nil.
local function PlatePoint(plate)
    local ok, x, y = pcall(plate.GetCenter, plate)
    if not ok or type(x) ~= "number" or type(y) ~= "number" then return nil end
    local okScale, scale = pcall(plate.GetEffectiveScale, plate)
    scale = okScale and tonumber(scale) or 1
    local ratio = scale / UIScale()
    return x * ratio, y * ratio + 18
end

--- The spot, in UIParent's units from its bottom left.
local function SpotPoint()
    local x, y = DamageNumbers:Spot()
    local okW, width = pcall(UIParent.GetWidth, UIParent)
    local okH, height = pcall(UIParent.GetHeight, UIParent)
    width = okW and tonumber(width) or 1024
    height = okH and tonumber(height) or 768
    return width / 2 + x, height / 2 + y
end

--- Where an anchor stands now. A plate that went away, or now shows
--- another mob, leaves the number where it last was.
local function Where(anchor)
    if anchor.plate then
        if PlateFor(anchor.unit) == anchor.plate then
            local x, y = PlatePoint(anchor.plate)
            if x then anchor.x, anchor.y = x, y end
        else
            anchor.plate = nil
        end
    elseif not anchor.x then
        anchor.x, anchor.y = SpotPoint()
    end
    return anchor.x or 0, anchor.y or 0
end
DamageNumbers.Where = Where

--------------------------------------------------------------------------------
-- Pools
--------------------------------------------------------------------------------

local function Strata(frame)
    pcall(frame.SetFrameStrata, frame, "LOW")
    pcall(frame.EnableMouse, frame, false)
end

--- A font string's font and size. The game raises on SetText until a
--- font string has a font, so a thick outline that won't take falls back
--- to a plain one, then to the game's own font.
local function SetFont(fontString, size)
    if fontString.fontSize == size then return end
    local font = ns.Theme and ns.Theme.FONT or [[Fonts\FRIZQT__.TTF]]
    for _, flags in ipairs({ "THICKOUTLINE", "OUTLINE" }) do
        local ok, set = pcall(fontString.SetFont, fontString, font, size, flags)
        if ok and set ~= false then
            fontString.fontSize = size
            return
        end
    end
    if _G.GameFontNormalLarge then pcall(fontString.SetFontObject, fontString, _G.GameFontNormalLarge) end
    fontString.fontSize = size
end

--- A font string with a font from the start.
local function NewText(frame, size)
    local text = frame:CreateFontString(nil, "OVERLAY")
    SetFont(text, size)
    return text
end

local function NewNumber()
    local frame = CreateFrame("Frame", nil, UIParent)
    frame:SetSize(10, 10)
    Strata(frame)
    local glow = frame:CreateTexture(nil, "BACKGROUND")
    glow:SetTexture(GLOW)
    pcall(glow.SetBlendMode, glow, "ADD")
    glow:SetPoint("CENTER")
    local text = NewText(frame, 24)
    text:SetPoint("CENTER")
    local sub = NewText(frame, 14)
    sub:SetPoint("TOP", text, "BOTTOM", 0, -2)
    frame:Hide()
    return { frame = frame, glow = glow, text = text, sub = sub }
end

--- A pooled thing: one not in use, else a new one under `most`, else the
--- oldest in use.
local function Take(pool, most, make)
    local oldest
    for _, each in ipairs(pool) do
        if not each.active then return each end
        if not oldest or each.born < oldest.born then oldest = each end
    end
    if #pool < most then
        local made = make()
        pool[#pool + 1] = made
        return made
    end
    return oldest
end

local function NewTexture(path)
    return function()
        local frame = CreateFrame("Frame", nil, UIParent)
        frame:SetSize(8, 8)
        Strata(frame)
        local texture = frame:CreateTexture(nil, "OVERLAY")
        texture:SetTexture(path)
        texture:SetAllPoints()
        if path ~= COIN then pcall(texture.SetBlendMode, texture, "ADD") end
        frame:Hide()
        return { frame = frame, texture = texture }
    end
end


local function Place(frame, x, y, scale)
    scale = scale > 0.01 and scale or 0.01
    frame:SetScale(scale)
    frame:ClearAllPoints()
    -- A scaled frame's offsets are in its own units.
    frame:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / scale, y / scale)
end

--------------------------------------------------------------------------------
-- The driver
--------------------------------------------------------------------------------

local function Ease(p) return 1 - (1 - p) ^ 3 end

local function EaseBack(p)
    local c = 1.6
    return 1 + (c + 1) * (p - 1) ^ 3 + c * (p - 1) ^ 2
end

local function Level()
    local Motion = ns.Motion
    if Motion and Motion.Level then
        local ok, level = pcall(Motion.Level)
        if ok and type(level) == "string" then return level end
    end
    return "full"
end

local function StepNumber(n, now)
    local age = now - n.born
    local style = n.style
    if age >= n.life then
        n.active = nil
        n.frame:Hide()
        return false
    end
    local x, y = Where(n.anchor)
    local p = age / n.life
    local popFor = 0.2
    local scale = 1
    if n.popFrom > 1 and age < popFor then
        scale = n.popFrom + (1 - n.popFrom) * EaseBack(age / popFor)
    end
    local rise = style.rise * n.size * Ease(p)
    local dx = n.dx * Ease(math.min(1, p * 2))
    local shake = 0
    if n.shakeUntil and age < n.shakeUntil then
        shake = (math.random() * 2 - 1) * 4 * n.size
    end
    Place(n.frame, x + dx + shake, y + n.dy + rise, scale)
    local alpha = 1
    if p > 0.65 then alpha = 1 - (p - 0.65) / 0.35 end
    n.frame:SetAlpha(alpha)
    if n.hasGlow then n.glow:SetAlpha(0.55 * (1 - p)) end
    return true
end

local function StepSpark(s, now, dt)
    local age = now - s.born
    if age >= s.life then
        s.active = nil
        s.frame:Hide()
        return false
    end
    s.vy = s.vy - 380 * dt
    s.x, s.y = s.x + s.vx * dt, s.y + s.vy * dt
    local p = age / s.life
    Place(s.frame, s.x, s.y, 1)
    pcall(s.texture.SetRotation, s.texture, math.atan2 and math.atan2(s.vy, s.vx) or 0)
    s.frame:SetAlpha(1 - p)
    return true
end

local function StepRing(r, now)
    local age = now - r.born
    if age >= r.life then
        r.active = nil
        r.frame:Hide()
        return false
    end
    if age < 0 then return true end
    local p = age / r.life
    local size = r.from + (r.to - r.from) * Ease(p)
    if r.inward then size = r.to - (r.to - r.from) * Ease(p) * 0.85 end
    r.frame:SetSize(size, size)
    local x, y = Where(r.anchor)
    Place(r.frame, x + r.dx, y + r.dy, 1)
    r.frame:SetAlpha(0.9 * (1 - p))
    return true
end

local function StepCoin(c, now, dt)
    local age = now - c.born
    if age >= c.life then
        c.active = nil
        c.frame:Hide()
        return false
    end
    c.vy = c.vy - 700 * dt
    c.x, c.y = c.x + c.vx * dt, c.y + c.vy * dt
    local spin = math.abs(math.cos(age * c.spin))
    c.frame:SetSize(c.size * (0.25 + 0.75 * spin), c.size)
    Place(c.frame, c.x, c.y, 1)
    local p = age / c.life
    c.frame:SetAlpha(p > 0.7 and (1 - (p - 0.7) / 0.3) or 1)
    return true
end

local function StepMote(m, now, dt)
    local age = now - m.born
    if age >= m.life then
        m.active = nil
        m.frame:Hide()
        return false
    end
    if age < 0 then return true end
    local p = age / m.life
    local fx = m.fx
    local alpha = 1 - p
    local width, height = m.size, m.size
    local rotation
    if fx == "rays" then
        local length = m.size * (1 + 2.5 * Ease(p))
        local x = m.x + math.cos(m.angle) * length * 0.6
        local y = m.y + math.sin(m.angle) * length * 0.6
        m.frame:SetSize(length, 4)
        Place(m.frame, x, y, 1)
        pcall(m.texture.SetRotation, m.texture, m.angle)
        m.frame:SetAlpha(alpha * 0.9)
        return true
    elseif fx == "stars" then
        m.angle = m.angle + m.spin * dt
        local radius = m.radius * (0.6 + 0.6 * p)
        local x = m.x + math.cos(m.angle) * radius
        local y = m.y + math.sin(m.angle) * radius * 0.6 + 20 * p
        local twinkle = 0.7 + 0.5 * math.abs(math.sin(age * 18 + m.spin))
        m.frame:SetSize(m.size * twinkle, m.size * twinkle)
        Place(m.frame, x, y, 1)
        m.frame:SetAlpha(alpha)
        return true
    elseif fx == "embers" then
        m.vx = m.vx + math.sin(age * 14 + m.spin) * 60 * dt
    elseif fx == "leaves" then
        m.vy = m.vy - 140 * dt
        m.vx = m.vx + math.cos(age * 10 + m.spin) * 90 * dt
        rotation = age * m.spin
        width, height = m.size * 1.6, m.size * 0.8
    elseif fx == "smoke" then
        local grow = 1 + 1.6 * p
        width, height = m.size * grow, m.size * grow
        alpha = 0.7 * (1 - p)
    elseif fx == "shards" then
        m.vy = m.vy - 460 * dt
        rotation = age * m.spin
        width, height = m.size * 0.7, m.size * 1.3
    else -- steel
        m.vy = m.vy - 380 * dt
        rotation = math.atan2 and math.atan2(m.vy, m.vx) or 0
        width, height = m.size * 2.4, 3
    end
    m.x, m.y = m.x + m.vx * dt, m.y + m.vy * dt
    m.frame:SetSize(width, height)
    Place(m.frame, m.x, m.y, 1)
    if rotation then pcall(m.texture.SetRotation, m.texture, rotation) end
    m.frame:SetAlpha(alpha)
    return true
end

local function StepCombo(now)
    if not combo or not combo.active then return false end
    local age = now - combo.last
    if age >= DamageNumbers.COMBO_WINDOW then
        combo.active = nil
        combo.frame:Hide()
        return false
    end
    local x, y = Where(combo.anchor)
    local scale = 1
    local since = now - combo.bumped
    if since < 0.18 then scale = 1.35 - 0.35 * Ease(since / 0.18) end
    Place(combo.frame, x, y + 62 * combo.size, scale)
    local left = DamageNumbers.COMBO_WINDOW - age
    combo.frame:SetAlpha(left < 0.5 and left / 0.5 or 1)
    return true
end

function DamageNumbers:CheckKills(now)
    for unit, look in pairs(pending) do
        if now > look.untilAt or not look.number.active then
            pending[unit] = nil
        elseif self:IsDead(unit, look.guid) then
            pending[unit] = nil
            self:Killed(look)
        end
    end
end

--- Moves everything one frame on. Real time `elapsed`; our own clock runs
--- slow for a moment after a kill.
function DamageNumbers:Step(elapsed)
    local real = Now()
    local dt = elapsed or 0
    if real < slowUntil then dt = dt * self.SLOW end
    clock = clock + dt
    local now = clock

    self:CheckKills(real)
    local count = 0
    for _, n in ipairs(numbers) do
        if n.active and StepNumber(n, now) then count = count + 1 end
    end
    for _, s in ipairs(sparks) do
        if s.active and StepSpark(s, now, dt) then count = count + 1 end
    end
    for _, r in ipairs(rings) do
        if r.active and StepRing(r, now) then count = count + 1 end
    end
    for _, c in ipairs(coins) do
        if c.active and StepCoin(c, now, dt) then count = count + 1 end
    end
    for _, m in ipairs(motes) do
        if m.active and StepMote(m, now, dt) then count = count + 1 end
    end
    if StepCombo(now) then count = count + 1 end
    if next(pending) then count = count + 1 end
    active = count
    if count == 0 and driver then driver:SetScript("OnUpdate", nil) end
    return count
end

local function Wake()
    if not driver then
        driver = CreateFrame("Frame", nil, UIParent)
    end
    if not driver:GetScript("OnUpdate") then
        driver:SetScript("OnUpdate", function(_, elapsed)
            local ok, err = pcall(DamageNumbers.Step, DamageNumbers, elapsed)
            if not ok then
                DamageNumbers.lastError = tostring(err)
                driver:SetScript("OnUpdate", nil)
            end
        end)
    end
end

--- How many things are moving, for the tests.
function DamageNumbers:Active() return active end
--- The pools and the combo, for the tests.
function DamageNumbers:Pools()
    return { numbers = numbers, sparks = sparks, rings = rings, coins = coins, motes = motes, combo = combo, pending = pending }
end

--------------------------------------------------------------------------------
-- Effects
--------------------------------------------------------------------------------

function DamageNumbers:Burst(x, y, count, color)
    for _ = 1, count do
        local s = Take(sparks, self.MOST_SPARKS, NewTexture(SPARK))
        local angle = math.random() * math.pi * 2
        local speed = 160 + math.random() * 260
        s.x, s.y = x, y
        s.vx, s.vy = math.cos(angle) * speed, math.sin(angle) * speed + 60
        s.life = 0.35 + math.random() * 0.3
        s.born, s.active = clock, true
        local length = 12 + math.random() * 14
        s.frame:SetSize(length, 4)
        s.texture:SetVertexColor(color[1], color[2], color[3])
        s.frame:Show()
    end
end

function DamageNumbers:Ring(anchor, size, color, delay, dx, dy, inward)
    local r = Take(rings, self.MOST_RINGS, NewTexture(RING))
    r.anchor, r.dx, r.dy, r.inward = anchor, dx or 0, dy or 0, inward or nil
    r.from, r.to = 24 * size, 150 * size
    r.life = 0.5
    r.born, r.active = clock + (delay or 0), true
    r.texture:SetVertexColor(color[1], color[2], color[3])
    r.frame:SetSize(r.from, r.from)
    r.frame:SetAlpha(0)
    r.frame:Show()
end

function DamageNumbers:CoinShower(x, y, count, size)
    for _ = 1, count do
        local c = Take(coins, self.MOST_COINS, NewTexture(COIN))
        c.x, c.y = x, y
        c.vx = (math.random() * 2 - 1) * 170
        c.vy = 180 + math.random() * 200
        c.spin = 8 + math.random() * 8
        c.size = (12 + math.random() * 5) * size
        c.life = 1.1 + math.random() * 0.4
        c.born, c.active = clock, true
        c.frame:Show()
    end
end

local function NewMote()
    local frame = CreateFrame("Frame", nil, UIParent)
    frame:SetSize(8, 8)
    Strata(frame)
    local texture = frame:CreateTexture(nil, "OVERLAY")
    texture:SetAllPoints()
    frame:Hide()
    return { frame = frame, texture = texture }
end

--- `count` of a kind of damage's motes flying off x, y. `big` for a crit.
function DamageNumbers:Motes(x, y, count, school, size, big)
    local look = SCHOOLS[school] or SCHOOLS.physical
    local fx = look.fx
    local art = MOTE_ART[fx]
    local spread = big and 1.5 or 1
    for i = 1, count do
        local m = Take(motes, self.MOST_MOTES, NewMote)
        if m.art ~= art then
            m.art = art
            m.texture:SetTexture(art)
        end
        local blend = fx == "smoke" and "BLEND" or "ADD"
        if m.blend ~= blend then
            m.blend = blend
            pcall(m.texture.SetBlendMode, m.texture, blend)
        end
        pcall(m.texture.SetRotation, m.texture, 0)
        m.texture:SetVertexColor(look.mote[1], look.mote[2], look.mote[3])
        local angle = math.random() * math.pi * 2
        local speed = (60 + math.random() * 120) * spread * size
        m.fx, m.x, m.y = fx, x, y
        m.vx, m.vy = math.cos(angle) * speed, math.sin(angle) * speed
        m.angle = fx == "rays" and (i / count) * math.pi * 2 + math.random() * 0.3 or angle
        m.spin = (math.random() < 0.5 and -1 or 1) * (3 + math.random() * 4)
        m.size = (6 + math.random() * 5) * size * (big and 1.2 or 1)
        m.life = 0.55 + math.random() * 0.5
        m.radius = (24 + math.random() * 30) * size * spread
        if fx == "embers" then
            m.vx, m.vy = m.vx * 0.5, math.abs(m.vy) * 0.6 + 60 * size
            m.life = m.life + 0.4
        elseif fx == "shards" then
            m.vy = math.abs(m.vy) * 0.7 + 80 * size
        elseif fx == "leaves" then
            m.vy = math.abs(m.vy) * 0.5 + 50 * size
            m.life = m.life + 0.3
        elseif fx == "smoke" then
            m.vx, m.vy = m.vx * 0.35, -(20 + math.random() * 30) * size
            m.size = m.size * 1.6
            m.life = m.life + 0.4
        elseif fx == "steel" then
            m.vx, m.vy = m.vx * 1.8, m.vy * 0.6 + 60 * size
            m.life = 0.3 + math.random() * 0.3
        elseif fx == "rays" then
            m.size = (14 + math.random() * 12) * size * spread
            m.life = 0.45 + math.random() * 0.2
        end
        m.born, m.active = clock, true
        m.frame:SetAlpha(0)
        m.frame:Show()
    end
end

--------------------------------------------------------------------------------
-- A hit
--------------------------------------------------------------------------------

local function Style(n, kind, size, school)
    local style = STYLES[kind]
    local look = SCHOOLS[school] or SCHOOLS.physical
    n.kind, n.style, n.size, n.school = kind, style, size, school
    SetFont(n.text, math.floor(style.size * size + 0.5))
    -- The kill stays gold for everyone; hits and crits wear their kind.
    local color = kind == "kill" and style.color or (kind == "crit" and look.crit or look.color)
    n.text:SetTextColor(color[1], color[2], color[3])
    n.hasGlow = style.glow ~= nil
    if n.hasGlow then
        local glow = math.floor(style.size * size * 3.2)
        local tint = kind == "kill" and style.glow or look.glow
        n.glow:SetSize(glow * 1.6, glow)
        n.glow:SetVertexColor(tint[1], tint[2], tint[3])
        n.glow:Show()
    else
        n.glow:Hide()
    end
end

--- A number for one hit. `amount` may be a secret value: it is shown as it
--- is and never compared.
function DamageNumbers:Pop(anchor, amount, crit, school)
    school = SCHOOLS[school] and school or "physical"
    local size = self:Scale()
    local level = Level()
    local n = Take(numbers, self.MOST_NUMBERS, NewNumber)
    local kind = crit and "crit" or "hit"
    Style(n, kind, size, school)
    pcall(n.text.SetText, n.text, amount)
    pcall(n.sub.SetText, n.sub, "")
    n.anchor = anchor
    n.born, n.active, n.life = clock, true, STYLES[kind].life
    -- Hits on one mob fan out left and right so they don't sit on each other.
    anchor.fan = ((anchor.fan or 0) + 1) % 4
    local side = (anchor.fan % 2 == 0) and 1 or -1
    n.dx = side * (10 + math.random() * 26) * size
    n.dy = (math.random() * 10 - 5) * size
    n.popFrom = level == "off" and 1 or (level == "subtle" and 1.2 or STYLES[kind].pop)
    n.shakeUntil = crit and level == "full" and 0.16 or nil
    n.frame:SetAlpha(1)
    n.frame:Show()

    local look = SCHOOLS[school]
    if crit and level ~= "off" then
        self:Ring(anchor, size, look.glow, 0, n.dx, n.dy, look.fx == "smoke")
    end
    if level == "full" then
        local x, y = Where(anchor)
        local count = crit and math.floor(10 * size + 0.5) or math.max(1, math.floor(3 * size + 0.5))
        self:Motes(x + n.dx, y + n.dy, count, school, size, crit)
    end
    return n
end

--- The combo over the mob: COMBO and x5, warming as it climbs.
function DamageNumbers:Bump(anchor, guid, now)
    local entry = combos[guid]
    if not entry or now - entry.last > self.COMBO_WINDOW then
        -- Mobs long done are let go, so the list never grows.
        for each, old in pairs(combos) do
            if now - old.last > self.COMBO_WINDOW then combos[each] = nil end
        end
        entry = { count = 0 }
        combos[guid] = entry
    end
    entry.count, entry.last = entry.count + 1, now
    if not self:ComboOn() or entry.count < 2 then return entry.count end

    if not combo then
        local frame = CreateFrame("Frame", nil, UIParent)
        frame:SetSize(10, 10)
        Strata(frame)
        local count = NewText(frame, 30)
        count:SetPoint("CENTER")
        local tag = NewText(frame, 12)
        tag:SetPoint("BOTTOM", count, "TOP", 0, 0)
        combo = { frame = frame, count = count, tag = tag }
    end
    local size = self:Scale()
    combo.size, combo.anchor = size, anchor
    combo.last, combo.bumped, combo.active = clock, clock, true
    SetFont(combo.count, math.floor(30 * size + 0.5))
    SetFont(combo.tag, math.max(8, math.floor(12 * size + 0.5)))
    combo.tag:SetText(L["COMBO"])
    combo.count:SetText(("x%d"):format(entry.count))
    local color = HEAT[#HEAT].color
    for _, heat in ipairs(HEAT) do
        if entry.count >= heat.from then color = heat.color break end
    end
    combo.count:SetTextColor(color[1], color[2], color[3])
    combo.tag:SetTextColor(color[1], color[2], color[3])
    combo.frame:SetAlpha(1)
    combo.frame:Show()
    if entry.count % 5 == 0 and Level() ~= "off" then
        self:Ring(anchor, size * 0.8, color, 0, 0, 62 * size)
    end
    return entry.count
end

--- Is this unit, still the same mob, dead?
function DamageNumbers:IsDead(unit, guid)
    local now = Ask(_G.UnitGUID, unit)
    if type(guid) == "string" and type(now) == "string" and now ~= guid then return false end
    return Ask(_G.UnitIsDead, unit) == true
end

--- The kill count and worth under the killing blow: "8/20" in red until
--- 20, then the count and "+1s 20c" from your own kills.
function DamageNumbers:KillLine(name)
    local Tooltip = ns.KillTooltip
    if type(name) ~= "string" or not (Tooltip and Tooltip.Kills) then return nil end
    local key = Tooltip.KeyHere(name)
    local ok, kills = pcall(Tooltip.Kills, key)
    if not ok or type(kills) ~= "number" then return nil end
    local need = ns.Tracker and ns.Tracker.MIN_KILLS or 20
    -- The tally counts the kill when it is looted; this is the one coming.
    local coming = kills + 1
    if coming < need then return ("|cffe5604f%d/%d|r"):format(coming, need) end
    local text = ("|cffe6e8ec%d|r"):format(coming)
    if kills >= need then
        local okRead, entry = pcall(Tooltip.Read, Tooltip, key, kills)
        if okRead and type(entry) == "table" and entry.text and not entry.estimate then
            text = text .. "  +" .. entry.text
        end
    end
    return text
end

--- The last hit killed it: the number becomes the killing blow.
function DamageNumbers:Killed(look)
    local n = look.number
    if not n or not n.active or n.kind == "kill" then return end
    local size = self:Scale()
    local level = Level()
    Style(n, "kill", size, n.school)
    n.born, n.life = clock, STYLES.kill.life
    n.popFrom = level == "off" and 1 or (level == "subtle" and 1.3 or STYLES.kill.pop)
    n.shakeUntil = level == "full" and 0.22 or nil
    local line = self:KillLine(look.name)
    SetFont(n.sub, math.max(8, math.floor(15 * size + 0.5)))
    n.sub:SetText(line or "")
    if level == "off" then return end
    local x, y = Where(n.anchor)
    self:Ring(n.anchor, size * 1.2, STYLES.kill.glow, 0, n.dx, n.dy)
    self:Ring(n.anchor, size * 0.9, { 1, 0.85, 0.4 }, 0.12, n.dx, n.dy)
    if level == "full" then
        self:Burst(x + n.dx, y + n.dy, math.floor(16 * size + 0.5), STYLES.kill.glow)
        self:CoinShower(x + n.dx, y + n.dy, math.floor(8 * size + 0.5), size)
        self:Motes(x + n.dx, y + n.dy, math.floor(8 * size + 0.5), n.school, size, true)
        slowUntil = Now() + self.SLOW_FOR
    end
    Wake()
end

--- What UNIT_COMBAT says. Only a nameplate's unit, or the target when it
--- has none; only a WOUND on a mob you can attack that isn't someone
--- else's.
function DamageNumbers:OnHit(unit, kind, flag, amount, school)
    if not self:IsEnabled() or type(unit) ~= "string" then return nil end
    local plate
    if unit:find("^nameplate%d+$") then
        plate = PlateFor(unit)
        if not plate then return Dropped("no plate") end
    elseif self.OTHER_UNITS[unit] then
        -- The client may tell only the target, not its plate, so the
        -- target counts too, on its plate when it has one.
        plate = PlateFor(unit)
        if not plate and unit ~= "target" then return Dropped("no plate") end
    else
        return nil
    end
    local okKind, wound = pcall(function() return kind == "WOUND" end)
    if not (okKind and wound) then return Dropped("not a wound") end
    if Ask(_G.UnitCanAttack, "player", unit) ~= true then return Dropped("can't attack") end
    if Ask(_G.UnitIsTapDenied, unit) == true then return Dropped("someone else's") end

    local shown = amount
    if not IsSecret(amount) then
        shown = tonumber(amount)
        if not shown or shown <= 0 then return nil end
        shown = tostring(math.floor(shown + 0.5))
    end
    local okCrit, crit = pcall(function() return flag == "CRITICAL" end)
    crit = okCrit and crit == true

    local guid = Ask(_G.UnitGUID, unit)
    if type(guid) ~= "string" then guid = unit end
    -- One hit comes once for each name the mob has (its plate, the
    -- target): show it once.
    local at, last = Now(), lastHit[guid]
    if last and last.at == at and last.unit ~= unit and last.crit == crit
        and (IsSecret(amount) or last.amount == shown) then
        return Dropped("seen already")
    end
    lastHit[guid] = { at = at, unit = unit, crit = crit, amount = (not IsSecret(amount)) and shown or nil }
    self.seen.shown = (self.seen.shown or 0) + 1
    local anchor = { unit = unit, plate = plate }
    -- Hits on one mob share an anchor, so they fan out around it.
    local entry = combos[guid]
    if entry and entry.anchor and entry.anchor.unit == unit and entry.anchor.plate == plate then
        anchor = entry.anchor
    end
    Where(anchor)

    local n = self:Pop(anchor, shown, crit, self.School(school))
    self:Bump(anchor, guid, clock)
    combos[guid].anchor = anchor

    local name
    if ns.KillTooltip and ns.KillTooltip.MobName then
        local ok, value = pcall(ns.KillTooltip.MobName, ns.KillTooltip, unit, guid)
        if ok then name = value end
    end
    local look = { guid = guid, number = n, name = name, untilAt = Now() + self.KILL_LOOK }
    if self:IsDead(unit, guid) then
        self:Killed(look)
    else
        pending[unit] = look
    end
    Wake()
    return n
end

--- A nameplate going: its mob may have just died.
function DamageNumbers:PlateGone(unit)
    local look = pending[unit]
    if not look then return end
    pending[unit] = nil
    if self:IsDead(unit, look.guid) then self:Killed(look) end
end

--- Everything off the screen at once.
function DamageNumbers:Clear()
    for _, pool in ipairs({ numbers, sparks, rings, coins, motes }) do
        for _, each in ipairs(pool) do
            each.active = nil
            each.frame:Hide()
        end
    end
    if combo then combo.active = nil combo.frame:Hide() end
    for unit in pairs(pending) do pending[unit] = nil end
    for guid in pairs(combos) do combos[guid] = nil end
    for guid in pairs(lastHit) do lastHit[guid] = nil end
    active = 0
    if driver then driver:SetScript("OnUpdate", nil) end
end

--------------------------------------------------------------------------------
-- Turning it on and off
--------------------------------------------------------------------------------

local listener

function DamageNumbers:Listen(on)
    if not listener then
        listener = CreateFrame("Frame")
        listener:SetScript("OnEvent", function(_, event, unit, ...)
            if event == "UNIT_COMBAT" then
                local seen = DamageNumbers.seen
                seen.events = (seen.events or 0) + 1
                if type(unit) == "string" then
                    local token = unit:find("^nameplate%d+$") and "nameplate" or unit
                    seen["from " .. token] = (seen["from " .. token] or 0) + 1
                end
                local ok, err = pcall(DamageNumbers.OnHit, DamageNumbers, unit, ...)
                if not ok then DamageNumbers.lastError = tostring(err) end
            elseif event == "NAME_PLATE_UNIT_REMOVED" then
                pcall(DamageNumbers.PlateGone, DamageNumbers, unit)
            end
        end)
    end
    for _, event in ipairs({ "UNIT_COMBAT", "NAME_PLATE_UNIT_REMOVED" }) do
        if on then pcall(listener.RegisterEvent, listener, event)
        else pcall(listener.UnregisterEvent, listener, event) end
    end
    self.listening = on and true or false
end

function DamageNumbers:SetEnabled(on)
    ns.db.damageNumbers = on and true or false
    self:Listen(on)
    if on then
        self:HideGameNumbers()
    else
        self:ShowGameNumbers()
        self:Clear()
    end
end

function DamageNumbers:SetSize(size)
    if not self.SCALE[size] then return end
    ns.db.damageNumbersSize = size
end

function DamageNumbers:SetComboOn(on)
    ns.db.damageNumbersCombo = on and true or false
    if not on and combo then combo.active = nil combo.frame:Hide() end
end

function DamageNumbers:OnEnable()
    if self:IsEnabled() then
        self:Listen(true)
        self:HideGameNumbers()
    else
        -- A value left from before (the game closed in a fight) goes back.
        self:ShowGameNumbers()
    end
    ns.RegisterEvent(self, "PLAYER_REGEN_ENABLED", function()
        if DamageNumbers.hideAfterCombat then DamageNumbers:HideGameNumbers() end
        if DamageNumbers.restoreAfterCombat then DamageNumbers:ShowGameNumbers() end
    end)
end

--- `/farm numbers check`: what the hits did this session, for a report
--- (ns.KeepCheck saves it). English on purpose, like the other checks.
function DamageNumbers.Check()
    local function Say(text) ns.PrintRaw(text) end
    Say(("numbers check: on %s, listening %s, size %s"):format(tostring(DamageNumbers:IsEnabled()),
        tostring(listener ~= nil and DamageNumbers.listening == true), DamageNumbers:Size()))
    for _, name in ipairs(DamageNumbers.CVARS) do
        Say(("%s = %s"):format(name, tostring(GetCVarValue(name))))
    end
    local keys = {}
    for key in pairs(DamageNumbers.seen) do keys[#keys + 1] = key end
    table.sort(keys)
    if #keys == 0 then Say("no hits heard yet: hit a mob, then run this again") end
    for _, key in ipairs(keys) do Say(("%s: %d"):format(key, DamageNumbers.seen[key])) end
    local target = PlateFor("target")
    Say(("target has a nameplate: %s"):format(tostring(target ~= nil)))
    Say(("last error: %s"):format(DamageNumbers.lastError or "none"))
end

ns.RegisterCommand("numbers", L["Damage numbers on or off, or how big they are."], function(rest)
    local argument = ns.Util.Trim(rest or ""):lower()
    if argument == "check" then
        ns.KeepCheck("numbers check", DamageNumbers.Check)
        return
    end
    if DamageNumbers.SCALE[argument] then
        DamageNumbers:SetSize(argument)
    else
        local on
        if argument == "on" then on = true
        elseif argument == "off" then on = false
        else on = not DamageNumbers:IsEnabled() end
        DamageNumbers:SetEnabled(on)
        ns.Print(on and L["Damage numbers on."] or L["Damage numbers off."])
    end
    if ns.SettingsUI then ns.SettingsUI:Refresh() end
end)
