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
--   * The mob just killed glows gold and its kill count pops bigger for a
--     beat. Its progress bar toward 20 moves like a goal's (Trent,
--     2026-09-27): it slides up, the part just gained lights, a shine runs
--     along it, passing a quarter, half or three quarters pulses it gold and
--     floats "Halfway there!", and the last few float "2 more!" in green.
--   * A green-or-better drop plays the rare-drop sound, and its line pulses
--     in its quality colour with an outline, and floats as "Rare! ...".
--   * A kill streak (kills close together) pops at each kill and floats a
--     "Streak x10!" at every fifth.
--   * The kill that unlocks a mob's drop rates (or a spot's catch rates)
--     drops a gold banner over the top of the panel, with sparkles, a shine
--     across the title bar and a long gold pulse on the mob's band.
--   * On a card's loot icons (Trent, 2026-09-28): the icon whose count went
--     up flashes and shows "+2" in its corner, and an item a mob has never
--     dropped before pops in with a gold NEW tag.
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
-- The progress bar toward rates slides and shines as a goal's does.
local SLIDE_TIME = 0.5
local BAR_SHINE = 26
local COUNT_TIME = 0.7
local CHIP_TIME = 4
local FLOAT_TIME = 1.8
local FLOAT_RISE = 30
local FLOAT_GAP = 0.18
local FLOAT_SIZE = 13
local FLOAT_RARE_SIZE = 16
local MAX_FLOATS = 6

-- A loot icon: its flash, the "+2" in its corner, and how long NEW stays.
local SLOT_FLASH = 0.7
local GAIN_TIME = 2.2
local NEW_TIME = 6
local POP_GROW = 8

-- The rare-drop pulse, and the gold one on an unlocking mob's band.
local PULSE_TIME = 2.2
local PULSE_ALPHA = 0.55

-- The unlock banner: how long it stays, and its height.
local BANNER_TIME = 3.6
local BANNER_HEIGHT = 38
local SHINE_TIME = 0.9
local SHINE_WIDTH = 36
local BRIGHT_GOLD = { 1, 0.906, 0.639 }   -- #FFE7A3

-- A streak floats a cheer at every this many kills.
local STREAK_CHEER = 5

-- What a float says ahead of a drop's name, by quality.
local CHEERS = { [2] = "Nice!", [3] = "Rare!", [4] = "Epic!", [5] = "Legendary!" }

-- Two rare-drop sounds in a row would step on each other.
local RARE_GAP = 1

-- Uncommon (green) and better.
local RARE_QUALITY = 2

-- Each row's wash, and which float labels are in the air, kept here rather
-- than as fields on the frames themselves.
local flashes = setmetatable({}, { __mode = "k" })
local busy = setmetatable({}, { __mode = "k" })
local outlines = setmetatable({}, { __mode = "k" })

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

--- What the panel shows changed without anything being gained (another tab,
--- a card opened or folded, a new order): the next redraw only takes note.
function TrackerFX:Rebase()
    self.seen = nil
end

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
            seen[line.key] = { count = line.count, bar = line.bar,
                progress = line.progress, milestone = line.milestone }
        end
        -- A card's loot icons are counted one by one.
        for _, icon in ipairs(line.icons or {}) do
            if icon.key and icon.count then seen[icon.key] = { count = icon.count } end
        end
    end

    local items = SessionItems()
    local previous, previousItems = self.seen, self.loot
    self.seen, self.loot = seen, items

    if not previous then return nil end

    local plan = { lines = {}, items = {}, icons = {}, shown = shown }

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

    -- Icons: one whose count went up, and one this mob never dropped before
    -- (its first, and just looted).
    local gained = {}
    for _, item in ipairs(plan.items) do gained[item.name] = true end

    for index, line in ipairs(shown) do
        for slot, icon in ipairs(line.icons or {}) do
            local was = icon.key and previous[icon.key]
            if was and (icon.count or 0) > (was.count or 0) then
                plan.icons[#plan.icons + 1] = { index = index, slot = slot, icon = icon,
                    delta = icon.count - was.count }
            elseif not was and icon.count == 1 and gained[icon.item] then
                plan.icons[#plan.icons + 1] = { index = index, slot = slot, icon = icon,
                    delta = 1, new = true }
            end
        end
    end

    for index, line in ipairs(shown) do
        local was = line.key and previous[line.key]
        if line.key and line.count and (not was or line.count > was.count) then
            plan.lines[#plan.lines + 1] = { index = index, line = line, was = was }

            if line.key == "total" and was and TrackerFX.Level() ~= "off" then
                self.chips.total = { text = "+" .. ns.Value.Coins(line.count - was.count),
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

    -- A card's icons: their row is the anchor for their floats too.
    for _, gain in ipairs(plan.icons or {}) do
        local row = rowFor(gain.index)
        local slot = row and row.slots and row.slots[gain.slot]
        if slot and slot:IsShown() then
            rows["loot:" .. gain.icon.item] = rows["loot:" .. gain.icon.item] or row
            self:SlotGained(slot, gain, level)
        end
    end

    -- A green-or-better drop pulses on every line it is drawn on, counted
    -- or not: a mob past 20 kills shows it as a rate.
    for _, item in ipairs(plan.items) do
        if (item.quality or 0) >= RARE_QUALITY then
            local rgb = HexRGB(ns.Tracker:LookOf(item.name).color) or Color("good")
            for index, line in ipairs(plan.shown or {}) do
                local row = line.item == item.name and line.key and rowFor(index)
                if row then self:Pulse(row, line.key, rgb) end
            end
        end
    end

    if level == "full" then
        -- The top row of the column. The gathered value in the title bar
        -- stops short of the X, so floats would start on top of it.
        local first = rowFor(1)
        if first and first.line and first.line.key == "total" then first = rowFor(2) or first end

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

    -- A plain glow taking over from a pulse leaves no outline behind.
    for _, line in ipairs(outlines[row] or {}) do line:SetAlpha(0) end

    self:Start({ slot = flash, row = row, key = key, duration = GLOW_TIME,
        apply = function(p)
            local alpha = peak * (1 - p) ^ 2
            flash:SetAlpha(alpha)
            edge:SetAlpha(math.min(1, alpha * 2.5))
        end,
        stop = Hide })
end

--- A one-pixel outline round a row, for the pulse.
local function Outline(row)
    local made = outlines[row]
    if made then return made end

    made = {}
    for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
        local edge = row:CreateTexture(nil, "ARTWORK")
        if side == "TOP" or side == "BOTTOM" then
            edge:SetPoint(side .. "LEFT")
            edge:SetPoint(side .. "RIGHT")
            edge:SetHeight(1)
        else
            edge:SetPoint("TOP" .. side)
            edge:SetPoint("BOTTOM" .. side)
            edge:SetWidth(1)
        end
        edge:SetAlpha(0)
        made[#made + 1] = edge
    end

    outlines[row] = made
    return made
end

--- A longer, beating glow with an outline: a rare drop's line in its
--- quality colour, or a mob's band in gold as its rates unlock.
function TrackerFX:Pulse(row, key, rgb, peak)
    peak = peak or PULSE_ALPHA

    local flash, edge = Flash(row)
    local outline = Outline(row)
    flash:SetColorTexture(rgb[1], rgb[2], rgb[3], 1)
    edge:SetColorTexture(rgb[1], rgb[2], rgb[3], 1)
    for _, line in ipairs(outline) do line:SetColorTexture(rgb[1], rgb[2], rgb[3], 1) end

    local function Alpha(alpha)
        flash:SetAlpha(alpha)
        edge:SetAlpha(math.min(1, alpha * 2))
        for _, line in ipairs(outline) do line:SetAlpha(math.min(1, alpha * 1.8)) end
    end

    self:Start({ slot = flash, row = row, key = key, duration = PULSE_TIME,
        apply = function(p)
            -- Three beats, each a little weaker than the last.
            local beat = 0.55 + 0.45 * math.cos(p * 6 * math.pi)
            Alpha(peak * (1 - p) ^ 1.5 * beat)
        end,
        stop = function() Alpha(0) end })
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

-- What a mark on the progress bar floats as it is passed.
local MARK_CHEERS = { "25%!", "Halfway there!", "75%!" }

--- A band's progress bar went up: the goal bar's slide, lit gain and shine,
--- a gold pulse at each mark, and the countdown floating in the last stretch.
function TrackerFX:Progress(row, line, was, level)
    local UI = ns.TrackerUI
    local bar = row.progress
    local key = line.key
    if not (UI and bar) then return end

    local from = was and tonumber(was.progress) or 0
    local to = tonumber(line.progress) or 0
    if to <= from then return end

    local width = UI:ProgressWidth(row)
    local full = level == "full"

    local slide = { slot = bar.fill, row = row, key = key, duration = SLIDE_TIME,
        apply = function(p)
            UI:SetProgress(row, from + (to - from) * EaseOut(p), line.final)
        end,
        stop = function()
            if row.line and row.line.key == key then UI:SetProgress(row, to, line.final) end
        end }
    self:Start(slide)
    -- From where it was straight away, so the new length never shows first.
    pcall(slide.apply, 0)

    bar.fresh:ClearAllPoints()
    bar.fresh:SetPoint("TOPLEFT", bar.track, "TOPLEFT", width * from, 0)
    bar.fresh:SetWidth(math.max(1, width * (to - from)))
    self:Start({ slot = bar.fresh, row = row, key = key, duration = GLOW_TIME,
        delay = SLIDE_TIME * 0.6,
        apply = function(p) bar.fresh:SetAlpha(0.6 * (1 - p) ^ 2) end,
        stop = function() bar.fresh:SetAlpha(0) end })

    if full then
        local reach = math.max(BAR_SHINE, width * to)
        bar.shine:SetWidth(BAR_SHINE)
        self:Start({ slot = bar.shine, row = row, key = key, duration = SHINE_TIME,
            delay = SLIDE_TIME * 0.5,
            apply = function(p)
                bar.shine:ClearAllPoints()
                bar.shine:SetPoint("TOPLEFT", bar.track, "TOPLEFT",
                    math.max(0, (reach - BAR_SHINE) * p), 0)
                bar.shine:SetAlpha(0.55 * math.sin(p * math.pi))
            end,
            stop = function() bar.shine:SetAlpha(0) end })
    end

    local passed = was ~= nil and (line.milestone or 0) > (was.milestone or 0)
    if passed then
        self:Pulse(row, key, BRIGHT_GOLD, PULSE_ALPHA)
    end

    if not (full and was) then return end

    if passed then
        self:FloatText(Util.Colored("accent", MARK_CHEERS[line.milestone] or "Nice!"),
            row, 0.35, FLOAT_RARE_SIZE)
    elseif line.final then
        local left = (line.target or 0) - (line.have or 0)
        self:FloatText(Util.Colored("good", ("%d more!"):format(left)), row, 0.35, 15)
    end
end

--- Gathered value, counting up to its new total.
function TrackerFX:CountUp(row, key, from, to)
    local label = row.right

    self:Start({ slot = "count", row = row, key = key, duration = COUNT_TIME,
        apply = function(p)
            label:SetText(ns.Value.Coins(from + (to - from) * EaseOut(p)))
        end,
        stop = function()
            -- Only if the row still shows the value: it may show another
            -- line by now.
            if row.line and row.line.key == key then label:SetText(ns.Value.Coins(to)) end
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

    if key == "streak" then
        local cheer = was and line.count % STREAK_CHEER == 0
        self:Glow(row, key, Color("accent"), cheer and PULSE_ALPHA or BAND_ALPHA)

        if level == "full" then
            self:Pop(row, key)
            if cheer then
                self:FloatText(Util.Colored("accent", ("Streak x%d!"):format(line.count)),
                    row, 0, FLOAT_RARE_SIZE)
            end
        end
        return
    end

    if line.style == "progress" then
        self:Progress(row, line, was, level)
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
-- A card's loot icons
--------------------------------------------------------------------------------

--- An icon's count went up, or it is new: it flashes (in its quality
--- colour for green and better), "+2" rises in its corner, and a first drop
--- pops in bigger with a gold NEW tag.
function TrackerFX:SlotGained(slot, gain, level)
    local icon = gain.icon
    local key = icon.key
    local rgb = Color("good")
    local quality = TrackerFX.QualityOf(icon.item) or 0
    if quality >= RARE_QUALITY then
        rgb = HexRGB(ns.Tracker:LookOf(icon.item).color) or rgb
    end
    if gain.new then rgb = BRIGHT_GOLD end

    slot.flash:SetColorTexture(rgb[1], rgb[2], rgb[3], 1)
    slot.glow:SetColorTexture(rgb[1], rgb[2], rgb[3], 1)
    local rest = tonumber(rawget(slot, "rest")) or 0

    self:Start({ slot = slot.flash, row = slot, key = key, duration = SLOT_FLASH * 2,
        apply = function(p)
            slot.flash:SetAlpha(0.65 * (1 - p) ^ 2)
            slot.glow:SetAlpha(rest + (0.9 - rest) * (1 - p) ^ 1.5)
        end,
        stop = function()
            slot.flash:SetAlpha(0)
            slot.glow:SetAlpha(rest)
        end })

    if gain.new then
        slot.tag:SetAlpha(1)
        slot.tagText:SetAlpha(1)
        self:Start({ slot = slot.tag, row = slot, key = key, duration = NEW_TIME,
            apply = function(p)
                local alpha = p < 0.8 and 1 or (1 - p) / 0.2
                slot.tag:SetAlpha(alpha)
                slot.tagText:SetAlpha(alpha)
            end,
            stop = function()
                slot.tag:SetAlpha(0)
                slot.tagText:SetAlpha(0)
            end })

        if level == "full" then
            local size = ns.TrackerUI.SLOT
            self:Start({ slot = slot, row = slot, key = key, duration = POP_TIME * 1.5,
                apply = function(p)
                    local grow = POP_GROW * (1 - EaseOut(p))
                    slot:SetSize(size + grow, size + grow)
                end,
                stop = function() slot:SetSize(size, size) end })
        end
        return
    end

    slot.gain:SetText(("+%d"):format(gain.delta))
    self:Start({ slot = slot.gain, row = slot, key = key, duration = GAIN_TIME,
        apply = function(p)
            slot.gain:SetAlpha(p < 0.1 and p / 0.1 or (p < 0.6 and 1 or (1 - p) / 0.4))
        end,
        stop = function() slot.gain:SetAlpha(0) end })
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

--- "+2 Wool Cloth" rising off the panel's right edge beside `anchor`; a
--- green-or-better drop bigger, with a cheer ahead of it ("Rare! ...").
function TrackerFX:Float(item, anchor, delay)
    local color = ns.Tracker:LookOf(item.name).color
    local text = ("+%d %s"):format(item.delta, item.name)

    local cheer = CHEERS[item.quality or 0]
    if cheer then text = cheer .. " " .. text end

    if type(color) == "string" and #color == 8 then
        text = ("|c%s%s|r"):format(color, text)
    end

    local rare = (item.quality or 0) >= RARE_QUALITY
    self:FloatText(text, anchor, delay, rare and FLOAT_RARE_SIZE or FLOAT_SIZE)
end

--- Any text rising off the panel's right edge beside `anchor`, and fading.
function TrackerFX:FloatText(text, anchor, delay, size)
    if not anchor then return end

    local label = self:FloatLabel()
    pcall(label.SetFont, label, Theme.FONT, size or FLOAT_SIZE, "OUTLINE")
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
-- The unlock banner
--------------------------------------------------------------------------------

-- Where the sparkles sit on the banner, as fractions across and down.
local SPARKS = {
    { 0.04, 0.2 }, { 0.12, 0.85 }, { 0.3, 0.1 }, { 0.62, 0.9 },
    { 0.8, 0.12 }, { 0.95, 0.75 }, { 0.5, 0.05 }, { 0.2, 0.5 },
}

function TrackerFX:Banner()
    if self.banner then return self.banner end

    local panel = ns.TrackerUI.frame
    -- Over the top of the column, under the tabs.
    local header = ns.TrackerUI.TOP or ns.TrackerUI.HEADER

    local banner = CreateFrame("Frame", nil, panel)
    banner:SetPoint("TOPLEFT", panel, "TOPLEFT", 4, -(header + 4))
    banner:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -4, -(header + 4))
    banner:SetHeight(BANNER_HEIGHT)
    banner:SetFrameLevel(panel:GetFrameLevel() + 12)

    Theme.Fill(banner, "window", 0.96)
    Theme.Border(banner, "accent")

    -- A gold wash that breathes behind the words.
    local wash = banner:CreateTexture(nil, "BORDER")
    wash:SetAllPoints(banner)
    wash:SetColorTexture(Theme.Unpack("accent"))
    pcall(wash.SetBlendMode, wash, "ADD")
    banner.wash = wash

    local title = Theme.CreateLabel(banner, "normal", "accent", "CENTER")
    pcall(title.SetFont, title, Theme.FONT, Theme.sizes.large, "OUTLINE")
    title:SetTextColor(BRIGHT_GOLD[1], BRIGHT_GOLD[2], BRIGHT_GOLD[3], 1)
    title:SetPoint("TOPLEFT", 6, -5)
    title:SetPoint("TOPRIGHT", -6, -5)
    banner.title = title

    local subject = Theme.CreateLabel(banner, "small", "text", "CENTER")
    subject:SetPoint("BOTTOMLEFT", 6, 5)
    subject:SetPoint("BOTTOMRIGHT", -6, 5)
    banner.subject = subject

    banner.sparks = {}
    for index = 1, #SPARKS do
        local spark = banner:CreateTexture(nil, "OVERLAY")
        spark:SetSize(3, 3)
        spark:SetColorTexture(BRIGHT_GOLD[1], BRIGHT_GOLD[2], BRIGHT_GOLD[3], 1)
        pcall(spark.SetBlendMode, spark, "ADD")
        banner.sparks[index] = spark
    end

    -- The shine that sweeps across the title bar. The banner's own, though
    -- it sits over the header: the header is a frame above the panel, so a
    -- texture of the panel's would draw underneath it.
    local shine = banner:CreateTexture(nil, "OVERLAY")
    shine:SetHeight(header)
    shine:SetWidth(SHINE_WIDTH)
    shine:SetColorTexture(BRIGHT_GOLD[1], BRIGHT_GOLD[2], BRIGHT_GOLD[3], 1)
    pcall(shine.SetBlendMode, shine, "ADD")
    shine:SetAlpha(0)
    banner.shine = shine

    banner:Hide()
    self.banner = banner
    return banner
end

--- A mob's drop rates (or a spot's catch rates) just unlocked: `info` is
--- { title, subject, key }. Tracker:Fanfare calls it with the sound.
function TrackerFX:Unlocked(info)
    if TrackerFX.Level() == "off" then return end
    if not (ns.TrackerUI and ns.TrackerUI.frame and ns.TrackerUI.frame:IsShown()) then return end

    local banner = self:Banner()
    banner.title:SetText(info.title or "RATES UNLOCKED")
    banner.subject:SetText(info.subject or "")
    banner:SetAlpha(0)
    banner:Show()

    local ok, width = pcall(banner.GetWidth, banner)
    width = ok and tonumber(width) or 200

    for index, spark in ipairs(banner.sparks) do
        spark:ClearAllPoints()
        spark:SetPoint("CENTER", banner, "TOPLEFT", SPARKS[index][1] * width,
            -SPARKS[index][2] * BANNER_HEIGHT)
    end

    local panel = ns.TrackerUI.frame
    local okPanel, panelWidth = pcall(panel.GetWidth, panel)
    panelWidth = okPanel and tonumber(panelWidth) or width

    self:Start({ slot = "banner", duration = BANNER_TIME,
        apply = function(p)
            -- In fast, a moment to read it, out slowly.
            local alpha = p < 0.06 and p / 0.06 or (p > 0.8 and (1 - p) / 0.2 or 1)
            banner:SetAlpha(alpha)
            banner.wash:SetAlpha(0.12 + 0.1 * math.sin(p * 8 * math.pi))

            for index, spark in ipairs(banner.sparks) do
                local twinkle = 0.5 + 0.5 * math.sin(p * 14 * math.pi + index * 1.7)
                spark:SetAlpha(twinkle * alpha)
            end

            -- The shine crosses the title bar once, in the first moment.
            local sweep = p * BANNER_TIME / SHINE_TIME
            if sweep < 1 then
                banner.shine:ClearAllPoints()
                banner.shine:SetPoint("TOPLEFT", panel, "TOPLEFT",
                    (panelWidth - SHINE_WIDTH) * sweep, 0)
                banner.shine:SetAlpha(0.35 * math.sin(sweep * math.pi))
            else
                banner.shine:SetAlpha(0)
            end

            if p >= 1 then banner:Hide() end
        end,
        stop = function()
            banner:Hide()
            banner.shine:SetAlpha(0)
        end })

    -- The mob's band beats gold for longer than a plain kill.
    for index, line in ipairs(ns.TrackerUI.shown or {}) do
        if line.key == info.key and ns.TrackerUI.lines[index] then
            self:Pulse(ns.TrackerUI.lines[index], line.key, BRIGHT_GOLD, 0.6)
        end
    end
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

ns.RegisterCommand("effects", "how much the panels and windows move: full, subtle or off", function(rest)
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
