-- Blackthornes Farmer -- Logic/GrindTo60.lua
-- Grind to 60 (the owner said build it, 2026-11-22, from a mockup whose
-- words he approved; a test feature, off unless ticked on the Experimental
-- page). A path of grind camps from level 1 to 60 for the character
-- playing: the first steps where its race starts, then camps on its side
-- or in zones both sides share, never an enemy town. Each step is the camp
-- that pays best for its levels, for gold and XP together (or one first).
--
-- Only what Farmer already holds is used: the Grind tab's mob spots
-- (Grinding:Mobs, Forever spots ahead of Classic rows), what they drop
-- priced the house way (Value:ForMob), your own kill XP when this session
-- has it, and herbs and skins only when you know Herbalism or Skinning.
-- A camp with real Forever kills beats any guess; where none has them, the
-- older drop lists fill in and the step says "estimate".
--
-- Kill rewards stay secret: the steps compare by dots, never gold a kill,
-- rates or percentages.
--
-- Worked out once per level, hide or skip (a stamp), never on a timer.
-- Saved, never renamed: `grindTo60` (nil off, true on), `grindTo60View`
-- (the chip picked), `grindTo60Pick`, `grindTo60Areas` (areas hidden here,
-- [lower "zone|place"] = { zone, label }), `grindTo60Mobs` (mobs hidden from
-- here, also on the hide list, [lower name] = name) and `grindElites`
-- ([name] = true, learned in game while on).

local _, ns = ...
local L = ns.L

local GrindTo60 = ns.NewModule("GrindTo60")

local Util = ns.Util

GrindTo60.TOP = 60
-- Levels a step covers, at least and at most.
GrindTo60.STEP_MIN = 3
GrindTo60.STEP_MOST = 6
-- How far over a step's first level a mob may start and still count: more
-- and the first kills there are too hard. A mob whose top is under the
-- step's first level is left out, it goes grey before the step is done.
GrindTo60.ABOVE = 3
-- Mobs a camp needs before "lots of mobs" is said of it.
GrindTo60.MANY = 3
-- Mobs Farmer must have seen at a camp, across all its mobs, for it to be
-- real rather than a guess.
GrindTo60.REAL_KILLS = 20
-- Steps whose top is under this lean hard on the race's own zone.
GrindTo60.HOME_UNTIL = 12

GrindTo60.PICKS = {
    { key = "both", label = L["Gold and XP"] },
    { key = "gold", label = L["Gold First"] },
    { key = "xp", label = L["XP First"] },
}

-- Where each race starts, by the game's English token.
GrindTo60.STARTS = {
    Human = "Elwynn Forest", Dwarf = "Dun Morogh", Gnome = "Dun Morogh", NightElf = "Teldrassil",
    Orc = "Durotar", Troll = "Durotar", Tauren = "Mulgore", Scourge = "Tirisfal Glades", Undead = "Tirisfal Glades",
}
GrindTo60.SIDE_START = { Alliance = "Elwynn Forest", Horde = "Durotar" }

-- Which side holds a zone. Zones not here are shared ("both"); a zone the
-- map does not know is left out.
GrindTo60.SIDES = {
    ["Elwynn Forest"] = "Alliance", ["Dun Morogh"] = "Alliance", ["Teldrassil"] = "Alliance",
    ["Westfall"] = "Alliance", ["Loch Modan"] = "Alliance", ["Darkshore"] = "Alliance",
    ["Redridge Mountains"] = "Alliance", ["Duskwood"] = "Alliance", ["Wetlands"] = "Alliance",
    ["Durotar"] = "Horde", ["Mulgore"] = "Horde", ["Tirisfal Glades"] = "Horde",
    ["The Barrens"] = "Horde", ["Silverpine Forest"] = "Horde",
}

-- Towns, by the side that holds them: never a camp, and the enemy's are
-- kept off the path whatever zone they are in.
GrindTo60.TOWNS = {
    ["The Crossroads"] = "Horde", ["Crossroads"] = "Horde", ["Camp Taurajo"] = "Horde", ["Razor Hill"] = "Horde",
    ["Bloodhoof Village"] = "Horde", ["Brill"] = "Horde", ["The Sepulcher"] = "Horde", ["Tarren Mill"] = "Horde",
    ["Hammerfall"] = "Horde", ["Kargath"] = "Horde", ["Grom'gol Base Camp"] = "Horde", ["Stonard"] = "Horde",
    ["Brackenwall Village"] = "Horde", ["Freewind Post"] = "Horde", ["Camp Mojache"] = "Horde",
    ["Shadowprey Village"] = "Horde", ["Splintertree Post"] = "Horde", ["Sun Rock Retreat"] = "Horde",
    ["Zoram'gar Outpost"] = "Horde", ["Valormok"] = "Horde", ["Bloodvenom Post"] = "Horde",
    ["Revantusk Village"] = "Horde", ["Sen'jin Village"] = "Horde",
    ["Goldshire"] = "Alliance", ["Kharanos"] = "Alliance", ["Dolanaar"] = "Alliance", ["Sentinel Hill"] = "Alliance",
    ["Thelsamar"] = "Alliance", ["Auberdine"] = "Alliance", ["Lakeshire"] = "Alliance", ["Darkshire"] = "Alliance",
    ["Menethil Harbor"] = "Alliance", ["Southshore"] = "Alliance", ["Refuge Pointe"] = "Alliance",
    ["Theramore Isle"] = "Alliance", ["Astranaar"] = "Alliance", ["Stonetalon Peak"] = "Alliance",
    ["Nijel's Point"] = "Alliance", ["Feathermoon Stronghold"] = "Alliance", ["Thalanaar"] = "Alliance",
    ["Nethergarde Keep"] = "Alliance", ["Aerie Peak"] = "Alliance", ["Talonbranch Glade"] = "Alliance",
    ["Chillwind Camp"] = "Alliance", ["Morgan's Vigil"] = "Alliance",
}

--------------------------------------------------------------------------------
-- Settings
--------------------------------------------------------------------------------

function GrindTo60.IsOn()
    return ns.db ~= nil and ns.db.grindTo60 == true
end

function GrindTo60:SetOn(on)
    if not ns.db then return end
    ns.db.grindTo60 = on and true or nil
    if not on then ns.db.grindTo60View = nil end
    self.plan = nil
end

--- Is the Grind tab showing the path (the chip picked, the feature on)?
function GrindTo60.Shown()
    return GrindTo60.IsOn() and ns.db.grindTo60View == true
end

function GrindTo60:SetShown(on)
    if not ns.db then return end
    ns.db.grindTo60View = on and GrindTo60.IsOn() or nil
end

function GrindTo60.Pick()
    local saved = ns.db and ns.db.grindTo60Pick
    for _, entry in ipairs(GrindTo60.PICKS) do
        if entry.key == saved then return saved end
    end
    return "both"
end

function GrindTo60:SetPick(key)
    local known = false
    for _, entry in ipairs(GrindTo60.PICKS) do
        if entry.key == key then known = true end
    end
    if ns.db then ns.db.grindTo60Pick = known and key ~= "both" and key or nil end
end

function GrindTo60.PickLabel(key)
    key = key or GrindTo60.Pick()
    for _, entry in ipairs(GrindTo60.PICKS) do
        if entry.key == key then return entry.label end
    end
    return GrindTo60.PICKS[1].label
end

--------------------------------------------------------------------------------
-- Who is playing
--------------------------------------------------------------------------------

local function Read(fn, ...)
    if type(fn) ~= "function" then return nil end
    local results = { pcall(fn, ...) }
    if not results[1] then return nil end
    -- A secret value raises when touched: a number is read by adding to
    -- it, words by Harvest's own copy.
    local Readable = ns.Harvest and ns.Harvest.Readable or function(value) return value end
    local out = {}
    for index = 2, #results do
        local raw = results[index]
        local ok, value
        if type(raw) == "number" then
            ok, value = pcall(function() return raw + 0 end)
        else
            ok, value = pcall(Readable, raw)
        end
        out[index - 1] = ok and value or nil
    end
    return out
end

--- { level, race, raceName, class, className, faction, factionName, start }.
--- Any part the client will not say is nil.
function GrindTo60.Who()
    local who = {}
    local level = Read(UnitLevel, "player")
    who.level = level and tonumber(level[1]) or nil
    if who.level and who.level <= 0 then who.level = nil end
    local race = Read(UnitRace, "player")
    if race then who.raceName, who.race = race[1], race[2] end
    local class = Read(UnitClass, "player")
    if class then who.className, who.class = class[1], class[2] end
    local faction = Read(UnitFactionGroup, "player")
    if faction then who.faction, who.factionName = faction[1], faction[2] or faction[1] end
    if who.faction ~= "Alliance" and who.faction ~= "Horde" then who.faction = nil end
    who.start = GrindTo60.STARTS[who.race or ""] or GrindTo60.SIDE_START[who.faction or ""]
    return who
end

--- Your Skinning and Herbalism, or nil for one you lack.
function GrindTo60.Skills()
    local skills = ns.Spots and ns.Spots.Skills and ns.Spots.Skills()
    if type(skills) ~= "table" then return {} end
    return { Skinning = tonumber(skills.Skinning), Herbalism = tonumber(skills.Herbalism) }
end

--------------------------------------------------------------------------------
-- Sides and towns
--------------------------------------------------------------------------------

--- "Alliance", "Horde" or "both" for a zone; nil for one the map does not
--- know.
function GrindTo60.SideOf(zone)
    if type(zone) ~= "string" then return nil end
    local side = GrindTo60.SIDES[zone]
    if side then return side end
    if ns.Spots and ns.Spots.Known and not ns.Spots.Known(zone) then return nil end
    return "both"
end

--- May `faction` grind in `zone` at all?
function GrindTo60.Allowed(zone, faction)
    local side = GrindTo60.SideOf(zone)
    if not side then return false end
    return side == "both" or not faction or side == faction
end

--- Is `place` a town (a camp of guards, never of grind mobs)?
function GrindTo60.IsTown(place)
    return type(place) == "string" and GrindTo60.TOWNS[place] ~= nil
end

--------------------------------------------------------------------------------
-- Elites, learned in game while on
--------------------------------------------------------------------------------

function GrindTo60:Learn(unit, name)
    if not GrindTo60.IsOn() or type(name) ~= "string" or name == "" then return end
    if type(UnitClassification) ~= "function" then return end
    local ok, value = pcall(UnitClassification, unit)
    local Readable = ns.Harvest and ns.Harvest.Readable
    value = ok and Readable and Readable(value) or nil
    if value ~= "elite" and value ~= "rareelite" and value ~= "worldboss" then return end
    if type(ns.db.grindElites) ~= "table" then ns.db.grindElites = {} end
    if not ns.db.grindElites[name] then
        ns.db.grindElites[name] = true
        self.elitesVersion = (self.elitesVersion or 0) + 1
    end
end

function GrindTo60.IsElite(name)
    local store = ns.db and ns.db.grindElites
    return type(store) == "table" and store[name] == true
end

--------------------------------------------------------------------------------
-- Hiding and skipping
--------------------------------------------------------------------------------

local function AreaKey(zone, label)
    return (tostring(zone) .. "|" .. tostring(label)):lower()
end

local function Store(key)
    if not ns.db then return {} end
    if type(ns.db[key]) ~= "table" then ns.db[key] = {} end
    return ns.db[key]
end

function GrindTo60.AreaHidden(zone, label)
    local areas = ns.db and ns.db.grindTo60Areas
    return type(areas) == "table" and areas[AreaKey(zone, label)] ~= nil
end

--- Hide a step's area from the path. Returns its label.
function GrindTo60:HideArea(step)
    if type(step) ~= "table" or not step.zone then return nil end
    Store("grindTo60Areas")[AreaKey(step.zone, step.label)] = { zone = step.zone, label = step.label }
    self.areasVersion = (self.areasVersion or 0) + 1
    self.plan = nil
    ns.Print(L.Format("%s is hidden from Grind to 60.", Util.Colored("accent", step.label or step.zone)))
    if ns.GrindingUI and ns.GrindingUI.Refresh then ns.GrindingUI:Refresh() end
    return step.label
end

--- Hide a mob: Farmer's hide list (so /farm hidden shows it), noted as
--- hidden from here so Show Again brings it back.
function GrindTo60:HideMob(name)
    if type(name) ~= "string" or name == "" then return nil end
    Store("grindTo60Mobs")[name:lower()] = name
    self.plan = nil
    ns.Print(L.Format("%s is hidden from Grind to 60.", Util.Colored("accent", name)))
    -- The hide list's watchers redraw the Grind tab.
    ns.DB:Hide("source", name)
    return name
end

--- How many areas and mobs are hidden from here (a mob shown again from
--- /farm hidden no longer counts).
function GrindTo60.HiddenCount()
    local count = 0
    for _ in pairs(type(ns.db and ns.db.grindTo60Areas) == "table" and ns.db.grindTo60Areas or {}) do
        count = count + 1
    end
    for _, name in pairs(type(ns.db and ns.db.grindTo60Mobs) == "table" and ns.db.grindTo60Mobs or {}) do
        if ns.DB:IsHiddenSource(name) then count = count + 1 end
    end
    return count
end

--- Bring back everything hidden from here.
function GrindTo60:ShowAgain()
    if not ns.db then return end
    local mobs = type(ns.db.grindTo60Mobs) == "table" and ns.db.grindTo60Mobs or {}
    ns.db.grindTo60Areas, ns.db.grindTo60Mobs = nil, nil
    self.areasVersion = (self.areasVersion or 0) + 1
    self.plan = nil
    local changed = false
    for _, name in pairs(mobs) do
        local key = name:lower()
        local list = ns.DB:HidesAny("source") and ns.DB:HiddenList("source") or {}
        if list[key] then list[key] = nil; changed = true end
    end
    if changed then
        ns.DB:HiddenChanged()
    elseif ns.GrindingUI and ns.GrindingUI.Refresh then
        ns.GrindingUI:Refresh()
    end
end

--- Skip Step: this camp is passed over for the rest of the session, and
--- the next best takes its levels.
function GrindTo60:Skip(step)
    if type(step) ~= "table" or not step.key then return end
    self.skips = self.skips or {}
    self.skips[step.key] = true
    self.skipsVersion = (self.skipsVersion or 0) + 1
    self.plan = nil
end

--------------------------------------------------------------------------------
-- Camps
--------------------------------------------------------------------------------

local function Distance(a, b)
    local dx, dy = a[1] - b[1], a[2] - b[2]
    return math.sqrt(dx * dx + dy * dy)
end

--- Every mob spot grouped into camps, kept while the Grind tab's list is.
--- { zone, location, label, key, coords, mobs }.
function GrindTo60:Camps()
    local Grinding = ns.Grinding
    local all = Grinding:Mobs().all
    if self.camps and self.campsFrom == Grinding.cache then return self.camps end

    local list = {}
    for _, mob in pairs(all) do list[#list + 1] = mob end
    table.sort(list, function(a, b)
        if a.zone ~= b.zone then return a.zone < b.zone end
        if (a.location or "") ~= (b.location or "") then return (a.location or "") < (b.location or "") end
        return a.name < b.name
    end)

    local camps, byKey, loose = {}, {}, {}
    local function Camp(key, zone, location, coords)
        local camp = byKey[key]
        if not camp then
            camp = { key = key, zone = zone, location = location, anchor = coords, mobs = {} }
            byKey[key] = camp
            camps[#camps + 1] = camp
        end
        return camp
    end

    for _, mob in ipairs(list) do
        if mob.dropSpot and mob.minLevel then
            local camp
            if mob.location then
                camp = Camp(AreaKey(mob.zone, mob.location), mob.zone, mob.location)
            elseif mob.coords then
                loose[mob.zone] = loose[mob.zone] or {}
                for _, near in ipairs(loose[mob.zone]) do
                    if Distance(near.anchor, mob.coords) <= Grinding.NEAR then camp = near break end
                end
                if not camp then
                    camp = Camp(AreaKey(mob.zone, "@" .. (#loose[mob.zone] + 1)), mob.zone, nil, mob.coords)
                    table.insert(loose[mob.zone], camp)
                end
            end
            if camp then camp.mobs[#camp.mobs + 1] = mob end
        end
    end

    for _, camp in ipairs(camps) do
        local sumX, sumY, count = 0, 0, 0
        for _, mob in ipairs(camp.mobs) do
            if mob.coords then sumX, sumY, count = sumX + mob.coords[1], sumY + mob.coords[2], count + 1 end
        end
        if count > 0 then camp.coords = { sumX / count, sumY / count } end
        if camp.location then
            camp.label = camp.location
        elseif camp.coords then
            camp.label = L.Format("around %.0f, %.0f", camp.coords[1], camp.coords[2])
        end
        camp.anchor = nil
    end

    self.camps, self.campsFrom = camps, Grinding.cache
    return camps
end

--------------------------------------------------------------------------------
-- Worth: XP and gold, only ever compared
--------------------------------------------------------------------------------

-- Classic's grey level gap by your level.
local function GreyGap(level)
    if level < 8 then return 5 end
    if level < 10 then return 6 end
    if level < 12 then return 7 end
    if level < 16 then return 8 end
    if level < 20 then return 9 end
    if level < 30 then return 11 end
    if level < 40 then return 12 end
    if level < 45 then return 13 end
    if level < 50 then return 14 end
    if level < 55 then return 15 end
    return 16
end

--- About what a kill of a mob of `mobLevel` gives at `level`, by Classic's
--- rule. Only ever compared, never shown.
function GrindTo60.KillXP(mobLevel, level)
    if not (mobLevel and level) then return 0 end
    local base = level * 5 + 45
    if mobLevel >= level then
        return base * (1 + 0.05 * math.min(mobLevel - level, 4))
    end
    local gap = GreyGap(level)
    if level - mobLevel >= gap then return 0 end
    return base * (1 - (level - mobLevel) / gap)
end

local function Midpoint(mob)
    local low = mob.minLevel or 0
    return (low + (mob.maxLevel or low)) / 2
end

--------------------------------------------------------------------------------
-- The plan
--------------------------------------------------------------------------------

local function Stamp(who, skills)
    local Grinding = ns.Grinding
    Grinding:Mobs()
    return table.concat({ tostring(who.level), tostring(who.race), tostring(who.class), tostring(who.faction),
        tostring(Grinding.cacheStamp), tostring(ns.DB.hiddenVersion or 0), tostring(GrindTo60.areasVersion or 0),
        tostring(GrindTo60.skipsVersion or 0), tostring(GrindTo60.elitesVersion or 0), GrindTo60.Pick(),
        tostring(skills.Skinning and math.floor(skills.Skinning / 25)),
        tostring(skills.Herbalism and math.floor(skills.Herbalism / 25)) }, "|")
end

--- What one camp looks like for levels low..high, or nil when no mob there
--- fits. Kept per plan: worth reads are a pcall each.
function GrindTo60:Look(camp, low, high, who, skills, kept)
    local mobs, seen = {}, {}
    local ZoneBoard = ns.ZoneBoard
    local slackLow, slackHigh = low, math.min(high, low + GrindTo60.ABOVE)
    for _, mob in ipairs(camp.mobs) do
        if not seen[mob.name] and mob.minLevel <= slackHigh and (mob.maxLevel or mob.minLevel) >= slackLow
            and mob.minLevel >= 1 and not GrindTo60.IsElite(mob.name)
            and not (ZoneBoard and ZoneBoard.LeftOut and ZoneBoard.LeftOut(mob)) then
            seen[mob.name] = true
            mobs[#mobs + 1] = mob
        end
    end
    if #mobs == 0 then return nil end

    local level = math.floor((low + high) / 2)
    local own = ns.XP and ns.XP.mobs or {}
    local onStep = who.level and who.level >= low and who.level < high
    local xp, gold, kills, forever, skinnable, cloth = 0, 0, 0, false, {}, false
    local leathers = {}
    for _, mob in ipairs(mobs) do
        local mine = own[mob.name]
        local each
        if onStep and type(mine) == "table" and (tonumber(mine.kills) or 0) >= 3 then
            each = mine.xp / mine.kills
        else
            each = GrindTo60.KillXP(Midpoint(mob), level)
        end
        xp = xp + each

        local worth = kept.worth[mob.name]
        if worth == nil then
            local ok, value = pcall(ns.Value.ForMob, ns.Value, mob.name)
            worth = ok and type(value) == "number" and value or 0
            kept.worth[mob.name] = worth
        end
        gold = gold + worth

        kills = kills + (tonumber(mob.corpses) or 0)
        if mob.forever then forever = true end
        if mob.cloth then cloth = true end
        if skills.Skinning and (mob.skinning or next(mob.leathers or {}) ~= nil) then
            local needSkin = mob.skinSkill or ns.Grinding.SkinSkill(mob.minLevel)
            if needSkin and needSkin <= skills.Skinning then
                skinnable[#skinnable + 1] = mob
                local copper = ns.GrindGather and ns.GrindGather:SkinWorth(mob.name)
                if not copper then
                    for name in pairs(mob.leathers or {}) do
                        local item = ns.DB:GetItem(name)
                        local ok, price = pcall(ns.Value.UnitPrice, ns.Value, item and item.id)
                        if ok and type(price) == "number" then copper = math.max(copper or 0, price) end
                    end
                end
                gold = gold + (copper or 0)
                for name in pairs(mob.leathers or {}) do leathers[name] = true end
            end
        end
    end
    -- A camp's worth is its mobs together: more kinds of mob, more to pull.
    local count = #mobs
    local density = count + math.min(3, kills / 100)
    local perMob = 1 / count

    -- Herbs in the zone you can pick add to the gold.
    local herbs, herbGold = {}, 0
    if skills.Herbalism then
        for _, row in ipairs(kept.herbs[camp.zone] or {}) do
            local reach = not row.skill or row.skill <= skills.Herbalism
            local fits = not row.minLevel or (row.minLevel <= high + 5 and (row.maxLevel or row.minLevel) >= low - 5)
            if reach and fits and not herbs[row.item] then
                herbs[row.item] = row
                herbs[#herbs + 1] = row
                herbGold = herbGold + (row.price or 0)
            end
        end
        table.sort(herbs, function(a, b) return (a.price or 0) > (b.price or 0) end)
        if #herbs > 0 then herbGold = herbGold / #herbs * 0.5 end
    end

    local look = {
        camp = camp, mobs = mobs, low = low, high = high,
        -- Against a kill of a mob your own level, so a step's dots tell how
        -- good its camp is, not how early it comes.
        xp = density * xp * perMob / (level * 5 + 45),
        gold = density * (gold * perMob + herbGold),
        kills = kills, real = forever and true or false,
        cloth = cloth, skinnable = skinnable, leathers = leathers, herbs = herbs,
    }
    look.estimate = not look.real
    return look
end

--- The best camp for levels low..high after `prev` (the step before).
local function Choose(looks, pick, prev, who, low)
    if #looks == 0 then return nil end
    local most = { xp = 0, gold = 0 }
    for _, look in ipairs(looks) do
        most.xp = math.max(most.xp, look.xp)
        most.gold = math.max(most.gold, look.gold)
    end
    local anyReal = false
    for _, look in ipairs(looks) do if look.real then anyReal = true end end

    local best, bestScore
    for _, look in ipairs(looks) do
        if look.real or not anyReal then
            local x = most.xp > 0 and look.xp / most.xp or 0
            local g = most.gold > 0 and look.gold / most.gold or 0
            local score
            if pick == "gold" then score = g * 2 + x * 0.5
            elseif pick == "xp" then score = x * 2 + g * 0.5
            else score = x + g end
            local zone = look.camp.zone
            if low < GrindTo60.HOME_UNTIL and who.start and zone == who.start then score = score + 1 end
            if prev then
                if prev.zone == zone then
                    score = score + 0.3
                else
                    local hops, how = ns.Spots.Hops(prev.zone, zone)
                    if how == "other continent" then score = score - 0.3
                    elseif hops and hops <= 1 then score = score + 0.15 end
                end
            end
            -- Classes without a heal of their own lean off mobs over the step.
            if (who.class == "WARRIOR" or who.class == "ROGUE") then
                for _, mob in ipairs(look.mobs) do
                    if (mob.maxLevel or mob.minLevel) > look.high + 1 then score = score - 0.1 break end
                end
            end
            if not bestScore or score > bestScore
                or (score == bestScore and look.camp.key < best.camp.key) then
                best, bestScore = look, score
            end
        end
    end
    return best
end

-- Words for why a step was picked, in order.
local REASONS = {
    many = L["Lots of mobs close together."],
    cloth = L["Cloth sells well."],
    herbs = L["Herbs grow along the path."],
    skins = L["Mobs here can be skinned."],
}

local function Dots(value, sorted)
    if #sorted == 0 or not value then return 1 end
    local below = 0
    for _, each in ipairs(sorted) do if each < value then below = below + 1 end end
    return 1 + math.floor(3 * below / math.max(1, #sorted - 1) + 0.5)
end

--- The path: { who, skills, steps, current, top, empty }. Each step
--- { low, high, zone, location, label, key, camp, mobs, real, estimate,
--- xpDots, goldDots, herbs, skinnable, leathers, elites, both, reasons,
--- drops, kills, done, current }.
function GrindTo60:Plan()
    local who = GrindTo60.Who()
    local skills = GrindTo60.Skills()
    local stamp = Stamp(who, skills)
    if self.plan and self.planStamp == stamp then return self.plan end

    local plan = { who = who, skills = skills, steps = {} }
    local level = who.level or 1
    plan.top = level >= GrindTo60.TOP

    local camps = self:Camps()
    local kept = { worth = {}, herbs = {} }
    if skills.Herbalism and ns.GrindGather then
        for _, row in ipairs(ns.GrindGather:DataRows("herbs")) do
            local item = ns.DB:GetItem(row.item)
            local ok, price = pcall(ns.Value.UnitPrice, ns.Value, item and item.id)
            kept.herbs[row.zone] = kept.herbs[row.zone] or {}
            table.insert(kept.herbs[row.zone], { item = row.item, skill = row.skill, minLevel = row.minLevel,
                maxLevel = row.maxLevel, price = ok and type(price) == "number" and price or 0 })
        end
    end

    local usable = {}
    for _, camp in ipairs(camps) do
        if GrindTo60.Allowed(camp.zone, who.faction) and not GrindTo60.IsTown(camp.location)
            and not (ns.Spots.IsInstance(camp.zone) or ns.Spots.IsInstance(camp.location))
            and not GrindTo60.AreaHidden(camp.zone, camp.label)
            and not (self.skips and self.skips[camp.key]) then
            usable[#usable + 1] = camp
        end
    end

    local low, prev, from = 1, nil, nil
    while low < GrindTo60.TOP do
        local high = math.min(GrindTo60.TOP, low + 5)
        local looks = {}
        for _, camp in ipairs(usable) do
            local look = self:Look(camp, low, high, who, skills, kept)
            if look then looks[#looks + 1] = look end
        end
        local best = Choose(looks, GrindTo60.Pick(), prev, who, low)
        if not best then
            -- No camp for these levels: the step before runs on through
            -- them, so the path has no hole and still ends at the top.
            if prev then
                prev.high = high
                prev.camp.maxLevel = high
            else
                from = from or low
            end
            low = high
        else
            local top = 0
            for _, mob in ipairs(best.mobs) do top = math.max(top, mob.maxLevel or mob.minLevel) end
            local stepHigh = math.max(low + GrindTo60.STEP_MIN, math.min(low + GrindTo60.STEP_MOST, top + 1))
            stepHigh = math.min(GrindTo60.TOP, stepHigh)
            local camp = best.camp
            if prev and prev.key == camp.key then
                -- The same camp again: one longer step, not two rows.
                prev.high = stepHigh
                prev.camp.maxLevel = stepHigh
                for _, mob in ipairs(best.mobs) do
                    local known = false
                    for _, each in ipairs(prev.mobs) do if each.name == mob.name then known = true end end
                    if not known then prev.mobs[#prev.mobs + 1] = mob end
                end
                prev.xp, prev.gold = math.max(prev.xp, best.xp), math.max(prev.gold, best.gold)
                low = stepHigh
            else
            local stepLow = from or low
            from = nil
            local step = {
                low = stepLow, high = stepHigh, zone = camp.zone, location = camp.location,
                label = camp.label or ns.Spots.Show(camp.zone), key = camp.key,
                mobs = best.mobs, real = best.real, estimate = best.estimate, xp = best.xp, gold = best.gold,
                herbs = best.herbs, skinnable = best.skinnable, leathers = best.leathers, kills = best.kills,
                both = GrindTo60.SideOf(camp.zone) == "both", cloth = best.cloth,
            }
            step.camp = { zone = camp.zone, label = step.label, location = camp.location, coords = camp.coords,
                mobs = best.mobs, minLevel = stepLow, maxLevel = stepHigh }
            plan.steps[#plan.steps + 1] = step
            prev = step
            low = stepHigh
            end
        end
    end

    -- Elites near: an elite you met at the same place or close by.
    local elites = ns.db and type(ns.db.grindElites) == "table" and ns.db.grindElites or {}
    if next(elites) then
        for _, step in ipairs(plan.steps) do
            for _, camp in ipairs(camps) do
                if camp.zone == step.zone and (camp.key == step.key or (camp.coords and step.camp.coords
                    and Distance(camp.coords, step.camp.coords) <= ns.Grinding.NEAR * 1.5)) then
                    for _, mob in ipairs(camp.mobs) do
                        if elites[mob.name] then step.elites = true end
                    end
                end
            end
        end
    end

    -- Dots compare the steps on this path; a step's XP is against what its
    -- levels need, so later steps don't win by being later.
    local xps, golds = {}, {}
    for _, step in ipairs(plan.steps) do
        xps[#xps + 1] = step.xp
        golds[#golds + 1] = step.gold
    end
    local manyCut = {}
    for _, step in ipairs(plan.steps) do manyCut[#manyCut + 1] = #step.mobs end
    table.sort(manyCut)
    local many = manyCut[math.max(1, math.ceil(#manyCut * 0.6))] or 99

    for index, step in ipairs(plan.steps) do
        step.xpDots = Dots(step.xp, xps)
        step.goldDots = Dots(step.gold, golds)
        step.done = level >= step.high
        if not plan.current and not step.done then
            plan.current = index
            step.current = true
        end
        step.reasons = {}
        if #step.mobs >= math.max(many, GrindTo60.MANY) then step.reasons[#step.reasons + 1] = REASONS.many end
        if step.cloth then step.reasons[#step.reasons + 1] = REASONS.cloth end
        if #step.herbs > 0 then step.reasons[#step.reasons + 1] = REASONS.herbs end
        if #step.skinnable > 0 then step.reasons[#step.reasons + 1] = REASONS.skins end
        step.drops = self:GoodDrops(step.mobs, kept)
    end
    plan.empty = #plan.steps == 0 or (not plan.top and not plan.current)

    self.plan, self.planStamp = plan, stamp
    return plan
end

--- Up to four items worth having from `mobs`, best first. Names only.
function GrindTo60:GoodDrops(mobs, kept)
    local best = {}
    for _, mob in ipairs(mobs) do
        for name, chance in pairs(mob.drops or {}) do
            local item = ns.DB:GetItem(name)
            local price = kept.price and kept.price[name]
            if price == nil then
                local ok, value = pcall(ns.Value.UnitPrice, ns.Value, item and item.id)
                price = ok and type(value) == "number" and value or 0
                kept.price = kept.price or {}
                kept.price[name] = price
            end
            local score = price * math.max(1, tonumber(chance) or 1)
            if not best[name] or score > best[name] then best[name] = score end
        end
    end
    local list = {}
    for name, score in pairs(best) do
        if score > 0 then list[#list + 1] = { name = name, score = score } end
    end
    table.sort(list, function(a, b)
        if a.score ~= b.score then return a.score > b.score end
        return a.name < b.name
    end)
    local out = {}
    for index = 1, math.min(4, #list) do out[index] = list[index].name end
    return out
end

--- About how long the rest of `step` takes at your usual pace, in
--- seconds, or nil while Farmer doesn't know your pace.
function GrindTo60.Seconds(step, level)
    local XP = ns.XP
    if not (XP and type(step) == "table") then return nil end
    local ok, rate = pcall(XP.UsualRate, XP)
    if not ok or not rate then
        local okRate, now = pcall(XP.Rate, XP)
        rate = okRate and now or nil
    end
    if type(rate) ~= "number" or rate <= 0 then return nil end
    local need = 0
    for each = math.max(step.low, level or step.low), step.high - 1 do
        need = need + (XP.Needed(each) or XP.TABLE[each] or 0)
    end
    if need <= 0 then return nil end
    return need / rate * 3600
end

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------

function GrindTo60:OnEnable()
    -- A level up or a zone change redraws the Grind tab (UI/Grinding.lua)
    -- and the stamp moves with the level; nothing else here runs.
end
