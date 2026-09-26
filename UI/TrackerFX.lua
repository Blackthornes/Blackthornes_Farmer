-- Blackthornes Farmer -- UI/TrackerFX.lua
-- What the kills panel does when something lands (Trent, 2026-09-26: "I'd
-- like it to give dopamine hits as you're killing stuff").
--
-- Before this the panel simply redrew, so nothing told your eye what had
-- changed. Now, on each redraw, whatever went up since the last one moves:
--
--   * Gathered value counts up to its new total, with a green "+38s" beside
--     it for a few seconds.
--   * Each item looted floats off the panel's right edge, "+2 Wool Cloth" in
--     its quality colour, and fades, like combat text.
--   * Any line whose count went up gets a wash that fades out: green, or the
--     item's own colour for green-and-better drops.
--   * The mob just killed glows gold, its kill count pops bigger for a beat,
--     and its bar toward 20 slides up instead of jumping.
--   * A green-or-better drop plays the rare-drop sound.
--
-- /farm effects (or Settings) picks Full, Subtle (washes and the count-up,
-- no floats or pops) or Off. The rare-drop sound has its own switch.
--
-- Everything here compares the addon's own counts from one redraw to the
-- next. Nothing reads the client, so a dungeon's secret values never reach
-- it, and anything that goes wrong is dropped rather than raised: the panel
-- is drawn by the loot handler, and an effect must never cost a kill.
--
-- It all runs off one OnUpdate on a small frame that is shown only while an
-- effect is playing, so an idle panel costs nothing per frame.

local _, ns = ...

local TrackerFX = ns.NewModule("TrackerFX")

local Theme = ns.Theme
local Util = ns.Util

local LEVELS = { "off", "subtle", "full" }
TrackerFX.LEVELS = LEVELS

local LEVEL_NAMES = { off = "Off", subtle = "Subtle", full = "Full" }
TrackerFX.LEVEL_NAMES = LEVEL_NAMES

-- How long each effect runs, in seconds, and how strong it starts.
local GLOW_TIME = 1.2
local GLOW_ALPHA = 0.32
local BAND_ALPHA = 0.45
local POP_TIME = 0.4
local POP_SIZE = 17
local BAR_TIME = 0.45
local COUNT_TIME = 0.7
local CHIP_TIME = 4
local FLOAT_TIME = 1.8
local FLOAT_RISE = 30
local FLOAT_GAP = 0.18
local FLOAT_SIZE = 13
local FLOAT_RARE_SIZE = 16
local MAX_FLOATS = 6

-- Two rare-drop sounds in a row would step on each other.
local RARE_GAP = 1

-- Uncommon (green) and better.
local RARE_QUALITY = 2

-- Each row's wash, and which float labels are in the air, kept here rather
-- than as fields on the frames themselves.
local flashes = setmetatable({}, { __mode = "k" })
local busy = setmetatable({}, { __mode = "k" })

TrackerFX.effects = {}
TrackerFX.clock = 0
TrackerFX.chips = {}
TrackerFX.rareAt = nil

--------------------------------------------------------------------------------
-- Settings
--------------------------------------------------------------------------------

--- "full", "subtle" or "off". Full unless you chose otherwise.
function TrackerFX.Level()
    local level = ns.db and ns.db.trackerEffects
    if level == "off" or level == "subtle" then return level end
    return "full"
end

function TrackerFX.RareSoundOn()
    return not (ns.db and ns.db.trackerRareSound == false)
end

--- An item's quality, from the colour the tracker kept for it. Nil when the
--- loot window never gave a readable link (inside a dungeon, say).
function TrackerFX.QualityOf(name)
    local look = ns.Tracker:LookOf(name)
    local color = type(look.color) == "string" and look.color:lower() or nil
    if not color then return nil end

    for quality, hex in pairs(ns.Tracker.QUALITY) do
        if hex == color then return quality end
    end

    return nil
end

--------------------------------------------------------------------------------
-- The clock
--------------------------------------------------------------------------------

local function EaseOut(p)
    return 1 - (1 - p) ^ 3
end

function TrackerFX:Driver()
    if self.driver then return self.driver end

    local parent = ns.TrackerUI and ns.TrackerUI.frame or UIParent
    local driver = CreateFrame("Frame", nil, parent)
    driver:SetScript("OnUpdate", function(_, elapsed) TrackerFX:Step(elapsed) end)
    driver:Hide()

    self.driver = driver
    return driver
end

--- Start `effect`: { slot, row, key, duration, delay, apply(p), stop() }.
-- `apply` gets 0 to 1 as it runs. A new effect in the same slot replaces the
-- old one, so a second kill mid-glow restarts the glow rather than stacking.
-- `stop` puts things back when it ends early.
function TrackerFX:Start(effect)
    for index = #self.effects, 1, -1 do
        local other = self.effects[index]
        if effect.slot and other.slot == effect.slot then
            table.remove(self.effects, index)
        end
    end

    effect.age = -(effect.delay or 0)
    self.effects[#self.effects + 1] = effect
    self:Driver():Show()
end

--- A row's wash, if it has had one. For the tests.
function TrackerFX.FlashOf(row)
    local made = flashes[row]
    return made and made[1] or nil
end

--- Whether a float label is in the air.
function TrackerFX.Floating(label)
    return busy[label] == true
end

--- A pooled row can be handed a different line by a later redraw; an effect
--- still running on it would then be drawing over someone else's line.
local function Moved(effect)
    local row = effect.row
    return row ~= nil and effect.key ~= nil
        and not (row.line and row.line.key == effect.key)
end

local function Stop(effect)
    if effect.stop then pcall(effect.stop) end
end

function TrackerFX:Step(elapsed)
    elapsed = tonumber(elapsed) or 0
    self.clock = self.clock + elapsed

    local live = {}

    for _, effect in ipairs(self.effects) do
        effect.age = effect.age + elapsed

        if Moved(effect) then
            Stop(effect)
        elseif effect.age >= 0 then
            local p = math.min(1, effect.age / effect.duration)
            local ok, err = pcall(effect.apply, p)

            if not ok then
                Stop(effect)
                ns.Debug("panel effect dropped:", tostring(err))
            elseif p < 1 then
                live[#live + 1] = effect
            end
        else
            live[#live + 1] = effect
        end
    end

    self.effects = live
    if #live == 0 and self.driver then self.driver:Hide() end
end

--- End everything at once, everything back as it was. The panel was hidden,
--- or effects were turned off.
function TrackerFX:Forget()
    for _, effect in ipairs(self.effects) do Stop(effect) end
    self.effects = {}
    self.chips = {}
    self.seen = nil
    self.loot = nil
    if self.driver then self.driver:Hide() end
end

--------------------------------------------------------------------------------
-- What changed
--------------------------------------------------------------------------------

--- Every item gathered this session, by source: kills, fishing, gathering.
local function SessionItems()
    local items = {}

    for name, count in pairs(ns.Tracker.sessionLoot or {}) do
        items["kill:" .. name] = { name = name, count = count }
    end
    if ns.Fishing then
        for name, count in pairs(ns.Fishing.sessionCatch or {}) do
            items["fish:" .. name] = { name = name, count = count }
        end
    end
    if ns.Gathering then
        for name, count in pairs(ns.Gathering.sessionItems or {}) do
            items["gather:" .. name] = { name = name, count = count }
        end
    end

    return items
end

--- Before the panel draws `shown` (the lines that fit, out of `all`): work
--- out what went up since the last redraw, and give the value line its
--- "+38s". Returns what Play needs, or nil when there is nothing to play.
--
-- The first redraw after login, or after the panel was hidden, only takes
-- note: that is where the counts start, not something that just happened.
function TrackerFX:Prepare(all, shown)
    local seen = {}
    for _, line in ipairs(all) do
        if line.key and line.count then
            seen[line.key] = { count = line.count, bar = line.bar }
        end
    end

    local items = SessionItems()
    local previous, previousItems = self.seen, self.loot
    self.seen, self.loot = seen, items

    if not previous then return nil end

    local plan = { lines = {}, items = {} }

    for key, entry in pairs(items) do
        local before = previousItems and previousItems[key] and previousItems[key].count or 0
        local count = tonumber(entry.count) or 0

        if count > before then
            plan.items[#plan.items + 1] = { key = key, name = entry.name,
                delta = count - before, quality = TrackerFX.QualityOf(entry.name) }
        end
    end

    -- Best first, so the rare one floats first and is never the one cut.
    table.sort(plan.items, function(a, b)
        local qa, qb = a.quality or 1, b.quality or 1
        if qa ~= qb then return qa > qb end
        return a.name < b.name
    end)

    for index, line in ipairs(shown) do
        local was = line.key and previous[line.key]
        if line.key and line.count and (not was or line.count > was.count) then
            plan.lines[#plan.lines + 1] = { index = index, line = line, was = was }

            if line.key == "total" and was and TrackerFX.Level() ~= "off" then
                self.chips.total = { text = "+" .. ns.Value.Money(line.count - was.count),
                    until_ = self.clock + CHIP_TIME }
            end
        end
    end

    -- The "+38s" stays for a few seconds, through any redraw in between.
    local chip = self.chips.total
    if chip and self.clock < chip.until_ then
        for _, line in ipairs(shown) do
            if line.key == "total" then line.badge = chip.text end
        end
    else
        self.chips.total = nil
    end

    return plan
end

--- After the panel drew: play what Prepare found. `rowFor(index)` is the
--- row drawing shown line `index`.
function TrackerFX:Play(plan, rowFor)
    if not plan then return end

    local rare = false
    for _, item in ipairs(plan.items) do
        if (item.quality or 0) >= RARE_QUALITY then rare = true end
    end
    if rare then self:PlayRare() end

    local level = TrackerFX.Level()
    if level == "off" then return end

    local rows = {}

    for _, gain in ipairs(plan.lines) do
        local row = rowFor(gain.index)
        if row then
            rows[gain.line.key] = row
            self:LineGained(row, gain.line, gain.was, level)
        end
    end

    if level == "full" then
        local first = rowFor(1)

        for index = 1, math.min(#plan.items, MAX_FLOATS) do
            local item = plan.items[index]
            local name = item.key:match("^kill:(.+)$")
            self:Float(item, (name and rows["loot:" .. name]) or first, (index - 1) * FLOAT_GAP)
        end
    end
end

--------------------------------------------------------------------------------
-- The effects
--------------------------------------------------------------------------------

local function Color(key)
    local r, g, b = Theme.Unpack(key)
    return { r, g, b }
end

--- "ff1eff00" as three 0-1 numbers.
local function HexRGB(hex)
    if type(hex) ~= "string" or #hex ~= 8 then return nil end
    local r = tonumber(hex:sub(3, 4), 16)
    local g = tonumber(hex:sub(5, 6), 16)
    local b = tonumber(hex:sub(7, 8), 16)
    if not (r and g and b) then return nil end
    return { r / 255, g / 255, b / 255 }
end

--- The wash over a row, and a brighter edge down its left side.
local function Flash(row)
    local made = flashes[row]
    if made then return made[1], made[2] end

    local flash = row:CreateTexture(nil, "BORDER")
    flash:SetAllPoints(row)
    pcall(flash.SetBlendMode, flash, "ADD")
    flash:SetAlpha(0)

    local edge = row:CreateTexture(nil, "ARTWORK")
    edge:SetPoint("TOPLEFT")
    edge:SetPoint("BOTTOMLEFT")
    edge:SetWidth(2)
    edge:SetAlpha(0)

    flashes[row] = { flash, edge }
    return flash, edge
end

function TrackerFX:Glow(row, key, rgb, peak)
    local flash, edge = Flash(row)
    flash:SetColorTexture(rgb[1], rgb[2], rgb[3], 1)
    edge:SetColorTexture(rgb[1], rgb[2], rgb[3], 1)

    local function Hide()
        flash:SetAlpha(0)
        edge:SetAlpha(0)
    end

    self:Start({ slot = flash, row = row, key = key, duration = GLOW_TIME,
        apply = function(p)
            local alpha = peak * (1 - p) ^ 2
            flash:SetAlpha(alpha)
            edge:SetAlpha(math.min(1, alpha * 2.5))
        end,
        stop = Hide })
end

--- The kill count, bigger for a beat and back.
function TrackerFX:Pop(row, key)
    local label = row.right
    local small = Theme.sizes.small

    local function Size(size)
        pcall(label.SetFont, label, Theme.FONT, size, "")
    end

    self:Start({ slot = label, row = row, key = key, duration = POP_TIME,
        apply = function(p)
            Size(small + (POP_SIZE - small) * (1 - EaseOut(p)))
        end,
        stop = function() Size(small) end })
end

--- The bar under the value, sliding from where it was to where it is.
function TrackerFX:Slide(row, key, from, to)
    local fill = row.fill
    local width = ns.TrackerUI.BAR

    self:Start({ slot = fill, row = row, key = key, duration = BAR_TIME,
        apply = function(p)
            local fraction = math.min(1, from + (to - from) * EaseOut(p))
            fill:SetWidth(math.max(1, width * fraction))
        end })
end

--- Gathered value, counting up to its new total.
function TrackerFX:CountUp(row, key, from, to)
    local label = row.right

    self:Start({ slot = "count", row = row, key = key, duration = COUNT_TIME,
        apply = function(p)
            label:SetText(ns.Value.Money(from + (to - from) * EaseOut(p)))
        end,
        stop = function()
            -- Only if the row still shows the value: it may show another
            -- line by now.
            if row.line and row.line.key == key then label:SetText(ns.Value.Money(to)) end
        end })

    -- The "+38s" beside it fades out at the end of its few seconds.
    local badge = row.badge
    self:Start({ slot = "chip", row = row, key = key, duration = CHIP_TIME,
        apply = function(p)
            local fade = 0.8
            badge:SetAlpha(p < fade and 1 or 1 - (p - fade) / (1 - fade))
            if p >= 1 then
                badge:SetText("")
                badge:Hide()
                badge:SetAlpha(1)
            end
        end,
        stop = function() badge:SetAlpha(1) end })
end

function TrackerFX:LineGained(row, line, was, level)
    local key = line.key

    if key == "total" then
        self:Glow(row, key, Color("good"), GLOW_ALPHA)
        if was then self:CountUp(row, key, was.count, line.count) end
        return
    end

    if line.style == "mob" then
        self:Glow(row, key, Color("accent"), BAND_ALPHA)
        if level == "full" then self:Pop(row, key) end

        if line.bar and was and was.bar and line.bar > was.bar then
            self:Slide(row, key, was.bar, line.bar)
        end
        return
    end

    -- An item in green or better washes in its own colour.
    local rgb = Color("good")
    if line.item and (TrackerFX.QualityOf(line.item) or 0) >= RARE_QUALITY then
        rgb = HexRGB(ns.Tracker:LookOf(line.item).color) or rgb
    end

    self:Glow(row, key, rgb, GLOW_ALPHA)
end

--------------------------------------------------------------------------------
-- Floating loot
--------------------------------------------------------------------------------

function TrackerFX:FloatLabel()
    self.floats = self.floats or {}

    for _, label in ipairs(self.floats) do
        if not busy[label] then return label end
    end

    if #self.floats >= MAX_FLOATS then
        -- All in the air: take the oldest.
        local label = table.remove(self.floats, 1)
        self.floats[#self.floats + 1] = label
        return label
    end

    if not self.holder then
        -- Over the panel, the size of it, so the labels draw above its rows.
        local panel = ns.TrackerUI.frame
        self.holder = CreateFrame("Frame", nil, panel)
        self.holder:SetAllPoints(panel)
        self.holder:SetFrameLevel(panel:GetFrameLevel() + 10)
    end
    local label = Theme.CreateLabel(self.holder, "normal", "text")
    label:Hide()
    self.floats[#self.floats + 1] = label
    return label
end

--- "+2 Wool Cloth" rising off the panel's right edge beside `anchor`.
function TrackerFX:Float(item, anchor, delay)
    if not anchor then return end

    local label = self:FloatLabel()
    local color = ns.Tracker:LookOf(item.name).color
    local text = ("+%d %s"):format(item.delta, item.name)
    if type(color) == "string" and #color == 8 then
        text = ("|c%s%s|r"):format(color, text)
    end

    local rare = (item.quality or 0) >= RARE_QUALITY
    pcall(label.SetFont, label, Theme.FONT, rare and FLOAT_RARE_SIZE or FLOAT_SIZE, "OUTLINE")
    label:SetText(text)
    label:SetAlpha(0)
    busy[label] = true

    local function Place(rise)
        label:ClearAllPoints()
        label:SetPoint("LEFT", anchor, "RIGHT", 8, rise)
    end

    Place(0)
    label:Show()

    self:Start({ slot = label, duration = FLOAT_TIME, delay = delay,
        apply = function(p)
            Place(FLOAT_RISE * EaseOut(p))
            label:SetAlpha(p < 0.15 and p / 0.15 or (1 - (p - 0.15) / 0.85))
            if p >= 1 then
                label:Hide()
                busy[label] = nil
            end
        end,
        stop = function()
            label:Hide()
            busy[label] = nil
        end })
end

--------------------------------------------------------------------------------
-- Sound
--------------------------------------------------------------------------------

function TrackerFX:PlayRare()
    if not TrackerFX.RareSoundOn() then return end
    local now = type(GetTime) == "function" and GetTime() or self.clock
    if self.rareAt and now - self.rareAt < RARE_GAP then return end

    self.rareAt = now
    ns.Tracker.PlayFile(ns.Tracker.SOUNDS.rare)
end

--------------------------------------------------------------------------------
-- Commands
--------------------------------------------------------------------------------

function TrackerFX:SetLevel(level)
    ns.db.trackerEffects = level
    if level == "off" then self:Forget() end
    if ns.SettingsUI and ns.SettingsUI.Refresh then ns.SettingsUI:Refresh() end
end

ns.RegisterCommand("effects", "how much the kill panel moves: full, subtle or off", function(rest)
    local argument = Util.Trim(rest):lower()

    if not LEVEL_NAMES[argument] then
        -- No word: step round full, subtle, off.
        local current = TrackerFX.Level()
        for index, level in ipairs(LEVELS) do
            if level == current then argument = LEVELS[index == 1 and #LEVELS or index - 1] end
        end
    end

    TrackerFX:SetLevel(argument)

    local lines = {
        full = "panel effects: full. Counts glow, value counts up, loot floats off the panel.",
        subtle = "panel effects: subtle. Counts glow and value counts up; nothing floats.",
        off = "panel effects off. /farm effects full turns them back on.",
    }
    ns.Print(lines[argument])
end)

ns.RegisterCommand("raresound", "a sound when something green or better drops (on/off)", function(rest)
    local argument = Util.Trim(rest):lower()

    if argument == "on" then
        ns.db.trackerRareSound = true
    elseif argument == "off" then
        ns.db.trackerRareSound = false
    else
        ns.db.trackerRareSound = ns.db.trackerRareSound == false
    end

    ns.Print(TrackerFX.RareSoundOn()
        and "a sound plays when something green or better drops. /farm raresound off to stop."
        or "no sound for rare drops. /farm raresound on to bring it back.")

    if ns.SettingsUI and ns.SettingsUI.Refresh then ns.SettingsUI:Refresh() end
end)
